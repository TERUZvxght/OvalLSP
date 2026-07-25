# frozen_string_literal: true

require_relative "../index/reference"

module Rslsp
  module Semantic
    # Aggregates resolved Index::Reference values across every indexed
    # file, keyed by SymbolId — the same role WorkspaceIndex plays for
    # declarations, HierarchyIndex for ancestor facts
    # (docs/design/tasks/014-reference-index-and-find-references.md
    # required interface). Deliberately holds only already-*resolved*
    # References (Semantic::ReferenceResolver's output), never raw
    # Index::ReferenceCandidate values -- resolution needs the whole
    # workspace's declarations, which this class has no reason to know
    # about itself.
    #
    # Mutation is single-writer, mutex-guarded, generation-bumping --
    # the same aggregation pattern WorkspaceIndex/HierarchyIndex/
    # Signatures::Environment already use throughout this codebase.
    class ReferenceIndex
      def initialize
        @mutex = Mutex.new
        @by_uri = {}
        @by_symbol = Hash.new { |h, k| h[k] = [] }
        @generation = 0
      end

      def generation
        @mutex.synchronize { @generation }
      end

      # Full swap of `uri`'s contribution -- a reference that disappeared
      # in a new version of the file (code deleted, a call rewritten)
      # doesn't linger, matching every other per-file index's replace
      # contract in this codebase.
      def replace_file(uri:, references:)
        @mutex.synchronize do
          remove_file_locked(uri)
          @by_uri[uri] = references
          references.each { |reference| @by_symbol[reference.symbol_id] << [uri, reference] }
          @generation += 1
        end
      end

      def remove_file(uri)
        @mutex.synchronize do
          removed = remove_file_locked(uri)
          @generation += 1 if removed
          removed
        end
      end

      # Every Reference resolved to `symbol_id` whose confidence meets
      # `minimum_confidence:` (`:low` accepts both `:low` and `:high`;
      # `:high` accepts only `:high`) -- "ambiguous callを確定参照として
      # 扱わない" is enforced here, at query time, not by dropping
      # low-confidence references at resolve time (a caller building a
      # Rename preview, unlike plain Find References, may want to see them).
      # `limit:` truncates for a large result set ("大量結果でpartial...が
      # 機能する").
      def references(symbol_id, minimum_confidence: :high, limit: nil)
        @mutex.synchronize do
          matches = @by_symbol.fetch(symbol_id, []).filter_map { |(_uri, r)| r if meets?(r.confidence, minimum_confidence) }
          limit ? matches.first(limit) : matches
        end
      end

      private

      def meets?(confidence, minimum)
        minimum == :low || confidence == :high
      end

      # Entries are `[uri, reference]` pairs, not bare References, so two
      # structurally-identical References from *different* files (a
      # realistic case -- the same call shape written the same way in two
      # files) are never confused with each other during removal, the
      # same way WorkspaceIndex#remove_file_locked distinguishes same-
      # SymbolId Declarations by uri rather than by value equality.
      def remove_file_locked(uri)
        previous = @by_uri.delete(uri)
        return false unless previous

        previous.each do |reference|
          entries = @by_symbol[reference.symbol_id]
          next unless entries

          entries.reject! { |(entry_uri, _ref)| entry_uri == uri }
          @by_symbol.delete(reference.symbol_id) if entries.empty?
        end
        true
      end
    end
  end
end
