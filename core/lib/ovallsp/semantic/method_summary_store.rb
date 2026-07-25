# frozen_string_literal: true

require "set"

module Ovallsp
  module Semantic
    # A cached summary of one method's inferred return type.
    #
    # - parameter_types: {name (String) => Types value}, currently always
    #   Types::UNKNOWN for every parameter (Task 010's explicit MVP scope
    #   — "初期版ではparameter型がUnknownでもよい") but kept as a real Hash
    #   keyed by parameter name so call-site-informed narrowing can fill
    #   it in later without changing this shape.
    # - return_type: the inferred return type (implicit last expression,
    #   unioned with every explicit `return`'s value across every reachable
    #   exit path).
    # - effects: reserved for future interprocedural effect tracking
    #   (raises, mutation, ...); always [] for now — "interprocedural
    #   effect analysis completeness" is explicitly out of scope, but the
    #   field exists so a later task doesn't need to change this shape.
    # - dependencies: SymbolIds of every method this summary's computation
    #   called into to determine the return type — what
    #   MethodSummaryStore#invalidate walks to find dependents.
    # - confidence: :high (the return type came from direct, unambiguous
    #   evidence) or :low (some part of the computation degraded — an
    #   unresolved call, a widened recursion, multiple differently-shaped
    #   declarations for the same symbol with no RBS to disambiguate, ...).
    # - generation: MethodSummaryStore#generation at the moment this
    #   summary was computed and stored.
    # - status: :complete, :partial (some declarations couldn't be
    #   analyzed at all), :timeout (the analysis budget ran out), or
    #   :recursive_widened (direct or mutual recursion was cut off).
    MethodSummary = Data.define(:symbol_id, :parameter_types, :return_type, :effects, :dependencies, :confidence,
                                 :generation, :status)

    # Caches MethodSummary by SymbolId and tracks a reverse dependency
    # graph (who calls whom) so invalidating one method's summary also
    # invalidates every summary that was computed *using* it — the same
    # generation-bumping, mutex-guarded aggregation pattern WorkspaceIndex/
    # Semantic::HierarchyIndex already use
    # (docs/design/tasks/010-method-summaries-and-call-chains.md).
    class MethodSummaryStore
      def initialize
        @mutex = Mutex.new
        @summaries = {}
        # Reverse edges: dependency SymbolId -> Set of SymbolIds whose last
        # computed summary depended on it. Forward edges (a summary's own
        # `dependencies`) live on the MethodSummary itself; this is only
        # ever used to walk "what needs to be invalidated".
        @dependents = Hash.new { |h, k| h[k] = Set.new }
        @generation = 0
      end

      def generation
        @mutex.synchronize { @generation }
      end

      def fetch(symbol_id)
        @mutex.synchronize { @summaries[symbol_id] }
      end

      # Installs `summary`, replacing any prior summary (and its reverse
      # dependency edges) for the same symbol_id.
      def replace(summary)
        @mutex.synchronize do
          remove_edges_locked(summary.symbol_id)
          summary.dependencies.each { |dep| @dependents[dep] << summary.symbol_id }
          @summaries[summary.symbol_id] = summary
          @generation += 1
        end
      end

      # Removes the cached summary for every id in `symbol_ids`, and
      # transitively for everything that (directly or indirectly)
      # depended on any of them — `A#foo` calling `B#bar` means a change
      # to `B#bar` must invalidate `A#foo` too, however many calls deep.
      # Returns the full set actually removed (useful for logging/tests;
      # includes ids that were never cached, harmlessly).
      def invalidate(symbol_ids)
        @mutex.synchronize do
          to_remove = Set.new
          queue = Array(symbol_ids).dup
          until queue.empty?
            id = queue.shift
            next if to_remove.include?(id)

            to_remove << id
            queue.concat(@dependents.fetch(id, []).to_a)
          end

          # Only actually-cached ids count toward "something changed" —
          # #invalidate is routinely called with symbol_ids that were
          # never summarized in the first place (e.g. Server invalidating
          # every method whose file changed, most of which nothing ever
          # queried yet), and that must stay a true no-op rather than
          # bumping generation for nothing.
          actually_cached = to_remove.select { |id| @summaries.key?(id) }
          actually_cached.each { |id| remove_edges_locked(id); @summaries.delete(id) }
          @generation += 1 unless actually_cached.empty?
          to_remove
        end
      end

      private

      def remove_edges_locked(symbol_id)
        summary = @summaries[symbol_id]
        return unless summary

        summary.dependencies.each { |dep| @dependents[dep]&.delete(symbol_id) }
      end
    end
  end
end
