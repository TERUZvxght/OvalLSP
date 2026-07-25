# frozen_string_literal: true

RSpec.describe Rslsp::Observation::TypeNormalizer do
  it "normalizes nil to Types::NIL" do
    expect(described_class.normalize(nil)).to eq(Rslsp::Types::NIL)
  end

  it "normalizes an ordinary object to a Nominal of its class name" do
    expect(described_class.normalize("hello")).to eq(Rslsp::Types::Nominal.new(name: "String"))
    expect(described_class.normalize(1)).to eq(Rslsp::Types::Nominal.new(name: "Integer"))
  end

  it "normalizes an instance of an anonymous class to Unknown rather than crashing or fabricating a name" do
    anonymous_instance = Class.new.new

    expect(described_class.normalize(anonymous_instance)).to eq(Rslsp::Types::UNKNOWN)
  end

  it "normalizes an anonymous class value itself to Unknown" do
    expect(described_class.normalize(Class.new)).to eq(Rslsp::Types::UNKNOWN)
  end

  it "normalizes a named Class/Module value itself to ClassOf(name), not its own metaclass" do
    expect(described_class.normalize(String)).to eq(
      Rslsp::Types::Generic.new(name: "ClassOf", type_arg: Rslsp::Types::Nominal.new(name: "String"))
    )
  end

  it "never calls #inspect or #to_s on the observed value" do
    poisoned = Object.new
    def poisoned.inspect = raise("must never be called")
    def poisoned.to_s = raise("must never be called")

    expect { described_class.normalize(poisoned) }.not_to raise_error
  end

  # Found by an independent review of Task 019: an object whose own
  # `#class` is overridden to return something whose `#name` isn't a
  # String (a proxy/delegator, or simply a broken override) previously
  # had that non-String value flow straight into Types::Nominal#name,
  # and out through rslsp/showTypeEvidence's JSON response unchanged.
  it "widens to Unknown, rather than trusting it verbatim, when an object's overridden #class.name isn't a String" do
    fake_class = Object.new
    def fake_class.name = 42 # not a String

    poisoned = Object.new
    poisoned.define_singleton_method(:class) { fake_class }

    expect(described_class.normalize(poisoned)).to eq(Rslsp::Types::UNKNOWN)
  end

  it "widens to Unknown, rather than trusting it verbatim, when a Module value's overridden #name isn't a String" do
    poisoned_module = Module.new
    def poisoned_module.name = 42 # not a String

    expect(described_class.normalize(poisoned_module)).to eq(Rslsp::Types::UNKNOWN)
  end
end
