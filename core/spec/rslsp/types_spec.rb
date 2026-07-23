# frozen_string_literal: true

RSpec.describe Rslsp::Types do
  describe ".normalize_union" do
    it "unwraps a single distinct member instead of wrapping it in a Union" do
      expect(described_class.normalize_union([described_class::Nominal.new(name: "User")]))
        .to eq(described_class::Nominal.new(name: "User"))
    end

    it "flattens nested unions and deduplicates members" do
      user = described_class::Nominal.new(name: "User")
      nested = described_class::Union.new(members: [user, described_class::NIL].freeze)

      result = described_class.normalize_union([nested, user, described_class::NIL])

      expect(result).to be_a(described_class::Union)
      expect(result.members).to contain_exactly(user, described_class::NIL)
    end

    it "produces a stable member order regardless of input order" do
      user = described_class::Nominal.new(name: "User")
      company = described_class::Nominal.new(name: "Company")

      expect(described_class.normalize_union([user, company])).to eq(described_class.normalize_union([company, user]))
    end
  end

  describe ".remove_nil" do
    it "drops nil from a union, unwrapping to the remaining member" do
      user = described_class::Nominal.new(name: "User")
      union = described_class.normalize_union([user, described_class::NIL])

      expect(described_class.remove_nil(union)).to eq(user)
    end

    it "widens a bare nil to Unknown rather than producing an empty type" do
      expect(described_class.remove_nil(described_class::NIL)).to eq(described_class::UNKNOWN)
    end

    it "leaves an already non-nil type unchanged" do
      user = described_class::Nominal.new(name: "User")

      expect(described_class.remove_nil(user)).to eq(user)
    end
  end
end
