# frozen_string_literal: true

require "stringio"

RSpec.describe Ovallsp::RuntimeAgent::Agent do
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
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
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

  # `024.136`. Optional parts were detected by testing the path spec for
  # the literal `(.:format)`, so a route with any other optional segment
  # was reported as having none — Signature Help then understates a path
  # helper's parameters, which is a wrong answer rather than an absent
  # one, because the helper really does accept them.
  #
  # Rails' own route object carries both lists, and the difference is the
  # answer. Asked of a real Rails 8.1.3.1 route set rather than reasoned
  # about:
  #
  #   get "/posts(/:page)", to: "posts#index", as: :paged_posts
  #   r = Rails.application.routes.routes.find { |x| x.name == "paged_posts" }
  #   r.parts           # => [:page, :format]
  #   r.required_parts  # => []
  #
  # so `parts - required_parts` is `[:page, :format]`, and the substring
  # test answers `["format"]`.
  it "reads a route's optional parts from the route, not from the path spec's text" do
    fake_route_class = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :parts, :source_location) do
      def path
        Struct.new(:spec).new(path_spec)
      end
    end
    # An optional segment that is not `(.:format)`, plus a required one.
    paged = fake_route_class.new("paged_posts", "GET", "/posts/:id(/:page)(.:format)",
                                 { controller: "posts", action: "index" }, [:id], %i[id page format], nil)

    fake_app = Class.new do
      define_method(:routes) { Struct.new(:routes).new([paged]) }
    end.new

    stub_const("Rails", Class.new do
      define_singleton_method(:version) { "7.1.0-fixture" }
      define_singleton_method(:application) { fake_app }
    end)

    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["routes"] }) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    route = sent_messages.first[:result][:routes].first
    expect(route).to include(requiredParts: ["id"], optionalParts: %w[page format])
  end

  it "answers agent/snapshot's routes section via the duck-typed route interface" do
    fake_route_class = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :parts, :source_location) do
      def path
        Struct.new(:spec).new(path_spec)
      end
    end
    named = fake_route_class.new("post", "GET", "/posts/:id(.:format)", { controller: "posts", action: "show" }, [:id],
                                       %i[id format], nil)
    unnamed = fake_route_class.new(nil, "GET", "/ping(.:format)", { controller: "health", action: "ping" }, [],
                                         %i[format], nil)

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

  describe "route source_location normalization (Task 008.5)" do
    def fake_route(source_location:, name: "post")
      fake_route_class = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :parts, :source_location) do
        def path
          Struct.new(:spec).new(path_spec)
        end
      end
      fake_route_class.new(name, "GET", "/posts/:id(.:format)", { controller: "posts", action: "show" }, [:id],
                            %i[id format], source_location)
    end

    def snapshot_routes(route)
      fake_app = Class.new { define_method(:routes) { Struct.new(:routes).new([route]) } }.new
      stub_const("Rails", Class.new do
        define_singleton_method(:version) { "7.1.0-fixture" }
        define_singleton_method(:application) { fake_app }
      end)

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["routes"] }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run
      sent_messages.first[:result][:routes].first
    end

    it "parses real Rails' \"path:line\" string format, converting to a 0-based line" do
      route = fake_route(source_location: "/app/config/routes.rb:12")

      expect(snapshot_routes(route)[:sourceLocation]).to eq(path: "/app/config/routes.rb", line: 11, column: 0)
    end

    it "resolves a relative path against Rails.root" do
      stub_const("Rails", Class.new do
        define_singleton_method(:version) { "7.1.0-fixture" }
        define_singleton_method(:root) { "/app" }
      end)
      # Reassigning Rails.application after the fact so #routes_available?
      # still finds it; simplest is to just build the route directly.
      route = fake_route(source_location: "config/routes.rb:1")
      fake_app = Class.new { define_method(:routes) { Struct.new(:routes).new([route]) } }.new
      Rails.define_singleton_method(:application) { fake_app }

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["routes"] }) +
        frame(jsonrpc: "2.0", method: "agent/shutdown", params: {})
      build_agent(input).run

      expect(sent_messages.first[:result][:routes].first[:sourceLocation]).to eq(
        path: "/app/config/routes.rb", line: 0, column: 0
      )
    end

    it "handles a gem-internal path string (framework routes) without crashing" do
      # Real Rails source_location for framework-internal routes (e.g.
      # rails/info) looks like this — not a real file under the app root,
      # but normalization must still produce a well-formed result rather
      # than raising; Core degrades gracefully if the path doesn't resolve
      # to anything openable.
      route = fake_route(source_location: "railties (8.1.3) lib/rails/application/finisher.rb:143")

      result = nil
      expect { result = snapshot_routes(route)[:sourceLocation] }.not_to raise_error
      expect(result[:line]).to eq(142)
      expect(result[:path]).to end_with("railties (8.1.3) lib/rails/application/finisher.rb")
    end

    it "returns nil for an unparsable source_location string instead of raising" do
      route = fake_route(source_location: "not a location at all")

      expect { snapshot_routes(route) }.not_to raise_error
      expect(snapshot_routes(route)[:sourceLocation]).to be_nil
    end

    it "accepts a Hash form, treating :line as 1-based like every other shape Rails gives" do
      route = fake_route(source_location: { path: "/app/config/routes.rb", line: 5 })

      expect(snapshot_routes(route)[:sourceLocation]).to eq(path: "/app/config/routes.rb", line: 4, column: 0)
    end

    it "returns nil when there's no source location at all" do
      route = fake_route(source_location: nil)

      expect(snapshot_routes(route)[:sourceLocation]).to be_nil
    end
  end

  it "treats a route's empty-string verb (e.g. real Rails' `via: :all`) as GET, not \"\"" do
    fake_route_class = Struct.new(:name, :verb, :path_spec, :defaults, :required_parts, :parts, :source_location) do
      def path
        Struct.new(:spec).new(path_spec)
      end
    end
    any_verb = fake_route_class.new("catch_all", "", "/catch_all(.:format)", { controller: "x", action: "y" }, [],
                                        %i[format], nil)

    fake_app = Class.new do
      define_method(:routes) { Struct.new(:routes).new([any_verb]) }
    end.new

    stub_const("Rails", Class.new do
      define_singleton_method(:version) { "7.1.0-fixture" }
      define_singleton_method(:application) { fake_app }
    end)

    input =
      frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["routes"] }) +
      frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

    build_agent(input).run

    expect(sent_messages.first[:result][:routes].first[:verb]).to eq("GET")
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

    it "returns every non-abstract model's full columns/associations in one agent/models response (Task 008.5)" do
      base = stub_active_record_base!
      fake_model_class("ApplicationRecord", base: base, table_name: nil, abstract: true)
      fake_model_class(
        "StubbedUser", base: base, table_name: "stubbed_users",
        columns: [{ name: "id", type: :integer, null: false }],
        associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: { optional: true } }]
      )
      fake_model_class("StubbedCompany", base: base, table_name: "stubbed_companies")

      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/models", params: {}) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      models = sent_messages.first[:result][:models]
      user = models.find { |m| m[:name] == "StubbedUser" }
      expect(user[:columns]).to include(name: "id", type: "integer", null: false)
      expect(user[:associations]).to include(name: "company", macro: "belongs_to", className: "StubbedCompany", optional: true)
      expect(models.map { |m| m[:name] }).to contain_exactly("StubbedUser", "StubbedCompany")
    end

    it "returns an empty list from agent/models rather than crashing when Active Record isn't available" do
      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/models", params: {}) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

      build_agent(input).run

      expect(sent_messages.first[:result]).to eq(models: [])
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

    describe "belongs_to optional? honors belongs_to_required_by_default (Task 008.6)" do
      it "reports a belongs_to with no explicit optional: as NOT optional when belongs_to_required_by_default is true (Rails 5+ default)" do
        base = stub_active_record_base!
        base.define_singleton_method(:belongs_to_required_by_default) { true }
        fake_model_class(
          "StubbedUser", base: base, table_name: "stubbed_users",
          associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: {} }]
        )

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "StubbedUser" }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        association = sent_messages.first[:result][:associations].first
        expect(association[:optional]).to be(false)
      end

      it "reports a belongs_to with no explicit optional: as optional when belongs_to_required_by_default is false" do
        base = stub_active_record_base!
        base.define_singleton_method(:belongs_to_required_by_default) { false }
        fake_model_class(
          "StubbedUser", base: base, table_name: "stubbed_users",
          associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: {} }]
        )

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "StubbedUser" }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        association = sent_messages.first[:result][:associations].first
        expect(association[:optional]).to be(true)
      end

      it "still honors an explicit optional: false even when belongs_to_required_by_default is false" do
        base = stub_active_record_base!
        base.define_singleton_method(:belongs_to_required_by_default) { false }
        fake_model_class(
          "StubbedUser", base: base, table_name: "stubbed_users",
          associations: [{ macro: :belongs_to, name: :company, class_name: "StubbedCompany", options: { optional: false } }]
        )

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/model", params: { name: "StubbedUser" }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        association = sent_messages.first[:result][:associations].first
        expect(association[:optional]).to be(false)
      end
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

    describe "eager loading before discovery (Task 008.5)" do
      it "discovers a model that only becomes defined once eager_load runs" do
        base = stub_active_record_base!
        autoloader = Class.new do
          define_method(:eager_load) do
            Object.const_set("LazyStubbedUser", Class.new(base) do
              define_singleton_method(:name) { "LazyStubbedUser" }
              define_singleton_method(:table_name) { "lazy_stubbed_users" }
              define_singleton_method(:abstract_class?) { false }
            end) unless Object.const_defined?("LazyStubbedUser")
          end
        end.new
        autoloaders = Struct.new(:main).new(autoloader)
        stub_const("Rails", Class.new do
          define_singleton_method(:version) { "7.1.0-fixture" }
          define_singleton_method(:autoloaders) { autoloaders }
        end)

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["models"] }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        expect(sent_messages.first[:result][:models]).to eq([{ name: "LazyStubbedUser", tableName: "lazy_stubbed_users" }])
      ensure
        Object.send(:remove_const, "LazyStubbedUser") if Object.const_defined?("LazyStubbedUser")
      end

      it "logs and continues instead of crashing when eager_load raises" do
        stub_active_record_base!
        autoloader = Class.new { define_method(:eager_load) { raise "broken model file" } }.new
        autoloaders = Struct.new(:main).new(autoloader)
        stub_const("Rails", Class.new do
          define_singleton_method(:version) { "7.1.0-fixture" }
          define_singleton_method(:autoloaders) { autoloaders }
        end)

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/snapshot", params: { sections: ["models"] }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        expect { build_agent(input).run }.not_to raise_error
        expect(sent_messages.first[:result][:models]).to eq([])
        expect(logger_messages.join).to include("eager load failed")
      end
    end

    describe "reloading models (Task 008.5)" do
      def stub_rails_with_reloader!(reload_calls, eager_load_calls)
        autoloader = Class.new { define_method(:eager_load) {} }.new
        autoloaders = Struct.new(:main).new(autoloader)
        reloader = Class.new do
          define_method(:reload!) { reload_calls << true }
        end.new
        fake_app = Struct.new(:reloader).new(reloader)

        stub_const("Rails", Class.new do
          define_singleton_method(:version) { "7.1.0-fixture" }
          define_singleton_method(:autoloaders) { autoloaders }
          define_singleton_method(:application) { fake_app }
        end)
      end

      it "runs Rails' reloader and re-eager-loads when sections includes models" do
        stub_active_record_base!
        reload_calls = []
        stub_rails_with_reloader!(reload_calls, [])

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: { sections: ["models"] }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        result = sent_messages.first[:result]
        expect(result).to eq(generation: 1, changedSections: ["models"], errors: [])
        expect(reload_calls).to eq([true])
      end

      it "reports a recoverable error and does not advance generation when the reloader raises" do
        stub_active_record_base!
        autoloader = Class.new { define_method(:eager_load) {} }.new
        autoloaders = Struct.new(:main).new(autoloader)
        reloader = Class.new { define_method(:reload!) { raise "boom" } }.new
        fake_app = Struct.new(:reloader).new(reloader)
        stub_const("Rails", Class.new do
          define_singleton_method(:version) { "7.1.0-fixture" }
          define_singleton_method(:autoloaders) { autoloaders }
          define_singleton_method(:application) { fake_app }
        end)

        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: { sections: ["models"] }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        result = sent_messages.first[:result]
        expect(result[:generation]).to eq(0)
        expect(result[:changedSections]).to eq([])
        expect(result[:errors].first).to include(code: "RELOAD_FAILED", recoverable: true)
      end

      it "does not attempt a models reload when Active Record isn't available" do
        input =
          frame(jsonrpc: "2.0", id: 1, method: "agent/reload", params: { sections: ["models"] }) +
          frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})

        build_agent(input).run

        expect(sent_messages.first[:result]).to eq(generation: 0, changedSections: [], errors: [])
      end
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

  describe "agent/ancestors" do
    def ancestors_for(names, root: "/app")
      input =
        frame(jsonrpc: "2.0", id: 1, method: "agent/ancestors", params: { names: names }) +
        frame(jsonrpc: "2.0", id: 2, method: "agent/shutdown", params: {})
      build_agent(input, root: root).run
      sent_messages.first[:result]
    end

    it "reports the running Object's own ancestors, which is the baseline for every answer" do
      result = ancestors_for([])

      expect(result[:objectAncestors]).to include("Object", "Kernel", "BasicObject")
    end

    # The whole point of measuring the baseline rather than assuming it:
    # an application that mixes into Object gives every class those
    # ancestors, and they are evidence about the application, not the class.
    # Asserts against a class rather than by mixing into the real `Object`:
    # `Object.include` cannot be undone, so that version left the module in
    # `Object.ancestors` for every later example in the process.
    it "reports whatever the application mixed in, so the baseline can cancel it out" do
      stub_const("FixtureAppMixin", Module.new)
      stub_const("FixtureMixedThing", Class.new { include FixtureAppMixin })

      answer = ancestors_for(["FixtureMixedThing"])[:classes][:FixtureMixedThing]

      expect(answer[:ancestors]).to include("FixtureAppMixin")
      expect(answer[:ancestors]).to include("Object", "Kernel", "BasicObject")
    end

    it "reports a class's full ancestry, so a mixed-in module is visible" do
      stub_const("FixtureMixin", Module.new)
      stub_const("FixtureThing", Class.new { include FixtureMixin })

      expect(ancestors_for(["FixtureThing"])[:classes][:FixtureThing][:ancestors])
        .to include("FixtureThing", "FixtureMixin", "Object")
    end

    it "answers null for a name the application does not define, which is a real answer" do
      result = ancestors_for(["NoSuchConstantAnywhere"])

      expect(result[:classes]).to have_key(:NoSuchConstantAnywhere)
      expect(result[:classes][:NoSuchConstantAnywhere]).to be_nil
    end

    it "answers null for a constant that is not a class or module at all" do
      stub_const("FixtureNotAModule", 42)

      expect(ancestors_for(["FixtureNotAModule"])[:classes][:FixtureNotAModule]).to be_nil
    end

    it "resolves a namespaced name" do
      stub_const("FixtureOuter", Module.new)
      stub_const("FixtureOuter::Inner", Class.new)

      expect(ancestors_for(["FixtureOuter::Inner"])[:classes][:"FixtureOuter::Inner"][:ancestors])
        .to include("FixtureOuter::Inner")
    end

    # Asking about one broken name must not cost the answers for the rest:
    # these are gathered lazily, and a name that raises would otherwise
    # take the whole batch with it and be re-asked forever.
    it "answers null for a name whose resolution raises, and still answers the others" do
      stub_const("FixtureFine", Class.new)
      exploding = Module.new do
        def self.const_defined?(*) = raise("boom")
      end
      stub_const("FixtureExploding", exploding)

      result = ancestors_for(["FixtureExploding::Anything", "FixtureFine"])

      expect(result[:classes][:"FixtureExploding::Anything"]).to be_nil
      expect(result[:classes][:FixtureFine][:ancestors]).to include("FixtureFine")
    end

    # `Object.const_defined?("Foo")` is true for an autoload-registered
    # constant, and const_get would then *run* the autoload -- which in a
    # real application raised Gem::LoadError from a gem that is not in the
    # bundle. An Agent that loads arbitrary code to answer a diagnostic
    # question is not one worth having (024.R5).
    it "never resolves a name the application has only registered for autoload" do
      loaded = []
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:const_get) { |*| loaded << :ran; Class.new }
        define_singleton_method(:autoload?) { |*| "some/gem/path" }
      end
      stub_const("FixtureAutoloading", autoloading)

      ancestors_for(["FixtureAutoloading::Lazy"])

      expect(loaded).to be_empty
    end

    # The guard has to hold for every segment, not just the last one.
    # Walking to the owner of `Foo::Bar::Baz` resolves `Foo::Bar` on the
    # way, and resolving *that* through an autoload runs it just as surely.
    it "never loads an intermediate namespace that is only registered for autoload" do
      loaded = []
      outer = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "some/gem/inner" }
        define_singleton_method(:const_get) { |*| loaded << :ran; Module.new }
      end
      stub_const("FixtureOuterLazy", outer)

      result = ancestors_for(["FixtureOuterLazy::Inner::Leaf"])

      expect(loaded).to be_empty
      expect(result[:classes][:"FixtureOuterLazy::Inner::Leaf"]).to be_nil
    end

    # The answer that makes the unloaded case decidable at all. A gem's
    # own `autoload` registers the bare require path it was written with
    # ("active_support/test_case"), which is not a file this workspace
    # owns -- so the class is someone else's, established without loading
    # it (024.R5).
    it "reports a constant registered for autoload from a bare require path as defined outside the workspace" do
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "active_support/test_case" }
      end
      stub_const("FixtureGem", autoloading)

      answer = ancestors_for(["FixtureGem::TestCase"], root: "/workspace")[:classes][:"FixtureGem::TestCase"]

      expect(answer[:definedOutsideWorkspace]).to be(true)
    end

    it "reports one registered from an absolute path outside the workspace the same way" do
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "/elsewhere/gems/thing.rb" }
      end
      stub_const("FixtureElsewhere", autoloading)

      answer = ancestors_for(["FixtureElsewhere::Thing"], root: "/workspace")[:classes][:"FixtureElsewhere::Thing"]

      expect(answer[:definedOutsideWorkspace]).to be(true)
    end

    # The distinguishing case: Zeitwerk registers the application's own
    # classes by absolute path under the workspace root. Those are the
    # workspace's own, so the static reading must stand and the check must
    # keep firing for them.
    it "says nothing about a constant Zeitwerk registered from inside the workspace" do
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "/workspace/app/models/article.rb" }
      end
      stub_const("FixtureOwn", autoloading)

      answer = ancestors_for(["FixtureOwn::Article"], root: "/workspace")[:classes][:"FixtureOwn::Article"]

      expect(answer).to be_nil
    end

    # `Module#autoload?` inherits by default, so a class that genuinely
    # defines the constant itself would be handed its superclass's
    # registration and judged foreign on someone else's evidence --
    # silencing the check for a class the workspace owns.
    it "does not read a superclass's autoload registration for a constant the class defines itself" do
      parent = Class.new
      stub_const("FixtureParent", parent)
      parent.autoload(:Shared, "some/gem/shared")
      child = Class.new(parent)
      stub_const("FixtureChild", child)
      child.const_set(:Shared, Class.new)

      answer = ancestors_for(["FixtureChild::Shared"], root: "/workspace")[:classes][:"FixtureChild::Shared"]

      expect(answer).not_to be_nil
      expect(answer[:definedOutsideWorkspace]).to be_nil
      expect(answer[:ancestors]).to include("Object")
    end

    # A module can report a name that is the empty string while it is still
    # being defined. Sending `""` as an ancestor would put an entry in the
    # registry that matches no workspace constant and no RBS type, i.e. a
    # foreign ancestor, silencing the check for that receiver.
    it "omits an ancestor whose name is empty rather than reporting it" do
      nameless = Module.new
      allow(nameless).to receive(:name).and_return("")
      stub_const("FixtureEmptyNamed", Class.new { include nameless })

      answer = ancestors_for(["FixtureEmptyNamed"])[:classes][:FixtureEmptyNamed]

      expect(answer[:ancestors]).not_to include("")
      expect(answer[:ancestors]).to include("FixtureEmptyNamed")
    end

    it "answers null for an empty name rather than resolving Object itself" do
      expect(ancestors_for([""])[:classes][:""]).to be_nil
    end

    it "answers null when a namespace segment is not a module" do
      stub_const("FixtureScalar", 42)

      expect(ancestors_for(["FixtureScalar::Inner"])[:classes][:"FixtureScalar::Inner"]).to be_nil
    end

    # A root that is not absolute cannot decide whose file a path is. With
    # an empty root, a bare prefix test makes every absolute path look
    # like the workspace's own, which silences the check everywhere.
    it "treats nothing as the workspace's own when the root is not an absolute path" do
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "/anywhere/at/all.rb" }
      end
      stub_const("FixtureRootless", autoloading)

      answer = ancestors_for(["FixtureRootless::Thing"], root: "")[:classes][:"FixtureRootless::Thing"]

      expect(answer[:definedOutsideWorkspace]).to be(true)
    end

    # A prefix match on the root string alone would call
    # "/workspace-other/app/thing.rb" the workspace's own.
    it "does not mistake a sibling directory sharing the root's name prefix for the workspace" do
      autoloading = Module.new do
        define_singleton_method(:const_defined?) { |*| true }
        define_singleton_method(:autoload?) { |*| "/workspace-other/app/thing.rb" }
      end
      stub_const("FixtureSibling", autoloading)

      answer = ancestors_for(["FixtureSibling::Thing"], root: "/workspace")[:classes][:"FixtureSibling::Thing"]

      expect(answer[:definedOutsideWorkspace]).to be(true)
    end
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
  # `delegate` is one of the commonest lines in a Rails model, and it was
  # reported as an unknown method on every one -- with `class_attribute`,
  # `mattr_accessor`, `thread_mattr_accessor`, `concerning` and
  # `deprecate`.
  #
  # All six are ActiveSupport's additions to `Module`, and the class-level
  # list was `base.methods - Object.methods`. `Object` is itself a class
  # object, so that subtraction removes every public `Module` instance
  # method -- exactly where those six live -- and `Diagnostics::Engine`
  # treats what arrives as the model's *complete* class-level method set.
  it "keeps a class-level method that lives on Module, which Object also carries" do
    active_record = Class.new do
      define_singleton_method(:descendants) { [] }
      define_singleton_method(:delegate) { |*| nil }
      define_singleton_method(:find) { |*| nil }
    end
    stub_const("ActiveRecord", Module.new)
    stub_const("ActiveRecord::Base", active_record)
    stub_const("Rails", Class.new do
      define_singleton_method(:version) { "8.1.3-fixture" }
    end)

    agent = Ovallsp::RuntimeAgent::Agent.new(input: StringIO.new(""), output: StringIO.new,
                                             logger: ->(_) {}, root: "/app")
    api = agent.send(:active_record_api)

    expect(api[:singleton]).to include("find")
    # `delegate` is defined on this fixture's singleton, so it survives any
    # subtraction. The real regression is a name Object also answers to:
    # pick one every class object has and assert it is still listed.
    expect(api[:singleton]).to include("name")
  end
end
