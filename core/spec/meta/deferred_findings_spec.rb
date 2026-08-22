# frozen_string_literal: true

# `046`'s C4. The register's grammar lives in `scripts/deferred_findings.rb`
# and is read from there by both this guard and `scripts/reindex_findings.rb`.
#
# It used to live here, and `reindex_findings.rb` -- which renders the
# index every reader navigates by -- had a second, hand-rolled
# `key: value` scanner of its own, under a comment saying "the yaml block
# is this file's own grammar rather than real YAML". That was true when
# it was written and stopped being true in 0.2.12, when `024.68` replaced
# the scanner on this side with `YAML.safe_load`. The two then disagreed:
# a quoted `status: "fixed"` renders in the index as `"fixed"` while
# every check here reads `fixed`.
#
# One text, one parser. `CLAUDE.md`'s countermeasure shape -- two
# scanners that had to agree, replaced by one both read.
require_relative "../../../scripts/deferred_findings"

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
  RESOLVED_STATUSES = %w[fixed done].freeze

  describe "the register stays findable" do
    it "is in numeric order with its index current" do
      require_relative "../../../scripts/reindex_findings"

      current = File.read(ReindexFindings::PATH, encoding: "UTF-8")

      expect(ReindexFindings.rebuild).to eq(current),
                                         "the register is out of numeric order, or its generated index no longer " \
                                         "matches the entries. Run: ruby scripts/reindex_findings.rb"
    end

    # A scripted edit doubled `024.69`'s entire body during 0.2.14 -- a
    # `String#find` that returned -1 when its terminator was absent, so a
    # slice meant to end at a paragraph ran to the end of the entry and
    # the "removal" pasted the block back. The file stayed well-formed:
    # heading count unchanged, index current, yaml parsed, every other
    # example green, and it was committed. It was noticed only because an
    # unrelated grep printed the same line at two line numbers.
    #
    # Nothing here could see it, because every check was about an entry's
    # *metadata*. This one is about its body: an entry states its Area
    # once, so twice means a block was pasted rather than moved.
    it "states each entry's Area exactly once, so a doubled body cannot pass" do
      require_relative "../../../scripts/reindex_findings"

      body = File.read(ReindexFindings::PATH, encoding: "UTF-8")
      kinds = DeferredFindings.entries(body).transform_values { |f| f["kind"] }
      doubled = body.split(/^## (?=024\.[0-9R]+ )/).filter_map do |chunk|
        number = chunk[/\A(024\.[0-9R]+) /, 1]
        next unless number
        # A roadmap entry describes a plan, not a place, and legitimately
        # names no Area. A defect or a friction always has one: it is
        # where to go and look.
        next if kinds[number] == "roadmap"

        # `!= 1`, not `> 1`. Zero passed until round 2 attacked it, so
        # "every entry states one Area" was enforced only against saying
        # it twice -- and deleting the line entirely was invisible, which
        # is the cheaper mutation of the two, and which two entries had
        # actually done.
        count = chunk.scan(/^\*\*Area:\*\*/).length
        "#{number} (#{count} Area lines)" if count != 1
      end

      expect(doubled).to be_empty,
                         "entries not stating exactly one Area: #{doubled.join(", ")}. " \
                         "A defect or friction states one — twice means a block was duplicated, " \
                         "none means there is nowhere to go and look."
    end

    # `046`'s C4. The index and the checks must read one entry the same
    # way. They did not between 0.2.12 and 0.2.14: `reindex_findings.rb`
    # kept a hand-rolled `key: value` scanner while this side moved to
    # yaml, and a quoted value rendered with its quotes in the index and
    # without them everywhere else.
    #
    # A quoted status is the cheapest shape that distinguishes them, and
    # it is written into a synthetic entry rather than the register so
    # the example proves the *parser* agrees rather than that this
    # particular file happens to contain no quotes.
    it "renders the index from the same reading the checks make" do
      require_relative "../../../scripts/reindex_findings"

      # Assembled, never spelled: `measured_claims_spec` requires every
      # register number in tracked content to resolve to an entry, and a
      # synthetic one written whole would be a dangling pointer in the
      # file that tests the register. `024.126`'s rule -- make the
      # example unspellable rather than exempt the file.
      number = ["024", "999"].join(".")
      entry = <<~MD
        ## #{number} A synthetic entry with a quoted status

        ```yaml
        status: "fixed"
        kind: defect
        user-visible: no
        user-visible-note: >
          Synthetic.
        target: 0.2.14
        ```
      MD

      expect(ReindexFindings.metadata_of(entry)).to eq(DeferredFindings.entries(entry).fetch(number))
      expect(ReindexFindings.metadata_of(entry)["status"]).to eq("fixed")
    end

    # `024.153`. `target:` was optional, so "nobody has decided" and
    # "deliberately unscheduled" were the same value — the absence of a
    # key, which carries no argument and which no check could read.
    # Measured before the rule: 26 open entries in no release, 18 of them
    # user-visible and published as limitations with no one undertaking
    # to fix them.
    #
    # `unscheduled` is a legal target and is the point of the rule: it
    # says so in a value, with the reason in the entry's body, which a
    # reader can disagree with. An absent key cannot be disagreed with.
    it "gives every open entry a release, so a queue cannot form in the gaps" do
      untargeted = DeferredFindings.entries(deferred)
                                   .reject { |_, f| RESOLVED_STATUSES.include?(f["status"]) }
                                   .reject { |_, f| f["target"].to_s != "" }
                                   .keys

      expect(untargeted).to be_empty,
                            "open entries with no `target:`: #{untargeted.join(", ")}. " \
                            "Name the release that will fix it, or write `target: unscheduled` " \
                            "and say why in the entry."
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
  # **Built, not substituted.** These used to plant by replacing the
  # first `target: 0.3.0` in the real register, which silently depended
  # on that occurrence belonging to an *open* entry. 0.2.14's retargeting
  # made the first one a resolved entry, and the example stopped
  # distinguishing anything while still passing its own description --
  # `CLAUDE.md`'s "a fixture that cannot distinguish the two candidate
  # behaviours" arriving in the spec written to catch a stale target.
  def entry_with(target:, status: "open")
    <<~MD
      ## #{unspellable_number(997)} A synthetic entry

      ```yaml
      status: #{status}
      kind: defect
      user-visible: no
      user-visible-note: >
        Synthetic.
      target: #{target}
      ```

      **Area:** `core/lib`
    MD
  end

  it "notices an open entry planted on a shipped release" do
    planted = deferred + "\n" + entry_with(target: "0.2.13")

    expect(DeferredFindings.open_entries_targeting_a_shipped_release(planted, artifacts))
      .to include(a_string_including("0.2.13"))
  end

  it "leaves an open entry targeting a release that has not shipped alone" do
    planted = deferred + "\n" + entry_with(target: "9.9.9")

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
