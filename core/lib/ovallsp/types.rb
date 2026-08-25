# frozen_string_literal: true

module Ovallsp
  # MVP subset of the type lattice in docs/design/docs/03-semantic-engine.md
  # section 2.4. Method body summaries, RBS, and blocks are still out of
  # scope: Unknown (no information yet), nil, a Nominal class reference,
  # Union for branch merges, and (since Task 007) Generic for the built-in
  # Active Record Relation[T]/CollectionProxy[T] shapes.
  module Types
    # No information is available yet; more evidence could still narrow it.
    # Distinct from a resolved-but-unrepresentable type (which this
    # implementation doesn't need yet, so it isn't modeled).
    class Unknown
      def to_s
        "Unknown"
      end
    end
    UNKNOWN = Unknown.new.freeze

    class NilType
      def to_s
        "nil"
      end
    end
    NIL = NilType.new.freeze

    # A concrete class/module reference, e.g. Nominal("User").
    Nominal = Data.define(:name) do
      def to_s
        name
      end
    end

    # A single-parameter generic container, e.g. Relation[Order] or
    # CollectionProxy[Order]. Full generics (arbitrary arity, user-defined
    # types) are still out of scope — this exists only for the built-in
    # Active Record shapes Task 007 introduces
    # (docs/03-semantic-engine.md section 7.1).
    Generic = Data.define(:name, :type_arg) do
      def to_s
        "#{name}[#{type_arg}]"
      end
    end

    # Generic names that stand for a *shape* this engine models rather than
    # a class anyone declares: `ClassOf[X]` is X's class object, and
    # Relation/CollectionProxy are the Active Record collection shapes.
    # Anything that would otherwise read a Generic's name as a class has to
    # exclude these -- a workspace is perfectly likely to contain its own
    # `Relation`, and resolving into it would be resolving into a class the
    # value has nothing to do with.
    INTERNAL_GENERIC_NAMES = %w[ClassOf Relation CollectionProxy].freeze

    # A class-object receiver, split into the thing to look a member up
    # on and whether that lookup is a singleton one.
    #
    # `String.new` types as `ClassOf[String]`, and a lookup that does not
    # make this move asks about a class literally named `ClassOf`. Three
    # readers were making it by hand — `MethodResolver#normalize_class_receiver`,
    # `QueryService#add_active_record_api_members` and the RBS member
    # lookup completion reads — and two more were not: the RBS signature
    # lookup and `QueryService#signature_definition_locations`, so every
    # `String.new(`, `File.read(`, `Integer.sqrt(` answered nothing in
    # signature help, hover and go to definition alike (`024.43`).
    #
    # Those two now reach it through `QueryService#rbs_lookup_chains`,
    # and completion through `#rbs_owner_chains`; both call this. The
    # methods that used to call it directly are named by shape rather
    # than by name here, because the names have already changed once and
    # a comment naming a method that no longer exists is what `024.43`'s
    # own review round found (`0.2.16`).
    #
    # A module function the readers call, rather than the move being
    # pushed into `#each_nominal`: that would fan it out to seven call
    # sites including the model-membership paths, and moving a rule to
    # where the value is produced is what `024.47` had to roll back.
    #
    # An explicit `singleton: true` from a caller still wins, so a
    # `class << self` path that already passes one is unaffected.
    def self.class_object_lookup(receiver_type, singleton: false)
      return [receiver_type, singleton] unless class_object?(receiver_type)

      [receiver_type.type_arg, true]
    end

    def self.class_object?(type) = type.is_a?(Generic) && type.name == "ClassOf"

    # The other direction: the class object *of* a type.
    # `class_object_lookup` above is the one place that knows how to take
    # a `ClassOf` apart, and this is the one place that knows how to build
    # one -- the wrap was written out by hand at five sites, and `024.85`
    # adds readers that have to agree with `#locate_in_def`'s about a
    # value they hand to each other.
    #
    # Deliberately *not* idempotent, because the operation is not:
    # `W.class` is `Class`, not `W`. A caller that means "the class object
    # this frame already denotes" asks `class_object?` first -- see
    # `LocalInferencer#enclosing_class_object`.
    def self.class_object(type) = Generic.new(name: "ClassOf", type_arg: type)

    # `#class` is the one call whose result this engine already has an
    # exact type for -- `ClassOf[T]` is what a class object *is* here.
    # Left to RBS it resolves to `Class`, which is true and useless: every
    # workspace class method reached through `record.class` was then
    # reported unknown, and completion after `x.class.` offered `Class`'s
    # members rather than the class's own. `024.46`'s first family, and
    # the one that made typing `self` unshippable in 0.2.1 --
    # `unless self.class.correct?(v)` is everyday Ruby.
    #
    # Taken from Ruby, not reasoned about:
    #
    #   $ ruby -e 'p nil.class; p 1.class; class W; end; p W.class'
    #   # => NilClass
    #   # => Integer
    #   # => Class
    #   # ruby 3.4.10
    #
    # so a class object's own `#class` is `Class` -- the operation is not
    # idempotent, which is why `class_object` above is not either.
    #
    # **Here rather than in either evaluator**, because both have to
    # answer it and a rule either one owns is a rule the other drifts
    # from -- the shape `LiteralTypes` already took after a literal added
    # to one table alone made a method *ending* in one return Unknown to
    # every caller while the same expression assigned to a local typed
    # correctly (twice).
    #
    # nil declines, wherever the receiver is not a class this engine can
    # name: an Unknown receiver, and the generics that stand for a shape
    # rather than a class (`INTERNAL_GENERIC_NAMES`, which `base_nominal`
    # already refuses). A Union declines whole rather than in part, so a
    # branch that cannot be named is not silently dropped from *this*
    # answer -- `LocalInferencer#resolve_call`'s own union fallback may
    # then still answer from the branches that can, which is the rule it
    # already applies to every other call and not something added here.
    def self.class_of(receiver_type)
      case receiver_type
      when Nominal then class_object(receiver_type)
      when Generic
        if class_object?(receiver_type)
          # **Declines**, and the reason is that this cannot tell a class
          # from a module while Ruby's answer differs:
          #
          #   $ ruby -e '
          #   module M; end
          #   class C; end
          #   p [M.class, C.class, Comparable.class]
          #   '
          #   # => [Module, Class, Module]
          #   # ruby 3.4.10
          #
          # The first version of this branch answered `Class` for every
          # class object, which is right for `C` and wrong for `M` and
          # for every module a project writes. `Types` holds no index and
          # so cannot ask which it has, and section 0 ranks a wrong answer
          # below no answer -- so the branch that cannot tell says
          # nothing. Nothing regresses: before `024.85` this whole
          # question had no answer at all.
          #
          # The pasted session above is why. The one this replaced showed
          # only `class W; end; p W.class`, so the module case was never
          # checked against the interpreter and the branch read as
          # correct.
          nil
        else
          base = base_nominal(receiver_type)
          base && class_object(base)
        end
      when NilType then class_object(Nominal.new(name: "NilClass"))
      when Union
        members = receiver_type.members.map { |member| class_of(member) }
        normalize_union(members) if members.none?(&:nil?)
      end
    end

    # The call shape `class_of` answers about: `x.class`, written with a
    # receiver and nothing else. Both extra guards decline, and Ruby says
    # they are not the same case:
    #
    #   $ ruby -e '
    #   s = "x"
    #   p(s.class { })
    #   begin; p s.class(1); rescue ArgumentError => e; p e.class; end
    #   '
    #   # => String
    #   # => ArgumentError
    #   # ruby 3.4.10
    #
    # An argument means this is not `Object#class`, which takes none, so
    # the call is somebody's own method or a mistake and this table does
    # not know its return type. A block is merely *ignored* by
    # `Object#class`, so declining there gives up an answer Ruby would
    # have -- a missing answer rather than a wrong one, which is the
    # direction section 0 asks for, and it keeps this predicate the plain
    # shape it claims to be rather than a partial model of Ruby's
    # argument rules.
    def self.class_call?(node)
      node.receiver && node.name == :class && node.arguments.nil? && node.block.nil?
    end

    # A normalized set of >= 2 distinct member types. Never nests another
    # Union — use Types.normalize_union to build one safely.
    Union = Data.define(:members) do
      def to_s
        members.map(&:to_s).join(" | ")
      end
    end

    # A placeholder used only *inside* a Semantic::GenericRule template
    # (Task 011) — e.g. `T` standing for a container's element type, `U`
    # for a block's return type. Never appears in a final, resolved type;
    # Semantic::GenericRuleRegistry substitutes every TypeParameter away
    # before returning a result.
    TypeParameter = Data.define(:name) do
      def to_s
        name
      end
    end

    # A block/proc's shape: `parameters` is the ordered list of types its
    # own parameters are bound to, `return_type` is what its body
    # evaluates to. Used both as a GenericRule template (with
    # TypeParameter placeholders) and as the concrete, evaluated shape a
    # caller reports back after actually running a block's body through
    # the same type evaluator (Task 011).
    ProcType = Data.define(:parameters, :return_type) do
      def to_s
        "(#{parameters.map(&:to_s).join(', ')}) -> #{return_type}"
      end
    end

    module_function

    # The class a value's type is an instance of, or nil when the type does
    # not name one. A `Generic` over a real class reads as that class:
    # `Hash[Unknown]` is a Hash, and a method the workspace adds to `Hash`
    # applies to it.
    #
    # Lives here because three separate consumers needed it and each was
    # taught separately, a release apart: MethodResolver in 0.1.8, then
    # LocalInferencer's instance-level and observed-evidence paths, then
    # the diagnostics engine -- each time as a fresh bug, because there was
    # no single place saying what a Generic receiver means.
    def base_nominal(type)
      case type
      when Nominal then type
      when Generic
        Nominal.new(name: type.name) unless INTERNAL_GENERIC_NAMES.include?(type.name)
      end
    end

    # Flattens nested unions, removes duplicate members (structural
    # equality — Nominal/Union are Data classes), and unwraps to a bare
    # type when only one distinct member remains. Member order is
    # normalized so equivalent unions compare equal regardless of the
    # order branches were visited in.
    def normalize_union(types)
      flattened = types.flat_map { |t| t.is_a?(Union) ? t.members : [t] }
      # `Hash` and `Hash[Unknown]` say the same thing, so a union holding
      # both presents a single type as two alternatives. Reachable from any
      # union of a bare container literal with a call returning the same
      # container generically, e.g.
      # `reduce({}) { |acc, x| acc.merge(x => x) }`.
      #
      # The *generic* form survives, for two reasons. It is what the rest
      # of the engine already produces for a container whose element type
      # is unknown -- `[]` infers `Array[Unknown]` -- so keeping the plain
      # one made the same value render two different ways depending on the
      # path it arrived by (024.2). And only the generic form carries a
      # type argument for GenericRuleRegistry to dispatch on, so collapsing
      # to the plain one threw away the ability to resolve anything called
      # on the result.
      generic_unknown_names = flattened.filter_map do |t|
        t.name if t.is_a?(Generic) && t.type_arg.is_a?(Unknown)
      end
      flattened = flattened.reject do |t|
        t.is_a?(Nominal) && generic_unknown_names.include?(t.name)
      end
      unique = flattened.uniq.sort_by { |t| t.to_s }

      case unique.size
      when 0 then UNKNOWN
      when 1 then unique.first
      else Union.new(members: unique.freeze)
      end
    end

    # Removes a `nil` member from a (possibly union) type, e.g. after a
    # truthiness guard. A type that was exactly `nil` widens to Unknown,
    # since asserting truthiness of something statically known to be nil
    # only would indicate dead code, not a real narrower type.
    def remove_nil(type)
      case type
      when NilType then UNKNOWN
      when Union then normalize_union(type.members.reject { |m| m == NIL })
      else type
      end
    end

    # Replaces every TypeParameter in `type` with its binding from
    # `bindings` (a name-String => Types value Hash), recursing through
    # Generic/Union/ProcType — shared by Semantic::GenericRuleRegistry
    # (Task 011's built-in container rules) and Signatures::Environment
    # (Task 012's RBS/RBI-sourced signatures), since both resolve a
    # template return type against a receiver's actual bound type
    # argument the same way. An unbound TypeParameter (no entry in
    # `bindings`) widens to Unknown rather than leaking a placeholder
    # name into a final, caller-visible type.
    def substitute(type, bindings)
      case type
      when TypeParameter then bindings.fetch(type.name, UNKNOWN)
      when Generic then Generic.new(name: type.name, type_arg: substitute(type.type_arg, bindings))
      when Union then normalize_union(type.members.map { |member| substitute(member, bindings) })
      when ProcType
        ProcType.new(parameters: type.parameters.map { |p| substitute(p, bindings) },
                      return_type: substitute(type.return_type, bindings))
      else type
      end
    end
  end
end
