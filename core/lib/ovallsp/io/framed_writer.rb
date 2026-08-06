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

      # More than one thread reaches this. Diagnostics go out on the
      # dispatch thread for didOpen, on a debounce waiter for didChange
      # (0.2.2), and *every*
      # `Server#republish_open_diagnostics` call site runs on a background
      # one: the Runtime Agent becoming ready, a restart, a routes or
      # models refresh, a deferred ancestry answer landing. 0.2.0 adds
      # another -- `WorkspaceDiagnostics` publishes for files nobody has
      # open, on its own thread.
      #
      # The mutex is what makes a frame safe: no two writers are ever
      # inside the sink at once, so a `Content-Length` can never land in
      # front of another message's body -- the one framing error a client
      # cannot recover from, since it resynchronises by guessing.
      #
      # Building the frame first and writing it once narrows a second
      # window the mutex cannot close: `Thread#kill` between two writes,
      # and the bounded join at shutdown kills exactly these threads. It
      # narrows rather than closes it -- a write larger than `PIPE_BUF`
      # is a retry loop underneath, so one call is not an atomicity
      # guarantee on a real pipe.
      def write_message(message)
        body = JSON.generate(message).b
        frame = "Content-Length: #{body.bytesize}\r\n\r\n".b + body
        @mutex.synchronize do
          @output.write(frame)
          @output.flush if @output.respond_to?(:flush)
        end
      end
    end
  end
end
