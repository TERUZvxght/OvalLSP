# frozen_string_literal: true

require_relative "observed_signature"

module Ovallsp
  module Observation
    # Aggregates a workspace's observed runtime evidence, one
    # ObservedSignature per SymbolId. Mutex-guarded, generation-bumping,
    # same single-writer contract as WorkspaceIndex/HierarchyIndex/etc.
    # throughout this codebase.
    #
    # Authority policy (docs/design/tasks/019-runtime-observation.md
    # "observation authorityはsource/RBS/Rails deterministic factsより
    #低くする"): Store itself has no opinion about *how* a caller weighs
    # this evidence against static ones -- it only ever hands back
    # ObservedSignature values, tagged with their own `samples` count, and
    # it is the caller's (Diagnostics::Engine/LocalInferencer's) job to
    # treat this as strictly lower-authority, supplementary evidence, and
    # never let it override an explicit RBS signature.
    #
    # A run *replaces* the previous one wholesale, the same "no partial
    # merge across generations" policy every other per-file/per-run index
    # in this codebase already uses (WorkspaceIndex#replace_file,
    # HierarchyIndex#replace_file, ...) -- an ever-accumulating union of
    # observed types across many stale runs would only ever grow wider
    # and staler, never actually reflect the current codebase.
    class Store
      def initialize
        @mutex = Mutex.new
        @by_symbol = {}
        @generation = 0
      end

      def generation
        @mutex.synchronize { @generation }
      end

      # `run` is an Array of ObservedSignature -- replaces every
      # previously-stored signature wholesale (not merged with the prior
      # run), matching one call to the observation runner.
      #
      # A non-Array is rejected loudly rather than tolerated, because the
      # one value a caller is realistically going to pass by mistake --
      # Observation::Runner#run's `nil`, its "this run produced no
      # outcome at all" sentinel -- would otherwise be *silently
      # destructive* rather than an error: `nil.to_h { ... }` is a
      # perfectly legal `{}` in Ruby, so `replace_run(nil)` would quietly
      # empty the store and bump the generation, which is precisely the
      # damage round 7's Server-side nil guard exists to prevent. Keeping
      # that invariant only at the single call site leaves the store's own
      # contract unenforced and this class of bug one new caller away
      # (found by an independent review, round 8).
      def replace_run(run)
        unless run.is_a?(Array)
          raise ArgumentError, "replace_run expects an Array of ObservedSignature, got #{run.class}"
        end

        @mutex.synchronize do
          @by_symbol = run.to_h { |signature| [signature.symbol_id, signature] }
          @generation += 1
        end
      end

      def evidence_for(symbol_id)
        @mutex.synchronize { @by_symbol[symbol_id] }
      end

      # Every symbol_id this Store currently holds evidence for -- what a
      # caller needs to enumerate before building the `current_fingerprints`
      # map #invalidate_changed expects (a symbol_id this map doesn't
      # mention at all is treated as "gone", so a caller must include
      # every symbol_id being asked about, not just ones from whichever
      # single file just changed).
      def tracked_symbol_ids
        @mutex.synchronize { @by_symbol.keys }
      end

      # Drops any stored signature whose `code_fingerprint` no longer
      # matches `current_fingerprints[symbol_id]` (the method's live
      # Declaration#body_source digest) -- "code fingerprint変更時に古い
      # 観測をstale化する" / "source変更後に古い観測を使用しない". A
      # symbol_id absent from `current_fingerprints` entirely (the
      # method itself was deleted) is dropped too, for the same reason:
      # its stored evidence no longer describes anything real.
      def invalidate_changed(current_fingerprints)
        @mutex.synchronize do
          before = @by_symbol.size
          @by_symbol.select! do |symbol_id, signature|
            current_fingerprints[symbol_id] == signature.code_fingerprint
          end
          @generation += 1 if @by_symbol.size != before
        end
      end

      def clear
        @mutex.synchronize do
          changed = !@by_symbol.empty?
          @by_symbol = {}
          @generation += 1 if changed
        end
      end
    end
  end
end
