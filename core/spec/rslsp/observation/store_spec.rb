# frozen_string_literal: true

RSpec.describe Rslsp::Observation::Store do
  subject(:store) { described_class.new }

  def sym(name) = Rslsp::Index::SymbolId.new(kind: :instance_method, owner: "::Widget", name: name, discriminator: nil)

  def signature(name, fingerprint: "fp1", samples: 3)
    Rslsp::Observation::ObservedSignature.new(
      symbol_id: sym(name), parameter_types: [Rslsp::Types::Nominal.new(name: "String")],
      return_type: Rslsp::Types::Nominal.new(name: "Integer"), samples: samples, run_id: "run-1",
      code_fingerprint: fingerprint, created_at: Time.now
    )
  end

  it "returns nil for a symbol with no observed evidence" do
    expect(store.evidence_for(sym("unknown"))).to be_nil
  end

  it "returns the observed evidence for a symbol after #replace_run" do
    sig = signature("foo")
    store.replace_run([sig])

    expect(store.evidence_for(sym("foo"))).to eq(sig)
  end

  it "replaces the whole previous run wholesale rather than merging with it" do
    store.replace_run([signature("foo")])
    store.replace_run([signature("bar")])

    expect(store.evidence_for(sym("foo"))).to be_nil
    expect(store.evidence_for(sym("bar"))).not_to be_nil
  end

  it "bumps generation on every #replace_run" do
    expect { store.replace_run([signature("foo")]) }.to change(store, :generation).by(1)
  end

  describe "#invalidate_changed" do
    it "drops a signature whose code_fingerprint no longer matches the live source" do
      store.replace_run([signature("foo", fingerprint: "old-fp")])

      store.invalidate_changed({ sym("foo") => "new-fp" })

      expect(store.evidence_for(sym("foo"))).to be_nil
    end

    it "keeps a signature whose code_fingerprint still matches the live source" do
      store.replace_run([signature("foo", fingerprint: "fp1")])

      store.invalidate_changed({ sym("foo") => "fp1" })

      expect(store.evidence_for(sym("foo"))).not_to be_nil
    end

    it "drops a signature for a method that no longer exists at all" do
      store.replace_run([signature("foo", fingerprint: "fp1")])

      store.invalidate_changed({})

      expect(store.evidence_for(sym("foo"))).to be_nil
    end

    it "does not bump generation when nothing was actually invalidated" do
      store.replace_run([signature("foo", fingerprint: "fp1")])

      expect { store.invalidate_changed({ sym("foo") => "fp1" }) }.not_to change(store, :generation)
    end
  end

  describe "#tracked_symbol_ids" do
    it "lists every symbol_id currently holding evidence" do
      store.replace_run([signature("foo"), signature("bar")])

      expect(store.tracked_symbol_ids).to contain_exactly(sym("foo"), sym("bar"))
    end
  end

  describe "#clear" do
    it "removes every observed signature" do
      store.replace_run([signature("foo")])

      store.clear

      expect(store.evidence_for(sym("foo"))).to be_nil
    end

    it "does not bump generation when already empty" do
      expect { store.clear }.not_to change(store, :generation)
    end
  end
end
