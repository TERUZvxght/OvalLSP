# frozen_string_literal: true

require_relative "../io/framed_reader"
require_relative "../io/framed_writer"

module Rslsp
  module RuntimeAgent
    # The Runtime Agent side of the RSLSP Agent Protocol v1
    # (docs/design/docs/05-protocol.md). Runs inside the target Rails app's
    # process (via `bin/rails runner`, or a plain `ruby` invocation against a
    # fixture environment for tests) and answers agent/hello, agent/status,
    # and agent/shutdown over the same Content-Length JSON-RPC framing the
    # Core Server's LSP transport uses. Task 005 scope only — no routes,
    # Active Record extraction, reload, or plugins yet.
    class Agent
      PROTOCOL_VERSION = 1

      METHOD_NOT_FOUND = -32601
      INTERNAL_ERROR = -32603

      def initialize(input:, output:, logger:, root: Dir.pwd)
        @reader = Rslsp::IO::FramedReader.new(input)
        @writer = Rslsp::IO::FramedWriter.new(output)
        @logger = logger
        @root = root
        @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Returns the process exit code (always 0 — a clean agent/shutdown and
      # an EOF-on-stdin both count as a normal exit per docs/04-runtime-agent.md
      # section 11: "stdin EOFで即時shutdownする").
      def run
        loop do
          message = begin
            @reader.read_message
          rescue Rslsp::IO::FramedReader::EOF
            break
          end

          break if dispatch(message) == :exit
        end

        0
      end

      private

      def dispatch(message)
        method = message[:method]
        id = message[:id]

        case method
        when "agent/hello"
          respond(id, hello_result(message[:params]))
        when "agent/status"
          respond(id, status_result)
        when "agent/shutdown"
          respond(id, {})
          return :exit
        else
          respond_error(id, code: METHOD_NOT_FOUND, message: "Method not found: #{method}") if id
        end

        nil
      rescue StandardError => e
        @logger.call("error handling #{method.inspect}: #{e.class}: #{e.message}")
        respond_error(id, code: INTERNAL_ERROR, message: "internal error") if id
        nil
      end

      def hello_result(_params)
        {
          protocolVersion: PROTOCOL_VERSION,
          agentVersion: Rslsp::VERSION,
          root: rails_root,
          railsVersion: rails_defined? ? Rails.version.to_s : nil,
          rubyVersion: RUBY_VERSION,
          capabilities: { routes: false, activeRecord: false, reload: false, runtimePlugins: false }
        }
      end

      def status_result
        {
          pid: Process.pid,
          uptimeSeconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
        }
      end

      def rails_defined?
        defined?(Rails) && Rails.respond_to?(:version)
      end

      def rails_root
        return Rails.root.to_s if rails_defined? && Rails.respond_to?(:root) && Rails.root

        @root
      end

      def respond(id, result)
        @writer.write_message(jsonrpc: "2.0", id: id, result: result)
      end

      def respond_error(id, code:, message:)
        @writer.write_message(jsonrpc: "2.0", id: id, error: { code: code, message: message })
      end
    end
  end
end
