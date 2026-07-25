# frozen_string_literal: true

RSpec.describe Ovallsp::Observation::Runner do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../../fixtures/observation_runner", __dir__) }

  subject(:runner) { described_class.new(logger: logger) }

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  it "observes a real, separately-spawned Ruby process running the workspace's own test command" do
    results = runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)

    signature = results.find { |r| r.symbol_id == sym(kind: :instance_method, owner: "::Calculator", name: "add") }
    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "Integer")])
    expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
  end

  it "returns an empty array, without raising, when the test command itself crashes" do
    results = nil
    expect { results = runner.run(command: "ruby", args: ["crash.rb"], workspace_root: fixtures_root) }.not_to raise_error

    expect(results).to eq([])
  end

  it "kills a hung test command past the timeout and returns an empty array, without raising" do
    results = nil
    expect do
      results = runner.run(command: "ruby", args: ["hang.rb"], workspace_root: fixtures_root, timeout_seconds: 1)
    end.not_to raise_error

    expect(results).to eq([])
  end

  # Found by an independent review (round 6) of Task 022.2. Everything
  # before the spawn -- Tempfile creation, and (since round 5 routed env
  # construction through BundleEnvironment.for_workspace)
  # `File.realpath(workspace_root)` plus the workspace Gemfile probe --
  # ran outside any rescue, so a workspace deleted or renamed while the
  # editor is still open made #run raise Errno::ENOENT despite its own
  # documented "never raises" contract, turning the user's explicit
  # `Run Tests with Type Observation` command into a bare LSP
  # `internal error` instead of an empty, logged result.
  it "returns an empty array, without raising, when the workspace root doesn't exist at all" do
    missing = File.join(fixtures_root, "definitely-not-a-real-directory")
    results = nil

    expect { results = runner.run(command: "ruby", args: [], workspace_root: missing) }.not_to raise_error
    expect(results).to eq([])
  end

  # Task 022.2 (found by an independent review, round 5): the command
  # spawned here is the *workspace's* own test command -- in practice
  # `bundle exec rspec` -- so it is a second instance of the exact Bundler
  # boundary RailsBootstrap.start already goes through. Before this fix
  # #harness_env returned four bare overrides on top of a fully inherited
  # ENV, so Core's own BUNDLE_GEMFILE/BUNDLE_PATH/BUNDLER_SETUP/
  # BUNDLER_VERSION, bundle-exec-derived GEM_HOME/GEM_PATH and PATH entry
  # all leaked into the workspace's separate Bundle graph.
  describe "Bundler boundary isolation (Task 022.2)" do
    let(:polluted_env) do
      {
        "BUNDLE_GEMFILE" => "/repo/core/Gemfile",
        "BUNDLE_PATH" => "/tmp/core-only-bundle",
        "BUNDLER_SETUP" => "/repo/core/.bundle/bundler/setup",
        "BUNDLER_VERSION" => Bundler::VERSION,
        "GEM_HOME" => "/tmp/core-only-bundle/ruby/3.4.0",
        "GEM_PATH" => "",
        "PATH" => "/tmp/core-only-bundle/ruby/3.4.0/bin:/usr/bin:/bin",
        "RUBYOPT" => "-W2 -r/repo/core/.bundle/bundler/setup"
      }
    end

    # Captures the env Hash actually handed to Process.spawn, without
    # running anything.
    def captured_spawn_env(workspace_root, env_source)
      captured = nil
      allow(Process).to receive(:spawn).and_wrap_original do |original, env, *|
        captured = env
        original.call(RbConfig.ruby, "-e", "") # a real, immediately-exiting child, so #wait_with_timeout still works
      end
      runner.run(command: "ruby", args: [], workspace_root: workspace_root, env_source: env_source)
      captured
    end

    it "spawns the workspace's test command through BundleEnvironment, not on top of Core's raw ENV" do
      env = captured_spawn_env(fixtures_root, polluted_env)

      expect(env).to include(Ovallsp::BundleEnvironment.for_workspace(fixtures_root, env: polluted_env)
                                                       .reject { |k, _| k == "RUBYOPT" })
    end

    it "does not leak Core's bundle-exec bin directory onto the workspace test command's PATH" do
      env = captured_spawn_env(fixtures_root, polluted_env)

      expect(env["PATH"].split(File::PATH_SEPARATOR)).to eq(%w[/usr/bin /bin])
    end

    # The old implementation didn't merely fail to strip this -- it
    # explicitly re-propagated `ENV["RUBYOPT"]` verbatim, so Core's own
    # `bundler/setup` was auto-required (running Bundler.setup against
    # Core's Gemfile) inside the workspace's test process.
    it "injects the harness into RUBYOPT without carrying Core's own bundler/setup flag" do
      env = captured_spawn_env(fixtures_root, polluted_env)

      flags = env["RUBYOPT"].split(" ")
      expect(flags).to include("-W2", "-r#{Ovallsp::Observation::Runner::HARNESS_PATH}")
      expect(flags).not_to include(a_string_ending_with("bundler/setup"))
    end
  end

  it "never lets the spawned process' stdout/stderr reach this process' own real stdio" do
    captured = Tempfile.new("ovallsp-observation-runner-stdio")
    original_stdout_fd = STDOUT.dup
    begin
      STDOUT.reopen(captured.path, "w")
      runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)
    ensure
      STDOUT.reopen(original_stdout_fd)
      original_stdout_fd.close
    end

    captured.rewind
    expect(captured.read).not_to include("fixture test command ran")
  end
end
