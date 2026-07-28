# frozen_string_literal: true

RSpec.describe Ovallsp::Signatures::OverloadResolver do
  let(:string_type) { Ovallsp::Types::Nominal.new(name: "String") }
  let(:integer_type) { Ovallsp::Types::Nominal.new(name: "Integer") }

  describe ".resolve (arity)" do
    let(:zero_arg) { Ovallsp::Signatures::Overload.new(return_type: integer_type) }
    let(:one_required) do
      Ovallsp::Signatures::Overload.new(required_positionals: [string_type], return_type: string_type)
    end

    it "picks the overload whose required positional arity matches the call" do
      result = described_class.resolve([zero_arg, one_required], positional_count: 1)

      expect(result).to eq(string_type)
    end

    it "picks the zero-arg overload when the call passes no positional arguments" do
      result = described_class.resolve([zero_arg, one_required], positional_count: 0)

      expect(result).to eq(integer_type)
    end

    it "unions every overload's return type when nothing matches, rather than guessing one" do
      result = described_class.resolve([zero_arg, one_required], positional_count: 5)

      expect(result).to eq(Ovallsp::Types.normalize_union([integer_type, string_type]))
    end

    it "matches an optional-positional overload across its whole min..max range" do
      overload = Ovallsp::Signatures::Overload.new(
        required_positionals: [string_type], optional_positionals: [integer_type], return_type: string_type
      )

      expect(described_class.resolve([overload], positional_count: 1)).to eq(string_type)
      expect(described_class.resolve([overload], positional_count: 2)).to eq(string_type)
      expect(described_class.resolve([overload], positional_count: 0)).to eq(string_type) # no match -> fallback
    end

    it "matches any positional count when a rest positional is present" do
      overload = Ovallsp::Signatures::Overload.new(rest_positional: string_type, return_type: integer_type)

      expect(described_class.resolve([overload], positional_count: 50)).to eq(integer_type)
    end
  end

  describe ".resolve (keywords)" do
    let(:overload) do
      Ovallsp::Signatures::Overload.new(
        required_keywords: { id: integer_type }, optional_keywords: { name: string_type }, return_type: string_type
      )
    end

    it "matches when every required keyword is present" do
      expect(described_class.resolve([overload], positional_count: 0, keyword_names: [:id])).to eq(string_type)
    end

    it "matches when an optional keyword is also present" do
      result = described_class.resolve([overload], positional_count: 0, keyword_names: %i[id name])

      expect(result).to eq(string_type)
    end

    it "does not match when a required keyword is missing" do
      other = Ovallsp::Signatures::Overload.new(return_type: integer_type)
      result = described_class.resolve([overload, other], positional_count: 0, keyword_names: [])

      expect(result).to eq(integer_type)
    end

    it "does not match when an unknown keyword is passed" do
      other = Ovallsp::Signatures::Overload.new(rest_keyword: integer_type, return_type: integer_type)
      result = described_class.resolve([overload, other], positional_count: 0, keyword_names: %i[id bogus])

      expect(result).to eq(integer_type)
    end

    it "does not treat a no-keyword overload as matching a keyword call" do
      no_keywords = Ovallsp::Signatures::Overload.new(return_type: string_type)
      accepts_bogus = Ovallsp::Signatures::Overload.new(
        optional_keywords: { bogus: integer_type }, return_type: integer_type
      )

      result = described_class.resolve(
        [no_keywords, accepts_bogus], positional_count: 0, keyword_names: [:bogus]
      )

      expect(result).to eq(integer_type)
    end
  end

  describe ".resolve (block)" do
    it "does not match a block-required overload when no block was given" do
      overload = Ovallsp::Signatures::Overload.new(block_required: true, return_type: string_type)
      fallback = Ovallsp::Signatures::Overload.new(return_type: integer_type)

      result = described_class.resolve([overload, fallback], positional_count: 0, block_given: false)

      expect(result).to eq(integer_type)
    end

    it "matches a block-required overload when a block was given" do
      overload = Ovallsp::Signatures::Overload.new(block_required: true, return_type: string_type)

      result = described_class.resolve([overload], positional_count: 0, block_given: true)

      expect(result).to eq(string_type)
    end

    # Guards the positive half of the block narrowing. Its negative half
    # (the fallback case, below) passed with or without the narrowing, so
    # nothing actually pinned the behaviour: deleting the whole hunk left
    # the entire suite green. Concretely this is what makes
    # `[1].each { |i| i }` infer `Array[Integer]` instead of unioning in
    # the blockless `Enumerator` overload's return type.
    it "narrows an arity match to the block-taking overload when a block was given" do
      with_block = Ovallsp::Signatures::Overload.new(
        block_type: Object.new, return_type: string_type
      )
      without_block = Ovallsp::Signatures::Overload.new(return_type: integer_type)

      result = described_class.resolve([with_block, without_block], positional_count: 0, block_given: true)

      expect(result).to eq(string_type)
    end

    it "does not re-narrow the all-overloads fallback by block presence after arity failed" do
      with_block = Ovallsp::Signatures::Overload.new(
        required_positionals: [string_type], block_type: Object.new, return_type: string_type
      )
      without_block = Ovallsp::Signatures::Overload.new(
        required_positionals: [string_type], return_type: integer_type
      )

      result = described_class.resolve([with_block, without_block], positional_count: 5, block_given: true)

      expect(result).to eq(Ovallsp::Types.normalize_union([string_type, integer_type]))
    end
  end
end
