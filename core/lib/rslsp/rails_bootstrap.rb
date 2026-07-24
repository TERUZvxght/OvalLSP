# frozen_string_literal: true

require_relative "agent_process_manager"

module Rslsp
  # Detects a Rails app at the workspace root and, if one is found, spawns
  # the Runtime Agent and populates a RouteRegistry/ModelRegistry from its
  # snapshot — the wiring `core/bin/rslsp` needs so route completion and
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
  # core/bin/rslsp), since a real Rails boot can take tens of seconds and
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
    def start(root:, logger:, route_registry:, model_registry:, hello_timeout: 60, command: nil, args: nil)
      env = {}
      if command.nil?
        return nil unless rails_app?(root)

        command = "bundle"
        args = ["exec", "ruby", BOOT_SCRIPT, "start", environment_file_for(root)]
        # If Core Server's own process was itself launched via `bundle
        # exec` (its normal invocation, being a Ruby gem), BUNDLE_GEMFILE
        # is already set in this process' environment and would
        # otherwise be inherited verbatim by the child -- silently
        # pointing `bundle exec` at *Core's* Gemfile instead of the
        # target Rails app's own one, since the target's own
        # config/boot.rb sets BUNDLE_GEMFILE with `||=` and never
        # overrides an inherited value
        # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
        # `nil` here tells Process.spawn to unset the var for the child
        # rather than merely not setting a new one.
        env = { "BUNDLE_GEMFILE" => nil }
      end

      manager = AgentProcessManager.new(command: command, args: args, chdir: root, logger: logger,
                                         hello_timeout: hello_timeout, env: env)
      status = manager.start

      if status == :ready
        populate_registries(manager, route_registry: route_registry, model_registry: model_registry, logger: logger)
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
    def populate_registries(manager, route_registry:, model_registry:, logger:)
      snapshot = manager.fetch_snapshot(sections: %w[routes])
      if snapshot
        route_registry.replace(snapshot[:routes] || [])
      else
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
      if models
        responses_by_name = models.filter_map { |entry| entry[:name] && [entry[:name], entry] }.to_h
        model_registry.replace(responses_by_name)
      else
        logger.warn("failed to fetch models from Runtime Agent; leaving model_registry as-is")
      end
    rescue StandardError => e
      logger.error("failed to populate Rails registries from Runtime Agent snapshot: #{e.class}: #{e.message}")
    end
  end
end
