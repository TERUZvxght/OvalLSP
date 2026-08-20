# frozen_string_literal: true

require "json"

# 037's C9. Every `didChange` was analysed to completion on the dispatch
# thread, and every analysis holds `@index_mutation_mutex` -- the lock a
# hover needs. Measured on this tree before the change
# (`scripts/measure_typing_publishes.rb`, 3,907-line file, ten keystrokes
# 0.15 s apart): ten publishes, and a hover asked during the burst
# answered in **1.419 / 1.431 / 1.476 s** min / median / max. Nine of
# those ten analyses were about text the developer had already replaced.
#
# The answers were never *wrong* -- 0.2.8's "22 wrong intermediate
# publishes" did not reproduce, and `040` records the re-measurement. What
# they were is queued in front of the developer's next question.
RSpec.describe "Ovallsp::Server analysis follows the settled state (037 C9)" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:uri) { "file:///a.rb" }

  def frame(message)
    body = JSON.generate(message)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  # A real pipe, not a StringIO: the whole question is what the server
  # does when more input is *already waiting*, and only a stream that can
  # be asked about readiness can answer it. A StringIO cannot, which is
  # why the deferral falls back to analysing immediately there -- and why
  # an example written against one would pass without exercising this at
  # all.
  def drive(messages)
    in_read, in_write = ::IO.pipe
    out_read, out_write = ::IO.pipe

    messages.each { |m| in_write.write(frame(m)) }
    in_write.close

    server = Ovallsp::Server.new(input: in_read, output: out_write, logger: logger)
    server.run
    out_write.close

    published(out_read)
  ensure
    [in_read, out_read].each { |io| io.close unless io.closed? }
  end

  def published(io)
    reader = Ovallsp::IO::FramedReader.new(io)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" }
            .map { |m| m[:params][:version] }
  end

  it "analyses the state a burst of edits settled into, not every edit in it" do
    versions = drive(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } },
        { jsonrpc: "2.0", method: "initialized", params: {} },
        { jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, languageId: "ruby", version: 1, text: "class A\nend\n" } } },
        *(2..8).map do |v|
          { jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: v },
                      contentChanges: [{ text: "class A\n  def m#{v}; end\nend\n" }] } }
        end,
        { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
        { jsonrpc: "2.0", method: "exit", params: {} }
      ]
    )

    # The last edit's state is published. The six before it are not: they
    # were superseded before the dispatch thread ever got to them.
    expect(versions.compact).to eq([8])
  end

  # A malformed frame arriving behind the edit, with the client still
  # connected -- which is the situation, because a client that has gone
  # away also ends the loop and the post-loop drain covers that.
  # `Server#run` rescued the `ProtocolError` and went straight back to a
  # blocking read, so the analysis the edit asked for was never drained;
  # and because the bad bytes were already in the pipe, `input_ready?` was
  # true when the edit was dispatched, so nothing drained there either.
  # The panel then described text the developer had already replaced,
  # until they typed again.
  #
  # Run on a thread with the pipe held open, because "the server is still
  # waiting for more input" is the whole condition.
  it "still analyses the settled state when a malformed frame follows the edit" do
    in_read, in_write = ::IO.pipe
    out_read, out_write = ::IO.pipe
    server = Ovallsp::Server.new(input: in_read, output: out_write, logger: logger)
    thread = Thread.new { server.run }

    [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } },
      { jsonrpc: "2.0", method: "initialized", params: {} },
      { jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: uri, languageId: "ruby", version: 1, text: "class A\nend\n" } } },
      { jsonrpc: "2.0", method: "textDocument/didChange",
        params: { textDocument: { uri: uri, version: 2 },
                  contentChanges: [{ text: "class A\n  def settled; end\nend\n" }] } }
    ].each { |m| in_write.write(frame(m)) }
    in_write.write("Content-Length: -5\r\n\r\n")
    in_write.flush

    versions = []
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    reader = Ovallsp::IO::FramedReader.new(out_read)
    # `wait_readable` before every read: without the drain there is simply
    # nothing more to read, and a blocking `read_message` would hang the
    # example rather than fail it. A test that hangs is not a test.
    until versions.include?(2) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      break unless out_read.wait_readable(1)

      message = reader.read_message
      versions << message[:params][:version] if message[:method] == "textDocument/publishDiagnostics"
    end

    expect(versions).to include(2)
  ensure
    in_write&.close
    thread&.join(5)
    [in_read, out_read, out_write].each { |io| io&.close unless io.nil? || io.closed? }
  end

  # The control, and the property that matters more than the coalescing:
  # an edit that settles is always analysed. A burst that stops must not
  # leave the panel describing the state before it.
  it "still analyses an edit that nothing supersedes" do
    versions = drive(
      [
        { jsonrpc: "2.0", id: 1, method: "initialize", params: { capabilities: {} } },
        { jsonrpc: "2.0", method: "initialized", params: {} },
        { jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, languageId: "ruby", version: 1, text: "class A\nend\n" } } },
        { jsonrpc: "2.0", method: "textDocument/didChange",
          params: { textDocument: { uri: uri, version: 2 },
                    contentChanges: [{ text: "class A\n  def only; end\nend\n" }] } },
        { jsonrpc: "2.0", id: 2, method: "shutdown", params: {} },
        { jsonrpc: "2.0", method: "exit", params: {} }
      ]
    )

    expect(versions.compact).to eq([2])
  end
end
