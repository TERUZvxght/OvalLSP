# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server semantic query integration (Task 013)" do
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
    messages
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  it "completes a receiver's members after `receiver.`, sourced from the workspace index" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\n  def burn\n  end\nend\nWidget.new.b\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 6, character: 12 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    labels = sent_messages.first[:result].map { |item| item[:label] }
    expect(labels).to include("build", "burn")
  end

  it "completes stdlib members via RBS when the receiver has no source declaration" do
    input =
      did_open("file:///a.rb", "x = \"hi\"\nx.upc\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 5 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    labels = sent_messages.first[:result].map { |item| item[:label] }
    expect(labels).to include("upcase")
  end

  it "resolves textDocument/definition for a receiver-qualified call to its source declaration, ahead of the lexical fallback" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n\nWidget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to eq([{ uri: "file:///widget.rb", range: { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } } }])
  end

  it "offers signature help for an ordinary method call using its source declaration's parameters" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build(name, count)\n  end\nend\n\nWidget.new.build(\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 18 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    signature = sent_messages.first[:result][:signatures].first
    expect(signature[:label]).to eq("build(name, count)")
  end
end
