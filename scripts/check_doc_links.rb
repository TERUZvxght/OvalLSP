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
# **Source comments are in scope, deliberately.** All 19 dangling
# citations live in them. A checker that read only Markdown would have
# reported this tree clean.

require "set"
require "shellwords"

# The repository to scan. Overridable so the marker's own guarantee can
# be pinned: a spec builds a throwaway git repository holding a citation
# that no commit ever carried, marks it as a recorded deletion, and
# requires this to fail anyway. Without the override that property could
# only be checked by damaging this tree.
ROOT = File.expand_path(ENV.fetch("CHECK_DOC_LINKS_ROOT", File.expand_path("..", __dir__)))

# `docs/<NN>-<name>.md` is an established shorthand for
# `docs/design/docs/<NN>-<name>.md`, used 91 times across 39 files since
# the design documents moved. It is a shorthand, not an error: rewriting
# 91 lines would cost more than it buys and would make the citations
# longer at every reading. Normalised here so the check can be strict
# about everything else.
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

# What a documentation path looks like, inside backticks or a Markdown
# link. Anchors and trailing punctuation are stripped by the caller.
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
    docs/(?:design/)?(?:tasks/|adrs/|docs/)?[A-Za-z0-9._-]+\.md
  )
}x

# A Markdown link whose target is relative -- resolved against the
# citing file's own directory, which is why it needs the second pass
# below rather than a wider version of the pattern above.
RELATIVE_LINK = %r{\]\((?<path>(?!https?://|/|\#)[A-Za-z0-9._/-]+\.md)(?:\#[^)]*)?\)}

def run(*args)
  out = IO.popen(args, chdir: ROOT, err: %i[child out], &:read)
  [out, $?]
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

# Binary and vendored trees hold no citations anybody maintains, and
# `core/vendor` alone is thousands of files.
SKIP = %r{\A(core/vendor/|vscode/node_modules/|core/spec/fixtures/rails_real/|.*\.(png|ico|svg|lock|vsix|sqlite3)\z)}

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
# also still a failure, because the marker is a deliberate edit on the
# line that needs it rather than a mode the file is in.
DELETED_MARKER = "<!-- deleted -->"

# Whether a path ever existed. `--diff-filter=D` alone misses a file
# deleted in a commit that git recorded as a rename, so this asks the
# cheaper and more direct question: does any commit's tree name it?
def ever_existed?(path)
  @ever_existed ||= {}
  return @ever_existed[path] if @ever_existed.key?(path)

  out, status = run("git", "log", "--all", "--pretty=format:%H", "-1", "--", path)
  @ever_existed[path] = status.success? && !out.strip.empty?
end

files = tracked_files.reject { |f| f.match?(SKIP) }

dangling = []
inspected = 0
citations = 0
recorded_deletions = 0
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
      target = raw.sub(SHORTHAND) { "docs/design/docs/#{Regexp.last_match(1)}" }
      next if File.file?(File.join(ROOT, target))

      if line.include?(DELETED_MARKER) && ever_existed?(target)
        recorded_deletions += 1
        next
      end

      dangling << { file: rel, line: number, cited: raw, resolved: target, text: line.strip[0, 110] }
    end

    # Relative links, resolved against the citing file's own directory.
    next unless rel.end_with?(".md")

    line.scan(RELATIVE_LINK) do
      raw = Regexp.last_match[:path]
      next if raw.start_with?("docs/") # already counted by the pass above

      citations += 1
      relative_citations += 1
      target = File.join(File.dirname(rel), raw)
      target = target.split("/").each_with_object([]) { |part, acc| part == ".." ? acc.pop : (acc << part unless part == ".") }.join("/")
      next if File.file?(File.join(ROOT, target))

      if line.include?(DELETED_MARKER) && ever_existed?(target)
        recorded_deletions += 1
        next
      end

      dangling << { file: rel, line: number, cited: raw, resolved: target, text: line.strip[0, 110] }
    end
  end
end

puts "check-doc-links: #{inspected} file(s) inspected, #{citations} documentation citation(s), " \
     "#{relative_citations} of them relative, " \
     "#{recorded_deletions} naming a deleted file on a line marked as recording the deletion."

# It fails rather than reporting, because the sentence below is the whole
# output of this check and it cannot be said about a file that was not
# read. `CLAUDE.md`'s test for a swallowed failure is not "is this
# failure important" but "does the fallback let a caller assert
# something" -- and here the caller asserts *every* path resolves.
unless unreadable.empty?
  warn("check-doc-links: #{unreadable.length} file(s) could not be read, so their citations were not checked:")
  unreadable.each { |u| warn("    #{u[:file]}  (#{u[:reason]})") }
  warn("check-doc-links: a file this cannot read is not a file it found clean. Fix its encoding, " \
       "or add it to SKIP with a reason if it is genuinely not authored text.")
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
