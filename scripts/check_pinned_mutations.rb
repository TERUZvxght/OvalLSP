#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# `042`'s D7. An example that claims to distinguish two behaviours names
# the mutation it claims to catch, and this applies that mutation and
# requires the example to fail.
#
# The hunk sweep asks "does *anything* fail when this line is reverted".
# This asks "does *this example* fail when the decision it names is
# inverted" -- which is the question a comment saying "an implementation
# that did X would fail this example" is making a claim about, and which
# nothing checked. 0.2.11's third round found such a comment attached to
# an example that passed under exactly the X it named.
#
# **The mutation is applied to the real file and restored.** A copy on the
# load path does not work: the Gemfile has a `gemspec`, so Bundler puts
# the real `core/lib` at the *front* of `$LOAD_PATH`, ahead of anything
# `-I` adds -- the first version of this script did that and reported all
# four mutations uncaught, because every run had loaded the unmutated
# code. Worth recording: a checker that cannot see the thing it checks
# reports the same "not caught" as a checker that works.
#
# So the file is written, the one example is run, and the original bytes
# are put back -- in an `ensure`, and again from `at_exit`, and the
# restoration is verified by comparing bytes before the next entry runs.
# Nothing is ever deleted. Do not run this while anything else is
# mutating the tree, for the reason `CLAUDE.md` gives for the hunk sweep.

require "fileutils"
require "shellwords"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
CORE = File.join(ROOT, "core")
MANIFEST = File.join(CORE, "spec", "meta", "pinned_mutations.yml")

# The roots a mutation may name, in one place.
#
# `core/lib` was the whole scope until 0.2.14. Round 2's method was to
# take a guarantee and try to make it false with the suite green, and it
# succeeded against nearly every check in `scripts/` -- because the
# manifest that exists to ask "does this example fail when the decision
# it names is inverted" could not name a decision in a check.
#
# `scripts/` is added, and nothing else: the applier writes to the real
# file and restores it, which is safe for a script a spec shells out to,
# and is *not* safe for a spec file, where mutating the source could
# delete the example being run. A decision inside a spec is pinned by a
# second example, not by this.
#
# One list, because there were three: this constant's predecessor was a
# literal argument list, the refusal below spelled the roots again in
# prose, and the manifest's header spelled them a third time -- and that
# third copy said `core/lib` alone for the whole of 0.2.14, having gone
# stale in the same commit that added the `scripts/` entries (`024.212`).
# The refusal now reads the list, and the manifest header points here
# rather than repeating it.
ACCEPTED_ROOTS = %w[core/lib/ scripts/].freeze

def fail_with(message)
  warn("check-pinned-mutations: #{message}")
  exit 1
end

# `--verify-only` checks the manifest without touching a file: every `from`
# matches exactly once, and every named example exists and is selected
# uniquely. That half is safe to run inside the ordinary suite. Applying the
# mutations is not -- it writes into the tracked file each entry names, and an
# interrupted rspec would leave the tree wrong -- so it is a CI job of its own.
# What each mode may then claim is at the bottom of this file.
verify_only = ARGV.include?("--verify-only")

entries = YAML.safe_load(File.read(MANIFEST, encoding: "UTF-8"))
fail_with("#{MANIFEST} is empty") if entries.nil? || entries.empty?

failures = []

