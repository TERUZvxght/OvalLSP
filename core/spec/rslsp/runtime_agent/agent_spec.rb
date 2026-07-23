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

  describe "agent/reload" do
    it "re-draws routes and advances generation when the app supports reload_routes!" do
      route_set = Struct.new(:routes).new([])
      reload_count = 0
      fake_app = Class.new do
        define_method(:routes) { route_set }
        define_method(:reload_routes!) { reload_count += 1 }
      end.new

      stub_const("Rails", Class.new do
        define_singleton_method(:version) { "7.1.0-fixture" }
        define_singleton_method(:application) { fake_app }
      end)

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: {}) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/reload", params: {}) +
        frame(jsonrpc: "2.0", id: 3, method: "agent/shutdown", params: {})

      build_agent(input).run

      messages = sent_messages
      expect(messages[0][:result]).to eq(generation: 1, changedSections: ["routes"], errors: [])
      expect(messages[1][:result]).to eq(generation: 2, changedSections: ["routes"], errors: [])
      expect(reload_count).to eq(2)
    end

    it "reports a recoverable error and does not advance generation when reload_routes! raises" do
      fake_app = Class.new do
        def routes = Struct.new(:routes).new([])
        def reload_routes! = raise("boom")
      end.new

      stub_const("Rails", Class.new do
        define_singleton_method(:version) { "7.1.0-fixture" }
        define_singleton_method(:application) { fake_app }
      end)

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: {}) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      result = sent_messages.first[:result]
      expect(result[:generation]).to eq(0)
      expect(result[:changedSections]).to eq([])
      expect(result[:errors].first).to include(code: "RELOAD_FAILED", recoverable: true)
    end

    it "is a graceful no-op (not an error) when there's no Rails app to reload" do
      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: {}) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      expect(sent_messages.first[:result]).to eq(generation: 0, changedSections: [], errors: [])
    end
  end

  describe "Active Record model extraction" do
    def stub_active_record_base!
      base = Class.new do
        def self.descendants
          @descendants ||= []
        end

        def self.inherited(subclass)
          super
          descendants << subclass
        end
      end
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Base", base)
      base
    end

    def fake_model_class(name, base:, table_name:, columns: [], associations: [], abstract: false)
      fake_column = Struct.new(:name, :type, :null, keyword_init: true)
      fake_reflection = Struct.new(:macro, :name, :class_name, :options, keyword_init: true)

      klass = Class.new(base) do
        define_singleton_method(:name) { name }
        define_singleton_method(:table_name) { table_name }
        define_singleton_method(:abstract_class?) { abstract }
        define_singleton_method(:columns) { columns.map { |c| fake_column.new(**c) } }
        define_singleton_method(:reflect_on_all_associations) do
          associations.map { |a| fake_reflection.new(**a) }
        end
      end
      stub_const(name, klass)
      klass
    end

    it "discovers non-abstract models via agent/snapshot's models section" do
      base = stub_active_record_base!
      fake_model_class("ApplicationRecord", base: base, table_name: nil, abstract: true)
      fake_model_class("StubbedUser", base: base, table_name: "stubbed_users")

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["models"] }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      models = sent_messages.first[:result][:models]
      expect(models).to eq([{ name: "StubbedUser", tableName: "stubbed_users" }])
    end

    it "returns columns and associations for a known model via agent/model" do
      base = stub_active_record_base!
      fake_model_class(
        "StubbedUser", base: base, table_name: "stubbed_users",
        columns: [{ name: "id", type: :integer, null: false }, { name: "company_id", type: :integer, null: true }],
        associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: { optional: true } }]
      )

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "StubbedUser" }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      result = sent_messages.first[:result]
      expect(result[:columns]).to include(name: "id", type: "integer", null: false)
      expect(result[:associations]).to include(name: "company", macro: "belongs_to", className: "StubbedCompany", optional: true)
      expect(result[:partial]).to be(false)
    end

    it "returns a NOT_FOUND error for an unknown or invalid model name, without constantizing arbitrary input" do
      stub_active_record_base!

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "Kernel" }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/model", params: { name: "NoSuchModel" }) +
        frame(jsonrpc: "2.0", id: 3, method: "agent/shutdown", params: {})

      build_agent(input).run

      messages = sent_messages
      expect(messages[0][:result][:error][:code]).to eq("NOT_FOUND") # Kernel isn't an AR model
      expect(messages[1][:result][:error][:code]).to eq("NOT_FOUND")
    end

    it "returns a partial result with associations intact when columns raise (DB unavailable)" do
      base = stub_active_record_base!
      user = fake_model_class(
        "StubbedUser", base: base, table_name: "stubbed_users",
        associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: {} }]
      )
      user.define_singleton_method(:columns) { raise "database unavailable" }

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "StubbedUser" }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      expect { build_agent(input).run }.not_to raise_error

      result = sent_messages.first[:result]
      expect(result[:columns]).to eq([])
      expect(result[:partial]).to be(true)
      expect(result[:associations]).not_to be_empty
    end
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
      frame(jsonrpc: "2.0", id: 1, method: "agent/thisMethodDoesNotExist", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    messages = sent_messages
    expect(messages[0][:error][:code]).to eq(-32601)
    expect(messages[1]).to include(id: 2)
  end
end
