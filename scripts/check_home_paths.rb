#!/usr/bin/env ruby
# frozen_string_literal: true

# One scanner for "a real home directory path was committed", read by
# both of the places that have to agree about it:
#
#   * `core/spec/meta/home_path_guard_spec.rb` scans tracked file
#     content with it, on every suite run;
#   * ci.yml's secret-scan job runs `--messages` with it, over commit
#     messages -- the channel a tree scan cannot see, and half of how
#     0.2.3 leaked one.
#
# Deliberately one implementation rather than a Ruby matcher beside a
# shell `grep`: two scanners that must agree about the same text is the
# defect 0.2.1 spent a countermeasure on (`#structural_tokens`), and this
# would have been the same shape.
#
# Usage:
#   ruby scripts/check_home_paths.rb --tree
#   ruby scripts/check_home_paths.rb --messages
module HomePaths
  ROOT = File.expand_path("..", __dir__)

  # A segment counts as a username only if it has at least one
  # alphanumeric character, so prose writing an ellipsis after the prefix
  # to describe the class -- including this file -- does not trip it.
  #
  # Both separators, so Windows' `C:\\Users\\name` is caught -- it was not
  # matched at all before, and it costs nothing to add.
  #
  # **Case-sensitive, deliberately, and this was measured rather than
  # assumed.** An audit pointed out that macOS' filesystem is
  # case-insensitive, so the all-lowercase spelling of a home path
  # reaches the same directory as the real one and slips past. Adding
  # `/i` does catch that -- and
  # flags 37 lines in this repository, because `app/views/users/...` is
  # ordinary Rails and appears throughout the specs and the design docs.
  # A check that cries wolf 37 times is a check people switch off, and
  # the case it buys is a tool that lowercases a path prefix, which
  # nothing here does. The real form is what is matched; the theoretical
  # one is recorded here instead of being defended against at that price.
  PATTERN = %r{[/\\](?:Users|home)[/\\](?=[A-Za-z0-9._-]*[A-Za-z0-9])([A-Za-z0-9._-]+)}

  # Synthetic, or unambiguously a CI machine rather than a person's.
  # Adding one is meant to be a deliberate edit with a reason: an unknown
  # name fails rather than being quietly tolerated.
  SYNTHETIC = %w[
    example
    exampleuser
    dev
    rhc
    runner
    runneradmin
  ].freeze

  NUL = "\0"

  module_function

  def names_in(text)
    text.scan(PATTERN).flatten.reject { |name| SYNTHETIC.include?(name) }
  end

  # Backticks hand back a string tagged with the *shell's* external
  # encoding, which is US-ASCII whenever LANG is unset -- so this repo's
  # Japanese commit messages raise on the first `split` under a bare
  # local shell while passing in CI's UTF-8 locale. Reading the bytes as
  # UTF-8 and scrubbing what is not valid makes the answer independent of
  # the environment the check happens to run in.
  def as_utf8(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  def tracked_files
    Dir.chdir(ROOT) { as_utf8(`git ls-files -z`).split(NUL) }
  end

  # Every file this scanner declined to read, and why. A skip is a file
  # the check could not clear, and until 0.2.5 both skips returned an
  # empty list silently -- indistinguishable, in the answer, from a file
  # that was read and found clean. It still skips them; it no longer does
  # so without saying.
  def skipped_files
    @skipped_files ||= []
  end

  def offences_in_file(relative_path)
    absolute = File.join(ROOT, relative_path)
    return [] unless File.file?(absolute)

    content = File.binread(absolute)
    # Compiled artefacts embed build-time paths that are not authored
    # content; make-final-review-bundle.sh inspects those instead, with
    # otool beside it.
    if content.include?(NUL)
      skipped_files << { path: relative_path, reason: :binary }
      return []
    end

    content.force_encoding(Encoding::UTF_8)
    unless content.valid_encoding?
      skipped_files << { path: relative_path, reason: :invalid_encoding }
      return []
    end

    content.lines.each_with_index.flat_map do |line, index|
      names_in(line).map { |name| "#{relative_path}:#{index + 1}: #{name}" }
    end
  end

  def tree_offences
    skipped_files.clear
    tracked_files.flat_map { |path| offences_in_file(path) }
  end

  def shallow?
    Dir.chdir(ROOT) { `git rev-parse --is-shallow-repository`.strip == "true" }
  end

  # `actions/checkout` fetches a single commit by default, and this mode
  # would then scan that one commit and report the whole history clean --
  # green because it did not run, which is the failure CLAUDE.md already
  # spends a section on. Refusing is the only honest answer; the
  # secret-scan job that runs this sets `fetch-depth: 0` for gitleaks
  # anyway, and `ci_skip_guard_spec.rb` pins that it still does.
  def message_offences
    raise "refusing to scan commit messages in a shallow clone -- fetch the full history (fetch-depth: 0)" if shallow?

    marker = "@@commit@@"
    log = Dir.chdir(ROOT) { as_utf8(`git log --all --format=#{marker}%H%n%B`) }

    log.split(marker).reject { |entry| entry.strip.empty? }.flat_map do |entry|
      sha, body = entry.split("\n", 2)
      names_in(body.to_s).map { |name| "#{sha.to_s[0, 12]}: #{name}" }
    end.uniq
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV[0]

  offences =
    case mode
    when "--tree"     then HomePaths.tree_offences
    when "--messages" then HomePaths.message_offences
    else
      warn "usage: check_home_paths.rb --tree|--messages"
      exit 2
    end

  if offences.empty?
    skipped = HomePaths.skipped_files
    unless skipped.empty?
      # Printed rather than swallowed: a clean answer that rests on
      # declining to read 40 files is a different claim from one that read
      # them all.
      puts "check-home-paths #{mode}: skipped #{skipped.size} unreadable file(s): " \
           "#{skipped.map { |e| "#{e[:path]} (#{e[:reason]})" }.join(', ')}"
    end
    puts "check-home-paths #{mode}: clean"
    exit 0
  end

  warn "A real home directory path is committed (#{mode}):"
  offences.each { |offence| warn "  #{offence}" }
  warn ""
  warn "Write $HOME, ~, or a description instead. If the name is genuinely"
  warn "synthetic, add it to SYNTHETIC in scripts/check_home_paths.rb and say why."
  exit 1
end
