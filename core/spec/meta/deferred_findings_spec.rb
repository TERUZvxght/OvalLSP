# frozen_string_literal: true

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

  # Deliberately not a YAML parser: the grammar is `key: value` lines and
  # one folded `>` block, and accepting more than that would be accepting
  # shapes nobody writes and nothing checks.
  def entries(markdown)
    markdown.scan(METADATA_BLOCK).to_h do |number, block|
      fields = block.scan(/^([a-z-]+): *(.*)$/).to_h
      [number, fields]
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

RSpec.describe "deferred findings metadata" do
  # Sorting and indexing are mechanical, so they are checked mechanically
  # rather than asked of whoever writes the next entry. The register had
  # reached 72 entries and 4,300 lines with 25 of them out of numeric
  # sequence, because rounds appended in whatever order they ran -- and
  # "is this already known?" is the question it exists to answer.
  #
  # `scripts/reindex_findings.rb` is the single implementation; this reads
  # it rather than reimplementing the ordering, so the two cannot diverge
  # about what "in order" means.
  describe "the register stays findable" do
    it "is in numeric order with its index current" do
      require_relative "../../../scripts/reindex_findings"

      current = File.read(ReindexFindings::PATH, encoding: "UTF-8")

      expect(ReindexFindings.rebuild).to eq(current),
                                         "the register is out of numeric order, or its generated index no longer " \
                                         "matches the entries. Run: ruby scripts/reindex_findings.rb"
    end

    it "indexes every entry, so the table cannot silently omit one" do
      require_relative "../../../scripts/reindex_findings"

      body = File.read(ReindexFindings::PATH, encoding: "UTF-8")
      headings = body.scan(/^## (024\.[0-9R]+)/).flatten
      indexed = body.scan(/^\| \[`(024\.[0-9R]+)`\]/).flatten

      expect(indexed).to eq(headings)
    end
  end

  def read_utf8(name) = File.read(File.expand_path("../../../#{name}", __dir__), encoding: "UTF-8")

  let(:deferred) { read_utf8("docs/design/tasks/024-deferred-review-findings.md") }
  let(:english) { read_utf8("docs/KNOWN_LIMITATIONS.md") }
  let(:japanese) { read_utf8("docs/KNOWN_LIMITATIONS.ja.md") }

  describe "the format, against inputs the real file does not contain" do
    def entry(number, **fields)
      body = fields.map { |k, v| "#{k.to_s.tr("_", "-")}: #{v}" }.join("\n")
      "## #{number} A finding\n\n```yaml\n#{body}\n```\n\nprose\n\n"
    end

    it "reads an entry's fields" do
      parsed = DeferredFindings.entries(entry("024.30", status: "open", kind: "defect"))

      expect(parsed).to eq("024.30" => { "status" => "open", "kind" => "defect" })
    end

    it "reports an open defect" do
      expect(DeferredFindings.open_defects(entry("024.30", status: "open", kind: "defect")).keys).to eq(["024.30"])
    end

    # Each of these must be the *excluding* case, or it cannot tell a
    # working rule from one that answers the same either way.
    it "excludes a resolved entry" do
      expect(DeferredFindings.open_defects(entry("024.30", status: "fixed", kind: "defect"))).to be_empty
      expect(DeferredFindings.open_defects(entry("024.30", status: "done", kind: "defect"))).to be_empty
    end

    it "excludes a roadmap entry, which the roadmap documents instead" do
      expect(DeferredFindings.open_defects(entry("024.R9", status: "open", kind: "roadmap"))).to be_empty
    end

    # An unknown status word is not resolved, so it stays open. Failing
    # loudly beats a typo quietly retiring an entry.
    it "treats an unrecognised status as open" do
      expect(DeferredFindings.open_defects(entry("024.30", status: "deferred", kind: "defect")).keys).to eq(["024.30"])
    end

    # Both readers have to agree about what a number looks like. If
    # `headings` recognised fewer than `entries` did, "parses every entry"
    # would compare two different sets and pass while an entry went
    # unchecked -- which is the failure this whole guard replaces.
    it "reads a sub-numbered entry as itself, in both readers" do
      markdown = entry("024.30.1", status: "open", kind: "defect")

      expect(DeferredFindings.entries(markdown).keys).to eq(["024.30.1"])
      expect(DeferredFindings.headings(markdown)).to eq(["024.30.1"])
    end

    it "requires the marker to end where the number ends" do
      expect(DeferredFindings.documents?("a limitation <!-- documents: 024.13 -->", "024.1")).to be(false)
      expect(DeferredFindings.documents?("a limitation <!-- documents: 024.21.1 -->", "024.21")).to be(false)
      expect(DeferredFindings.documents?("a limitation <!-- documents: 024.13 -->", "024.13")).to be(true)
    end

    # `.` is a regex metacharacter: unescaped, `024.13` matches `024x13`.
    it "matches the number literally rather than as a pattern" do
      expect(DeferredFindings.documents?("a limitation <!-- documents: 024x13 -->", "024.13")).to be(false)
    end

    # The distinction the whole guard turns on, and the one its previous
    # form could not make.
    it "does not accept the number occurring in prose" do
      expect(DeferredFindings.documents?("blocked by 024.13, still open", "024.13")).to be(false)
    end

    it "does not accept a marker with no prose in front of it" do
      expect(DeferredFindings.documents?("<!-- documents: 024.13 -->\n\nsomething else", "024.13")).to be(false)
      expect(DeferredFindings.documents?("  <!-- documents: 024.13 -->", "024.13")).to be(false)
    end

    it "does not accept two markers for one number" do
      markdown = "one place <!-- documents: 024.13 -->\n\nand another <!-- documents: 024.13 -->\n"

      expect(DeferredFindings.documents?(markdown, "024.13")).to be(false)
    end

    it "excludes an entry that declares no user-visible half" do
      opted_out = entry("024.30", status: "open", kind: "defect", user_visible: "no")

      expect(DeferredFindings.undocumented(opted_out, "no citations here")).to be_empty
      expect(DeferredFindings.undocumented(entry("024.30", status: "open", kind: "defect"), "none")).to eq(["024.30"])
    end

    # Each half stated with the case that must *fail*, or it cannot tell a
    # working rule from one that answers the same either way.
    it "reports a resolved entry that is still cited as a limitation" do
      markdown = entry("024.30", status: "fixed", kind: "defect")

      expect(DeferredFindings.wrongly_documented(markdown, "still broken <!-- documents: 024.30 -->")).to eq(["024.30"])
      expect(DeferredFindings.wrongly_documented(markdown, "no mention")).to be_empty
    end

    it "does not report an open entry as wrongly cited" do
      markdown = entry("024.30", status: "open", kind: "defect")

      expect(DeferredFindings.wrongly_documented(markdown, "a limitation <!-- documents: 024.30 -->")).to be_empty
    end

    it "requires every named document to cite the entry, not just one" do
      markdown = entry("024.30", status: "open", kind: "defect")

      expect(DeferredFindings.undocumented(markdown, "x <!-- documents: 024.30 -->", "y <!-- documents: 024.30 -->")).to be_empty
      expect(DeferredFindings.undocumented(markdown, "x <!-- documents: 024.30 -->", "nothing")).to eq(["024.30"])
    end
  end

  describe "the real file" do
    # The failure the previous guard had: a heading it could not parse was
    # skipped rather than reported, so an entry could exist and never be
    # checked.
    it "parses every entry" do
      parsed = DeferredFindings.entries(deferred).keys
      missing = DeferredFindings.headings(deferred) - parsed

      expect(missing).to be_empty,
                         "entries with no `yaml` metadata block: #{missing.join(", ")}. " \
                         "Every `## 024.N` heading needs one, directly beneath it."
    end

    # `entries` builds a Hash, so a reused number keeps the *last* entry
    # and discards the first silently -- and `parses every entry` cannot
    # see it either, because subtracting the parsed keys from the headings
    # leaves nothing when the duplicate is the same string twice. The
    # discarded entry's `status`/`user-visible` are then checked by
    # nothing, and the day either number is cited in `KNOWN_LIMITATIONS`
    # the citation guards answer from the wrong entry.
    #
    # The 0.2.4-bound branch's round 37, after two entries were appended
    # as 024.60 by a renumber that read the register's highest number
    # before a merge added another. Reading the file is what failed; a
    # check is what does not.
    it "gives every entry a number of its own" do
      duplicated = DeferredFindings.headings(deferred).tally.select { |_, count| count > 1 }

      expect(duplicated.keys).to be_empty,
                                 "reused entry numbers: #{duplicated.keys.join(", ")}. " \
                                 "A number keyed twice means one entry's metadata is never read."
    end

    it "finds the open defects it is meant to guard" do
      expect(DeferredFindings.open_defects(deferred)).not_to be_empty
    end

    it "states a status and a kind for every entry" do
      incomplete = DeferredFindings.entries(deferred).reject do |_, fields|
        fields["status"] && fields["kind"]
      end

      expect(incomplete.keys).to be_empty
    end

    it "gives a reason with every `user-visible: no`" do
      unexplained = DeferredFindings.entries(deferred).select do |_, fields|
        fields["user-visible"] == "no" && fields["user-visible-note"].to_s.strip.empty?
      end

      expect(unexplained.keys).to be_empty,
                                  "declared not user-visible without saying why: #{unexplained.keys.join(", ")}"
    end

    it "documents every open defect in both languages" do
      missing = DeferredFindings.undocumented(deferred, english, japanese)

      expect(missing).to be_empty,
                         "open findings absent from KNOWN_LIMITATIONS: #{missing.join(", ")}. " \
                         "Document the user-visible half in both languages, or declare " \
                         "`user-visible: no` with a `user-visible-note` saying why."
    end

    it "stops documenting a finding once it is fixed" do
      stale = DeferredFindings.wrongly_documented(deferred, english, japanese)

      expect(stale).to be_empty,
                       "findings recorded as fixed but still published as current limitations: " \
                       "#{stale.join(", ")}. Remove the paragraph, in both languages -- a limitation " \
                       "naming a defect the release does not have is worse than none."
    end
  end
end
