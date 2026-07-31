# frozen_string_literal: true

# `vscode/PRIVACY.md` and `PRIVACY.ja.md` are the single source of truth
# for what the extension records and what it writes to disk, and both ship
# in the VSIX -- a Japanese Marketplace reader sees only the second.
#
# This guard exists because 0.1.12 corrected a false claim ("nothing is
# written to disk beyond the parse cache") in the English file and not the
# Japanese one, leaving the document contradicting itself in one language.
# The changelog pair has had a parity guard since 0.1.6; this pair did not,
# which is precisely why the gap survived review until someone read both.
#
# Read with an explicit encoding, never the locale's: the Japanese file is
# almost entirely non-ASCII, and under a C/POSIX locale `File.read` hands
# back US-ASCII and every scan raises.
RSpec.describe "privacy document parity" do
  PRIVACY_EN = File.expand_path("../../../vscode/PRIVACY.md", __dir__)
  PRIVACY_JA = File.expand_path("../../../vscode/PRIVACY.ja.md", __dir__)

  def read_utf8(path) = File.read(path, encoding: "UTF-8")

  def sections(path) = read_utf8(path).scan(/^## (.+)$/).flatten

  it "documents the same sections, in the same order, in both languages" do
    expect(sections(PRIVACY_JA).size).to eq(sections(PRIVACY_EN).size)
  end

  it "links each language's document to the other" do
    expect(read_utf8(PRIVACY_EN)).to include("PRIVACY.ja.md")
    expect(read_utf8(PRIVACY_JA)).to include("PRIVACY.md")
  end

  # The two claims a reader most needs to be able to trust, and the two
  # that were wrong before 0.1.12. Stated as "if one language says it, so
  # must the other" rather than by matching prose, which no test can do
  # across a translation.
  {
    "the parse cache contains source" => [%r{contains parts\s+of your source code}i, /ソースコードの一部が含まれます/],
    "an observation run writes temporary files" => [%r{two more\s+files|two temporary files}i, /2つのファイル|一時ファイルが2つ/],
    "the test command's own output is redirected there" => [%r{standard output\s+and standard error}i, /標準出力と標準\s*エラー/]
  }.each do |claim, (en_pattern, ja_pattern)|
    it "states in both languages that #{claim}" do
      expect(read_utf8(PRIVACY_EN)).to match(en_pattern)
      expect(read_utf8(PRIVACY_JA)).to match(ja_pattern)
    end
  end

  # Resolved against , where PRIVACY itself lives -- a repo-root
  # README has different headings, and pointing the check at the wrong one
  # makes it fail on links that are fine.
  #
  # A link that goes nowhere in a privacy document is worse than in most
  # places: it is the reader's route to the thing being described.
  it "links only to headings its README actually has" do
    { PRIVACY_EN => "README.md", PRIVACY_JA => "README.ja.md" }.each do |privacy, readme|
      readme_body = read_utf8(File.expand_path("../../../vscode/#{readme}", __dir__))
      headings = readme_body.scan(/^#+ (.+)$/).flatten.map { |h| h.downcase.strip.gsub(/[^\p{Word}\- ]/, "").tr(" ", "-") }

      read_utf8(privacy).scan(/\(#{Regexp.escape(readme)}\#([^)]+)\)/).flatten.each do |anchor|
        expect(headings).to include(anchor), "#{File.basename(privacy)} links #{readme}##{anchor}, which has no such heading"
      end
    end
  end
end
