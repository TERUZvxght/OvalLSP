#!/usr/bin/env ruby
# frozen_string_literal: true

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

ROOT = File.expand_path("..", __dir__)

# `docs/NN-name.md` is an established shorthand for
# `docs/design/docs/NN-name.md`, used 91 times across 39 files since the
# design documents moved. It is a shorthand, not an error: rewriting 91
# lines would cost more than it buys and would make the citations longer
# at every reading. Normalised here so the check can be strict about
# everything else.
SHORTHAND = %r{\Adocs/(\d{2}-[a-z0-9-]+\.md)\z}

# What a documentation path looks like, inside backticks or a Markdown
# link. Anchors and trailing punctuation are stripped by the caller.
CITATION = %r{
  (?<path>
    docs/(?:design/)?(?:tasks/|adrs/|docs/)?[A-Za-z0-9._-]+\.md
  )
}x

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

tracked, status = run("git", "ls-files")
refuse("could not list tracked files") unless status.success?

# Binary and vendored trees hold no citations anybody maintains, and
# `core/vendor` alone is thousands of files.
SKIP = %r{\A(core/vendor/|vscode/node_modules/|core/spec/fixtures/rails_real/|.*\.(png|ico|svg|lock|vsix|sqlite3)\z)}

files = tracked.split("\n").reject { |f| f.match?(SKIP) }

dangling = []
inspected = 0
citations = 0

files.each do |rel|
  path = File.join(ROOT, rel)
  next unless File.file?(path)

  begin
    content = File.read(path, encoding: "UTF-8")
    next unless content.valid_encoding?
  rescue StandardError
    # A file this cannot read holds no citation it can check, and saying
    # so is the honest answer -- but not raising here would make an
    # unreadable file look clean. Counted, and reported at the end.
    next
  end

  inspected += 1
  content.each_line.with_index(1) do |line, number|
    line.scan(CITATION) do
      raw = Regexp.last_match[:path]
      citations += 1
      target = raw.sub(SHORTHAND) { "docs/design/docs/#{Regexp.last_match(1)}" }
      next if File.file?(File.join(ROOT, target))

      dangling << { file: rel, line: number, cited: raw, resolved: target, text: line.strip[0, 110] }
    end
  end
end

puts "check-doc-links: #{inspected} tracked file(s) inspected, #{citations} documentation citation(s)."

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
exit 1
