#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"

# Every documentation path named in tracked content must resolve to a file
# that exists.
#
# `046`'s A0, and it is first because nothing else in that change set is
# safe without it: **"does anything cite this?" has to be a question the
# tree can answer before any deletion is trustworthy.**
#
# The measured state when this was written, at `6bc31b9`: **19 lines
# across 17 files cite five task filenames that have never existed in any
# commit.** The whole `plugins/` subsystem and the public SDK document
# point at one of them, and `024.87`'s `**Area:**` names a source file
# never committed -- which is the first thing whoever picks up that open,
# user-visible entry would act on.
#
# `scripts/check_site_links.rb` already makes this argument in its own
# header -- "nothing else would notice a renamed page" -- and is scoped to
# `site/` alone. This is the same argument for the other 101 documents.
#
# **Source comments are in scope, deliberately.** Eighteen of the 19
# dangling citations live in them; the nineteenth is in the public SDK
# document named above. A checker that read only Markdown would have
# found one of the nineteen and reported the rest of this tree clean.
#
# `024.178`: this said "all 19", in four places, one of them an rspec
# failure message -- so the false sentence was what a future failure
# would print at the reader. Re-running the founding census reproduces
# it exactly and puts the nineteenth in a Markdown document, which the
# sentence immediately above already names. The conclusion survives at
# 18 of 19; the absolute quantifier carrying it did not.

require "set"
require "shellwords"

# The repository to scan. Overridable so the marker's own guarantee can
# be pinned: a spec builds a throwaway git repository holding a citation
# that no commit ever carried, marks it as a recorded deletion, and
# requires this to fail anyway. Without the override that property could
# only be checked by damaging this tree.
ROOT = File.expand_path(ENV.fetch("CHECK_DOC_LINKS_ROOT", File.expand_path("..", __dir__)))

# `docs/<NN>-<name>.md` is an established shorthand for the
# fully-qualified form, used widely across this tree since the design
# documents moved.
#
# It is a shorthand, not an error: rewriting those lines would cost more
# than it buys and would make the citations longer at every reading.
# Normalised here so the check can be strict about everything else.
#
# **No count is written here, deliberately.** `024.179`: this sentence
# carried one, and it was wrong twice running. It said "91 times across
# 39 files", which was a raw count of the short form anywhere — a
# pattern that also matches the *tail* of the fully-qualified path, the
# form that is not a shorthand at all, so the cost side of the argument
# was roughly doubled. Round 3 re-derived it to "45 times across 20
# files": the citation count was true one commit before the commit that
# wrote the sentence and on no commit since, and the file count was
# never true at all -- 22 there, 23 on the commit that wrote it.
# (Neither spelling of the path is written out here: this script scans
# itself, and quoting either makes the comment the finding.)
#
# The number moves with every release and the argument does not rest on
# it. A number that is a claim about this tree belongs in a
# `<!-- measured: -->` marker with a deriver, and this file is outside
# the four globs that scanner reads (`024.181`) — so the correction is
# to stop asserting it here, not to assert it again.
#
# **The placeholders are written with angle brackets deliberately.** This
# script scans every tracked file, which includes itself, so an example
# path spelled the way a real one is spelled becomes a finding about the
# checker's own comment. Without the brackets these two lines were
# exactly that, on the first run of the spec -- and so, on the second
# run, was the sentence written to explain it, which quoted the bad form
# in order to name it.
#
# Any checker that reads all tracked content has this problem. The fix is
# to make an example unspellable as a path, not to exempt the file:
# exempting it would stop checking a file that does carry real citations,
# and this one carries four.
SHORTHAND = %r{\Adocs/(\d{2}-[a-z0-9-]+\.md)\z}

# Binary and vendored trees hold no citations anybody maintains, and
# `core/vendor` alone is thousands of files.
#
# `.gitignore` and `.gitattributes` hold *patterns*, not prose. A glob
# ending in a Markdown extension is not a reference to anything, and
# reading one as a citation reports a dangling path that never was one.
# (The example is described rather than quoted: writing the glob here
# would make this comment the finding.)
SKIP = %r{\A(core/vendor/|vscode/node_modules/|core/spec/fixtures/rails_real/|(.*/)?\.gitignore\z|(.*/)?\.gitattributes\z|.*\.(png|ico|svg|lock|vsix|sqlite3)\z)}

