# frozen_string_literal: true

# `Loader` forks a plugin so a broken or hostile one cannot take Core
# down, and read the result back with `Marshal.load` -- which instantiates
# whatever classes the stream names, **in the parent, before any
# validation runs**. The fork boundary was undone by the way its result
# came back (`024.73`). A `Marshal.load` allowlist proc is not a fix: the
# proc runs after each object is constructed, which is after a gadget has
# fired.
#
# So the boundary carries plain data and the parent rebuilds the typed
# values itself, from fields it has checked. This module is that format.
# It is deliberately a closed list -- an encoding it does not know is
# dropped, never guessed at, and never turned into a constant lookup or a
# `to_sym` on attacker-chosen text.
RSpec.describe Ovallsp::Plugins::Wire do
  def round_trip(value)
    described_class.decode_type(JSON.parse(JSON.generate(described_class.encode_type(value)), symbolize_names: true))
  end

  describe "the type lattice" do
    it "carries every type a plugin may put in a declaration" do
      [
        Ovallsp::Types::UNKNOWN,
        Ovallsp::Types::NIL,
        Ovallsp::Types::Nominal.new(name: "Boolean"),
        Ovallsp::Types::Generic.new(name: "Relation", type_arg: Ovallsp::Types::Nominal.new(name: "Order")),
        Ovallsp::Types::Union.new(members: [Ovallsp::Types::Nominal.new(name: "A"), Ovallsp::Types::NIL]),
        Ovallsp::Types::TypeParameter.new(name: "T"),
        Ovallsp::Types::ProcType.new(parameters: [Ovallsp::Types::Nominal.new(name: "A")],
                                     return_type: Ovallsp::Types::NIL)
      ].each { |type| expect(round_trip(type)).to eq(type) }
    end

    it "drops a type it does not recognise rather than reconstructing it" do
      expect(described_class.decode_type({ kind: "os_command", name: "rm -rf /" })).to be_nil
    end

    # The gadget shape the whole change is about, in the form it would
    # arrive: a payload naming a class to instantiate.
    it "never turns an encoded name into a constant" do
      expect(Ovallsp::Plugins::Wire).not_to receive(:const_get)

      expect(described_class.decode_type({ kind: "nominal", name: "Kernel" }))
        .to eq(Ovallsp::Types::Nominal.new(name: "Kernel"))
    end
  end

  describe "a static plugin's declarations" do
    let(:facts) do
      [{ symbol_id: Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "Widget", name: "shiny?",
                                                 discriminator: nil),
         return_type: Ovallsp::Types::Nominal.new(name: "Boolean") }]
    end

    it "survives the boundary unchanged" do
      encoded = JSON.parse(JSON.generate(described_class.encode_result({ ok: true, result: facts })),
                           symbolize_names: true)

      expect(described_class.decode_result(encoded)).to eq(ok: true, result: facts)
    end

    it "drops a declaration whose kind is not one this Core knows" do
      encoded = { ok: true,
                  result: { shape: "declarations",
                            declarations: [{ symbol_id: { kind: "system", owner: nil, name: "x" },
                                             return_type: nil }] } }

      expect(described_class.decode_result(encoded)).to eq(ok: true, result: [])
    end
  end

  describe "a runtime plugin's summary" do
    # Strings on both sides: `register_snapshot_section` stores
    # `name.to_s`, so nothing a plugin chooses is ever interned.
    it "carries the section names and hook count, without interning them" do
      summary = { snapshot_section_names: %w[routes schema], reload_hook_count: 2 }
      encoded = JSON.parse(JSON.generate(described_class.encode_result({ ok: true, result: summary })),
                           symbolize_names: true)

      expect(described_class.decode_result(encoded)).to eq(ok: true, result: summary)
    end
  end

  describe "a failure from the child" do
    it "carries the message, and only as a string" do
      encoded = JSON.parse(JSON.generate(described_class.encode_result({ ok: false, error: "RuntimeError: boom" })),
                           symbolize_names: true)

      expect(described_class.decode_result(encoded)).to eq(ok: false, error: "RuntimeError: boom")
    end
  end

  it "refuses a payload that is not one of the two shapes" do
    expect(described_class.decode_result([1, 2, 3])).to be_nil
    expect(described_class.decode_result({ ok: true })).to be_nil
  end
end
