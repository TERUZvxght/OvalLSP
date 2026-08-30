#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"

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
  # Both separators, and one or two of them, so a Windows drive path, a
  # JSON-escaped solidus and a doubled slash are all caught. Each of
  # those is how the *same real path* is stored on disk by an ordinary
  # tool, and until `024.189` the pattern required exactly one separator
  # and saw none of them. The forms are described rather than spelled
  # here on purpose: this file is scanned by this pattern, so an
  # illustration written the way a real path is written is a finding
  # about the scanner (`024.126`).
  #
  # **Case-sensitive, deliberately, and the cost of the alternative is
  # re-derived rather than typed.** An audit pointed out that macOS'
  # filesystem is case-insensitive, so the all-lowercase spelling of a
  # home path reaches the same directory as the real one and slips past.
  # Adding `/i` does catch that -- and flags dozens of ordinary
  # `app/views/users/...` lines, because that is ordinary Rails and
  # appears throughout the specs and the design docs. A check that cries
  # wolf that often is a check people switch off, and the case it buys is
  # a tool that lowercases a path prefix, which nothing here does. The
  # real form is what is matched; the theoretical one is recorded here
  # instead of being defended against at that price.
  #
  # This paragraph carried a count until 0.2.16, and the count was never
  # right at any revision -- `024.192`. It is not restated here, and it is
  # not restated in the spec either: `home_path_guard_spec.rb`'s
  # "would cry wolf if it were case-insensitive" example scans this
  # tree with this pattern plus `/i` on every run and asserts a floor, so
  # the trade-off above is a live derivation rather than a number
  # somebody remembered.
  PATTERN = %r{[/\\]{1,2}(?:Users|home)[/\\]{1,2}(?=[A-Za-z0-9._-]*[A-Za-z0-9])([A-Za-z0-9._-]+)}

  # The same real path with every separator replaced by a hyphen, which
  # is how an agent scratchpad names a directory after the workspace it
  # belongs to. `024.189`: it discloses the username *and* the directory
  # layout, and this repository's task documents quote verbatim command
  # output constantly -- which is how 0.2.3 leaked one. It was not
  # hypothetical. Widening the scan found this spelling of the
  # maintainer's own home directory already committed, in an entry
  # written after `024.189` was raised, because nothing could see it.
  #
  # `Users` only, and no `home`: an English hyphenated phrase ending in
  # "home" is ordinary prose -- this file's own output strings contain
  # one -- while the capitalised form in a hyphen-joined path is not.
  # The captured name excludes the hyphen for the same reason the
  # separator is one: there is no boundary left to stop at.
  MANGLED_PATTERN = %r{-Users-(?=[A-Za-z0-9._]*[A-Za-z0-9])([A-Za-z0-9._]+)}

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

  module_function

  def names_in(text)
    (text.scan(PATTERN).flatten + text.scan(MANGLED_PATTERN).flatten)
      .reject { |name| SYNTHETIC.include?(name) }
  end

  # What this still buys is `.scrub`, and only `.scrub`.
  #
  # It was written for a different hazard: backticks hand back a string
  # tagged with the *shell's* external encoding, US-ASCII whenever LANG
  # is unset, so this repository's Japanese commit messages raised on the
  # first `split` under a bare local shell while passing in CI. That
  # hazard is gone -- line 4's `require_relative "utf8"` fixes
  # `Encoding.default_external` before anything here shells out, so the
  # backtick result is already UTF-8 under `LC_ALL=C`. The comment
  # describing it outlived it by a release (`024.191`), which is the
  # shape `CLAUDE.md`'s revert/documentation rule warns about: the prose
  # was correct when written and nothing about the fix announced that it
  # had made it false.
  #
  # A commit message can still carry genuinely invalid bytes, which no
  # locale setting fixes and which would make `scan` raise here rather
  # than not-match. That is what `.scrub` is for, and why the method
  # stays. Deleting line 4 would bring the old hazard back; the two are
  # not interchangeable.
  def as_utf8(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  def tracked_files
    RepoFiles.list(ROOT)
  end

  # Every path this scanner declined to read, and why. A skip is a path
  # the check could not clear, and until 0.2.5 the skips returned an
  # empty list silently -- indistinguishable, in the answer, from a file
  # that was read and found clean.
  #
  # There is one skip left, and it is for a path that is not a file at
  # all. The two that used to be here -- a NUL byte, and invalid UTF-8 --
  # were skips of *content*, and `024.187` is what that cost: the rule
  # was written as a property of the bytes rather than of the file, so
  # any text file that acquired one stray byte silently stopped being
  # checked, including the plain-ASCII home path sitting next to it. The
  # bytes are scrubbed and read now. Measured before the change: the two
  # files it had been declining are both PNGs, and neither carries a
  # name.
  def skipped_files
    @skipped_files ||= []
  end

  # `root:` so an example can point this at a scratch directory. There is
  # no other way to pin the symlink and stray-byte decisions below: both
  # are about what happens to a *file on disk under the root*, and the
  # repository is not a place to create one.
  def offences_in_file(relative_path, root: ROOT)
    absolute = File.join(root, relative_path)

    # **A symlink's content, to git, is the target string** -- so
    # `ln -s $HOME/... x && git add x` commits and pushes a real home
    # path verbatim. `File.file?` and `File.binread` both follow the
    # link: a live one made this read bytes from outside the repository
    # and report a line number in a file that is not in it, and a broken
    # one returned `[]` with no skip recorded at all. `024.188`.
    content =
      if File.symlink?(absolute)
        File.readlink(absolute)
      elsif File.file?(absolute)
        File.binread(absolute)
      else
        # A directory, an unreadable file, or one that vanished between
        # being listed and being read -- which `RepoFiles.list` made
        # possible by including untracked files. This was a bare early
        # return until `024.188`, so it was a third silent skip beside
        # the two the 0.2.5 fix announced.
        skipped_files << { path: relative_path, reason: :not_a_file }
        return []
      end

    as_utf8(content).lines.each_with_index.flat_map do |line, index|
      names_in(line).map { |name| "#{relative_path}:#{index + 1}: #{name}" }
    end
  end

  def tree_offences
    skipped_files.clear
    tracked_files.flat_map { |path| offences_in_file(path) }
  end

  # The two PNGs this tree carries are what make the example above
  # distinguishing: they hold NUL bytes, they are the files the old rule
  # declined, and `skipped_files` comes back empty only because they are
  # read now.
  def files_with_stray_bytes
    tracked_files.select do |relative|
      absolute = File.join(ROOT, relative)
      File.file?(absolute) && !File.symlink?(absolute) && File.binread(absolute).include?("\0")
    end
  end

  # Through `RepoFiles` rather than a backtick in `Dir.chdir(ROOT)`:
  # `chdir` does not override an inherited `GIT_DIR`, so under a
  # pre-commit hook's environment this guard read whichever repository
  # that variable named and reported clean about it -- the privacy check
  # answering about the wrong tree, which is `024.157`.
  def shallow?
    RepoFiles.capture(ROOT, %w[rev-parse --is-shallow-repository]).strip == "true"
  end

  # `actions/checkout` fetches a single commit by default, and this mode
  # would then scan that one commit and report the whole history clean --
  # green because it did not run, which is the failure CLAUDE.md already
  # spends a section on. Refusing is the only honest answer; the
  # secret-scan job that runs this sets `fetch-depth: 0` for gitleaks
  # anyway, and `ci_skip_guard_spec.rb` pins that it still does.
  def message_offences
    raise "refusing to scan commit messages in a shallow clone -- fetch the full history (fetch-depth: 0)" if shallow?

    commit_offences + tag_offences
  end

  def commit_offences
    marker = "@@commit@@"
    log = as_utf8(RepoFiles.capture(ROOT, ["log", "--all", "--format=#{marker}%H%n%B"]))

    log.split(marker).reject { |entry| entry.strip.empty? }.flat_map do |entry|
      sha, body = entry.split("\n", 2)
      names_in(body.to_s).map { |name| "#{sha.to_s[0, 12]}: #{name}" }
    end.uniq
  end

  # An annotated tag's body is hand-written at release time and pushed to
  # the public remote, and it is not a commit message -- so neither
  # `--tree` (blob content) nor the commit half above nor gitleaks (blob
  # rules, and `.gitleaks.toml` adds no home-path rule) ever read a byte
  # of it. `024.190`. Release time is exactly when 0.2.3 pasted a build
  # machine's home directory into a commit message, so this is the same
  # class of channel the check exists for, left uncovered; and a leak
  # here is harder to repair than a commit one, because republishing tags
  # breaks the `buildCommit` SHAs the Marketplace artifacts reference.
  def tag_offences
    tag_bodies.flat_map do |name, body|
      names_in(body).map { |found| "tag #{name}: #{found}" }
    end.uniq
  end

  # Split out so an example can assert **what was read**, not only that
  # nothing was found in it. A tag scan whose format string is wrong, or
  # run in a clone fetched without tags, returns nothing and looks
  # exactly like a clean one -- the shape `shallow?` already refuses for
  # commits, arriving through the other door.
  def tag_bodies
    marker = "@@tag@@"
    format = "#{marker}%(refname:short)%0a%(contents)"
    refs = as_utf8(RepoFiles.capture(ROOT, ["for-each-ref", "refs/tags", "--format=#{format}"]))

    refs.split(marker).reject { |entry| entry.strip.empty? }.map do |entry|
      name, body = entry.split("\n", 2)
      [name.to_s.strip, body.to_s]
    end
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
