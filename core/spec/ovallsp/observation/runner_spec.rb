# frozen_string_literal: true

require "tmpdir"

RSpec.describe Ovallsp::Observation::Runner do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../../fixtures/observation_runner", __dir__) }

  subject(:runner) { described_class.new(logger: logger) }

  def sym(kind:, owner:, name:) = Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil)

  # SIGKILL delivery and the subsequent reparent-and-reap by init are not
  # instantaneous, so poll briefly rather than sampling once -- an
  # orphaned process stays alive indefinitely, so a real failure never
  # needs the full budget to show itself.
  def process_gone?(pid, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      Process.kill(0, pid)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    rescue Errno::ESRCH
      return true
    end
  end

  # Never leave a stray `sleep 120` behind if the expectation above it
  # failed (i.e. exactly when the process is still running). Signals the
  # leftover's whole group, because the shape being asserted about is a
  # wrapper *plus* its grandchild -- killing the recorded pid alone would
  # itself leak the wrapper on every failure.
  def kill_leftover(pid)
    return unless pid

    Process.kill("KILL", -Process.getpgid(pid))
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # Blocks until the wrapper fixture has recorded its grandchild's pid,
  # so a test that must act "while the run is genuinely in flight" never
  # races the child's startup.
  def await_grandchild_pid(pid_file, timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return Integer(File.read(pid_file))
    rescue StandardError
      raise "fixture never recorded its grandchild pid" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end

  it "observes a real, separately-spawned Ruby process running the workspace's own test command" do
    results = runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)

    signature = results.find { |r| r.symbol_id == sym(kind: :instance_method, owner: "::Calculator", name: "add") }
    expect(signature).not_to be_nil
    expect(signature.parameter_types).to eq([Ovallsp::Types::Nominal.new(name: "Integer"), Ovallsp::Types::Nominal.new(name: "Integer")])
    expect(signature.return_type).to eq(Ovallsp::Types::Nominal.new(name: "Integer"))
  end

  # Found by an independent review (round 7) of Task 022.2. Every failure
  # mode below used to return `[]`, indistinguishable from "the suite ran
  # and genuinely observed nothing" -- and Server#run_observed_tests_result
  # feeds that straight into Store#replace_run, a full generation swap. So
  # one broken run wiped every signature the user had already accumulated.
  # See Runner#run's own docs; same conflation Task 008.6 fixed for
  # RailsBootstrap's `fetch_all_models || []`.
  it "returns nil, not an empty array, without raising, when the test command itself crashes" do
    results = :unset
    expect { results = runner.run(command: "ruby", args: ["crash.rb"], workspace_root: fixtures_root) }.not_to raise_error

    expect(results).to be_nil
  end

  it "kills a hung test command past the timeout and returns nil, without raising" do
    results = :unset
    expect do
      results = runner.run(command: "ruby", args: ["hang.rb"], workspace_root: fixtures_root, timeout_seconds: 1)
    end.not_to raise_error

    expect(results).to be_nil
  end

  # Found by an independent review (round 9) of Task 022.2. The timeout
  # kill signalled only the pid Runner itself spawned, but the workspace's
  # configured test command is arbitrary and almost always a *wrapper*
  # that forks (`bin/rails test`, `make test`, `npm test`, `docker compose
  # run ...`, a shell wrapper, or Ruby's own single-string shell fallback).
  # So a hung suite survived its own timeout: Runner reaped the wrapper,
  # reported "no evidence", and left the real test process running
  # unsupervised forever, holding DB connections, ports and CPU with
  # nothing left that knew its pid.
  it "kills the hung command's whole process group, not just the wrapper it spawned" do
    pid_file = File.join(Dir.mktmpdir("ovallsp-observation-pgroup"), "grandchild.pid")
    runner.run(command: "ruby", args: ["hang_with_child.rb", pid_file], workspace_root: fixtures_root,
               timeout_seconds: 2)

    grandchild = Integer(File.read(pid_file))
    expect(process_gone?(grandchild)).to be(true)
  ensure
    kill_leftover(grandchild)
  end

  # Found by an independent review (round 10) of Task 022.2, and the
  # other half of the leak round 9 fixed above. Timing out is not the
  # only way control leaves #spawn_and_collect with the child still
  # running, and every other way left the workspace's whole test tree
  # orphaned onto init forever. Interrupt is the reachable one: #run
  # rescues `StandardError` on purpose (round 9 -- a Ctrl-C must really
  # kill the editor's server rather than be logged as "no evidence"), so
  # a Ctrl-C arriving while Runner blocks waiting on the test command
  # propagates past every rescue in the class. Round 9's own `pgroup:
  # true` is what makes it unconditional: the child used to share Core's
  # process group, so a terminal delivered it the same SIGINT by
  # accident, and under an editor (`--stdio`, no controlling tty) there
  # was no such delivery even then.
  it "kills the workspace's whole test tree when the wait is interrupted rather than timing out" do
    pid_file = File.join(Dir.mktmpdir("ovallsp-observation-interrupt"), "grandchild.pid")
    allow(Process).to receive(:waitpid2) do
      await_grandchild_pid(pid_file) # only interrupt once the tree genuinely exists
      raise Interrupt
    end

    expect do
      runner.run(command: "ruby", args: ["hang_with_child.rb", pid_file], workspace_root: fixtures_root)
    end.to raise_error(Interrupt)

    grandchild = Integer(File.read(pid_file))
    expect(process_gone?(grandchild)).to be(true)
  ensure
    kill_leftover(grandchild)
  end

  it "returns nil, not an empty array, when the command name doesn't resolve to anything at all" do
    results = :unset
    expect do
      results = runner.run(command: "ovallsp-definitely-not-an-executable", args: [], workspace_root: fixtures_root)
    end.not_to raise_error

    expect(results).to be_nil
  end

  it "returns nil, not an empty array, when the result file is corrupt rather than merely empty" do
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(a_string_including("ovallsp-observation")).and_return("not a Marshal payload")

    expect(runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)).to be_nil
  end

  # The sibling of the test above, covering #read_results' *other*
  # untrusted-payload branch: a payload that deserializes perfectly well
  # but isn't an Array of ObservedSignature (a version skew, a stale
  # result file from an older Core) never reaches the rescue the corrupt
  # case does, so "corrupt" coverage alone doesn't imply it.
  it "returns nil, not an empty array, when the result payload deserializes to the wrong shape" do
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(a_string_including("ovallsp-observation"))
                                    .and_return(Marshal.dump({ "not" => "signatures" }))

    expect(runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)).to be_nil
  end

  # Found by an independent review (round 8) of Task 022.2, and the same
  # harm round 7 fixed for every other failure mode -- still reachable
  # through the one door left open. Harness#dump always writes
  # `Marshal.dump(results)` (4 bytes even for zero observations), so a
  # zero-byte result file means the harness never ran at all. That is the
  # normal shape of an ordinary configuration -- a non-Ruby test command,
  # a wrapper that re-execs with a sanitized env, a Spring-style preloader
  # -- and every one of them exits *zero*, so the exit-status check can't
  # catch it. `return [] if raw.empty?` therefore handed Server a trusted
  # empty run: a full Store#replace_run generation swap destroying every
  # signature the user had accumulated.
  it "returns nil, not an empty array, when the command exits cleanly but the harness never wrote results" do
    expect(runner.run(command: "ruby", args: ["no_harness_output.rb"], workspace_root: fixtures_root)).to be_nil
  end

  # The other half of the same distinction -- the fix must not collapse
  # into "always nil". A command that exits cleanly having observed
  # nothing is a completed run with zero evidence, and Server is supposed
  # to install that (emptying the store) rather than preserve stale
  # evidence.
  it "returns an empty array, not nil, for a test command that completes cleanly having observed nothing" do
    expect(runner.run(command: "ruby", args: ["no_observations.rb"], workspace_root: fixtures_root)).to eq([])
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
  it "returns nil, without raising, when the workspace root doesn't exist at all" do
    missing = File.join(fixtures_root, "definitely-not-a-real-directory")
    results = :unset

    expect { results = runner.run(command: "ruby", args: [], workspace_root: missing) }.not_to raise_error
    expect(results).to be_nil
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
