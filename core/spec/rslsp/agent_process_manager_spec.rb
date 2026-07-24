# frozen_string_literal: true

require "rbconfig"

RSpec.describe Rslsp::AgentProcessManager do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:fixture_root) { File.join(core_root, "spec/fixtures/rails_minimal") }
  let(:boot_script) { File.join(core_root, "lib/rslsp/runtime_agent/boot.rb") }
  let(:environment_file) { File.join(fixture_root, "config/environment.rb") }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

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
end
