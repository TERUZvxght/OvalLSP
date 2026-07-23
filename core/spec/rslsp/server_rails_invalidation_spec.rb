# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server Rails file-change invalidation" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:route_registry) { Rslsp::Routes::RouteRegistry.new }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def changes_input(changes)
    frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles", params: { changes: changes }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
  end

  def build_server(input_string, agent_manager:, agent_bootstrap: nil, workspace_root: "/workspace")
    server = Rslsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger,
      route_registry: route_registry, model_registry: model_registry,
      workspace_root: workspace_root, agent_bootstrap: agent_bootstrap || Rslsp::RailsBootstrap
    )
    server.instance_variable_set(:@agent_manager, agent_manager)
    server
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield

      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "reloads and re-fetches routes when config/routes.rb changes" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) do |sections:|
        calls << [:reload, sections]
        { generation: 2, changedSections: sections, errors: [] }
      end
      define_singleton_method(:fetch_snapshot) do |sections:|
        calls << [:fetch_snapshot, sections]
        {
          routes: [{
            name: "new_route", verb: "GET", pathTemplate: "/new", requiredParts: [], optionalParts: ["format"],
            defaults: { controller: "widgets", action: "index" }, sourceLocation: nil, routeSet: "main_app"
          }]
        }
      end
    end

    server = build_server(changes_input([{ uri: "file:///app/config/routes.rb", type: 2 }]), agent_manager: fake_manager)
    server.run

    expect(calls.pop(timeout: 2)).to eq([:reload, ["routes"]])
    expect(calls.pop(timeout: 2)).to eq([:fetch_snapshot, ["routes"]])
    expect(wait_until { route_registry.completion_names("new_").include?("new_route_path") }).to be(true)
  end

  it "re-fetches only the changed model when a file under app/models/ changes" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_model) do |name:|
        calls << [:fetch_model, name]
        { name: name, tableName: "users", columns: [], associations: [], partial: false }
      end
    end

    server = build_server(changes_input([{ uri: "file:///app/app/models/user.rb", type: 2 }]), agent_manager: fake_manager)
    server.run

    expect(calls.pop(timeout: 2)).to eq([:fetch_model, "User"])
    expect(wait_until { model_registry.known_model?("User") }).to be(true)
  end

  it "camelizes a namespaced model path (app/models/admin/project.rb -> Admin::Project)" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_model) do |name:|
        calls << name
        { name: name, tableName: "projects", columns: [], associations: [], partial: false }
      end
    end

    server = build_server(
      changes_input([{ uri: "file:///app/app/models/admin/project.rb", type: 2 }]), agent_manager: fake_manager
    )
    server.run

    expect(calls.pop(timeout: 2)).to eq("Admin::Project")
  end

  it "restarts the whole Agent when Gemfile.lock changes" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) { calls << :stopped }
    end
    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |**kwargs|
        calls << [:restarted, kwargs[:root]]
        :new_manager
      end
    end

    server = build_server(
      changes_input([{ uri: "file:///workspace/Gemfile.lock", type: 2 }]),
      agent_manager: fake_manager, agent_bootstrap: fake_bootstrap, workspace_root: "/workspace"
    )
    server.run

    expect(calls.pop(timeout: 2)).to eq(:stopped)
    expect(calls.pop(timeout: 2)).to eq([:restarted, "/workspace"])
  end

  it "does nothing when no Agent is running (never started or static-only)" do
    server = build_server(changes_input([{ uri: "file:///app/config/routes.rb", type: 2 }]), agent_manager: nil)

    expect { server.run }.not_to raise_error
  end

  it "does nothing when the Agent exists but isn't ready (static-only)" do
    not_ready_manager = Class.new do
      define_singleton_method(:ready?) { false }
    end

    server = build_server(
      changes_input([{ uri: "file:///app/config/routes.rb", type: 2 }]), agent_manager: not_ready_manager
    )

    expect { server.run }.not_to raise_error
  end

  it "logs a warning instead of silently dropping a change when the Agent isn't ready" do
    not_ready_manager = Class.new do
      define_singleton_method(:ready?) { false }
      define_singleton_method(:status) { :starting }
    end

    server = build_server(
      changes_input([{ uri: "file:///app/config/routes.rb", type: 2 }]), agent_manager: not_ready_manager
    )

    server.run

    expect(logger).to have_received(:warn).with(/not ready/)
  end

  it "deduplicates a batch: many files for the same model only trigger one fetch_model call" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_model) do |name:|
        calls << name
        { name: name, tableName: "users", columns: [], associations: [], partial: false }
      end
    end

    # Simulates an editor reporting the same file changed twice in one
    # notification batch (harmless in practice, but shouldn't double the
    # Agent traffic) alongside a genuinely different model.
    changes = [
      { uri: "file:///app/app/models/user.rb", type: 2 },
      { uri: "file:///app/app/models/user.rb", type: 2 },
      { uri: "file:///app/app/models/company.rb", type: 2 }
    ]

    server = build_server(changes_input(changes), agent_manager: fake_manager)
    server.run

    seen = []
    seen << calls.pop(timeout: 2)
    seen << calls.pop(timeout: 2)
    expect(seen).to contain_exactly("User", "Company")
    expect(calls.pop(timeout: 0.2)).to be_nil # no third call
  end

  it "deduplicates a batch: many Gemfile.lock/initializer changes only trigger one restart" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) { calls << :stopped }
    end
    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |**|
        calls << :restarted
        :new_manager
      end
    end

    changes = [
      { uri: "file:///workspace/Gemfile.lock", type: 2 },
      { uri: "file:///workspace/config/initializers/a.rb", type: 2 },
      { uri: "file:///workspace/config/initializers/b.rb", type: 2 }
    ]

    server = build_server(
      changes_input(changes), agent_manager: fake_manager, agent_bootstrap: fake_bootstrap,
      workspace_root: "/workspace"
    )
    server.run

    expect(calls.pop(timeout: 2)).to eq(:stopped)
    expect(calls.pop(timeout: 2)).to eq(:restarted)
    expect(calls.pop(timeout: 0.2)).to be_nil # only one restart despite three matching files
  end

  it "skips routes/model refreshes entirely when the same batch also needs a restart" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) { calls << :stopped }
      define_singleton_method(:reload) { |**| calls << :reload; nil }
      define_singleton_method(:fetch_model) { |**| calls << :fetch_model; nil }
    end
    fake_bootstrap = Class.new do
      define_singleton_method(:start) { |**| calls << :restarted; :new_manager }
    end

    changes = [
      { uri: "file:///workspace/Gemfile.lock", type: 2 },
      { uri: "file:///workspace/config/routes.rb", type: 2 },
      { uri: "file:///workspace/app/models/user.rb", type: 2 }
    ]

    server = build_server(
      changes_input(changes), agent_manager: fake_manager, agent_bootstrap: fake_bootstrap,
      workspace_root: "/workspace"
    )
    server.run

    expect(calls.pop(timeout: 2)).to eq(:stopped)
    expect(calls.pop(timeout: 2)).to eq(:restarted)
    expect(calls.pop(timeout: 0.2)).to be_nil # reload/fetch_model never called — restart supersedes them
  end
end
