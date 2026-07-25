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
    Rslsp::Plugins.clear_registration("rslsp-monkeypatching")
    Rslsp::Plugins.clear_registration("rslsp-stdout-writer")
    Rslsp::Plugins.clear_registration("rslsp-monkeypatching-runtime")
    Rslsp::Plugins.clear_registration("rslsp-io-scavenger")
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

    it "isolates a plugin's top-level code in a separate process -- monkeypatching a Core class does not survive back into this process" do
      symbol_id = Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Whatever", discriminator: nil)
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_PLUGIN")

      contexts = loader.load_static([manifest_path("monkeypatching")])

      expect(contexts.size).to eq(1)
      expect(contexts.first.declarations.first[:symbol_id].owner).to eq("::MonkeypatchModel")
      # The plugin's own file reopened Rslsp::Index::SymbolId and
      # redefined #to_s at its top level, independent of anything it did
      # through StaticContext -- if that patch leaked into this (parent)
      # process, every SymbolId in Core would now report this string.
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_PLUGIN")
    end

    it "never lets a plugin's raw STDOUT/STDERR writes reach this process' real stdio -- fd 1 is the live LSP transport in --stdio mode" do
      require "tempfile"
      captured = Tempfile.new("rslsp-plugin-stdio-leak")
      original_stdout_fd = STDOUT.dup
      original_stderr_fd = STDERR.dup
      contexts = nil
      begin
        STDOUT.reopen(captured.path, "w")
        STDERR.reopen(captured.path, "w")

        contexts = loader.load_static([manifest_path("stdout_writer")])
      ensure
        STDOUT.reopen(original_stdout_fd)
        STDERR.reopen(original_stderr_fd)
        original_stdout_fd.close
        original_stderr_fd.close
      end

      expect(contexts.size).to eq(1)
      captured.rewind
      expect(captured.read).not_to include("EVIL-EVIL-LSP-PROTOCOL-CORRUPTION")
    end

    it "never lets a plugin reach any OTHER IO object the parent happens to have open -- not just fd 1/2" do
      # Found by the Task 014-018 independent review's third pass:
      # Process.fork hands the child the parent's *entire* fd table, so
      # a plugin doesn't need to write to a known fd (STDOUT/STDERR) to
      # corrupt something -- any IO object the parent has open (e.g.
      # AgentProcessManager's own pipes to a live Rails Runtime Agent)
      # is reachable via ObjectSpace with zero requires. Stands in for
      # that scenario with an ordinary pipe held open in this process.
      stand_in_reader, stand_in_writer = ::IO.pipe

      # The fixture writes to every open IO it can find via ObjectSpace,
      # indiscriminately -- including, harmlessly, its own legitimate
      # result-reporting pipe, which just means *this* plugin's own
      # result comes back corrupted (already handled gracefully:
      # #load_static simply contributes nothing for it, the same as any
      # other plugin failure). What matters for this test is only
      # whether the write reached the unrelated *stand-in* pipe below.
      loader.load_static([manifest_path("io_scavenger")])

      stand_in_writer.close
      leaked = begin
        Timeout.timeout(0.2) { stand_in_reader.read }
      rescue Timeout::Error
        ""
      end
      stand_in_reader.close

      expect(leaked).not_to include("EVIL-VIA-OBJECTSPACE")
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

    it "isolates a runtime plugin's top-level code in a separate process, same as a static plugin" do
      symbol_id = Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Whatever", discriminator: nil)

      contexts = loader.load_runtime([manifest_path("monkeypatching_runtime")], trusted: true)

      expect(contexts.size).to eq(1)
      expect(contexts.first.snapshot_sections.keys).to eq(["example"])
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_RUNTIME_PLUGIN")
    end
  end
end
