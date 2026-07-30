# frozen_string_literal: true

# `SymbolId` equality is exact, and its `owner` arrives in two forms
# (0.1.11).
#
# `ParserService` indexes a declaration's owner qualified (`::Object`);
# `HierarchyIndex::DEFAULT_OBJECT_CHAIN` names its entries bare
# (`Object`). Every lookup built from an ancestor chain therefore missed
# for those three names, and the rule "an owner is qualified" ended up
# written at each call site instead of here -- four times in the
# diagnostics engine alone, three of them wrong.
RSpec.describe Ovallsp::Index::SymbolId do
  it "stores a bare owner in the qualified form" do
    expect(described_class.new(kind: :instance_method, owner: "Object", name: "x", discriminator: nil).owner)
      .to eq("::Object")
  end

  it "leaves an already-qualified owner alone" do
    expect(described_class.new(kind: :instance_method, owner: "::Object", name: "x", discriminator: nil).owner)
      .to eq("::Object")
  end

  # The whole point is that the two forms become the same key.
  it "compares equal whichever form each was built from" do
    bare = described_class.new(kind: :instance_method, owner: "Object", name: "x", discriminator: nil)
    qualified = described_class.new(kind: :instance_method, owner: "::Object", name: "x", discriminator: nil)

    expect(bare).to eq(qualified)
    expect(bare.hash).to eq(qualified.hash)
  end

  # Normalising a prefix is not matching by simple name: a nested class
  # is a different class.
  it "keeps a nested owner distinct from a root-scoped one" do
    nested = described_class.new(kind: :instance_method, owner: "Admin::Object", name: "x", discriminator: nil)
    root = described_class.new(kind: :instance_method, owner: "::Object", name: "x", discriminator: nil)

    expect(nested).not_to eq(root)
    expect(nested.owner).to eq("::Admin::Object")
  end

  # A class-level symbol has no owner, and `"::"` is not a class.
  it "leaves a nil owner as nil" do
    expect(described_class.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil).owner).to be_nil
  end
end
