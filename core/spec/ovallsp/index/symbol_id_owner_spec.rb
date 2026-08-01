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

  # A class/module's own `name` is qualified too — documented in this
  # type's header since 0.1.11 and enforced nowhere until 0.1.12.
  # `ParserService` happened to always produce it that way, so the gap
  # only opened where something else builds a SymbolId: a plugin's
  # registered declaration reaches the index verbatim, and a bare `name`
  # there made `resolve_type_symbol_locked` match a qualified needle
  # against it and answer with the wrong class (round 9).
  it "qualifies a class's own name, not just its owner" do
    expect(described_class.new(kind: :class, owner: nil, name: "Widget", discriminator: nil).name).to eq("::Widget")
  end

  it "qualifies a module's own name" do
    expect(described_class.new(kind: :module, owner: nil, name: "Admin", discriminator: nil).name).to eq("::Admin")
  end

  # A method's name is plain (`company`, not `::company`), so the rule
  # must apply to the two kinds that carry a qualified name and no others
  # — that pair is what tells the rule from a blanket prefix.
  it "leaves a method's own name alone" do
    expect(described_class.new(kind: :instance_method, owner: "::Widget", name: "build",
                               discriminator: nil).name).to eq("build")
  end

  # Reading `kind`/`name` in the initializer must not make them optional:
  # a nil name indexes under "", matches nothing, and surfaces much later
  # as a `NoMethodError` inside an unrelated request rather than an
  # `ArgumentError` at the call site that got it wrong (round 10).
  it "still requires a kind and a name" do
    expect { described_class.new(kind: :class, owner: nil, discriminator: nil) }
      .to raise_error(ArgumentError, /name/)
    expect { described_class.new(name: "::Widget", owner: nil, discriminator: nil) }
      .to raise_error(ArgumentError, /kind/)
  end

  it "makes the two spellings of a class one key" do
    bare = described_class.new(kind: :class, owner: nil, name: "Widget", discriminator: nil)
    qualified = described_class.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil)

    expect(bare).to eq(qualified)
    expect(bare.hash).to eq(qualified.hash)
  end

  # The same decision read the other way, for the type model and for
  # `ModelRegistry`, whose keys are Rails' own bare `model.name`. Round 7
  # of the 0.1.12 review found three one-line copies of exactly this.
  describe ".bare_name" do
    it "drops a leading `::`" do
      expect(described_class.bare_name("::Admin::Widget")).to eq("Admin::Widget")
    end

    it "leaves an already-bare name alone" do
      expect(described_class.bare_name("Admin::Widget")).to eq("Admin::Widget")
    end

    # Only the *leading* prefix. Collapsing to the simple name is a
    # different rule, and it is the one that made `Admin::User` borrow the
    # top-level `User`'s associations.
    it "keeps every inner namespace segment" do
      expect(described_class.bare_name("::A::B::C")).to eq("A::B::C")
    end

    it "answers `\"\"` for nil rather than raising" do
      expect(described_class.bare_name(nil)).to eq("")
    end
  end

  # Lexical qualification: a *different* operation from the two above,
  # because it prepends the enclosing owner rather than only normalising a
  # prefix. Four byte-identical copies of it lived in `ParserService`,
  # `LocalInferencer` (twice) and `RbiParser`.
  describe ".qualify_within" do
    it "prepends the enclosing owner" do
      expect(described_class.qualify_within("::Admin", "Widget")).to eq("::Admin::Widget")
    end

    it "root-scopes a name written at the top level" do
      expect(described_class.qualify_within(nil, "Widget")).to eq("::Widget")
    end

    # An already-absolute path is absolute regardless of where it is
    # written -- this is the branch that makes the operation different
    # from plain concatenation, and the pair is what shows it.
    it "leaves an already-root-scoped path alone, even inside an owner" do
      expect(described_class.qualify_within("::Admin", "::Widget")).to eq("::Widget")
    end

    it "keeps a multi-segment local path intact under its owner" do
      expect(described_class.qualify_within("::Api", "V1::Widget")).to eq("::Api::V1::Widget")
    end
  end
end
