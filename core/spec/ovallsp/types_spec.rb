# frozen_string_literal: true

RSpec.describe Ovallsp::Types do
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

    # `Hash` and `Hash[Unknown]` say exactly the same thing -- a Generic
    # whose argument is Unknown constrains nothing beyond its name -- so
    # keeping both presents one type as two alternatives. Reachable from
    # any union of a bare container literal with a call that returns the
    # same container generically, e.g. `reduce({}) { |acc, x| acc.merge(x => x) }`.
    it "collapses a Generic whose argument is Unknown into the same-named plain type" do
      hash = described_class::Nominal.new(name: "Hash")
      generic = described_class::Generic.new(name: "Hash", type_arg: described_class::UNKNOWN)

      expect(described_class.normalize_union([hash, generic])).to eq(hash)
    end

    it "keeps a Generic that carries a real argument alongside the plain type" do
      hash = described_class::Nominal.new(name: "Hash")
      generic = described_class::Generic.new(name: "Hash", type_arg: described_class::Nominal.new(name: "User"))

      result = described_class.normalize_union([hash, generic])

      expect(result).to be_a(described_class::Union)
      expect(result.members).to contain_exactly(hash, generic)
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

  describe ".substitute (Task 012)" do
    let(:t) { described_class::TypeParameter.new(name: "T") }
    let(:user) { described_class::Nominal.new(name: "User") }

    it "replaces a bound TypeParameter with its binding" do
      expect(described_class.substitute(t, { "T" => user })).to eq(user)
    end

    it "widens an unbound TypeParameter to Unknown instead of leaking the placeholder" do
      expect(described_class.substitute(t, {})).to eq(described_class::UNKNOWN)
    end

    it "recurses into a Generic's type_arg" do
      generic = described_class::Generic.new(name: "Array", type_arg: t)

      expect(described_class.substitute(generic, { "T" => user })).to eq(described_class::Generic.new(name: "Array", type_arg: user))
    end

    it "recurses into a Union's members and re-normalizes" do
      union = described_class.normalize_union([t, described_class::NIL])

      expect(described_class.substitute(union, { "T" => user })).to eq(described_class.normalize_union([user, described_class::NIL]))
    end

    it "recurses into a ProcType's parameters and return_type" do
      u = described_class::TypeParameter.new(name: "U")
      proc_type = described_class::ProcType.new(parameters: [t], return_type: u)

      result = described_class.substitute(proc_type, { "T" => user, "U" => described_class::NIL })

      expect(result).to eq(described_class::ProcType.new(parameters: [user], return_type: described_class::NIL))
    end

    it "leaves a non-template type unchanged" do
      expect(described_class.substitute(user, { "T" => described_class::NIL })).to eq(user)
    end
  end
end
