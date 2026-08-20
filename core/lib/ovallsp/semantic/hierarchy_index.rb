# frozen_string_literal: true

require "set"
require_relative "../index/type_name_resolution"

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
    #   :prepend, :include, :extend, :superclass, :default (the implicit
    #   Object/Kernel/BasicObject root every class ultimately has), or
    #   :class_object (the Class/Module/Object/Kernel/BasicObject tail a
    #   *singleton* chain ends in, because the class object is an instance
    #   of them -- see #declaration_kind, which is why it is distinct from
    #   :default).
    # - location: the LSP range of the statement that introduced this
    #   ancestor (the `include Foo` call, the `< Foo` superclass clause),
    #   or nil for the implicit default root.
    AncestorEntry = Data.define(:name, :kind, :origin, :location) do
      # Which declaration kind a lookup should ask this ancestor for, and
      # the one place that knows the rule -- it was written out at two
      # call sites and both had it wrong for the `:class_object` tail.
      #
      # In singleton mode most ancestors contribute `def self.foo`, but
      # two kinds contribute *instance* methods: a module reached by
      # `extend` (its instance methods become the receiver's class-level
      # ones), and the tail below, which is in the chain because the
      # class object is an instance of `Class`/`Module`/`Object`.
      INSTANCE_SIDE_ORIGINS = %i[extend class_object].freeze

      def declaration_kind(singleton:)
        return :instance_method unless singleton

        INSTANCE_SIDE_ORIGINS.include?(origin) ? :instance_method : :singleton_method
      end

      # Not a link the workspace wrote, so it cannot be one the workspace
      # reopened.
      def synthesised? = %i[default class_object].include?(origin)
    end

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

      # What a class object *is*, which is what its singleton chain ends
      # in: `Widget.private` finds `Module#private` because `Widget` is a
      # `Class`, `Class < Module`, and `Module < Object`. Without this
      # tail the chain stopped at the last workspace superclass, so every
      # `private`, `attr_reader`, `include` and `alias_method` in a class
      # body resolved nowhere and the unknown-method check reported it
      # (024.23) -- 49 of the 60 findings over this repository's own
      # `core/lib` on 0.1.13.
      #
      # A module's singleton side is the same list without `Class`: a
      # module is a `Module` but not a `Class`, which is why `superclass`
      # answers on one and not the other.
      DEFAULT_CLASS_SINGLETON_CHAIN = [
        AncestorEntry.new(name: "Class", kind: :class, origin: :class_object, location: nil),
        AncestorEntry.new(name: "Module", kind: :class, origin: :class_object, location: nil),
        *DEFAULT_OBJECT_CHAIN.map { |entry| entry.with(origin: :class_object) }
      ].freeze
      private_constant :DEFAULT_CLASS_SINGLETON_CHAIN

      DEFAULT_MODULE_SINGLETON_CHAIN = [
        AncestorEntry.new(name: "Module", kind: :class, origin: :class_object, location: nil),
        *DEFAULT_OBJECT_CHAIN.map { |entry| entry.with(origin: :class_object) }
      ].freeze
      private_constant :DEFAULT_MODULE_SINGLETON_CHAIN

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
        @mutex.synchronize do
          entries = compute_ancestors_locked(type_name, singleton: singleton, visited: Set.new)
          dedupe_named(singleton ? entries + singleton_tail_for(type_name, entries) : entries, singleton)
        end
      end

      # Every `alias`/`alias_method` fact recorded directly inside
      # `type_name`'s own body (not inherited — Ruby aliases are resolved
      # against whatever `old_name` means *at definition time* in that
      # exact class/module, not looked up again through the ancestor
      # chain at call time).
      def aliases(type_name)
        canonical = canonical_name(type_name)
        @mutex.synchronize { @aliases_by_owner.fetch(canonical, []).dup }
      end

      private

      # One entry per *link*, where a link is a name **and which side of
      # it** the chain reaches. Not the name alone:
      #
      #   $ ruby -e 'module ES; extend self; def es_a; end; end
      #              p ES.singleton_class.ancestors.first(3)'
      #   # => [#<Class:ES>, ES, Module]
      #   # ruby 3.4.10
      #
      # Those are two different things, and this index writes both under
      # the name `"::ES"` -- the singleton class as `origin: :self`, the
      # module as `origin: :extend`, which is exactly what
      # `AncestorEntry#declaration_kind` reads. Keying the dedupe on the
      # name alone kept the first and dropped the second, which made
      # `extend self` record a fact that nothing could then read:
      # `ActiveSupport::Inflector.pluralize` lost hover, go-to-definition
      # and completion and gained a false report, and 0.2.9 had answered
      # it correctly.
      #
      # Nameless entries are never merged: each is a *different* thing
      # this index could not identify, and collapsing them would say the
      # chain is shorter than the number of unknowns in it.
      def dedupe_named(entries, singleton)
        seen = Set.new
        entries.select do |entry|
          entry.name.nil? || seen.add?([entry.name, entry.declaration_kind(singleton: singleton)])
        end
      end

      # Plain resolution. 0.2.1 applied `Index::TypeNameResolution` here so
      # that a literal's `String` would not be answered by a workspace
      # `Serializer::Elements::String`, and that broke a bare name the
      # user *wrote*: `Range.new` inside `module Billing` is how Ruby
      # refers to a class from its own namespace, and hover, go to
      # definition and completion all stopped answering for it.
      #
      # The two cases differ in whether the name was written or inferred,
      # and this method is handed a name with no lexical context to tell
      # them apart -- so the rule stays where it can be applied safely,
      # in the diagnostics engine, which is refusing to *report* rather
      # than refusing to resolve. 024.47 records what a real fix needs.
      def canonical_name(type_name)
        @workspace_index.resolve_type_name(type_name) || type_name.to_s
      end

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
        canonical = canonical_name(type_name)
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
        if superclass_fact && unresolvable_superclass?(superclass_fact.target)
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
        entries.concat(concern_class_method_entries(canonical, visited))

        superclass_fact = @superclass_by_owner[canonical]
        if superclass_fact && unresolvable_superclass?(superclass_fact.target)
          # Unbounded parent: no tail, for the same reason the instance
          # side omits one. Appending Class/Module here would say the
          # chain is fully accounted for when its middle is not.
          entries << AncestorEntry.new(name: nil, kind: nil, origin: :superclass, location: nil)
        elsif superclass_fact && !ROOT_SUPERCLASS_NAMES.include?(superclass_fact.target)
          # The tail is not appended here at all: `#ancestors` adds it
          # once, from the receiver's own kind.
          entries.concat(
            compute_ancestors_locked(superclass_fact.target, singleton: true, visited: visited, origin_for_self: :superclass)
          )
        end

        entries
      end

      # `include M` where `M::ClassMethods` exists puts that module on the
      # *class-level* chain -- which is `ActiveSupport::Concern`'s whole
      # contract, and what makes recording a `class_methods do` block as
      # `M::ClassMethods` mean anything:
      #
      #   $ ruby -e '
      #   gem "activesupport"; require "active_support"
      #   require "active_support/concern"
      #   module Taggable
      #     extend ActiveSupport::Concern
      #     class_methods do
      #       def cm_public; end
      #     end
      #   end
      #   class Article; include Taggable; end
      #   p [Article.respond_to?(:cm_public), Article.new.respond_to?(:cm_public)]
      #   '
      #   # => [true, false]
      #   # ruby 3.4.10, activesupport 8.1.3.1
      #
      # Keyed on the *declaration existing* rather than on spotting
      # `extend ActiveSupport::Concern`: a module that declares a
      # `ClassMethods` and is included without being a Concern adds
      # nothing at runtime, so this can be wrong in the direction of
      # offering a name that is not there. That is the same trade the
      # rest of this index makes for `include`/`extend`, and the
      # alternative -- requiring the `extend ActiveSupport::Concern` line
      # -- misses every concern written before Rails 4 and every project
      # that re-exports one. `024.104`.
      # `prepend` as well as `include`: `Concern#prepend_features` extends
      # `ClassMethods` exactly as `append_features` does, so a prepended
      # concern's class methods are on the class the same way.
      def concern_class_method_entries(canonical, visited)
        facts = @includes_by_owner.fetch(canonical, []) + @prepends_by_owner.fetch(canonical, [])
        facts.flat_map do |fact|
          class_methods = "#{Index::SymbolId.qualify_owner(canonical_name(fact.target))}::ClassMethods"
          next [] unless kind_of(class_methods)

          compute_ancestors_locked(class_methods, singleton: false, visited: visited, origin_for_self: :extend)
        end
      end

      # What the *receiver* is, which is what its singleton chain ends in:
      # `W.singleton_class.ancestors` ends `Class, Module, Object, Kernel,
      # BasicObject` for every class W, whatever its superclasses are.
      # 0.1.14 decided this inside the recursion, from the name the walk
      # terminated at -- so a class whose ancestors end at a module got
      # the module tail, and `new` was reported on it
      # (`ActionController::TestRequest`).
      #
      # A `nil` kind means the workspace never declared this name, so
      # whether it is a class, a module or neither is not ours to assume;
      # and a chain with an unbounded link is not one we can say ends
      # anywhere at all.
      def singleton_tail_for(type_name, entries)
        return [] if entries.any? { |entry| entry.name.nil? }

        canonical = canonical_name(type_name)
        case kind_of(canonical)
        when :class then DEFAULT_CLASS_SINGLETON_CHAIN
        when :module then DEFAULT_MODULE_SINGLETON_CHAIN
        else []
        end
      end

      # A parent this index cannot identify, which is two things rather
      # than one:
      #
      # - `class Foo < <expression>` records no name at all;
      # - a name `WorkspaceIndex` answers only by substituting a
      #   different class. Resolution here is by last segment and is
      #   deliberately not lexical (see this class's own comment), so
      #   `class ThroughAssociation < Association` inside `Preloader`
      #   picked whichever `Association` sorted first -- and ActiveRecord
      #   8.1.3 has three. Every answer about the subclass was then about
      #   a chain it does not have: `loaded?(owner)` was reported as
      #   taking no arguments, twice, on correct code.
      #
      # Both mean the same thing to every reader of this chain -- the
      # method set above this class is unbounded -- so both produce the
      # same nameless entry rather than a resolved one. That is what
      # makes the checks decline rather than report about the wrong
      # class; `WorkspaceIndex#guessed_type_name?` states the rule for a
      # receiver and this is the same rule one level up.
      def unresolvable_superclass?(target)
        target.nil? || @workspace_index.guessed_type_name?(target)
      end

      # Shared by prepend/include (their target's own *instance* side —
      # a module's methods, plus whatever it in turn includes) and extend
      # (same: `extend M` puts M's instance methods on the singleton
      # chain, so the extended module's instance-side ancestors are what
      # belongs here too, not its own singleton side).
      def ancestor_entries_for(fact, visited)
        # An ancestor whose name is claimed by several declared types is
        # not resolved -- it is picked, and Ruby's own lookup is lexical
        # while `AncestorFact` carries no lexical nesting. Picking put a
        # module from an unrelated namespace into the chain and left the
        # chain looking complete, which is worse than not knowing: the
        # class's own methods were then reported missing.
        #
        # Recorded as a nameless entry rather than dropped, so the chain
        # says it is incomplete instead of silently shrinking. Dropping it
        # would produce the same false report for a new reason.
        #
        # The durable fix is 024.81: carry the lexical context, so this is
        # a lookup again rather than a refusal.
        if @workspace_index.ambiguous_type_name?(fact.target)
          return [AncestorEntry.new(name: nil, kind: nil, origin: fact.relation, location: fact.location)]
        end

        compute_ancestors_locked(fact.target, singleton: false, visited: visited, origin_for_self: fact.relation)
      end

      def kind_of(canonical)
        @workspace_index.type_kind(canonical)
      end
    end
  end
end
