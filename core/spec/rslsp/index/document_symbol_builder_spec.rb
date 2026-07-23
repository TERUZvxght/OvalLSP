# frozen_string_literal: true

RSpec.describe Rslsp::Index::DocumentSymbolBuilder do
  def declaration(kind:, owner:, name:)
    Rslsp::Index::Declaration.new(
      symbol_id: Rslsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil),
      location: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
      visibility: nil,
      parameters: [],
      origin: :source
    )
  end

  it "nests methods under their owning class and produces LSP DocumentSymbol shapes" do
    declarations = [
      declaration(kind: :class, owner: nil, name: "::User"),
      declaration(kind: :instance_method, owner: "::User", name: "name")
    ]

    result = described_class.build(declarations)

    expect(result.size).to eq(1)
    expect(result.first).to include(name: "User", kind: 5)
    expect(result.first[:children]).to contain_exactly(a_hash_including(name: "name", kind: 6))
  end

  it "keeps unrelated top-level declarations as siblings" do
    declarations = [
      declaration(kind: :class, owner: nil, name: "::A"),
      declaration(kind: :class, owner: nil, name: "::B")
    ]

    result = described_class.build(declarations)

    expect(result.map { |s| s[:name] }).to contain_exactly("A", "B")
  end
end
