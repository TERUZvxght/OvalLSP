# frozen_string_literal: true

require "rbconfig"
require "tmpdir"

RSpec.describe Ovallsp::RailsBootstrap do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:fixture_root) { File.join(core_root, "spec/fixtures/rails_minimal") }
  let(:boot_script) { File.join(core_root, "lib/ovallsp/runtime_agent/boot.rb") }
  let(:environment_file) { File.join(fixture_root, "config/environment.rb") }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:route_registry) { Ovallsp::Routes::RouteRegistry.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }

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

    it "keeps the last-known-good models instead of wiping the registry when fetch_all_models fails (Task 008.6)" do
      model_registry.register_from_agent_response(
        "User", { name: "User", tableName: "users", columns: [], associations: [], partial: false }
      )
      fake_manager = instance_double(
        Ovallsp::AgentProcessManager,
        fetch_snapshot: { routes: [] },
        fetch_all_models: nil # simulates a timeout/communication failure, not a genuinely empty app
      )

      Ovallsp::RailsBootstrap.populate_registries(
        fake_manager, route_registry: route_registry, model_registry: model_registry, logger: logger
      )

      expect(model_registry.known_model?("User")).to be(true)
      expect(logger).to have_received(:warn).with(/leaving model_registry as-is/)
    end

    it "keeps the last-known-good routes instead of wiping the registry when fetch_snapshot fails (Task 008.6)" do
      route_registry.replace(
        [{ name: "existing", verb: "GET", pathTemplate: "/existing", requiredParts: [], optionalParts: [],
           defaults: { controller: "existing", action: "index" }, sourceLocation: nil, routeSet: "main_app" }]
      )
      fake_manager = instance_double(Ovallsp::AgentProcessManager, fetch_snapshot: nil, fetch_all_models: [])

      Ovallsp::RailsBootstrap.populate_registries(
        fake_manager, route_registry: route_registry, model_registry: model_registry, logger: logger
      )

      expect(route_registry.completion_names("existing")).to include("existing_path")
      expect(logger).to have_received(:warn).with(/leaving route_registry as-is/)
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

        fake_manager = instance_double(Ovallsp::AgentProcessManager, start: :static_only)
        captured = nil
        allow(Ovallsp::AgentProcessManager).to receive(:new) do |**kwargs|
          captured = kwargs
          fake_manager
        end

        described_class.start(root: dir, logger: logger, route_registry: route_registry,
                               model_registry: model_registry)

        expect(captured[:command]).to eq("bundle")
        # Must NOT be `bin/rails runner` — that boots Rails (running every
        # initializer) before boot.rb gets a chance to protect stdout.
        expect(captured[:args]).to eq(
          ["exec", "ruby", Ovallsp::RailsBootstrap::BOOT_SCRIPT, "start", File.join(dir, "config", "environment.rb")]
        )
        # Core and the target Rails app are separate Bundle graphs --
        # Core's own BUNDLE_GEMFILE/BUNDLE_PATH/BUNDLE_APP_CONFIG (and
        # RUBYOPT's "-rbundler/setup", RUBYLIB's Core-bundler-lib entry)
        # must never leak into this child's `bundle exec`
        # (docs/design/tasks/008.5-runtime-and-index-corrections.md
        # first found this for BUNDLE_GEMFILE alone; a later review found
        # the same leak for BUNDLE_PATH/BUNDLE_APP_CONFIG, closed by
        # BundleEnvironment). Compared against BundleEnvironment's own
        # output rather than a hardcoded Hash literal, since exactly
        # which keys need nil-ing out depends on which Bundler-owned
        # variables are actually live in whatever environment is running
        # this spec -- the contract is "matches BundleEnvironment for
        # this workspace", not "matches this one machine's env snapshot".
        expect(captured[:env]).to eq(Ovallsp::BundleEnvironment.for_workspace(dir))
      end
    end
  end
end
