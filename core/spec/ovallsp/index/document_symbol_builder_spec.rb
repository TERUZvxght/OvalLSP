# frozen_string_literal: true

RSpec.describe Ovallsp::Index::DocumentSymbolBuilder do
  def declaration(kind:, owner:, name:, location: nil, name_location: nil)
    Ovallsp::Index::Declaration.new(
      symbol_id: Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil),
      location: location || { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
      visibility: nil,
      parameters: [],
      origin: :source,
      name_location: name_location
    )
  end

  # A whole-declaration range and the narrow range of the identifier
  # inside it, deliberately different at both ends so an example cannot
  # pass by picking either one at random.
  WHOLE = { start: { line: 0, character: 0 }, end: { line: 4, character: 3 } }.freeze
  JUST_THE_NAME = { start: { line: 0, character: 6 }, end: { line: 0, character: 7 } }.freeze

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

  # `024.27`. `selectionRange` is not `range`. The installed protocol
  # types say so:
  #
  #   /**
  #    * The range that should be selected and revealed when this symbol
  #    * is being picked, e.g the name of a function.
  #    * Must be contained by the `range`.
  #    */
  #   selectionRange: Range;
  #
  #   vscode/node_modules/vscode-languageserver-types/lib/esm/main.d.ts:2003-2007
  #
  # The builder wrote `decl.location` into both, so picking a class in
  # the outline selected and revealed its entire body. `name_location`
  # is populated for exactly these symbols and is what `prepareRename`
  # already returns for them from the same Declaration objects -- the
  # product emitted the narrow range for one feature and discarded it
  # for another.
  describe "selectionRange" do
    it "is the identifier, not the whole declaration" do
      declarations = [declaration(kind: :class, owner: nil, name: "::User",
                                  location: WHOLE, name_location: JUST_THE_NAME)]

      result = described_class.build(declarations)

      expect(result.first).to include(range: WHOLE, selectionRange: JUST_THE_NAME)
    end

    it "is the identifier for a nested method too" do
      declarations = [
        declaration(kind: :class, owner: nil, name: "::User", location: WHOLE, name_location: JUST_THE_NAME),
        declaration(kind: :instance_method, owner: "::User", name: "name",
                    location: WHOLE, name_location: JUST_THE_NAME)
      ]

      result = described_class.build(declarations)

      expect(result.first[:children].first).to include(range: WHOLE, selectionRange: JUST_THE_NAME)
    end

    # `name_location` is nil for anything whose identifier span is not
    # tracked separately, and the field is not optional in the protocol
    # -- so the whole range is the only honest answer there, and it is
    # still contained by `range`, which is what the types require.
    it "falls back to the whole declaration where no identifier span was recorded" do
      declarations = [declaration(kind: :class, owner: nil, name: "::User", location: WHOLE)]

      result = described_class.build(declarations)

      expect(result.first).to include(range: WHOLE, selectionRange: WHOLE)
    end
  end
end
