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
  class AgentProcessManager
    STATUSES = %i[not_started starting ready static_only stopped].freeze

    def initialize(command:, args: [], chdir:, logger:, hello_timeout: 10, core_version: Rslsp::VERSION)
      @command = command
      @args = args
      @chdir = chdir
      @logger = logger
      @hello_timeout = hello_timeout
      @core_version = core_version
      @status = :not_started
      @inbox = Queue.new
      @next_id = 0
      @pid = nil
      @hello_result = nil
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
      return nil unless ready?

      response = request("agent/status", {}, timeout: timeout)
      if response.nil?
        @logger.warn("agent/status timed out; marking runtime agent static-only")
        @status = :static_only
        terminate_process
        nil
      else
        response[:result]
      end
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

    def spawn_process
      stdin_read, @stdin_write = ::IO.pipe
      @stdout_read, stdout_write = ::IO.pipe
      @stderr_read, stderr_write = ::IO.pipe

      @pid = Process.spawn(
        @command, *@args,
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
    end

    def log_stderr
      @stderr_read.each_line { |line| @logger.info("[agent pid=#{@pid}] #{line.chomp}") }
    rescue IOError, Errno::EBADF
      nil
    end

    def request(method, params, timeout:)
      id = (@next_id += 1)
      @writer.write_message(jsonrpc: "2.0", id: id, method: method, params: params)

      deadline = monotonic_now + timeout
      loop do
        remaining = deadline - monotonic_now
        return nil if remaining <= 0

        message = @inbox.pop(timeout: remaining)
        return nil if message.nil? || message == :eof
        return message if message.is_a?(Hash) && message[:id] == id
        # A stray notification or mismatched id: MVP is single-flight, so
        # just ignore it and keep waiting for our own response.
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
