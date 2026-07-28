# frozen_string_literal: true

require_relative "bundle_environment"
require_relative "agent_process_manager"

module Ovallsp
  # Detects a Rails app at the workspace root and, if one is found, spawns
  # the Runtime Agent and populates a RouteRegistry/ModelRegistry from its
  # snapshot — the wiring `core/bin/ovallsp` needs so route completion and
  # Active Record type inference actually work when the Core Server runs
  # for real, not just inside tests that construct AgentProcessManager
  # directly.
  #
  # Deliberately does NOT use `bin/rails runner`: that command boots the
  # whole Rails app (running every initializer) *before* handing control to
  # boot.rb, so boot.rb's own stdout-protection swap would happen too late
  # to catch initializer output — exactly the corruption
  # docs/design/docs/04-runtime-agent.md section 4 warns about. Instead
  # this spawns boot.rb as a plain Ruby process and passes
  # config/environment.rb as an explicit argument, so boot.rb requires it
  # itself, after protecting stdout first
  # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
  #
  # Intentionally synchronous — the caller is expected to run #start on a
  # background thread if it shouldn't block the LSP transport (see
  # core/bin/ovallsp), since a real Rails boot can take tens of seconds and
  # `docs/02-architecture.md` section 8 keeps the main thread reserved for
  # transport and state mutation.
  module RailsBootstrap
    BOOT_SCRIPT = File.expand_path("runtime_agent/boot.rb", __dir__)

    module_function

    def rails_app?(root)
      File.file?(File.join(root, "bin", "rails")) && File.file?(environment_file_for(root))
    end

    def environment_file_for(root)
      File.join(root, "config", "environment.rb")
    end

    # `command`/`args` are overridable so tests can point this at the
    # rails_minimal fixture instead of the real `bundle exec ruby boot.rb`
    # invocation this defaults to.
    #
    # `on_manager_created`, if given, is invoked synchronously with the
    # freshly-constructed AgentProcessManager the moment it exists --
    # *before* the blocking `manager.start` call below runs at all. #start
    # can block for real seconds (an actual Rails boot) to `hello_timeout`
    # seconds (an unresponsive one), and this module's own docs already
    # say the caller runs #start on a background thread for exactly that
    # reason -- without this hook, a Server wanting to cancel that
    # background thread (process shutdown, an RSpec example ending) has no
    # way to reach the manager until this method eventually returns.
    # Server uses it to register the manager with its own
    # BackgroundTasks#track_manager immediately, so #stop can be called on
    # it (terminating any already-spawned child process, or preventing one
    # from ever spawning) regardless of exactly how far the handshake
    # below has gotten.
    # `env_source:` (default: the real `ENV`) is the environment
    # BundleEnvironment.for_workspace reads Core's own Bundler/RubyGems
    # pollution *from* -- production code always leaves it as the
    # default; it exists so integration tests can simulate "what if
    # Core's own process had X polluted" by passing a plain Hash,
    # exercising this real method end-to-end without ever mutating global
    # ENV (see BundleEnvironment's own docs for why that matters).
    def start(root:, logger:, route_registry:, model_registry:, hello_timeout: 60, command: nil, args: nil,
              on_unavailable: nil, on_manager_created: nil, install_snapshot: nil, env_source: ENV)
      env = {}
      if command.nil?
        return nil unless rails_app?(root)

        command = "bundle"
        args = ["exec", "ruby", BOOT_SCRIPT, "start", environment_file_for(root)]
        # Core and the target Rails app are two entirely separate Bundle
        # graphs -- Core's own BUNDLE_GEMFILE/BUNDLE_PATH/BUNDLE_APP_CONFIG
        # (and RUBYOPT's "-rbundler/setup", RUBYLIB's Core-bundler-lib
        # entry) must never leak into this `bundle exec` and silently
        # point it at Core's own Gemfile/gem install instead of the
        # target app's own (docs/design/tasks/008.5-runtime-and-index-corrections.md
        # first found this for BUNDLE_GEMFILE alone; a review-bundle
        # script that runs Core's own test suite against a temporary,
        # isolated BUNDLE_PATH later found the same leak applied to
        # BUNDLE_PATH/BUNDLE_APP_CONFIG too, making the Runtime Agent
        # unable to resolve rails/sqlite3/activerecord from the target
        # app's own bundle install at all). See BundleEnvironment's own
        # docs for why `Bundler.unbundled_env` alone isn't enough here.
        env = Ovallsp::BundleEnvironment.for_workspace(root, env: env_source)
      end

      manager = AgentProcessManager.new(command: command, args: args, chdir: root, logger: logger,
                                         hello_timeout: hello_timeout, env: env, on_unavailable: on_unavailable)
      on_manager_created&.call(manager)
      status = manager.start

      if status == :ready
        populate_registries(
          manager, route_registry: route_registry, model_registry: model_registry, logger: logger,
          install_snapshot: install_snapshot
        )
      else
        logger.warn("Runtime Agent unavailable (#{status}); continuing in static-only mode")
      end

      manager
    end

    # Fetches routes (one flat list) and models (one bulk agent/models
    # request returning every model's full columns/associations in one
    # round trip, rather than a lightweight discovery list followed by one
    # agent/model request per model -- real Rails apps can have hundreds
    # of models, so N round trips was pure request/response overhead, not
    # actual work (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    # Runs on the caller's (background) thread, not the LSP transport
    # thread, and a failure here is logged and swallowed rather than
    # propagated, since static features must keep working either way.
    def populate_registries(manager, route_registry:, model_registry:, logger:, install_snapshot: nil)
      snapshot = manager.fetch_snapshot(sections: %w[routes])
      routes = snapshot && (snapshot[:routes] || [])
      unless snapshot
        logger.warn("failed to fetch routes snapshot from Runtime Agent; leaving route_registry as-is")
      end

      # `nil` (communication failure — timeout, degraded Agent) and `[]`
      # (the app genuinely has zero models) are different outcomes and
      # must not be conflated: `manager.fetch_all_models || []` used to
      # treat a failed fetch as "zero models" and wipe every previously
      # known model via #replace({}) — including ones from *before* this
      # populate call (e.g. a restart repopulating after a Gemfile.lock
      # fix, where the Agent answers routes fine but times out on the
      # heavier models fetch). Only a genuine (non-nil) response, empty or
      # not, is installed; a failed fetch leaves the last-known-good
      # models in place (docs/design/tasks/008.6-agent-and-index-hardening.md).
      #
      # Built up into a name-keyed Hash and installed in one #replace call
      # rather than incrementally, so a successful fetch's model table is
      # a full swap (a model discoverable in an earlier boot but absent
      # from this fetch doesn't linger) — the same generation-replace
      # semantics route_registry.replace already gives routes above.
      models = manager.fetch_all_models
      responses_by_name = nil
      if models
        responses_by_name = models.filter_map { |entry| entry[:name] && [entry[:name], entry] }.to_h
      else
        logger.warn("failed to fetch models from Runtime Agent; leaving model_registry as-is")
      end

      if install_snapshot
        install_snapshot.call(routes: routes, models: responses_by_name)
      else
        prepared_routes = route_registry.prepare_replace(routes) if routes
        prepared_models = model_registry.prepare_replace(responses_by_name) if responses_by_name
        route_registry.commit_replace(prepared_routes) if prepared_routes
        model_registry.commit_replace(prepared_models) if prepared_models
      end
    rescue StandardError => e
      logger.error("failed to populate Rails registries from Runtime Agent snapshot: #{e.class}: #{e.message}")
    end
  end
end
