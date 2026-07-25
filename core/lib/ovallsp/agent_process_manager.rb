# frozen_string_literal: true

require_relative "child_process"
require_relative "io/framed_reader"
require_relative "io/framed_writer"
require_relative "runtime_agent/agent"

module Ovallsp
  # Core-side counterpart to Ovallsp::RuntimeAgent::Agent: spawns the Runtime
  # Agent as a child process, performs the agent/hello handshake, and lets
  # callers send further single-flight requests (agent/status,
  # agent/shutdown). If the Agent never answers hello in time, or later
  # stops responding, this degrades to :static_only rather than taking the
  # Core Server down with it (docs/02-architecture.md 障害分離 table).
  #
  # docs/05-protocol.md section 7 explicitly allows "MVP Agentは
  # single-flight reloadと、read requestの並行処理なしでもよい" — #request
  # enforces exactly that with a mutex, because Server can call public
  # methods here (fetch_model, reload, request_status, ...) from several
  # background threads at once (one per changed file), and without
  # serializing the write-then-await-matching-response round trip, one
  # thread can steal and discard another's response, leaving it to time
  # out. There is one shared stdin/stdout pipe pair; only one request may
  # be in flight on it at a time.
  class AgentProcessManager
    STATUSES = %i[not_started starting ready static_only stopped].freeze

    def initialize(command:, args: [], chdir:, logger:, hello_timeout: 10, core_version: Ovallsp::VERSION, env: {},
                   on_unavailable: nil)
      @command = command
      @args = args
      @chdir = chdir
      @logger = logger
      @hello_timeout = hello_timeout
      @core_version = core_version
      @env = env
      # Task 022: called at most once, exactly when this manager
      # transitions ready -> static_only on its own (a crash, a stopped-
      # responding Agent) -- never for an explicit #stop, and never more
      # than once for a manager that's already static_only. Lets Server
      # layer an auto-restart-with-backoff policy (AgentSupervisor) on
      # top without AgentProcessManager itself knowing anything about
      # restart policy -- it only ever reports its own state transitions.
      @on_unavailable = on_unavailable
      @status = :not_started
      @inbox = Queue.new
      @next_id = 0
      @pid = nil
      @hello_result = nil
      @request_mutex = Mutex.new
      @status_mutex = Mutex.new
      @terminate_mutex = Mutex.new
      # Set by #stop when called before #start has (or may not yet have)
      # spawned a process -- see #start's own comment for why this needs
      # to be checked *inside* the same @terminate_mutex critical section
      # that #spawn_process itself runs in, rather than as a plain
      # unsynchronized flag read.
      @cancelled = false
    end

    attr_reader :status, :hello_result, :pid

    def ready?
      @status == :ready
    end

    # Spawns the Agent and blocks for up to `hello_timeout` seconds waiting
    # for agent/hello to succeed. Returns the resulting status; never
    # raises even if the Agent never starts.
    #
    # #spawn_process itself runs inside @terminate_mutex, the same lock
    # #stop's cancellation path uses (see #stop) -- so #start and a
    # concurrent #stop can never interleave in a way that spawns a process
    # #stop already decided nothing should ever spawn: either #stop wins
    # the race (sets @cancelled first; this method sees it under the same
    # lock and returns :static_only without ever spawning) or #start's own
    # spawn wins it (completes first; #stop then sees @pid already set
    # under the same lock and terminates the process it just spawned).
    # Found necessary by Server#run needing to cancel a Runtime Agent
    # bootstrap thread that may not have reached #start yet at all --
    # Server hands #stop a manager reference the moment it's constructed
    # (RailsBootstrap.start's on_manager_created:), well before this
    # method necessarily runs.
    def start
      return @status unless @status == :not_started

      spawned = @terminate_mutex.synchronize do
        if @cancelled
          false
        else
          spawn_process
          true
        end
      end

      unless spawned
        @logger.warn("runtime agent start cancelled before the process was spawned")
        return set_status(:static_only)
      end

      set_status(:starting)
      register_exit_hook

      response = request("agent/hello",
                          { protocolVersion: RuntimeAgent::Agent::PROTOCOL_VERSION, coreVersion: @core_version,
                            capabilities: {} }, timeout: @hello_timeout)

      if response && response[:result] && compatible_protocol_version?(response[:result][:protocolVersion])
        @hello_result = response[:result]
        set_status(:ready)
      elsif response && response[:result]
        # Task 022: "major不一致は接続拒否" -- Core and the Agent it just
        # spawned ship together (same gem, same install), so in practice
        # this should never actually fire; it exists as a fail-safe
        # against a stale boot script, a manually-launched Agent from a
        # different install, or any future skew between the two, rather
        # than trusting whatever protocolVersion came back unconditionally
        # (the pre-Task-022 behavior).
        @logger.error(
          "runtime agent protocol version mismatch (agent=#{response[:result][:protocolVersion].inspect}, " \
          "core expects #{RuntimeAgent::Agent::PROTOCOL_VERSION}); refusing to use it, falling back to static-only mode"
        )
        set_status(:static_only)
        terminate_process
      else
        @logger.warn("agent/hello did not complete in time; falling back to static-only mode")
        set_status(:static_only)
        terminate_process
      end

      @status
    rescue StandardError => e
      @logger.error("failed to start runtime agent: #{e.class}: #{e.message}")
      set_status(:static_only)
      terminate_process
      @status
    end

    # Returns the agent/status result, or nil if the Agent isn't ready or
    # stops responding (in which case status degrades to :static_only).
    def request_status(timeout: 5)
      response = request_while_ready("agent/status", {}, timeout: timeout, on_failure: "agent/status timed out")
      response && response[:result]
    end

    # Requests one or more agent/snapshot sections (e.g. ["routes"]).
    # Returns nil if the Agent isn't ready or doesn't respond in time (in
    # which case status degrades to :static_only).
    def fetch_snapshot(sections:, timeout: 5)
      response = request_while_ready(
        "agent/snapshot", { sections: sections }, timeout: timeout, on_failure: "agent/snapshot timed out"
      )
      response && response[:result]
    end

    # Requests a single model's columns/associations via agent/model.
    # Returns nil if the Agent isn't ready or doesn't respond in time (in
    # which case status degrades to :static_only); the result hash may
    # still contain an `:error` key (e.g. NOT_FOUND) that callers should
    # check -- that's a valid response, not a failed round trip.
    def fetch_model(name:, timeout: 5)
      response = request_while_ready(
        "agent/model", { name: name }, timeout: timeout, on_failure: "agent/model timed out"
      )
      response && response[:result]
    end

    # Bulk counterpart to N x #fetch_model: one agent/models round trip
    # returns every model's full columns/associations, avoiding the
    # request/response overhead of fetching hundreds of models one at a
    # time (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    # Returns nil if the Agent isn't ready or doesn't respond in time.
    def fetch_all_models(timeout: 30)
      response = request_while_ready("agent/models", {}, timeout: timeout, on_failure: "agent/models timed out")
      response && response[:result] && response[:result][:models]
    end

    # Asks the Agent to re-draw routes (and anything else a real reload
    # touches) and returns its { generation:, changedSections:, errors: }
    # result, or nil if unavailable (in which case status degrades to
    # :static_only).
    def reload(reason: "filesChanged", changed_paths: [], sections: ["routes"], timeout: 30)
      response = request_while_ready(
        "agent/reload", { reason: reason, changedPaths: changed_paths, sections: sections }, timeout: timeout,
        on_failure: "agent/reload timed out"
      )
      response && response[:result]
    end

    # Idempotent: asks the Agent to shut down cleanly, then force-kills it
    # if it doesn't exit promptly. Safe to call even if the Agent already
    # died on its own (crash) or was never started.
    #
    # `request("agent/shutdown", ...)` below can itself cause the Agent to
    # exit, which the reader thread observes as EOF and reports through
    # #mark_unavailable — concurrently with this method's own cleanup.
    # The final `@status = :stopped` write goes through the same
    # @status_mutex #mark_unavailable uses, and unconditionally wins
    # (rather than a compare-and-set), so an explicit #stop always ends
    # in :stopped even if a same-moment reader-thread-detected EOF
    # otherwise would have written :static_only first
    # (docs/design/tasks/008.6-agent-and-index-hardening.md) — a
    # deliberate stop is a stronger, terminal signal than a mere
    # unavailability degrade.
    # Deliberately does NOT bail out early just because @pid is still nil
    # (a never-spawned, or not-yet-spawned, manager) -- unlike the earlier
    # version of this method. #stop is Server's one cancellation primitive
    # for a manager at *any* lifecycle stage, including "constructed but
    # #start hasn't run yet" and "#start is currently blocked mid
    # agent/hello handshake", both of which have @pid nil or set but no
    # completed handshake. Only a fully :ready manager gets the polite
    # `agent/shutdown` RPC first -- for :not_started/:starting/
    # :static_only there's nothing coherent to ask (the Agent, if even
    # spawned yet, hasn't finished its own handshake), and attempting the
    # request would only block waiting for @request_mutex, which #start's
    # own in-flight hello request already holds until *its* timeout
    # elapses -- not a deadlock (the wait is bounded, by hello_timeout),
    # but exactly what let a mid-bootstrap #stop call block for the full
    # hello_timeout instead of cancelling promptly.
    #
    # The teardown itself runs inside `ensure`, not inline after the
    # `agent/shutdown` request -- found necessary by an independent
    # review: Server's BackgroundTasks#shutdown runs #stop on its own
    # short-lived thread so one stuck manager can't block the rest of
    # shutdown forever (see BackgroundTasks#shutdown), and bounds that
    # thread with a plain `Thread#kill` if #stop itself doesn't return in
    # time. A #stop that ran `request(...)` *then* `terminate_process` as
    # two separate top-level statements could be killed *between* them --
    # after the polite RPC attempt, but before the process was ever
    # actually torn down -- leaving the child Agent process running with
    # nothing left anywhere that will ever call #stop on it again. MRI
    # runs pending `ensure` blocks while unwinding a killed thread (the
    # same guarantee Mutex#synchronize's own internal unlock-on-exit
    # already relies on elsewhere in this class), so putting teardown in
    # `ensure` here means it happens even if this method's calling thread
    # is killed while still blocked inside the `agent/shutdown` request.
    def stop(timeout: 3)
      return if @status == :stopped

      begin
        request("agent/shutdown", {}, timeout: timeout) if @status == :ready
      ensure
        # Same lock #start's own spawn decision runs under (see #start's
        # comment) -- guarantees this either (a) sets @cancelled before
        # #start ever spawns, so #start never spawns at all, (b) runs
        # after #start's spawn already completed, sees @pid set, and
        # terminates the process #start just spawned, or (c) tears down a
        # process that was already fully spawned and :ready. No
        # interleaving, and no interruption of this method itself, can
        # leave a spawned process that this never tears down.
        @terminate_mutex.synchronize do
          @cancelled = true
          terminate_process_locked if @pid
        end
        @status_mutex.synchronize { @status = :stopped }
      end
    end

    def alive?
      return false unless @pid

      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    private

    # Every #start-side status transition goes through here rather than a
    # plain `@status = ...` -- guards against a concurrent #stop's own
    # `:stopped` write (see #stop's comment: an explicit stop is meant to
    # "unconditionally win" as a terminal signal) being silently
    # overwritten by a #start that was already mid-flight when #stop ran.
    # No process is ever left running either way (#stop already tore it
    # down before writing :stopped), but without this guard @status itself
    # could misreport what actually happened. Found by an independent
    # review.
    def set_status(new_status)
      @status_mutex.synchronize do
        break @status if @status == :stopped

        @status = new_status
      end
    end

    # Every read-style request (agent/status, agent/snapshot, agent/model,
    # agent/reload) shares the same failure contract: not ready -> nil
    # without side effects; a round trip that returns nothing (timeout —
    # EOF and a crashed reader thread are now caught directly at the
    # source, see #mark_unavailable) degrades status to :static_only so a
    # request that timed out today is never mistaken for a live Agent
    # tomorrow (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    # An in-band `:error` result (e.g. agent/model's NOT_FOUND) is still a
    # *successful* round trip and must NOT degrade anything -- only #request
    # returning nil does.
    def request_while_ready(method, params, timeout:, on_failure:)
      return nil unless ready?

      response = request(method, params, timeout: timeout)
      mark_unavailable(on_failure, from_reader_thread: false) if response.nil?
      response
    end

    # The single place every :ready -> :static_only transition goes
    # through, whichever *event* triggers it. Before Task 008.6 this only
    # ran lazily, from inside a request that happened to fail -- if the
    # reader thread died (EOF, a crashed parse) while no request was in
    # flight, @status stayed :ready indefinitely, and anything that reads
    # #ready?/#status directly without making a request (e.g.
    # Server#with_ready_agent) would keep believing the Agent was healthy
    # (docs/design/tasks/008.6-agent-and-index-hardening.md). #read_loop
    # now calls this directly, at the moment it detects EOF or a crash --
    # the actual event -- instead of waiting for some future request to
    # discover it.
    #
    # The status flag itself is updated under @status_mutex (a tiny,
    # fast compare-and-set) so two triggers racing each other (a reader
    # thread crash and an in-flight request timing out at nearly the same
    # moment) only ever run cleanup once. #terminate_process is run
    # *outside* that lock, and on a separate thread when `from_reader_thread`
    # is set -- #terminate_process calls `@reader_thread.kill`, which
    # would otherwise be the reader thread trying to kill itself
    # mid-rescue-clause, silently abandoning everything after that call
    # (pipe cleanup, @stderr_thread.join, @pid = nil) instead of running
    # it. `from_reader_thread` is passed explicitly by the one caller that
    # knows statically it *is* the reader thread (#read_loop), rather than
    # compared via `Thread.current == @reader_thread` — @reader_thread is
    # itself assigned from the *return value* of `Thread.new { read_loop }`
    # in #spawn_process, so the thread body can start running before that
    # assignment completes, and an identity check could otherwise briefly
    # see @reader_thread as nil and misidentify itself as a different
    # thread.
    def mark_unavailable(reason, from_reader_thread:)
      became_unavailable = @status_mutex.synchronize do
        next false unless @status == :ready

        @status = :static_only
        true
      end
      return unless became_unavailable

      @logger.warn("#{reason}; marking runtime agent static-only")
      from_reader_thread ? Thread.new { terminate_process } : terminate_process
      @on_unavailable&.call(reason)
    end

    def compatible_protocol_version?(agent_protocol_version)
      agent_protocol_version == RuntimeAgent::Agent::PROTOCOL_VERSION
    end

    def spawn_process
      stdin_read, @stdin_write = ::IO.pipe
      @stdout_read, stdout_write = ::IO.pipe
      @stderr_read, stderr_write = ::IO.pipe

      @pid = Process.spawn(
        @env, @command, *@args,
        chdir: @chdir,
        in: stdin_read, out: stdout_write, err: stderr_write
      )
      stdin_read.close
      stdout_write.close
      stderr_write.close

      @writer = Ovallsp::IO::FramedWriter.new(@stdin_write)
      @reader_thread = Thread.new { read_loop }
      @stderr_thread = Thread.new { log_stderr }
    end

    def read_loop
      reader = Ovallsp::IO::FramedReader.new(@stdout_read)
      loop { @inbox << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF, IOError, Errno::EBADF
      @inbox << :eof
      # The Agent's stdout closed: it exited (crash or normal termination
      # outside of our own #stop) or the pipe was torn down. This is a
      # definite, permanent event, not merely "a request happened to fail"
      # -- transition immediately rather than waiting for whatever request
      # (if any) is pending or next attempted to discover it.
      mark_unavailable("runtime agent stdout closed (EOF)", from_reader_thread: true)
    rescue StandardError => e
      # An invalid frame or unparsable JSON raises something other than
      # the three "normal" end-of-stream shapes above -- without this,
      # the thread would die silently, @inbox would never receive
      # anything again, and every pending/future request would have to
      # wait out its full timeout instead of failing fast, with @status
      # stuck at :ready the whole time (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      @logger.error("runtime agent reader thread crashed: #{e.class}: #{e.message}")
      @inbox << :eof
      mark_unavailable("runtime agent reader thread crashed: #{e.class}", from_reader_thread: true)
    end

    def log_stderr
      @stderr_read.each_line { |line| @logger.info("[agent pid=#{@pid}] #{line.chomp}") }
    rescue IOError, Errno::EBADF
      nil
    end

    # Serialized: only one request may be written and awaited at a time
    # (see the class comment). A concurrent caller simply waits its turn
    # rather than risking stealing another caller's response off `@inbox`.
    def request(method, params, timeout:)
      @request_mutex.synchronize { request_locked(method, params, timeout) }
    end

    def request_locked(method, params, timeout)
      id = (@next_id += 1)
      @writer.write_message(jsonrpc: "2.0", id: id, method: method, params: params)

      deadline = monotonic_now + timeout
      loop do
        remaining = deadline - monotonic_now
        return nil if remaining <= 0

        message = @inbox.pop(timeout: remaining)
        return nil if message.nil? || message == :eof
        return message if message.is_a?(Hash) && message[:id] == id
        # A stray notification or mismatched id: with the mutex held, this
        # should be unreachable in practice, but staying defensive costs
        # nothing — just keep waiting for our own response.
      end
    rescue StandardError => e
      @logger.error("agent request #{method} failed: #{e.class}: #{e.message}")
      nil
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # #mark_unavailable can now trigger this from a background thread
    # (when the reader thread itself detected EOF/a crash) *concurrently*
    # with an explicit #stop from the caller's own thread — without
    # serializing here, both invocations would race on @pid/@reader_thread/
    # the pipes (e.g. one sees `@pid` go nil out from under it between its
    # own `return unless @pid` check and its `Process.wait(@pid, ...)`
    # call). @terminate_mutex makes a second, concurrent call block until
    # the first finishes and then see the now-nil @pid via the guard
    # clause below and no-op, rather than racing it.
    def terminate_process
      @terminate_mutex.synchronize { terminate_process_locked }
    end

    def terminate_process_locked
      return unless @pid

      # Signalled through ChildProcess, so a signal failure can never
      # propagate out of here (found by an independent review, round 12 --
      # the third site in this codebase to hand-roll this, see
      # ChildProcess' own docs). Rescuing only Errno::ESRCH meant an
      # EPERM (or anything else kill(2) reports) escaped *before* the
      # teardown below: the Agent's three pipes stayed open, the reader
      # thread stayed alive, `@pid` stayed set, and the exception replaced
      # whatever was already propagating through #stop's `ensure` -- or
      # escaped `at_exit { stop }` entirely.
      ChildProcess.signal(@pid, "TERM")
      wait_for_exit(2) || force_kill

      [@stdin_write, @stdout_read, @stderr_read].each { |io| io&.close unless io&.closed? }
      @reader_thread&.kill
      @stderr_thread&.join(1)
      @pid = nil
    end

    # Same total signal as above, plus a give-up that *detaches* rather
    # than abandoning the pid: this method's caller goes on to nil out
    # `@pid`, so on giving up nothing in this process would have been left
    # tracking the child at all and it would have stayed a zombie for the
    # rest of the LSP session. ChildProcess.reap is already the bounded
    # WNOHANG poll #wait_for_exit does, with that fallback attached.
    def force_kill
      return unless @pid

      ChildProcess.signal(@pid)
      ChildProcess.reap(@pid, timeout: 2, logger: @logger)
    end

    def wait_for_exit(timeout)
      deadline = monotonic_now + timeout
      loop do
        return true if Process.wait(@pid, Process::WNOHANG)
        return false if monotonic_now >= deadline

        sleep 0.02
      end
    rescue Errno::ECHILD
      true
    end

    def register_exit_hook
      at_exit { stop }
    end
  end
end
