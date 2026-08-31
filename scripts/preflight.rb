#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Everything that must be true before a commit, in one command, so that
# "did I run it all?" stops being answered from memory.
#
#   ruby scripts/preflight.rb              # run every check
#   ruby scripts/preflight.rb --install    # install it as a git pre-commit hook
#   ruby scripts/preflight.rb --list       # print the checks and exit
#
# `046`'s C9. Twice in the 0.2.13 session a commit was made on a partial
# run: the suite had been run for one directory, it was green, and the
# full run afterwards was not. Both times the tree was already pushed.
# Neither was carelessness in a form more care would fix -- the checks
# were scattered and the only thing holding the list together was a
# person remembering it.
#
# **The count is not written here, deliberately.** It was, and it was
# wrong: this comment said "six places (the suite, three scripts, a git
# state, a derived number)" while the file ran two rspec invocations and
# six scripts and had no git-state check at all, and it drifted inside
# the release that added a check to the list. Three other documents
# stated three different numbers (`024.195`). `CHECKS` below is the list;
# `--list` prints it.
#
# Two rules this follows, both learned the hard way:
#
# - **A check that is skipped is reported, never assumed passed.** The
#   real-Rails and capability suites skip in full without local `rails`
#   and `sqlite3`, and `rspec` still exits 0 -- so a green local run can
#   mean the suite that decides whether a capability row is true never
#   executed. This prints the example count and fails on zero.
# - **It says what it ran.** The output is the evidence, so a commit
#   message can quote a run rather than a recollection.

require "open3"
require "json"
require_relative "check_suites_ran"

ROOT = File.expand_path("..", __dir__)
CORE = File.join(ROOT, "core")

Check = Struct.new(:name, :why, :dir, :command, :expect, keyword_init: true)

# `expect` is an optional lambda over the combined output; it returns a
# string when the check passed its exit status but failed on what it
# said. That is the "green because it did not run" case, and an exit
# status cannot see it.
NON_EMPTY_SUITE = lambda do |out|
  count = out[/^(\d+) examples?,/, 1]
  return "rspec reported no example count" if count.nil?
  return "0 examples ran -- the suite skipped rather than executed" if count == "0"

  nil
end

# `024.148`. The count above is not enough on its own and this is the
# check that needs more: a **skipped example is still an example**, so a
# suite that skipped in full reports every one of its examples as
# pending, zero failures, and exit 0 -- which satisfies any count-based
# rule. The first version of this file had only the count, and therefore
# could not fail in the one case it existed for -- found by review round
# 1.
#
# No example figure is quoted here. `024.196`: one was, in three places,
# attributed to a different file each time and matching none of them by
# the release that found it -- this comment named `real_rails_spec.rb`
# for a figure belonging to the e2e suite, while the entry it cites as
# its authority gives that file's real count. A suite's size is a number
# about this tree; the shape is what the argument rests on.
#
# `scripts/check_suites_ran.rb` reads the JSON formatter's per-example
# status, and is the same script ci.yml runs.
SUITES_RAN = lambda do |_out|
  report_path = File.join(CORE, "tmp", "rspec.json")
  return "no #{report_path} -- the run did not produce a JSON report" unless File.file?(report_path)

  complaints = CheckSuitesRan.complaints(JSON.parse(File.read(report_path, encoding: "UTF-8")))
  complaints.empty? ? nil : complaints.join("\n    ")
end

CHECKS = [
  # First, and it takes under a second: `--dry-run` loads every spec file
  # and counts without running one. This is the check that went stale
  # four times in a single 0.2.14 session -- every commit adding an
  # example makes it false -- and discovering that eight minutes into a
  # suite run is the whole reason it is at the top.
  Check.new(
    name: "documented example counts current",
    why: "three documents state the count; a stale one is caught here instead of at the end of the suite",
    dir: ROOT, command: %w[ruby scripts/documented_counts.rb --check]
  ),
  Check.new(
    name: "full suite",
    why: "the whole thing, not the directory you were working in",
    dir: CORE, command: %w[bundle exec rspec --order random], expect: NON_EMPTY_SUITE
  ),
  Check.new(
    name: "environment-dependent suites actually ran",
    why: "without local rails/sqlite3/node_modules these skip in full and rspec still exits 0",
    dir: CORE,
    command: %w[bundle exec rspec spec/integration/real_rails_spec.rb spec/e2e/capabilities_spec.rb
                spec/meta/client_behaviour_spec.rb --format json --out tmp/rspec.json --format progress],
    expect: SUITES_RAN
  ),
  Check.new(
    name: "no real home path in tracked content",
    why: "the repository is public; a tree scan cannot see commit messages, so --messages runs in CI",
    dir: ROOT, command: %w[ruby scripts/check_home_paths.rb --tree]
  ),
  Check.new(
    name: "every documentation path resolves",
    why: "a path resolving to nothing sends the next reader somewhere that does not exist",
    dir: ROOT, command: %w[ruby scripts/check_doc_links.rb]
  ),
  Check.new(
    name: "register index current",
    why: "the index is generated; a hand-edited one is a record nobody can search",
    dir: ROOT, command: %w[ruby scripts/reindex_findings.rb --check]
  ),
  Check.new(
    name: "every rescue in core/lib has a verdict",
    why: "catching and continuing is not the default here",
    dir: ROOT, command: %w[ruby scripts/check_swallowed_failures.rb]
  ),
  Check.new(
    name: "site links resolve",
    why: "the site is not generated from the docs and propagates nothing on its own",
    dir: ROOT, command: %w[ruby scripts/check_site_links.rb]
  ),
  Check.new(
    name: "every pasted interpreter session still reproduces",
    why: "a session is evidence only while it runs; until 0.2.16 all 69 of them were inert text",
    dir: ROOT, command: %w[ruby scripts/check_interpreter_sessions.rb]
  )
].freeze

