# frozen_string_literal: true

RSpec.describe Ovallsp::Signatures::RbiParser do
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
    expect(sm.symbol_id).to eq(Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::Foo", name: "bar", discriminator: nil))
    expect(sm.source_kind).to eq(:rbi)
    overload = sm.overloads.first
    expect(overload.required_positionals).to eq(
      [Ovallsp::Types::Nominal.new(name: "Integer"),
       Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::NIL])]
    )
    expect(overload.return_type).to eq(Ovallsp::Types::Nominal.new(name: "String"))
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
    expect(sm.overloads.first.return_type).to eq(Ovallsp::Types::UNKNOWN)
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

    expect(overload.required_positionals.first).to eq(
      Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")])
    )
    expect(overload.return_type).to eq(Ovallsp::Types::NIL)
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

    expect(overload.return_type).to eq(Ovallsp::Types::Generic.new(name: "Array", type_arg: Ovallsp::Types::Nominal.new(name: "Integer")))
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

  # Sorbet's `params(...)` is a name-to-type map and says nothing about
  # parameter *shape*: `params(x: Integer)` describes `def f(x)` and
  # `def f(x:)` identically. The `def` immediately below the sig is the
  # authority on shape, and this parser has always had that node in hand.
  #
  # Filing every entry as a required keyword "for arity matching purposes"
  # was invisible while nothing rendered it. 0.1.12 made the signature
  # label render keywords, at which point a method declared
  # `def combine(x, y)` started telling the user to type `x:` (0.1.12,
  # round 5).
  describe "parameter shape comes from the def, types from params(...)" do
    def overload_for(source)
      parse(source).signature_methods.first.overloads.first
    end

    it "files a positional parameter as a positional, not a keyword" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer, y: String).returns(Integer) }
          def combine(x, y)
          end
        end
      RBI

      expect(overload.required_positionals).to eq(
        [Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")]
      )
      expect(overload.required_keywords).to be_empty
    end

    it "files a keyword parameter as a keyword" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer).returns(Integer) }
          def only_kw(x:)
          end
        end
      RBI

      expect(overload.required_keywords).to eq({ x: Ovallsp::Types::Nominal.new(name: "Integer") })
      expect(overload.required_positionals).to be_empty
    end

    # The same `params(...)` line, two different defs -- which is the pair
    # that shows the shape is being read from the def rather than guessed.
    it "distinguishes an optional positional from a required one" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer, y: String).returns(Integer) }
          def combine(x, y = "d")
          end
        end
      RBI

      expect(overload.required_positionals).to eq([Ovallsp::Types::Nominal.new(name: "Integer")])
      expect(overload.optional_positionals).to eq([Ovallsp::Types::Nominal.new(name: "String")])
    end

    it "distinguishes an optional keyword from a required one" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer, y: String).returns(Integer) }
          def combine(x:, y: "d")
          end
        end
      RBI

      expect(overload.required_keywords).to eq({ x: Ovallsp::Types::Nominal.new(name: "Integer") })
      expect(overload.optional_keywords).to eq({ y: Ovallsp::Types::Nominal.new(name: "String") })
    end

    it "puts a splat in the rest slot and a double splat in the keyword-rest slot" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(args: Integer, opts: String).returns(Integer) }
          def spread(*args, **opts)
          end
        end
      RBI

      expect(overload.rest_positional).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
      expect(overload.rest_keyword).to eq(Ovallsp::Types::Nominal.new(name: "String"))
      expect(overload.required_positionals).to be_empty
    end

    it "keeps a trailing required positional required" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(a: Integer, rest: String, z: Symbol).returns(Integer) }
          def trailing(a, *rest, z)
          end
        end
      RBI

      expect(overload.required_positionals).to eq(
        [Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "Symbol")]
      )
    end

    # A block parameter is not something the caller types in the argument
    # list, so it must not occupy a slot -- but the sig names it, and the
    # old code turned every name into one.
    it "does not give a block parameter an argument slot" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer, blk: T.untyped).returns(Integer) }
          def each_thing(x, &blk)
          end
        end
      RBI

      expect(overload.required_positionals).to eq([Ovallsp::Types::Nominal.new(name: "Integer")])
      expect(overload.required_keywords).to be_empty
      expect(overload.rest_keyword).to be_nil
    end

    # `sig { void }` says nothing about parameters, but the def still has
    # them -- and a signature claiming zero arity for a two-argument
    # method is the same lie in the other direction.
    it "gives an untyped slot to a parameter the sig does not mention" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { void }
          def build(a, b)
          end
        end
      RBI

      expect(overload.required_positionals).to eq([Ovallsp::Types::UNKNOWN, Ovallsp::Types::UNKNOWN])
    end

    # Not every node in a parameter list answers `#name`. Reading shape
    # from the def means meeting the whole grammar, and three legal forms
    # have no name at all: `...`, `**nil`, and a destructured
    # `(b, c)`. Asking them for one raised, `handle_sig`'s blanket rescue
    # turned that into a warning, and the method's signature was dropped
    # entirely -- so a `.rbi` that parsed before this release stopped
    # producing hover, signature help and a declaration for that method.
    # Caught in round 6; it was introduced in round 5.
    it "parses a sig over `def f(...)` rather than dropping the signature" do
      result = parse(<<~RBI)
        class Foo
          sig { params(x: Integer).returns(String) }
          def forward(...)
          end
        end
      RBI

      expect(result.diagnostics).to be_empty
      expect(result.signature_methods.map { |sm| sm.symbol_id.name }).to eq(["forward"])
    end

    # `...` forwards positionals, keywords and a block alike, so both rest
    # slots have to be open or a forwarding method rejects arguments it
    # does in fact accept.
    it "treats `...` as accepting both positionals and keywords" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer).returns(String) }
          def forward(...)
          end
        end
      RBI

      expect(overload.rest_positional).to eq(Ovallsp::Types::UNKNOWN)
      expect(overload.rest_keyword).to eq(Ovallsp::Types::UNKNOWN)
    end

    # The opposite of `...`, and the pair is what shows the two are being
    # told apart rather than both waved through: `**nil` declares that the
    # method takes no keywords at all.
    it "gives `**nil` no keyword-rest slot" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer).returns(String) }
          def strict(x, **nil)
          end
        end
      RBI

      expect(overload.rest_keyword).to be_nil
      expect(overload.required_positionals).to eq([Ovallsp::Types::Nominal.new(name: "Integer")])
    end

    it "keeps a destructured positional as a positional, typed Unknown" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(a: Integer).returns(String) }
          def pairs(a, (b, c))
          end
        end
      RBI

      expect(overload.required_positionals).to eq([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::UNKNOWN])
    end

    # `empty_slots` is reached by every sig over a parameter-less def, and
    # nothing asserted what it contains -- reverting the whole method only
    # proved the method existed (CLAUDE.md's named blind spot).
    it "gives a sig over a parameter-less def no argument slots at all" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { returns(Integer) }
          def count
          end
        end
      RBI

      expect(overload.required_positionals).to be_empty
      expect(overload.optional_positionals).to be_empty
      expect(overload.rest_positional).to be_nil
      expect(overload.required_keywords).to be_empty
      expect(overload.optional_keywords).to be_empty
      expect(overload.rest_keyword).to be_nil
    end

    # A `params(...)` entry naming something the def does not declare is a
    # broken RBI. It must not invent an argument the method cannot take.
    it "ignores a params entry with no matching parameter" do
      overload = overload_for(<<~RBI)
        class Foo
          sig { params(x: Integer, ghost: String).returns(Integer) }
          def combine(x)
          end
        end
      RBI

      expect(overload.required_positionals).to eq([Ovallsp::Types::Nominal.new(name: "Integer")])
      expect(overload.required_keywords).to be_empty
      expect(overload.optional_keywords).to be_empty
    end
  end
end
