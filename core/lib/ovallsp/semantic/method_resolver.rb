# frozen_string_literal: true

require "set"
require_relative "../types"
require_relative "../index/symbol_id"

module Ovallsp
  module Semantic
    # One resolved candidate for a method lookup.
    #
    # - symbol_id: the declaring method's SymbolId (owner is the ancestor
    #   that actually defines it, which may differ from the receiver
    #   type itself).
    # - declarations: [[uri, Declaration], ...] — every source occurrence
    #   (a reopened class contributes more than one).
    # - owner: the declaring type's canonical name (same as symbol_id.owner,
    #   surfaced directly since callers building a definition/hover result
    #   usually want this without unpacking symbol_id).
    # - visibility: :public/:private/:protected/nil, from the declaration.
    # - lookup_rank: position in the receiver type's ancestor chain (0 =
    #   the type itself) — the candidate with the lowest rank is the one
    #   an actual method call would invoke; #resolve returns every match
    #   found along the chain, not just the first, so a shadowed
    #   superclass method stays inspectable (docs/design/tasks/009-method-hierarchy-and-lookup.md
    #   "definitionは候補集合を返してよい").
    # - conditional: true if this method name isn't available on every
    #   member of a Union receiver (only meaningful when the query was
    #   made against a Union; always false for a single Nominal receiver).
    # - origin: how the declaring ancestor entered the chain — :self,
    #   :prepend, :include, :extend, :superclass, :default, or
    #   :class_object (the Class/Module tail of a singleton chain --
    #   `Diagnostics::Engine` declines to judge argument counts against
    #   one of those, since the workspace did not state it).
    MethodCandidate = Data.define(:symbol_id, :declarations, :owner, :visibility, :lookup_rank, :conditional, :origin)

    # Resolves method-call candidates and completion lists from a receiver
    # Types value, combining Semantic::HierarchyIndex (ancestor order) with
    # WorkspaceIndex (where methods are actually declared). Deliberately a
    # separate class from HierarchyIndex — "building the hierarchy" and
    # "querying methods against it" are different responsibilities
    # (docs/design/tasks/009-method-hierarchy-and-lookup.md).
    #
    # `context` (a Hash) recognizes two keys, both optional:
    #   - `singleton:` (default false) — look up class/singleton methods
    #     instead of instance methods (`extend`/`def self.`/`class << self`).
    #   - `implicit_self:` (default false) — true for a bare, receiver-less
    #     call from inside the type's own body (`foo` instead of `x.foo`),
    #     where private methods are legitimately callable; anything else
    #     (an explicit receiver, or unknown) excludes private methods from
    #     #complete's results (docs/design/tasks/009-method-hierarchy-and-lookup.md
    #     "private methodを不正な明示receiver候補として上位表示しない").
    class MethodResolver
      def initialize(workspace_index:, hierarchy_index:)
        @workspace_index = workspace_index
        @hierarchy_index = hierarchy_index
      end

      # All candidates named `name` reachable from `receiver_type`, in
      # ancestor order, deduplicated by declaring symbol. For a Union
      # receiver, a candidate not present on every member is marked
      # `conditional: true` rather than omitted — diagnostics/definition
      # callers decide what to do with a conditional candidate; this
      # layer never silently drops one.
      def resolve(receiver_type:, name:, context: {})
        method_name = name.to_s
        receiver_type, context = normalize_class_receiver(receiver_type, context)
        types = nominal_members(receiver_type)
        return [] if types.empty?

        per_type = types.map { |type| candidates_for_type(type, method_name, context) }
        merge_candidates(per_type, method_name)
      end

      # Every distinct method name starting with `prefix` reachable from
      # `receiver_type`, across its full ancestor chain, respecting
      # visibility. Conditional (Union, not-on-every-member) names sort
      # after unconditional ones.
      def complete(receiver_type:, prefix:, context: {}, limit: 50)
        receiver_type, context = normalize_class_receiver(receiver_type, context)
        types = nominal_members(receiver_type)
        return [] if types.empty?

        per_type_names = types.map { |type| names_for_type(type, prefix, context) }
        merge_names(per_type_names).first(limit)
      end

      private

      # `ClassOf[X]` is this engine's representation of the class object
      # itself -- what a bare constant evaluates to, and what `self` is
      # inside `class << self`. Looking a method up on it means looking at
      # X's *singleton* chain.
      #
      # Without this, a class receiver reached `nominal_members`, matched
      # nothing (it is a Generic, not a Nominal), and returned [] -- so
      # `Widget.` offered no `def self.` methods and no completion at all.
      # An explicit `singleton: true` from the caller still wins, so the
      # `class << self` path that already passed one is unaffected.
      def normalize_class_receiver(receiver_type, context)
        return [receiver_type, context] unless receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"

        [receiver_type.type_arg, context.merge(singleton: true)]
      end

      # A `Generic` receiver over a *real* class is read as that class:
      # `Hash[Unknown]`'s own methods live on `Hash`, exactly as `{}`'s do.
      # Without this, a container receiver reached here and matched
      # nothing, so a *workspace-declared* method on a reopened container
      # class was invisible to definition and completion, while the same
      # class reached as a plain Nominal found it. RBS-backed members were
      # never affected -- QueryService unwraps a Generic on its own for the
      # signature paths -- so the gap was specifically the workspace's own
      # declarations.
      #
      # `Types::INTERNAL_GENERIC_NAMES` are excluded because they name a
      # shape, not a class -- `Relation[User]` is not an instance of
      # anything called `Relation`. A member this returns nil for is
      # dropped, which for a Union also keeps it out of the
      # every-member-has-it count: a shape nobody can look a method up on
      # is not evidence that the method is conditional, and treating it as
      # evidence lowered the reference's confidence below what Find
      # References and Rename accept, dropping real call sites silently.
      def nominal_members(type)
        case type
        when Types::Union then type.members.filter_map { |m| base_nominal(m) }
        else Array(base_nominal(type))
        end
      end

      def base_nominal(type) = Types.base_nominal(type)

      def candidates_for_type(nominal, method_name, context)
        singleton = context[:singleton] == true
        entries = @hierarchy_index.ancestors(nominal.name, singleton: singleton)

        entries.each_with_index.filter_map { |entry, rank| build_candidate(entry, method_name, singleton, rank) }
      end

      def build_candidate(entry, method_name, singleton, rank)
        # A nameless entry is what `HierarchyIndex` records for a parent it
        # cannot identify -- `class Foo < <expression>`, or a name that
        # only resolves by substituting a different class. It names no
        # owner, so it can declare nothing, and asking anyway is not
        # merely useless: `SymbolId`'s owner would be nil, which is the
        # key a *top-level* `def` is recorded under. Every class with an
        # unknown parent inherited every top-level method in the
        # workspace. Ruby's own `un.rb` defines a top-level `mv`, and
        # `rubygems/package_task.rb`'s `mv gem_file, ".."` was reported as
        # passing two arguments to a method that takes none.
        return nil if entry.name.nil?

        kind = symbol_kind_for(entry, singleton)
        resolved_name = resolve_alias(entry.name, method_name, kind)
        symbol_id = Index::SymbolId.new(kind: kind, owner: entry.name, name: resolved_name, discriminator: nil)
        decls = @workspace_index.declarations_with_uri(symbol_id)
        return nil if decls.empty?

        MethodCandidate.new(
          symbol_id: symbol_id, declarations: decls, owner: entry.name,
          visibility: decls.first[1].visibility, lookup_rank: rank, conditional: false, origin: entry.origin
        )
      end

      # `extend M` surfaces M's *instance* methods (ordinary `def foo`,
      # declared with kind: :instance_method wherever M itself is
      # written) into the receiver's singleton lookup — the module body
      # doesn't use any special singleton syntax for this to work, so the
      # declaration kind to search for at an :extend-origin ancestor is
      # :instance_method even while the overall traversal is in singleton
      # mode -- and so does :class_object, the Class/Module tail, because
      # a class object is an *instance* of those. :self and :superclass in
      # singleton mode genuinely mean :singleton_method (`def self.foo`/
      # `class << self`). The rule lives in AncestorEntry so that this
      # file and Diagnostics::Engine cannot disagree about it; they did,
      # and both copies were wrong for the tail.
      def symbol_kind_for(entry, singleton) = entry.declaration_kind(singleton: singleton)

      # A single level of `alias`/`alias_method` indirection: if `owner`
      # doesn't declare `method_name` directly but *does* record an alias
      # from it to some `old_name`, resolve that instead. Real Ruby binds
      # an alias to whatever `old_name` means at the moment of the
      # `alias` statement, which could itself involve further chasing
      # through the ancestor chain — this covers the common case (the
      # aliased method is declared directly in the same class body, or
      # inherited under the same simple name) without implementing that
      # full generality.
      def resolve_alias(owner, method_name, kind)
        singleton = kind == :singleton_method
        fact = @hierarchy_index.aliases(owner).find { |f| f.new_name == method_name && f.singleton == singleton }
        fact ? fact.old_name : method_name
      end

      def merge_candidates(per_type, method_name)
        return per_type.first || [] if per_type.size <= 1

        present_count = per_type.count { |candidates| candidates.any? { |c| c.symbol_id.name == method_name } }
        conditional = present_count < per_type.size

        per_type.flatten.group_by(&:symbol_id).map { |_, group| group.first.with(conditional: conditional) }
                .sort_by(&:lookup_rank)
      end

      def names_for_type(nominal, prefix, context)
        singleton = context[:singleton] == true
        explicit_receiver = context[:implicit_self] != true
        entries = @hierarchy_index.ancestors(nominal.name, singleton: singleton)

        seen = Set.new
        entries.each_with_object([]) do |entry, names|
          kind = symbol_kind_for(entry, singleton)
          method_names_for_owner(entry.name, kind).each do |name|
            next unless name.start_with?(prefix)
            next if seen.include?(name)

            visibility = @workspace_index.declarations_with_uri(
              Index::SymbolId.new(kind: kind, owner: entry.name, name: name, discriminator: nil)
            ).first&.last&.visibility
            next if explicit_receiver && visibility == :private

            seen << name
            names << name
          end
        end
      end

      def method_names_for_owner(owner, kind)
        @workspace_index.method_symbol_ids(owner, kind: kind).map(&:name).uniq
      end

      def merge_names(per_type_names)
        total = per_type_names.size
        all_names = per_type_names.flatten.uniq

        all_names.map { |name| { name: name, conditional: per_type_names.count { |names| names.include?(name) } < total } }
                 .sort_by { |result| [result[:conditional] ? 1 : 0, result[:name]] }
      end
    end
  end
end
