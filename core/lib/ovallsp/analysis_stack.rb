# frozen_string_literal: true

module Ovallsp
  # **The one place the analysis collaborators are wired together.**
  #
  # Every one of them reads the others, and which ones a given object was
  # handed decides what the engine can answer. Assembling that graph in
  # more than one place means running more than one program, and this
  # project has now measured a fix against the wrong one twice:
  #
  # - `024.103` (0.2.10) came out byte-identical on both sides of a
  #   6,772-finding comparison, because `LocalInferencer` in
  #   `scripts/corpus_diagnostics.rb` had no `workspace_index:`.
  # - `024.112` (0.2.11) repeated it exactly, in the same script, whose
  #   own comment by then read "keep every constructor here matching
  #   `Server#initialize`". A comment asking a reader to keep two lists in
  #   step is the arrangement that failed both times.
  #
  # The specs had it worse and more quietly: twenty-eight of them built
  # their own, and most were missing `signatures:`, `hierarchy_index:` or
  # `generated_method_index:` -- so an example could pass while the
  # server, holding a fuller graph, answered differently. That is
  # `024.109`'s category arriving through the wiring rather than through a
  # fixture.
  #
  # `core/spec/meta/analysis_stack_spec.rb` fails if anything outside this
  # file constructs one of these collaborators. A harness cannot be a
  # subset of the server if it does not assemble anything, and a
  # collaborator added here reaches every consumer in the same edit.
  AnalysisStack = Data.define(
    :workspace_index, :hierarchy_index, :method_resolver, :method_analyzer,
    :method_summary_store, :generated_method_index, :local_inferencer,
    :observation_store, :signatures, :model_registry
  ) do
    # `signatures` is required rather than defaulted: loading an RBS
    # environment is the one expensive step here, the server loads it its
    # own way, and a default would let a caller build a stack that quietly
    # knows no stdlib -- which is a different program again.
    def self.build(signatures:,
                   workspace_index: WorkspaceIndex.new,
                   model_registry: Models::ModelRegistry.new,
                   observation_store: Observation::Store.new,
                   method_summary_store: Semantic::MethodSummaryStore.new,
                   generated_method_index: Semantic::GeneratedMethodIndex.new,
                   gem_index: Semantic::GemIndex.empty,
                   max_steps: nil)
      hierarchy_index = Semantic::HierarchyIndex.new(workspace_index: workspace_index, gem_index: gem_index)
      method_resolver = Semantic::MethodResolver.new(workspace_index: workspace_index,
                                                    hierarchy_index: hierarchy_index,
                                                    gem_index: gem_index)
      # `method_resolver`/`method_analyzer` let a plain (non-Active-Record)
      # method call chain keep resolving past its first hop instead of
      # widening to Unknown immediately -- see
      # `LocalInferencer#resolve_source_method_member`
      # (`docs/design/tasks/010-method-summaries-and-call-chains.md`; wired
      # in as part of Task 013 after an independent review found Task 010
      # had shipped as a fully isolated, never-called engine).
      method_analyzer = Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: method_summary_store, model_registry: model_registry,
        generated_method_index: generated_method_index
      )
      # `max_steps` is passed only when a caller names one, so the
      # inferencer's own default stays the single source of it.
      local_inferencer = LocalInferencer.new(
        **{ model_registry: model_registry, method_resolver: method_resolver,
            method_analyzer: method_analyzer, signatures: signatures,
            observation_store: observation_store, workspace_index: workspace_index,
            hierarchy_index: hierarchy_index }.merge(max_steps ? { max_steps: max_steps } : {})
      )

      new(workspace_index: workspace_index, hierarchy_index: hierarchy_index,
          method_resolver: method_resolver, method_analyzer: method_analyzer,
          method_summary_store: method_summary_store,
          generated_method_index: generated_method_index,
          local_inferencer: local_inferencer, observation_store: observation_store,
          signatures: signatures, model_registry: model_registry)
    end

    # The context the diagnostics engine reads. Built here for the same
    # reason the rest is: it names eight of these collaborators, and a
    # caller assembling it by hand can omit one.
    def semantic_context(route_registry:, generation: 1, ancestry_registry: nil, **rest)
      Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index,
        method_resolver: method_resolver, local_inferencer: local_inferencer,
        model_registry: model_registry, route_registry: route_registry,
        signatures: signatures, generation: generation,
        ancestry_registry: ancestry_registry || Runtime::AncestryRegistry.new,
        **rest
      )
    end

    # Every per-file store that has to be told about a parsed file, so a
    # caller cannot update one and forget another. `024.62` is about two
    # of these being separated by nothing but their payload; until that is
    # settled, this is where the pair is kept in step.
    def replace_file(summary)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
    end

    def remove_file(uri)
      workspace_index.remove_file(uri)
      hierarchy_index.remove_file(uri)
    end
  end
end
