# frozen_string_literal: true

# The observation channel's half of `024.73`, recorded separately as
# `024.135`: `Runner` spawns the workspace's own test command and read its
# results back with `Marshal.load`, which instantiates whatever classes
# the stream names before `#read_results`' shape check looks at anything.
#
# So the payload is plain data and Core rebuilds the typed values itself,
# from fields it has checked. Both closed lists are narrower than what
# `Types` and `SymbolId` can express, because a run can only carry what
# `Collector` and `TypeNormalizer` produce -- and a malformed entry
# rejects the whole payload instead of being dropped from it, because
# `Store#replace_run` is a generation swap and a partial run would install
# itself as a complete one.
RSpec.describe Ovallsp::Observation::Wire do
  def sym(name = "add")
    Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::Calculator", name: name, discriminator: nil)
  end

  def signature(**overrides)
    Ovallsp::Observation::ObservedSignature.new(
      **{ symbol_id: sym, parameter_types: [Ovallsp::Types::Nominal.new(name: "Integer")],
          return_type: Ovallsp::Types::Nominal.new(name: "Integer"), samples: 3,
          run_id: "run-1", code_fingerprint: "abc:12", created_at: Time.at(1_700_000_000) }.merge(overrides)
    )
  end

  def round_trip(results)
    described_class.decode(JSON.parse(JSON.generate(described_class.encode(results)), symbolize_names: true))
  end

  it "carries every field of an observed signature across the boundary" do
    expect(round_trip([signature])).to eq([signature])
  end

  # The four shapes `TypeNormalizer` and `Collector#results` between them
  # can produce, driven through the boundary rather than asserted about.
  it "carries every type an observation run can actually hold" do
    observed = signature(
      parameter_types: [Ovallsp::Types::NIL,
                        Ovallsp::Types::Generic.new(name: "ClassOf",
                                                    type_arg: Ovallsp::Types::Nominal.new(name: "Order")),
                        Ovallsp::Types::Union.new(members: [Ovallsp::Types::Nominal.new(name: "String"),
                                                            Ovallsp::Types::NIL])],
      return_type: Ovallsp::Types::UNKNOWN
    )

    expect(round_trip([observed])).to eq([observed])
  end

  # `Types` documents a Union as two members or more, and
  # `normalize_union` is what upholds it, so a payload claiming a
  # one-member Union is not a payload Core wrote.
  it "refuses a union of one rather than flattening it into the member" do
    payload = JSON.parse(JSON.generate(described_class.encode([signature])), symbolize_names: true)
    payload[:signatures][0][:return_type] = { kind: "union", members: [{ kind: "nil" }] }

    expect(described_class.decode(payload)).to be_nil
  end

  it "carries a signature whose file could not be fingerprinted" do
    expect(round_trip([signature(code_fingerprint: nil)])).to eq([signature(code_fingerprint: nil)])
  end

  # The distinction `Runner#read_results` is built on: a completed run
  # that observed nothing is `[]`, and only a payload this module wrote
  # can produce it.
  it "carries a run that observed nothing as an empty run, not as no run" do
    expect(round_trip([])).to eq([])
  end

  it "answers nothing at all for a payload that is not this envelope" do
    expect(described_class.decode({ signatures: [] })).to be_nil
    expect(described_class.decode({ shape: "observations" })).to be_nil
    expect(described_class.decode("observations")).to be_nil
  end

  # One bad entry is not one lost signature: the run installs wholesale,
  # so a payload that cannot be fully decoded is no run.
  it "rejects the whole payload rather than dropping the entry it cannot read" do
    payload = JSON.parse(JSON.generate(described_class.encode([signature, signature(symbol_id: sym("mul"))])),
                         symbolize_names: true)
    payload[:signatures][1][:samples] = "many"

    expect(described_class.decode(payload)).to be_nil
  end

  # `Collector#defined_method` answers nil for a method whose owner has
  # no name, so an ownerless signature never comes from a run this Core
  # observed -- and `SymbolId` would accept one, since a class-level
  # symbol legitimately has no owner. Nothing downstream could resolve an
  # instance method against nothing.
  it "refuses a signature whose method has no owner" do
    payload = JSON.parse(JSON.generate(described_class.encode([signature])), symbolize_names: true)
    payload[:signatures][0][:symbol_id][:owner] = nil

    expect(described_class.decode(payload)).to be_nil
  end

  it "refuses a symbol kind this Core does not use rather than interning it" do
    payload = JSON.parse(JSON.generate(described_class.encode([signature])), symbolize_names: true)
    payload[:signatures][0][:symbol_id][:kind] = "system"

    expect(described_class.decode(payload)).to be_nil
  end

  # The gadget shape the change is about, in the form it would arrive:
  # a payload naming a class to build. Nothing here reaches `const_get`.
  it "reconstructs nothing from a payload naming a class" do
    payload = JSON.parse(JSON.generate(described_class.encode([signature])), symbolize_names: true)
    payload[:signatures][0][:return_type] = { kind: "object", class: "Gem::Requirement" }

    expect(described_class.decode(payload)).to be_nil
  end

  it "keeps a decoded symbol id's reserved discriminator empty" do
    expect(round_trip([signature]).first.symbol_id.discriminator).to be_nil
  end
end
