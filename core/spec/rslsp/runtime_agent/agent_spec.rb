# frozen_string_literal: true

require "stringio"

RSpec.describe Rslsp::RuntimeAgent::Agent do
  let(:output) { StringIO.new }
  let(:logger_messages) { [] }
  let(:logger) { ->(msg) { logger_messages << msg } }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_agent(input_string, root: "/app")
    described_class.new(input: StringIO.new(input_string), output: output, logger: logger, root: root)
  end

  def sent_messages
    output.rewind
    reader = Rslsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages
  end

  it "answers agent/hello with protocol/version/root metadata" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/hello", params: { protocolVersion: 1, coreVersion: "0.0.1" }) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input, root: "/workspace/app").run

    result = sent_messages.first[:result]
    expect(result).to include(
      protocolVersion: described_class::PROTOCOL_VERSION,
      root: "/workspace/app",
      rubyVersion: RUBY_VERSION
    )
  end

  it "reports Rails.version and Rails.root when a Rails constant is defined" do
    stub_const("Rails", Class.new do
      def self.version = "7.1.0-fixture"
      def self.root = "/rails/app"
    end)

    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/hello", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    result = sent_messages.first[:result]
    expect(result[:railsVersion]).to eq("7.1.0-fixture")
    expect(result[:root]).to eq("/rails/app")
  end

  it "answers agent/snapshot's routes section via the duck-typed route interface" do
    fake_route_class = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :source_location) do
      def path
        Struct.new(:spec).new(path_spec)
      end
    end
    named = fake_route_class.new("post", "GET", "/posts/:id(.:format)", { controller: "posts", action: "show" }, [:id], nil)
    unnamed = fake_route_class.new(nil, "GET", "/ping(.:format)", { controller: "health", action: "ping" }, [], nil)

    fake_app = Class.new do
      define_method(:routes) { Struct.new(:routes).new([named, unnamed]) }
    end.new

    stub_const("Rails", Class.new do
      define_singleton_method(:version) { "7.1.0-fixture" }
      define_singleton_method(:application) { fake_app }
    end)

    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["routes"] }) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    routes = sent_messages.first[:result][:routes]
    expect(routes.size).to eq(1) # the unnamed /ping route is skipped
    expect(routes.first).to include(name: "post", verb: "GET", requiredParts: ["id"])
  end

  it "answers agent/status with the process pid" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/status", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    result = sent_messages.first[:result]
    expect(result[:pid]).to eq(Process.pid)
    expect(result[:uptimeSeconds]).to be_a(Numeric)
  end

  it "exits its run loop after agent/shutdown" do
    input = frame(jsonrpc: "2.0", id: 1, method: "agent/shutdown", params: {})

    expect(build_agent(input).run).to eq(0)
  end

  it "exits cleanly on stdin EOF without a shutdown request" do
    expect(build_agent("").run).to eq(0)
  end

  it "returns MethodNotFound for unknown requests without crashing the loop" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    messages = sent_messages
    expect(messages[0][:error][:code]).to eq(-32601)
    expect(messages[1]).to include(id: 2)
  end
end
