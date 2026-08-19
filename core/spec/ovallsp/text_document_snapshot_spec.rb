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
# The consequence is a torn read, and the offsets half is the one that
# bites: measured against a concurrent change loop on `main`, 1,977,450
# of 1,977,451 calls to `position_to_byte_offset` returned an offset
# belonging to neither document. MRI preempts between `text=`'s two
# statements and the document sits torn for a whole quantum.
#
# The version half -- old-text findings sent under a new version number
# -- was first justified by a claim about what the client does with a
# version, and that claim was false. What the client actually does is in
# `docs/CLIENT_BEHAVIOUR.md`, which exists because this one was written
# into three files without being checked.
#
# 029's M-2. A snapshot cannot tear: text, version and offsets are
# computed together at construction and never change afterwards, so a
# reader either sees the whole old document or the whole new one.
RSpec.describe Ovallsp::TextDocument do
  def document(text, version: 1)
    described_class.new(uri: "file:///a.rb", text: text, version: version, language_id: "ruby")
  end

  # `freeze` alone is shallow, and `attr_reader :text` hands the string
  # out. A reviewer measured the consequence: `d.text << "ccc\n"`
  # succeeds and `position_to_byte_offset` then answers against offsets
  # for text that no longer exists -- **the exact torn state this release
  # is built to eliminate, with no concurrency at all.** No caller
  # mutates it today, so it was latent; but the invariant `document_store.rb`
  # and the architecture document both state as a property was resting on
  # nobody trying.
  # `+"..."` on purpose: this file is `frozen_string_literal: true`, so a
  # plain literal arrives already frozen and the example would pass
  # whatever the class does -- an assertion that cannot fail, in the file
  # asserting the release's central invariant. The text a real `didOpen`
  # carries comes from `JSON.parse` and is not frozen.
  it "is frozen through, so nothing can change it or what it says about itself" do
    doc = described_class.new(uri: "file:///a.rb", text: +"a\nbb\n", version: 1, language_id: "ruby")

    expect(doc).to be_frozen
    expect(doc.text).to be_frozen
    expect { doc.text << "ccc\n" }.to raise_error(FrozenError)
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
