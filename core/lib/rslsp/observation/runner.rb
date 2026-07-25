# frozen_string_literal: true

require "tempfile"
require "timeout"
require_relative "observed_signature"

module Rslsp
  module Observation
    # Spawns the workspace's own configured test command as a genuinely
    # separate OS process, with Harness injected via `RUBYOPT` -- never
    # runs test/observation code inside Core's own process ("production
    # process injection" is explicitly out of scope;
    # docs/design/tasks/019-runtime-observation.md). A runner crash,
    # hang, or empty/corrupt result never raises out of #run; it's
    # exactly one more "this run produced no evidence" outcome, logged,
    # the same fail-closed posture every other subprocess boundary in
    # this codebase (Plugins::Loader, AgentProcessManager) already uses.
    class Runner
      DEFAULT_TIMEOUT_SECONDS = 300
      HARNESS_PATH = File.expand_path("harness.rb", __dir__)

      def initialize(logger:)
        @logger = logger
      end

      # `command`/`args` are the workspace's own configured test command
      # (e.g. `["bundle", "exec", "rspec"]`), run with `workspace_root`
      # as both cwd and the Collector's own workspace-path filter root.
      # Returns an Array of ObservedSignature (possibly empty) -- never
      # raises.
      def run(command:, args:, workspace_root:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        run_id = "#{Time.now.to_f}-#{Process.pid}-#{rand(1_000_000)}"
        output_file = Tempfile.new(["rslsp-observation", ".marshal"])
        log_file = Tempfile.new(["rslsp-observation", ".log"])
        output_file.close
        log_file.close

        env = harness_env(workspace_root: workspace_root, output_path: output_file.path, run_id: run_id)
        results = spawn_and_collect(command, args, workspace_root, env, output_file.path, log_file.path, timeout_seconds)
        results || []
      ensure
        output_file&.unlink
        log_file&.unlink
      end

      private

      def harness_env(workspace_root:, output_path:, run_id:)
        {
          "RSLSP_OBSERVATION_WORKSPACE_ROOT" => File.realpath(workspace_root),
          "RSLSP_OBSERVATION_OUTPUT_PATH" => output_path,
          "RSLSP_OBSERVATION_RUN_ID" => run_id,
          "RUBYOPT" => [ENV["RUBYOPT"], "-r#{HARNESS_PATH}"].compact.join(" ")
        }
      end

      # Never lets the spawned process inherit this process' real
      # stdout/stderr -- in `--stdio` mode fd 1 is the live LSP JSON-RPC
      # transport, the same class of leak already found and fixed for
      # Plugins::Loader (Task 014-018's independent review) -- both
      # streams are captured to `log_path` instead, purely for the
      # caller's own diagnostics (e.g. surfacing the test command's
      # output back to the editor), never forwarded to this process' own
      # fd 1/2.
      def spawn_and_collect(command, args, workspace_root, env, output_path, log_path, timeout_seconds)
        pid = Process.spawn(env, command, *Array(args), chdir: workspace_root, out: log_path, err: log_path)
        finished = wait_with_timeout(pid, timeout_seconds)
        return nil unless finished

        read_results(output_path)
      rescue StandardError => e
        @logger.error("observation runner failed: #{e.class}: #{e.message}")
        nil
      end

      def wait_with_timeout(pid, timeout_seconds)
        Timeout.timeout(timeout_seconds) { Process.waitpid(pid) }
        true
      rescue Timeout::Error
        @logger.error("observation runner exceeded #{timeout_seconds}s -- killing it")
        kill(pid)
        false
      rescue Errno::ECHILD
        true
      end

      def kill(pid)
        Process.kill("KILL", pid)
        Process.waitpid(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def read_results(output_path)
        raw = File.binread(output_path)
        return [] if raw.empty?

        results = Marshal.load(raw)
        return [] unless results.is_a?(Array) && results.all? { |r| r.is_a?(ObservedSignature) }

        results
      rescue StandardError => e
        @logger.error("observation runner produced unreadable results: #{e.class}: #{e.message}")
        []
      end
    end
  end
end
