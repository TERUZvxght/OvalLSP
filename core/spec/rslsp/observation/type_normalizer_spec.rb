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
end
