# frozen_string_literal: true

require "json"

module Ovallsp
  module IO
    # Reads LSP messages framed with Content-Length headers from an input
    # stream. Buffers internally so callers of `input.read` may return any
    # number of bytes per call (including fewer bytes than requested), which
    # is what real stdio pipes and sockets do under load.
    class FramedReader
      class EOF < StandardError; end

      CRLF = "\r\n"

      def initialize(input)
        @input = input
        @buffer = "".b
      end

      def read_message
        headers = read_headers
        length = Integer(headers.fetch("content-length") { raise ProtocolError, "missing Content-Length header" })
        body = read_bytes(length)
        JSON.parse(body, symbolize_names: true)
      end

      class ProtocolError < StandardError; end

      private

      def read_headers
        headers = {}
        loop do
          line = read_line
          break if line.empty?

          key, value = line.split(":", 2)
          headers[key.strip.downcase] = value.strip if key && value
        end
        headers
      end

      def read_line
        loop do
          if (idx = @buffer.index(CRLF))
            line = @buffer.byteslice(0, idx)
            @buffer = @buffer.byteslice((idx + CRLF.bytesize)..@buffer.bytesize) || "".b
            return line
          end

          fill_buffer
        end
      end

      def read_bytes(length)
        fill_buffer while @buffer.bytesize < length

        bytes = @buffer.byteslice(0, length)
        @buffer = @buffer.byteslice(length..@buffer.bytesize) || "".b
        bytes.force_encoding(Encoding::UTF_8)
      end

      def fill_buffer
        # `IO#read(n)` blocks until exactly `n` bytes arrive or EOF, which
        # would hang forever on a live stdio pipe that has only delivered a
        # short message so far. `readpartial` returns as soon as any data is
        # available, matching how a real LSP client streams bytes.
        chunk = @input.readpartial(4096)
        @buffer << chunk.b
      rescue EOFError
        raise EOF
      end
    end
  end
end
