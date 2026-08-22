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

def fail_with(message)
  warn("check-pinned-mutations: #{message}")
  exit 1
end

# `--verify-only` checks the manifest without touching a file: every `from`
# matches exactly once, and every named example exists and is selected
# uniquely. That half is safe to run inside the ordinary suite. Applying the
# mutations is not -- it writes to `core/lib`, and an interrupted rspec would
# leave the tree wrong -- so it is a CI job of its own.
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
  # `core/lib` was the whole scope until 0.2.14. Round 2's method was to
  # take a guarantee and try to make it false with the suite green, and
  # it succeeded against nearly every check in `scripts/` -- because the
  # manifest that exists to ask "does this example fail when the decision
  # it names is inverted" could not name a decision in a check.
  #
  # `scripts/` is added, and nothing else: the applier writes to the real
  # file and restores it, which is safe for a script a spec shells out
  # to, and is *not* safe for a spec file, where mutating the source
  # could delete the example being run. A decision inside a spec is
  # pinned by a second example, not by this.
  unless entry["file"].start_with?("core/lib/", "scripts/")
    fail_with("entry #{i + 1}: #{entry["file"]} is under neither core/lib nor scripts -- " \
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
    File.write(source, original.sub(entry["from"], entry["to"]))

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

if failures.empty?
  puts "check-pinned-mutations: #{entries.length} mutation(s), every one caught by the example that names it."
  exit 0
end

warn("check-pinned-mutations: #{failures.length} of #{entries.length} mutation(s) not caught:")
failures.each { |f| warn("  - #{f}") }
exit 1
