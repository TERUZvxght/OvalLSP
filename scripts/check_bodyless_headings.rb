#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"

# **A heading whose body was deleted keeps making the heading's claim.**
#
# Three times this project has fixed a limitation, removed the paragraph
# describing it, and left the `##` above it standing. With nothing under
# it the heading *is* the whole statement, and it states a defect the
# product no longer has:
#
#   0.3.0  `024.99` fixed, "Completion offers methods you cannot call" left
#   0.3.0  `024.86` fixed, "An instance variable set in another method" left
#   0.3.2  `024.283` fixed, its body cut and the heading left saying the
#          packaged extension is only smoke-tested on macOS
#
# **No existing check could see any of them**, and the reason is worth
# stating because it is the shape of the whole class:
# `deferred_findings_spec`'s "stops documenting a finding once it is
# fixed" matches on the `<!-- documents: -->` marker, and that marker
# lives *inside the body*. It leaves with the body. The heading it leaves
# behind is invisible to the guard written for exactly this case. Two of
# the three sat in the tree across three releases with preflight green
# over them.
#
# `CLAUDE.md`'s same-place rule says the third instance is where a
# mechanical countermeasure replaces a hand fix, and that a regression
# test for the one case is not one. So this reads the *shape*, over every
# tracked Markdown document rather than the two limitation pages.
#
# **The rule is "followed by a heading of the same level", and it was
# measured rather than chosen.** The looser form -- any heading with no
# text before the next heading -- finds five things in this tree: the
# four real ones above, and `030-0.2.4-review-loop.md`'s "The original
# record follows", which introduces a quoted document that opens with its
# own level-1 heading. That is a document boundary, not an empty section.
# Restricting to the *same* level keeps all four and drops that one, so
# this needs no exemption list -- and an exemption list is the part that
# would rot.
module BodylessHeadings
  ROOT = File.expand_path("..", __dir__)

  module_function

  # `RepoFiles.list`, not `git ls-files`: a document written and not yet
  # committed must not be invisible to the check that judges it, which is
  # `024.194` and is enforced by `untracked_visibility_spec`. This check
  # inspects the files rather than treating them as evidence that
  # something happens, so `list` is the right side of that pair.
  def tracked_markdown(root = ROOT)
    RepoFiles.list(root, "*.md")
  end

  # `nil` for anything that is not an ATX heading. The `\S` matters: a
  # line of hashes and spaces is a horizontal rule in some dialects and a
  # heading with no text in none of them.
  def heading_level(line)
    match = /\A(\#{1,6}) \S/.match(line)
    match && match[1].length
  end

  # Every heading immediately followed by a heading of the same level,
  # blank lines aside. Fenced blocks are skipped: a `##` inside ``` is
  # sample text, and this repository's documents quote Markdown often.
  def offenders(text)
    lines = text.split("\n")
    fenced = false

    lines.each_with_index.filter_map do |line, index|
      if line.lstrip.start_with?("```")
        fenced = !fenced
        next
      end
      next if fenced

      level = heading_level(line)
      next unless level

      following = lines[(index + 1)..].to_a.drop_while { |l| l.strip.empty? }.first
      next unless following && heading_level(following) == level

      [index + 1, line]
    end
  end

  def scan(paths, root = ROOT)
    paths.flat_map do |relative|
      offenders(File.read(File.join(root, relative), encoding: "UTF-8")).map { |line, text| [relative, line, text] }
    end
  end

  def run(root = ROOT)
    paths = tracked_markdown(root)

    # The census before the verdict. A checker that cannot see the thing
    # it checks reports exactly what a working checker reports when
    # nothing is wrong (`024.148`), and an empty file list is the way
    # this one would do that.
    if paths.empty?
      warn "check-bodyless-headings: git listed no tracked Markdown, so this check cannot see what it checks"
      return 1
    end

    found = scan(paths, root)
    puts "check-bodyless-headings: #{paths.length} tracked Markdown document(s) read."

    if found.empty?
      puts "check-bodyless-headings: no heading is left standing without a body."
      0
    else
      warn "check-bodyless-headings: #{found.length} heading(s) with no body:"
      found.each { |path, line, text| warn "  #{path}:#{line}  #{text}" }
      warn "A heading with nothing under it *is* its claim. If the body went because the thing it"
      warn "described is fixed, the heading goes with it; if the section is still owed, write it."
      1
    end
  end
end

exit(BodylessHeadings.run) if __FILE__ == $PROGRAM_NAME
