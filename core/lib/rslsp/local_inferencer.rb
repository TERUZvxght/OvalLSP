# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "models/model_registry"
require_relative "semantic/generic_rule_registry"

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
  # Task 011 adds array-literal element tracking (`[User.new]` is
  # `Array[User]`, not a bare `Array`) and Semantic::GenericRuleRegistry-
  # backed block inference for `map`/`select`/`filter_map`/`find`/`each`/
  # `find_each`/`to_a`/`build` across Array/Relation/CollectionProxy.
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
    # Array joins Relation/CollectionProxy here (Task 011): `#first`/
    # `#first!` mean the exact same thing on any of the three.
    RELATION_LIKE = ["Array", "Relation", "CollectionProxy"].freeze
    # Caps how many array-literal elements contribute to the inferred
    # element-type union before widening the whole array to Unknown
    # element type — "type argument explosion widening"
    # (docs/design/tasks/011-generic-types-and-block-inference.md). A
    # 200-element literal of 200 distinct types is not a realistic Ruby
    # array; it's almost certainly generated/data, not a case worth an
    # increasingly large Union over.
    MAX_ARRAY_ELEMENT_UNION = 8

    def initialize(max_steps: 5000, model_registry: Models::ModelRegistry.new, generic_rules: nil,
                   method_resolver: nil, method_analyzer: nil)
      @max_steps = max_steps
      @model_registry = model_registry
      @generic_rules = generic_rules || self.class.default_generic_rules
      # Both optional and nil-safe: a caller with no HierarchyIndex/
      # MethodResolver/MethodSummaryStore wired up yet (most unit tests,
      # every LocalInferencer built before Task 013) still gets exactly
      # the pre-existing behavior -- a plain (non-Active-Record) method
      # call simply stays Types::UNKNOWN, as it always has.
      @method_resolver = method_resolver
      @method_analyzer = method_analyzer
      @step_budget = max_steps
    end

    # A fresh registry per instance by default (registries are cheap and
    # stateless once built) rather than one shared mutable singleton — a
    # caller that wants to `register` an extra project-specific rule can
    # pass its own registry in without affecting every other
    # LocalInferencer instance.
    def self.default_generic_rules
      Semantic::GenericRuleRegistry.new.tap { |registry| Semantic::BuiltInGenericRules.install(registry) }
    end

    # `document` is an Rslsp::TextDocument; `position` is an LSP
    # { line:, character: } position (UTF-16). `initial_env` seeds bindings
    # before evaluation starts — Task 008 uses this to propagate a
    # controller action's instance variable types into a view's Ruby
    # regions. `max_steps` overrides the constructor's default for this
    # one call only (Task 013's QueryContext#budget, threaded down from a
    # single request rather than fixed per LocalInferencer instance).
    # Never raises — returns Types::UNKNOWN for anything unresolved, out
    # of budget, or on unexpected parser input.
    def infer_at(document, position, initial_env: {}, max_steps: nil)
      # Prism node locations are UTF-8 byte offsets, not Ruby character
      # offsets — using #position_to_char_offset here would select the
      # wrong node whenever a multibyte character appears anywhere before
      # the target position (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      offset = document.position_to_byte_offset(position)
      result = Prism.parse(document.text)
      @steps = 0
      @step_budget = max_steps || @max_steps

      locate(result.value.statements, offset, initial_env.dup)
    rescue BudgetExceeded, StandardError
      Types::UNKNOWN
    end

    # Walks every statement in `method_name`'s body (declared directly on
    # `owner_name`, per ParserService's SymbolId#owner convention) and
    # returns the type of each `@ivar` as of the end of the method — what a
    # view rendered after this action runs would see
    # (docs/design/tasks/008-controller-view-propagation.md). Returns {} if
    # the method can't be found or parsing fails; never raises.
    def infer_ivars_for_method(document, owner_name:, method_name:)
      method_node = find_method_node(document, owner_name, method_name)
      return {} unless method_node&.body

      @steps = 0
      @step_budget = @max_steps
      env = {}
      eval_type(method_node.body, env)
      # Symbol-keyed (":@user", not "@user") to match how Prism names
      # InstanceVariableReadNode/WriteNode, so this can be passed straight
      # back in as another call's `initial_env` without re-keying.
      env.select { |key, _| key.to_s.start_with?("@") }
    rescue BudgetExceeded, StandardError
      {}
    end

    # Finds a literal `render :name` / `render "name"` / `render "dir/name"`
    # call anywhere in `method_name`'s body and returns its target as a
    # string, or nil if there's no such call (or it's not statically
    # resolvable — dynamic render strings are out of scope). Used to
    # propagate ivars from an action into a *different* action's view when
    # that action explicitly renders it.
    def find_static_render_target(document, owner_name:, method_name:)
      method_node = find_method_node(document, owner_name, method_name)
      return nil unless method_node&.body

      @steps = 0
      @step_budget = @max_steps
      RenderTargetFinder.new.tap { |finder| method_node.body.accept(finder) }.target
    rescue StandardError
      nil
    end

    private

    def find_method_node(document, owner_name, method_name)
      result = Prism.parse(document.text)
      locator = MethodLocator.new(owner_name, method_name.to_s)
      result.value.accept(locator)
      locator.found
    end

    def step!
      @steps += 1
      raise BudgetExceeded if @steps > @step_budget
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
      when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode
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
        elsif node.block.is_a?(Prism::BlockNode) && contains?(node.block.location, offset)
          locate_in_block(node, offset, env)
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

    # A position inside a block (its parameter list or its body) needs its
    # own nested env, built the same way #resolve_generic_call's block
    # binding does — but without running the block's body, since we don't
    # yet know which subnode the caller actually wants evaluated. Falls
    # back to the whole call's own type when the receiver isn't a
    # generic-rule-backed container (nothing to bind block params to).
    def locate_in_block(node, offset, env)
      receiver_type = node.receiver && eval_type(node.receiver, env)
      nested_env = block_nested_env(node, receiver_type, env)
      return eval_type(node, env) unless nested_env

      param_node = block_parameter_node_at(node.block, offset)
      return nested_env.fetch(param_node.name, Types::UNKNOWN) if param_node

      locate(node.block.body, offset, nested_env)
    end

    def block_nested_env(node, receiver_type, env)
      return nil unless receiver_type.is_a?(Types::Generic)

      param_types = @generic_rules.block_parameter_types(receiver_type: receiver_type, method_name: node.name)
      return nil unless param_types

      nested_env = env.dup
      block_parameter_names(node.block).each_with_index do |name, index|
        nested_env[name] = param_types[index] || Types::UNKNOWN
      end
      nested_env
    end

    def block_parameter_node_at(block_node, offset)
      params = block_node.parameters
      return nil unless params.is_a?(Prism::BlockParametersNode)

      params.parameters&.requireds&.find { |p| p.respond_to?(:name) && contains?(p.location, offset) }
    end

    def locate_in_statements(node, offset, env)
      result = Types::UNKNOWN
      node.body.each do |stmt|
        if contains?(stmt.location, offset)
          result = locate(stmt, offset, env)
        else
          # If `stmt` is a conditional, eval_type's own branch-merge (see
          # #eval_conditional) already folds its surviving branches'
          # bindings into `env` in place — nothing further needed here.
          eval_type(stmt, env)
        end
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
        else_env = narrowed(env, node.predicate, negate(assume))
        # An `elsif` is another IfNode, not an ElseNode — recursing through
        # #locate lets it check its *own* predicate instead of treating its
        # then-branch as an unconditional else.
        return locate(subsequent, offset, else_env) if subsequent.is_a?(Prism::IfNode)
        return locate(subsequent.statements, offset, else_env) if subsequent.statements
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
      when Prism::InstanceVariableWriteNode
        env[node.name] = eval_type(node.value, env)
      when Prism::InstanceVariableReadNode
        env.fetch(node.name, Types::UNKNOWN)
      when Prism::IntegerNode then Types::Nominal.new(name: "Integer")
      when Prism::FloatNode then Types::Nominal.new(name: "Float")
      when Prism::RationalNode then Types::Nominal.new(name: "Rational")
      when Prism::StringNode, Prism::InterpolatedStringNode then Types::Nominal.new(name: "String")
      when Prism::SymbolNode then Types::Nominal.new(name: "Symbol")
      when Prism::TrueNode, Prism::FalseNode then Types::Nominal.new(name: "Boolean")
      when Prism::NilNode then Types::NIL
      when Prism::ArrayNode then eval_array(node, env)
      when Prism::HashNode then Types::Nominal.new(name: "Hash")
      when Prism::ParenthesesNode then eval_type(node.body, env)
      when Prism::CallNode then eval_call(node, env)
      when Prism::IfNode, Prism::UnlessNode then eval_conditional(node, env)
      else Types::UNKNOWN
      end
    end

    # Elements beyond #MAX_ARRAY_ELEMENT_UNION contribute to a widened
    # (Unknown) element type rather than an ever-growing Union — "type
    # argument explosion widening". An empty array literal has no
    # evidence for its element type at all, so it stays Unknown too
    # (`[]` alone can't say what it's an array *of*).
    def eval_array(node, env)
      return Types::Generic.new(name: "Array", type_arg: Types::UNKNOWN) if node.elements.empty?
      return Types::Generic.new(name: "Array", type_arg: Types::UNKNOWN) if node.elements.size > MAX_ARRAY_ELEMENT_UNION

      element_type = Types.normalize_union(node.elements.map { |element| eval_type(element, env) })
      Types::Generic.new(name: "Array", type_arg: element_type)
    end

    def eval_call(node, env)
      receiver_type = node.receiver && eval_type(node.receiver, env)
      base = resolve_call(node, receiver_type, env)

      node.respond_to?(:safe_navigation?) && node.safe_navigation? ? Types.normalize_union([base, Types::NIL]) : base
    end

    def resolve_call(node, receiver_type, env)
      if node.name == :new && constant_receiver?(node.receiver)
        return Types::Nominal.new(name: node.receiver.full_name)
      end

      class_level = constant_receiver?(node.receiver) && resolve_class_level_finder(node.receiver.full_name, node.name)
      return class_level if class_level

      generic = receiver_type && resolve_generic_call(node, receiver_type, env)
      return generic if generic

      instance_level = receiver_type && resolve_instance_level(receiver_type, node.name)
      return instance_level if instance_level

      Types::UNKNOWN
    end

    # Block-taking (and a couple of blockless) generic container methods
    # go through Semantic::GenericRuleRegistry first — `#first`/`#first!`
    # deliberately stay on the older #resolve_relation_member path just
    # below instead of being duplicated into a rule, since they need no
    # block and no template substitution.
    #
    # A nested block gets its own env *copy* (`env.dup`), never the outer
    # env directly — this is what keeps an inner block's parameter
    # binding from leaking into (or shadowing) the outer scope's own
    # bindings once evaluation returns to it ("nested blockで外側binding
    # を壊さない").
    def resolve_generic_call(node, receiver_type, env)
      return nil unless receiver_type.is_a?(Types::Generic)

      block_callable =
        if node.block.is_a?(Prism::BlockNode)
          ->(bound_params) { eval_block(node.block, bound_params, env) }
        end

      @generic_rules.resolve(receiver_type: receiver_type, method_name: node.name, block: block_callable)
    end

    def eval_block(block_node, bound_params, outer_env)
      nested_env = outer_env.dup
      block_parameter_names(block_node).each_with_index do |name, index|
        nested_env[name] = bound_params[index] || Types::UNKNOWN
      end

      eval_type(block_node.body, nested_env)
    end

    # Destructuring parameters (`|(a, b)|`) are out of scope
    # ("destructuringの完全対応") and simply contribute no binding — the
    # block body just sees Unknown for whatever it references from them,
    # same as any other unresolved local.
    def block_parameter_names(block_node)
      params = block_node.parameters
      case params
      when Prism::NumberedParametersNode
        (1..params.maximum).map { |i| :"_#{i}" }
      when Prism::BlockParametersNode
        params.parameters&.requireds&.filter_map { |p| p.name if p.respond_to?(:name) } || []
      else
        []
      end
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
        resolve_model_member(receiver_type.name, method_name) || resolve_source_method_member(receiver_type, method_name)
      when Types::Generic
        resolve_relation_member(receiver_type, method_name)
      when Types::Union
        resolve_union_member(receiver_type, method_name)
      end
    end

    # A plain, hand-written instance method (not an Active Record column/
    # association, which #resolve_model_member already handles) resolves
    # through Semantic::MethodResolver (Task 009, ancestor-aware lookup)
    # and Semantic::MethodAnalyzer (Task 010, body-source return-type
    # inference with its own call-chain recursion and cache) when both are
    # wired up. This is what makes a call chain like
    # `current_user.company.orders.first.total` keep resolving past the
    # first hop instead of widening to Unknown the moment it leaves
    # Active Record's own DSL surface. Nil-safe: either dependency being
    # absent (most unit tests, anything predating Task 013's Server
    # wiring) just skips this and falls through to Unknown, exactly as
    # before this method existed.
    def resolve_source_method_member(receiver_type, method_name)
      return nil unless @method_resolver && @method_analyzer

      candidate = @method_resolver.resolve(receiver_type: receiver_type, name: method_name).min_by(&:lookup_rank)
      return nil unless candidate

      @method_analyzer.summarize(symbol_id: candidate.symbol_id).return_type
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
        base = Types::Nominal.new(name: column.ruby_type)
        column.nullable ? Types.normalize_union([base, Types::NIL]) : base
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

    # One branch's outcome: the type its body evaluates to, the (narrowed,
    # possibly-mutated) environment as of its end, and whether it
    # unconditionally exits (return/next/break/raise) — a terminated
    # branch's bindings never reach code after the conditional, so
    # #merge_branches_into! excludes it entirely (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    BranchOutcome = Struct.new(:type, :env, :terminated)
    private_constant :BranchOutcome

    # Evaluates both branches on their own narrowed environment *copies*,
    # unions their types for this expression's own value, and then folds
    # whichever branches survive (don't unconditionally exit) back into
    # the caller's `env` — mutating it in place, the same way a plain
    # assignment does. This is what makes `if c; @user = User.new; else;
    # @user = Admin.new; end` leave `@user: User | Admin` visible after
    # the conditional, and (as a special case where only one branch
    # survives) is also what makes `return unless user` narrow `user` for
    # the rest of the method.
    def eval_conditional(node, env)
      assume = node.is_a?(Prism::IfNode) ? :truthy : :falsy
      eval_type(node.predicate, env)

      then_outcome = evaluate_then_branch(node, env, assume)
      else_outcome = evaluate_else_branch(node, env, assume)

      merge_branches_into!(env, [then_outcome, else_outcome])
      Types.normalize_union([then_outcome.type, else_outcome.type])
    end

    def evaluate_then_branch(node, env, assume)
      branch_env = narrowed(env, node.predicate, assume)
      type = node.statements ? eval_type(node.statements, branch_env) : Types::NIL
      terminated = node.statements ? exits_unconditionally?(node.statements) : false
      BranchOutcome.new(type, branch_env, terminated)
    end

    def evaluate_else_branch(node, env, assume)
      branch_env = narrowed(env, node.predicate, negate(assume))
      subsequent = node.consequent

      if subsequent.nil?
        BranchOutcome.new(Types::NIL, branch_env, false)
      elsif subsequent.is_a?(Prism::IfNode)
        # `elsif` is another IfNode, not an ElseNode. Recursing through
        # eval_type lets it check its *own* predicate and perform its own
        # branch merge into `branch_env`, instead of treating its
        # then-branch as an unconditional else (a real, pre-existing bug
        # this task also fixes). Its own termination is folded in as
        # "not terminated" conservatively — precisely tracking whether
        # every arm of a whole elsif chain terminates isn't worth the
        # extra complexity for what Task 008.5 asks for.
        BranchOutcome.new(eval_type(subsequent, branch_env), branch_env, false)
      else
        statements = subsequent.statements
        type = statements ? eval_type(statements, branch_env) : Types::NIL
        terminated = statements ? exits_unconditionally?(statements) : false
        BranchOutcome.new(type, branch_env, terminated)
      end
    end

    # Unions each variable's type across every branch that doesn't
    # unconditionally exit, and writes the result into `env` — the single
    # merge point for both plain branch-merging and guard-clause
    # narrowing (`return unless x`), which is just the special case where
    # only one branch survives. A key a surviving branch never touched
    # falls back to nil, not Unknown: if we're merging branches at all, we
    # fully analyzed this scope, so "never assigned on this path" is
    # exactly what real Ruby does with a local or instance variable that's
    # reachable but never written — not missing information.
    def merge_branches_into!(env, outcomes)
      surviving = outcomes.reject(&:terminated)
      return if surviving.empty? # every branch exits; nothing reaches code after this

      keys = surviving.flat_map { |outcome| outcome.env.keys }.uniq
      keys.each do |key|
        types = surviving.map { |outcome| outcome.env.fetch(key) { env.fetch(key, Types::NIL) } }
        env[key] = Types.normalize_union(types)
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

    # Finds the single DefNode for an unqualified instance method
    # (`owner_name`/`method_name`, matching ParserService's SymbolId
    # convention) anywhere in the file, tracking lexical nesting the same
    # way ParserService::Visitor does. Stops descending once found.
    class MethodLocator < Prism::Visitor
      attr_reader :found

      def initialize(owner_name, method_name)
        super()
        @owner_name = owner_name
        @method_name = method_name
        @owner_stack = []
        @found = nil
      end

      def visit_module_node(node) = visit_namespace(node)
      def visit_class_node(node) = visit_namespace(node)

      def visit_def_node(node)
        return if @found
        return unless node.receiver.nil? && node.name.to_s == @method_name && @owner_stack.last == @owner_name

        @found = node
      end

      private

      def visit_namespace(node)
        return if @found

        @owner_stack.push(qualify(node.constant_path.full_name))
        node.each_child_node { |child| child.accept(self) }
        @owner_stack.pop
      end

      def qualify(local_path)
        return local_path if local_path.start_with?("::")

        @owner_stack.last ? "#{@owner_stack.last}::#{local_path}" : "::#{local_path}"
      end
    end
    private_constant :MethodLocator

    # Finds the first literal-argument `render` call (no receiver) in a
    # method body. Dynamic render targets (interpolated strings, variables)
    # are intentionally left unresolved.
    class RenderTargetFinder < Prism::Visitor
      attr_reader :target

      def visit_call_node(node)
        return super if @target
        return super unless node.receiver.nil? && node.name == :render

        arg = node.arguments&.arguments&.first
        case arg
        when Prism::SymbolNode then @target = arg.value.to_s
        when Prism::StringNode then @target = arg.unescaped
        end

        super
      end
    end
    private_constant :RenderTargetFinder
  end
end
