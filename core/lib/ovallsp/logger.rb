# frozen_string_literal: true

require_relative "redactor"

module Ovallsp
  # Writes diagnostic messages to an injectable IO. Must never be pointed at
  # stdout: stdout carries only LSP protocol frames.
  class Logger
    def initialize(io: $stderr)
      @io = io
    end

    def info(message)
      write("INFO", message)
    end

    def warn(message)
      write("WARN", message)
    end

    def error(message)
      write("ERROR", message)
    end

    private

    # Task 022: every message goes through Redactor before it ever
    # reaches the log file/output channel -- see Redactor's own docs for
    # why this applies even to messages this codebase didn't author
    # itself (rendered exception text from a workspace's own Rails app).
    def write(level, message)
      @io.puts("[ovallsp] #{level}: #{Redactor.redact(message)}")
      @io.flush if @io.respond_to?(:flush)
    rescue StandardError
      nil
    end
  end
end
