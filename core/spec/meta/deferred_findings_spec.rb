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
# Two rules follow from that history and are load-bearing:
#
# - **An entry with no block is a failure, not a skip.** The old guard
#   silently dropped a heading it did not recognise, so an entry could be
#   added and never checked. `parses every entry` compares the block count
#   to the heading count for exactly that reason.
# - **The opt-out must say why.** The old guard documented that
#   requirement in three places and enforced it nowhere.
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
                          .reject { |number| documents.all? { |doc| cited?(doc, number) } }
  end

  # A citation ends where the number ends: `include?("024.1")` is true of
  # a document that only ever mentions `024.13`. The optional dot keeps
  # `024.21.1` from citing `024.21` while still allowing a sentence to end
  # "...recorded as 024.13."
  def cited?(document, number) = document.match?(/#{Regexp.escape(number)}(?!\.?\d)/)
end

RSpec.describe "deferred findings metadata" do
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

    it "requires the citation to end where the number ends" do
      expect(DeferredFindings.cited?("recorded as 024.13 and 024.14", "024.1")).to be(false)
      expect(DeferredFindings.cited?("see 024.21.1", "024.21")).to be(false)
      expect(DeferredFindings.cited?("recorded as 024.13.", "024.13")).to be(true)
    end

    # `.` is a regex metacharacter: unescaped, `024.13` matches `024x13`.
    it "matches a citation literally rather than as a pattern" do
      expect(DeferredFindings.cited?("see 024x13 here", "024.13")).to be(false)
    end

    it "excludes an entry that declares no user-visible half" do
      opted_out = entry("024.30", status: "open", kind: "defect", user_visible: "no")

      expect(DeferredFindings.undocumented(opted_out, "no citations here")).to be_empty
      expect(DeferredFindings.undocumented(entry("024.30", status: "open", kind: "defect"), "none")).to eq(["024.30"])
    end

    it "requires every named document to cite the entry, not just one" do
      markdown = entry("024.30", status: "open", kind: "defect")

      expect(DeferredFindings.undocumented(markdown, "024.30", "024.30")).to be_empty
      expect(DeferredFindings.undocumented(markdown, "024.30", "nothing")).to eq(["024.30"])
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
  end
end
