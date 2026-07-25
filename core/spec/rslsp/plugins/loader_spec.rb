# frozen_string_literal: true

RSpec.describe Rslsp::Plugins::Loader do
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../../fixtures/plugins", __dir__) }

  subject(:loader) { described_class.new(logger: logger, timeout_seconds: 1) }

  def manifest_path(name)
    File.join(fixtures_root, name, "plugin-manifest.json")
  end

  after do
    # Loader always calls Plugins.clear_registration after a run, but a
    # test that inspects state mid-way (or a fixture whose block itself
    # raises before registering) could otherwise leak a stale
    # registration into the next example, since Plugins' registry is a
    # shared module-level Hash.
    Rslsp::Plugins.clear_registration("rslsp-example-state-machine")
    Rslsp::Plugins.clear_registration("rslsp-raising")
    Rslsp::Plugins.clear_registration("rslsp-slow")
    Rslsp::Plugins.clear_registration("rslsp-malformed-fact")
    Rslsp::Plugins.clear_registration("rslsp-runtime-example")
  end

  describe "#load_static" do
    it "loads a valid plugin and collects its registered declarations" do
      contexts = loader.load_static([manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
      fact = contexts.first.declarations.first
      expect(fact[:symbol_id]).to eq(
        Rslsp::Index::SymbolId.new(kind: :instance_method, owner: "::ExampleModel", name: "pending?", discriminator: nil)
      )
      expect(fact[:return_type]).to eq(Rslsp::Types::Nominal.new(name: "Boolean"))
    end

    it "skips a plugin whose protocol_version doesn't match this Core build's own, without raising" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("bad_version")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/protocol_version/))
    end

    it "isolates a plugin whose entrypoint raises -- no exception escapes, and it contributes nothing" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("raising")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/boom/))
    end

    it "isolates a plugin whose entrypoint hangs past the timeout" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("slow")]) }.not_to raise_error

      expect(contexts).to eq([])
    end

    it "isolates a plugin that registers a malformed fact (missing required keys)" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("malformed_fact")]) }.not_to raise_error

      expect(contexts).to eq([])
    end

    it "skips a manifest whose static_entrypoint file doesn't exist, logging why" do
      contexts = loader.load_static([manifest_path("missing_entrypoint")])

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/entrypoint not found/))
    end

    it "skips an invalid manifest without raising, and still loads every other plugin in the batch" do
      contexts = loader.load_static([manifest_path("invalid_manifest"), manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
    end

    it "disables a plugin after repeated consecutive failures across separate loads" do
      described_class::MAX_CONSECUTIVE_FAILURES.times do
        loader.load_static([manifest_path("raising")])
      end

      expect(logger).to have_received(:error).with(a_string_matching(/boom/)).at_least(described_class::MAX_CONSECUTIVE_FAILURES).times
    end

    it "keeps two plugins isolated from each other -- one failing does not affect the other" do
      contexts = loader.load_static([manifest_path("raising"), manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
      expect(contexts.first.declarations).not_to be_empty
    end

    it "supports reload: loading the same plugin twice both times returns a fresh context" do
      first = loader.load_static([manifest_path("state_machine_example")])
      second = loader.load_static([manifest_path("state_machine_example")])

      expect(first.first.declarations).to eq(second.first.declarations)
    end
  end

  describe "#load_runtime" do
    it "does not load anything at all for an untrusted workspace" do
      contexts = loader.load_runtime([manifest_path("runtime_example")], trusted: false)

      expect(contexts).to eq([])
    end

    it "loads a runtime plugin's contributions for a trusted workspace" do
      contexts = loader.load_runtime([manifest_path("runtime_example")], trusted: true)

      expect(contexts.size).to eq(1)
      expect(contexts.first.snapshot_sections.keys).to eq(["example"])
    end
  end
end
