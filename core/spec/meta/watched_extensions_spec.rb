# frozen_string_literal: true

require_relative "../../../scripts/check_watched_extensions"

# **What the first index reads and what the watcher watches are one
# contract, written in two languages, and they had drifted.**
#
# `ColdIndexer::DEFAULT_INCLUDED_EXTENSIONS` includes `.rake`;
# `WATCHED_FILES_GLOB` did not. So a `.rake` file was read once at startup
# and never again: edited, added or deleted outside the editor with the
# file unopened, the index went on answering from the first read. Three
# releases, and nothing could notice, because no check knew the two lists
# were about the same thing. Found by the 2026-09-05 critical review, R12.
#
# `scripts/check_watched_extensions.rb` is the single detector; this file
# and the preflight gate are its two readers.
RSpec.describe "scripts/check_watched_extensions.rb" do
  # **The rule's own teeth.** Without these, a regexp that matched
  # nothing would report exactly what two agreeing lists report, which is
  # `024.148`'s shape and the one this project keeps meeting.
  describe "the rule" do
    it "reads a list from each side rather than an empty one" do
      expect(WatchedExtensions.indexed_extensions).to include(".rb", ".rake", ".erb")
      expect(WatchedExtensions.watched_extensions).to include(".rb", ".rake")
    end

    it "reports an extension Core indexes and the extension does not watch" do
      allow(WatchedExtensions).to receive(:indexed_extensions).and_return([".rb", ".rake"])
      allow(WatchedExtensions).to receive(:watched_extensions).and_return([".rb"])

      expect(WatchedExtensions.problems).to eq([".rake is indexed by ColdIndexer and not watched by the extension"])
    end

    it "reports an extension the extension watches and Core does not index" do
      allow(WatchedExtensions).to receive(:indexed_extensions).and_return([".rb"])
      allow(WatchedExtensions).to receive(:watched_extensions).and_return([".rb", ".haml"])

      expect(WatchedExtensions.problems).to eq([".haml is watched by the extension and not indexed by Core"])
    end

    # Signatures and schema are watched because a change to them
    # invalidates answers, not because they are indexed as source. A
    # deliberate difference, listed rather than inferred.
    it "accepts the signature extensions as a deliberate difference" do
      allow(WatchedExtensions).to receive(:indexed_extensions).and_return([".rb"])
      allow(WatchedExtensions).to receive(:watched_extensions).and_return([".rb", ".rbs", ".rbi"])

      expect(WatchedExtensions.problems).to be_empty
    end

    it "refuses two empty lists rather than calling them agreed" do
      allow(WatchedExtensions).to receive(:indexed_extensions).and_return([])
      allow(WatchedExtensions).to receive(:watched_extensions).and_return([])

      expect(WatchedExtensions.problems).not_to be_empty
    end
  end

  it "finds the two lists agreeing in this tree" do
    expect(WatchedExtensions.problems).to be_empty
  end
end
