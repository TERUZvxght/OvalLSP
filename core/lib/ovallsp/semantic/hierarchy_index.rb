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
    # Raised by `AncestorEntry#name` on an edge nobody resolved. Declared
    # here rather than inside the `Data.define` block because a constant
    # assigned in that block lands in the *lexical* scope, not on the
    # class -- so `AncestorEntry::Unidentified` would not exist, and the
    # rescue that named it would never match.
    UnidentifiedAncestor = Class.new(StandardError)

    AncestorEntry = Data.define(:identified_name, :kind, :origin, :location) do
      #
      # `024.80`. An ancestor this index could not identify used to be an
      # entry whose `name` is `nil` -- and `nil` is also the owner a
      # *top-level* `def` is indexed under, so asking one for its members
      # answered with every top-level method in the workspace, offered as
      # completions on a class that has none of them. Two readers guarded
      # it by hand, each guard added after the same bug was found in that
      # reader.
      #
      # So the member is `identified_name` and the accessor is `#name`:
      # there is no way to *spell* "the owner of an edge nobody
      # resolved". A reader that forgets `#identified?` raises here,
      # where the suite sees it, rather than answering plausibly.
      # Reads well at a call site, and keeps `identified_name` from being
      # spelled out anywhere but here.
      def self.identified(name:, kind:, origin:, location:)
        new(identified_name: name, kind: kind, origin: origin, location: location)
      end

      # A parent this index could not resolve -- `class Foo < <expression>`,
      # or an `include` of a name nothing declares. Kept in the chain
      # rather than omitted: omitting it makes the class look parentless
      # and therefore fully known, which is what made every Rails
      # migration report its own DSL calls as undefined methods.
      def self.unidentified(origin:, location:)
        new(identified_name: nil, kind: nil, origin: origin, location: location)
      end

      def identified? = !identified_name.nil?

      def name
        raise UnidentifiedAncestor, "an ancestor reached by #{origin} could not be identified" unless identified?

        identified_name
      end

      # For the readers that legitimately want "the name, or nothing" --
      # a dedupe key, a log line. Named so that reaching for it is a
      # decision rather than a habit.
      def name_or_nil = identified_name

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
      def synthesised? = %i[default class_object singleton_of].include?(origin)
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
        AncestorEntry.identified(name: "Object", kind: :class, origin: :default, location: nil),
        AncestorEntry.identified(name: "Kernel", kind: :module, origin: :default, location: nil),
        AncestorEntry.identified(name: "BasicObject", kind: :class, origin: :default, location: nil)
      ].freeze
      DEFAULT_CHAIN_NAMES = %w[Object Kernel BasicObject].freeze
      # What a class object's singleton chain ends in, over and above
      # the object chain: read by `#gem_singleton_links`, which must not
      # re-emit the tail `DEFAULT_CLASS_SINGLETON_CHAIN` already adds.
      CLASS_OBJECT_TAIL_NAMES = (DEFAULT_CHAIN_NAMES + %w[Class Module]).freeze
      private_constant :DEFAULT_OBJECT_CHAIN, :DEFAULT_CHAIN_NAMES, :CLASS_OBJECT_TAIL_NAMES

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
      # **The two links Ruby puts before `Class`**, and which an entry
      # naming a *type* could not express: the singleton classes of
      # `Object` and `BasicObject`.
      #
      #   $ ruby -e '
      #   class Object; def self.foo; :ok; end; end
      #   class Widget; end
      #   p [Widget.foo, Widget.singleton_class.ancestors.first(3)]
      #   '
      #   # => [:ok, [#<Class:Widget>, #<Class:Object>, #<Class:BasicObject>]]
      #   # ruby 3.4.10
      #
      # `origin: :singleton_of` keeps them on the *singleton* side, which
      # is what distinguishes them from the `:class_object` tail below --
      # that tail is there because the class object is an *instance* of
      # `Class`/`Module`/`Object`, and contributes those classes' instance
      # methods. These two contribute `Object`'s and `BasicObject`'s
      # `def self.` methods, which is what makes a workspace
      # `class Object; def self.foo` reachable from every class, as Ruby
      # makes it (`024.26`).
      DEFAULT_CLASS_SINGLETON_CHAIN = [
        AncestorEntry.identified(name: "Object", kind: :class, origin: :singleton_of, location: nil),
        AncestorEntry.identified(name: "BasicObject", kind: :class, origin: :singleton_of, location: nil),
        AncestorEntry.identified(name: "Class", kind: :class, origin: :class_object, location: nil),
        AncestorEntry.identified(name: "Module", kind: :class, origin: :class_object, location: nil),
        *DEFAULT_OBJECT_CHAIN.map { |entry| entry.with(origin: :class_object) }
      ].freeze
      private_constant :DEFAULT_CLASS_SINGLETON_CHAIN

      DEFAULT_MODULE_SINGLETON_CHAIN = [
        AncestorEntry.identified(name: "Module", kind: :class, origin: :class_object, location: nil),
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

      def initialize(workspace_index:, gem_index: GemIndex.empty, signatures: nil)
        @workspace_index = workspace_index
        # 024.R7. Empty unless a Runtime Agent has answered. Read at the
        # one place a chain stops for want of a superclass fact.
        @gem_index = gem_index
        # Read for one question only, in #canonical_name: whether a bare
        # name already denotes something, which is the difference between
        # reading `Relation` as a gem class and reading `Integer` as one.
        # `nil` is a stack built without signatures, and it declines
        # rather than guesses.
        @signatures = signatures
        @mutex = Mutex.new
        @facts_by_uri = {}
        @superclass_by_owner = {}
        @prepends_by_owner = Hash.new { |h, k| h[k] = [] }
        @includes_by_owner = Hash.new { |h, k| h[k] = [] }
        @extends_by_owner = Hash.new { |h, k| h[k] = [] }
        # `def self.included(base) = base.extend(ClassMethods)` -- a
        # concern marker, not an ancestor edge. Its own bucket because
        # it is neither: the module does not extend anything.
        @concern_markers_by_owner = Hash.new { |h, k| h[k] = [] }
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
      # 024.R7. Installed after the stack is built, because it is the
      # running application's answer and the stack exists before there
      # is one. Under the same mutex as everything else here: a query
      # on another thread must see one index or the other, never half.
      def gem_index = @mutex.synchronize { @gem_index }

      def gem_index=(index)
        @mutex.synchronize { @gem_index = index }
      end

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
          !entry.identified? || seen.add?([entry.name, entry.declaration_kind(singleton: singleton)])
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
      # The workspace answers first. Where it does not own the name at
      # all, the gem index's simple-name resolution does -- `Relation`
      # is what the type model spells `ActiveRecord::Relation`, and
      # `024.87` is the entry that needs it. Asking here, rather than
      # inside every gem-index lookup, is what keeps a workspace class
      # from being answered for out of a same-named gem class.
      def canonical_name(type_name)
        resolved = @workspace_index.resolve_type_name(type_name)
        return resolved if resolved

        bare = type_name.to_s
        return bare unless free_for_a_gem_to_claim?(bare)

        @gem_index.resolve_simple_name(bare) || bare
      end

      # **Whether this bare name means nothing yet.** The rule above
      # declines where two gems claim one simple name, and that was written
      # as though a contest between gems were the only way to be wrong. A
      # core class is the other way, and it cannot enter the contest:
      # `Object.const_source_location` answers `[]` for one, so the Agent --
      # which keeps only what a gem path accounts for -- never reports it,
      # and a gem's own nested class of that name stands unopposed. The
      # receiver then takes that class's chain, and every core method on it
      # is reported as one that does not exist.
      #
      # Signatures are the oracle, because they are the one thing here that
      # knows a name has a referent without a gem having loaded it. Only an
      # outright `false` -- never heard of it -- licenses the
      # reinterpretation. `nil` is the unbuildable chain of `024.223` and
      # declines; so does having no signature environment at all. This is
      # the "is this constant known" direction `#declares?` names, and that
      # one fails towards *known*.
      def free_for_a_gem_to_claim?(bare)
        return false unless @signatures

        @signatures.declares?(bare) == false
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
        when :concern_class_methods then @concern_markers_by_owner[fact.owner] << fact
        end
      end

      def remove_fact_locked(fact)
        case fact.relation
        when :superclass
          @superclass_by_owner.delete(fact.owner) if @superclass_by_owner[fact.owner] == fact
        when :prepend then @prepends_by_owner[fact.owner]&.delete(fact)
        when :include then @includes_by_owner[fact.owner]&.delete(fact)
        when :extend then @extends_by_owner[fact.owner]&.delete(fact)
        when :concern_class_methods then @concern_markers_by_owner[fact.owner]&.delete(fact)
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

        entries << AncestorEntry.identified(name: canonical, kind: kind_of(canonical), origin: origin_for_self, location: nil)

        @includes_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }

        superclass_fact = @superclass_by_owner[canonical]
        if superclass_fact && unresolvable_superclass?(superclass_fact.target)
          # `class Foo < <expression>`: the class has a parent whose name
          # we cannot resolve, so its method set is unbounded. Recorded as
          # a nameless, kindless ancestor rather than omitted, because
          # omitting it makes the class look parentless and therefore
          # fully known -- which is what made every Rails migration report
          # its own DSL calls as undefined methods.
          entries << AncestorEntry.unidentified(origin: :superclass, location: nil)
        elsif superclass_fact && ROOT_SUPERCLASS_NAMES.include?(superclass_fact.target)
          entries.concat(DEFAULT_OBJECT_CHAIN)
        elsif superclass_fact
          entries.concat(
            compute_ancestors_locked(superclass_fact.target, singleton: false, visited: visited, origin_for_self: :superclass)
          )
        elsif kind_of(canonical) == :class
          entries.concat(DEFAULT_OBJECT_CHAIN)
        end

        entries.concat(gem_ancestry(canonical, entries))
        entries
      end

      # 024.R7. Where the workspace's knowledge stops and the running
      # application's begins.
      #
      # A class whose parent is in a gem has no superclass fact, so the
      # walk above ends at that parent without reaching `BasicObject` --
      # honest while nothing knows what the gem defines, and the reason
      # the undefined-method check goes quiet for every Rails
      # controller.
      #
      # **Here rather than in `MethodResolver`, and that was measured.**
      # Splicing it there produced 47 reports over activerecord's own
      # source and every one was false -- `Foo.new` and `raise` among
      # them -- because rooting a chain needs three things this class
      # owns and a splice elsewhere skips: `DEFAULT_OBJECT_CHAIN`, whose
      # `Kernel` is a **module** and which the splice called a class;
      # the singleton tail, without which `.new` is not on the chain at
      # all; and `dedupe_named`.
      #
      # Only the gem's own links are added. `Object`/`Kernel`/
      # `BasicObject` come from the default chain, which is what every
      # other rooted class gets.
      def gem_ancestry(canonical, entries)
        return [] if @gem_index.empty?
        # **Classes only.** Rooting a module`s chain makes every
        # `ClassMethods`-style module a closed receiver -- and what
        # `self` is inside one at call time is the class that extended
        # it, which nothing here knows. Measured: with modules rooted,
        # activerecord`s own source reported `superclass`, `name` and
        # `primary_key` on its own modules, all of them correct code.
        # `kind_of` reads the *workspace* index, which knows nothing
        # about a gem's own class -- so this refused a receiver that is
        # itself a gem class, and `ActiveRecord::Relation`'s chain
        # stopped at one link. That is `024.87`'s unconfirmed half:
        # hover said `Relation[Post]` and completion after the dot was
        # empty, because the type survived and the members had nowhere
        # to come from.
        return [] unless class_here?(canonical)
        return [] if entries.any? { |e| e.identified? && qualify(e.identified_name) == "::BasicObject" }

        tail = entries.reverse.find { |e| e.identified? && @gem_index.knows?(e.identified_name) }
        return [] unless tail

        # **By identity, not by position.** `.drop(1)` assumed the
        # payload's first ancestor was the class itself, which is only
        # true when nothing is prepended -- Ruby puts a `prepend`ed
        # module *ahead* of the class, and instrumentation gems prepend
        # into ActiveRecord and ActionController routinely. Dropping the
        # head then deleted the module (its methods reported missing on
        # correct code, and a `method_missing` it declares never asked
        # about) and left the class on the chain twice, because `tail`
        # is already an entry in `entries`.
        known = @gem_index.ancestors(tail.identified_name).reject do |name|
          name == tail.identified_name || DEFAULT_CHAIN_NAMES.include?(name)
        end
        known.map { |name| AncestorEntry.identified(name: name, kind: kind_for_gem(name), origin: :superclass, location: nil) } +
          DEFAULT_OBJECT_CHAIN
      end

      # The gem index does not say class or module, and the distinction
      # decides which side a link is asked about. A gem entry whose own
      # ancestry starts with itself and then `Object` is a class; one
      # that does not reach `Object` is a module, which is what Ruby's
      # own `Module#ancestors` shows for a bare module.
      # A class, as either index sees it. The gem index does not label
      # class or module, so `#kind_for_gem` reads it off the loaded
      # ancestry -- a bare module's does not reach `Object`.
      def class_here?(name)
        return true if kind_of(name) == :class

        @gem_index.knows?(name) && kind_for_gem(name) == :class
      end

      # An `extend`ed module puts its *instance* methods on the
      # class-level chain, and the index's `singletonMethods` is
      # `singleton_methods(false)`, which cannot see them. Ruby settles
      # it: `CGI.singleton_class.ancestors` carries `CGI::Escape`, and
      # `CGI.escapeHTML` -- which exists -- was reported missing over
      # rack's own source without this.
      #
      # The links are asked for their *instance* methods, because that
      # is what `extend` surfaces -- `AncestorEntry#declaration_kind`
      # already makes that distinction for a workspace `extend`.
      def gem_singleton_links(canonical, entries)
        return [] if @gem_index.empty?
        return [] unless entries.length == 1
        return [] unless @gem_index.knows?(canonical)

        # `.drop(1)` here ate the first extended module rather than the
        # receiver: the Agent's `filter_map` has already removed the
        # anonymous `#<Class:X>`, which has no `module_name`, so element
        # 0 is the very thing this method exists to add. Rejecting by
        # identity keeps it and still removes the duplicate.
        #
        # `Class` and `Module` are rejected alongside the object chain
        # because they are the *class object's* own tail, which
        # `DEFAULT_CLASS_SINGLETON_CHAIN` supplies below with the right
        # `:class_object` origin and `kind: :class`. Left in, they made
        # this result non-empty for every receiver, so the `case` in
        # `#singleton_tail_for` never ran and a gem **module** was given
        # the class tail with `Class` on it.
        @gem_index.singleton_ancestors(canonical)
                  .reject { |n| n == canonical || CLASS_OBJECT_TAIL_NAMES.include?(n) }
                  .map { |n| AncestorEntry.identified(name: n, kind: :module, origin: :extend, location: nil) }
      end

      def kind_for_gem(name)
        @gem_index.ancestors(name).include?("Object") ? :class : :module
      end

      def qualify(name) = Index::SymbolId.qualify_owner(name)

      def singleton_ancestors_locked(canonical, visited, origin_for_self)
        entries = [AncestorEntry.identified(name: canonical, kind: kind_of(canonical), origin: origin_for_self, location: nil)]

        @extends_by_owner.fetch(canonical, []).reverse_each { |fact| entries.concat(ancestor_entries_for(fact, visited)) }
        entries.concat(concern_class_method_entries(canonical, visited))

        superclass_fact = @superclass_by_owner[canonical]
        if superclass_fact && unresolvable_superclass?(superclass_fact.target)
          # Unbounded parent: no tail, for the same reason the instance
          # side omits one. Appending Class/Module here would say the
          # chain is fully accounted for when its middle is not.
          entries << AncestorEntry.unidentified(origin: :superclass, location: nil)
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
      # **A marker is required, and there are two of them.** 0.2.10 keyed
      # this on the `ClassMethods` declaration merely existing, which made
      # completion offer a name that raises for any module that happens to
      # nest one. 0.2.11 first narrowed it to `extend ActiveSupport::Concern`
      # alone, on the stated ground that the pre-Rails-4 spelling is "an
      # ordinary `extend` this index has always followed" -- **that was
      # not true, and it was written from another round's summary rather
      # than checked.** In
      # `def self.included(base); base.extend(ClassMethods); end` the
      # receiver is a method *parameter*; there is no `extend` in a class
      # body for this index to follow, and a whole generation of real
      # concerns became false reports for one round.
      #
      # So the second marker is that spelling itself, recognised by the
      # parser as an `extend` fact from the module to its own
      # `ClassMethods`. Both are markers the module *writes*; a module
      # that writes neither still contributes nothing (`024.115`).
      #
      # `prepend` as well as `include`: `Concern#prepend_features` extends
      # `ClassMethods` exactly as `append_features` does, so a prepended
      # concern's class methods are on the class the same way.
      def concern_class_method_entries(canonical, visited)
        concern_targets(canonical, Set.new).flat_map do |target|
          concern_class_method_sources(target).flat_map do |name|
            # An `extend` the hook *names* and this workspace cannot
            # resolve is not "no class methods" -- the module is a gem's,
            # and whatever it declares is on the class. Unidentified, so
            # `#reason_to_decline` declines about the receiver rather than
            # asserting a method set built without it.
            #
            # **The difference does not show through diagnostics**: read
            # as identified, the name is one no signature set declares, so
            # `#reason_to_decline` reaches `:ancestor_not_declared_anywhere`
            # and declines by the other route. What it does show is the
            # chain, which is where it is pinned -- an identified entry
            # carrying the whole `Object, Kernel, BasicObject` tail claims
            # a chain that was never built, and every later reader of
            # `#ancestors` acts on that claim.
            next [AncestorEntry.unidentified(origin: :extend, location: nil)] if name && !kind_of(name)

            compute_ancestors_locked(name, singleton: false, visited: visited, origin_for_self: :extend)
          end
        end
      end

      # **Where a concern's class methods actually come from.** Two
      # spellings, and until now only one of them was read:
      #
      # - `extend ActiveSupport::Concern` names no module, and Concern's
      #   own rule is the nested `ClassMethods`. That is the fallback, and
      #   it is a guess about a name rather than a fact, so a missing
      #   `ClassMethods` means "no class methods" and not "cannot tell".
      # - `def self.included(base) = base.extend(X)` names `X`. The parser
      #   has recorded that name since 0.2.11 and **nothing read it**:
      #   `#{target}::ClassMethods` was synthesised instead, which is
      #   right only when `X` happens to be spelled `ClassMethods`. A hook
      #   extending anything else -- `base.extend(Helpers)` -- put no
      #   class methods on the class at all, and every one of them was
      #   reported missing (ruby 3.4.10 says `W3.respond_to?(:from_helpers)`
      #   is `true`).
      #
      # Both, unioned, because a module may carry both markers and the
      # union is the safe direction. `#nested_type_name` with the fact's
      # own nesting, as `#ancestor_entries_for` does: `ClassMethods`
      # written inside `module H1` means `H1::ClassMethods`, and a
      # workspace-wide pick among every module that nests one is exactly
      # the ambiguity `024.15` records.
      def concern_class_method_sources(target)
        hooked = @concern_markers_by_owner.fetch(target, []).map do |fact|
          @workspace_index.nested_type_name(fact.target, nesting: fact.nesting) || fact.target
        end

        nested = "#{target}::ClassMethods"
        hooked + (kind_of(nested) ? [nested] : [])
      end

      # Every concern this owner picks up, **transitively**. A concern
      # that includes another concern passes the inner one's class methods
      # on -- `ActiveSupport::Concern#append_features` runs the inner
      # module's own hook -- and reading `@includes_by_owner` one level
      # deep lost them. That is the commonest way a large Rails
      # application composes concerns.
      #
      # Only through modules that are concerns: a plain module that
      # happens to include one does *not* pass its class methods on, and
      # Ruby raises there.
      def concern_targets(canonical, seen)
        return [] unless seen.add?(canonical)

        facts = @includes_by_owner.fetch(canonical, []) + @prepends_by_owner.fetch(canonical, [])
        facts.flat_map do |fact|
          target = Index::SymbolId.qualify_owner(canonical_name(fact.target))
          next [] unless concern?(target)

          [target, *concern_targets(target, seen)]
        end
      end

      # Whether the module says it is one, by either spelling: the
      # `extend ActiveSupport::Concern` line, or the `self.included` hook
      # the parser records as `:concern_class_methods`.
      def concern?(target)
        return true unless @concern_markers_by_owner.fetch(target, []).empty?

        @extends_by_owner.fetch(target, []).any? { |fact| concern_marker_name?(fact.target) }
      end

      # **Matched on the name it resolves to, not the name as written.**
      # Rails writes `extend Concern` bare, from inside
      # `module ActiveSupport` -- `callbacks.rb:66`, `rescuable.rb:12`,
      # `actionable_error.rb:12` -- and matching the written text missed
      # every one, so `ActiveSupport::ExecutionWrapper.define_callbacks`,
      # `ActiveSupport::Reloader`, `ActionDispatch::Callbacks` and
      # `ActionCable::Server::Worker` were all reported as missing
      # methods. Fourteen of the fifteen false reports a `reproduce`
      # round measured this release adding.
      #
      # `#canonical_name` is what does the work, and it is enough on its
      # own: it resolves the bare `Concern` written inside
      # `module ActiveSupport` to `::ActiveSupport::Concern`, so the
      # suffix test matches. 0.2.11 added `|| name.split("::").last ==
      # "Concern"` beside it and documented the loosening as a deliberate
      # trade -- it was dead code, and the trade was never being made.
      # Found by `scripts/check_pinned_mutations.rb` on its first run:
      # removing the clause left the example that supposedly needed it
      # passing.
      def concern_marker_name?(target)
        Index::SymbolId.bare_name(canonical_name(target).to_s).end_with?("ActiveSupport::Concern")
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
        return [] if entries.any? { |entry| !entry.identified? }

        gem_singleton = gem_singleton_links(canonical_name(type_name), entries)
        return gem_singleton + DEFAULT_CLASS_SINGLETON_CHAIN unless gem_singleton.empty?

        canonical = canonical_name(type_name)
        # `class_here?` rather than `kind_of`: the workspace index does
        # not know a gem class, so its singleton chain got no tail and
        # `Foo.new` became a closed receiver with no `new` on it -- 37
        # false reports over activerecord, every one a `.new`.
        # The workspace answers first: it distinguishes class from
        # module, and the gem index only says "class" or nothing.
        # Written the other way round, a workspace *module* was given a
        # class tail and 25 examples failed.
        # The workspace answers first -- it distinguishes class from
        # module, and the gem index only says "class" or nothing. And
        # the gem fallback applies only to a name the *index* knows, so
        # a workspace name the workspace could not classify keeps the
        # answer it had. Written without either guard, 25 examples
        # failed on workspace types this never used to speak about.
        case kind_of(canonical) || (@gem_index.knows?(canonical) && kind_for_gem(canonical) == :class ? :class : nil)
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
        # **Ruby's own lookup first, as of 0.2.12.** `AncestorFact` carries
        # `Module.nesting` at the point the constant was written, so
        # `include Helpers` inside `Rackish::Request` names
        # `Rackish::Request::Helpers` whatever other namespace has a
        # `Helpers` -- which is what Ruby does, and what the refusal below
        # was standing in for. Same rule and same reader as `024.103`'s.
        target = @workspace_index.nested_type_name(fact.target, nesting: fact.nesting) || fact.target

        if @workspace_index.ambiguous_type_name?(target)
          return [AncestorEntry.unidentified(origin: fact.relation, location: fact.location)]
        end

        compute_ancestors_locked(target, singleton: false, visited: visited, origin_for_self: fact.relation)
      end

      def kind_of(canonical)
        @workspace_index.type_kind(canonical)
      end
    end
  end
end
