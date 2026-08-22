# frozen_string_literal: true

# `046`'s C1. Every documentation path named in tracked content must
# resolve to a file that exists.
#
# The measured state before this landed, at `6bc31b9`: **19 citations
# across 17 files naming five task filenames that had never existed in
# any commit.** The whole `plugins/` subsystem and the public SDK
# document pointed at one of them. Every one lived in a *source comment*,
# so a checker that read only Markdown would have called this tree clean.
#
# `scripts/check_site_links.rb` had already bought this countermeasure
# for `site/` alone, and its header makes the argument: nothing else
# would notice a renamed page. This is the same argument for the other
# 101 documents, and by CLAUDE.md's rule the fourth occurrence buys the
# check rather than a fourth fix.
RSpec.describe "documentation links" do
  it "all resolve to a file that exists" do
    script = File.expand_path("../../../scripts/check_doc_links.rb", __dir__)
    output = IO.popen(["ruby", script], err: %i[child out], &:read)

    expect($?).to be_success, output
  end
end
