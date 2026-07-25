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

        if rule.block_type
          return nil unless block

          bound_params = rule.block_type.parameters.map { |template| Types.substitute(template, bindings) }
          bindings["U"] = block.call(bound_params)
        end

        return receiver_type if rule.return_template == :receiver

        Types.substitute(rule.return_template, bindings)
      end

      # The block parameter types a matching rule would bind (e.g. `T` for
      # `map`), without evaluating the block or resolving a return type —
      # used to answer a position query that lands inside a block's
      # parameter list or body before/without evaluating the block itself.
      # Returns nil if no rule matches or the matched rule takes no block.
      def block_parameter_types(receiver_type:, method_name:)
        rule = find_rule(receiver_type, method_name)
        return nil unless rule&.block_type

        bindings = { "T" => receiver_type.type_arg }
        rule.block_type.parameters.map { |template| Types.substitute(template, bindings) }
      end

      private

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
        # Real Rails' Relation#find_each returns nil (it's a void-ish
        # batched-iteration method, unlike #each).
        registry.register(GenericRule.new(
                             receiver_pattern: %w[Relation], method_name: :find_each, parameters: [],
                             block_type: Types::ProcType.new(parameters: [t], return_type: Types::UNKNOWN),
                             return_template: Types::NIL
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
