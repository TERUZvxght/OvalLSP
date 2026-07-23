# frozen_string_literal: true

require "json"

module Rslsp
  module IO
    # Writes LSP messages framed with Content-Length headers to an output
    # stream. Content-Length must be a byte count, not a character count, so
    # multi-byte UTF-8 payloads are measured with `bytesize`.
    class FramedWriter
      def initialize(output)
        @output = output
      end

      def write_message(message)
        body = JSON.generate(message).b
        @output.write("Content-Length: #{body.bytesize}\r\n\r\n".b)
        @output.write(body)
        @output.flush if @output.respond_to?(:flush)
      end
    end
  end
end
