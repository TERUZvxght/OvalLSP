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
end