def run_check(check)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  out, status = Open3.capture2e(*check.command, chdir: check.dir)
  # Explicit encoding, never the invoking shell's ambient locale. Under a
  # locale-less shell `capture2e` hands back US-ASCII, and the first
  # `String#[]` against output containing a Japanese failure message
  # raises `invalid byte sequence` -- so the gate that exists to catch a
  # failure would crash on one. `scripts/generate_sbom.rb` carries the
  # same fix for the same reason, found the same way (Task 023.8).
  out = out.dup.force_encoding(Encoding::UTF_8)
  out = out.scrub("?") unless out.valid_encoding?
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)

  complaint = status.success? ? check.expect&.call(out) : "exited #{status.exitstatus}"
  [complaint, out, elapsed]
end

HOOK = <<~SH
  #!/bin/sh
  # Installed by `ruby scripts/preflight.rb --install`.
  # Skip a single commit with: PREFLIGHT_SKIP=1 git commit ...
  [ -n "$PREFLIGHT_SKIP" ] && exit 0
  exec ruby "$(git rev-parse --show-toplevel)/scripts/preflight.rb"
SH

if ARGV.include?("--list")
  CHECKS.each { |c| puts "#{c.name}\n    #{c.why}\n    #{c.command.join(' ')}  (in #{c.dir == CORE ? 'core/' : '.'})" }
  exit 0
end

if ARGV.include?("--install")
  hooks = IO.popen(%w[git rev-parse --git-path hooks], chdir: ROOT, &:read).strip
  hooks = File.expand_path(hooks, ROOT)
  path = File.join(hooks, "pre-commit")
  if File.exist?(path) && File.read(path) != HOOK
    warn "preflight: #{path} already exists and is not this hook. Not overwriting it."
    warn "preflight: add `exec ruby scripts/preflight.rb` to it yourself, or move it aside."
    exit 1
  end
  require "fileutils"
  FileUtils.mkdir_p(hooks)
  File.write(path, HOOK)
  File.chmod(0o755, path)
  puts "preflight: installed #{path}."
  puts "preflight: skip one commit with PREFLIGHT_SKIP=1."
  exit 0
end


# 024.284: a green preflight is a statement about the Core. It runs
# nothing under `vscode/`, and it cannot see the `spec/meta` examples
# that refuse a partial tree -- which is why 024.281 and 024.282 stayed
# red for a week while every local signal said the tree was fine.
#
# So: report, do not gate. This runs *after* the verdict and cannot
# change it. It is deliberately not a tenth `Check` -- it needs the
# network, and a check that needs the network at the front of every
# commit is not one this repository wants. `--list` therefore does not
# print it, and "all N checks passed" stays true about the N checks.
def report_ci_status(root)
  system("ruby", File.join(root, "scripts", "ci_status.rb"))
end

failures = []
CHECKS.each do |check|
  print "preflight: #{check.name}... "
  $stdout.flush
  complaint, out, elapsed = run_check(check)
  if complaint
    puts "FAILED (#{elapsed}s)"
    failures << [check, complaint, out]
  else
    summary = out[/^\d+ examples?, \d+ failures?[^\n]*/]
    puts "ok (#{elapsed}s)#{summary ? " -- #{summary}" : ""}"
  end
end

if failures.empty?
  puts "preflight: all #{CHECKS.length} checks passed."
  report_ci_status(ROOT)
  exit 0
end

# stdout carries the running "ok"/"FAILED" lines and stderr carries the
# report; without this the report interleaves into the middle of them and
# the summary reads as if it came before the last check.
$stdout.flush

failures.each do |check, complaint, out|
  warn "\n=== #{check.name}: #{complaint} ==="
  warn "    why it is here: #{check.why}"
  warn out.lines.last(30).join
end
warn "\npreflight: #{failures.length} of #{CHECKS.length} checks failed."
$stderr.flush
report_ci_status(ROOT)
exit 1
