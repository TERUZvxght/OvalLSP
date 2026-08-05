# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server route helper support" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def route_fact(name:, verb:, action:, controller: "posts", required: [], location: nil)
    {
      name: name, verb: verb, pathTemplate: "/#{controller}", requiredParts: required, optionalParts: ["format"],
      defaults: { controller: controller, action: action }, sourceLocation: location, routeSet: "main_app"
    }
  end

  def build_server(input_string, registry)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger, route_registry: registry)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  let(:post_registry) do
    Ovallsp::Routes::RouteRegistry.from_route_facts([
                                                     route_fact(name: "post", verb: "GET", action: "show", required: ["id"],
                                                                location: { path: "/app/config/routes.rb", line: 3 }),
                                                     route_fact(name: "post", verb: "PATCH", action: "update", required: ["id"]),
                                                     route_fact(name: "post", verb: "DELETE", action: "destroy", required: ["id"]),
                                                     route_fact(name: "posts", verb: "GET", action: "index")
                                                   ])
  end

  it "completes post_path from a partial identifier" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "post_p\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 6 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, post_registry).run

    labels = sent_messages.first[:result][:items].map { |item| item[:label] }
    expect(labels).to include("post_path")
    expect(labels).not_to include("posts_path") # "post_p" isn't a prefix of "posts_path"
  end

  it "offers signature help for post_path(post) using the route's required and optional parts" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "post_path(post)\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 10 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, post_registry).run

    signature = sent_messages.first[:result][:signatures].first
    expect(signature[:label]).to eq("post_path(id, format = nil, options = {})")
    expect(signature[:parameters]).to eq([{ label: "id" }, { label: "format = nil" }])
  end

  it "shows post_url (not post_path) in the signature label when that's what was actually called (Task 008.5)" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "post_url(post)\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 9 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, post_registry).run

    signature = sent_messages.first[:result][:signatures].first
    expect(signature[:label]).to eq("post_url(id, format = nil, options = {})")
  end

  it "resolves textDocument/definition for post_path to routes.rb and PostsController#show" do
    controller_uri = "file:///app/controllers/posts_controller.rb"
    controller_text = "class PostsController\n  def show\n  end\nend\n"

    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: controller_uri, text: controller_text, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "post_path(post)\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, post_registry).run

    locations = sent_messages.first[:result]
    expect(locations).to include(
      uri: "file:///app/config/routes.rb",
      range: { start: { line: 3, character: 0 }, end: { line: 3, character: 0 } }
    )
    expect(locations).to include(
      a_hash_including(uri: controller_uri, range: { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } })
    )
  end

  it "resolves textDocument/definition for post_url to the exact same locations as post_path (Task 008.5)" do
    controller_uri = "file:///app/controllers/posts_controller.rb"
    controller_text = "class PostsController\n  def show\n  end\nend\n"

    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: controller_uri, text: controller_text, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "post_url(post)\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, post_registry).run

    locations = sent_messages.first[:result]
    expect(locations).to include(
      uri: "file:///app/config/routes.rb",
      range: { start: { line: 3, character: 0 }, end: { line: 3, character: 0 } }
    )
    expect(locations).to include(
      a_hash_including(uri: controller_uri, range: { start: { line: 1, character: 2 }, end: { line: 2, character: 5 } })
    )
  end

  it "falls back gracefully when a route helper has no source location" do
    registry = Ovallsp::Routes::RouteRegistry.from_route_facts(
      [route_fact(name: "unlocatable", verb: "GET", action: "show", controller: "mystery", location: nil)]
    )

    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "unlocatable_path\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input, registry).run }.not_to raise_error
    expect(sent_messages.first[:result]).to eq([])
  end

  it "offers no completion for an unnamed route" do
    registry = Ovallsp::Routes::RouteRegistry.from_route_facts(
      [route_fact(name: nil, verb: "GET", action: "ping", controller: "health")]
    )

    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: "ping\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input, registry).run

    expect(sent_messages.first[:result]).to eq(isIncomplete: false, items: [])
  end
end
