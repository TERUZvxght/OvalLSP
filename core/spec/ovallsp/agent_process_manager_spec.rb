# frozen_string_literal: true

require "rbconfig"

RSpec.describe Ovallsp::AgentProcessManager do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:fixture_root) { File.join(core_root, "spec/fixtures/rails_minimal") }
  let(:boot_script) { File.join(core_root, "lib/ovallsp/runtime_agent/boot.rb") }
  let(:environment_file) { File.join(fixture_root, "config/environment.rb") }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def build_manager(hello_timeout: 5)
    described_class.new(
      command: RbConfig.ruby,
      args: ["-I", File.join(core_root, "lib"), boot_script, "start", environment_file],
      chdir: fixture_root,
      logger: logger,
      hello_timeout: hello_timeout
    )
  end

  after do
    @manager&.stop
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  it "receives the fixture app's Rails root and version via agent/hello" do
    @manager = build_manager
    status = @manager.start

    expect(status).to eq(:ready)
    expect(@manager.hello_result[:railsVersion]).to eq("7.1.0-fixture")
    expect(@manager.hello_result[:root]).to eq(File.expand_path(fixture_root))
    expect(@manager.hello_result[:rubyVersion]).to eq(RUBY_VERSION)
  end

  it "connects successfully even though the fixture's initializer writes to stdout" do
    @manager = build_manager

    expect(@manager.start).to eq(:ready)
    # If the noisy `puts` in config/environment.rb had reached the protocol
    # stream instead of stderr, the Content-Length framing would have been
    # corrupted and hello would have timed out instead of succeeding.
    expect(logger).to have_received(:info).with(/accidental stdout from a noisy initializer/)
    # Some gems/frameworks write via the STDOUT *constant* directly rather
    # than the reassignable $stdout global; boot.rb must redirect both.
    expect(logger).to have_received(:info).with(/accidental stdout via the STDOUT constant directly/)
  end

  it "isolates a raw fd-1 write and a child process' inherited stdout, not just $stdout/STDOUT (Task 008.6)" do
    @manager = build_manager

    # If any of these three had reached the protocol pipe, Content-Length
    # framing would have been corrupted (extra/garbled bytes before the
    # next frame) and either hello would time out, or a later request
    # would get a mismatched/garbage response instead of failing cleanly.
    # A Ruby-level `$stdout`/`STDOUT` swap alone (Task 008.5) does not
    # stop any of the three, because none of them go through a Ruby IO
    # object at all -- boot.rb must redirect file descriptor 1 itself.
    expect(@manager.start).to eq(:ready)
    expect(@manager.request_status[:pid]).to eq(@manager.pid) # protocol wasn't corrupted by any of the below

    expect(logger).to have_received(:info).with(/accidental raw fd1 write via IO\.for_fd\(1\)/)
    expect(logger).to have_received(:info).with(/accidental stdout from a child process via system/)
    # Open3.capture2 pipes its child's stdout back into a Ruby string
    # rather than letting it inherit fd 1 at all, so it can't corrupt the
    # protocol either way -- this only proves boot doesn't crash when the
    # target app happens to use it (no assertion on stdout forwarding).
  end

  it "answers agent/status once ready" do
    @manager = build_manager
    @manager.start

    result = @manager.request_status
    expect(result[:pid]).to eq(@manager.pid)
  end

  it "degrades to static-only, and stops the process, when hello never arrives in time" do
    @manager = described_class.new(
      command: RbConfig.ruby,
      args: [File.join(core_root, "spec/fixtures/unresponsive_agent/boot.rb")],
      chdir: core_root,
      logger: logger,
      hello_timeout: 0.5
    )

    status = @manager.start

    expect(status).to eq(:static_only)
    expect(@manager.alive?).to be(false)
  end

  it "survives the agent being killed out from under it (crash), degrading to static-only" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    expect { Process.kill("KILL", pid) }.not_to raise_error
    sleep 0.3

    expect { @manager.request_status }.not_to raise_error
    expect(@manager.request_status).to be_nil
    expect(@manager.status).to eq(:static_only)
  end

  it "degrades to static-only after any request times out, not just request_status (Task 008.5)" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    expect { Process.kill("KILL", pid) }.not_to raise_error
    sleep 0.3

    expect(@manager.fetch_model(name: "User", timeout: 0.5)).to be_nil
    expect(@manager.status).to eq(:static_only)
  end

  it "degrades to static-only instead of getting stuck at :ready when the reader thread crashes on a corrupt frame (Task 008.5)" do
    @manager = described_class.new(
      command: RbConfig.ruby,
      args: [File.join(core_root, "spec/fixtures/corrupting_agent/boot.rb")],
      chdir: core_root,
      logger: logger,
      hello_timeout: 5
    )

    expect(@manager.start).to eq(:ready)

    expect(@manager.request_status(timeout: 2)).to be_nil
    expect(@manager.status).to eq(:static_only)
    expect(logger).to have_received(:error).with(/reader thread crashed/)
  end

  it "transitions to static-only the moment the reader thread detects EOF, without any request ever being made (Task 008.6)" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    expect { Process.kill("KILL", pid) }.not_to raise_error

    # No #request_status, #fetch_model, or any other request call here --
    # the whole point is that #status must already reflect the crash on
    # its own, driven directly by the reader thread's own EOF detection,
    # not lazily discovered the next time something happens to ask the
    # Agent for a response.
    became_static_only = wait_until { @manager.status == :static_only }

    expect(became_static_only).to be(true)
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "leaves no process behind after #stop" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    @manager.stop

    expect(@manager.alive?).to be(false)
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end

  # Found by an independent review (round 12) of Task 022.2, the third
  # site in this codebase hand-rolling "signal a child, then wait for it"
  # and the second to get it wrong (see Ovallsp::ChildProcess' own docs;
  # rounds 9-11 fixed the same class in Observation::Runner, round 12 in
  # Plugins::Loader).
  #
  # #terminate_process_locked rescued only Errno::ESRCH around its
  # `Process.kill("TERM", @pid)`. Any other signal failure -- EPERM is the
  # documented one, and #alive? two methods away already treated it as a
  # normal answer, so this class demonstrably considers it reachable --
  # escaped *before* the
  # teardown that follows the kill: the Agent's three pipes stayed open,
  # @reader_thread stayed alive, @pid stayed set, and the exception
  # replaced whatever was already propagating through #stop's own
  # `ensure`, or escaped `at_exit { stop }` outright. Every one of those
  # is a leak of exactly the resources #stop exists to release, triggered
  # by the one path that only ever runs when something is already wrong.
  # Found by an independent review (round 13): #alive? was the fourth
  # hand-rolled Process.kill in Core and the one round 12's migration left
  # behind, because its `rescue Errno::ESRCH, Errno::EPERM` looked
  # exhaustive for signal 0. Enumerating the failures you thought of is
  # the exact mistake ChildProcess exists to stop -- a probe whose job is
  # to answer true/false must not be able to raise instead, least of all
  # from #stop's own teardown window. Errno::EIO stands in here for "any
  # failure the old list didn't name"; the reachable real one is the
  # TypeError from `@pid` being nil'd by a concurrent
  # #terminate_process_locked between the guard and the kill, which the
  # same fix (read @pid once into a local) closes and which no
  # non-flaky test can pin down to a single VM instruction.
  it "answers #alive? as false, rather than raising, for a signal failure its old rescue list never named" do
    @manager = build_manager
    expect(@manager.start).to eq(:ready)
    allow(Process).to receive(:kill).and_raise(Errno::EIO)

    result = :unset
    expect { result = @manager.alive? }.not_to raise_error
    expect(result).to be(false)
  end

  # Found by an independent review (round 15) of Task 022.2, and
  # byte-for-byte the shape round 10 fixed in Observation::Runner and round
  # 14 fixed in Plugins::Loader: every bit of the cleanup #spawn_process
  # owes sat on its straight-line success path, so a `Process.spawn` that
  # *raised* closed none of the six pipe ends it had just opened. `@pid`
  # stays nil on that path, so #start's rescue -> #terminate_process ->
  # `return unless @pid` no-ops, and BackgroundTasks#track_manager then
  # prunes the :static_only manager on the (here false) grounds that it
  # "already tore down its own process internally" -- dropping the last
  # reference that could ever close them deterministically.
  #
  # Counts real descriptors rather than inspecting ivars, because half the
  # leak is in *locals* (the child's three ends) that no ivar assertion can
  # see -- exactly how round 14's own regression tests came to guard only
  # the kill half of round 14's fix and not the pipe-close half (see the
  # matching loader spec, strengthened in the same pass). GC is deliberately
  # never forced: it does eventually close an unreferenced IO, which is why
  # this decayed slowly instead of instantly, but a few dozen bytes per
  # leaked IO exerts no allocation pressure, so in a real session the fd
  # limit arrives long before a collection does. Errno::ENOENT is the real
  # production trigger (a workspace whose `bundle`/`ruby` isn't on the
  # BundleEnvironment-sanitized PATH; a `chdir:` renamed mid-session).
  it "closes every pipe it opened when the Agent process itself can't be spawned" do
    open_fd_count = -> { Dir.children("/dev/fd").size }

    allow(Process).to receive(:spawn).and_raise(Errno::ENOENT)

    build_manager(hello_timeout: 1).start # warm up any lazily-opened fds first
    before = open_fd_count.call
    20.times { build_manager(hello_timeout: 1).start }
    leaked = open_fd_count.call - before

    # Six per attempt pre-fix (120); zero post-fix. The bound is loose
    # enough that unrelated fd churn in the same process can't flake it.
    expect(leaked).to be < 12, "#spawn_process leaked #{leaked} descriptors across 20 failed spawns"
  end

  it "still tears down its pipes, reader thread and pid when the TERM signal itself fails to land" do
    @manager = build_manager
    expect(@manager.start).to eq(:ready)
    pid = @manager.pid
    real_kill = Process.method(:kill)
    allow(Process).to receive(:kill) do |name, target|
      raise Errno::EPERM if name == "TERM"

      real_kill.call(name, target)
    end

    expect { @manager.stop }.not_to raise_error

    expect(@manager.pid).to be_nil
    expect(@manager.status).to eq(:stopped)
    # The SIGKILL escalation is what must still get to run: TERM never
    # landed, so nothing else would have ended this process.
    expect(process_alive?(pid)).to be(false)
  ensure
    begin
      real_kill&.call("KILL", pid)
    rescue Errno::ESRCH, Errno::EPERM, TypeError
      nil
    end
  end

  # Found by an independent review (round 16). Round 15 made
  # #spawn_process's cleanup `ensure`-based and introduced
  # ChildProcess.close_quietly for it; #terminate_process_locked -- the
  # *teardown* half, one method below -- was still a bare straight line
  # (`io&.close`, `@reader_thread&.kill`, `@stderr_thread&.join(1)`,
  # `@pid = nil`) in which any raise abandoned every step after it.
  #
  # `@stdin_write.close` raising Errno::EPIPE is not a contrivance of this
  # stub: `IO#close` flushes first, and this fd is the write end of a pipe
  # into a child we have just SIGTERM'd. A FramedWriter#write_message whose
  # `flush` already hit EPIPE against a dead Agent is an expected, rescued
  # event here (#request_locked logs it and returns nil -- that is what
  # degrades the manager in the first place), and a failed flush leaves the
  # buffer in place, so `close` retries it and raises again. Verified with a
  # bare pipe on this machine's Ruby: flush -> EPIPE, close -> EPIPE.
  #
  # Pre-fix this reproduced end to end: the EPIPE escaped #stop from inside
  # #stop's own `ensure` (the exact "an escaping Errno replaces the
  # exception currently propagating" hazard ChildProcess exists to prevent),
  # @status stayed :static_only, both remaining pipe ends stayed open --
  # and `@pid = nil` never ran. The last of those is the serious one: a
  # stale @pid is a number the kernel may hand to somebody else, and
  # `at_exit { stop }` re-enters teardown at process exit and delivers
  # SIGTERM/SIGKILL to whatever unrelated process inherited it.
  it "completes teardown -- pipes, threads, and above all @pid -- when closing a pipe raises" do
    @manager = build_manager
    expect(@manager.start).to eq(:ready)
    stdout_read = @manager.instance_variable_get(:@stdout_read)
    stderr_read = @manager.instance_variable_get(:@stderr_read)
    allow(@manager.instance_variable_get(:@stdin_write)).to receive(:close).and_raise(Errno::EPIPE)

    expect { @manager.stop }.not_to raise_error

    # A stale pid is the finding, not a detail: nothing may go on holding a
    # signal target the kernel is free to reuse.
    expect(@manager.pid).to be_nil
    expect(@manager.status).to eq(:stopped)
    expect(stdout_read).to be_closed
    expect(stderr_read).to be_closed
    expect(@manager.instance_variable_get(:@reader_thread)).not_to be_alive
  end

  # The other half of the same finding, and the reason the fix is an
  # `ensure` rather than merely routing the closes through
  # ChildProcess.close_quietly: `Thread#join` re-raises whatever exception
  # killed the joined thread, *in the joiner*. #log_stderr rescues only
  # IOError/Errno::EBADF, so a pump thread killed by anything else (
  # `each_line` raising Errno::EIO; `@logger.info` raising Errno::EPIPE or
  # ENOSPC once the editor has closed or filled Core's own stderr) hands
  # its exception to the teardown that was merely winding it down -- and
  # `@pid = nil`, the last statement of all, was the one that paid.
  # BackgroundTasks#reclaim_batch had already learned this exact lesson
  # (`safely { t.join(...) }`) without it reaching this sibling boundary.
  it "completes teardown when the stderr pump thread dies of something its own rescue list never enumerated" do
    @manager = build_manager
    expect(@manager.start).to eq(:ready)
    stderr_thread = @manager.instance_variable_get(:@stderr_thread)
    # Kill the pump thread with an exception #log_stderr does not rescue,
    # exactly as a failing logger write would, then let teardown join it.
    stderr_thread.raise(Errno::EIO)
    sleep 0.05 until !stderr_thread.alive?

    expect { @manager.stop }.not_to raise_error

    expect(@manager.pid).to be_nil
    expect(@manager.status).to eq(:stopped)
  end

  # Server's BackgroundTasks#shutdown runs #stop on its own short-lived
  # thread and Thread#kills it if it doesn't return in time (found
  # necessary because #stop's `agent/shutdown` RPC has no bound of its
  # own beyond @request_mutex -- it can block for as long as some other,
  # unrelated in-flight request already holds that mutex, e.g. a real 30s
  # #fetch_all_models round trip). An independent review found that
  # killing #stop's thread while it was still blocked *acquiring*
  # @request_mutex (never having reached #terminate_process at all) left
  # the real spawned child process running -- #stop's teardown must run
  # even when #stop itself is interrupted this way, not only when it
  # returns normally. This drives that exact interleaving against a real
  # spawned process, not a duck-typed fake (which can't observe whether
  # #terminate_process, specifically, actually ran).
  it "still reaps the real child process if #stop's own thread is killed while blocked waiting for another in-flight request's mutex" do
    @manager = build_manager
    status = @manager.start
    expect(status).to eq(:ready)
    pid = @manager.pid

    # Models "some other request is already using @request_mutex" by
    # holding it directly from this thread, rather than needing a genuine
    # slow round trip to the fixture Agent.
    request_mutex = @manager.instance_variable_get(:@request_mutex)
    request_mutex.lock
    stop_thread = nil

    # If the "genuinely blocked" assertion below ever fails, everything
    # after it -- killing/joining stop_thread, unlocking request_mutex --
    # would otherwise be skipped, leaving a thread blocked forever on a
    # mutex nothing would ever unlock again for the rest of this RSpec
    # process: precisely the leaked-background-thread shape this whole
    # change set exists to eliminate (found by an independent review).
    begin
      stop_thread = Thread.new { @manager.stop(timeout: 30) }

      # Deterministic proof #stop is genuinely blocked trying to acquire
      # @request_mutex (not merely not yet scheduled to run at all)
      # before killing it -- a thread blocked on Mutex#lock reports
      # "sleep".
      expect(wait_until { stop_thread.status == "sleep" }).to be(true)
    ensure
      stop_thread&.kill
      stop_thread&.join(2)
      request_mutex.unlock if request_mutex.owned?
    end

    # #stop's own teardown (guaranteed via `ensure`, see its own docs)
    # can still be finishing on the killed thread's own unwind after
    # #kill/#join return -- BackgroundTasks#shutdown's docs are explicit
    # that it doesn't wait for this itself, so neither does this
    # assertion; it polls instead of asserting immediately.
    expect(wait_until(timeout: 5) { !process_alive?(pid) }).to be(true)
  end

  # Task 022 background-task lifecycle: Server hands #stop a manager
  # reference the moment it's constructed (RailsBootstrap.start's
  # on_manager_created:), which can be well before -- or, in principle,
  # concurrently with -- #start ever actually runs. #stop must be a real
  # cancellation primitive at that stage, not merely a no-op that leaves
  # #start free to spawn a process moments later with nothing left to stop
  # it.
  it "cancels a manager whose #stop was called before #start ever ran -- #start never spawns anything" do
    @manager = build_manager
    @manager.stop

    # #start's own early guard (`return @status unless @status ==
    # :not_started`) already short-circuits once #stop has set :stopped,
    # so #start returns :stopped here without even reaching its own
    # @cancelled check -- covered by that guard alone. The @cancelled flag
    # this test really exists to cover matters for the narrower race where
    # #start's spawn decision is *already in flight* (inside its own
    # @terminate_mutex critical section) at the moment #stop runs; that
    # interleaving can't be forced deterministically from a single-process
    # test, so this asserts the observable *outcome* both paths must
    # share: whatever #start returns, it never actually spawns a process.
    status = @manager.start

    expect(status).to eq(:stopped)
    expect(@manager.pid).to be_nil
    expect(@manager.alive?).to be(false)
  end

  it "leaves #status at :stopped (not :not_started) after #stop on a manager that was never started, and a later #start is a no-op" do
    @manager = build_manager

    @manager.stop
    expect(@manager.status).to eq(:stopped)

    # #start's own early guard (`return @status unless @status ==
    # :not_started`) means a manager already cancelled this way can never
    # be started later by a stray #start call -- :stopped is terminal.
    expect(@manager.start).to eq(:stopped)
    expect(@manager.pid).to be_nil
  end

  it "is safe to call #stop twice on a manager that was never started (idempotent)" do
    @manager = build_manager

    expect { @manager.stop }.not_to raise_error
    expect { @manager.stop }.not_to raise_error
    expect(@manager.status).to eq(:stopped)
  end

  it "always ends at :stopped after #stop, never :static_only, however the reader thread's concurrent EOF write interleaves (Task 008.6)" do
    @manager = build_manager
    @manager.start

    # agent/shutdown causes the fixture Agent process to exit, which the
    # reader thread observes as EOF and reports via #mark_unavailable
    # concurrently with #stop's own cleanup. Without funneling #stop's
    # final write through the same @status_mutex #mark_unavailable's
    # compare-and-set uses, there is a real (if narrow) TOCTOU window: the
    # reader thread can read @status == :ready, then #stop writes
    # :stopped, then the reader thread's now-stale-read-based write lands
    # and overwrites it with :static_only. Real thread scheduling makes
    # this specific interleaving unreliable to force from a single test
    # run, so this drives many stop attempts to raise the odds of
    # catching the window if the mutex funnel were ever removed, rather
    # than asserting off one run alone.
    10.times do
      manager = build_manager
      manager.start
      manager.stop
      expect(manager.status).to eq(:stopped)
    end
  end

  it "fetches a single model's columns and associations via #fetch_model" do
    @manager = build_manager
    @manager.start

    result = @manager.fetch_model(name: "User")

    expect(result[:associations]).to include(a_hash_including(name: "company", macro: "belongs_to"))
  end

  it "fetches every model's full columns/associations in one agent/models round trip (Task 008.5)" do
    @manager = build_manager
    @manager.start

    models = @manager.fetch_all_models

    user = models.find { |m| m[:name] == "User" }
    expect(user[:associations]).to include(a_hash_including(name: "company", macro: "belongs_to"))
    expect(models.map { |m| m[:name] }).to include("User", "Company")
  end

  it "serializes concurrent requests from multiple threads instead of losing responses to each other" do
    @manager = build_manager
    @manager.start

    # Simulates many files changing at once (e.g. a git checkout touching
    # many app/models/*.rb files), each refreshed on its own background
    # thread — exactly what Server#refresh_model does per changed file.
    # Without serializing the write-then-await round trip in
    # AgentProcessManager#request, one thread's response can be read and
    # discarded by another thread waiting on a different request id,
    # leaving the rightful recipient to time out.
    names = %w[User Company Order] * 8
    threads = names.map { |name| Thread.new(name) { |n| @manager.fetch_model(name: n) } }
    results = threads.map(&:value)

    # Every thread must get back the model it actually asked for — not
    # nil (a timed-out request) and not another thread's response.
    expect(results.map { |r| r && r[:name] }).to eq(names)
  end

  describe "#reload" do
    let(:disable_flag) { File.join(fixture_root, "config", ".disable_archived_route") }

    after { File.delete(disable_flag) if File.exist?(disable_flag) }

    it "removes a route from a fresh snapshot after routes.rb changes and #reload runs (Task 006)" do
      File.delete(disable_flag) if File.exist?(disable_flag)

      @manager = build_manager
      @manager.start

      before_routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(before_routes.map { |r| r[:name] }).to include("archived")

      # Simulate editing routes.rb to remove the route, then Core telling
      # the Agent to reload — mirrors docs/04-runtime-agent.md section 8's
      # file-change -> agent/reload flow.
      File.write(disable_flag, "1")
      reload_result = @manager.reload

      expect(reload_result[:changedSections]).to eq(["routes"])
      expect(reload_result[:generation]).to be > 0

      after_routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(after_routes.map { |r| r[:name] }).not_to include("archived")
    end
  end

  describe "protocol version negotiation (Task 022)" do
    # Mutating the constant only affects *this* (Core-side test) process
    # -- the fixture Agent is a genuinely separate `ruby` process that
    # loads its own fresh copy of RuntimeAgent::Agent, so it still
    # reports its own real (unmutated) PROTOCOL_VERSION back. That's
    # exactly what makes this a faithful "the Agent I'm talking to
    # reports a different protocol version than I expect" repro, not
    # just an isolated unit check.
    around do |example|
      original = Ovallsp::RuntimeAgent::Agent::PROTOCOL_VERSION
      Ovallsp::RuntimeAgent::Agent.send(:remove_const, :PROTOCOL_VERSION)
      Ovallsp::RuntimeAgent::Agent.const_set(:PROTOCOL_VERSION, 999)
      example.run
    ensure
      Ovallsp::RuntimeAgent::Agent.send(:remove_const, :PROTOCOL_VERSION)
      Ovallsp::RuntimeAgent::Agent.const_set(:PROTOCOL_VERSION, original)
    end

    it "refuses to use an Agent whose reported protocol version doesn't match, falling back to static-only" do
      @manager = build_manager

      status = @manager.start

      expect(status).to eq(:static_only)
      expect(logger).to have_received(:error).with(a_string_matching(/protocol version mismatch/))
    end
  end

  describe "on_unavailable callback (Task 022)" do
    it "is called exactly once, with the reason, when the Agent stops responding after being ready" do
      reasons = []
      @manager = described_class.new(
        command: RbConfig.ruby,
        args: ["-I", File.join(core_root, "lib"), boot_script, "start", environment_file],
        chdir: fixture_root, logger: logger, hello_timeout: 5, on_unavailable: ->(reason) { reasons << reason }
      )
      @manager.start
      Process.kill("KILL", @manager.pid)

      wait_until { @manager.status == :static_only }

      expect(reasons.size).to eq(1)
    end

    def wait_until(timeout: 3)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return true if yield

        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.02
      end
    end
  end
end
