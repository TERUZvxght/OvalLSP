# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server Rails file-change invalidation" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:route_registry) { Ovallsp::Routes::RouteRegistry.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def changes_input(changes)
    frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles", params: { changes: changes }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
  end

  def build_server(input_string, agent_manager:, agent_bootstrap: nil, workspace_root: "/workspace")
    server = Ovallsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger,
      route_registry: route_registry, model_registry: model_registry,
      workspace_root: workspace_root, agent_bootstrap: agent_bootstrap || Ovallsp::RailsBootstrap
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

  it "serializes refreshes from the same Agent so an older response cannot overwrite a newer one" do
    first_fetch_entered = Queue.new
    release_first_fetch = Queue.new
    fetch_count = 0
    fetch_count_mutex = Mutex.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
      define_singleton_method(:fetch_snapshot) do |**|
        number = fetch_count_mutex.synchronize { fetch_count += 1 }
        if number == 1
          first_fetch_entered << true
          release_first_fetch.pop
        end
        name = number == 1 ? "old" : "new"
        {
          routes: [{
            name: name, verb: "GET", pathTemplate: "/#{name}", requiredParts: [], optionalParts: [],
            defaults: { controller: name, action: "index" }, sourceLocation: nil, routeSet: "main_app"
          }]
        }
      end
    end
    server = build_server("", agent_manager: fake_manager)

    server.send(:refresh_routes)
    expect(first_fetch_entered.pop(timeout: 2)).to be(true)
    server.send(:refresh_routes)
    release_first_fetch << true

    expect(wait_until { route_registry.completion_names("new").include?("new_path") }).to be(true)
    expect(route_registry.completion_names("old")).to be_empty
    server.send(:shutdown_background_tasks)
  end

  it "re-fetches only the changed model when a file under app/models/ changes" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| calls << :reload; { generation: 1, changedSections: ["models"], errors: [] } }
      define_singleton_method(:fetch_model) do |name:|
        calls << [:fetch_model, name]
        { name: name, tableName: "users", columns: [], associations: [], partial: false }
      end
    end

    server = build_server(changes_input([{ uri: "file:///app/app/models/user.rb", type: 2 }]), agent_manager: fake_manager)
    server.run

    expect(calls.pop(timeout: 2)).to eq(:reload)
    expect(calls.pop(timeout: 2)).to eq([:fetch_model, "User"])
    expect(wait_until { model_registry.known_model?("User") }).to be(true)
  end

  # Regression: this was the one mutation site left outside
  # @index_mutation_mutex. Swapping the signature environment and
  # emptying the summaries derived from it off the lock lets a request
  # thread compute a summary from the pre-reload environment and store it
  # after the clear, stranding a stale entry no later reload invalidates.
  it "reloads signatures and clears method summaries under the index lock" do
    fake_manager = Class.new do
      define_singleton_method(:ready?) { false }
    end
    server = build_server("", agent_manager: fake_manager)
    index_mutex = server.instance_variable_get(:@index_mutation_mutex)
    signatures = server.instance_variable_get(:@signatures)
    summary_store = server.instance_variable_get(:@method_summary_store)
    observations = []
    allow(signatures).to receive(:load) { observations << [:load, index_mutex.owned?] }
    allow(summary_store).to receive(:clear).and_wrap_original do |original|
      observations << [:clear, index_mutex.owned?]
      original.call
    end

    server.send(:handle_did_change_watched_files, { changes: [{ uri: "file:///workspace/sig/user.rbs", type: 2 }] })

    expect(observations).to eq([[:load, true], [:clear, true]])
  end

  it "publishes a changed-model batch and clears method summaries under one index lock" do
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
      define_singleton_method(:fetch_model) do |name:|
        { name: name, tableName: "#{name.downcase}s", columns: [], associations: [], partial: false }
      end
    end
    server = build_server("", agent_manager: fake_manager)
    index_mutex = server.instance_variable_get(:@index_mutation_mutex)
    summary_store = server.instance_variable_get(:@method_summary_store)
    clear_observations = Queue.new
    allow(summary_store).to receive(:clear).and_wrap_original do |original|
      acquired = index_mutex.try_lock
      index_mutex.unlock if acquired
      clear_observations << {
        lock_held: !acquired,
        user_present: model_registry.known_model?("User"),
        team_present: model_registry.known_model?("Team")
      }
      original.call
    end

    server.send(:refresh_models, Set["User", "Team"])

    expect(clear_observations.pop(timeout: 2)).to eq(
      lock_held: true, user_present: true, team_present: true
    )
    server.send(:shutdown_background_tasks)
  end

  # Regression: serializing refreshes on @agent_refresh_mutex made each
  # one queue behind the previous, so a slow/wedged Agent accumulated
  # blocked threads without bound while every queued refresh was already
  # stale. Targeted model refreshes are coalesced instead -- but they
  # must be coalesced, not dropped: a later refresh of ["Team"] says
  # nothing about an earlier ["User"], so superseding by generation (as
  # the whole-section refreshes do) would silently lose names.
  #
  # The name check alone did not test coalescing at all -- three
  # independent serialized refreshes fetch the same three names. The
  # claim is *one Agent round trip per batch*, so the reload count is
  # what has to be asserted, and it is only deterministic if the second
  # and third refreshes are queued while the first is provably already
  # inside `reload` (hence `entered`): the two behind it then find both
  # names pending, one drains them together and the other finds nothing.
  it "coalesces overlapping model refreshes into one batch without losing any name" do
    gate = Queue.new
    entered = Queue.new
    reloads = Queue.new
    fetched = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) do |**|
        reloads << :reload
        entered << :entered
        gate.pop # hold the refresh inside the mutex
        true
      end
      define_singleton_method(:fetch_model) do |name:|
        fetched << name
        { name: name, tableName: "#{name.downcase}s", columns: [], associations: [], partial: false }
      end
    end
    server = build_server("", agent_manager: fake_manager)

    server.send(:refresh_models, Set["User"])
    entered.pop(timeout: 2) # the first refresh has drained ["User"] and holds the mutex
    # Queued while the first refresh is blocked inside `reload`.
    server.send(:refresh_models, Set["Team"])
    server.send(:refresh_models, Set["Invoice"])
    gate << :go
    gate << :go

    collected = []
    collected << fetched.pop(timeout: 2) while collected.size < 3
    expect(collected).to contain_exactly("User", "Team", "Invoice")

    server.send(:shutdown_background_tasks)
    # Two round trips, not three: Team and Invoice were batched together.
    expect(reloads.size).to eq(2)
  end

  # Regression: the retention contract above was one step short of a
  # permanent wedge. `prepare_replace` raises on a malformed payload and
  # the ensure re-enqueued the *whole* drained batch -- bad name
  # included -- so every later drain re-included it, raised again, and
  # re-enqueued again. One model with a permanently malformed payload
  # therefore suppressed every unrelated model for the life of the
  # process: a well-formed `Post` queued afterwards never landed.
  it "drops a permanently malformed model instead of poisoning every later batch" do
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
      define_singleton_method(:fetch_model) do |name:|
        if name == "Team"
          {
            name: name, tableName: "teams", columns: [],
            associations: [{ name: "owner", macro: nil, className: "User" }], partial: false
          }
        else
          { name: name, tableName: "#{name.downcase}s", columns: [], associations: [], partial: false }
        end
      end
    end
    server = build_server("", agent_manager: fake_manager)

    server.send(:refresh_models, Set["User", "Team"])
    expect(wait_until { server.instance_variable_get(:@pending_model_names) == ["User"] }).to be(true)

    # An unrelated, well-formed model changes afterwards.
    server.send(:refresh_models, Set["Post"])

    expect(wait_until { model_registry.known_model?("Post") && model_registry.known_model?("User") }).to be(true)
    expect(model_registry.known_model?("Team")).to be(false)
    server.send(:shutdown_background_tasks)
  end

  # Regression: bounding thread accumulation against a wedged Agent is
  # the stated reason refreshes stopped being serialized at all, and
  # routes/all-models honour it by checking their generation before
  # blocking. Targeted model refreshes did not check anything: every
  # batch parked another thread on the mutex for the Agent's full
  # timeout, so an Agent wedged on a bad migration plus a few minutes of
  # saves under app/models/ accumulated one blocked thread (and one
  # @background_tasks entry) per save, without bound -- all of them
  # queued to perform the identical drain.
  it "parks at most one waiting thread per wedged model refresh, without losing names" do
    gate = Queue.new
    entered = Queue.new
    fetched = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) do |**|
        entered << :entered
        gate.pop
        true
      end
      define_singleton_method(:fetch_model) do |name:|
        fetched << name
        { name: name, tableName: "#{name.downcase}s", columns: [], associations: [], partial: false }
      end
    end
    server = build_server("", agent_manager: fake_manager)
    threads = server.instance_variable_get(:@background_tasks).instance_variable_get(:@threads)

    server.send(:refresh_models, Set["User"])
    entered.pop(timeout: 2) # wedged inside reload, holding the mutex
    8.times { |i| server.send(:refresh_models, Set["Model#{i}"]) }
    expect(wait_until { threads.count(&:alive?) <= 2 }).to be(true),
                                                          "expected one holder and at most one waiter, saw #{threads.count(&:alive?)} live threads"

    # Bowing out must not drop the bowed-out names: every one of them is
    # still ahead of the single waiter's drain.
    gate << :go
    gate << :go
    collected = []
    collected << fetched.pop(timeout: 2) while collected.size < 9
    expect(collected).to contain_exactly("User", *8.times.map { |i| "Model#{i}" })
    server.send(:shutdown_background_tasks)
  end

  # Regression: draining empties @pending_model_names, and every
  # re-enqueue lived on a hand-enumerated failure branch -- so anything
  # that *raised* (a broken pipe to a dying Agent, mid-round-trip)
  # unwound straight to the rescue with the whole batch already gone,
  # silently losing every name in it with only an error log.
  #
  # This is the *transient* case, where retrying is the right answer. A
  # malformed payload is the opposite and is covered separately above:
  # retrying that one forever is what poisoned every later batch.
  it "keeps every drained name pending when the batch raises" do
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
      define_singleton_method(:fetch_model) do |name:|
        raise IOError, "broken pipe" if name == "Team"

        { name: name, tableName: "#{name.downcase}s", columns: [], associations: [], partial: false }
      end
    end
    server = build_server("", agent_manager: fake_manager)

    server.send(:refresh_models, Set["User", "Team"])
    server.send(:shutdown_background_tasks)

    expect(server.instance_variable_get(:@pending_model_names)).to contain_exactly("User", "Team")
  end

  it "rolls back a changed-model batch when any payload is malformed" do
    model_registry.register_from_agent_response(
      "User", { name: "User", tableName: "old_users", columns: [], associations: [], partial: false }
    )
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
      define_singleton_method(:fetch_model) do |name:|
        if name == "User"
          { name: name, tableName: "new_users", columns: [], associations: [], partial: false }
        else
          {
            name: name, tableName: "teams", columns: [],
            associations: [{ name: "owner", macro: nil, className: "User" }], partial: false
          }
        end
      end
    end
    server = build_server("", agent_manager: fake_manager)
    summary_store = server.instance_variable_get(:@method_summary_store)
    allow(summary_store).to receive(:clear).and_call_original

    server.send(:refresh_models, Set["User", "Team"])
    server.send(:shutdown_background_tasks)

    expect(model_registry.model("User").table_name).to eq("old_users")
    expect(model_registry.known_model?("Team")).to be(false)
    expect(summary_store).not_to have_received(:clear)
    expect(logger).to have_received(:error).with(/failed to refresh models/)
  end

  it "computes diagnostics while holding a consistent semantic index snapshot" do
    server = build_server("", agent_manager: nil)
    index_mutex = server.instance_variable_get(:@index_mutation_mutex)
    lock_held = false
    engine = instance_double(Ovallsp::Diagnostics::Engine)
    allow(engine).to receive(:analyze) do
      acquired = index_mutex.try_lock
      index_mutex.unlock if acquired
      lock_held = !acquired
      []
    end
    server.instance_variable_set(:@diagnostics_engine, engine)
    document = Ovallsp::TextDocument.new(
      uri: "file:///workspace/a.rb", text: "value = 1\n", version: 1, language_id: "ruby"
    )

    server.send(:publish_diagnostics, document)

    expect(lock_held).to be(true)
  end

  it "removes a model from the registry when the Agent reports it no longer exists after reload" do
    calls = Queue.new
    model_registry.register_from_agent_response(
      "User", { name: "User", tableName: "users", columns: [], associations: [], partial: false }
    )
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| { generation: 1, changedSections: ["models"], errors: [] } }
      define_singleton_method(:fetch_model) do |name:|
        calls << name
        { name: name, error: { code: "NOT_FOUND", message: "no such model" } }
      end
    end

    server = build_server(changes_input([{ uri: "file:///app/app/models/user.rb", type: 1 }]), agent_manager: fake_manager)
    server.run

    expect(calls.pop(timeout: 2)).to eq("User")
    expect(wait_until { !model_registry.known_model?("User") }).to be(true)
  end

  it "camelizes a namespaced model path (app/models/admin/project.rb -> Admin::Project)" do
    calls = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| true }
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

  describe "schema changes (Task 008.6)" do
    def fake_manager_for(models_by_name)
      Class.new do
        define_singleton_method(:ready?) { true }
        define_singleton_method(:reload) { |**| true }
        define_singleton_method(:fetch_all_models) { models_by_name.values }
      end
    end

    it "re-fetches every model in one bulk round trip when db/schema.rb changes" do
      fake_manager = fake_manager_for(
        "User" => { name: "User", tableName: "users", columns: [{ name: "bio", type: "string", null: true }],
                    associations: [], partial: false },
        "Company" => { name: "Company", tableName: "companies", columns: [], associations: [], partial: false }
      )

      server = build_server(changes_input([{ uri: "file:///app/db/schema.rb", type: 2 }]), agent_manager: fake_manager)
      server.run

      expect(wait_until { model_registry.known_model?("User") && model_registry.known_model?("Company") }).to be(true)
      expect(model_registry.column("User", "bio").nullable).to be(true)
    end

    it "treats db/structure.sql the same as db/schema.rb" do
      fake_manager = fake_manager_for(
        "Order" => { name: "Order", tableName: "orders", columns: [], associations: [], partial: false }
      )

      server = build_server(changes_input([{ uri: "file:///app/db/structure.sql", type: 2 }]), agent_manager: fake_manager)
      server.run

      expect(wait_until { model_registry.known_model?("Order") }).to be(true)
    end

    it "treats a file under db/migrate/ the same as a schema change" do
      fake_manager = fake_manager_for(
        "Order" => { name: "Order", tableName: "orders", columns: [], associations: [], partial: false }
      )

      server = build_server(
        changes_input([{ uri: "file:///app/db/migrate/20260101000000_add_status_to_orders.rb", type: 2 }]),
        agent_manager: fake_manager
      )
      server.run

      expect(wait_until { model_registry.known_model?("Order") }).to be(true)
    end

    it "drops a model no longer returned after a schema change (generation-replace, not merge)" do
      model_registry.register_from_agent_response(
        "Removed", { name: "Removed", tableName: "removeds", columns: [], associations: [], partial: false }
      )
      fake_manager = fake_manager_for(
        "User" => { name: "User", tableName: "users", columns: [], associations: [], partial: false }
      )

      server = build_server(changes_input([{ uri: "file:///app/db/schema.rb", type: 2 }]), agent_manager: fake_manager)
      server.run

      expect(wait_until { model_registry.known_model?("User") }).to be(true)
      expect(model_registry.known_model?("Removed")).to be(false)
    end

    it "keeps last-known-good models instead of wiping the registry when the post-schema-change fetch fails" do
      model_registry.register_from_agent_response(
        "User", { name: "User", tableName: "users", columns: [], associations: [], partial: false }
      )
      fake_manager = Class.new do
        define_singleton_method(:ready?) { true }
        define_singleton_method(:reload) { |**| nil }
        define_singleton_method(:fetch_all_models) { nil } # communication failure
      end

      server = build_server(changes_input([{ uri: "file:///app/db/schema.rb", type: 2 }]), agent_manager: fake_manager)
      server.run
      sleep 0.1

      expect(model_registry.known_model?("User")).to be(true)
    end

    it "does not fetch or install a model snapshot when the prerequisite reload fails" do
      fetches = Queue.new
      fake_manager = Class.new do
        define_singleton_method(:ready?) { true }
        define_singleton_method(:reload) { |**| nil }
        define_singleton_method(:fetch_all_models) { fetches << :called; [] }
      end

      build_server(
        changes_input([{ uri: "file:///app/db/schema.rb", type: 2 }]), agent_manager: fake_manager
      ).run
      sleep 0.05

      expect(fetches.pop(timeout: 0.1)).to be_nil
    end
  end

  it "does not fetch a changed model when the prerequisite reload fails" do
    fetches = Queue.new
    fake_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| nil }
      define_singleton_method(:fetch_model) { |name:| fetches << name }
    end

    build_server(
      changes_input([{ uri: "file:///app/app/models/user.rb", type: 2 }]), agent_manager: fake_manager
    ).run
    sleep 0.05

    expect(fetches.pop(timeout: 0.1)).to be_nil
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

  it "atomically installs a restart snapshot and invalidates model-dependent method summaries" do
    old_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) {}
    end
    new_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) {}
    end
    installed = Queue.new
    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |install_snapshot:, **|
        install_snapshot.call(
          routes: [{
            name: "fresh", verb: "GET", pathTemplate: "/fresh", requiredParts: [], optionalParts: [],
            defaults: { controller: "fresh", action: "index" }, sourceLocation: nil, routeSet: "main_app"
          }],
          models: {
            "Post" => { name: "Post", tableName: "posts", columns: [], associations: [], partial: false }
          }
        )
        installed << true
        new_manager
      end
    end
    server = build_server(
      changes_input([{ uri: "file:///workspace/Gemfile.lock", type: 2 }]),
      agent_manager: old_manager, agent_bootstrap: fake_bootstrap, workspace_root: "/workspace"
    )
    summary_store = server.instance_variable_get(:@method_summary_store)
    allow(summary_store).to receive(:clear).and_call_original

    server.run

    expect(installed.pop(timeout: 2)).to be(true)
    expect(route_registry.completion_names("fresh")).to include("fresh_path")
    expect(model_registry.known_model?("Post")).to be(true)
    expect(summary_store).to have_received(:clear)
  end

  it "publishes neither routes nor models when a restart snapshot contains a malformed model" do
    route_registry.replace(
      [{ name: "old", verb: "GET", pathTemplate: "/old", requiredParts: [], optionalParts: [],
         defaults: { controller: "old", action: "index" }, sourceLocation: nil, routeSet: "main_app" }]
    )
    model_registry.register_from_agent_response(
      "User", { name: "User", tableName: "old_users", columns: [], associations: [], partial: false }
    )
    server = build_server("", agent_manager: nil)

    # Without this, the test passes vacuously against any build where
    # `install_agent_snapshot` does not exist: `send` itself raises
    # NoMethodError, satisfying the `raise_error(NoMethodError)` below,
    # and every assertion after it then holds trivially because nothing
    # ran. It would have stayed green if the method were deleted outright.
    expect(server.respond_to?(:install_agent_snapshot, true)).to be(true)

    expect do
      server.send(
        :install_agent_snapshot,
        routes: [{
          name: "fresh", verb: "GET", pathTemplate: "/fresh", requiredParts: [], optionalParts: [],
          defaults: { controller: "fresh", action: "index" }, sourceLocation: nil, routeSet: "main_app"
        }],
        models: {
          "Team" => {
            name: "Team", tableName: "teams", columns: [],
            associations: [{ name: "owner", macro: nil, className: "User" }], partial: false
          }
        }
      )
    end.to raise_error(NoMethodError, /to_sym/) # the malformed `macro: nil`, not a missing method

    expect(route_registry.completion_names("old")).to include("old_path")
    expect(route_registry.completion_names("fresh")).to be_empty
    expect(model_registry.model("User").table_name).to eq("old_users")
    expect(model_registry.known_model?("Team")).to be(false)
  end

  it "restarts the Agent on a Gemfile.lock change even when it's currently static-only — restart IS the recovery path" do
    calls = Queue.new
    static_only_manager = Class.new do
      define_singleton_method(:ready?) { false }
      define_singleton_method(:status) { :static_only }
      define_singleton_method(:stop) { calls << :stopped }
    end
    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |**|
        calls << :restarted
        :new_manager
      end
    end

    server = build_server(
      changes_input([{ uri: "file:///workspace/Gemfile.lock", type: 2 }]),
      agent_manager: static_only_manager, agent_bootstrap: fake_bootstrap, workspace_root: "/workspace"
    )
    server.run

    expect(calls.pop(timeout: 2)).to eq(:stopped)
    expect(calls.pop(timeout: 2)).to eq(:restarted)
  end

  it "never leaks an Agent process when two restart triggers race across separate notifications" do
    events = Queue.new
    next_id = 0

    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |**|
        id = (next_id += 1)
        sleep 0.05 # simulate a slow Rails boot so both restarts overlap
        manager = Object.new
        manager.define_singleton_method(:id) { id }
        manager.define_singleton_method(:stop) { events << [:stopped, id] }
        events << [:started, id]
        manager
      end
    end

    initial_manager = Object.new
    initial_manager.define_singleton_method(:stop) { events << [:stopped, :initial] }

    # Two SEPARATE notifications (not one batch) — e.g. `bundle install`
    # touching Gemfile.lock, then a followup save shortly after — each
    # independently triggers its own #restart_agent call.
    input =
      frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
            params: { changes: [{ uri: "file:///workspace/Gemfile.lock", type: 2 }] }) +
      frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
            params: { changes: [{ uri: "file:///workspace/Gemfile.lock", type: 2 }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = Ovallsp::Server.new(
      input: StringIO.new(input), output: output, logger: logger,
      route_registry: route_registry, model_registry: model_registry,
      workspace_root: "/workspace", agent_bootstrap: fake_bootstrap
    )
    server.instance_variable_set(:@agent_manager, initial_manager)
    server.run

    collected = Array.new(4) { events.pop(timeout: 2) }
    started_ids = collected.select { |kind, _| kind == :started }.map(&:last)
    stopped_ids = collected.select { |kind, _| kind == :stopped }.map(&:last)

    expect(wait_until { server.instance_variable_get(:@agent_manager).respond_to?(:id) }).to be(true)
    final_id = server.instance_variable_get(:@agent_manager).id

    leaked = started_ids - stopped_ids - [final_id]
    expect(leaked).to be_empty
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
      define_singleton_method(:reload) { |**| true }
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

  it "does not let a stale in-flight refresh from a replaced Agent overwrite the new Agent's fresh data (Task 008.6)" do
    release_old_fetch = Queue.new
    old_manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:reload) { |**| { generation: 1, changedSections: ["routes"], errors: [] } }
      define_singleton_method(:fetch_snapshot) do |**|
        release_old_fetch.pop # blocks until the test explicitly releases it, simulating an in-flight round trip
        {
          routes: [{
            name: "stale_route", verb: "GET", pathTemplate: "/stale", requiredParts: [], optionalParts: [],
            defaults: { controller: "stale", action: "index" }, sourceLocation: nil, routeSet: "main_app"
          }]
        }
      end
      define_singleton_method(:stop) {}
    end
    new_manager_populated = Queue.new
    fake_bootstrap = Class.new do
      define_singleton_method(:start) do |route_registry:, **|
        route_registry.replace(
          [{ name: "fresh_route", verb: "GET", pathTemplate: "/fresh", requiredParts: [], optionalParts: [],
             defaults: { controller: "fresh", action: "index" }, sourceLocation: nil, routeSet: "main_app" }]
        )
        new_manager_populated << true
        :new_manager
      end
    end

    # Observes every #replace call (rather than sleeping and hoping) so
    # this test deterministically tells whether the old Agent's stale
    # write ever lands, instead of a timing-dependent guess.
    replace_calls = Queue.new
    allow(route_registry).to receive(:replace).and_wrap_original do |original, facts|
      result = original.call(facts)
      replace_calls << facts.map { |f| f[:name] }
      result
    end

    # Two SEPARATE notifications, not one batch: a batch containing both a
    # :routes and a :restart change short-circuits straight to the
    # restart and skips #refresh_routes entirely (see "skips routes/model
    # refreshes..." above) -- this test needs #refresh_routes to actually
    # run and race the restart, which only happens across two
    # notifications, e.g. an editor saving routes.rb and then a
    # `bundle install` moments later.
    input =
      frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
            params: { changes: [{ uri: "file:///workspace/config/routes.rb", type: 2 }] }) +
      frame(jsonrpc: "2.0", method: "workspace/didChangeWatchedFiles",
            params: { changes: [{ uri: "file:///workspace/Gemfile.lock", type: 2 }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
    server = build_server(input, agent_manager: old_manager, agent_bootstrap: fake_bootstrap)
    server.run

    # The restart (triggered by the Gemfile.lock change in the same
    # batch) must complete -- and fully repopulate route_registry with
    # the new Agent's data -- before the old Agent's blocked fetch is
    # allowed to finish.
    expect(new_manager_populated.pop(timeout: 2)).to be(true)
    expect(replace_calls.pop(timeout: 2)).to eq(["fresh_route"])
    release_old_fetch << true

    # The old (stale) refresh_routes thread now proceeds: on unguarded
    # code it calls #replace with the stale route, which would show up
    # here; on guarded code it never calls #replace at all, and this
    # simply times out with nil -- either way we get a definite answer
    # instead of guessing via sleep.
    stale_replace_call = replace_calls.pop(timeout: 1)

    expect(stale_replace_call).to be_nil
    expect(route_registry.completion_names("fresh").map(&:to_s)).to include("fresh_route_path")
    expect(route_registry.completion_names("stale")).to be_empty
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
