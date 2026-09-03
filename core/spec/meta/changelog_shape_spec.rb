# frozen_string_literal: true

require "json"
require_relative "../../../scripts/changelog"

# **The shape of a release's changelog entry, against inputs the real
# files do not contain.**
#
# `changelog_parity_spec.rb` reads the two real files and asks whether
# they agree. What it cannot do is fail on a shape nobody has written
# yet, and what it cannot do *at all* is judge the release being
# prepared: it asserts the newest section names `Ovallsp::VERSION`, which
# is true only after the version has been bumped — so the moment a person
# most needs to be told the changelog is wrong is the one moment nothing
# is watching.
#
# So the shape lives in `scripts/changelog.rb`, this drives it against
# planted deviations, and `scripts/check_changelog.rb` asks it about a
# version that has not been bumped yet. One implementation, three
# callers — the countermeasure shape `docs/REVIEW_LOOP.md` prescribes for
# two readers of one text.
RSpec.describe "the shape of a changelog entry" do
  CHANGELOG_SHAPE_ROOT = File.expand_path("../../..", __dir__)

  # Versions that cannot be confused with a release this project has cut.
  def prepared = "9.9.9"

  def older = "9.9.8"

  def english(version: prepared, bullets: 2, details: "### Details", extra: "")
    section(version, "what changed", bullets, details, extra)
  end

  def japanese(version: prepared, bullets: 2, details: "### 詳細", extra: "")
    section(version, "変わったこと", bullets, details, extra)
  end

  def section(version, headline, bullets, details, extra)
    body = Array.new(bullets) { |n| "- **Item #{n + 1}.** What a reader would meet.\n" }.join
    "# Changelog\n\n## #{version} — #{headline}\n\n#{body}\n#{details}\n\nWhy it was done.\n#{extra}"
  end

  def complain(en, ja, expected = prepared) = Changelog.complaints(en, ja, expected)

  # **The control, and it goes first.** Every example below asserts that
  # something is reported, and a checker that reported everything would
  # satisfy all of them.
  it "reports nothing about a section in the shape both files use" do
    expect(complain(english, japanese)).to be_empty
  end

  it "reports a newest section that is not the version being prepared" do
    expect(complain(english(version: older), japanese(version: older)))
      .to include(a_string_matching(/#{older}.*#{prepared}/))
  end

  it "reports the two languages naming different versions" do
    expect(complain(english, japanese(version: older))).not_to be_empty
  end

  # `024.130`'s shape, in the file a user reads on the Marketplace: one
  # language told something the other was not. The count is what a
  # machine can see, and a dropped bullet is how this pair has actually
  # gone wrong (0.1.12, round 4).
  it "reports the two languages leading with a different number of bullets" do
    expect(complain(english(bullets: 3), japanese(bullets: 2)))
      .to include(a_string_matching(/bullet/i))
  end

  it "reports a section that leads with prose instead of bullets" do
    expect(complain(english(bullets: 0), japanese(bullets: 0)))
      .to include(a_string_matching(/bullet/i))
  end

  it "reports a section with no reasoning under it" do
    plain = "# Changelog\n\n## #{prepared} — what changed\n\n- **Item 1.** What a reader would meet.\n"

    expect(complain(plain, plain)).to include(a_string_matching(/Details/))
  end

  # The Japanese file puts the reasoning under its own heading, so
  # checking for the English one there would pass on a translation that
  # had quietly stopped translating.
  it "reports the Japanese section using the English heading for its reasoning" do
    expect(complain(english, japanese(details: "### Details")))
      .to include(a_string_matching(/詳細/))
  end

  it "reports a file with no release section at all" do
    expect(complain("# Changelog\n\nNothing yet.\n", japanese)).not_to be_empty
  end

  # **And the real files, at the version this build ships as.** The
  # examples above prove the checker can fail; this one proves it is
  # aimed at something that passes, which is the half a planted fixture
  # can never show.
  it "reports nothing about the changelogs this repository ships" do
    en = File.read(File.join(CHANGELOG_SHAPE_ROOT, Changelog::EN), encoding: "UTF-8")
    ja = File.read(File.join(CHANGELOG_SHAPE_ROOT, Changelog::JA), encoding: "UTF-8")

    expect(Changelog.complaints(en, ja, Ovallsp::VERSION)).to be_empty
  end

  # The shape applies to the newest section only. Everything below it was
  # written under whatever convention held at the time, and rewriting a
  # published release's notes to satisfy a check written afterwards would
  # be changing what shipped.
  it "says nothing about the sections below the newest one" do
    trailing = "\n## #{older} — an older release\n\nProse, no bullets, no reasoning heading.\n"

    expect(complain(english(extra: trailing), japanese(extra: trailing))).to be_empty
  end
end
