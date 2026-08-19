# frozen_string_literal: true

# `TextDocument` was mutated in place on the dispatch thread while
# background threads read it. `#apply_incremental_change` wrote `@text`
# and then `@version`; `text=` assigned `@text` *before* recomputing the
# two line-offset tables; and `DocumentStore#open_documents` duplicated
# the array while handing out the same mutable objects. Six
# `republish_open_diagnostics` call sites read `text` and `version` from
# background threads, and `handle_did_change` mutated before taking any
# lock.
#
# The consequence is a torn read: a background publish can pair
# old-text findings with a new version number -- which the client's
# staleness filter then *accepts*, because the number looks current --
# or run position arithmetic with new text against stale offsets.
#
# 029's M-2. A snapshot cannot tear: text, version and offsets are
# computed together at construction and never change afterwards, so a
# reader either sees the whole old document or the whole new one.
RSpec.describe Ovallsp::TextDocument do
  def document(text, version: 1)
    described_class.new(uri: "file:///a.rb", text: text, version: version, language_id: "ruby")
  end

  it "is frozen, so nothing can change it after it is built" do
    expect(document("x = 1\n")).to be_frozen
  end

  it "has no mutators left for a caller to reach for" do
    expect(described_class.instance_methods).not_to include(:apply_full_change, :apply_incremental_change, :text=)
  end

  describe "#with_full_change" do
    it "answers a new document, leaving the old one exactly as it was" do
      original = document("old\n")

      updated = original.with_full_change(text: "new\n", version: 2)

      expect([updated.text, updated.version]).to eq(["new\n", 2])
      expect([original.text, original.version]).to eq(["old\n", 1])
    end
  end

  describe "#with_incremental_change" do
    it "answers a new document with the edit applied" do
      original = document("hello world\n")

      updated = original.with_incremental_change(
        range: { start: { line: 0, character: 6 }, end: { line: 0, character: 11 } },
        new_text: "there", version: 2
      )

      expect([updated.text, updated.version]).to eq(["hello there\n", 2])
      expect(original.text).to eq("hello world\n")
    end

    # The torn read, stated as a property: the offsets a reader gets are
    # always the ones for the text it gets. Before this, `text=` assigned
    # `@text` first and recomputed the tables second, so a reader between
    # the two saw new text against old offsets.
    it "carries offsets that match its own text, never the other document's" do
      original = document("a\nbb\nccc\n")

      updated = original.with_full_change(text: "wwwwwwww\nx\n", version: 2)

      expect(original.position_to_byte_offset({ line: 2, character: 0 })).to eq(5)
      expect(updated.position_to_byte_offset({ line: 1, character: 0 })).to eq(9)
    end
  end
end
