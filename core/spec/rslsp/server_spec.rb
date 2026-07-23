# frozen_string_literal: true

require "stringio"

RSpec.describe Rslsp::Server do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    described_class.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Rslsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages
  end

  it "completes the initialize handshake and reports hover/shutdown/exit results" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(
        jsonrpc: "2.0", id: 2, method: "textDocument/hover",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 0 } }
      ) +
      frame(jsonrpc: "2.0", id: 3, method: "shutdown", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    exit_code = build_server(input).run

    expect(exit_code).to eq(0)

    messages = sent_messages
    expect(messages[0]).to include(id: 1)
    expect(messages[0][:result][:capabilities][:hoverProvider]).to eq(true)
    expect(messages[1]).to include(id: 2)
    expect(messages[1][:result][:contents][:value]).to eq("RSLSP connected")
    expect(messages[2]).to include(id: 3, result: nil)
  end

  it "tracks document versions through didOpen/didChange" do
    document_store = nil
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "a = 1\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///a.rb", version: 2 },
          contentChanges: [{ text: "a = 2\n" }]
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = build_server(input)
    server.instance_variable_get(:@document_store).tap { |store| document_store = store }
    server.run

    doc = document_store.fetch(uri: "file:///a.rb")
    expect(doc.text).to eq("a = 2\n")
    expect(doc.version).to eq(2)
  end

  it "answers textDocument/documentSymbol with a hierarchical result after didOpen" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///user.rb",
            text: "class User\n  def name\n  end\nend\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///user.rb" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result.size).to eq(1)
    expect(result.first[:name]).to eq("User")
    expect(result.first[:children].first[:name]).to eq("name")
  end

  it "returns an empty documentSymbol result for a uri that was never opened" do
    input =
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///missing.rb" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "returns MethodNotFound for an unknown request instead of crashing" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/completion", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    messages = sent_messages
    expect(messages[0][:error]).to include(code: -32601)
    expect(messages[1]).to include(id: 2)
  end

  it "logs and continues after a notification handler raises" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///missing.rb", version: 2 },
          contentChanges: [{ text: "x" }]
        }
      ) +
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input).run }.not_to raise_error
    expect(logger).to have_received(:error)

    messages = sent_messages
    expect(messages[0]).to include(id: 1)
  end

  it "exits with status 1 when exit arrives without a prior shutdown" do
    input = frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(build_server(input).run).to eq(1)
  end
end
