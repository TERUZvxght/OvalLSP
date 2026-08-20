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

      # Whether another message is already waiting, which is how the
      # server tells "the developer is still typing" from "they have
      # stopped" without a timer to tune (037's C9).
      #
      # **False when it cannot tell**, which is the safe direction: the
      # caller then analyses immediately, exactly as every release before
      # this one did. A `StringIO` -- what most of the suite drives the
      # server with -- cannot be asked, and neither can anything else that
      # is not a real IO.
      #
      # At end of stream a pipe reports itself readable, so `#eof?` is
      # asked first; otherwise the last message of a session would leave a
      # pending analysis that nothing ever drains.
      def input_ready?
        return true unless @buffer.empty?
        return false unless @input.respond_to?(:wait_readable)

        !@input.wait_readable(0).nil? && !@input.eof?
      rescue ::IOError, ::SystemCallError
        # `SystemCallError` covers every `Errno::*`: a closed or reset
        # pipe raises one of those rather than `IOError`, and letting it
        # out of here ends `Server#run` with a raw backtrace -- the exact
        # failure shape 0.2.6 fixed for frames and this method reopened.
        false
      end

      # Everything that is not a well-formed frame leaves here as a
      # `ProtocolError`, and a stream that simply ended leaves as `EOF`.
      # Until 0.2.6 the difference reached the caller as whatever Ruby
      # happened to raise -- `ArgumentError` from `Integer()`,
      # `NoMethodError` from a negative `byteslice`, `JSON::ParserError`,
      # or `ProtocolError` -- and `Server#run` rescues only `EOF`, so any
      # of them ended the process with a raw backtrace and the client's
      # next request unanswered.
      #
      # `\A\d+\z` rather than `Integer()`: that accepted `0x10` as 16 and
      # `1_0` as 10, neither of which the LSP framing grammar allows, and
      # it accepted `-5`, which reached `byteslice(0, -5)`.
      def read_message
        headers = read_headers
        raw_length = headers.fetch("content-length") { raise ProtocolError, "missing Content-Length header" }
        raise ProtocolError, "Content-Length is not a decimal byte count: #{raw_length.inspect}" unless
          raw_length.match?(/\A\d+\z/)

        body = read_bytes(Integer(raw_length, 10))
        parse_body(body)
      end

      def parse_body(body)
        JSON.parse(body, symbolize_names: true)
      rescue JSON::ParserError => e
        raise ProtocolError, "frame body is not JSON: #{e.message}"
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
