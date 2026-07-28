# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server workspace trust gating" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:calls) { Queue.new }

  # Stands in for Ovallsp::RailsBootstrap: records that it was asked to
  # start (and with what root), without actually spawning anything.
  let(:fake_bootstrap) do
    queue = calls
    Class.new do
      # `**` mirrors the real RailsBootstrap.start, which takes
      # install_snapshot: too. Server passes that unconditionally now, so
      # a double with a narrower signature would only be testing a
      # bootstrap that cannot exist in production.
      define_singleton_method(:start) do |root:, logger:, route_registry:, model_registry:, on_unavailable: nil,
                                            on_manager_created: nil, **|
        queue << { root: root, route_registry: route_registry, model_registry: model_registry }
      end
    end
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: fake_bootstrap
    )
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  it "starts the Runtime Agent bootstrap when the workspace is explicitly trusted" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize",
            params: { initializationOptions: { workspaceTrusted: true } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    call = calls.pop(timeout: 2)
    expect(call).not_to be_nil
    expect(call[:root]).to eq("/workspace")
  end

  it "does NOT start the Runtime Agent bootstrap when trust isn't communicated at all (fail-closed)" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(calls.pop(timeout: 0.3)).to be_nil
  end

  it "does NOT start the Runtime Agent bootstrap when the workspace is explicitly untrusted" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize",
            params: { initializationOptions: { workspaceTrusted: false } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(calls.pop(timeout: 0.3)).to be_nil
    expect(logger).to have_received(:warn).with(/workspace trust/)
  end

  def trusted_initialize_and_exit_input
    frame(jsonrpc: "2.0", id: 1, method: "initialize",
          params: { initializationOptions: { workspaceTrusted: true } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
  end

  # Task 022's background-task lifecycle requirements: a bootstrap that
  # never returns must never delay the initialize response, and must never
  # outlive Server#run. Deterministic (Queue-synchronized, never a real
  # `sleep`) so this can't rot into a timing-dependent flake -- previously
  # this test used `sleep 5` as its fake bootstrap's entire body, which
  # (a) made this test itself take 5+ real seconds, and (b) surfaced a real
  # bug: `sleep 5`'s own return value (an Integer, the number of seconds
  # slept) got assigned to @agent_manager, and the leaked, never-reclaimed
  # bootstrap thread would later call `5.ready?` -- crashing with a
  # NoMethodError, inside a `rescue` clause that then touched a
  # `logger` RSpec double already torn down by a *later* example
  # (`RSpec::Mocks::ExpiredTestDoubleError`). See BackgroundTasks and
  # Server#shutdown_background_tasks.
  it "still answers the initialize handshake immediately even though the bootstrap is blocked (regression A)" do
    bootstrap_started = Queue.new
    bootstrap_thread_holder = Queue.new
    release_bootstrap = Queue.new
    blocked_bootstrap = Class.new do
      define_singleton_method(:start) do |**|
        bootstrap_thread_holder << Thread.current
        bootstrap_started << true
        release_bootstrap.pop # never released in this test -- models a bootstrap that hangs forever
        nil
      end
    end

    server = Ovallsp::Server.new(
      input: StringIO.new(trusted_initialize_and_exit_input), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: blocked_bootstrap, background_task_shutdown_timeout: 0.2
    )

    run_thread = Thread.new { server.run }

    # Deterministic proof the bootstrap is genuinely mid-call (not merely
    # "hasn't been scheduled yet") before asserting anything about how
    # promptly initialize answered.
    expect(bootstrap_started.pop(timeout: 2)).to be(true)
    expect(sent_messages.first).to include(id: 1)

    # #run only returns once its background tasks are reclaimed
    # (BackgroundTasks#shutdown force-kills a thread with no owned
    # subprocess once its bounded graceful join expires) -- bounded by
    # background_task_shutdown_timeout above, not by this test's own
    # timeout.
    run_thread.join(3)
    expect(run_thread).not_to be_alive

    bootstrap_thread = bootstrap_thread_holder.pop(timeout: 1)
    expect(bootstrap_thread).not_to be_alive
  end

  # Requirement B: once a bootstrap has constructed its AgentProcessManager
  # (registered via on_manager_created) but is still blocked -- modeling an
  # in-flight agent/hello handshake -- shutdown must stop that Manager
  # (never just kill the thread and abandon whatever process it owns).
  # The fake models the real AgentProcessManager's own contract: calling
  # #stop on a manager whose #start is mid-handshake force-terminates its
  # child process, which is exactly what unblocks the still-in-flight
  # request on the real class (see AgentProcessManager#stop/#terminate_process).
  it "stops an already-constructed Manager instead of abandoning it when the bootstrap is blocked mid-handshake (regression B)" do
    manager_created = Queue.new
    stop_calls = Queue.new
    release_handshake = Queue.new

    fake_manager = Class.new do
      define_singleton_method(:ready?) { false }
    end
    fake_manager.define_singleton_method(:stop) do
      stop_calls << true
      release_handshake << true
    end

    bootstrap = Class.new do
      define_singleton_method(:start) do |on_manager_created:, **|
        on_manager_created.call(fake_manager)
        manager_created << true
        release_handshake.pop
        fake_manager
      end
    end

    server = Ovallsp::Server.new(
      input: StringIO.new(trusted_initialize_and_exit_input), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: bootstrap, background_task_shutdown_timeout: 2
    )

    run_thread = Thread.new { server.run }

    expect(manager_created.pop(timeout: 2)).to be(true)

    run_thread.join(3)
    expect(run_thread).not_to be_alive
    expect(stop_calls.pop(timeout: 1)).to be(true)
  end

  # Found by an independent review of this fix's first version: an earlier
  # draft had `on_manager_created:`'s callback assign @agent_manager
  # itself, the moment the manager was constructed -- which made
  # #status_result see a non-nil, not-yet-ready manager for a real Rails
  # app's *entire* boot (up to hello_timeout seconds) and report
  # "agent-unavailable". That state is documented elsewhere (server.rb's
  # own comment above #status_result) as "an Agent bootstrap was
  # attempted... but it's not currently responding" -- i.e. a *failure*
  # signal, not "still starting up normally". @agent_manager must only be
  # assigned its final value once the bootstrap actually returns, exactly
  # as before this fix; BackgroundTasks tracks (and can cancel) the
  # in-progress manager independently of what @agent_manager currently
  # holds.
  it "does not report agent-unavailable while a Runtime Agent bootstrap is still genuinely in progress" do
    manager_created = Queue.new
    release_handshake = Queue.new

    fake_manager = Class.new do
      define_singleton_method(:ready?) { false }
    end
    fake_manager.define_singleton_method(:stop) { release_handshake << true }

    bootstrap = Class.new do
      define_singleton_method(:start) do |on_manager_created:, **|
        on_manager_created.call(fake_manager)
        manager_created << true
        release_handshake.pop
        fake_manager
      end
    end

    # A real pipe, not a fixed StringIO, and deliberately no `exit` frame
    # written yet: with both frames present upfront (as every other test
    # in this file uses), #run's dispatch loop reaches `exit` -- and
    # therefore Server#shutdown_background_tasks -- essentially
    # immediately after `initialize`, racing ahead of the bootstrap thread
    # before it even calls on_manager_created. That race made an earlier
    # version of this test spuriously pass regardless of timing (shutdown
    # would cancel the bootstrap via BackgroundTasks#track_manager's own
    # already-shutting-down path before this assertion ever ran). Keeping
    # the write end open holds #run inside its own blocking read, with no
    # `exit` in flight, so the bootstrap is genuinely still in progress
    # (not already being cancelled) at the point this test checks status.
    read_end, write_end = ::IO.pipe
    write_end.write(frame(jsonrpc: "2.0", id: 1, method: "initialize",
                          params: { initializationOptions: { workspaceTrusted: true } }))
    write_end.flush

    server = Ovallsp::Server.new(
      input: read_end, output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: bootstrap, background_task_shutdown_timeout: 2
    )

    run_thread = Thread.new { server.run }

    expect(manager_created.pop(timeout: 2)).to be(true)
    # The manager has been constructed and registered with BackgroundTasks
    # by this point (on_manager_created already fired), but the bootstrap
    # itself is still blocked, and no shutdown has been requested --
    # @agent_manager must still be nil.
    expect(server.instance_variable_get(:@agent_manager)).to be_nil

    # #status_result checks @cold_indexing before @agent_manager, and
    # Cold Index (walking the nonexistent "/workspace") normally finishes
    # well before this point in the test, making a plain
    # `status_result != agent-unavailable` assertion here pass either way
    # -- via "indexing" -- without ever actually exercising the
    # @agent_manager branch this test exists to cover (found by an
    # independent review). Forcing it false isolates exactly the
    # regression this test targets: with @agent_manager still nil, status
    # must read "ready-static", not "agent-unavailable".
    server.instance_variable_set(:@cold_indexing, false)
    expect(server.send(:status_result, nil)).to eq(state: "ready-static")

    # Let the bootstrap, then #run itself, finish cleanly.
    release_handshake << true
    write_end.write(frame(jsonrpc: "2.0", method: "exit", params: nil))
    write_end.close

    run_thread.join(3)
    expect(run_thread).not_to be_alive
  ensure
    read_end&.close unless read_end&.closed?
    write_end&.close unless write_end&.closed?
  end

  # Requirement C: a bootstrap that violates the "nil or an object
  # responding to #stop" contract must never crash the background thread
  # that calls it -- Server falls back to static-only and logs a contract
  # violation instead. This is the exact `sleep 5` -> Integer shape that
  # broke the original (pre-fix) test, tested directly rather than as a
  # side effect of timing. A real RailsBootstrap always returns nil or a
  # genuine AgentProcessManager; this is a defensive boundary check, not
  # the primary fix (the thread-lifecycle fix above is what actually
  # prevents the leak).
  it "does not let the bootstrap thread raise unhandled when the bootstrap returns a value that violates the manager contract (regression C)" do
    contract_violating_bootstrap = Class.new do
      define_singleton_method(:start) { |**| 5 }
    end

    server = Ovallsp::Server.new(
      input: StringIO.new(trusted_initialize_and_exit_input), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: contract_violating_bootstrap
    )

    expect { server.run }.not_to raise_error
    expect(logger).to have_received(:error).with(/contract violation/)
  end

  # Requirement D: shutdown/exit/ensure all overlapping (here: #run's own
  # `ensure` firing once naturally, then #shutdown_background_tasks called
  # again directly, twice more) must never raise -- idempotent by
  # construction (BackgroundTasks#shutdown no-ops once @shutting_down is
  # already true).
  it "tolerates overlapping cleanup calls without raising (regression D)" do
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
    end
    fake_manager.define_singleton_method(:stop) {}
    bootstrap = Class.new do
      define_singleton_method(:start) { |**| fake_manager }
    end

    server = Ovallsp::Server.new(
      input: StringIO.new(trusted_initialize_and_exit_input), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: bootstrap
    )

    expect { server.run }.not_to raise_error
    expect { server.send(:shutdown_background_tasks) }.not_to raise_error
    expect { server.send(:shutdown_background_tasks) }.not_to raise_error
  end
end
