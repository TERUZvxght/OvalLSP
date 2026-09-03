# frozen_string_literal: true

require_relative "../../../scripts/check_bodyless_headings"

# **A heading whose body was deleted keeps making the heading's claim**,
# and this project has left one standing three times:
#
#   0.3.0  `024.99` fixed, its section's body removed, heading left
#   0.3.0  `024.86` fixed, the same
#   0.3.2  `024.283` fixed, its body cut and a heading left asserting the
#          packaged extension is only smoke-tested on the platform CI now
#          builds
#
# The reason no check saw them is the shape of the class:
# `deferred_findings_spec`'s "stops documenting a finding once it is
# fixed" matches the `<!-- documents: -->` marker, and that marker is
# *inside the body*. It leaves when the body leaves, and the heading it
# leaves behind is invisible to the guard written for this exact case.
# Two of the three sat in the tree across three releases with preflight
# green over them.
#
# `CLAUDE.md`'s same-place rule says the third instance is where a
# mechanical countermeasure replaces a hand fix, and that a regression
# test for the one instance is not one. `scripts/check_bodyless_headings.rb`
# is the single detector; this file and the preflight gate are the two
# readers of it.
RSpec.describe "scripts/check_bodyless_headings.rb" do
  REPO_ROOT_FOR_BODYLESS_HEADINGS = File.expand_path("../../..", __dir__)

  # **The rule's own teeth.** Without these, a regexp typo or a fence
  # tracker that swallowed the file would report exactly what a clean
  # tree reports -- `024.148`'s shape, and the one this project keeps
  # meeting. Each example is stated with the case that must *fail*, so
  # the pair can tell a working rule from one that answers the same
  # either way.
  describe "the rule" do
    it "reports a heading followed by one of the same level" do
      text = "## First\n\n## Second\n\nbody\n"

      expect(BodylessHeadings.offenders(text).map(&:last)).to eq(["## First"])
    end

    it "accepts a heading whose body is a deeper heading" do
      text = "## Parent\n\n### Child\n\nbody\n"

      expect(BodylessHeadings.offenders(text)).to be_empty
    end

    # Measured, not assumed. The looser rule -- any heading with no text
    # before the next heading -- finds one more thing in this tree than
    # the four real ones, and it is a heading introducing a quoted
    # document that opens with its own level-1 heading. Restricting to
    # the same level drops it without an exemption list.
    it "accepts a heading followed by a shallower one, which is a document boundary" do
      text = "## The original record follows\n\n# A quoted document\n\nbody\n"

      expect(BodylessHeadings.offenders(text)).to be_empty
    end

    it "does not read a heading inside fenced code" do
      text = "## Real\n\n```\n## Not a heading\n## Nor this\n```\n\ntext\n"

      expect(BodylessHeadings.offenders(text)).to be_empty
    end

    it "reports the last heading in a file when the one before it has no body" do
      text = "## Penultimate\n\n## Last\n"

      expect(BodylessHeadings.offenders(text).map(&:last)).to eq(["## Penultimate"])
    end

    # A line of hashes with no text is not a heading in any dialect this
    # tree writes, and treating it as one would make every horizontal
    # rule a finding.
    it "does not treat a bare row of hashes as a heading" do
      text = "##\n\n##\n\nbody\n"

      expect(BodylessHeadings.offenders(text)).to be_empty
    end
  end

  # The census, asserted rather than assumed: this is what tells a clean
  # result from a blind one. `git ls-files` answering nothing would make
  # the example below pass over an unread tree.
  it "is reading the tracked Markdown, not an empty list" do
    paths = BodylessHeadings.tracked_markdown(REPO_ROOT_FOR_BODYLESS_HEADINGS)

    expect(paths.length).to be > 50
    expect(paths).to include("README.md")
  end

  it "finds no heading left standing without a body" do
    paths = BodylessHeadings.tracked_markdown(REPO_ROOT_FOR_BODYLESS_HEADINGS)
    offenders = BodylessHeadings.scan(paths, REPO_ROOT_FOR_BODYLESS_HEADINGS)

    expect(offenders).to be_empty, lambda {
      listed = offenders.map { |path, line, text| "  #{path}:#{line}  #{text}" }.join("\n")
      "headings with no body:\n#{listed}\n" \
        "A heading with nothing under it *is* its claim. If the body went because the thing it " \
        "described is fixed, the heading goes with it; if the section is still owed, write it."
    }
  end
end
