# frozen_string_literal: true

# **`SECURITY.md` and its translation, compared the way `PRIVACY` already
# is.**
#
# `docs/DOCUMENTATION_MAP.md`'s "Anything about the Runtime Agent,
# workspace trust, or what the extension executes" row names four
# documents and has nothing in its "Checked by" column. What that row
# governs is the document a reader consults before deciding whether to
# trust a workspace, and a translation that has quietly lost a section is
# a reader told less about what runs on their machine.
#
# Modelled on `privacy_parity_spec.rb`, which exists for the same reason
# one row above. Structure and the load-bearing claims, never prose: the
# two are translated independently and demanding identical wording buys a
# stricter check by making the translation worse — the argument
# `check_site_links.rb` makes about the site's Japanese.
RSpec.describe "SECURITY.md and SECURITY.ja.md" do
  def repo_root = File.expand_path("../../..", __dir__)

  def english = File.read(File.join(repo_root, "SECURITY.md"), encoding: "UTF-8")

  def japanese = File.read(File.join(repo_root, "SECURITY.ja.md"), encoding: "UTF-8")

  def sections(body) = body.lines.count { |line| line.start_with?("## ") }

  # These documents are hard-wrapped, so a phrase worth matching is
  # almost certainly split across a line. Two versions of the example
  # below failed on that before failing on anything real.
  def flat(body) = body.gsub(/\s+/, " ")

  it "has the same number of sections in each language" do
    expect(sections(japanese)).to eq(sections(english)),
                                  "English has #{sections(english)} sections, Japanese #{sections(japanese)}"
  end

  # The control: the count is of something. A pair of documents with no
  # `## ` headings at all would satisfy the example above and say
  # nothing, which is the shape `check_pinned_mutations.rb` reported on
  # its first run.
  it "is counting real sections" do
    expect(sections(english)).to be >= 2
    expect(english.length).to be > 500
    expect(japanese.length).to be > 500
  end

  # **Where a report goes, which is the one thing here a reader acts on
  # rather than reads.** A translation that sent people somewhere else
  # would be worse than one that reads badly.
  #
  # Two earlier versions of this example were wrong about the document
  # rather than about the document being wrong: the first compared a
  # version token (`0.x`) that the Japanese states without that
  # spelling, and the second looked for an email address or a URL, when
  # the route is GitHub's private vulnerability reporting named in
  # prose. What both languages must carry is the control the reader is
  # told to use.
  it "sends a report down the same route in both languages" do
    route = 'Report a vulnerability'

    expect(flat(english)).to include(route), "SECURITY.md no longer names the reporting control"
    expect(flat(japanese)).to include(route), "SECURITY.ja.md no longer names the reporting control"
    expect(english.downcase).to include("private")
    expect(japanese).to include("非公開")

    # And neither may quietly become a public issue, which is the one
    # instruction this document exists to give.
    expect(flat(english).downcase).to include("rather than opening a public issue")
    expect(flat(japanese)).to include("公開issueを開かず")
  end

  # Each points at the other, so a reader who lands on one can reach the
  # language they read.
  it "cross-links the two" do
    expect(english).to include("SECURITY.ja.md")
    expect(japanese).to include("SECURITY.md")
  end
end
