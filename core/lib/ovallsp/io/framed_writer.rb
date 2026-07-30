# frozen_string_literal: true

require "json"

module Ovallsp
  module IO
    # Writes LSP messages framed with Content-Length headers to an output
    # stream. Content-Length must be a byte count, not a character count, so
    # multi-byte UTF-8 payloads are measured with `bytesize`.
    class FramedWriter
      def initialize(output)
        @output = output
        @mutex = Mutex.new
      end

      # A header and its body are two writes, and more than one thread
      # reaches this: diagnostics are published from the dispatch thread,
      # from the Runtime Agent's bootstrap, and (0.2.0) from the
      # workspace-wide pass. Interleaving them puts a `Content-Length`
      # in front of somebody else's message, which is not a recoverable
      # protocol error -- the client resynchronises by guessing.
      def write_message(message)
        body = JSON.generate(message).b
        header = "Content-Length: #{body.bytesize}\r\n\r\n".b
        # One write, not two. The mutex gives mutual exclusion between
        # threads; it gives nothing against `Thread#kill`, and a
        # background thread killed by the bounded join at shutdown was
        # landing between the header and the body -- leaving a
        # `Content-Length` with no message after it, which is the one
        # framing error a client cannot recover from. Reproduced at
        # roughly 9 runs in 12 before this.
        @mutex.synchronize do
          @output.write(header + body)
          @output.flush if @output.respond_to?(:flush)
        end
      end
    end
  end
end
