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

# Forced to UTF-8: a diff of this tree carries Japanese comments, and
# `Open3` hands back ASCII-8BIT, which makes every regex against it raise
# `invalid byte sequence in US-ASCII`. Found by running this script on
# the change set that introduced it -- which is the only way this kind of
# thing is found, and the reason the script is in the tree rather than
# rebuilt from memory each release.
def run(*command, chdir: ROOT)
  stdout, status = Open3.capture2e(*command, chdir: chdir)
  [stdout.force_encoding(Encoding::UTF_8), status.success?]
end

def refuse(message)
  warn "hunk_sweep: #{message}"
  exit 1
end

# Two meta specs assert things about the tree's own bookkeeping rather
# than about behaviour, and both go red for any change a sweep makes:
# `documented_counts_spec` compares the example count against three
# documents, so **deleting any spec file turns the suite red for that
# reason alone**, and `measured_claims_spec` recomputes the `Mutex.new`
# count, so any hunk that adds or removes one does the same.
#
# Excluded, because otherwise this instrument reports "pinned" and "pins
# something" for reasons that have nothing to do with what it is
# measuring. Found by a review round, which measured that the spec-file
# half **could never** report its own negative verdict -- the half this
# script's header advertises as the thing no sweep here had looked for.
# A check that cannot fail is the defect this whole exercise is about,
# and it was in the instrument built to find it.
BOOKKEEPING_SPECS = %w[
  spec/meta/documented_counts_spec.rb
  spec/meta/measured_claims_spec.rb
].freeze

def suite_result
  command = ["bundle", "exec", "rspec", "--no-color", "--fail-fast"]
  BOOKKEEPING_SPECS.each { |spec| command.push("--exclude-pattern", spec) }
  output, = run(*command, chdir: File.join(ROOT, "core"))
  line = output.lines.reverse.find { |l| l.match?(/^\d+ examples?,/) }
  return [:errored, "the suite did not run to a count"] unless line

  # An errored run is not a green one. `0 examples, 0 failures, 1 error
  # occurred outside of examples` contains " 0 failures" and was read as
  # green -- so a hunk whose reversal breaks *loading* was reported
  # UNPINNED, which is the opposite of the truth and the most load-bearing
  # kind of line there is. Found by this script on its second real run,
  # against the change set that adds a `require_relative`.
  # RSpec pluralises: two load errors print "2 errors occurred outside of
  # examples", which the singular substring does not match -- and if any
  # example ran, the line still contains " 0 failures" and the hunk is
  # reported UNPINNED. Reverting a `require_relative` used by two spec
  # files is enough to reach it. The check written for exactly this
  # failure mode had it; a review round found that on the release whose
  # stated lesson is that a check gets a round aimed at whether it can
  # fail at all.
  return [:errored, line.strip] if line.match?(/\d+ errors? occurred outside of examples/)
  return [:errored, "the suite ran no examples"] if line.start_with?("0 examples")

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
at_exit do
  File.delete(LOCK) if File.exist?(LOCK) && File.read(LOCK) == Process.pid.to_s
  # Ctrl-C mid-hunk otherwise leaves a reverted hunk behind -- and a
  # reverted hunk is not inert: a review round found this checkout with
  # one line of `parser_service.rb` reverse-applied, which made
  # `#summarize` raise on **any file containing an `alias` keyword**. At
  # minutes per suite run and dozens of hunks, an interrupted sweep is
  # the likely case rather than the exception, so it restores rather than
  # warns.
  dirty, = run("git", "status", "--porcelain")
  unless dirty.strip.empty?
    warn("hunk_sweep: interrupted with the tree modified -- restoring core/ and vscode/.")
    run("git", "checkout", "--", "core", "vscode")
  end
end

diff, ok = run("git", "diff", "#{base}...HEAD", "-U3", "--", "core/lib")
refuse("could not diff against #{base}") unless ok
hunks = hunks_of(diff)

added_specs, = run("git", "diff", "--name-only", "--diff-filter=A", "#{base}...HEAD", "--", "core/spec")
added_specs = added_specs.split("\n").select { |f| f.end_with?("_spec.rb") }

puts "hunk_sweep: #{hunks.length} hunk(s) over core/lib, #{added_specs.length} spec file(s) added, against #{base}"
puts "hunk_sweep: `vscode/src` is not swept -- its suite is separate and this only drives rspec."
puts

pinned = unpinned = commentary = entangled = errored = 0
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
      entangled += 1
      puts "#{label}  cannot revert alone (depends on another hunk)"
      next
    end

    _, reverted = run("git", "apply", "-R", path)
    refuse("#{label}: could not reverse-apply after its own check said it could") unless reverted

    verdict, detail = suite_result

    _, restored = run("git", "apply", path)
    # A restore that fails silently contaminates every later verdict, and
    # this script's own header calls a contaminated sweep the thing that
    # "reports a number that reads exactly like a real one". It was the
    # one contamination path the script did not check.
    refuse("#{label}: could not restore the hunk. The tree is now wrong -- `git checkout core/lib`.") unless restored

    case verdict
    when :green then unpinned += 1
    when :errored then errored += 1
    else pinned += 1
    end
    label_for = { green: "UNPINNED", errored: "load-bearing (the suite could not run)" }.fetch(verdict, "pinned  ")
    puts "#{label}  #{label_for}  #{detail}"
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
accounted = pinned + unpinned + commentary + entangled + errored
puts "hunk_sweep: #{pinned} pinned, #{unpinned} unpinned, #{commentary} comment-only, " \
     "#{entangled} not separable, #{errored} load-bearing " \
     "(#{accounted} of #{hunks.length} accounted for)"
puts "An unpinned behavioural line is a defect in its own right (CLAUDE.md)." if unpinned.positive?
