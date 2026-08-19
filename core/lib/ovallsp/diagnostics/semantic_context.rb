# frozen_string_literal: true

module Ovallsp
  module Diagnostics
    # Everything Engine#analyze needs to resolve candidates against the
    # workspace, bundled into one value so the required interface's
    # `semantic_context:` parameter is a single object rather than a
    # sprawling keyword list -- the same reason Semantic::QueryService's
    # constructor bundles its own dependencies (docs/design/tasks/015-confidence-aware-diagnostics.md).
    # Every field except `workspace_index`/`hierarchy_index`/`method_resolver`/
    # `local_inferencer` is optional and nil-safe: a caller with no Rails
    # Runtime Agent connected, or no RBS environment loaded, still gets
    # every check that doesn't depend on it.
    SemanticContext = Data.define(
      :workspace_index, :hierarchy_index, :method_resolver, :local_inferencer, :model_registry, :route_registry,
      :signatures, :generation, :ancestry_registry, :assigned_ivars
    ) do
      # `assigned_ivars` is the set of instance variable names this
      # document is known to receive, or nil for "nobody worked it out"
      # (0.2.0). The distinction is the whole safety of the check that
      # reads it: an empty set means an action that assigns nothing, and
      # nil means there is no action -- and reporting every `@ivar` in a
      # file for which no context could be established is the failure mode
      # this must not have. nil is therefore the default.
      REQUIRED = %i[workspace_index hierarchy_index method_resolver local_inferencer].freeze

      def initialize(model_registry: nil, route_registry: nil, signatures: nil, generation: nil,
                     ancestry_registry: nil, assigned_ivars: nil, **rest)
        # A context missing one of these cannot answer the questions
        # `Engine` asks of it, so every reader that touched one carried a
        # `return unless` -- and 0.2.9 wrote the same one twice in a row
        # in `#closed_nominal?`, which is what a guard repeated at each
        # caller invites. Refused here instead, for the same reason
        # `Cache::Store` performs every removal in one place: containment
        # is not an emergent property of all the callers being right.
        missing = REQUIRED.select { |field| rest[field].nil? }
        raise ArgumentError, "a semantic context needs #{missing.join(', ')}" unless missing.empty?

        super(model_registry: model_registry, route_registry: route_registry, signatures: signatures,
              generation: generation, ancestry_registry: ancestry_registry, assigned_ivars: assigned_ivars, **rest)
      end
    end
  end
end
