# frozen_string_literal: true

require_relative "../index/symbol_id"

module Ovallsp
  module Semantic
    # Aggregates Index::GeneratedMethodFact values across every indexed
    # file, keyed by SymbolId -- the same per-file replace/remove,
    # mutex-guarded, generation-bumping pattern WorkspaceIndex/
    # HierarchyIndex/ReferenceIndex already use throughout this codebase
    # (docs/design/tasks/017-rails-dsl-expansion.md).
    class GeneratedMethodIndex
      def initialize
        @mutex = Mutex.new
        @by_uri = {}
        @by_symbol = {}
        @generation = 0
      end

      def generation
        @mutex.synchronize { @generation }
      end

      def replace_file(uri:, facts:)
        @mutex.synchronize do
          remove_file_locked(uri)
          @by_uri[uri] = facts
          facts.each { |fact| (@by_symbol[symbol_id_for(fact)] ||= []) << [uri, fact] }
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

      def fact_for(symbol_id)
        @mutex.synchronize { @by_symbol.fetch(symbol_id, nil)&.last&.last }
      end

      private

      def symbol_id_for(fact)
        Index::SymbolId.new(kind: fact.kind, owner: fact.owner, name: fact.name, discriminator: nil)
      end

      def remove_file_locked(uri)
        previous = @by_uri.delete(uri)
        return false unless previous

        previous.each do |fact|
          symbol_id = symbol_id_for(fact)
          entries = @by_symbol[symbol_id]
          next unless entries

          entries.reject! { |entry_uri, _entry_fact| entry_uri == uri }
          @by_symbol.delete(symbol_id) if entries.empty?
        end
        true
      end
    end
  end
end
