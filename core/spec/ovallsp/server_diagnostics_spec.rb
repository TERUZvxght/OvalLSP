# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server textDocument/publishDiagnostics (Task 015)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def all_sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages
  end

  def diagnostics_for(uri)
    all_sent_messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == uri }
  end

  it "publishes a syntax-error diagnostic on didOpen" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "def foo(\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    diags = diagnostics_for("file:///a.rb").last[:params][:diagnostics]
    expect(diags.map { |d| d[:code] }).to include("syntax-error")
  end

  # Both messages are written to the stream before the server runs, so
  # the didChange is already waiting when the didOpen is dispatched --
  # which is the situation 037's C9 is about. One analysis, of the state
  # the two settled into. Until 0.2.10 this published twice, and the
  # first of the two described text the developer had already replaced.
  it "publishes the state the edits settled into, reflecting the current content" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "class Widget\n  def show\n    bogus_call\n  end\nend\n",
                                   version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///a.rb", version: 2 },
          contentChanges: [{ text: "class Widget\n  def show\n    puts \"ok\"\n  end\nend\n" }]
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    published = diagnostics_for("file:///a.rb")
    expect(published.size).to eq(1)
    # The *second* version, with the `bogus_call` of the first gone --
    # so this distinguishes "analysed the settled state" from both
    # "analysed the first and stopped" and "published without analysing".
    expect(published.last[:params][:version]).to eq(2)
    expect(published.last[:params][:diagnostics]).to eq([])
  end

  it "clears diagnostics when the document is closed" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "def foo(\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(jsonrpc: "2.0", method: "textDocument/didClose", params: { textDocument: { uri: "file:///a.rb" } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(diagnostics_for("file:///a.rb").last[:params][:diagnostics]).to eq([])
  end

  it "does not report unresolved-constant in the default (:safe) mode" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "TotallyMadeUpConstant.new\n", version: 1, languageId: "ruby" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    diags = diagnostics_for("file:///a.rb").last[:params][:diagnostics]
    expect(diags.map { |d| d[:code] }).not_to include("unresolved-constant")
  end

  it "reports unresolved-constant when initialized with diagnosticsMode: standard" do
    input =
      frame(
        jsonrpc: "2.0", id: 1, method: "initialize",
        params: { initializationOptions: { diagnosticsMode: "standard" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "TotallyMadeUpConstant.new\n", version: 1, languageId: "ruby" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    diags = diagnostics_for("file:///a.rb").last[:params][:diagnostics]
    expect(diags.map { |d| d[:code] }).to include("unresolved-constant")
  end
end
