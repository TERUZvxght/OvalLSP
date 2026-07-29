# frozen_string_literal: true

# The roadmap restates README's capability matrix in the user's terms, so
# it is a second copy of the same list -- and a second copy with nothing
# enforcing correspondence is how a plan quietly starts promising a
# different product than the matrix does.
#
# Same guard as the capability tables and the changelog pair, for the same
# reason. Read with an explicit encoding, never the locale's: the Japanese
# files are almost entirely non-ASCII, and under a C/POSIX locale
# `File.read` hands back US-ASCII and every scan raises.
RSpec.describe "roadmap parity" do
  ROADMAP_EN = File.expand_path("../../../docs/ROADMAP.md", __dir__)
  ROADMAP_JA = File.expand_path("../../../docs/ROADMAP.ja.md", __dir__)
  README_EN = File.expand_path("../../../README.md", __dir__)

  def read_utf8(path) = File.read(path, encoding: "UTF-8")

  # A matrix row whose first column is a version is a planned capability;
  # `| … | 0.3.0 | …`.
  def planned_rows
    read_utf8(README_EN).scan(/^\| (.+?) \| (\d+\.\d+\.\d+) \|/).map(&:last)
  end

  # `## 0.2.0 — …` followed by its top-level bullets.
  def roadmap_sections(path)
    read_utf8(path).split(/^## /)[1..].to_h do |section|
      [section[/\A\d+\.\d+\.\d+/], section.lines.count { |line| line.start_with?("- ") }]
    end
  end

  it "gives every version README plans for its own section" do
    expect(roadmap_sections(ROADMAP_EN).keys).to include(*planned_rows.uniq)
  end

  it "lists as many items per version as README has rows for it" do
    expected = planned_rows.tally
    actual = roadmap_sections(ROADMAP_EN).slice(*expected.keys)

    expect(actual).to eq(expected)
  end

  it "plans the same versions, with the same number of items, in both languages" do
    expect(roadmap_sections(ROADMAP_JA)).to eq(roadmap_sections(ROADMAP_EN))
  end

  it "links each language's roadmap to the other" do
    expect(read_utf8(ROADMAP_EN)).to include("ROADMAP.ja.md")
    expect(read_utf8(ROADMAP_JA)).to include("ROADMAP.md")
  end
end