# What a documentation path looks like, inside backticks or a Markdown
# link. **Nothing strips anything.** The character class simply stops
# before an anchor or a trailing full stop, so the capture is already a
# bare path and both readers of it -- the scan loop and `resolve` -- take
# it verbatim. This comment said "stripped by the caller" until
# `024.169`; no caller stripped, and a maintainer acting on it would
# either have added a pass that already happens or widened the class
# trusting a cleanup that does not exist. (`RELATIVE_LINK` below does
# consume an anchor, but in the pattern rather than in a caller, and it
# is a different constant -- which is where the belief came from.)
#
# Two forms, because until 0.2.14 only the first was matched and the
# header claimed to check "every documentation path named in tracked
# content". It did not: **105 relative links were outside the check
# entirely**, including ten between task files that cite each other
# constantly (`](042-second-enumeration.md)`) and `docs/ROADMAP.md`'s
# own link to the register. Round 1 measured it. A guarantee stated
# without a caveat has to be the guarantee, or the caveat has to be
# stated.
CITATION = %r{
  (?<path>
    # Any depth under `docs/`. Round 2 enumerated the subdirectories that
    # existed at the time, and a citation in any other one was not merely
    # resolved loosely -- it never matched, so the check reported clean a
    # region it had not read. `024.177`. The reach of a scanner is not a
    # list anybody maintains, and the coverage example in
    # `doc_links_spec.rb` now asserts that every document in this tree is
    # one this can name.
    docs/(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+\.md
    |
    # Documents that live outside `docs/`: an upper-case name, an
    # optional `.ja`, an optional `vscode/` prefix. Round 2 found the
    # check could not name a single one of them, though they are cited
    # all over the tree. The header said "every documentation path named
    # in tracked content"; it meant "every path beginning `docs/`".
    #
    # Matched **structurally**, not from a list of what exists. Deriving
    # the set from the tree would make this self-defeating: a citation of
    # a *deleted* root document would stop matching the moment the file
    # went away, which is the one case the check is for.
    #
    # Neither their number nor an enumeration of them is written here.
    # `024.179`: the sentence said "twenty" and then named fifteen,
    # counting `vscode/` as six when it is eight and dropping three `.ja`
    # halves -- and it is the list a reader consults to decide whether
    # the structural pattern still covers what it claims, so being wrong
    # in both directions at once is the whole cost. The coverage example
    # checks that every run instead.
    (?:vscode/)?[A-Z][A-Z0-9_]*(?:\.ja)?\.md
  )
}x

# A Markdown link whose target is relative -- resolved against the
# citing file's own directory, which is why it needs the second pass
# below rather than a wider version of the pattern above.
RELATIVE_LINK = %r{\]\((?<path>(?!https?://|/|\#)[A-Za-z0-9._/-]+\.md)(?:\#[^)]*)?\)}

# Every caller here runs git, and goes through `RepoFiles` so that the
# inherited `GIT_DIR`/`GIT_INDEX_FILE` a hook is given cannot aim it at
# another repository -- `024.157`, which is why this is not a bare
# `IO.popen(["git", ...])` any more.
def run(*args)
  args = args.drop(1) if args.first == "git"
  [RepoFiles.capture(ROOT, args), $?]
end

def refuse(message)
  warn("check-doc-links: #{message}")
  exit 1
end

shallow, = run("git", "rev-parse", "--is-shallow-repository")
refuse("this is a shallow clone; a citation census over part of a tree is not a census.") if shallow.strip == "true"

# Tracked files *and* files not yet added — `024.147`. A citation added
# in a file you have not committed is exactly the citation this exists to
# catch, and `git ls-files` alone cannot see it.
begin
  tracked_files = RepoFiles.list(ROOT)
rescue StandardError => e
  refuse("could not list files: #{e.message}")
end


# A record of a deletion has to be able to name what was deleted, and a
# release document that says "this file went away" is the one place a
# path *should* resolve to nothing. Marking the line says so.
#
# The marker is not a blanket exemption, and this is the whole design:
# it admits a path that **once existed in this repository's history**
# and no longer does. A path that has never existed in any commit is
# still a failure with the marker present -- which is the case this
# check was built for, since all 19 of its founding citations were
# names no commit had ever carried. A pointer to a *renamed* file is
# also still a failure, and is reported separately, because the content
# is not gone and "restore the file" is not the repair -- the citation
# should name where it went.
#
# That last sentence described nothing until 0.2.16. `ever_existed?`
# asks whether any commit's tree named the path, which is true for a
# path git carried under its pre-rename name, so a renamed-away pointer
# passed and was counted in the deleted-file total -- and renames are
# how documents move in this tree, which made the exemption widest
# exactly where it was meant to be narrowest. `024.176`.
DELETED_MARKER = "<!-- deleted -->"

# Whether a path ever existed. `--diff-filter=D` alone misses a file
# deleted in a commit that git recorded as a rename, so this asks the
# cheaper and more direct question: does any commit's tree name it?
# Where a citation may resolve. The two-digit design-doc form is an established
# shorthand for `docs/design/docs/`; a bare upper-case name like
# `KNOWN_LIMITATIONS.md` is prose shorthand for the file wherever it
# actually lives, which for most of them is `docs/`. Returns nil when it
# resolves, or the path it could not find.
def candidates_for(raw)
  list = [raw]
  list << "docs/design/docs/#{Regexp.last_match(1)}" if raw.match(SHORTHAND)
  list.concat(["docs/#{raw}", "vscode/#{raw}", "docs/design/#{raw}"]) unless raw.include?("/")
  list
end

def resolve(raw)
  list = candidates_for(raw)
  return nil if list.any? { |c| carried?(c) }

  list.first
end

# Whether this repository carries the path, byte for byte. `024.175`.
#
# This was `File.file?`, which asks the working tree rather than the
# repository, and the two disagree in both directions. On APFS the
# working tree folds case, so a citation differing from the real
# filename only in case resolved on the maintainer's machine and was a
# dead link on Linux and in GitHub's renderer -- with `preflight`, the
# gate whose whole purpose is to run *before* the commit, strictly
# weaker than CI on that class of typo. And a file present on disk but
# ignored by git is not a file any reader of this repository has, yet
# `File.file?` answered for it too.
#
# `CARRIED` is the same enumeration the scan itself reads, so the
# resolver and the census cannot disagree about what exists, and it is
# the same question `ever_existed?` puts to git -- which was already
# case-sensitive, so the script previously disagreed with itself.
def carried?(path)
  CARRIED.include?(path)
end

# The same candidate list, against history. A citation written as a bare
# document name may refer to a file git only ever carried under a
# directory -- so asking history about the bare path answers no, and the
# deletion marker cannot admit a deletion it is correctly recording.
#
# (No filename appears in this comment on purpose. This script scans
# itself, and naming the deleted file here would make the comment a
# finding about the comment -- which is what it did on the first run.)
def ever_existed_anywhere?(raw)
  candidates_for(raw).any? { |c| ever_existed?(c) }
end

def ever_existed?(path)
  @ever_existed ||= {}
  return @ever_existed[path] if @ever_existed.key?(path)

  out, status = run("git", "log", "--all", "--pretty=format:%H", "-1", "--", path)
  @ever_existed[path] = status.success? && !out.strip.empty?
end

# The name a renamed path lives under **now**, or nil.
#
# `024.176`. The marker paragraph above says a pointer to a renamed file
# is still a failure, and until 0.2.16 nothing made that true:
# `ever_existed?` asks whether any commit's tree named the path, which is
# yes for a path git carried under its pre-rename name. So a citation of
# a file that was renamed away passed, and was counted in the "naming a
# deleted file" total -- the count the check prints was not the count it
# names. Renames are the common case for documents in this tree, so the
# exemption was widest exactly where it was meant to be narrowest.
#
# The question asked is not "was this ever renamed" but "did the content
# end up somewhere that still exists". A file renamed and *then* deleted
# is a genuine deletion and is still admitted, which is why the target is
# tested against the working tree rather than the rename being treated as
# disqualifying on its own.
# Every rename this history records, old name to new, read in one call.
#
# **Without a pathspec, deliberately.** `git log --diff-filter=R
# --name-status -- <path>` reports *nothing* for a path that was renamed:
# the pathspec limits the diff before rename detection runs, so the two
# halves are never paired. Measured before this was written -- with the
# pathspec the output is empty, without it the same history prints the
# `R100  <old>  <new>` line. That is also why this is one call for the
# whole run rather than one per marked citation: 136 renames across this
# history, 40ms, against 24 marked citations.
def rename_map
  @rename_map ||= begin
    out, status = run("git", "log", "--all", "--find-renames", "--diff-filter=R",
                      "--name-status", "--pretty=format:")
    map = {}
    if status.success?
      out.each_line do |line|
        kind, from, to = line.strip.split("\t")
        next unless kind.to_s.start_with?("R") && from && to

        # Oldest wins: `git log` walks newest first, so a later
        # assignment is an earlier rename in a chain.
        map[from] = to
      end
    end
    map
  end
end

# Where a renamed path's content lives **now**, or nil.
def renamed_target(path)
  @renamed_target ||= {}
  return @renamed_target[path] if @renamed_target.key?(path)

  seen = {}
  current = path
  result = nil
  while (nxt = rename_map[current]) && !seen[current]
    seen[current] = true
    current = nxt
    if File.file?(File.join(ROOT, current))
      result = current
      break
    end
  end
  @renamed_target[path] = result
end

def renamed_target_anywhere(raw)
  candidates_for(raw).filter_map { |c| renamed_target(c) }.first
end

files = tracked_files.reject { |f| f.match?(SKIP) }

# What this repository carries, as an exact set -- see `carried?`.
CARRIED = tracked_files.to_set

dangling = []
inspected = 0
citations = 0
recorded_deletions = 0
renamed = []
unreadable = []
relative_citations = 0

files.each do |rel|
  path = File.join(ROOT, rel)
  next unless File.file?(path)

  begin
    content = File.read(path, encoding: "UTF-8")
    unless content.valid_encoding?
      unreadable << { file: rel, reason: "not valid UTF-8" }
      next
    end
  rescue StandardError => e
    # A file this cannot read holds no citation it can check, and saying
    # so is the honest answer -- but dropping it silently makes an
    # unreadable file indistinguishable from a clean one. **Counted and
    # reported**, which until 0.2.14 this comment claimed and nothing
    # did: `inspected` was incremented after the skip and the summary
    # printed neither branch, so a file that took its citations with it
    # left the gate printing "every documentation path resolves".
    unreadable << { file: rel, reason: "#{e.class}: #{e.message}" }
    next
  end

  inspected += 1
  content.each_line.with_index(1) do |line, number|
    line.scan(CITATION) do
      raw = Regexp.last_match[:path]
      citations += 1
      target = resolve(raw)
      next if target.nil?

      if line.include?(DELETED_MARKER) && ever_existed_anywhere?(raw)
        moved = renamed_target_anywhere(raw)
        if moved.nil?
          recorded_deletions += 1
          next
        end
        renamed << { file: rel, line: number, cited: raw, moved: moved }
        next
      end

      dangling << { file: rel, line: number, cited: raw, resolved: target, text: line.strip[0, 110] }
    end

    # Relative links, resolved against the citing file's own directory.
    next unless rel.end_with?(".md")

    line.scan(RELATIVE_LINK) do
      raw = Regexp.last_match[:path]

      # A link beginning `docs/` used to be handed back to the pass above
      # on the grounds that it was "already counted" there. That pass
      # resolves against the repository root; a relative link resolves
      # against the citing file's own directory, and the two agree only
      # for a document at the root. `024.174`: for anything nested the
      # checker was validating a path the reader can never follow --
      # which is the failure the relative pass was added to close,
      # reopened by the pass's own optimisation. It is counted twice now,
      # once per question asked, because the two questions are different.
      citations += 1
      relative_citations += 1
      target = File.join(File.dirname(rel), raw)
      target = target.split("/").each_with_object([]) { |part, acc| part == ".." ? acc.pop : (acc << part unless part == ".") }.join("/")
      next if carried?(target)

      if line.include?(DELETED_MARKER) && ever_existed?(target)
        moved = renamed_target(target)
        if moved.nil?
          recorded_deletions += 1
          next
        end
        renamed << { file: rel, line: number, cited: raw, moved: moved }
        next
      end

      dangling << { file: rel, line: number, cited: raw, resolved: target, text: line.strip[0, 110] }
    end
  end
end

puts "check-doc-links: #{inspected} file(s) inspected, #{citations} documentation citation(s), " \
     "#{relative_citations} of them relative, " \
     "#{recorded_deletions} naming a deleted file on a line marked as recording the deletion."

# Coverage, per top-level root, so that **what this read is a claim and
# not an assumption**.
#
# Round 2 broke this check by widening `SKIP`: inspection dropped from
# 537 files to 117, a dangling citation in a `core/lib` source comment
# went unreported, and every example stayed green. `SKIP` was an unpinned
# constant, and the headline of this file -- "source comments are in
# scope, deliberately" -- was one edit away from false.
#
# A floor stated as a total would be a number to keep updating. Stated
# per root it is structural: this check is worthless if it stops reading
# any of these, and none of them will ever legitimately fall to zero.
# `doc_links_spec.rb` asserts each is non-zero, which is an assertion
# `SKIP` cannot satisfy by shrinking the input.
coverage = files.group_by { |f| f.split("/").first }.transform_values(&:length)
%w[core vscode scripts docs site].each do |root|
  puts "check-doc-links: coverage.#{root}=#{coverage.fetch(root, 0)}"
end

# The other half of coverage, and the half a hand-written list shrinks
# without anybody noticing. `024.177`.
#
# The floor above says how much of the tree this **reads**. This says how
# much of it this can **refer to**: a document `CITATION` cannot name is
# one whose citations from source comments no run will ever test, however
# much of the tree was read looking for them. Round 2's pattern could
# name a path only in an enumerated set of `docs/` subdirectories, so
# that property was a silent consequence of where a file happened to be
# put, and adding a subdirectory would have made the check quietly
# smaller while every number it prints stayed healthy.
#
# Reported rather than refused, for the same reason the floor is: a
# throwaway repository built by a spec, or somebody else's tree, may
# legitimately hold a document nothing cites. `doc_links_spec.rb`
# requires this to be zero for *this* repository.
#
# The names go on the same line as the count rather than in a loop below
# it, so that reverting the count cannot leave the names behind or the
# other way round: one statement, one hunk, nothing here unpinned.
unnameable = files.select { |f| f.end_with?(".md") }.reject { |f| f.match?(/\A#{CITATION}\z/) }
puts "check-doc-links: unnameable-documents=#{unnameable.length}" \
     "#{unnameable.empty? ? '' : " (#{unnameable.join(', ')})"}"

# It fails rather than reporting, because the sentence below is the whole
# output of this check and it cannot be said about a file that was not
# read. `docs/CODE_DISCIPLINE.md`'s test for a swallowed failure is not "is this
# failure important" but "does the fallback let a caller assert
# something" -- and here the caller asserts *every* path resolves.
unless unreadable.empty?
  warn("check-doc-links: #{unreadable.length} file(s) could not be read, so their citations were not checked:")
  unreadable.each { |u| warn("    #{u[:file]}  (#{u[:reason]})") }
  warn("check-doc-links: a file this cannot read is not a file it found clean. Fix its encoding, " \
       "or add it to SKIP with a reason if it is genuinely not authored text.")
  exit 1
end

# A marked citation of a path the content merely *moved* out of.
# Reported separately because the repair is different: the path is not
# gone, so restoring a file is not the fix and neither is deleting the
# line -- the citation should name where the content went. `024.176`.
unless renamed.empty?
  warn("check-doc-links: #{renamed.length} citation(s) marked as recording a deletion name a file " \
       "that was renamed, not deleted:")
  renamed.sort_by { |r| [r[:file], r[:line]] }.each do |r|
    warn("    #{r[:file]}:#{r[:line]}  `#{r[:cited]}` now lives at `#{r[:moved]}`")
  end
  warn("check-doc-links: the marker admits a path whose content is gone. Repoint the citation at " \
       "the current name.")
  exit 1
end

if dangling.empty?
  puts "check-doc-links: every documentation path resolves."
  exit 0
end

by_name = dangling.group_by { |d| d[:cited] }
warn("check-doc-links: #{dangling.length} citation(s) resolve to nothing, naming #{by_name.length} path(s):")
by_name.sort_by { |name, _| name }.each do |name, hits|
  warn("  #{name}")
  hits.sort_by { |h| [h[:file], h[:line]] }.each { |h| warn("    #{h[:file]}:#{h[:line]}  #{h[:text]}") }
end
warn("check-doc-links: fix the citation or restore the file. A path that resolves to nothing " \
     "sends the next reader -- or the next agent -- somewhere that does not exist.")
warn("check-doc-links: if a line is *recording* a deletion, mark it #{DELETED_MARKER} -- " \
     "which admits only a path some commit in this history actually carried.")
exit 1
