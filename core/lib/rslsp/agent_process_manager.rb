# frozen_string_literal: true

require_relative "io/framed_reader"
require_relative "io/framed_writer"
require_relative "runtime_agent/agent"

module Rslsp
  # Core-side counterpart to Rslsp::RuntimeAgent::Agent: spawns the Runtime
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

    def initialize(command:, args: [], chdir:, logger:, hello_timeout: 10, core_version: Rslsp::VERSION, env: {})
      @command = command
      @args = args
      @chdir = chdir
      @logger = logger
      @hello_timeout = hello_timeout
      @core_version = core_version
      @env = env
      @status = :not_started
      @inbox = Queue.new
      @next_id = 0
      @pid = nil
      @hello_result = nil
      @request_mutex = Mutex.new
    end

    attr_reader :status, :hello_result, :pid

    def ready?
      @status == :ready
    end

    # Spawns the Agent and blocks for up to `hello_timeout` seconds waiting
    # for agent/hello to succeed. Returns the resulting status; never
    # raises even if the Agent never starts.
    def start
      return @status unless @status == :not_started

      spawn_process
      @status = :starting
      register_exit_hook

      response = request("agent/hello",
                          { protocolVersion: RuntimeAgent::Agent::PROTOCOL_VERSION, coreVersion: @core_version,
                            capabilities: {} }, timeout: @hello_timeout)

      if response && response[:result]
        @hello_result = response[:result]
        @status = :ready
      else
        @logger.warn("agent/hello did not complete in time; falling back to static-only mode")
        @status = :static_only
        terminate_process
      end

      @status
    rescue StandardError => e
      @logger.error("failed to start runtime agent: #{e.class}: #{e.message}")
      @status = :static_only
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
    def stop(timeout: 3)
      return if @status == :stopped || @pid.nil?

      request("agent/shutdown", {}, timeout: timeout) unless @status == :static_only
      terminate_process
      @status = :stopped
    end

    def alive?
      return false unless @pid

      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    private

    # Every read-style request (agent/status, agent/snapshot, agent/model,
    # agent/reload) shares the same failure contract: not ready -> nil
    # without side effects; a round trip that returns nothing (EOF,
    # timeout, a crashed reader thread, an unparsable frame) degrades
    # status to :static_only so a request that timed out today is never
    # mistaken for a live Agent tomorrow (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    # An in-band `:error` result (e.g. agent/model's NOT_FOUND) is still a
    # *successful* round trip and must NOT degrade anything -- only #request
    # returning nil does.
    def request_while_ready(method, params, timeout:, on_failure:)
      return nil unless ready?

      response = request(method, params, timeout: timeout)
      degrade_to_static_only(on_failure) if response.nil?
      response
    end

    def degrade_to_static_only(reason)
      return unless @status == :ready # already static_only/stopped/stopping: nothing to degrade

      @logger.warn("#{reason}; marking runtime agent static-only")
      @status = :static_only
      terminate_process
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

      @writer = Rslsp::IO::FramedWriter.new(@stdin_write)
      @reader_thread = Thread.new { read_loop }
      @stderr_thread = Thread.new { log_stderr }
    end

    def read_loop
      reader = Rslsp::IO::FramedReader.new(@stdout_read)
      loop { @inbox << reader.read_message }
    rescue Rslsp::IO::FramedReader::EOF, IOError, Errno::EBADF
      @inbox << :eof
    rescue StandardError => e
      # An invalid frame or unparsable JSON raises something other than
      # the three "normal" end-of-stream shapes above -- without this,
      # the thread would die silently, @inbox would never receive
      # anything again, and every pending/future request would have to
      # wait out its full timeout instead of failing fast, with @status
      # stuck at :ready the whole time (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      @logger.error("runtime agent reader thread crashed: #{e.class}: #{e.message}")
      @inbox << :eof
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

    def terminate_process
      return unless @pid

      begin
        Process.kill("TERM", @pid)
      rescue Errno::ESRCH
        nil
      end
      wait_for_exit(2) || force_kill

      [@stdin_write, @stdout_read, @stderr_read].each { |io| io&.close unless io&.closed? }
      @reader_thread&.kill
      @stderr_thread&.join(1)
      @pid = nil
    end

    def force_kill
      return unless @pid

      begin
        Process.kill("KILL", @pid)
      rescue Errno::ESRCH
        return true
      end
      wait_for_exit(2)
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
