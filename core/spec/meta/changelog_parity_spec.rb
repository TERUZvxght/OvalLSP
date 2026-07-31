# frozen_string_literal: true

# The Japanese changelog is a translation, not a second source of truth:
# it must cover exactly the same releases, in the same order.
#
# The same guard the capability tables already have, for the same reason.
# A release entry added to one file and not the other is how a translated
# document quietly starts describing a different product -- and this pair
# is worse than most, because both are shipped inside the VSIX and one of
# them is what a Japanese-reading user sees on the Marketplace page.
RSpec.describe "changelog parity" do
  CHANGELOG_EN = File.expand_path("../../../vscode/CHANGELOG.md", __dir__)
  CHANGELOG_JA = File.expand_path("../../../vscode/CHANGELOG.ja.md", __dir__)

  # Read with an explicit encoding, never the locale's: the Japanese file
  # is entirely non-ASCII, and under a C/POSIX locale `File.read` hands
  # back US-ASCII and every scan raises. That has already broken this
  # project once.
  def versions(path)
    File.read(path, encoding: "UTF-8").scan(/^## (\d+\.\d+\.\d+)/).flatten
  end

  it "documents the same releases in both languages, in the same order" do
    expect(versions(CHANGELOG_JA)).to eq(versions(CHANGELOG_EN))
  end

  it "documents the version this build ships as" do
    expect(versions(CHANGELOG_EN).first).to eq(Ovallsp::VERSION)
  end

  it "links each language's changelog to the other" do
    expect(File.read(CHANGELOG_EN, encoding: "UTF-8")).to include("CHANGELOG.ja.md")
    expect(File.read(CHANGELOG_JA, encoding: "UTF-8")).to include("CHANGELOG.md")
  end

  # A changelog is read to answer "what changed", so every release leads
  # with that, and the reasoning lives under a Details heading below it.
  # Pinned because the natural way to write a release entry is to start
  # explaining, and one entry that does drags the whole file back.
  def releases(path)
    File.read(path, encoding: "UTF-8").split(/^## /)[1..].map { |section| section.split(/^### /).first }
  end

  [["English", CHANGELOG_EN], ["Japanese", CHANGELOG_JA]].each do |language, path|
    it "leads every #{language} release with a bullet list, before any prose section" do
      offenders = releases(path).reject { |summary| summary.lines.any? { |line| line.start_with?("- ") } }

      expect(offenders.map { |s| s.lines.first.strip }).to be_empty
    end
  end

  # Same releases, same headline count. Round 4 of the 0.1.12 review found
  # the Japanese changelog missing a bullet the English one had -- the
  # exact failure this file exists to prevent, and every guard above it
  # passed. A count is not a translation check, but a dropped bullet is
  # the way this file actually goes wrong, and it is the part a machine
  # can see (0.1.12, round 5).
  it "gives every release the same number of headline bullets in both languages" do
    bullets = lambda do |path|
      File.read(path, encoding: "UTF-8").split(/^## /)[1..].to_h do |section|
        summary = section.split(/^### /).first
        [section[/\A(\d+\.\d+\.\d+)/, 1], summary.lines.count { |line| line.start_with?("- ") }]
      end
    end

    expect(bullets.call(CHANGELOG_JA)).to eq(bullets.call(CHANGELOG_EN))
  end

  it "keeps the same releases explained in detail in both languages" do
    detailed = lambda do |path|
      File.read(path, encoding: "UTF-8").split(/^## /)[1..].filter_map do |section|
        section[/\A(\d+\.\d+\.\d+)/, 1] if section.include?("\n### ")
      end
    end

    expect(detailed.call(CHANGELOG_JA)).to eq(detailed.call(CHANGELOG_EN))
  end
end
