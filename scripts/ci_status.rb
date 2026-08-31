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

require "open3"
require_relative "utf8"
require_relative "repo_files"

ROOT = File.expand_path("..", __dir__)
TIMEOUT = 8

def say(text)
  puts "ci: #{text}"
  exit 0
end

branch =
  begin
    out = RepoFiles.capture(ROOT, %w[rev-parse --abbrev-ref HEAD])
    $?.success? ? out.strip : nil
  rescue SystemCallError
    # Contained: no branch name means the question cannot be asked, and
    # `say` below reports exactly that rather than a verdict.
    nil
  end
say("cannot tell -- not a git branch") if branch.nil? || branch.empty? || branch == "HEAD"

# `gh` is optional tooling, and its absence is the commonest case on a
# fresh clone. Reported, not raised.
out, err, status =
  begin
    Open3.popen3(
      "gh", "run", "list", "--branch", branch, "--limit", "1",
      "--json", "status,conclusion,displayTitle,headSha,url"
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
    # Answering
    # `[]` here would print "no runs recorded", which is a claim.
    say("cannot tell -- gh returned output this script could not parse")
  end
say("no runs recorded for #{branch}") if runs.empty?

run = runs.first
head = RepoFiles.capture(ROOT, %w[rev-parse HEAD]).strip
same = run["headSha"].to_s.start_with?(head[0, 12].to_s) || head.start_with?(run["headSha"].to_s[0, 12])
verdict =
  if run["status"] != "completed"
    run["status"].to_s.tr("_", " ")
  else
    run["conclusion"].to_s
  end
say("#{branch} #{verdict}#{same ? "" : " (an older commit -- HEAD is not the run's)"} -- #{run["url"]}")
