# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server textDocument/references (Task 014)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Rslsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Rslsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  it "finds every call to a method, resolved through its receiver's type" do
    source = "class Widget\n  def build\n  end\nend\n\nw1 = Widget.new\nw1.build\nw2 = Widget.new\nw2.build\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    lines = result.map { |loc| loc[:range][:start][:line] }
    expect(lines).to contain_exactly(6, 8)
  end

  it "finds a local variable's references, and does not confuse it with a same-named local in a different method" do
    source = "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    lines = result.map { |loc| loc[:range][:start][:line] }
    expect(lines).to contain_exactly(1, 2) # only scope `a`'s `x`, never scope `b`'s
  end

  it "finds references across multiple files" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result.map { |loc| loc[:uri] }).to contain_exactly("file:///user.rb")
  end

  it "removes a file's references once it's closed and reverted, or deleted" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(jsonrpc: "2.0", method: "textDocument/didClose", params: { textDocument: { uri: "file:///user.rb" } }) +
      frame(
        jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
        params: { changes: [{ uri: "file:///user.rb", type: 3 }] } # 3 = Deleted
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "returns [] for a position with no reference candidate under the cursor" do
    input =
      did_open("file:///a.rb", "  \n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/references",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end
end
