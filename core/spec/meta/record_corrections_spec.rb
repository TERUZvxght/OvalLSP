# frozen_string_literal: true

# A record defect fixed by editing a document leaves nothing behind that
# would fail if it came back. These are the regressions for the ones
# `024.276`'s re-triage repaired rather than relabelled.
#
# One file, one example per entry, because the alternative is a spec file
# per corrected paragraph and the alternative to *that* is no test at
# all -- which is how the corrections in `046` came to state work they
# had not done.
#
# **Needles are assembled rather than spelled.** `024.126`: a spec is
# tracked content, so a phrase written here the way the document writes
# it is a second copy of exactly the text some future scanner is hunting.
# Nothing contiguous survives in the source.
RSpec.describe "corrections that stay corrected" do
  # Namespaced: a constant written inside `RSpec.describe` lands on
  # Object, and the file that loads last silently gives its value to the
  # other one. Written as a bare `ROOT` first, and `spec_constants_spec`
  # caught it -- this file then read its paths relative to `core/`.
  RECORD_ROOT = File.expand_path("../../..", __dir__)

  def read(*parts) = File.read(File.join(RECORD_ROOT, *parts), encoding: "UTF-8")

  # Whitespace-flattened: `024.161` hid from its own first grep because
  # the phrase spans a line break in the document and not in the entry.
  def flat(text) = text.gsub(/\s+/, " ")

  describe "046, the release whose subject is making the record true" do
    let(:record) { read("docs", "design", "tasks", "046-0.2.14-making-the-record-true.md") }

    # `024.161`. A round-3 correction closed with the phrase "is not what
    # the diff shows and is removed". It was not removed: it was still
    # the document's closing clause, so the file asserted both a false
    # thing about its own change set and that the assertion was gone.
    it "does not still carry the closing phrase its own correction says was removed" do
      needle = ["4,000 lines", "of revert"].join(" ")

      expect(flat(record).scan(needle).length).to eq(1),
                                                  "the phrase appears #{flat(record).scan(needle).length} times. " \
                                                  "One is the correction that says it was removed; a second is the " \
                                                  "phrase itself, still there (024.161)."
    end

    # `024.165`. The 138 unticked acceptance boxes are kept, and the
    # reason given was that no box has ever been ticked here. Boxes are
    # ticked in ten task files, thirteen of them inside the stated range.
    # The decision stands; the reason had to go.
    #
    # The needle is the *bullet*, not the sentence. Two of this file's
    # own findings quote the false claim in order to report it, which is
    # what they are for -- an example that hunted the bare sentence
    # would fail on the record of the defect it exists to keep fixed.
    it "does not keep the acceptance boxes on a reason that is false" do
      justification = ["in tasks 001\u2013022.** No box", "has ever been ticked"].join(" ")

      expect(flat(record)).not_to include(justification),
                                  "the justification 046 gives for keeping 138 unticked boxes is a fact that " \
                                  "is false, in a file this change set edited (024.165)."
    end

    # And the control for the example above: the decision it justifies is
    # still recorded. Without this, deleting the whole bullet would pass.
    it "still records the decision that reason was given for" do
      expect(flat(record)).to include("unticked acceptance boxes in tasks")
    end

    # `024.163`. The round-2 header asserted that every attacker worked
    # in a clone or reverted and the tree was verified clean afterwards,
    # while four findings recorded in the same document said the tree was
    # dirty and changing throughout. Corrected before 0.2.15 and carried
    # as open for two releases after that -- including through a closing
    # pass that said it still reproduced.
    it "does not assert the round-2 tree was clean, which its own findings deny" do
      # The needle is the header's own opening clause, not the sentence
      # it made: the corrected header quotes that sentence in order to
      # say it was wrong, and a round-3 finding quotes it to report it.
      # Both are the record working.
      claim = ["Every attacker worked in", "a clone or reverted"].join(" ")

      header = flat(record)[/### Round 2.*?### Round 3/m].to_s

      expect(header).not_to include(claim)
      expect(header).to include("The working tree was dirty for almost all of this round")
    end
  end

  # `024.196`. One measurement -- what a fully skipped suite reports --
  # was quoted in three places as a specific example count, attributed to
  # a different file each time, and matched none of them: the figure
  # named `real_rails_spec.rb` in one, belonged to the e2e suite in
  # another, and named no file at all in the third. Both suites had since
  # moved.
  #
  # The argument does not need a number, so none of the three carries one
  # now. This is the regression: a frozen count about a suite's size is
  # a claim about this tree, and the three places that make it are not
  # where a claim can be re-derived.
  describe "051, the release record whose own claim 024.276 disproved" do
    let(:record) { read("docs", "design", "tasks", "051-0.2.16-shipped.md") }

    # `024.276`. That entry's Area names three files, and this is the one
    # that was never edited: `051` says twice that every entry naming
    # 0.2.16 was retargeted with a reason of its own, taken from the
    # release's own measurements. `024.276` counted them -- 53 of 54
    # carried one of exactly two byte-identical paragraphs, and driving
    # them found one entry fixed two releases earlier, one contradicting
    # its own Direction a paragraph above, and one that was wrong when
    # written.
    #
    # Found in 0.2.18 by asking whether the 0.2.x line was really closed,
    # rather than by a reviewer -- which is why it is pinned here and not
    # only corrected: an entry marked `fixed` whose own Area still
    # carries the disproved claim is the shape this file exists for.
    #
    # Needle assembled, per this file's header.
    it "does not still assert every retarget carried a reason of its own" do
      needle = %w[retargeted with a reason].join(" ")
      corrected = flat(record)

      expect(corrected).to include("024.276"),
                           "051 makes the claim 024.276 disproved and does not cite it; " \
                           "the correction has been reverted or was never applied."
      expect(corrected.scan(needle).length).to be <= 1,
                                                "the claim appears #{corrected.scan(needle).length} times. " \
                                                "024.276 established it was false of 53 of 54 entries."
    end
  end

  describe "the argument for reading per-example status" do
    let(:sources) do
      { "scripts/preflight.rb" => read("scripts", "preflight.rb"),
        "scripts/check_suites_ran.rb" => read("scripts", "check_suites_ran.rb"),
        "CLAUDE.md" => read("CLAUDE.md") }
    end

    it "quotes no frozen example count" do
      frozen = ["45", "examples"].join(" ")
      carrying = sources.select { |_, text| flat(text).include?(frozen) }.keys

      expect(carrying).to be_empty,
                          "#{carrying.join(', ')} still quote a specific example count for a skipped " \
                          "suite. Both suites it was attributed to have moved since it was written."
    end

    # The control: each still makes the argument, so deleting the
    # paragraph is not how this passes.
    it "still makes the argument the count was standing in for" do
      # A needle that fits on one line of each: two of the three are Ruby
      # comments, so flattening leaves the `#` between wrapped lines.
      sources.each do |name, text|
        expect(flat(text)).to include("example is still an example"), name
      end
    end
  end
end
