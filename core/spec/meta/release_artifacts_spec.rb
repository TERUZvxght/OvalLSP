# frozen_string_literal: true

require "shellwords"

# `docs/RELEASE_ARTIFACTS.md` records the SHA-256 of every published VSIX.
#
# It exists because `docs/PUBLISHING.md` asked for the hash to be
# "computed and recorded" from the first Preview onward and never said
# where, so sixteen tags went by with the hash computed and discarded. A
# hash nobody wrote down cannot be compared against anything later.
#
# The invariant this guards is not "the table is up to date" -- it cannot
# be, between a version bump and the publish that produces the artifact.
# It is that **every tag is accounted for**: a tagged version is either
# recorded with the hash it shipped, or recorded as never published. That
# is the exact gap that let 0.1.14 and 0.1.15 be tagged, never built, and
# noticed only by someone looking at the Marketplace by eye.
RSpec.describe "release artifacts" do
  RELEASE_ARTIFACTS = File.expand_path("../../../docs/RELEASE_ARTIFACTS.md", __dir__)
  REPO_ROOT = File.expand_path("../../..", __dir__)

  def document = File.read(RELEASE_ARTIFACTS, encoding: "UTF-8")

  # `| 0.2.0 | `<64 hex>` | Pre-Release |`
  def published = document.scan(/^\| (\d+\.\d+\.\d+) \| `([0-9a-f]{64})` \|/)

  # The second table has no hash, by construction: there is no artifact.
  def unpublished = document.scan(/^\| (\d+\.\d+\.\d+) \| (?!`)/).flatten

  def tags
    `cd #{REPO_ROOT.shellescape} && git tag --list 'v*'`.split("\n").map { |tag| tag.delete_prefix("v") }
  end

  it "accounts for every tag, in one table or the other" do
    recorded = published.map(&:first) + unpublished

    expect(tags - recorded).to be_empty,
                               "tagged but not recorded: #{(tags - recorded).join(', ')}. " \
                               "Add the published SHA-256, or a row saying it never shipped."
  end

  it "records no version that was never tagged" do
    recorded = published.map(&:first) + unpublished

    expect(recorded - tags).to be_empty, "recorded but never tagged: #{(recorded - tags).join(', ')}"
  end

  it "records each version once" do
    recorded = published.map(&:first) + unpublished

    expect(recorded.tally.select { |_, count| count > 1 }).to be_empty
  end

  # A hash is only worth recording if it is the one users receive. The
  # document says how to re-derive each row from the Marketplace; this
  # asserts the shape so a truncated or mistyped digest fails here rather
  # than during an incident.
  it "records a full SHA-256 for every published version" do
    expect(published).not_to be_empty
    expect(published.map(&:last)).to all(match(/\A[0-9a-f]{64}\z/))
  end
end
