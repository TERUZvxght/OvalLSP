# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server Rails DSL generated methods (Task 017)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Rslsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger, model_registry: model_registry)
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

  it "infers an enum predicate call's return type as Boolean" do
    source = "class Widget\n  enum status: { active: 0, archived: 1 }\n\n  def show\n    active?\n  end\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 4, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Boolean")
  end

  it "completes an enum predicate method after `receiver.`" do
    source = "class Widget\n  enum status: { active: 0, archived: 1 }\nend\n\nWidget.new.ac\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 4, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    labels = sent_messages.first[:result].map { |item| item[:label] }
    expect(labels).to include("active?")
  end

  it "infers a scope call's return type as Relation[Model]" do
    source = "class Widget\n  scope :active, -> { where(active: true) }\nend\n\nWidget.active\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 4, character: 8 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Relation[Widget]")
  end

  it "propagates a delegated attribute's real column type" do
    model_registry.register_from_agent_response(
      "Widget",
      { tableName: "widgets", partial: false, columns: [],
        associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: false }] }
    )
    model_registry.register_from_agent_response(
      "Company",
      { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }], associations: [] }
    )
    source = "class Widget\n  delegate :name, to: :company\n\n  def show\n    name\n  end\nend\n"
    input =
      did_open("file:///a.rb", source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 4, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "String")
  end

  it "removes generated methods once the DSL call is deleted from the file" do
    original = "class Widget\n  enum status: { active: 0 }\nend\n\nWidget.new.active?\n"
    input =
      did_open("file:///a.rb", original) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: "file:///a.rb", version: 2 },
          contentChanges: [{ text: "class Widget\nend\n\nWidget.new.active?\n" }]
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 3, character: 13 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end
end