entries.each_with_index do |entry, i|
  label = entry["why"].to_s.strip.split("\n").first.to_s[0, 70]
  %w[why file from spec example].each do |key|
    fail_with("entry #{i + 1} has no `#{key}`") if entry[key].nil? || entry[key].to_s.empty?
  end
  # `to` may be empty: deleting a line is a mutation, and the commonest
  # one for a guard. Nil is still an error -- that is a missing key
  # rather than a deliberate deletion.
  fail_with("entry #{i + 1} has no `to`") if entry["to"].nil?

  source = File.join(ROOT, entry["file"])
  fail_with("entry #{i + 1}: #{entry["file"]} does not exist") unless File.file?(source)
  unless entry["file"].start_with?(*ACCEPTED_ROOTS)
    fail_with("entry #{i + 1}: #{entry["file"]} is under none of #{ACCEPTED_ROOTS.join(", ")} -- " \
              "a spec file cannot be mutated here, because the mutation could remove the example")
  end

  # Read as UTF-8 explicitly: these files carry en dashes, and a
  # US-ASCII default external encoding makes `scan` raise rather than
  # not-match, which reads as a broken script instead of a missing
  # mutation.
  original = File.read(source, encoding: "UTF-8")
  occurrences = original.scan(entry["from"]).length
  if occurrences != 1
    fail_with("entry #{i + 1} (#{label}): its `from` matches #{occurrences} times in #{entry["file"]}. " \
              "A mutation has to name one place exactly, or it is not the mutation the example is about.")
  end

  if verify_only
    dry = IO.popen(["bundle", "exec", "rspec", "--dry-run", "-e", entry["example"].to_s.strip, entry["spec"]],
                   chdir: CORE, err: %i[child out], &:read)
    selected = dry[/(\d+) examples?/, 1].to_i
    if selected != 1
      failures << "#{label}\n    `#{entry["example"].to_s.strip}` selects #{selected} examples in " \
                  "#{entry["spec"]}; it must select exactly one."
    end
    next
  end

  restore = -> { File.write(source, original) if File.read(source, encoding: "UTF-8") != original }
  at_exit(&restore)

  begin
    # **Block form.** `String#sub` expands backreferences in a
    # replacement *string* -- `\0`, `\1`, `\&`, and a backslash-backtick
    # meaning everything before the match. `to` is author-supplied YAML,
    # so whether any of them bites is a property of today's manifest and
    # not of this code. The block form expands nothing, and costs two
    # characters. `024.225`, whose instance took a tracked document from
    # 11,555 lines to 25,878 twice.
    File.write(source, original.sub(entry["from"]) { entry["to"] })

    command = ["bundle", "exec", "rspec", "-e", entry["example"].to_s.strip, entry["spec"]]
    output = IO.popen(command, chdir: CORE, err: %i[child out], &:read)
    status = $?
  ensure
    restore.call
    if File.read(source, encoding: "UTF-8") != original
      fail_with("could not restore #{entry["file"]}. The tree is now wrong -- `git checkout #{entry["file"]}`.")
    end
  end

  count = output[/(\d+) examples?, (\d+) failures?/, 1].to_i
  fails = output[/(\d+) examples?, (\d+) failures?/, 2].to_i

  if count.zero?
    failures << "#{label}\n    `#{entry["example"].to_s.strip}` selected no example in #{entry["spec"]}."
  elsif count > 1
    failures << "#{label}\n    `#{entry["example"].to_s.strip}` selected #{count} examples; it must select one."
  elsif fails.zero? && status.success?
    failures << "#{label}\n    the example passed with the mutation applied, so it does not pin what it claims " \
                "to. #{entry["spec"]} -- `#{entry["example"].to_s.strip}`"
  else
    puts "check-pinned-mutations: pinned  #{label}"
  end
end

# Two modes, two conclusions, because they establish different things and
# only one of them ran anything against mutated source.
#
# `--verify-only` used to fall through to the applying run's sentence --
# "every one caught by the example that names it" -- after taking the
# early `next` above, so the ordinary suite emitted that claim on every
# run while writing no file and running no example to failure. It is this
# project's own "the answer that would be right if nothing had gone
# wrong", in the checker built to detect that shape, and it is what this
# script's header warns about two paragraphs in: a checker that cannot
# see the thing it checks reports what a working one reports. `024.211`.
#
# The failure branch was wrong symmetrically: in `--verify-only` a
# failure can only be a manifest that no longer selects what it names,
# never an example that survived its mutation.
if failures.empty?
  puts(if verify_only
         "check-pinned-mutations: #{entries.length} mutation(s) checked as a manifest -- every `from` matches " \
         "its file exactly once, and every named example exists and is selected uniquely. Nothing was applied " \
         "here, so nothing here says an example fails under its mutation: that is ci.yml's \"Pinned mutations\"."
       else
         "check-pinned-mutations: #{entries.length} mutation(s), every one caught by the example that names it."
       end)
  exit 0
end

warn(if verify_only
       "check-pinned-mutations: #{failures.length} of #{entries.length} mutation(s) no longer select " \
       "what they name:"
     else
       "check-pinned-mutations: #{failures.length} of #{entries.length} mutation(s) not caught:"
     end)
failures.each { |f| warn("  - #{f}") }
exit 1
