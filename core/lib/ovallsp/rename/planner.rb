# frozen_string_literal: true

require_relative "plan"

module Ovallsp
  module Rename
    # Turns a resolved SymbolId into a Rename::Plan
    # (docs/design/tasks/016-guarded-rename-and-preview.md).
    #
    # Every edit location comes from exactly two places: WorkspaceIndex's
    # own declarations for `symbol_id` (the `def`/`class`/`@ivar =`
    # site(s)) and Semantic::ReferenceIndex's high-confidence-only
    # references for it (Task 014's #references defaults to
    # `minimum_confidence: :high` for exactly this reason -- a Union-
    # receiver call that only *might* be this method never gets edited).
    # Because both are keyed by SymbolId, an override of the same method
    # name on a *different* class has its own distinct SymbolId and is
    # never touched -- "override chain全体のrenameは初期版では明示選択また
    # は拒否する" is satisfied structurally, by construction, rather than
    # needing its own detection pass: there is no code path that could
    # ever reach a different symbol_id's locations in the first place.
    class Planner
      REFUSED_KINDS = %i[route_helper active_record_column active_record_association].freeze

      IDENTIFIER_PATTERNS = {
        local_variable: /\A[a-z_][a-zA-Z0-9_]*\z/,
        instance_method: /\A[a-z_][a-zA-Z0-9_]*[?!=]?\z/,
        singleton_method: /\A[a-z_][a-zA-Z0-9_]*[?!=]?\z/,
        ivar: /\A@[a-zA-Z_][a-zA-Z0-9_]*\z/,
        cvar: /\A@@[a-zA-Z_][a-zA-Z0-9_]*\z/,
        class: /\A[A-Z][a-zA-Z0-9_]*\z/,
        module: /\A[A-Z][a-zA-Z0-9_]*\z/,
        constant: /\A[A-Z][a-zA-Z0-9_]*\z/
      }.freeze

      def initialize(workspace_index:, reference_index:)
        @workspace_index = workspace_index
        @reference_index = reference_index
      end

      # LSP `textDocument/prepareRename`'s answer: is this symbol
      # renameable at all, and what should the editor pre-fill as the
      # placeholder? nil means "refuse to even start" (nothing found, or
      # a generated/DSL-origin symbol).
      def prepare(symbol_id)
        return nil unless symbol_id
        return nil if REFUSED_KINDS.include?(symbol_id.kind)
        return nil if locations_for(symbol_id).empty?

        { placeholder: simple_name(symbol_id) }
      end

      def plan(symbol_id, new_name:, generation:)
        return Plan.new(target: nil, generation: generation) unless symbol_id

        if REFUSED_KINDS.include?(symbol_id.kind)
          return refused_plan(symbol_id, generation,
                               "`#{simple_name(symbol_id)}` is a generated Rails method (#{symbol_id.kind}) -- " \
                               "rename its source declaration (the association/column, or the route) instead; " \
                               "the call sites are never edited directly here")
        end

        unless valid_identifier?(symbol_id.kind, new_name)
          return refused_plan(symbol_id, generation, "`#{new_name}` is not a valid #{symbol_id.kind} name")
        end

        conflicts = conflicts_for(symbol_id, new_name)
        return conflicted_plan(symbol_id, conflicts, generation) unless conflicts.empty?

        locations = locations_for(symbol_id)
        edits = locations.map { |(uri, range)| { uri: uri, range: range, new_text: new_name } }
        Plan.new(target: symbol_id, confirmed_edits: edits, generation: generation)
      end

      private

      def refused_plan(symbol_id, generation, warning)
        Plan.new(target: symbol_id, confirmed_edits: [], warnings: [warning], generation: generation)
      end

      def conflicted_plan(symbol_id, conflicts, generation)
        Plan.new(
          target: symbol_id, confirmed_edits: [], conflicts: conflicts,
          warnings: ["rename refused: #{conflicts.map { |c| c[:reason] }.join('; ')}"], generation: generation
        )
      end

      # `decl.name_location`, never `decl.location` -- the latter spans
      # the *whole* declaration (`class Foo\n...\nend`), which as an edit
      # range would replace an entire class/method body with just the
      # new name instead of renaming the identifier.
      def locations_for(symbol_id)
        decl_locations = @workspace_index.declarations_with_uri(symbol_id)
                                          .filter_map { |(uri, decl)| [uri, decl.name_location] if decl.name_location }
        ref_locations = @reference_index.references(symbol_id, minimum_confidence: :high).map { |r| [r.uri, r.location] }
        (decl_locations + ref_locations).uniq
      end

      def simple_name(symbol_id)
        symbol_id.name.to_s.split("::").last
      end

      def valid_identifier?(kind, name)
        pattern = IDENTIFIER_PATTERNS[kind]
        return true unless pattern

        !!pattern.match?(name.to_s)
      end

      # Constant/class/module: does a type by the renamed fully-qualified
      # name already exist? Method: does the owner already declare a
      # method by that name? Everything else (local variables, ivars,
      # cvars) has no cross-symbol collision to check -- a local's own
      # scope id already keeps it from ever being confused with another
      # scope's same-named local (Task 014), and Ruby itself allows
      # redefining/reassigning an ivar/cvar freely.
      def conflicts_for(symbol_id, new_name)
        case symbol_id.kind
        when :class, :module, :constant
          constant_conflicts(symbol_id, new_name)
        when :instance_method, :singleton_method
          method_conflicts(symbol_id, new_name)
        else
          []
        end
      end

      def constant_conflicts(symbol_id, new_name)
        namespace = symbol_id.name.to_s.sub(/[^:]+\z/, "")
        candidate_full_name = "#{namespace}#{new_name}"
        return [] unless @workspace_index.resolve_type_name(candidate_full_name) == candidate_full_name

        [{ reason: "a type named `#{candidate_full_name}` already exists" }]
      end

      def method_conflicts(symbol_id, new_name)
        existing = @workspace_index.method_symbol_ids(symbol_id.owner, kind: symbol_id.kind)
                                    .any? { |sid| sid.name == new_name }
        return [] unless existing

        [{ reason: "`#{symbol_id.owner}##{new_name}` is already declared" }]
      end
    end
  end
end
