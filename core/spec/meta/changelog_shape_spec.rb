# frozen_string_literal: true

require "json"
require_relative "../../../scripts/changelog"
require_relative "../../../scripts/check_changelog"

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

  # **A file that opens straight on a release heading.** The split drops
  # everything before the first heading, and a text with nothing before
  # it has no such chunk -- so dropping one unconditionally threw the
  # newest section away. Latent while both real files open with a title,
  # which is exactly the kind of thing that stops being true once.
  it "reads a section from a text that begins with one" do
    body = "## #{prepared} - what changed\n\n- **Item 1.** What a reader would meet.\n\n### Details\n\nWhy.\n"

    expect(Changelog.sections(body).map(&:version)).to eq([prepared])
  end

  it "reports a file with no release section at all" do
    expect(complain("# Changelog\n\nNothing yet.\n", japanese)).not_to be_empty
  end

  # **The release being prepared is what the branch says**, when there is
  # a release branch. `check_changelog.rb` with no `--version` is what
  # preflight runs, and it compared the newest section with
  # `vscode/package.json` -- so from `open` until `bump`, every commit on
  # `release/<v>` failed preflight for writing the entry it was told to
  # write. The branch is the evidence of what is being prepared; the
  # package manifest is the evidence of what was last built.
  describe "which version the newest section is measured against" do
    it "takes it from a release branch, which knows before the manifest does" do
      expect(CheckChangelog.expected_version(nil, "release/#{prepared}", older)).to eq(prepared)
    end

    it "takes it from the manifest anywhere else" do
      expect(CheckChangelog.expected_version(nil, "main", older)).to eq(older)
    end

    it "lets --version override both, for a release prepared off a branch that does not say" do
      expect(CheckChangelog.expected_version(prepared, "main", older)).to eq(prepared)
    end
  end

  # **And the real files, at the version this build ships as.** The
  # examples above prove the checker can fail; this one proves it is
  # aimed at something that passes, which is the half a planted fixture
  # can never show.
  # **Against the version the check would use, not against
  # `Ovallsp::VERSION`.** Between `open` and `bump` the newest section is
  # the release being prepared and `VERSION` is still the one that
  # shipped, so measuring against `VERSION` made this example -- and the
  # parity spec's -- fail on every commit in that window. That is the
  # window `check_changelog.rb --version` exists for, and asking the same
  # question two ways is how the two answers came to disagree.
  it "reports nothing about the changelogs this repository ships" do
    en = File.read(File.join(CHANGELOG_SHAPE_ROOT, Changelog::EN), encoding: "UTF-8")
    ja = File.read(File.join(CHANGELOG_SHAPE_ROOT, Changelog::JA), encoding: "UTF-8")
    expected = CheckChangelog.expected_version(nil, CheckChangelog.branch, Ovallsp::VERSION)

    expect(Changelog.complaints(en, ja, expected)).to be_empty
  end

  # And the composition itself, driven: what the two specs above now do
  # is ask `expected_version` first and `complaints` second, so the pair
  # is pinned rather than each half separately.
  describe "the pair the suite asks" do
    def complaints_on(branch_name)
      Changelog.complaints(english, japanese,
                           CheckChangelog.expected_version(nil, branch_name, older))
    end

    it "says nothing while a release branch carries the section it is preparing" do
      expect(complaints_on("release/#{prepared}")).to be_empty
    end

    it "says so when the same files sit on a branch that names no release" do
      expect(complaints_on("main")).not_to be_empty
    end
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
