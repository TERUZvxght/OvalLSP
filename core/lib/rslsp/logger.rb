# frozen_string_literal: true

module Rslsp
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

    def write(level, message)
      @io.puts("[rslsp] #{level}: #{message}")
      @io.flush if @io.respond_to?(:flush)
    rescue StandardError
      nil
    end
  end
end
