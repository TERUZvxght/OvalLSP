#!/usr/bin/env ruby
# frozen_string_literal: true

# Reverse-applies each behavioural hunk of a change set on its own and
# runs the suite, so a line no test fails on is found by a machine
# instead of by a reviewer. CLAUDE.md calls that an unpinned behavioural
# line and a defect in its own right.
#
#   ruby scripts/hunk_sweep.rb [base-ref]        # default: main
#
# **This existed only in whichever session was running it**, rebuilt from
# memory each release, which is exactly the state `corpus_diagnostics.rb`
# was written to end. Two consequences it had: 0.2.7's recorded sweep
# figures did not reproduce when a reviewer re-ran them (5 pinned against
# 6, "two comment-only" against one), and one reviewer contaminated a
# result by mutating the same worktree while a sweep was running it --
# the rule against that is in CLAUDE.md and had nothing to enforce it.
#
# Two things are reported, not one:
#
# - **hunks**: reverse-apply each, run the suite. Green means nothing
#   fails on that line.
# - **spec files added by the change set**: delete each, run the suite.
#   Green means the file pins nothing that the rest of the suite does not
#   already pin -- an example that could be deleted for free. That is the
#   other half of "an assertion that cannot fail", and no sweep before
#   this one looked for it.
#
# The tree must be clean and no other sweep may be running: both are
# refused rather than warned about, because a contaminated sweep reports
# a number that reads exactly like a real one.
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
LOCK = File.join(Dir.tmpdir, "ovallsp-hunk-sweep.lock")

def run(*command, chdir: ROOT)
  stdout, status = Open3.capture2e(*command, chdir: chdir)
  [stdout, status.success?]
end

def refuse(message)
  warn "hunk_sweep: #{message}"
  exit 1
end

def suite_result
  output, = run("bundle", "exec", "rspec", "--no-color", "--fail-fast", chdir: File.join(ROOT, "core"))
  line = output.lines.reverse.find { |l| l.match?(/^\d+ examples?,/) }
  return [:errored, "the suite did not run to a count"] unless line

  [line.include?(" 0 failures") ? :green : :red, line.strip]
end

def hunks_of(diff)
  diff.split(/(?m)^(?=diff --git )/).reject { |part| part.strip.empty? }.flat_map do |file|
    lines = file.lines
    first = lines.index { |l| l.start_with?("@@") }
    next [] unless first

    header = lines[0...first].join
    file[header.length..].split(/(?m)^(?=@@ )/).reject { |h| h.strip.empty? }.map { |h| header + h }
  end
end

# A hunk that only adds or removes comment and blank lines cannot change
# behaviour, so it is reported as such rather than counted as unpinned --
# 0.2.7's record called one hunk comment-only and meant two, and the
# difference is the whole reading of the number.
def comment_only?(hunk)
  hunk.lines.select { |l| l.match?(/\A[+-][^+-]/) || l.match?(/\A[+-]\z/) }
      .all? { |l| l[1..].to_s.strip.empty? || l[1..].to_s.lstrip.start_with?("#", "//") }
end

base = ARGV[0] || "main"

status, = run("git", "status", "--porcelain")
refuse("the working tree is not clean. A sweep rewrites it; commit or stash first.") unless status.strip.empty?
refuse("another sweep is running (#{LOCK}). Sequence them -- concurrent mutation invalidates both.") if File.exist?(LOCK)

File.write(LOCK, Process.pid.to_s)
at_exit { File.delete(LOCK) if File.exist?(LOCK) && File.read(LOCK) == Process.pid.to_s }

diff, ok = run("git", "diff", "#{base}...HEAD", "-U3", "--", "core/lib")
refuse("could not diff against #{base}") unless ok
hunks = hunks_of(diff)

added_specs, = run("git", "diff", "--name-only", "--diff-filter=A", "#{base}...HEAD", "--", "core/spec")
added_specs = added_specs.split("\n").select { |f| f.end_with?("_spec.rb") }

puts "hunk_sweep: #{hunks.length} hunk(s) over core/lib, #{added_specs.length} spec file(s) added, against #{base}"
puts

pinned = unpinned = commentary = 0
Dir.mktmpdir do |scratch|
  hunks.each_with_index do |hunk, index|
    label = format("h%02d", index + 1)
    path = File.join(scratch, "#{label}.diff")
    File.write(path, hunk)

    if comment_only?(hunk)
      commentary += 1
      puts "#{label}  comment-only (no behaviour to pin)"
      next
    end

    _, can_revert = run("git", "apply", "-R", "--check", path)
    unless can_revert
      puts "#{label}  cannot revert alone (depends on another hunk)"
      next
    end

    run("git", "apply", "-R", path)
    verdict, detail = suite_result
    run("git", "apply", path)

    case verdict
    when :green then unpinned += 1
    else pinned += 1
    end
    puts "#{label}  #{verdict == :green ? 'UNPINNED' : 'pinned  '}  #{detail}"
  end

  added_specs.each do |spec|
    contents = File.read(File.join(ROOT, spec))
    File.delete(File.join(ROOT, spec))
    verdict, detail = suite_result
    File.write(File.join(ROOT, spec), contents)

    puts "#{verdict == :green ? 'PINS NOTHING' : 'pins        '}  #{spec}  #{detail}"
  end
end

puts
puts "hunk_sweep: #{pinned} pinned, #{unpinned} unpinned, #{commentary} comment-only"
puts "An unpinned behavioural line is a defect in its own right (CLAUDE.md)." if unpinned.positive?
