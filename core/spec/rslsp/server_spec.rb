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
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
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
    # A document that was never opened has nothing to hover -- an empty,
    # non-committal result rather than a guess (Task 013).
    expect(messages[1][:result][:contents][:value]).to eq("")
    expect(messages[2]).to include(id: 3, result: nil)
  end

  it "answers textDocument/hover with the inferred type, plus origin/definition for a receiver-qualified call (Task 013)" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: { uri: "file:///widget.rb", text: "class Widget\n  def build\n  end\nend\n\nWidget.new.build\n",
                           version: 1, languageId: "ruby" }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/hover",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 5, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    value = sent_messages.first[:result][:contents][:value]
    expect(value).to include("Origin: source declaration")
    expect(value).to include("Defined: file:///widget.rb:2")
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
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/thisMethodDoesNotExist", params: {}) +
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

  it "resolves textDocument/definition for an identifier by lexical name" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///user.rb",
            text: "class User\nend\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: "file:///app.rb",
            text: "User.new\n",
            version: 1,
            languageId: "ruby"
          }
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///app.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to eq([{ uri: "file:///user.rb", range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } } }])
  end

  it "returns [] for textDocument/definition when no word is under the cursor" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "  \n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "answers workspace/symbol with matches across all open files" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///user.rb", text: "class User\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "workspace/symbol",
        params: { query: "Us" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result).to contain_exactly(a_hash_including(name: "User", kind: 5))
  end

  it "removes a file's workspace index contribution on a Deleted watched-file notification" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///user.rb", text: "class User\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
        params: { changes: [{ uri: "file:///user.rb", type: 3 }] }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "workspace/symbol",
        params: { query: "User" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq([])
  end

  it "answers the custom rslsp/explainType request with the inferred type" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "user = User.new\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 1 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User")
  end

  # Task 013's QueryContext existed (matching the design doc's required
  # interface) but was never actually constructed or consulted anywhere
  # -- a follow-up review of Tasks 009-013 flagged it as orphaned. These
  # exercise the fix directly: Server now builds one per hover/explainType
  # request and checks it for staleness afterward.
  describe "QueryContext wiring (Task 013 review fix)" do
    let(:server) { build_server("") }

    it "#build_query_context captures the current workspace/signature generations" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })

      expect(query_context.workspace_generation).to eq(server.instance_variable_get(:@workspace_index).generation)
      expect(query_context.signature_generation).to eq(server.instance_variable_get(:@signatures).generation)
    end

    it "#warn_if_stale logs a warning when the workspace generation moved on since the context was built" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })
      allow(server.instance_variable_get(:@workspace_index)).to receive(:generation).and_return(
        query_context.workspace_generation + 1
      )

      expect(logger).to receive(:warn).with(a_string_matching(/became stale/))
      server.send(:warn_if_stale, query_context)
    end

    it "#warn_if_stale does not log when nothing has changed" do
      query_context = server.send(:build_query_context, "file:///a.rb", { line: 0, character: 0 })

      expect(logger).not_to receive(:warn)
      server.send(:warn_if_stale, query_context)
    end
  end
end
