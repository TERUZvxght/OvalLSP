#!/usr/bin/env ruby
# frozen_string_literal: true

# One line saying what CI last said about this branch.
#
# 024.284: preflight's checks are the Ruby suites and the tree checks, so
# a green preflight is a statement about the Core -- it runs nothing under
# `vscode/`, and it cannot see the `spec/meta` examples that refuse a
# partial tree, because a local clone is never partial. 024.281 and
# 024.282 survived a week because every local signal said the tree was
# fine while CI had been red since the push that made it so.
#
# This **reports**; it does not gate. It exits 0 always, including when it
# cannot answer, because the two ordinary ways it fails to answer -- no
# network and no `gh` -- say nothing about the tree. Preflight runs it
# after its verdict for the same reason: a line that could change a
# passing run into a failing one would be a tenth check, and a tenth check
# that needs the network is not one this repository wants at the front of
# every commit.
#
# **Every workflow on the commit, not the newest run.** `gh run list
# --limit 1` answers with the most recent run of *any* workflow, and this
# repository runs two on every push. 0.3.0's release branch had `CI` red
# and `Site` green, `Site` finished second, and this line read
# `release/0.3.0 success` under a green preflight while the branch's own
# suite had been failing for two commits -- 024.284's failure mode
# arriving through the door 024.284 opened. The verdict is now the worst
# of the runs that share HEAD, and it names which workflow it came from.

require "open3"
require_relative "utf8"
require_relative "repo_files"

module CiStatus
  ROOT = File.expand_path("..", __dir__)
  TIMEOUT = 8
  # A conclusion that is not a pass. `neutral` and `skipped` are not
  # here: a skipped job is how a conditional workflow reports that it had
  # nothing to do, and calling that red would teach a reader to ignore
  # this line.
  NOT_A_PASS = %w[failure cancelled timed_out action_required startup_failure stale].freeze

  module_function

  def same_commit?(run_sha, head)
    a = run_sha.to_s
    b = head.to_s
    return false if a.empty? || b.empty?

    a.start_with?(b[0, 12]) || b.start_with?(a[0, 12])
  end

  # The line, given what `gh` returned. Pure, so the decision this script
  # exists to make is testable without a network.
  def verdict_line(branch:, runs:, head:)
    return "no runs recorded for #{branch}" if runs.empty?

    on_head = runs.select { |run| same_commit?(run["headSha"], head) }
    # Nothing for HEAD means the newest commit CI has seen is an older
    # one, and every run of *that* commit is what there is to report.
    considered = on_head.empty? ? runs.select { |run| run["headSha"] == runs.first["headSha"] } : on_head
    note = on_head.empty? ? " (an older commit -- HEAD is not the run's)" : ""

    run, verdict = worst(considered)
    workflow = run["workflowName"].to_s
    "#{branch} #{verdict}#{workflow.empty? ? "" : " (#{workflow})"}#{note} -- #{run["url"]}"
  end

  # Worst first: a failure outranks a run still going, and both outrank a
  # pass. A green workflow beside a red one is not news, and a green one
  # beside an unfinished one is not a verdict.
  def worst(runs)
    failed = runs.find { |run| run["status"] == "completed" && NOT_A_PASS.include?(run["conclusion"].to_s) }
    return [failed, failed["conclusion"].to_s] if failed

    unfinished = runs.find { |run| run["status"] != "completed" }
    return [unfinished, unfinished["status"].to_s.tr("_", " ")] if unfinished

    [runs.first, runs.first["conclusion"].to_s]
  end

  def say(text)
    puts "ci: #{text}"
    exit 0
  end

  def current_branch
    out = RepoFiles.capture(ROOT, %w[rev-parse --abbrev-ref HEAD])
    $?.success? ? out.strip : nil
  rescue SystemCallError
    # Contained: no branch name means the question cannot be asked, and
    # the caller reports exactly that rather than a verdict.
    nil
  end

  # 20 rather than 1: enough to hold every workflow of the last few
  # pushes, which is what makes "every workflow on this commit" a
  # question this can answer at all.
  def fetch_runs(branch)
    Open3.popen3(
      "gh", "run", "list", "--branch", branch, "--limit", "20",
      "--json", "status,conclusion,displayTitle,headSha,url,workflowName"
    ) do |stdin, stdout, stderr, wait|
      stdin.close
      unless wait.join(TIMEOUT)
        Process.kill("TERM", wait.pid)
        wait.join
        next ["", "timed out after #{TIMEOUT}s", nil]
      end
      [stdout.read.force_encoding(Encoding::UTF_8), stderr.read.force_encoding(Encoding::UTF_8), wait.value]
    end
  rescue Errno::ENOENT
    say("cannot tell -- `gh` is not installed (see CONTRIBUTING.md)")
  rescue SystemCallError => e
    # Contained: any other failure to reach `gh` is reported as a failure
    # to reach it. No caller reads this; it is one line for a person.
    say("cannot tell -- #{e.class}")
  end

  def run
    branch = current_branch
    say("cannot tell -- not a git branch") if branch.nil? || branch.empty? || branch == "HEAD"

    out, err, status = fetch_runs(branch)
    say("cannot tell -- gh timed out after #{TIMEOUT}s") if status.nil?
    unless status.success?
      first = err.to_s.lines.first.to_s.strip
      say("cannot tell -- gh exited #{status.exitstatus}#{first.empty? ? "" : ": #{first}"}")
    end

    require "json"
    runs =
      begin
        JSON.parse(out)
      rescue JSON::ParserError, EncodingError
        # Contained: unreadable output is reported as unreadable, and the
        # encoding case is here because it is not a `ParserError`: a pipe
        # arrives as US-ASCII, so the first non-ASCII byte in a run title
        # raised past a narrower rescue on the first run of this script.
        # Answering `[]` here would print "no runs recorded", which is a
        # claim.
        say("cannot tell -- gh returned output this script could not parse")
      end

    say(verdict_line(branch: branch, runs: runs, head: RepoFiles.capture(ROOT, %w[rev-parse HEAD]).strip))
  end
end

CiStatus.run if $PROGRAM_NAME == __FILE__
