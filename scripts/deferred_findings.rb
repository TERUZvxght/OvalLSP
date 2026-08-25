# frozen_string_literal: true

require_relative "utf8"

require "yaml"

# Every entry in `docs/design/tasks/024-deferred-review-findings.md`
# carries a fenced `yaml` block stating its status, its kind, and whether
# it has a user-visible half. This guard reads those blocks.
#
# It exists because the previous attempt did not have them to read.
# 024.25 records that attempt in full: two specs that parsed the file's
# *prose* -- headings, `**Status:**` lines, an opt-out marker written
# mid-sentence -- and were rolled back after each review round found
# another shape the regexes mishandled. The difference here is not a
# better regex. It is that the data now has a grammar with unambiguous
# delimiters, so there is one shape to parse instead of however many
# prose can take.
#
# Three rules follow from that history and are load-bearing:
#
# - **An entry with no block is a failure, not a skip.** The old guard
#   silently dropped a heading it did not recognise, so an entry could be
#   added and never checked. `parses every entry` compares the block count
#   to the heading count for exactly that reason -- and it could not do
#   that until 0.2.16, because both counts came from one pattern and a
#   heading outside it was missing from both. `024.155`; see
#   `HEADING_LINE`, which is deliberately the looser of the two.
# - **The opt-out must say why.** The old guard documented that
#   requirement in three places and enforced it nowhere.
# - **The other end of the check needs a grammar too.** Until 0.2.1 this
#   half was a bare-number search, which is prose-parsing wearing a
#   different hat -- see `#documents?`.
#
# Read with an explicit encoding, never the locale's: the Japanese file is
# almost entirely non-ASCII, and under a C/POSIX locale `File.read` hands
# back US-ASCII and every scan raises.
module DeferredFindings
  module_function

  # The entry number, as a well-formed heading spells it: the prefix and
  # a number, an `R` and a number for a roadmap item, or a dotted tail
  # for a sub-entry. (Described rather than spelled -- `024.126`. An
  # illustration of a sub-number written out here is a citation of an
  # entry that does not exist, in the file the citation guard reads its
  # grammar from.)
  #
  # **One place.** `024.216` counted six readers of this in three
  # incompatible grammars -- the index renderer truncated a sub-number to
  # its parent, one spec's scan matched nothing at all, and each reader
  # was the only reader of its own result, so they could not notice.
  # Everything that needs to recognise a number reads this.
  #
  # The `R` branch requires digits: `R` alone would make the trailing
  # `\b` in `CITATION` match the register's own prose about the roadmap
  # numbering.
  NUMBER = /024\.(?:R[0-9]+|[0-9]+(?:\.[0-9]+)*)/

  ENTRY_HEADING = /^## (#{NUMBER}) ([^\n]*)/

  # Deliberately looser than `ENTRY_HEADING`, and the asymmetry is the
  # point -- `024.155`. `parses every entry` subtracts the parsed blocks
  # from the headings, so if both sides read the same pattern a heading
  # outside it is absent from *both* sets and the subtraction is empty
  # exactly where it was meant to bite: the guard's own header calls that
  # "an entry could be added and never checked", and it was true of this
  # guard until 0.2.16. A colon after the number was enough.
  HEADING_LINE = /^## (024\.\S*)/

  # Where one entry ends and the next begins. Shared, for the same reason
  # as `NUMBER`: three splits with three patterns disagreed about whether
  # a heading needed a trailing space, and the one that said no rendered
  # an index row for a heading the checks could not parse.
  ENTRY_SPLIT = /^(?=## 024\.)/

  # A pointer *to* an entry, written in prose anywhere in the tree.
  # Derived from `NUMBER` rather than written independently: the
  # hand-rolled version could not express a sub-number, so a citation of
  # a sub-entry that has never existed matched as its parent, which does
  # exist, and resolved (`024.182`). Shape described, not spelled, for
  # the reason given above `NUMBER`.
  CITATION = /\b(#{NUMBER})\b/

  # `[^\n]*` for the title, not `.*`: under `/m` -- which the block body
  # needs -- a dot matches newlines, and the title would swallow the file
  # down to the last block, leaving one entry parsed and every other one
  # reported as missing.
  METADATA_BLOCK = /^## (#{NUMBER}) [^\n]*\n\n```yaml\n(.*?)\n```$/m

  # A row in the register's "Retired numbers" table. A deleted entry
  # keeps its number resolvable, which is the whole point of citing one.
  RETIRED_ROW = /^\| `(#{NUMBER})` \|/

  RESOLVED = %w[fixed done].freeze

  def headings(markdown) = markdown.scan(HEADING_LINE).flatten

  def retired_numbers(markdown) = markdown.scan(RETIRED_ROW).flatten

  # The number and title of one entry's block, read from the strict
  # grammar. `nil` for a heading that grammar cannot parse -- the caller
  # decides what to do about that, and the one caller there is refuses to
  # render an index row for it rather than rendering an empty one.
  def number_of(block) = block[ENTRY_HEADING, 1]

  def title_of(block) = block[ENTRY_HEADING, 2].to_s.strip

  # Raised when an entry names a key the legend does not define.
  UnknownKey = Class.new(StandardError)

  # Every key the legend defines. A new one is a deliberate edit here and
  # in the legend, which is the point: `024.68` is a typo'd key silently
  # un-routing an entry, and three guards bolted onto a hand-rolled
  # `key: value` scanner were each broken by the next round -- one blind
  # outside its own `[a-z-]` character class, one skipping every indented
  # line as a folded note's continuation.
  #
  # **This is not a fourth guard.** The block is `yaml` and is parsed as
  # yaml, so `Target:`, `user_visible:` and a key indented under another
  # are keys like any other and are checked like any other. The grammar
  # the guards were guarding does not exist any more.
  KNOWN_KEYS = %w[status kind target released-in user-visible user-visible-note].freeze

  # `defect` is a fault in what the product answers; `roadmap` is a plan;
  # `friction` is something that made *working here* harder. A kind the
  # legend does not define is a typo that would silently route an entry
  # out of every check that filters on kind -- `open_defects` reads
  # `kind == "defect"`, so `kind: defct` makes an open defect invisible
  # to the KNOWN_LIMITATIONS guard.
  KNOWN_KINDS = %w[defect roadmap friction].freeze

  def entries(markdown)
    markdown.scan(METADATA_BLOCK).to_h do |number, block|
      parsed =
        begin
          YAML.safe_load(block)
        rescue Psych::SyntaxError => e
          raise UnknownKey, "#{number}'s metadata is not valid yaml: #{e.message}"
        end
      raise UnknownKey, "#{number}'s metadata is not a mapping" unless parsed.is_a?(Hash)

      unknown = parsed.keys.map(&:to_s) - KNOWN_KEYS
      raise UnknownKey, "#{number} names #{unknown.join(", ")}, which the legend does not define" if unknown.any?

      kind = parsed["kind"].to_s
      unless kind.empty? || KNOWN_KINDS.include?(kind)
        raise UnknownKey, "#{number} has kind #{kind.inspect}, which is not one of #{KNOWN_KINDS.join(", ")}"
      end

      # Stringified because every caller compares against `"open"`,
      # `"defect"`, `"no"` -- and yaml turns an unquoted `yes` into
      # `true`, which is the one shape this file writes that would
      # otherwise change meaning.
      [number, parsed.transform_values { |v| v == true ? "yes" : (v == false ? "no" : v.to_s) }]
    end
  end

  def open_defects(markdown)
    entries(markdown).select do |_, fields|
      fields["kind"] == "defect" && !RESOLVED.include?(fields["status"])
    end
  end

  def undocumented(markdown, *documents)
    open_defects(markdown).reject { |_, fields| fields["user-visible"] == "no" }
                          .keys
                          .reject { |number| documents.all? { |doc| documents?(doc, number) } }
  end

  # Every version `docs/RELEASE_ARTIFACTS.md` records as published. An
  # *open* entry naming one of these is claiming a release that has
  # already gone out (`024.124`).
  def published_versions(markdown) = markdown.scan(/^\| (\d+\.\d+\.\d+) \| `/).flatten

  # **Both sources, because they become true at different moments.**
  # `RELEASE_ARTIFACTS.md` gains a version's row *after* the VSIX is
  # published, so a guard reading only that cannot fire before the
  # release it is about -- it reports the mistake once the mistake has
  # shipped. 0.2.15 went out with six entries still naming it, preflight
  # green the whole way, and this check went red immediately afterwards.
  #
  # A changelog section is written *before* the tag is cut, so preflight
  # sees it while there is still something to do about it. Reading both
  # keeps the later signal as a backstop without waiting for it
  # (`024.233`).
  def open_entries_targeting_a_shipped_release(markdown, artifacts, changelog = nil)
    shipped = published_versions(artifacts) | changelog_versions(changelog)
    open_defects(markdown).filter_map do |number, fields|
      target = fields["target"]
      "#{number} (#{target})" if target && shipped.include?(target)
    end
  end

  # A version with a changelog section is one this project has written
  # release notes for, which happens before the tag.
  def changelog_versions(changelog)
    return [] unless changelog

    changelog.scan(/^## (\d+\.\d+\.\d+)/).flatten
  end

  # The `**Area:**` line of an entry, as the paths it names. Backticked,
  # comma-separated, sometimes with a parenthetical naming the method.
  AREA_LINE = /^\*\*Area:\*\*(.+?)(?=\n\n)/m
  AREA_PATH = %r{`((?:core|vscode|scripts|docs|site|\.github)/[A-Za-z0-9._/-]+)`}

  def area_paths(markdown)
    markdown.scan(/#{HEADING_LINE.source}(.*?)(?=^## 024\.|\z)/m).to_h do |number, body|
      line = body[AREA_LINE, 1].to_s
      [number, line.scan(AREA_PATH).flatten]
    end
  end

  def resolved(markdown)
    entries(markdown).select { |_, fields| RESOLVED.include?(fields["status"]) }
  end

  # The other direction, and the one the 0.2.x work found missing. This
  # guard only ever asked whether an *open* finding is cited, so retiring
  # one left its paragraph in `KNOWN_LIMITATIONS` with nothing to
  # complain -- and the 0.2.4-bound branch's loop found three such
  # paragraphs standing at once, each telling a reader to expect
  # behaviour that had just been removed. Worse than no limitation at
  # all: it sends them looking for something that is not there.
  #
  # `CLAUDE.md` states the lesson as "a revert is the change most likely
  # to leave documentation behind". This is that lesson mechanised, so
  # it does not depend on anyone remembering it.
  def wrongly_documented(markdown, *documents)
    resolved(markdown).keys.select { |number| documents.any? { |doc| anchors(doc, number).any? } }
  end

  # What counts as documenting a finding, as opposed to mentioning it.
  #
  # The bare number was the whole test until 0.2.1, and it cannot tell the
  # two apart: 024.20's user-facing half -- the largest false-positive
  # family the engine had -- appeared nowhere in `KNOWN_LIMITATIONS`,
  # while its number appeared in a paragraph about a *different*
  # consequence, and the guard was green for twenty-two rounds.
  #
  # No regex reads prose well enough to judge that, and 024.25 records
  # what happens when one tries. So the writer says it instead: an
  # `<!-- documents: 024.N -->` marker at the end of the line that
  # documents the finding. A machine cannot check that the paragraph is
  # *adequate*, but it can insist the claim was made deliberately, which
  # a number occurring in a sentence never is. Written inline rather than
  # on its own line because a comment between two list items ends the
  # list in most Markdown renderers.
  #
  # Exactly once per document: two markers for one number mean two
  # paragraphs each claiming to be the place, and no way to tell which
  # one a later edit should keep.
  ANCHOR_PREFIX = "documents:"

  def anchors(document, number)
    document.scan(/^([^\n]*?)<!-- #{ANCHOR_PREFIX} #{Regexp.escape(number)}(?!\.?\d) *-->/)
  end

  # The capture is whatever the marker's own line holds in front of it: a
  # marker alone on a line, or opening one, anchors nothing.
  def documents?(document, number)
    found = anchors(document, number)
    found.length == 1 && found.first.first.match?(/\S/)
  end
end

# `046`'s C3b, run at release time:
#
#   ruby scripts/deferred_findings.rb --targeting 0.2.14
#
# Prints every open entry whose `target:` is that version, with its Area,
# so the person cutting the release has the list of reproductions to
# re-run rather than a memory of which ones mattered.
#
# It exists because `024.41`'s reproduction was quoted forward for
# fifteen releases and two of its six recorded cases had silently moved
# in opposite directions -- one had stopped being the defect, and one had
# become a wider defect than the entry claimed. Nobody re-ran it, because
# nothing said which entries a release was supposed to have re-run.
if __FILE__ == $PROGRAM_NAME
  require "optparse"

  version = nil
  OptionParser.new do |o|
    o.banner = "usage: ruby scripts/deferred_findings.rb --targeting VERSION"
    o.on("--targeting VERSION", "list open entries targeting VERSION") { |v| version = v }
  end.parse!

  if version.nil?
    warn "usage: ruby scripts/deferred_findings.rb --targeting VERSION"
    exit 1
  end

  register = File.expand_path("../docs/design/tasks/024-deferred-review-findings.md", __dir__)
  markdown = File.read(register, encoding: "UTF-8")
  areas = DeferredFindings.area_paths(markdown)

  matching = DeferredFindings.entries(markdown).select do |_, fields|
    fields["target"] == version && !DeferredFindings::RESOLVED.include?(fields["status"])
  end

  if matching.empty?
    puts "deferred-findings: no open entry targets #{version}."
    exit 0
  end

  puts "deferred-findings: #{matching.length} open entr#{matching.length == 1 ? 'y' : 'ies'} target #{version}."
  puts "Re-run each reproduction against the tree being cut, and record the result in the entry."
  puts
  matching.each do |number, fields|
    puts "  #{number}  (#{fields['kind']}, user-visible: #{fields['user-visible']})"
    Array(areas[number]).each { |path| puts "      #{path}" }
  end
end
