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
#   to the heading count for exactly that reason.
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

  ENTRY_HEADING = /^## (024\.[0-9R][0-9.]*) /
  # `[^\n]*` for the title, not `.*`: under `/m` -- which the block body
  # needs -- a dot matches newlines, and the title would swallow the file
  # down to the last block, leaving one entry parsed and every other one
  # reported as missing.
  METADATA_BLOCK = /^## (024\.[0-9R][0-9.]*) [^\n]*\n\n```yaml\n(.*?)\n```$/m
  RESOLVED = %w[fixed done].freeze

  def headings(markdown) = markdown.scan(ENTRY_HEADING).flatten

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

  def open_entries_targeting_a_shipped_release(markdown, artifacts)
    published = published_versions(artifacts)
    open_defects(markdown).filter_map do |number, fields|
      target = fields["target"]
      "#{number} (#{target})" if target && published.include?(target)
    end
  end

  # The `**Area:**` line of an entry, as the paths it names. Backticked,
  # comma-separated, sometimes with a parenthetical naming the method.
  AREA_LINE = /^\*\*Area:\*\*(.+?)(?=\n\n)/m
  AREA_PATH = %r{`((?:core|vscode|scripts|docs|site|\.github)/[A-Za-z0-9._/-]+)`}

  def area_paths(markdown)
    markdown.scan(/^## (024\.\S+)(.*?)(?=^## 024\.|\z)/m).to_h do |number, body|
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
