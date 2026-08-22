# frozen_string_literal: true

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
  let(:artifacts) { read_utf8("docs/RELEASE_ARTIFACTS.md") }
  let(:english) { read_utf8("docs/KNOWN_LIMITATIONS.md") }
  let(:japanese) { read_utf8("docs/KNOWN_LIMITATIONS.ja.md") }

  describe "the format, against inputs the real file does not contain" do
    def entry(number, **fields)
      body = fields.map { |k, v| "#{k.to_s.tr("_", "-")}: #{v}" }.join("\n")
      "## #{number} A finding\n\n```yaml\n#{body}\n```\n\nprose\n\n"
    end

    # **`024.68`. Three guards were bolted onto the hand-rolled grammar
    # and each was broken by the next round, one assumption deeper: a
    # `KNOWN_KEYS` filter blind outside its own `[a-z-]` class, a
    # stray-line check that skipped every indented line, and a third
    # that the fourth round got round again.
    #
    # This is not a fourth guard. The block is `yaml`, so it is parsed as
    # yaml and its keys are checked against the set the legend defines --
    # `Target:` and `user_visible:` are then keys like any other, and
    # unknown ones fail. The grammar the guards were guarding is gone.
    it "refuses a key the legend does not define, whatever its case" do
      planted = entry("024.30", status: "open", kind: "defect") .sub("status:", "Target:")

      expect { DeferredFindings.entries(planted) }
        .to raise_error(DeferredFindings::UnknownKey, /Target/)
    end

    it "refuses an underscored spelling of a hyphenated key" do
      planted = "## 024.30 A finding\n\n```yaml\nstatus: open\nkind: defect\nuser_visible: yes\n```\n\nprose\n\n"

      expect { DeferredFindings.entries(planted) }
        .to raise_error(DeferredFindings::UnknownKey, /user_visible/)
    end

    # The one the round-11 guard skipped as "the folded note's
    # continuation". A real parser cannot skip it: it is a nested key.
    it "refuses a key indented under another" do
      planted = "## 024.30 A finding\n\n```yaml\nstatus: open\nkind: defect\n  target: 0.2.4\n```\n\nprose\n\n"

      expect { DeferredFindings.entries(planted) }
        .to raise_error(DeferredFindings::UnknownKey, /target|mapping|scan/i)
    end

    # And the control: the real file parses, so the rule is not "refuse
    # everything".
    it "accepts every key the real register uses" do
      expect { DeferredFindings.entries(deferred) }.not_to raise_error
    end

    # A kind the legend does not define routes an entry out of every check
    # that filters on kind: `open_defects` reads `kind == "defect"`, so
    # `kind: defct` makes an open user-visible defect invisible to the
    # KNOWN_LIMITATIONS guard while the suite stays green.
    it "refuses a kind the legend does not define" do
      planted = entry("024.30", status: "open", kind: "defct")

      expect { DeferredFindings.entries(planted) }
        .to raise_error(DeferredFindings::UnknownKey, /defct/)
    end

    it "accepts friction, which is a kind the legend defines" do
      parsed = DeferredFindings.entries(entry("024.30", status: "open", kind: "friction"))

      expect(parsed["024.30"]["kind"]).to eq("friction")
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
  # `024.124`. Three releases in a row inherited entries naming a version
  # that had already shipped -- 0.2.9's preparation found three, 0.2.12's
  # found four, and 0.2.13's found four more, each time fixed by hand.
  #
  # Not "fail on any shipped target": an entry legitimately names a
  # release for the whole time that release is being prepared, and the
  # value only becomes wrong once the tag exists. So the comparison is
  # against `RELEASE_ARTIFACTS.md`, which lists what was actually
  # published, and only *open* entries are checked -- a fixed one keeps
  # its target as history, which is what `released-in:` sits beside it
  # for.
  # The distinguishing pair: it must fire, and it must not fire on an
  # entry whose target is a release still being prepared.
  it "notices an open entry planted on a shipped release" do
    planted = deferred.sub("target: 0.3.0", "target: 0.2.13")

    expect(DeferredFindings.open_entries_targeting_a_shipped_release(planted, artifacts)).not_to be_empty
  end

  it "leaves an open entry targeting a release that has not shipped alone" do
    planted = deferred.sub("target: 0.3.0", "target: 9.9.9")

    expect(DeferredFindings.open_entries_targeting_a_shipped_release(planted, artifacts))
      .not_to include(a_string_including("9.9.9"))
  end

  it "has no open entry naming a release that has already shipped" do
    stale = DeferredFindings.open_entries_targeting_a_shipped_release(deferred, artifacts)

    expect(stale).to be_empty,
                     "open findings targeting a released version: #{stale.join(", ")}. " \
                     "Retarget them at a release that has not shipped, or mark them fixed."
  end
  # `046`'s C3. An open entry's `**Area:**` is the first thing whoever
  # picks it up will open, and nothing checked that those paths exist.
  # `024.87` -- open and user-visible -- named
  # `semantic/built_in_generic_rules.rb`, which has never been committed;
  # the real file is `semantic/generic_rule_registry.rb`.
  #
  # Open entries only. A resolved entry's Area is history and may name a
  # file that has since been renamed or deleted, which is the ordinary
  # outcome of fixing something.
  it "names only paths that exist, in every open entry's Area" do
    open_numbers = DeferredFindings.open_defects(deferred).keys
    areas = DeferredFindings.area_paths(deferred)
    root = File.expand_path("../../..", __dir__)

    missing = open_numbers.flat_map do |number|
      areas.fetch(number, []).reject { |path| File.exist?(File.join(root, path)) }
           .map { |path| "#{number}: #{path}" }
    end

    expect(missing).to be_empty,
                       "open entries whose Area names a path that does not exist: #{missing.join(", ")}. " \
                       "That path is the first thing whoever picks the entry up will open."
  end
end
