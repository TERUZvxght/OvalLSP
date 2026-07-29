# frozen_string_literal: true

require "set"

module Ovallsp
  module Semantic
    # One entry in a resolved ancestor chain.
    #
    # - name: the ancestor type's canonical (fully-qualified where known)
    #   name — raw/as-written if it couldn't be resolved against the
    #   workspace (an external gem class, a Ruby built-in, a genuinely
    #   unresolved constant).
    # - kind: :class or :module if known, nil if the name couldn't be
    #   resolved to a declared type at all.
    # - origin: how this ancestor entered the chain *at this exact
    #   position* — :self (the type actually queried, or one reached via
    #   inheritance/include/prepend/extend that is itself being listed),
    #   :prepend, :include, :extend, :superclass, or :default (the
    #   implicit Object/Kernel/BasicObject root every class ultimately
    #   has).
    # - location: the LSP range of the statement that introduced this
    #   ancestor (the `include Foo` call, the `< Foo` superclass clause),
    #   or nil for the implicit default root.
    AncestorEntry = Data.define(:name, :kind, :origin, :location)

    # Aggregates AncestorFact/AliasFact (Task 009, extracted by
    # ParserService's Visitor) across every indexed file and answers
    # ordered ancestor-chain queries, the same role WorkspaceIndex plays
    # for declarations. Kept as a separate class specifically so
    # "building the hierarchy" and "querying methods against it"
    # (Semantic::MethodResolver) stay decoupled
    # (docs/design/tasks/009-method-hierarchy-and-lookup.md).
    #
    # Name resolution (raw source name -> canonical declared type) is
    # delegated to WorkspaceIndex#resolve_type_name/#type_kind — real
    # (lexical-scope-aware) Ruby constant resolution is out of scope; an
    # unresolved target simply degrades to a partial ancestor chain
    # (the last acceptance criterion) rather than raising.
    #
    # Mutation is single-writer and every method synchronizes on one
    # mutex, mirroring WorkspaceIndex's own concurrency contract.
    class HierarchyIndex
      DEFAULT_OBJECT_CHAIN = [
        AncestorEntry.new(name: "Object", kind: :class, origin: :default, location: nil),
        AncestorEntry.new(name: "Kernel", kind: :module, origin: :default, location: nil),
        AncestorEntry.new(name: "BasicObject", kind: :class, origin: :default, location: nil)
      ].freeze
      private_constant :DEFAULT_OBJECT_CHAIN

      # A class explicitly writing `< Object` (redundant, but legal) is
      # recognized directly rather than recursed into, since Object is a
      # Ruby built-in essentially never declared in the workspace itself
      # — recursing into it would just resolve to nothing and silently
      # drop Kernel/BasicObject, unlike the *implicit* (no `< Superclass`
      # at all) case, which already appends #DEFAULT_OBJECT_CHAIN.
      ROOT_SUPERCLASS_NAMES = %w[Object ::Object].freeze
      private_constant :ROOT_SUPERCLASS_NAMES

      def initialize(workspace_index:)
        @workspace_index = workspace_index
        @mutex = Mutex.new
        @facts_by_uri = {}
        @superclass_by_owner = {}
        @prepends_by_owner = Hash.new { |h, k| h[k] = [] }
        @includes_by_owner = Hash.new { |h, k| h[k] = [] }
        @extends_by_owner = Hash.new { |h, k| h[k] = [] }
        @aliases_by_owner = Hash.new { |h, k| h[k] = [] }
        @generation = 0
      end

      def generation
        @mutex.synchronize { @generation }
      end

      # Adds or replaces one file's contribution. Always a full swap for
      # that uri (remove-then-add), so ancestor/alias facts that
      # disappeared in a new version of the file (an `include` deleted,
      # a superclass changed) don't linger — the same generation-replace
      # contract WorkspaceIndex#replace_file gives declarations. Bumps
      # #generation unconditionally on every call (facts have no
      # staleness/version concept of their own; the caller — Server — is
      # expected to call this only when WorkspaceIndex#replace_file for
      # the same summary actually applied).
      def replace_file(summary)
        @mutex.synchronize do
          remove_file_locked(summary.uri)
          @facts_by_uri[summary.uri] = { ancestor: summary.ancestor_facts, alias: summary.alias_facts }
          summary.ancestor_facts.each { |fact| add_fact_locked(fact) }
          summary.alias_facts.each { |fact| @aliases_by_owner[fact.owner] << fact }
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

      # The ordered ancestor chain for `type_name` (as written — resolved
      # against the workspace internally), matching real Ruby's own
      # `ancestors`/singleton-class-ancestors ordering: prepended modules
      # (most recently prepended first), the type itself, included
      # modules (most recently included first), then the superclass
      # chain recursively — or, for `singleton: true`, the type's own
      # singleton "self" entry, extended modules (most recently extended
      # first), then the superclass's singleton chain.
      def ancestors(type_name, singleton: false)
        @mutex.synchronize { compute_ancestors_locked(type_name, singleton: singleton, visited: Set.new) }
      end

      # Every `alias`/`alias_method` fact recorded directly inside
      # `type_name`'s own body (not inherited — Ruby aliases are resolved
      # against whatever `old_name` means *at definition time* in that
      # exact class/module, not looked up again through the ancestor
      # chain at call time).
      def aliases(type_name)
        canonical = @workspace_index.resolve_type_name(type_name) || type_name
        @mutex.synchronize { @aliases_by_owner.fetch(canonical, []).dup }
      end

      private

      def remove_file_locked(uri)
        facts = @facts_by_uri.delete(uri)
        return false unless facts

        facts[:ancestor].each { |fact| remove_fact_locked(fact) }
        facts[:alias].each { |fact| @aliases_by_owner[fact.owner]&.delete(fact) }
        true
      end

      def add_fact_locked(fact)
        case fact.relation
        when :superclass then @superclass_by_owner[fact.owner] = fact
        when :prepend then @prepends_by_owner[fact.owner] << fact
        when :include then @includes_by_owner[fact.owner] << fact
        when :extend then @extends_by_owner[fact.owner] << fact
        end
      end

      def remove_fact_locked(fact)
        case fact.relation
        when :superclass
          @superclass_by_owner.delete(fact.owner) if @superclass_by_owner[fact.owner] == fact
        when :prepend then @prepends_by_owner[fact.owner]&.delete(fact)
        when :include then @includes_by_owner[fact.owner]&.delete(fact)
        when :extend then @extends_by_owner[fact.owner]&.delete(fact)
        end
      end

      def compute_ancestors_locked(type_name, singleton:, visited:, origin_for_self: :self)
        canonical = @workspace_index.resolve_type_name(type_name) || type_name.to_s
        return [] if visited.include?([canonical, singleton])

        visited << [canonical, singleton]
        singleton ? singleton_ancestors_locked(canonical, visited, origin_for_self) : instance_ancestors_locked(canonical, visited, origin_for_self)
      end

      def instance_ancestors_locked(canonical, visited, origin_for_self)
        entries = []
        @prepends_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }

        entries << AncestorEntry.new(name: canonical, kind: kind_of(canonical), origin: origin_for_self, location: nil)

        @includes_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }

        superclass_fact = @superclass_by_owner[canonical]
        if superclass_fact && superclass_fact.target.nil?
          # `class Foo < <expression>`: the class has a parent whose name
          # we cannot resolve, so its method set is unbounded. Recorded as
          # a nameless, kindless ancestor rather than omitted, because
          # omitting it makes the class look parentless and therefore
          # fully known -- which is what made every Rails migration report
          # its own DSL calls as undefined methods.
          entries << AncestorEntry.new(name: nil, kind: nil, origin: :superclass, location: nil)
        elsif superclass_fact && ROOT_SUPERCLASS_NAMES.include?(superclass_fact.target)
          entries.concat(DEFAULT_OBJECT_CHAIN)
        elsif superclass_fact
          entries.concat(
            compute_ancestors_locked(superclass_fact.target, singleton: false, visited: visited, origin_for_self: :superclass)
          )
        elsif kind_of(canonical) == :class
          entries.concat(DEFAULT_OBJECT_CHAIN)
        end

        entries
      end

      def singleton_ancestors_locked(canonical, visited, origin_for_self)
        entries = [AncestorEntry.new(name: canonical, kind: kind_of(canonical), origin: origin_for_self, location: nil)]

        @extends_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }

        superclass_fact = @superclass_by_owner[canonical]
        if superclass_fact && superclass_fact.target.nil?
          entries << AncestorEntry.new(name: nil, kind: nil, origin: :superclass, location: nil)
        elsif superclass_fact && !ROOT_SUPERCLASS_NAMES.include?(superclass_fact.target)
          entries.concat(
            compute_ancestors_locked(superclass_fact.target, singleton: true, visited: visited, origin_for_self: :superclass)
          )
        end

        entries
      end

      # Shared by prepend/include (their target's own *instance* side —
      # a module's methods, plus whatever it in turn includes) and extend
      # (same: `extend M` puts M's instance methods on the singleton
      # chain, so the extended module's instance-side ancestors are what
      # belongs here too, not its own singleton side).
      def ancestor_entries_for(fact, visited)
        compute_ancestors_locked(fact.target, singleton: false, visited: visited, origin_for_self: fact.relation)
      end

      def kind_of(canonical)
        @workspace_index.type_kind(canonical)
      end
    end
  end
end
