# frozen_string_literal: true

require "fileutils"

# Exercises the Runtime Agent against a genuinely installed Rails
# (real `rails`/`activerecord`/`sqlite3` gems, not the hand-written
# fake_routing.rb/fake_active_record.rb harness `rails_minimal` uses
# elsewhere in this suite) -- Task 008.5 was explicitly about bugs that
# don't surface against a Fake Rails/ASCII-centric test double, so this
# suite exists to catch anything the fixture-based specs structurally
# can't (docs/design/tasks/008.5-runtime-and-index-corrections.md).
#
# Skipped entirely (not failed) when Rails/sqlite3 aren't resolvable from
# gems already installed on the machine running specs -- `bundle install
# --local` never touches the network, so this only runs where those gems
# already happen to be present. CI that can't afford real Rails boot time
# can exclude it: `bundle exec rspec --tag ~real_rails`.
RSpec.describe "Runtime Agent against a real Rails app", :real_rails do
  FIXTURE_ROOT = File.expand_path("../fixtures/rails_real", __dir__)
  ROUTES_FILE = File.join(FIXTURE_ROOT, "config/routes.rb")
  MODELS_DIR = File.join(FIXTURE_ROOT, "app/models")
  DB_FILE = File.join(FIXTURE_ROOT, "db/rails_real.sqlite3")
  BOOT_SCRIPT = File.expand_path("../../lib/rslsp/runtime_agent/boot.rb", __dir__)

  def self.real_rails_available?
    return @available if defined?(@available)

    Dir.chdir(FIXTURE_ROOT) do
      locked = system("bundle", "lock", "--local", out: File::NULL, err: File::NULL)
      installed = locked && system("bundle", "install", "--local", out: File::NULL, err: File::NULL)
      @available = installed
    end
  end

  before do
    skip "Rails/sqlite3 not available as local gems; skipping real-Rails integration suite" unless self.class.real_rails_available?
  end

  after do
    File.delete(DB_FILE) if File.exist?(DB_FILE)
  end

  let(:logger_messages) { [] }
  let(:logger) do
    double = Object.new
    messages = logger_messages
    double.define_singleton_method(:info) { |m| messages << [:info, m] }
    double.define_singleton_method(:warn) { |m| messages << [:warn, m] }
    double.define_singleton_method(:error) { |m| messages << [:error, m] }
    double
  end

  # Goes through RailsBootstrap.start itself (the actual production
  # invocation path -- `bundle exec ruby boot.rb ...`, with BUNDLE_GEMFILE
  # explicitly cleared) rather than constructing an AgentProcessManager by
  # hand, so this suite also exercises that BUNDLE_GEMFILE doesn't leak
  # from Core Server's own `bundle exec` invocation into the Agent child
  # process and silently point it at the wrong Gemfile
  # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
  def boot_manager(hello_timeout: 30)
    route_registry = Rslsp::Routes::RouteRegistry.new
    model_registry = Rslsp::Models::ModelRegistry.new
    Rslsp::RailsBootstrap.start(
      root: FIXTURE_ROOT, logger: logger, route_registry: route_registry, model_registry: model_registry,
      hello_timeout: hello_timeout
    )
  end

  # 1. Real Rails' own boot sequence (railties, gems, our noisy
  # initializer) writes to stdout via both `puts` and the `STDOUT`
  # constant directly; none of it may reach the framed protocol stream.
  it "keeps initializer stdout from corrupting the Agent protocol" do
    @manager = boot_manager

    expect(@manager.status).to eq(:ready)
    expect(logger_messages).to include([:info, a_string_matching(/accidental stdout from a noisy initializer \(real Rails\)/)])
    expect(logger_messages).to include([:info, a_string_matching(/accidental stdout via the STDOUT constant directly \(real Rails\)/)])
  ensure
    @manager&.stop
  end

  # 2 & 3. Routes come from real config/routes.rb, and each source
  # location is normalized (absolute path, 0-based line).
  it "lists routes drawn by real config/routes.rb with a normalized source_location" do
    @manager = boot_manager
    routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]

    post_index = routes.find { |r| r[:name] == "posts" && r[:verb] == "GET" }
    expect(post_index).not_to be_nil

    location = post_index[:sourceLocation]
    expect(location[:path]).to eq(ROUTES_FILE)
    expect(location[:path]).to start_with("/") # absolute
    expect(location[:line]).to be_a(Integer)
    expect(location[:line]).to be >= 0 # normalized from Rails' 1-based line to LSP's 0-based
    # The exact line Rails attributes a `resources` block's generated
    # routes to is a Rails-internal detail (varies by Rails version, and
    # doesn't necessarily land on the `resources :posts` line itself) --
    # what Core actually depends on is that it's *some* valid 0-based
    # line inside routes.rb, not any specific number.
    routes_lines = File.readlines(ROUTES_FILE)
    expect(location[:line]).to be < routes_lines.size
  ensure
    @manager&.stop
  end

  # 4 & 5. post_path and post_url both resolve back to the exact same
  # RouteHelper, and therefore the exact same routes.rb definition site.
  it "resolves both post_path and post_url to the same routes.rb definition (Core-side RouteRegistry over the real snapshot)" do
    @manager = boot_manager
    routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]
    registry = Rslsp::Routes::RouteRegistry.from_route_facts(routes)

    path_helper = registry.find_by_method_name("post_path")
    url_helper = registry.find_by_method_name("post_url")

    expect(path_helper).to equal(url_helper)
    expect(path_helper.source_location[:path]).to eq(ROUTES_FILE)
  ensure
    @manager&.stop
  end

  # 6. Rails' default (non-eager-load) development mode means a model
  # nobody has referenced yet is normally invisible to
  # ActiveRecord::Base.descendants -- Agent#eager_load_models! must still
  # surface it.
  it "discovers models that were never eager-loaded, in real Rails' default development mode" do
    @manager = boot_manager
    models = @manager.fetch_all_models

    expect(models.map { |m| m[:name] }).to include("User", "Post", "Company")
  ensure
    @manager&.stop
  end

  # 7 & 8. Real ActiveRecord column/association reflection, not a
  # hand-maintained fake.
  it "returns real ActiveRecord columns and associations for User" do
    @manager = boot_manager
    user = @manager.fetch_all_models.find { |m| m[:name] == "User" }

    expect(user[:columns]).to include(name: "name", type: "string", null: false)
    expect(user[:columns]).to include(name: "email", type: "string", null: true)
    expect(user[:associations]).to include(name: "company", macro: "belongs_to", className: "Company", optional: true)
    expect(user[:associations]).to include(name: "posts", macro: "has_many", className: "Post", optional: true)
  ensure
    @manager&.stop
  end

  # 9. A model added after boot becomes visible after an agent/reload
  # (models), and one removed after boot disappears -- Rails' own
  # reloader unloading/reloading autoloaded app/models constants.
  it "picks up a new model and drops a removed one after agent/reload (models)" do
    @manager = boot_manager
    tag_file = File.join(MODELS_DIR, "tag.rb")

    begin
      File.write(tag_file, "class Tag < ApplicationRecord\nend\n")
      reload_result = @manager.reload(sections: ["models"])
      expect(reload_result[:changedSections]).to eq(["models"])

      models_after_add = @manager.fetch_all_models
      expect(models_after_add.map { |m| m[:name] }).to include("Tag")

      File.delete(tag_file)
      @manager.reload(sections: ["models"])

      models_after_remove = @manager.fetch_all_models
      expect(models_after_remove.map { |m| m[:name] }).not_to include("Tag")
    ensure
      File.delete(tag_file) if File.exist?(tag_file)
    end
  ensure
    @manager&.stop
  end

  # 10. A route added after boot becomes visible after agent/reload
  # (routes), and one removed disappears -- real Rails' reload_routes!.
  it "picks up a new route and drops a removed one after agent/reload (routes)" do
    original_routes = File.read(ROUTES_FILE)
    @manager = boot_manager

    begin
      File.write(ROUTES_FILE, "Rails.application.routes.draw do\n  resources :posts\n  resources :companies\nend\n")
      reload_result = @manager.reload(sections: ["routes"])
      expect(reload_result[:changedSections]).to eq(["routes"])

      routes_after_add = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(routes_after_add.map { |r| r[:name] }).to include("companies")

      File.write(ROUTES_FILE, original_routes)
      @manager.reload(sections: ["routes"])

      routes_after_remove = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(routes_after_remove.map { |r| r[:name] }).not_to include("companies")
    ensure
      File.write(ROUTES_FILE, original_routes)
    end
  ensure
    @manager&.stop
  end

  # 11. Once the Agent has stopped, requests degrade to nil instead of
  # raising -- static (non-Rails-dependent) LSP features must keep
  # working regardless.
  it "returns nil instead of raising once the real-Rails-backed Agent has stopped" do
    @manager = boot_manager
    @manager.stop

    expect { @manager.fetch_model(name: "User") }.not_to raise_error
    expect(@manager.fetch_model(name: "User")).to be_nil
    expect(@manager.status).to eq(:stopped)
  end

  # 12. An Agent killed out from under Core (crash, OOM, ...) must not be
  # reported :ready forever -- mirrors the equivalent rails_minimal-fixture
  # test, but against a real Rails process specifically.
  it "degrades to static-only, not stuck at :ready, when the real-Rails-backed Agent is killed" do
    @manager = boot_manager
    pid = @manager.pid

    expect { Process.kill("KILL", pid) }.not_to raise_error
    sleep 0.3

    expect(@manager.request_status).to be_nil
    expect(@manager.status).to eq(:static_only)
  end
end
