# frozen_string_literal: true

require_relative "agent_process_manager"

module Rslsp
  # Detects a Rails app at the workspace root and, if one is found, spawns
  # the Runtime Agent and populates a RouteRegistry/ModelRegistry from its
  # snapshot — the wiring `core/bin/rslsp` needs so route completion and
  # Active Record type inference actually work when the Core Server runs
  # for real, not just inside tests that construct AgentProcessManager
  # directly (docs/design/docs/04-runtime-agent.md section 2's recommended
  # `bundle exec bin/rails runner ... boot.rb start` invocation).
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
      File.file?(File.join(root, "bin", "rails"))
    end

    # `command`/`args` are overridable so tests can point this at the
    # rails_minimal fixture (which has no real `bin/rails`) instead of the
    # real `bundle exec bin/rails runner` invocation this defaults to.
    def start(root:, logger:, route_registry:, model_registry:, hello_timeout: 60, command: nil, args: nil)
      if command.nil?
        return nil unless rails_app?(root)

        command = "bundle"
        args = ["exec", File.join(root, "bin", "rails"), "runner", BOOT_SCRIPT, "start"]
      end

      manager = AgentProcessManager.new(command: command, args: args, chdir: root, logger: logger,
                                         hello_timeout: hello_timeout)
      status = manager.start

      if status == :ready
        populate_registries(manager, route_registry: route_registry, model_registry: model_registry, logger: logger)
      else
        logger.warn("Runtime Agent unavailable (#{status}); continuing in static-only mode")
      end

      manager
    end

    # Fetches routes eagerly (there's one flat list, and Core needs all of
    # it for completion) and models in two passes: a lightweight discovery
    # list, then one agent/model request per discovered model. Real Rails
    # apps can have hundreds of models, so this can be slow — it runs on
    # the caller's (background) thread, not the LSP transport thread, and
    # a failure here is logged and swallowed rather than propagated, since
    # static features must keep working either way.
    def populate_registries(manager, route_registry:, model_registry:, logger:)
      snapshot = manager.fetch_snapshot(sections: %w[routes models])
      return unless snapshot

      route_registry.replace(snapshot[:routes] || [])

      (snapshot[:models] || []).each do |entry|
        name = entry[:name]
        next unless name

        response = manager.fetch_model(name: name)
        next unless response && !response[:error]

        model_registry.register_from_agent_response(name, response)
      end
    rescue StandardError => e
      logger.error("failed to populate Rails registries from Runtime Agent snapshot: #{e.class}: #{e.message}")
    end
  end
end
