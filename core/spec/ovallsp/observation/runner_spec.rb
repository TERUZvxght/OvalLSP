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
  # `killer:` exists for the one example below that deliberately stubs
  # Process.kill into failing: its cleanup has to use the *real* one
  # (captured before the stub was installed), or the leftover it is there
  # to reap would survive the example that created it.
  def kill_leftover(pid, killer: Process.method(:kill))
    return unless pid

    killer.call("KILL", -Process.getpgid(pid))
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
    pid_file = File.join(example_tmpdir("ovallsp-observation-pgroup"), "grandchild.pid")
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
    pid_file = File.join(example_tmpdir("ovallsp-observation-interrupt"), "grandchild.pid")
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

  # Found by an independent review (round 11) of Task 022.2. #kill's own
  # docs already named Errno::EPERM as a signal failure that can happen --
  # but #kill only retried the bare pid on Errno::ESRCH (the one failure
  # meaning "already gone", i.e. the one that needs no retry), so any
  # other failure left the child completely unsignalled, and #reap's
  # unbounded `Process.waitpid(pid)` then blocked on it forever. That is
  # not a stray zombie: this is the last thing the *timeout* path runs,
  # and Server#run_observed_tests_result calls #run synchronously on the
  # LSP transport thread, so `timeout_seconds` silently became "hang the
  # user's whole editor session". Same shape for a child that outlives
  # SIGKILL for any other reason (an uninterruptible kernel wait on a
  # wedged network mount).
  #
  # Bounded by Thread#join, NOT by wrapping #run in an outer
  # Timeout.timeout -- and that is the whole difference between a guard
  # and a decoration (found by an independent review, round 12). #run's
  # contract is a blanket `rescue StandardError`, and Timeout::Error is a
  # RuntimeError, so an outer Timeout raises *into* the code under test
  # and #run swallows it and returns nil: the assertions still pass. The
  # original version of this test did exactly that and passed against
  # pre-round-11 Runner -- it merely took 60s instead of 3s, because
  # `hang.rb` happens to `sleep 60` and the unbounded `Process.waitpid`
  # eventually returned when the child died of old age. A join deadline is
  # measured from outside the thread and cannot be intercepted by anything
  # #run rescues.
  it "still honours its own timeout when the kill signal fails to land rather than the child ignoring it" do
    real_kill = Process.method(:kill)
    spawned = nil
    allow(Process).to receive(:spawn).and_wrap_original do |original, *args, **options|
      spawned = original.call(*args, **options)
    end
    allow(Process).to receive(:kill).and_wrap_original do |original, signal, target|
      raise Errno::EPERM if signal == "KILL"

      original.call(signal, target)
    end

    results = :unset
    error = nil
    worker = Thread.new do
      results = runner.run(command: "ruby", args: ["hang.rb"], workspace_root: fixtures_root, timeout_seconds: 1)
    rescue Exception => e # rubocop:disable Lint/RescueException -- #run's contract is that nothing at all escapes it here
      error = e
    end

    # Generously above `timeout_seconds` + REAP_TIMEOUT_SECONDS, so this
    # only ever trips for a genuinely unbounded wait, never a slow one --
    # and well under `hang.rb`'s own 60s lifetime, so a run that is merely
    # waiting the child out still fails.
    expect(worker.join(15)).not_to be_nil, "Runner#run never returned -- its own timeout_seconds blocked forever"
    expect(error).to be_nil
    expect(results).to be_nil
    # `nil` is #run's answer to *every* failure, so on its own it does not
    # witness that this run reached the kill path at all -- a spawn that
    # never happened would satisfy it just as well. Pinning the timeout log
    # keeps the example a guard rather than a decoration, the same lesson
    # round 12 drew about this test's own outer bound (round 13).
    expect(logger).to have_received(:error).with(a_string_matching(/exceeded 1s -- killing it/))
    expect(spawned).not_to be_nil
  ensure
    worker&.kill
    kill_leftover(spawned, killer: real_kill)
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
    allow(File).to receive(:binread).with(a_string_including("ovallsp-observation")).and_return("not a payload")

    expect(runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)).to be_nil
  end

  # The sibling of the test above, covering #read_results' *other*
  # untrusted-payload branch: a payload that parses perfectly well but
  # isn't the envelope Harness writes (a version skew, a stale result
  # file from an older Core) never reaches the rescue the corrupt case
  # does, so "corrupt" coverage alone doesn't imply it.
  it "returns nil, not an empty array, when the result payload parses to the wrong shape" do
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(a_string_including("ovallsp-observation"))
                                    .and_return(JSON.generate({ "not" => "signatures" }))

    expect(runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)).to be_nil
  end

  # `024.135`, and the same argument `plugins/loader_spec.rb` makes one
  # boundary over for `024.73`. The subprocess runs the workspace's own
  # test command, so those bytes are written by code Core did not author,
  # and `Marshal.load` instantiates whatever classes the stream names --
  # in Core's process, before the shape check below it looks at anything.
  # Driven at `bdd0ebe` before the fix: `#read_results` answered `nil`,
  # having already run a `marshal_load` hook the payload carried.
  #
  # Asserted as "never calls it" rather than by demonstrating a gadget:
  # a gadget is a property of whichever classes happen to be loaded, so a
  # passing gadget test would be evidence about this Gemfile, while this
  # is evidence about the boundary. It fails the moment anyone puts
  # `Marshal.load` back on this path.
  it "never reconstructs the subprocess's results with Marshal" do
    expect(Marshal).not_to receive(:load)

    results = runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)

    expect(results.map { |r| r.symbol_id.name }).to include("add")
  end

  # The other half: a result file holding a Marshal payload -- what the
  # harness used to write, and what a stale file from an older Core still
  # holds -- produces no run rather than a decoded object graph.
  it "rejects a Marshal payload in the result file instead of loading it" do
    signature = Ovallsp::Observation::ObservedSignature.new(
      symbol_id: sym(kind: :instance_method, owner: "::Calculator", name: "add"),
      parameter_types: [], return_type: Ovallsp::Types::UNKNOWN, samples: 1,
      run_id: "run", code_fingerprint: "fp", created_at: Time.now
    )
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(a_string_including("ovallsp-observation"))
                                    .and_return(Marshal.dump([signature]))

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

  # Found by an independent review (round 15) of Task 022.2, sweeping every
  # resource-owning method in Core for the "cleanup only runs when nothing
  # went wrong" shape rounds 10/14/15 found at the three subprocess sites.
  # #run's `ensure` was already total, but `Tempfile#unlink` only removes
  # the directory entry -- it leaves the descriptor open -- so when the
  # *second* `Tempfile.new` raises (a full or unwritable TMPDIR,
  # Errno::EMFILE), the first file's fd was stranded until GC happened to
  # finalize it. Same fix as everywhere else: close on every path.
  # Asserts on the tempfiles themselves rather than on a count of
  # /dev/fd: that count is process-wide, so unrelated descriptors opened
  # or finalized by anything else in the process land in the difference,
  # and a full-suite run observed it going *negative*. Every file this
  # method opened being closed is the actual claim, and it distinguishes
  # the same regression without depending on what the rest of the process
  # is doing.
  it "closes the result tempfile it already opened when creating the log tempfile fails" do
    real_new = Tempfile.method(:new)
    opened = []
    calls = 0
    allow(Tempfile).to receive(:new) do |*args|
      calls += 1
      raise Errno::ENOSPC if calls.even?

      real_new.call(*args).tap { |file| opened << file }
    end

    10.times { runner.run(command: "ruby", args: ["-e", "1"], workspace_root: fixtures_root) }

    expect(opened).not_to be_empty
    stranded = opened.reject(&:closed?)
    expect(stranded).to be_empty, "#run stranded #{stranded.size} open tempfile(s) across 10 failed starts"
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
        original.call(RbConfig.ruby, "-e", "") # a real, immediately-exiting child, so #wait_for_exit still works
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

  # Found by an independent review (round 19) of Task 022.2. #run's
  # `ensure` was a bare two-step straight line -- `output_file&.close!`
  # then `log_file&.close!` -- and `Tempfile#close!` is not total: its
  # `unlink` rescues only Errno::ENOENT/EACCES, so Errno::EROFS (a TMPDIR
  # remounted read-only after the disk filled), EPERM (an immutable or
  # append-only TMPDIR), EIO and EBUSY all escape it. That is the same
  # "cleanup that only runs when the step before it didn't raise" shape
  # rounds 15 and 16 fixed in AgentProcessManager, one level in: the
  # `ensure` existed, its body did not honour the same contract.
  #
  # Both halves are asserted, because they are separate failures:
  # the *second* temp file is stranded on disk with nothing left that
  # would ever unlink it, and the Errno escapes #run entirely -- whose
  # documented contract is "Never raises", the contract round 6 opened to
  # make structural and round 13 had to re-open for a second method.
  describe "temp-file discard (round 19)" do
    # Real Tempfiles, so the assertion is about a real on-disk file being
    # unlinked rather than about a double receiving a message. Only the
    # *first* one's #close! is broken; everything else behaves normally.
    def stub_tempfiles_with_a_broken_first_discard
      first = Tempfile.new(["ovallsp-observation-spec", ".marshal"])
      second = Tempfile.new(["ovallsp-observation-spec", ".log"])
      # The broken discard is the whole point, so nothing under test will
      # ever unlink `first` -- this spec must not itself leave litter in
      # TMPDIR (see the sibling `Dir.mktmpdir` fix in this same round).
      @leftover_paths = [first.path, second.path]
      allow(first).to receive(:close!).and_raise(Errno::EROFS)
      allow(Tempfile).to receive(:new).and_return(first, second)
      [first, second]
    end

    after do
      Array(@leftover_paths).each do |path|
        File.unlink(path)
      rescue SystemCallError
        nil
      end
    end

    it "still discards the second temp file when discarding the first one raises" do
      _first, second = stub_tempfiles_with_a_broken_first_discard
      second_path = second.path

      # Swallowed deliberately, so this example measures the *stranded
      # file* specifically rather than collapsing into the sibling
      # example's "it raised at all" -- pre-fix both are true, and they
      # are two different costs.
      begin
        runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)
      rescue SystemCallError
        nil
      end

      expect(File.exist?(second_path)).to be(false)
    end

    it "does not let a failing discard raise out of #run, whose contract is that it never does" do
      stub_tempfiles_with_a_broken_first_discard

      expect do
        runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)
      end.not_to raise_error
    end

    # The sharpest edge of the same defect: an `ensure` that raises
    # *replaces* whatever was already propagating, and #run deliberately
    # lets Interrupt through (round 9 -- a Ctrl-C must really kill the
    # editor's server). Pre-fix this reported Errno::EROFS instead.
    it "lets an in-flight Interrupt survive a failing discard rather than replacing it" do
      stub_tempfiles_with_a_broken_first_discard
      allow(Process).to receive(:waitpid2).and_raise(Interrupt)

      expect do
        runner.run(command: "ruby", args: ["run_tests.rb"], workspace_root: fixtures_root)
      end.to raise_error(Interrupt)
    end
  end
end
