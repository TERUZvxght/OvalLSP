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

      # The ancestor chain a lookup on this receiver walks, as
      # `[owner_name, singleton?]` pairs -- the second element being which
      # *side* of that owner to ask, which is not the same question as the
      # side of the walk (`AncestorEntry#declaration_kind`: a class object
      # is an instance of `Class`, so the tail of a singleton chain is
      # asked for instance methods).
      #
      # Exposed because `QueryService#members_of` needs the same chain for
      # its signature source and had none: it asked RBS about the
      # receiver's own name only, so an inherited signature was never
      # offered. Rather than hand that service a second reference to the
      # hierarchy index, the object that already owns it answers.
      def lookup_owners(receiver_type, singleton: false)
        nominal = base_nominal(receiver_type)
        return [] unless nominal

        @hierarchy_index.ancestors(nominal.name, singleton: singleton).filter_map do |entry|
          next if entry.name.nil?

          [entry.name, entry.declaration_kind(singleton: singleton) == :singleton_method]
        end
      end

      # All candidates named `name` reachable from `receiver_type`, in
      # ancestor order, deduplicated by declaring symbol. For a Union
      # receiver, a candidate not present on every member is marked
      # `conditional: true` rather than omitted — diagnostics/definition
      # callers decide what to do with a conditional candidate; this
      # layer never silently drops one.
      # The same question as `#resolve`, answered in three states instead
      # of a list whose emptiness means two different things.
      #
      # **The default is `unknown`, and that inversion is the point.**
      # `#resolve` answers `[]` both for "the workspace does not declare
      # this" and for "I could not look at all", and every consumer then
      # assumes absence and subtracts the ways of not knowing it has
      # heard about. 0.2.6 added four such subtractions to
      # `Diagnostics::Engine`, one per review round, each after a false
      # report on code that runs. With the default the other way round, a
      # way of not knowing that nobody has thought of yet produces
      # silence.
      #
      # This resolver rules out only what it can see: a receiver that is
      # not a class, and an ancestor chain with a link it could not
      # identify. RBS, the Runtime Agent, a reopened core class and a
      # surface opened by an unreadable macro are all somebody else's to
      # rule out, and until they do the answer stays `unknown`. Nothing
      # here produces `absent` yet, deliberately: `absent` is earned by
      # whoever can account for the whole surface, and moving those
      # accounts here is the rest of `037`'s C2.
      #
      # `#resolve` is untouched, so nothing changes behaviour on the
      # strength of this alone.
      # `signatures:` is passed per call rather than held. Holding it
      # meant two references to one fact -- `Server` rebuilds its
      # signature environment when the client names a root other than the
      # cwd (`024.98`), and this resolver would have had to be kept in
      # step, which is the class of defect this release is about arriving
      # inside the fix for it. The caller already has the environment.
      #
      # Its absence is not neutral: without one, nothing can be shown to
      # account for an ancestor, so this never answers `absent`. That is
      # the honest reading, and what `Diagnostics::Engine` already did by
      # returning early when it had no signatures.
      def availability(receiver_type:, name:, context: {}, signatures: nil)
        normalized, normalized_context = normalize_class_receiver(receiver_type, context)
        types = nominal_members(normalized)
        return MemberAvailability.unknown(:receiver_not_nominal) if types.empty?

        candidates = merge_candidates(types.map { |type| candidates_for_type(type, name.to_s, normalized_context) },
                                      name.to_s)
        return MemberAvailability.present(candidates) unless candidates.empty?

        reason = types.filter_map { |type| unenumerable_reason(type, normalized_context, signatures) }.first
        return MemberAvailability.unknown(reason) if reason

        # The one place `absent` is produced: every link in the chain is
        # accounted for by the workspace or by signatures, nothing on it
        # answers at call time or hides an unreadable surface, and the
        # name is not among its members. Everything that could make that
        # untrue is a reason above.
        MemberAvailability.absent
      end

      # Why this receiver's members could not be listed in full, or nil if
      # they could.
      #
      # These were `return false` lines inside
      # `Diagnostics::Engine#closed_nominal?`, each added a review round
      # at a time after a false report on working code. They belong where
      # the enumeration happens: as a reason on the answer, a reader gets
      # them without having been taught, which is the whole of `037`'s C2.
      #
      # Two of the engine's six are not here yet -- both need the
      # signature environment to say whether an ancestor is one RBS
      # declares, and this resolver is not given one. They move when it
      # is.
      def unenumerable_reason(type, context, signatures)
        singleton = context[:singleton] == true
        entries = @hierarchy_index.ancestors(type.name, singleton: singleton)

        # `Diagnostics::Engine#closed_nominal?` opened with
        # `return false if entries.empty?`, and that line cannot fire: a
        # chain always contains at least the receiver itself, for a name
        # nothing declares and for the empty string alike, in both
        # singleton and instance modes. It is not carried here.
        # CLAUDE.md: a guard no input can reach is the same defect as an
        # untested one.
        #
        # Always the *instance* chain, even for a singleton lookup: a
        # singleton chain ends at the class itself and never reaches
        # BasicObject, so asking it directly would call every `Foo.bar`
        # unenumerable and silence everything.
        instance_entries = @hierarchy_index.ancestors(type.name, singleton: false)
        # **A module's instance chain is itself, and that is complete.**
        # `PlainMod.ancestors` is `[PlainMod]` -- no Object, no
        # BasicObject -- so requiring BasicObject called every module
        # unenumerable and nothing checked a module's class-level calls at
        # all: `PlainClass.nope_y` was reported and `PlainMod.nope_x` was
        # not, on a module whose `def self.` methods this engine knows
        # (`024.106`). Ruby raises `NoMethodError` for both.
        return :ancestor_not_identified unless rooted_instance_chain?(type, instance_entries, singleton)
        # A singleton lookup depends on the instance chain too: `include`
        # puts a module there, and `included`/`extended` hooks are how a
        # module adds class methods.
        return :ancestor_not_identified if singleton && instance_entries.any? { |e| e.name.nil? }
        return :ancestor_not_identified if entries.any? { |e| e.name.nil? }

        return :responds_at_call_time if entries.any? { |e| declares_method_missing?(e, singleton) }
        return :surface_open if entries.any? { |e| open_surface?(e, singleton) }

        # An ancestor neither the workspace nor the signature environment
        # declares means the receiver's real method set could include
        # anything. Without a signature environment at all, nothing can be
        # shown to be accounted for -- so the whole chain reads as
        # unaccounted rather than as fine.
        return :ancestor_not_declared_anywhere unless entries.all? { |e| accounted_for?(e, signatures) }
        # The singleton half: `include` puts a module on the *instance*
        # chain, and `included`/`extended` hooks are how a module adds
        # class methods, so a class-level lookup depends on the instance
        # chain being accounted for too. 0.2.6 spent a review round
        # learning this -- `include Singleton` reported `.instance`
        # missing, `include Sidekiq::Worker` reported `sidekiq_options`.
        return :ancestor_not_declared_anywhere if singleton && !instance_entries.all? { |e| accounted_for?(e, signatures) }

        nil
      end

      # Whether anything can say what this link *contributes*, which is a
      # stronger question than whether it was identified.
      #
      # Without a signature environment, nothing can: the synthesised
      # `Object`/`Kernel`/`BasicObject` tail carries a kind but its
      # members live in RBS, so treating "has a kind" as accounted-for
      # made a bare resolver answer `absent` for every method on every
      # class -- `Widget.new.to_s` included. `Diagnostics::Engine` has the
      # same hole in `#ancestor_known?` and never meets it, because
      # `#unknown_method_findings` returns before asking when there is no
      # signature environment.
      def accounted_for?(entry, signatures)
        return false if signatures.nil?
        return true if entry.kind

        !signatures.ancestors(Index::SymbolId.qualify_owner(entry.name)).empty?
      end

      # Whether the chain ends where Ruby ends it: at `::BasicObject`.
      #
      # **0.2.10 tried to make a module an exception and rolled it back.**
      # `PlainMod.ancestors` is `[PlainMod]`, so the sentinel can never
      # fire for one, and `024.106`'s second half -- nothing checks a
      # module's class-level calls -- is real. But "the workspace declares
      # this name a module" is not the completeness proof the sentinel is:
      # a module reopened *anywhere*, however partially, then read as
      # fully enumerable. `module Rails` reopened by two generator files
      # was enough to report `Rails.application`, `Rails.env`,
      # `Rails.logger`, `Rails.root` and four more as missing.
      #
      # Measured by a `drive` round over 261 files of actioncable,
      # activejob, activemodel and this repository's own `core/lib`, with
      # `unresolved-constant` identical at 1,780 as the control:
      # **41 findings added, 0 removed, and every one of the 41 false** --
      # including two about code this release itself added. A rule that
      # buys no true report for 41 false ones is not a rule to refine.
      # `024.106`'s second half is open again and records what a real
      # completeness proof for a module would have to be.
      def rooted_instance_chain?(type, instance_entries, _singleton)
        instance_entries.any? { |e| Index::SymbolId.qualify_owner(e.name) == "::BasicObject" }
      end

      # **The side matters.** `def self.method_missing` answers class-level
      # calls and `def method_missing` answers instance ones, and this
      # asked for instance methods whichever side the lookup was on -- so
      # a class answering `CWithMM.anything` through
      # `def self.method_missing` was judged closed and every call it
      # handles was reported (`024.116`). Ruby returns `:mm`.
      def declares_method_missing?(entry, singleton)
        # The same side computation `#open_surface?` makes, for the same
        # reason, and 0.2.11 shipped this without it for one round:
        # `extend M` puts M's *instance* methods on the class-level
        # chain, so asking M about its singleton side asks the wrong one
        # and `ExtC.anything` was reported on a class Ruby answers.
        kind = if entry.origin == :extend
                 :instance_method
               else
                 singleton ? :singleton_method : :instance_method
               end
        @workspace_index.method_symbol_ids(entry.name, kind: kind).any? { |sid| sid.name == "method_missing" }
      end

      # `extend M` puts M's *instance* methods on the class-level chain,
      # so a link reached that way is asked about the other side.
      def open_surface?(entry, singleton)
        @workspace_index.open_surface?(entry.name, singleton: entry.origin == :extend ? false : singleton)
      end

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
          # The same refusal `#build_candidate` makes, for the same
          # reason, and it was missing here. A nameless entry is a parent
          # `HierarchyIndex` could not identify; `nil` is also the owner a
          # *top-level* `def` is indexed under, so asking it for members
          # answered with every top-level method in the workspace --
          # offered as completions on a class that has none of them.
          #
          # Found by an external review reading the two consumers against
          # each other: one had sealed this representation locally and the
          # other had not. The durable answer is that an unresolved
          # hierarchy edge should not be expressible as an owner at all
          # (`024.80`); this is the guard until it is not.
          next if entry.name.nil?

          kind = symbol_kind_for(entry, singleton)
          method_names_for_owner(entry.name, kind).each do |name|
            next unless name.start_with?(prefix)
            next if seen.include?(name)

            visibility = @workspace_index.declarations_with_uri(
              Index::SymbolId.new(kind: kind, owner: entry.name, name: name, discriminator: nil)
            ).first&.last&.visibility
            # **Protected as well as private.** `Prot.new.guarded` raises
            # exactly as a private call does, and only private was
            # excluded -- a 0.2.8 review round measured the cost by asking
            # a booted application `respond_to?` for every label offered.
            # Protected is the one visibility that depends on where the
            # call is written rather than only on the declaration, which
            # is why it is filtered on the explicit-receiver branch and
            # left alone for an implicit self.
            next if explicit_receiver && %i[private protected].include?(visibility)

            seen << name
            names << name
          end
        end
      end

      # Declared names *and* the aliases that point at them. `#resolve`
      # has followed an alias since Task 009 and `#complete` never did, so
      # hover, go-to-definition and the undefined-method check all knew
      # `aka` while completion said the name did not exist (`024.107`) --
      # one question with two answers depending which feature asked, which
      # is `024.100`'s shape and what C2 is for.
      def method_names_for_owner(owner, kind)
        declared = @workspace_index.method_symbol_ids(owner, kind: kind).map(&:name)
        aliases = @hierarchy_index.aliases(owner)
                                  .select { |fact| fact.singleton == (kind == :singleton_method) }
                                  .map(&:new_name)
        (declared + aliases).uniq
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
