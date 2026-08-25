#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Sorts the deferred-findings register by number and regenerates the
# index at its head.
#
# The register is the project's answer to "is this already known?", and
# it had stopped being able to answer: 72 entries, 4,300 lines, 25 of
# them out of numeric sequence because rounds appended in whatever order
# they ran. A record nobody can search is the recording habit without the
# benefit it was adopted for.
#
# Sorting and indexing are mechanical, so they are done mechanically
# rather than asked of whoever writes the next entry --
# `core/spec/meta/deferred_findings_spec.rb` fails when the file on disk
# differs from what this produces, which is what stops the index rotting
# the way a hand-maintained one would.
#
#   ruby scripts/reindex_findings.rb          # rewrite in place
#   ruby scripts/reindex_findings.rb --check  # exit 1 if not current
require_relative "deferred_findings"

module ReindexFindings
  ROOT = File.expand_path("..", __dir__)
  PATH = File.join(ROOT, "docs", "design", "tasks", "024-deferred-review-findings.md")

  module_function

  def entry_key(number)
    tail = number.split(".", 2)[1]
    # `024.R*` are roadmap items and sort after the defects, which is
    # where they have always been read.
    return [1, tail[1..].to_i] if tail.start_with?("R")

    # Element-wise, so a sub-numbered entry sorts under its parent rather
    # than tying with it. `"13.1".to_i` is 13, so both entries used to
    # key on `[0, 13]` and `sort_by` is not stable -- which of the two
    # came first was unspecified (`024.216`).
    [0, *tail.split(".").map(&:to_i)]
  end

  # `024.216`. These were hand-rolled here, in a third grammar: one that
  # truncated a sub-number to its parent and one that then failed
  # outright, so the index grew a second row numbered after the parent
  # with an empty title and a dead anchor. The register has one parser.
  def number_of(block) = DeferredFindings.number_of(block)

  def title_of(block) = DeferredFindings.title_of(block)

  # `046`'s C4. This used to be a second, hand-rolled `key: value`
  # scanner, under a comment saying the yaml block was "this file's own
  # grammar rather than real YAML (see the register's legend)". True when
  # written; false from 0.2.12, when `024.68` replaced the guard's side
  # with `YAML.safe_load` and deleted that legend rule. The two grammars
  # then disagreed -- a quoted `status: "fixed"` rendered in this index
  # as `"fixed"` while every check read `fixed` -- and nothing could
  # notice, because each was the only reader of its own result.
  #
  # `DeferredFindings.entries` is now the single parser. It is stricter
  # than the scanner was (an unknown key raises), which is the point: the
  # index is regenerated from the same reading the checks make.
  def metadata_of(block)
    DeferredFindings.entries(block).values.first || {}
  end

  def anchor_for(number, title)
    slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    "##{number.delete('.')}-#{slug}"
  end

  def render(legend, blocks)
    rows = blocks.map do |block|
      number = number_of(block)
      meta = metadata_of(block)
      title = title_of(block)
      shown = title.length > 69 ? "#{title[0, 68]}…" : title
      release = meta["target"] || meta["released-in"] || "—"
      "| [`#{number}`](#{anchor_for(number, title)}) | #{meta.fetch('status', '?')} | #{release} | #{shown} |"
    end

    index = <<~INDEX
      ## Index

      **Generated from the entries below; do not hand-edit.** Regenerate with
      `ruby scripts/reindex_findings.rb`, which `core/spec/meta/deferred_findings_spec.rb`
      checks is current. It exists because answering "is this known?" used to mean
      reading four thousand lines in no particular order — 25 of 72 entries were out
      of numeric sequence. Findability is what makes a record worth keeping; a record
      nobody can search is the recording habit without the benefit.

      | # | status | release | what it is |
      |---|---|---|---|
      #{rows.join("\n")}

      ---

    INDEX

    "#{legend}\n#{index}#{blocks.join}"
  end

  # Raised when the register carries a heading this grammar cannot read.
  Unparsable = Class.new(StandardError)

  # `024.155`. The reader here used to be *looser* than the one the checks
  # use, so a heading the checks could not parse still got an index row --
  # `?` for status, an empty title, a dead anchor -- and that row then
  # made `indexes every entry` and `is in numeric order with its index
  # current` both pass about an entry nothing else had looked at.
  # Refusing is the only answer that does not manufacture a record.
  #
  # Split out of `rebuild` so an example can hand it a register-shaped
  # string: `rebuild` reads one fixed path, and a check that can only be
  # run against the real file cannot be shown failing.
  def blocks_of(source)
    first = source.index("\n## 024.")
    raise Unparsable, "no entries found" unless first

    blocks = source[(first + 1)..].split(DeferredFindings::ENTRY_SPLIT).reject { |part| part.strip.empty? }

    unparsed = blocks.reject { |block| number_of(block) }
    unless unparsed.empty?
      raise Unparsable, "#{unparsed.length} heading(s) the entry grammar cannot parse, first: " \
                        "#{unparsed.first.lines.first.to_s.strip.inspect}. An entry heading is the " \
                        "number, then a space, then its title."
    end

    blocks
  end

  def rebuild
    source = File.read(PATH, encoding: "UTF-8")
    blocks = blocks_of(source)
    first = source.index("\n## 024.")

    legend = source[0..first]
    # Any previously generated index is part of the legend region and is
    # dropped here rather than parsed, so this is idempotent.
    legend = legend.split(/^## Index$/, 2).first.rstrip + "\n"

    render(legend, blocks.sort_by { |block| entry_key(number_of(block)) })
  end
end

if $PROGRAM_NAME == __FILE__
  rebuilt = ReindexFindings.rebuild
  current = File.read(ReindexFindings::PATH, encoding: "UTF-8")

  if ARGV.include?("--check")
    if rebuilt == current
      puts "reindex-findings: current"
      exit 0
    end
    warn "reindex-findings: the register is out of order or its index is stale."
    warn "Run: ruby scripts/reindex_findings.rb"
    exit 1
  end

  File.write(ReindexFindings::PATH, rebuilt)
  puts(rebuilt == current ? "reindex-findings: already current" : "reindex-findings: rewritten")
end
