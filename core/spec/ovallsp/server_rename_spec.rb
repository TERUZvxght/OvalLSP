# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server textDocument/prepareRename and textDocument/rename (Task 016)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  it "renames a method's declaration and every resolved call site across files" do
    input =
      did_open("file:///widget.rb", "class Widget\n  def build\n  end\nend\n") +
      did_open("file:///user.rb", "Widget.new.build\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 1, character: 6 }, newName: "construct" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    changes = sent_messages.first[:result][:changes]
    expect(changes.keys).to contain_exactly(:"file:///widget.rb", :"file:///user.rb")
    expect(changes[:"file:///widget.rb"].first).to eq(
      range: { start: { line: 1, character: 6 }, end: { line: 1, character: 11 } }, newText: "construct"
    )
    expect(changes[:"file:///user.rb"].first[:newText]).to eq("construct")
  end

  it "returns a placeholder and range from prepareRename" do
    input =
      did_open("file:///widget.rb", "class Widget\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///widget.rb" }, position: { line: 0, character: 7 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    result = sent_messages.first[:result]
    expect(result[:placeholder]).to eq("Widget")
    expect(result[:range]).to eq(start: { line: 0, character: 6 }, end: { line: 0, character: 12 })
  end

  it "refuses (null result) prepareRename on a generated route helper call" do
    route_registry = Ovallsp::Routes::RouteRegistry.from_route_facts([
                                                                      { name: "user", verb: "GET", pathTemplate: "/users/:id",
                                                                        requiredParts: ["id"], optionalParts: [],
                                                                        defaults: { controller: "users", action: "show" },
                                                                        sourceLocation: nil, routeSet: "main_app" }
                                                                    ])
    input =
      did_open("file:///c.rb", "class UsersController\n  def show\n    user_path(1)\n  end\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/prepareRename",
        params: { textDocument: { uri: "file:///c.rb" }, position: { line: 2, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger, route_registry: route_registry)
    server.run

    expect(sent_messages.first[:result]).to be_nil
  end

  it "refuses (null WorkspaceEdit) a rename that would collide with an existing declaration" do
    input =
      did_open("file:///a.rb", "class Widget\nend\n\nclass Gadget\nend\n") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 7 }, newName: "Gadget" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to be_nil
  end

  it "does not confuse a local variable with a same-named local in a different scope" do
    source = "def a\n  x = 1\n  x\nend\n\ndef b\n  x = 2\n  x\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/rename",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 2, character: 2 }, newName: "y" }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    edits = sent_messages.first[:result][:changes][:"file:///a.rb"]
    lines = edits.map { |e| e[:range][:start][:line] }
    expect(lines).to contain_exactly(1, 2)
  end
end
