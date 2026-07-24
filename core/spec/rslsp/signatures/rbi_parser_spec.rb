# frozen_string_literal: true

RSpec.describe Rslsp::Signatures::RbiParser do
  def parse(source)
    described_class.parse(source, uri: "file:///app/foo.rbi")
  end

  it "converts a `sig { params(...).returns(...) }` immediately above a def into a SignatureMethod" do
    source = <<~RBI
      class Foo
        sig { params(a: Integer, b: T.nilable(String)).returns(String) }
        def bar(a, b)
        end
      end
    RBI

    result = parse(source)

    expect(result.signature_methods.size).to eq(1)
    sm = result.signature_methods.first
    expect(sm.symbol_id).to eq(Rslsp::Index::SymbolId.new(kind: :instance_method, owner: "::Foo", name: "bar", discriminator: nil))
    expect(sm.source_kind).to eq(:rbi)
    overload = sm.overloads.first
    expect(overload.required_keywords[:a]).to eq(Rslsp::Types::Nominal.new(name: "Integer"))
    expect(overload.required_keywords[:b]).to eq(Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "String"), Rslsp::Types::NIL]))
    expect(overload.return_type).to eq(Rslsp::Types::Nominal.new(name: "String"))
  end

  it "treats `def self.x` under a sig as a singleton_method" do
    source = <<~RBI
      class Foo
        sig { void }
        def self.build
        end
      end
    RBI

    sm = parse(source).signature_methods.first

    expect(sm.symbol_id.kind).to eq(:singleton_method)
    expect(sm.overloads.first.return_type).to eq(Rslsp::Types::UNKNOWN)
  end

  it "qualifies a method's owner through nested class/module namespaces" do
    source = <<~RBI
      module Outer
        class Inner
          sig { returns(Integer) }
          def count
          end
        end
      end
    RBI

    sm = parse(source).signature_methods.first

    expect(sm.symbol_id.owner).to eq("::Outer::Inner")
  end

  it "converts T.any to a Union" do
    source = <<~RBI
      class Foo
        sig { params(x: T.any(Integer, String)).returns(NilClass) }
        def bar(x)
        end
      end
    RBI

    overload = parse(source).signature_methods.first.overloads.first

    expect(overload.required_keywords[:x]).to eq(
      Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "Integer"), Rslsp::Types::Nominal.new(name: "String")])
    )
    expect(overload.return_type).to eq(Rslsp::Types::NIL)
  end

  it "converts T::Array[X] to a Generic" do
    source = <<~RBI
      class Foo
        sig { returns(T::Array[Integer]) }
        def bar
        end
      end
    RBI

    overload = parse(source).signature_methods.first.overloads.first

    expect(overload.return_type).to eq(Rslsp::Types::Generic.new(name: "Array", type_arg: Rslsp::Types::Nominal.new(name: "Integer")))
  end

  it "ignores a `def` with no preceding sig" do
    source = <<~RBI
      class Foo
        def bar
        end
      end
    RBI

    expect(parse(source).signature_methods).to be_empty
  end

  it "does not raise on a syntactically broken RBI file, and records a diagnostic or degrades to no signatures" do
    source = "class Foo\n  def bar(\nend"

    expect { parse(source) }.not_to raise_error
    expect(parse(source).signature_methods).to eq([])
  end

  it "does not crash on a sig DSL shape it doesn't recognize, and simply skips it" do
    source = <<~RBI
      class Foo
        sig { abstract.returns(Integer) }
        def bar
        end
      end
    RBI

    expect { parse(source) }.not_to raise_error
  end
end
