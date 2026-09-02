# frozen_string_literal: true

require_relative "../../../scripts/issue_index"

# `docs/ISSUES.md` is one view of every known issue, and the half below
# `## Index` is generated from the register so it cannot drift from it.
#
# **A consolidated document that was hand-maintained would be the second
# place to keep right**, and this project has already paid for that
# shape: 0.2.1 shipped two changelog bullets contradicting each other
# about one behaviour, and a `KNOWN_LIMITATIONS` section describing a
# rolled-back arrangement instead of the shipped one. The rule this
# encodes is that the register stays the store and everything else is
# derived from it or points at it.
RSpec.describe "docs/ISSUES.md" do
  let(:root) { File.expand_path("../../..", __dir__) }

  around do |example|
    Dir.chdir(root) { example.run }
  end

  it "is current with the register" do
    expect(IssueIndex.rebuild).to eq(File.read(IssueIndex::DOC, encoding: "UTF-8")),
                                  "docs/ISSUES.md is stale. Run `ruby scripts/issue_index.rb`."
  end

  # The control: regenerating twice changes nothing, which is what makes
  # the check above a check rather than a coin toss.
  it "is idempotent" do
    once = IssueIndex.rebuild
    File.write(IssueIndex::DOC, once)
    expect(IssueIndex.rebuild).to eq(once)
  end

  # And the assertion that could otherwise pass on an empty document.
  it "actually lists the open entries" do
    open_count = IssueIndex.entries(IssueIndex::LIVE).count { |e| e.status == "open" }

    expect(open_count).to be_positive
    expect(File.read(IssueIndex::DOC, encoding: "UTF-8")).to include("**#{open_count} open**")
  end

  it "keeps the hand-written policy above the generated region" do
    expect(File.read(IssueIndex::DOC, encoding: "UTF-8")).to include("## The rule").and include("## Intake")
  end
end
