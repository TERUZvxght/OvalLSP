# frozen_string_literal: true

require "rbconfig"
require "tmpdir"

RSpec.describe Rslsp::RailsBootstrap do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:fixture_root) { File.join(core_root, "spec/fixtures/rails_minimal") }
  let(:boot_script) { File.join(core_root, "lib/rslsp/runtime_agent/boot.rb") }
  let(:environment_file) { File.join(fixture_root, "config/environment.rb") }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:route_registry) { Rslsp::Routes::RouteRegistry.new }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }

  after { @manager&.stop }

  describe ".rails_app?" do
    it "is true when both bin/rails and config/environment.rb exist at the root" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "bin", "rails"), "#!/usr/bin/env ruby\n")
        File.write(File.join(dir, "config", "environment.rb"), "\n")

        expect(described_class.rails_app?(dir)).to be(true)
      end
    end

    it "is false when bin/rails exists but config/environment.rb doesn't" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "bin"))
        File.write(File.join(dir, "bin", "rails"), "#!/usr/bin/env ruby\n")

        expect(described_class.rails_app?(dir)).to be(false)
      end
    end

    it "is false for a plain directory" do
      Dir.mktmpdir { |dir| expect(described_class.rails_app?(dir)).to be(false) }
    end
  end

  describe ".start" do
    it "returns nil without spawning anything when the root isn't a Rails app and no command is injected" do
      Dir.mktmpdir do |dir|
        result = described_class.start(root: dir, logger: logger, route_registry: route_registry,
                                        model_registry: model_registry)

        expect(result).to be_nil
        expect(route_registry.completion_names("")).to be_empty
      end
    end

    it "populates both registries from a real Runtime Agent's snapshot (injected command, standing in for bin/rails runner)" do
      @manager = described_class.start(
        root: fixture_root, logger: logger, route_registry: route_registry, model_registry: model_registry,
        command: RbConfig.ruby, args: ["-I", File.join(core_root, "lib"), boot_script, "start", environment_file]
      )

      expect(@manager.status).to eq(:ready)
      expect(route_registry.completion_names("post_")).to include("post_path")
      expect(model_registry.known_model?("User")).to be(true)
      expect(model_registry.association("User", "company").class_name).to eq("Company")
    end

    it "logs a warning and leaves the registries empty when the Agent never becomes ready" do
      unresponsive = File.join(core_root, "spec/fixtures/unresponsive_agent/boot.rb")

      @manager = described_class.start(
        root: core_root, logger: logger, route_registry: route_registry, model_registry: model_registry,
        command: RbConfig.ruby, args: [unresponsive], hello_timeout: 0.5
      )

      expect(@manager.status).to eq(:static_only)
      expect(logger).to have_received(:warn).with(/static-only/).at_least(:once)
      expect(route_registry.completion_names("")).to be_empty
    end

    it "spawns boot.rb as a plain ruby process with the environment file as an argument, not via `bin/rails runner`" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "bin"))
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "bin", "rails"), "#!/usr/bin/env ruby\n")
        File.write(File.join(dir, "config", "environment.rb"), "\n")

        fake_manager = instance_double(Rslsp::AgentProcessManager, start: :static_only)
        captured = nil
        allow(Rslsp::AgentProcessManager).to receive(:new) do |**kwargs|
          captured = kwargs
          fake_manager
        end

        described_class.start(root: dir, logger: logger, route_registry: route_registry,
                               model_registry: model_registry)

        expect(captured[:command]).to eq("bundle")
        # Must NOT be `bin/rails runner` — that boots Rails (running every
        # initializer) before boot.rb gets a chance to protect stdout.
        expect(captured[:args]).to eq(
          ["exec", "ruby", Rslsp::RailsBootstrap::BOOT_SCRIPT, "start", File.join(dir, "config", "environment.rb")]
        )
        # If Core Server's own process was launched via `bundle exec`,
        # BUNDLE_GEMFILE is already set and would otherwise be inherited
        # verbatim by this child, silently pointing its `bundle exec` at
        # Core's own Gemfile instead of the target Rails app's
        # (docs/design/tasks/008.5-runtime-and-index-corrections.md) --
        # `nil` here must be passed through to unset it for the child,
        # not merely omitted.
        expect(captured[:env]).to eq("BUNDLE_GEMFILE" => nil)
      end
    end
  end
end
