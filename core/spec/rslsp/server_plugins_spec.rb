# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server plugin loading (Task 018)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../fixtures/plugins", __dir__) }

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

  after { Rslsp::Plugins.clear_registration("rslsp-example-state-machine") }

  it "adds the example plugin's fixture method without any Core code change" do
    manifest_path = File.join(fixtures_root, "state_machine_example", "plugin-manifest.json")
    input =
      frame(
        jsonrpc: "2.0", id: 1, method: "initialize",
        params: { initializationOptions: { pluginManifests: [manifest_path] } }
      ) +
      did_open("file:///a.rb", "class ExampleModel\nend\n\nExampleModel.new.pending?\n") +
      frame(
        jsonrpc: "2.0", id: 2, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 3, character: 19 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.find { |m| m[:id] == 2 }[:result]
    expect(result).to eq(type: "Boolean")
  end

  it "does not load anything when no pluginManifests are configured" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input).run }.not_to raise_error
  end

  it "drops a malformed plugin declaration instead of crashing the whole Server on it" do
    # Defense in depth for the Task 014-018 independent review's fourth
    # finding: Plugins::Loader's own isolation is what stops a plugin
    # from forging cross-process data in the first place, but nothing
    # downstream re-validated the shape of what a plugin returns before
    # this fix -- a malformed fact (missing :symbol_id, or one that
    # isn't a real Index::SymbolId) reaching WorkspaceIndex used to raise
    # an ordinary NoMethodError with no rescue anywhere between here and
    # #run, killing the whole Server process on what should be "one
    # broken plugin contributes nothing".
    server = build_server(frame(jsonrpc: "2.0", method: "exit", params: nil))
    context = Rslsp::Plugins::StaticContext.new("bad-plugin").tap do |c|
      c.restore_declarations([{ not_a_real_declaration: "forged" }])
    end

    expect { server.send(:apply_plugin_context, context) }.not_to raise_error
  end
end
