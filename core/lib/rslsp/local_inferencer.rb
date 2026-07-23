# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "models/model_registry"

module Rslsp
  # Minimal local type inference over a single document's top-level
  # statements (docs/design/tasks/004-type-model-and-local-inference.md).
  # Deliberately narrow: literals, `Class.new`, local variable bindings,
  # if/unless/ternary branch unions, truthy/nil narrowing after guard
  # clauses, and safe navigation. No method body summaries or RBS yet.
  #
  # Task 007 adds an optional Models::ModelRegistry: when a receiver
  # resolves to a known Active Record model, `.find`/`.find_by`/`.where`,
  # association accessors, DB column accessors, and
  # Relation/CollectionProxy#first all resolve through it instead of
  # falling back to Unknown.
  #
  # Re-parses the document on demand and discards the AST when done; the
  # workspace index never retains it (docs/02-architecture.md).
  class LocalInferencer
    # A defensive substitute for a wall-clock timeout: wall-clock timeouts
    # are flaky under test and unsafe to interrupt mid-recursion in Ruby.
    # Instead, cap the number of node visits per query; exceeding it widens
    # to Unknown exactly like a real timeout would
    # (docs/02-architecture.md 障害分離 table: "type inference timeout ->
    # Unknownへwiden").
    class BudgetExceeded < StandardError; end

    TERMINAL_NODE_TYPES = [Prism::ReturnNode, Prism::NextNode, Prism::BreakNode].freeze
    RELATION_LIKE = ["Relation", "CollectionProxy"].freeze

    def initialize(max_steps: 5000, model_registry: Models::ModelRegistry.new)
      @max_steps = max_steps
      @model_registry = model_registry
    end

    # `document` is an Rslsp::TextDocument; `position` is an LSP
    # { line:, character: } position (UTF-16). Never raises — returns
    # Types::UNKNOWN for anything unresolved, out of budget, or on
    # unexpected parser input.
    def infer_at(document, position)
      offset = document.position_to_char_offset(position)
      result = Prism.parse(document.text)
      @steps = 0

      locate(result.value.statements, offset, {})
    rescue BudgetExceeded, StandardError
      Types::UNKNOWN
    end

    private

    def step!
      @steps += 1
      raise BudgetExceeded if @steps > @max_steps
    end

    def contains?(location, offset)
      location.start_offset <= offset && offset <= location.end_offset
    end

    # Finds the most specific node containing `offset`, threading (and
    # mutating) `env` exactly as eval_type does, so bindings and narrowing
    # accumulate correctly on the way down to the target.
    def locate(node, offset, env)
      step!
      return Types::UNKNOWN if node.nil?

      case node
      when Prism::StatementsNode
        locate_in_statements(node, offset, env)
      when Prism::LocalVariableWriteNode
        if contains?(node.value.location, offset)
          result = locate(node.value, offset, env)
          env[node.name] = eval_type(node.value, env)
          result
        else
          eval_type(node, env)
        end
      when Prism::CallNode
        if node.receiver && contains?(node.receiver.location, offset)
          locate(node.receiver, offset, env)
        else
          eval_type(node, env)
        end
      when Prism::IfNode, Prism::UnlessNode
        locate_in_conditional(node, offset, env)
      when Prism::DefNode
        contains?(node.location, offset) ? locate(node.body, offset, {}) : Types::UNKNOWN
      else
        eval_type(node, env)
      end
    end

    def locate_in_statements(node, offset, env)
      result = Types::UNKNOWN
      node.body.each do |stmt|
        if contains?(stmt.location, offset)
          result = locate(stmt, offset, env)
        else
          eval_type(stmt, env)
        end
        apply_guard_narrowing(stmt, env)
      end
      result
    end

    def locate_in_conditional(node, offset, env)
      if node.predicate && contains?(node.predicate.location, offset)
        return locate(node.predicate, offset, env)
      end

      assume = node.is_a?(Prism::IfNode) ? :truthy : :falsy
      if node.statements && contains?(node.statements.location, offset)
        return locate(node.statements, offset, narrowed(env, node.predicate, assume))
      end

      subsequent = node.consequent
      if subsequent && contains?(subsequent.location, offset)
        else_statements = subsequent.respond_to?(:statements) ? subsequent.statements : subsequent
        return locate(else_statements, offset, narrowed(env, node.predicate, negate(assume)))
      end

      eval_type(node, env)
    end

    # Pure with respect to `env`: reads bindings but never mutates them,
    # except for LocalVariableWriteNode, which intentionally does (an
    # assignment's whole point is to bind — see docs' 5.1 "ローカル推論").
    def eval_type(node, env)
      step!

      case node
      when nil then Types::NIL
      when Prism::StatementsNode
        node.body.reduce(Types::NIL) { |_, stmt| eval_type(stmt, env) }
      when Prism::LocalVariableWriteNode
        env[node.name] = eval_type(node.value, env)
      when Prism::LocalVariableReadNode
        env.fetch(node.name, Types::UNKNOWN)
      when Prism::IntegerNode then Types::Nominal.new(name: "Integer")
      when Prism::FloatNode then Types::Nominal.new(name: "Float")
      when Prism::RationalNode then Types::Nominal.new(name: "Rational")
      when Prism::StringNode, Prism::InterpolatedStringNode then Types::Nominal.new(name: "String")
      when Prism::SymbolNode then Types::Nominal.new(name: "Symbol")
      when Prism::TrueNode, Prism::FalseNode then Types::Nominal.new(name: "Boolean")
      when Prism::NilNode then Types::NIL
      when Prism::ArrayNode then Types::Nominal.new(name: "Array")
      when Prism::HashNode then Types::Nominal.new(name: "Hash")
      when Prism::ParenthesesNode then eval_type(node.body, env)
      when Prism::CallNode then eval_call(node, env)
      when Prism::IfNode, Prism::UnlessNode then eval_conditional(node, env)
      else Types::UNKNOWN
      end
    end

    def eval_call(node, env)
      receiver_type = node.receiver && eval_type(node.receiver, env)
      base = resolve_call(node, receiver_type)

      node.respond_to?(:safe_navigation?) && node.safe_navigation? ? Types.normalize_union([base, Types::NIL]) : base
    end

    def resolve_call(node, receiver_type)
      if node.name == :new && constant_receiver?(node.receiver)
        return Types::Nominal.new(name: node.receiver.full_name)
      end

      class_level = constant_receiver?(node.receiver) && resolve_class_level_finder(node.receiver.full_name, node.name)
      return class_level if class_level

      instance_level = receiver_type && resolve_instance_level(receiver_type, node.name)
      return instance_level if instance_level

      Types::UNKNOWN
    end

    # `Model.find` -> Model, `Model.find_by` -> Model | nil,
    # `Model.where`/`Model.all` -> Relation[Model]
    # (docs/03-semantic-engine.md section 7.1).
    def resolve_class_level_finder(class_name, method_name)
      return nil unless @model_registry.known_model?(class_name)

      model_type = Types::Nominal.new(name: class_name)
      case method_name
      when :find then model_type
      when :find_by then Types.normalize_union([model_type, Types::NIL])
      when :where, :all then Types::Generic.new(name: "Relation", type_arg: model_type)
      end
    end

    def resolve_instance_level(receiver_type, method_name)
      case receiver_type
      when Types::Nominal
        resolve_model_member(receiver_type.name, method_name)
      when Types::Generic
        resolve_relation_member(receiver_type, method_name)
      when Types::Union
        resolve_union_member(receiver_type, method_name)
      end
    end

    # `user.company.orders` where `company` is `Company | nil`: resolves
    # against each non-nil member (docs/03-semantic-engine.md section 6,
    # "Union: 各memberで解決し、共通部分を優先する") and unions whatever
    # resolves. A bare (non-safe-navigation) call through a nilable receiver
    # is exactly the kind of code these acceptance examples are written to
    # infer through, so the nil member itself contributes nothing here.
    def resolve_union_member(union_type, method_name)
      resolved = union_type.members.filter_map do |member|
        next if member == Types::NIL

        resolve_instance_level(member, method_name)
      end
      return nil if resolved.empty?

      Types.normalize_union(resolved)
    end

    # Association accessors (`user.company`, `company.orders`) and DB
    # column accessors (`order.total`) on a known model instance.
    def resolve_model_member(model_name, method_name)
      return nil unless @model_registry.known_model?(model_name)

      if (assoc = @model_registry.association(model_name, method_name))
        target = Types::Nominal.new(name: assoc.class_name)
        case assoc.macro
        when :belongs_to
          assoc.optional ? Types.normalize_union([target, Types::NIL]) : target
        when :has_one
          Types.normalize_union([target, Types::NIL])
        when :has_many
          Types::Generic.new(name: "CollectionProxy", type_arg: target)
        end
      elsif (column = @model_registry.column(model_name, method_name))
        Types::Nominal.new(name: column.ruby_type)
      end
    end

    # `Relation[T]#first`/`CollectionProxy[T]#first` -> T | nil,
    # `#first!` -> T.
    def resolve_relation_member(generic_type, method_name)
      return nil unless RELATION_LIKE.include?(generic_type.name)

      case method_name
      when :first then Types.normalize_union([generic_type.type_arg, Types::NIL])
      when :first! then generic_type.type_arg
      end
    end

    def constant_receiver?(node)
      node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    end

    def eval_conditional(node, env)
      assume = node.is_a?(Prism::IfNode) ? :truthy : :falsy
      eval_type(node.predicate, env)

      then_type = node.statements ? eval_type(node.statements, narrowed(env, node.predicate, assume)) : Types::NIL

      subsequent = node.consequent
      else_type =
        if subsequent
          else_statements = subsequent.respond_to?(:statements) ? subsequent.statements : subsequent
          eval_type(else_statements, narrowed(env, node.predicate, negate(assume)))
        else
          Types::NIL
        end

      Types.normalize_union([then_type, else_type])
    end

    # If `stmt` is an if/unless where one branch unconditionally exits
    # (return/next/break) and the other is absent, the code after `stmt`
    # only runs via the surviving branch — so the outer `env` gets that
    # branch's narrowing applied for real, mutating it in place. This is
    # what makes `return unless user` narrow `user` for the rest of the
    # method (Task 004's headline acceptance criterion).
    def apply_guard_narrowing(stmt, env)
      return unless stmt.is_a?(Prism::IfNode) || stmt.is_a?(Prism::UnlessNode)
      return unless stmt.consequent.nil? # only the simple (no else) guard shape

      assume = stmt.is_a?(Prism::IfNode) ? :truthy : :falsy
      if exits_unconditionally?(stmt.statements)
        apply_narrowing!(env, stmt.predicate, negate(assume))
      elsif stmt.statements.nil? || stmt.statements.body.empty?
        # `if x; end` with an empty body: nothing to narrow either way.
        nil
      end
    end

    def exits_unconditionally?(statements)
      return false unless statements

      last = statements.body.last
      return false unless last

      TERMINAL_NODE_TYPES.any? { |klass| last.is_a?(klass) } ||
        (last.is_a?(Prism::CallNode) && last.receiver.nil? && last.name == :raise)
    end

    def narrowed(env, predicate, assume)
      copy = env.dup
      apply_narrowing!(copy, predicate, assume)
      copy
    end

    # Supports the pattern subset from docs/03-semantic-engine.md 5.3: a
    # bare local (`if user`), `x.nil?`, and `x.is_a?(Type)`. Anything else
    # is left alone rather than guessed at.
    def apply_narrowing!(env, predicate, assume)
      case predicate
      when Prism::LocalVariableReadNode
        env[predicate.name] = assume == :truthy ? Types.remove_nil(env[predicate.name]) : Types::NIL
      when Prism::CallNode
        apply_call_narrowing!(env, predicate, assume)
      end
    end

    def apply_call_narrowing!(env, predicate, assume)
      receiver = predicate.receiver
      return unless receiver.is_a?(Prism::LocalVariableReadNode)

      case predicate.name
      when :nil?
        env[receiver.name] = assume == :truthy ? Types::NIL : Types.remove_nil(env[receiver.name])
      when :is_a?, :kind_of?, :instance_of?
        return unless assume == :truthy

        arg = predicate.arguments&.arguments&.first
        env[receiver.name] = Types::Nominal.new(name: arg.full_name) if constant_receiver?(arg)
      end
    end

    def negate(assume)
      assume == :truthy ? :falsy : :truthy
    end
  end
end
