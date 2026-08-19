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
