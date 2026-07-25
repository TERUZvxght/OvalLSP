# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

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
  BOOT_SCRIPT = File.expand_path("../../lib/ovallsp/runtime_agent/boot.rb", __dir__)

  # Deliberately isolated from Core's own Bundler context via
  # BundleEnvironment (see its own docs): this fixture is a genuinely
  # separate Bundle graph from Core's, and Core's own BUNDLE_GEMFILE/
  # BUNDLE_PATH/BUNDLE_APP_CONFIG must never leak into the fixture's own
  # `bundle lock`/`bundle install` any more than they may leak into the
  # Runtime Agent process #boot_manager below eventually spawns via
  # RailsBootstrap.start (which applies the exact same isolation). Found
  # necessary by a review-bundle script that runs Core's own test suite
  # against a temporary, isolated BUNDLE_PATH to keep Core's own gem
  # install self-contained: without this, that isolation leaked into
  # *this* fixture's own bundle operations too (system() inherits the
  # parent process' ENV by default, same trap Process.spawn has), making
  # `bundle install --local` here fail to resolve rails/sqlite3/
  # activerecord from the machine's actual system gem install and this
  # entire suite spuriously report itself unavailable -- or, worse, only
  # partially unavailable in a way that let stale/wrong gems resolve.
  def self.fixture_bundle_env
    Ovallsp::BundleEnvironment.for_workspace(FIXTURE_ROOT)
  end

  # Whether rails/sqlite3 are installed on this *machine* at all --
  # answered WITHOUT going through BundleEnvironment, deliberately.
  #
  # Found by an independent review (round 3): #real_rails_available? below
  # gates this entire suite on `bundle lock/install --local` succeeding
  # *through BundleEnvironment* -- i.e. its precondition is the very code
  # under test. A regression in BundleEnvironment.base therefore made the
  # whole real-Rails suite report itself "unavailable" and silently SKIP
  # (0 failures, everything pending) under exactly the isolated-BUNDLE_PATH
  # invocation this Task 022.2 fix exists to make work -- turning a real
  # regression into a green run, the same "silently provides no coverage"
  # shape round 1 already caught for a different mechanism. Verified by
  # neutering `BundleEnvironment.base` to return `{}`: under a plain
  # `bundle exec rspec` the suite still failed loudly, but under
  # `BUNDLE_PATH=<tmp> bundle exec rspec` all 15 examples went pending.
  #
  # The pre-Bundler environment is reconstructed from Bundler's own
  # `BUNDLER_ORIG_*` snapshot (present whenever this suite runs under
  # `bundle exec`, which is always) rather than from BundleEnvironment's
  # heuristics, so this probe is genuinely independent of the module it
  # guards. Restoring GEM_HOME/GEM_PATH from that snapshot rather than
  # blindly nil'ing them also keeps the probe correct on chruby/RVM, whose
  # own GEM_HOME is not bundle-exec-derived (the round-1 finding).
  def self.machine_has_real_rails_gems?
    return @machine_gems if defined?(@machine_gems)

    intentionally_nil = "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
    env = {}
    ENV.each_key do |key|
      env[key] = nil if key.start_with?("BUNDLE_", "BUNDLER_") || %w[RUBYOPT RUBYLIB].include?(key)
    end
    %w[GEM_HOME GEM_PATH PATH].each do |key|
      original = ENV["BUNDLER_ORIG_#{key}"]
      env[key] = original == intentionally_nil ? nil : original if original
    end

    probe = 'exit(%w[rails sqlite3].all? { |g| !Gem::Specification.find_all_by_name(g).empty? } ? 0 : 1)'
    @machine_gems = system(env, RbConfig.ruby, "-e", probe, out: File::NULL, err: File::NULL)
  end

  def self.real_rails_available?
    unless defined?(@available)
      @available = Dir.chdir(FIXTURE_ROOT) do
        env = fixture_bundle_env
        locked = system(env, "bundle", "lock", "--local", out: File::NULL, err: File::NULL)
        locked && system(env, "bundle", "install", "--local", out: File::NULL, err: File::NULL)
      end
      # The machine genuinely has the gems, yet resolving them through
      # BundleEnvironment's spawn env failed -- that is a BundleEnvironment
      # (Task 022.2) regression, not an unavailable-fixture situation.
      # Memoized as an error (rather than raised inline) so it is re-raised
      # for *every* example rather than only whichever one happened to run
      # first under `--order random`.
      @availability_error =
        if @available || !machine_has_real_rails_gems?
          nil
        else
          "rails/sqlite3 ARE installed on this machine, but `bundle lock/install --local` failed for " \
          "#{FIXTURE_ROOT} under BundleEnvironment.for_workspace's env -- Core's own Bundler context is " \
          "leaking into the fixture's separate Bundle graph (Task 022.2 regression). Reproduce with: " \
          "d=$(mktemp -d); BUNDLE_PATH=$d bundle install && BUNDLE_PATH=$d bundle exec rspec #{__FILE__} " \
          "(the `bundle install` is required -- an empty BUNDLE_PATH would fail for the unrelated reason " \
          "that Core's own gems aren't there yet)"
        end
    end

    raise @availability_error if @availability_error

    @available
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
    route_registry = Ovallsp::Routes::RouteRegistry.new
    model_registry = Ovallsp::Models::ModelRegistry.new
    Ovallsp::RailsBootstrap.start(
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

  # Task 008.6: a Ruby-level $stdout/STDOUT swap alone does not stop a
  # native extension writing to fd 1 directly, or a child process
  # (system/backticks/Open3) that inherits fd 1 -- both are realistic for
  # a genuine Rails app (asset pipelines, git/version probes, etc.).
  # boot.rb must redirect file descriptor 1 itself, not just the two Ruby
  # objects, before Rails is required.
  it "isolates a raw fd-1 write and a child process' inherited stdout against real Rails (Task 008.6)" do
    @manager = boot_manager

    expect(@manager.status).to eq(:ready)
    expect(@manager.request_status[:pid]).to eq(@manager.pid) # protocol wasn't corrupted by any of the below

    expect(logger_messages).to include([:info, a_string_matching(/accidental raw fd1 write via IO\.for_fd\(1\) \(real Rails\)/)])
    expect(logger_messages).to include([:info, a_string_matching(/accidental stdout from a child process via system.*\(real Rails\)/)])
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
    registry = Ovallsp::Routes::RouteRegistry.from_route_facts(routes)

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

  # Task 008.6: a belongs_to written *without* an explicit `optional:`
  # is required, not optional, under real Rails' own
  # belongs_to_required_by_default (true under any `config.load_defaults`
  # targeting Rails 5+, which this fixture sets to 8.1) -- Comment#post
  # exercises exactly that implicit case, unlike every other association
  # in this fixture which sets `optional:` explicitly.
  it "reports an implicit (no optional: kwarg) belongs_to as required under real Rails' belongs_to_required_by_default" do
    @manager = boot_manager
    comment = @manager.fetch_all_models.find { |m| m[:name] == "Comment" }

    expect(comment[:associations]).to include(name: "post", macro: "belongs_to", className: "Post", optional: false)
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

  # Task 022.2: Bundler boundary isolation. Core and this fixture are two
  # entirely separate Bundle graphs; a review-bundle process that runs
  # Core's own test suite against a temporary, isolated BUNDLE_PATH must
  # never leak that isolation into the Runtime Agent this fixture spawns.
  #
  # Every scenario below spawns a genuinely separate OS process whose OWN
  # live ENV carries the pollution under test, then has THAT process run
  # the real, unmodified RailsBootstrap.start -> BundleEnvironment.for_workspace
  # -> AgentProcessManager -> spawn-a-real-Agent path against its own
  # (now genuinely polluted) ENV -- never a global ENV mutation of *this*
  # RSpec process (see BundleEnvironment's own docs for why: Server is
  # multi-threaded, and a global ENV mutation would race any other thread
  # reading ENV during the same window).
  #
  # An earlier version of this block instead built a `env_source:` Hash
  # (`ENV.to_h.merge(overrides)`) and passed it directly to
  # `RailsBootstrap.start` in the *current* process. That does NOT
  # reproduce the actual bug: `BundleEnvironment.base` only emits
  # *overrides* (nil-outs and cleaned values) for whatever the given `env`
  # already has *live* -- `Process.spawn` still inherits everything else
  # from the real, current-process ENV regardless of what `env_source`
  # claims. So those tests only failed pre-fix when the RSpec process
  # *itself* happened to be running under a polluted bundle already
  # (i.e., only under the exact isolated-BUNDLE_PATH invocation this
  # whole fix is about) -- under a completely ordinary `bundle exec
  # rspec`, they passed even with the fix fully reverted, silently
  # providing no coverage in the common case (found by an independent
  # review). Spawning a real subprocess whose own ENV is genuinely
  # polluted closes that gap for regression A (BUNDLE_PATH/BUNDLE_APP_CONFIG
  # /GEM_HOME/GEM_PATH pollution): it fails pre-fix there under ANY
  # invocation, not just the isolated-BUNDLE_PATH one. Regression C
  # (RUBYOPT carrying "-rbundler/setup") is different: reverting only
  # #strip_bundler_setup_flag still passes this end-to-end scenario either
  # way, because a *stale* RUBYOPT alone doesn't stop `bundle exec` from
  # resolving the fixture's own Gemfile once BUNDLE_GEMFILE/BUNDLE_PATH are
  # already correct -- so this block's C scenario is a true end-to-end
  # sanity check ("the Agent still boots with this RUBYOPT set"), not a
  # regression test for #strip_bundler_setup_flag specifically. That
  # method's own behavior (it strips the flag, and only that flag) is
  # covered by spec/ovallsp/bundle_environment_spec.rb's unit tests, which
  # do fail pre-fix (found by an independent review).
  describe "Bundler boundary isolation (Task 022.2)" do
    CORE_LIB_DIR = File.expand_path("../../lib", __dir__)

    # Explicit load-path entries for Core's own runtime gem deps, computed
    # from *this* (unpolluted) process -- not left to the spawned
    # subprocess's own GEM_HOME/GEM_PATH resolution. This is deliberate:
    # the pollution under test represents "Core's own process was already
    # running (already successfully resolved its own prism/rbs) when it
    # spawns the Agent child" -- not "a process that can't even load
    # itself". Passing these via `-I` means the harness script's own
    # `require "ovallsp"` never depends on GEM_HOME/GEM_PATH being
    # correct, so a test can pollute GEM_HOME/GEM_PATH for
    # BundleEnvironment to read without also breaking the harness script
    # that reads it.
    def self.core_runtime_gem_load_paths
      %w[prism rbs].map { |name| File.join(Gem::Specification.find_by_name(name).full_gem_path, "lib") }
    end

    # The real, existing "bundler/setup" Bundler's own installation
    # provides -- a valid `-r` target, unlike a made-up path, so a test
    # that deliberately sets RUBYOPT to something ending in
    # "/bundler/setup" (regression C) doesn't crash the *harness*
    # process's own interpreter startup (RUBYOPT's `-r` flags are
    # auto-required for *every* Ruby invocation, including this harness
    # script's own -- not just ones going through `bundle exec`).
    def self.real_bundler_setup_require_arg
      bundler_dir = File.dirname(Bundler.method(:unbundled_env).source_location.first)
      "-r#{File.join(bundler_dir, "bundler", "setup")}"
    end

    # Spawns a real, separate Ruby process whose own ENV is
    # `ENV.to_h.merge(overrides)` (genuine pollution, not a Hash passed
    # only to a method call), runs the real RailsBootstrap.start against
    # this fixture with its own default `env_source: ENV` (i.e. exactly
    # the production code path, reading whatever's actually live in that
    # subprocess), and reports the resulting manager status (and, when
    # ready, a real ActiveRecord column) back as JSON on stdout.
    #
    # RUBYOPT is cleared for the harness's own spawn by default (not left
    # inherited) -- the ambient RUBYOPT under a normal `bundle exec rspec`
    # invocation already carries "-rbundler/setup" pointing at Core's own
    # (real, working) Bundler install, harmless on its own, but combined
    # with a test that deliberately breaks GEM_HOME/GEM_PATH (regression
    # A) it would make the *harness script itself* fail to boot before it
    # ever reaches the scenario under test. A test that specifically wants
    # RUBYOPT pollution (regression C) passes its own explicit override,
    # using #real_bundler_setup_require_arg rather than a made-up path for
    # exactly the same reason.
    #
    # BUNDLER_SETUP is cleared for the same reason, and is NOT merely
    # RUBYOPT's own concern: RubyGems' own bootstrap
    # (rubygems.rb -- `require ENV["BUNDLER_SETUP"] if ENV["BUNDLER_SETUP"]
    # && !defined?(Bundler)`) auto-requires whatever path BUNDLER_SETUP
    # names, completely independently of RUBYOPT's own `-r` flags.
    # `bundle exec` sets it to the real, absolute path of its own
    # `bundler/setup.rb` -- found the hard way: clearing RUBYOPT alone
    # still left the harness itself crashing during its own interpreter
    # startup (before this script's own code ever runs) whenever this
    # spec suite is invoked via the ordinary `bundle exec rspec` (which
    # sets BUNDLER_SETUP ambiently) combined with a test that deliberately
    # breaks GEM_HOME/GEM_PATH -- RubyGems' auto-require doesn't check
    # RUBYOPT at all, it checks this separate variable directly.
    def self.boot_status_with_polluted_subprocess_env(overrides)
      script = <<~RUBY
        require "ovallsp"
        require "json"

        logger = Object.new
        logger.define_singleton_method(:info) { |*| }
        logger.define_singleton_method(:warn) { |*| }
        logger.define_singleton_method(:error) { |*| }

        manager = Ovallsp::RailsBootstrap.start(
          root: #{FIXTURE_ROOT.inspect}, logger: logger,
          route_registry: Ovallsp::Routes::RouteRegistry.new,
          model_registry: Ovallsp::Models::ModelRegistry.new,
          hello_timeout: 30
        )

        result = { "status" => manager&.status&.to_s }
        if manager&.status == :ready
          user = manager.fetch_all_models&.find { |m| m[:name] == "User" }
          email_column = user && user[:columns]&.find { |c| c[:name] == "email" }
          result["user_email_column"] = email_column && email_column.transform_keys(&:to_s)
        end
        manager&.stop

        STDOUT.puts(JSON.generate(result))
      RUBY

      env = ENV.to_h.merge("RUBYOPT" => nil, "BUNDLER_SETUP" => nil).merge(overrides)
      load_path_args = ([CORE_LIB_DIR] + core_runtime_gem_load_paths).flat_map { |path| ["-I", path] }
      Open3.capture3(env, RbConfig.ruby, *load_path_args, "-e", script)
    end

    def self.parsed_boot_result(overrides)
      stdout, stderr, status = boot_status_with_polluted_subprocess_env(overrides)
      raise "subprocess failed (status=#{status.exitstatus}): #{stderr}" unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError
      raise "subprocess produced non-JSON output -- stdout: #{stdout.inspect}, stderr: #{stderr.inspect}"
    end

    # Regression A: a parent process whose own BUNDLE_PATH/BUNDLE_APP_CONFIG
    # (and the GEM_HOME/GEM_PATH `bundle exec` itself derives from them --
    # see BundleEnvironment's own docs) point at a throwaway, Core-only
    # directory (exactly what a review-bundle script isolating Core's own
    # gem install does) must not stop the Runtime Agent from reaching
    # :ready against the fixture's own, separate Bundle graph.
    it "boots to :ready even when the parent process' BUNDLE_PATH/BUNDLE_APP_CONFIG genuinely point at a Core-only directory" do
      Dir.mktmpdir do |core_only_dir|
        result = self.class.parsed_boot_result(
          "BUNDLE_PATH" => File.join(core_only_dir, "core-bundle"),
          "BUNDLE_APP_CONFIG" => File.join(core_only_dir, "core-config"),
          "GEM_HOME" => File.join(core_only_dir, "core-bundle", "ruby", RUBY_VERSION),
          "GEM_PATH" => ""
        )

        expect(result["status"]).to eq("ready")
      end
    end

    # Regression (round 4): `bundle exec` unshifts its own
    # "#{Bundler.bundle_path}/bin" onto PATH, and `Process.spawn` resolves a
    # bare command name (this Agent is spawned as literally `bundle`)
    # through the env Hash's own PATH -- so leaving PATH fully inherited
    # meant the Agent resolved executables out of *Core's* bundle. Proven
    # here rather than only at the unit level by planting a deliberately
    # broken `bundle` in exactly the directory Core's own `bundle exec`
    # would have put first on PATH: pre-fix the Agent runs that one and
    # never reaches :ready.
    it "does not resolve the Agent's own `bundle` out of Core's bundle-exec PATH entry" do
      Dir.mktmpdir do |core_only_dir|
        gem_home = File.join(core_only_dir, "core-bundle", "ruby", RUBY_VERSION)
        bin_dir = File.join(gem_home, "bin")
        FileUtils.mkdir_p(bin_dir)
        poisoned = File.join(bin_dir, "bundle")
        File.write(poisoned, "#!/bin/sh\nexit 47\n")
        FileUtils.chmod(0o755, poisoned)

        result = self.class.parsed_boot_result(
          "BUNDLE_PATH" => File.join(core_only_dir, "core-bundle"),
          "BUNDLE_APP_CONFIG" => File.join(core_only_dir, "core-config"),
          "GEM_HOME" => gem_home,
          "GEM_PATH" => "",
          "PATH" => "#{bin_dir}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH")}"
        )

        expect(result["status"]).to eq("ready")
      end
    end

    # Regression B: a parent process whose own BUNDLE_GEMFILE genuinely
    # points at Core's own Gemfile (exactly what happens whenever Core's
    # own process is itself launched via `bundle exec`, its normal
    # invocation) must not make the Runtime Agent try to use Core's
    # Gemfile instead of the fixture's own.
    it "uses the fixture's own Gemfile, not the parent's genuine BUNDLE_GEMFILE" do
      result = self.class.parsed_boot_result(
        "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__)
      )

      expect(result["status"]).to eq("ready")
      # Only resolvable via the fixture's own Gemfile (rails/sqlite3
      # aren't in Core's) -- reaching :ready and successfully fetching a
      # real ActiveRecord model's columns is only possible if the Agent
      # actually loaded Rails from the fixture's own bundle, not Core's.
      expect(result["user_email_column"]).to include("name" => "email", "type" => "string", "null" => true)
    end

    # Regression C: a parent process whose own RUBYOPT genuinely carries
    # "-rbundler/setup" (exactly what `bundle exec` injects, i.e. every
    # normal invocation of Core itself) must not prevent the Runtime
    # Agent's own `bundle exec` from resolving the fixture's Bundle, and
    # any *other*, legitimate RUBYOPT content survives alongside it
    # (verified with a distinctive extra flag here, not just via the
    # unit-level spec/ovallsp/bundle_environment_spec.rb coverage).
    it "boots to :ready even when the parent process' RUBYOPT genuinely carries -rbundler/setup" do
      result = self.class.parsed_boot_result(
        "RUBYOPT" => "#{self.class.real_bundler_setup_require_arg} -W1"
      )

      expect(result["status"]).to eq("ready")
    end

    # Regression D/E: the Agent process genuinely runs against the
    # fixture's own separate Bundle -- it can resolve a gem the fixture's
    # own Gemfile.lock installs (sqlite3, which Core's own Gemfile never
    # lists) but NOT one only Core's own Gemfile lists (rspec-core, which
    # the fixture's Gemfile never lists) -- proving actual Bundle graph
    # isolation, not merely that some Ruby process happened to boot.
    #
    # Deliberately NOT prism/rbs for the "Core-only" half of this check:
    # prism specifically ships as a *default* gem bundled with the Ruby
    # interpreter itself (Ruby 3.3+), so `require "prism"` succeeds
    # regardless of which Bundle is active -- found by this exact test
    # failing with `prism=true` even under correct isolation, before
    # switching to rspec-core (a genuine third-party gem, never bundled
    # with Ruby, only ever pulled in by Core's own Gemfile as a
    # development dependency).
    it "resolves a workspace-only gem the Agent needs (sqlite3) but not a Core-only gem (rspec-core) (regression D/E)" do
      env = Ovallsp::BundleEnvironment.for_workspace(FIXTURE_ROOT)
      probe = <<~RUBY
        begin
          require "sqlite3"
          sqlite3_loaded = true
        rescue LoadError
          sqlite3_loaded = false
        end
        begin
          require "rspec/core"
          rspec_loaded = true
        rescue LoadError
          rspec_loaded = false
        end
        puts "sqlite3=\#{sqlite3_loaded} rspec=\#{rspec_loaded}"
      RUBY

      stdout, _stderr, status = Open3.capture3(
        env, "bundle", "exec", "ruby", "-e", probe, chdir: FIXTURE_ROOT
      )

      expect(status).to be_success
      expect(stdout.strip).to eq("sqlite3=true rspec=false")
    end
  end
end
