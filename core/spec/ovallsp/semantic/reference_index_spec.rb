# frozen_string_literal: true

RSpec.describe Ovallsp::Semantic::ReferenceIndex do
  subject(:index) { described_class.new }

  def sym(name) = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::X", name: name, discriminator: nil)

  def reference(name, confidence: :high, uri: "file:///a.rb",
                 location: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } })
    Ovallsp::Index::Reference.new(
      symbol_id: sym(name), location: location, kind: :method_call, confidence: confidence, origin: :source,
      receiver_type: nil, uri: uri, generation: 1
    )
  end

  it "starts empty and returns [] for an unknown symbol" do
    expect(index.references(sym("nope"))).to eq([])
  end

  it "stores and fetches references by symbol_id after #replace_file" do
    ref = reference("foo")
    index.replace_file(uri: "file:///a.rb", references: [ref])

    expect(index.references(sym("foo"))).to eq([ref])
  end

  it "bumps generation on every #replace_file and every #remove_file that actually removes something" do
    expect(index.generation).to eq(0)

    index.replace_file(uri: "file:///a.rb", references: [reference("foo")])
    expect(index.generation).to eq(1)

    index.remove_file("file:///a.rb")
    expect(index.generation).to eq(2)
  end

  it "does not bump generation when #remove_file removes nothing" do
    index.remove_file("file:///nope.rb")

    expect(index.generation).to eq(0)
  end

  it "fully replaces a uri's contribution -- a reference removed in the new version doesn't linger" do
    index.replace_file(uri: "file:///a.rb", references: [reference("foo"), reference("bar")])
    index.replace_file(uri: "file:///a.rb", references: [reference("bar")])

    expect(index.references(sym("foo"))).to eq([])
    expect(index.references(sym("bar")).size).to eq(1)
  end

  it "removes a uri's contribution entirely on #remove_file, without touching another uri's" do
    index.replace_file(uri: "file:///a.rb", references: [reference("foo")])
    index.replace_file(uri: "file:///b.rb", references: [reference("foo")])

    index.remove_file("file:///a.rb")

    expect(index.references(sym("foo")).size).to eq(1)
  end

  describe "#references minimum_confidence" do
    it "excludes a :low-confidence reference by default (minimum_confidence: :high)" do
      index.replace_file(uri: "file:///a.rb", references: [reference("foo", confidence: :low)])

      expect(index.references(sym("foo"))).to eq([])
    end

    it "includes a :low-confidence reference when minimum_confidence: :low" do
      ref = reference("foo", confidence: :low)
      index.replace_file(uri: "file:///a.rb", references: [ref])

      expect(index.references(sym("foo"), minimum_confidence: :low)).to eq([ref])
    end
  end

  describe "#references limit" do
    it "truncates a large result set when limit: is given" do
      refs = (1..5).map { |i| reference("foo", location: { start: { line: i, character: 0 }, end: { line: i, character: 1 } }) }
      index.replace_file(uri: "file:///a.rb", references: refs)

      expect(index.references(sym("foo"), limit: 2).size).to eq(2)
    end
  end
end
