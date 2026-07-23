# frozen_string_literal: true

RSpec.describe Rslsp::DocumentStore do
  subject(:store) { described_class.new }

  describe "#open and #fetch" do
    it "stores the document text, version, and language id" do
      store.open(uri: "file:///a.rb", text: "a = 1\n", version: 1, language_id: "ruby")

      doc = store.fetch(uri: "file:///a.rb")

      expect(doc.text).to eq("a = 1\n")
      expect(doc.version).to eq(1)
      expect(doc.language_id).to eq("ruby")
    end
  end

  describe "#change" do
    it "applies a full-document change (no range)" do
      store.open(uri: "file:///a.rb", text: "a = 1\n", version: 1, language_id: "ruby")

      store.change(uri: "file:///a.rb", version: 2, changes: [{ text: "a = 2\n" }])

      doc = store.fetch(uri: "file:///a.rb")
      expect(doc.text).to eq("a = 2\n")
      expect(doc.version).to eq(2)
    end

    it "applies an incremental change using a range" do
      store.open(uri: "file:///a.rb", text: "hello world\n", version: 1, language_id: "ruby")

      store.change(
        uri: "file:///a.rb",
        version: 2,
        changes: [
          { range: { start: { line: 0, character: 6 }, end: { line: 0, character: 11 } }, text: "ruby!" }
        ]
      )

      expect(store.fetch(uri: "file:///a.rb").text).to eq("hello ruby!\n")
    end

    it "applies multiple incremental changes across lines in order" do
      store.open(uri: "file:///a.rb", text: "one\ntwo\nthree\n", version: 1, language_id: "ruby")

      store.change(
        uri: "file:///a.rb",
        version: 2,
        changes: [
          { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 3 } }, text: "TWO" }
        ]
      )

      expect(store.fetch(uri: "file:///a.rb").text).to eq("one\nTWO\nthree\n")
    end

    it "converts UTF-16 positions correctly across an astral character (emoji)" do
      # "😀" is a single Ruby character but two UTF-16 code units, so the
      # character after it sits at utf16 offset 7, not 6.
      store.open(uri: "file:///e.rb", text: "x = \"😀y\"\n", version: 1, language_id: "ruby")

      store.change(
        uri: "file:///e.rb",
        version: 2,
        changes: [
          { range: { start: { line: 0, character: 7 }, end: { line: 0, character: 8 } }, text: "z" }
        ]
      )

      expect(store.fetch(uri: "file:///e.rb").text).to eq("x = \"😀z\"\n")
    end

    it "raises a descriptive error for an unopened document" do
      expect do
        store.change(uri: "file:///missing.rb", version: 2, changes: [{ text: "x" }])
      end.to raise_error(Rslsp::DocumentStore::UnknownDocumentError, /missing\.rb/)
    end
  end

  describe "#close" do
    it "removes the document" do
      store.open(uri: "file:///a.rb", text: "a", version: 1, language_id: "ruby")

      store.close(uri: "file:///a.rb")

      expect(store.fetch(uri: "file:///a.rb")).to be_nil
    end
  end
end
