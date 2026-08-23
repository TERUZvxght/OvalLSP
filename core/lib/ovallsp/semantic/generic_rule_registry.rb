# frozen_string_literal: true

require_relative "../types"

module Ovallsp
  module Semantic
    # One built-in generic method rule: how a call to `method_name` on a
    # `Types::Generic` receiver whose name is in `receiver_pattern`
    # resolves its return type.
    #
    # - receiver_pattern: an Array of Types::Generic#name strings this
    #   rule applies to (e.g. `%w[Array Relation CollectionProxy]` — the
    #   same rule usually covers every Enumerable-ish container the same
    #   way).
    # - parameters: reserved for future non-block argument type checking
    #   (e.g. `Array.new(3, default)`); unused by every built-in rule
    #   registered so far — Task 011's scope is block-taking methods.
    # - block_type: nil for a rule that takes no block (`to_a`, `build`),
    #   or a Types::ProcType template (using Types::TypeParameter
    #   placeholders, conventionally `T` for the receiver's own element
    #   type and `U` for the block's return type) describing what the
    #   block is called with.
    # - return_template: the resolved type, expressed with the same
    #   TypeParameter placeholders — GenericRuleRegistry#resolve
    #   substitutes them with the actual bound types. `:receiver` (a bare
    #   Symbol, not a Types value) is a special template meaning "return
    #   the receiver's own type unchanged" (`each`'s effective Ruby return
    #   value), since a single static template can't otherwise express
    #   "whichever of Array/Relation/CollectionProxy was actually called".
    GenericRule = Data.define(:receiver_pattern, :method_name, :parameters, :block_type, :return_template)

    # Resolves a generic container method call (`Array[User]#map`,
    # `Relation[Order]#first`, ...) to a concrete return type via a small,
    # data-driven rule table rather than a hardcoded case statement per
    # method — "built-in generic method rules"
    # (docs/design/tasks/011-generic-types-and-block-inference.md).
    #
    # Deliberately does not evaluate a block's body itself: `resolve`'s
    # `block:` argument (when the matched rule needs one) is a *callable*
    # — `->(bound_param_types) { evaluated_return_type }` — the caller
    # (LocalInferencer/MethodAnalyzer, whichever owns the actual AST
    # evaluator and its local variable environment) supplies. This keeps
    # the registry itself free of any dependency on how blocks get
    # evaluated, matching Task 009's same "construction vs query" split.
    class GenericRuleRegistry
      def initialize
        @rules = []
      end

      def register(rule)
        @rules << rule
      end

      # Returns nil if no rule matches `receiver_type`/`method_name` (the
      # caller should fall back to whatever other resolution it has), or
      # if a matched rule needs a block but none was given.
      def resolve(receiver_type:, method_name:, arguments: [], block: nil)
        rule = find_rule(receiver_type, method_name)
        return nil unless rule

        bindings = { "T" => receiver_type.type_arg }

        # Positional arguments bind their rule's type parameters first, so
        # a method whose result comes from a seed value (`reduce(0)`,
        # `each_with_object({})`) is answered from that argument rather
        # than from the block's return type.
        bind_argument_parameters(rule, arguments, bindings)

        if rule.block_type
          return nil unless block

          bound_params = rule.block_type.parameters.map { |template| Types.substitute(template, bindings) }
          bind_block_result(rule, block.call(bound_params), bindings)
        end

        return receiver_type if rule.return_template == :receiver

        Types.substitute(rule.return_template, bindings)
      end

      # The block parameter types a matching rule would bind (e.g. `T` for
      # `map`), without evaluating the block or resolving a return type —
      # used to answer a position query that lands inside a block's
      # parameter list or body before/without evaluating the block itself.
      # Returns nil if no rule matches or the matched rule takes no block.
      def block_parameter_types(receiver_type:, method_name:, arguments: [])
        rule = find_rule(receiver_type, method_name)
        return nil unless rule&.block_type

        # Binds arguments exactly as #resolve does. Without this, an
        # argument-bound rule answered two different things for the same
        # expression depending on where the cursor was: hovering
        # `reduce(0) { |sum, u| ... }` as a whole said Integer, while
        # hovering `sum` said Unknown -- and the block body was walked
        # with `U` unbound while #resolve had evaluated it with `U` bound.
        bindings = { "T" => receiver_type.type_arg }
        bind_argument_parameters(rule, arguments, bindings)
        rule.block_type.parameters.map { |template| Types.substitute(template, bindings) }
      end

      private

      # Where a block's return type goes is the rule's own statement, not
      # a fixed convention: `block_type.return_type` already says it. A
      # rule whose block result Ruby discards (`each`, `select`,
      # `each_with_object`) declares Unknown and contributes nothing.
      #
      # Hardcoding `bindings["U"] ||= block_result` instead was wrong in
      # both directions. It bound U for rules that do not use it, and --
      # once `reduce`/`inject` started binding U from their seed -- it
      # made the seed *beat* the block, which is backwards: Ruby returns
      # the block's last value and falls back to the seed only for an
      # empty receiver. `[1].reduce(0) { |a, x| a.to_s }` answered
      # `Integer` where Ruby returns `String`, and
      # `line_items.reduce(0) { |sum, i| sum + i.amount }` answered
      # `Integer` for a BigDecimal sum -- confidently wrong, which is
      # worse than the Unknown these rules were added to replace. Both
      # outcomes are possible at runtime, so the honest answer is their
      # union.
      # Unknown is dropped from the union rather than carried in it, the
      # same way `resolve_call` filters it out of a Union receiver's
      # member results and the `.new` ladder treats it as "no answer".
      # `X | Unknown` is strictly less informative than either member: it
      # offers the reader two alternatives where the truth is
      # "unconstrained", and it is the *common* case, not an edge one --
      # `acc << x` on an untyped accumulator, or any call this engine
      # cannot resolve, produces it. It degrades completion too, since a
      # member is marked conditional unless it exists on every union
      # member and nothing exists on Unknown.
      def bind_block_result(rule, block_result, bindings)
        target = rule.block_type.return_type
        return unless target.is_a?(Types::TypeParameter)

        candidates = [bindings[target.name], block_result].compact
        informative = candidates.reject { |type| type.is_a?(Types::Unknown) }
        bindings[target.name] =
          informative.empty? ? candidates.first : Types.normalize_union(informative)
      end

      def bind_argument_parameters(rule, arguments, bindings)
        rule.parameters.each_with_index do |template, index|
          next unless template.is_a?(Types::TypeParameter)

          argument = arguments[index]
          bindings[template.name] = argument if argument
        end
      end

      def find_rule(receiver_type, method_name)
        return nil unless receiver_type.is_a?(Types::Generic)

        @rules.find { |rule| rule.method_name == method_name && rule.receiver_pattern.include?(receiver_type.name) }
      end
    end

    # The container methods Task 011 scopes in: Array/Relation/CollectionProxy
    # share the same `map`/`each`/`select`/`filter_map`/`find` shapes (all
    # Enumerable-like), plus the Active Record-specific `first`/`first!`
    # (handled separately by LocalInferencer's pre-existing Task 007 logic,
    # not duplicated here), `find_each`, `build`, and `to_a`. Verified
    # against real Rails' actual `find_each`/`build`/`to_a` return values
    # via a live probe rather than assumed
    # (docs/design/tasks/011-generic-types-and-block-inference.md "実際の
    # 戻り値と一致するようRails APIをfixtureで確認する").
    module BuiltInGenericRules
      module_function

      ENUMERABLE_LIKE = %w[Array Relation CollectionProxy].freeze

      # `024.87`. Every one of these answered `Post::ActiveRecord_Relation`
      # under ActiveRecord 8.1.3.1 with an in-memory sqlite3 and
      # `rel = Post.where(title: "x")` -- probed, not assumed.
      RELATION_RETURNING = %i[
        where order limit offset includes joins distinct group having
        preload eager_load references reorder readonly none unscope
      ].freeze

      def install(registry)
        t = Types::TypeParameter.new(name: "T")
        u = Types::TypeParameter.new(name: "U")

        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :map, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: u),
                             return_template: Types::Generic.new(name: "Array", type_arg: u)
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :select, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: Types::UNKNOWN),
                             return_template: Types::Generic.new(name: "Array", type_arg: t)
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :filter_map, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: u),
                             return_template: Types::Generic.new(name: "Array", type_arg: u)
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :find, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: Types::UNKNOWN),
                             return_template: Types.normalize_union([t, Types::NIL])
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :each, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: Types::UNKNOWN),
                             return_template: :receiver
                           ))
        # `024.87`. A relation stayed a relation for exactly one hop:
        # `Post.where(a: 1)` inferred `Relation[Post]` and
        # `Post.where(a: 1).where(b: 2)` inferred nothing, because the
        # relation-*returning* methods had no rule. The cost was not only
        # hover -- the undefined-method check switched off at the second
        # link of the most common Rails expression there is.
        #
        # **Probed against real Rails rather than assumed**, the same way
        # `find_each`/`build`/`to_a` beside them were. ActiveRecord
        # 8.1.3.1, in-memory sqlite3, `rel = Post.where(title: "x")`:
        # every one of these answered `Post::ActiveRecord_Relation`.
        #
        # `select` is deliberately not here. On a Relation it returns a
        # Relation without a block and an Array with one, and the
        # `ENUMERABLE_LIKE` rule above already covers the block form;
        # adding a relation rule would make the answer depend on which
        # rule matched first.
        RELATION_RETURNING.each do |method_name|
          registry.register(GenericRule.new(
                               receiver_pattern: %w[Relation CollectionProxy], method_name: method_name,
                               parameters: [], block_type: nil, return_template: :receiver
                             ))
        end

        # Real Rails' Relation#find_each returns nil (it's a void-ish
        # batched-iteration method, unlike #each).
        registry.register(GenericRule.new(
                             receiver_pattern: %w[Relation], method_name: :find_each, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: Types::UNKNOWN),
                             return_template: Types::NIL
                           ))
        # These bind their type parameter from the *seed argument*, not
        # from the block's element type: `reduce`/`inject` start from the
        # accumulator seed, `each_with_object` returns the object handed
        # in. They differ in what the block contributes, and each says so
        # through its own `return_type`: `reduce`/`inject` declare `u`,
        # because the block's value *becomes* the next accumulator and is
        # what Ruby returns for a non-empty receiver (the seed survives
        # only for an empty one, hence the union); `each_with_object`
        # declares Unknown, because Ruby discards its block's value. With no rule of their own they fell through to RBS, whose
        # method-level type parameters this engine does not bind, so they
        # degraded to a bare `Unknown` once overload narrowing started
        # selecting the block-taking overload. `reduce` is common enough
        # that this is a visible hover regression.
        #
        # `parameters` finally carries its documented meaning here -- it
        # was already part of GenericRule, reserved for exactly this, and
        # `resolve` already accepted an `arguments:` it never consulted.
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :reduce, parameters: [u],
                             block_type: Types::ProcType.new(parameters: [u, t], return_type: u),
                             return_template: u
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :inject, parameters: [u],
                             block_type: Types::ProcType.new(parameters: [u, t], return_type: u),
                             return_template: u
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: ENUMERABLE_LIKE, method_name: :each_with_object, parameters: [u],
                             block_type: Types::ProcType.new(parameters: [t, u], return_type: Types::UNKNOWN),
                             return_template: u
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: %w[Relation CollectionProxy], method_name: :to_a, parameters: [],
                             block_type: nil, return_template: Types::Generic.new(name: "Array", type_arg: t)
                           ))
        registry.register(GenericRule.new(
                             receiver_pattern: %w[CollectionProxy], method_name: :build, parameters: [],
                             block_type: nil, return_template: t
                           ))
      end
    end
  end
end
