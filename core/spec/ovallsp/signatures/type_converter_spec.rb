# frozen_string_literal: true

RSpec.describe Ovallsp::Signatures::TypeConverter do
  def rbs_type(source)
    RBS::Parser.parse_type(source)
  end

  describe ".convert" do
    it "converts a plain class instance type to a Nominal" do
      expect(described_class.convert(rbs_type("::String")).to_s).to eq("String")
    end

    it "converts a single-argument generic (Array[T]) to a Generic" do
      expect(described_class.convert(rbs_type("::Array[::Integer]")).to_s).to eq("Array[Integer]")
    end

    it "keeps only the value type for a two-argument generic (Hash[K, V])" do
      expect(described_class.convert(rbs_type("::Hash[::Symbol, ::String]")).to_s).to eq("Hash[String]")
    end

    it "converts an optional type to a Union with nil" do
      result = described_class.convert(rbs_type("::String?"))

      expect(result).to eq(Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "String"), Ovallsp::Types::NIL]))
    end

    it "converts a union type to a Union" do
      result = described_class.convert(rbs_type("::Integer | ::String"))

      expect(result).to eq(Ovallsp::Types.normalize_union(
                              [Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "String")]
                            ))
    end

    it "converts a type variable to a TypeParameter" do
      variable_type = RBS::Parser.parse_type("Elem", variables: [:Elem])

      expect(described_class.convert(variable_type)).to eq(Ovallsp::Types::TypeParameter.new(name: "Elem"))
    end

    it "converts untyped to Unknown" do
      expect(described_class.convert(rbs_type("untyped"))).to eq(Ovallsp::Types::UNKNOWN)
    end

    it "converts nil to the NIL type" do
      expect(described_class.convert(rbs_type("nil"))).to eq(Ovallsp::Types::NIL)
    end

    it "converts a proc type to a ProcType" do
      result = described_class.convert(rbs_type("^(::Integer) -> ::String"))

      expect(result).to eq(Ovallsp::Types::ProcType.new(
                              parameters: [Ovallsp::Types::Nominal.new(name: "Integer")],
                              return_type: Ovallsp::Types::Nominal.new(name: "String")
                            ))
    end

    it "never raises for a type it doesn't recognize, widening to Unknown instead" do
      expect { described_class.convert(nil) }.not_to raise_error
      expect(described_class.convert(nil)).to eq(Ovallsp::Types::UNKNOWN)
    end
  end
end
