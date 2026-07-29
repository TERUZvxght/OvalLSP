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
      :signatures, :generation, :ancestry_registry
    ) do
      def initialize(model_registry: nil, route_registry: nil, signatures: nil, generation: nil,
                     ancestry_registry: nil, **rest)
        super(model_registry: model_registry, route_registry: route_registry, signatures: signatures,
              generation: generation, ancestry_registry: ancestry_registry, **rest)
      end
    end
  end
end
