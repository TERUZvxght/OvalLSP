# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "models/model_registry"
require_relative "semantic/generic_rule_registry"
require_relative "signatures/overload_resolver"

module Ovallsp
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
                   method_resolver: nil, method_analyzer: nil, signatures: nil, observation_store: nil)
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
      @signatures = signatures
      @observation_store = observation_store
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

    # `document` is an Ovallsp::TextDocument; `position` is an LSP
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
      @self_type_stack = []

      locate(result.value.statements, offset, initial_env.dup)
    rescue BudgetExceeded, StandardError
      Types::UNKNOWN
    end

    def infer_ivars_for_method_node(method_node, initial_env: {}, self_type_name:, reset_budget: true)
      return ivars_from(initial_env) unless method_node
      return ivars_from(initial_env) unless method_node.body

      begin_ivar_inference if reset_budget
      @self_type_stack = [Types::Nominal.new(name: self_type_name.to_s.delete_prefix("::"))]
      env = initial_env.dup
      eval_type(method_node.body, env)
      # Symbol-keyed (":@user", not "@user") to match how Prism names
      # InstanceVariableReadNode/WriteNode, so this can be passed straight
      # back in as another call's `initial_env` without re-keying.
      ivars_from(env)
    rescue BudgetExceeded, StandardError
      ivars_from(initial_env)
    end

    def method_nodes(document, owner_name:)
      locator = MethodMapLocator.new(owner_name)
      Prism.parse(document.text).value.accept(locator)
      locator.nodes
    rescue StandardError
      {}
    end

    def begin_ivar_inference
      @steps = 0
      @step_budget = @max_steps
    end

    def before_action_operations(document, owner_name:, action_name:)
      finder = BeforeActionFinder.new(owner_name, action_name.to_s)
      Prism.parse(document.text).value.accept(finder)
      finder.operations
    rescue StandardError
      []
    end

    def static_render_target_for_node(method_node)
      return nil unless method_node&.body

      @steps = 0
      @step_budget = @max_steps
      RenderTargetFinder.new.tap { |finder| method_node.body.accept(finder) }.target
    rescue StandardError
      nil
    end

    private

    def ivars_from(env)
      env.select { |key, _| key.to_s.start_with?("@") }
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
        elsif (argument = argument_containing(node, offset))
          # An argument is its own expression and has its own type.
          # Without this, every position inside an argument list answered
          # with the *enclosing* call's type: hovering `params` in
          # `User.find(params[:id])` said User, and -- because the
          # diagnostics engine resolves a receiver by asking for the type
          # at the receiver's position -- `params[:id]` was reported as
          # "User has no method named `[]`".
          locate(argument, offset, env)
        else
          eval_type(node, env)
        end
      when Prism::IfNode, Prism::UnlessNode
        locate_in_conditional(node, offset, env)
      when Prism::DefNode
        locate_in_def(node, offset)
      when Prism::ClassNode, Prism::ModuleNode
        # A class/module body (and `class << self`) is its own fresh local
        # scope, just like a `def` body -- verified live (`class << self`
        # cannot see an enclosing class body's locals). Without this case,
        # `locate` had no way to descend past the *first* class/module in
        # a file at all: every real Ruby file wraps its actual code in at
        # least one `class`/`module`, so #infer_at only ever worked for
        # bare top-level statements before this fix -- found while
        # building Task 014's reference resolution, which is the first
        # thing to query #infer_at against realistic (class-nested)
        # source rather than deliberately top-level test fixtures.
        locate_in_namespace(node, offset)
      when Prism::SingletonClassNode
        locate_in_singleton_class(node, offset)
      else
        # Anything not named above may still *contain* the position: a
        # keyword argument's value, an array element, a hash value, a
        # `while`/`case`/`begin` body, a `return`'s value. Descending into
        # whichever child holds the offset is the right default, and
        # listing node types was the wrong one -- every unlisted composite
        # answered with its own type instead of the expression under the
        # cursor, so hovering `"s".upcase` inside `f(a: ...)` said Unknown
        # and inside `[1, ...]` said Array. Found after the same mistake
        # in CallNode reported `User.find(params[:id])` as a missing `[]`
        # on the model.
        child = node.compact_child_nodes.find { |candidate| contains?(candidate.location, offset) }
        child ? locate(child, offset, env) : eval_type(node, env)
      end
    end

    # `self` inside the class/module body being entered -- pushed onto
    # @self_type_stack for the duration of the descent so an implicit-
    # self call anywhere inside (`active?`, not `widget.active?`) can
    # resolve against it. Found missing while building Task 017: without
    # this, #eval_call's `node.receiver.nil?` case had no receiver type
    # to resolve against at all and silently fell through to Unknown --
    # meaning *every* bare method call inside a method body (the single
    # most common shape of call in real Ruby) never resolved, the same
    # class of gap as the ClassNode/ModuleNode fix above, just one level
    # deeper.
    def argument_containing(node, offset)
      (node.arguments&.arguments || []).find { |argument| contains?(argument.location, offset) }
    end

    def locate_in_namespace(node, offset)
      return Types::UNKNOWN unless contains?(node.location, offset)

      @self_type_stack.push(Types::Nominal.new(name: node.constant_path.full_name))
      locate(node.body, offset, {})
    ensure
      @self_type_stack.pop
    end

    # `class << self` -- unlike ClassNode/ModuleNode, Prism::SingletonClassNode
    # has no `constant_path` (it reopens `self`'s own singleton class, not
    # a named constant), so self inside it is `ClassOf[enclosing self]`,
    # the same value `def self.x` already computes.
    def locate_in_singleton_class(node, offset)
      return Types::UNKNOWN unless contains?(node.location, offset)

      @self_type_stack.push(Types::Generic.new(name: "ClassOf", type_arg: @self_type_stack.last))
      locate(node.body, offset, {})
    ensure
      @self_type_stack.pop
    end

    def locate_in_def(node, offset)
      return Types::UNKNOWN unless contains?(node.location, offset)

      singleton = node.receiver.is_a?(Prism::SelfNode)
      enclosing_self = @self_type_stack.last
      @self_type_stack.push(singleton ? Types::Generic.new(name: "ClassOf", type_arg: enclosing_self) : enclosing_self)
      locate(node.body, offset, {})
    ensure
      @self_type_stack.pop
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

      # Same argument types #resolve_generic_call passes, so a block
      # parameter bound from a seed argument (`reduce(0)`,
      # `each_with_object([])`) resolves identically whether the cursor is
      # on the call or inside the block.
      argument_types = (node.arguments&.arguments || []).map do |argument|
        argument.is_a?(Prism::SplatNode) || argument.is_a?(Prism::KeywordHashNode) ? nil : eval_type(argument, env)
      end
      param_types = @generic_rules.block_parameter_types(
        receiver_type: receiver_type, method_name: node.name, arguments: argument_types
      )
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
      # Generic, matching `[]` and `Hash.new`: one kind of value renders
      # one way, whichever spelling produced it (024.12). Not for dispatch
      # -- the container rules have no `Hash` entry -- purely so the same
      # value does not render two ways depending on how it was written.
      when Prism::HashNode then Types::Generic.new(name: "Hash", type_arg: Types::UNKNOWN)
      when Prism::ParenthesesNode then eval_type(node.body, env)
      when Prism::CallNode then eval_call(node, env)
      when Prism::IfNode, Prism::UnlessNode then eval_conditional(node, env)
      when Prism::ConstantReadNode, Prism::ConstantPathNode then eval_constant(node)
      else Types::UNKNOWN
      end
    end

    # A bare constant is the *class object*, not an instance of it, which
    # is what `ClassOf[X]` means everywhere else in this engine (it is
    # already what `self` is inside `class << self` and what a singleton
    # method's receiver resolves to).
    #
    # There was no case for this at all, so every constant evaluated to
    # Unknown -- and since completion asks for the type of whatever
    # precedes the dot, `User.`, `Article.`, `JSON.` produced an empty
    # list. That is the single most common completion trigger in Ruby, and
    # it answered nothing in every released version.
    #
    # `Foo.new`/`Foo.find` do not come through here: #eval_call resolves a
    # constant receiver from the AST directly, which is why those worked
    # while the receiver's own type did not.
    def eval_constant(node)
      name = node.full_name
      return Types::UNKNOWN if name.nil? || name.empty?

      Types::Generic.new(name: "ClassOf", type_arg: Types::Nominal.new(name: name.delete_prefix("::")))
    rescue StandardError
      # `full_name` raises on a dynamic constant path (`Foo::(bar)`).
      Types::UNKNOWN
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
      # An implicit-self call (`active?`, not `widget.active?`) resolves
      # against whatever @self_type_stack was pushed to when #locate
      # descended into the enclosing class/module and def -- nil at true
      # top level (no enclosing class), which correctly leaves the call
      # unresolved rather than guessing.
      receiver_type = node.receiver ? eval_type(node.receiver, env) : @self_type_stack.last
      base = resolve_call(node, receiver_type, env)

      node.respond_to?(:safe_navigation?) && node.safe_navigation? ? Types.normalize_union([base, Types::NIL]) : base
    end

    def resolve_call(node, receiver_type, env)
      if constant_receiver?(node.receiver)
        constant_type = Types::Nominal.new(name: node.receiver.full_name)
        signature_method = resolve_signature_call(
          constant_type, node, singleton: true, direct: true
        )
        # An `untyped` RBS result resolves to an Unknown, which is truthy
        # -- so consulting RBS first (correct in itself) let an untyped
        # `.new` beat the nominal-constructor fallback that used to
        # answer. `Point = Struct.new(:x, :y)` went from `Struct` to
        # `Unknown`, as did `Data.new`. Unknown carries no information, so
        # it must count as "no answer" here, exactly as the union branch
        # further down already filters it out.
        #
        # Matched by type rather than `== Types::UNKNOWN` because the
        # class, not the constant, is what "no information" means here:
        # Types::Unknown defines no value equality, so any Unknown that is
        # not the frozen constant would compare unequal to it and slip
        # through. Every producer happens to return the constant today
        # (TypeConverter maps untyped/void/top/bottom to it), so this is a
        # guard against a second instance appearing, not a live fix.
        return signature_method if signature_method && !signature_method.is_a?(Types::Unknown)

        if node.name == :new
          singleton_method = resolve_source_method_member(constant_type, node.name, singleton: true)
          inherited_signature = resolve_signature_call(constant_type, node, singleton: true, direct: false)
          inherited_signature = nil if inherited_signature.is_a?(Types::Unknown)
          return singleton_method || inherited_signature || constant_type
        end

        # Nothing to return here: the guard above already returned any
        # signature answer that carried information, so anything still held
        # in `signature_method` is Unknown -- which is what a project
        # writing `-> untyped` is saying, and it says nothing. Returning it
        # switched the method off, skipping the class-level finder and the
        # source declaration below (024.3). The `.new` branch had always
        # filtered it; this branch had not.
        class_level = resolve_class_level_finder(node.receiver.full_name, node.name)
        return class_level if class_level

        # `Widget.some_class_method` -- an ordinary (non-Active-Record)
        # singleton method call, e.g. Task 017's `scope` (which declares
        # its generated method with kind: :singleton_method). Tried after
        # the AR class-level finder specifically fails, not unconditionally,
        # so a real Active Record finder never gets shadowed by a same-
        # named source declaration.
        singleton_method = resolve_source_method_member(constant_type, node.name, singleton: true)
        return singleton_method if singleton_method

        inherited_signature = resolve_signature_call(constant_type, node, singleton: true, direct: false)
        return inherited_signature if inherited_signature
      end

      generic = receiver_type && resolve_generic_call(node, receiver_type, env)
      return generic if generic

      if receiver_type.is_a?(Types::Union)
        member_types = receiver_type.members.filter_map do |member|
          next if member == Types::NIL

          resolved = resolve_call(node, member, env)
          resolved unless resolved == Types::UNKNOWN
        end
        return Types.normalize_union(member_types) unless member_types.empty?
      end

      signature = receiver_type && resolve_signature_call(receiver_type, node, direct: true)
      return signature if signature

      instance_level = receiver_type && resolve_instance_level(receiver_type, node.name)
      return instance_level if instance_level

      inherited_signature = receiver_type && resolve_signature_call(receiver_type, node, direct: false)
      return inherited_signature if inherited_signature

      observed = receiver_type && resolve_observed_call(receiver_type, node)
      return observed if observed

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

      # Evaluated so a rule can bind its type parameter from a seed
      # argument (`reduce(0)`, `each_with_object({})`) instead of from the
      # block's return type.
      argument_types = (node.arguments&.arguments || []).map do |argument|
        argument.is_a?(Prism::SplatNode) || argument.is_a?(Prism::KeywordHashNode) ? nil : eval_type(argument, env)
      end

      @generic_rules.resolve(
        receiver_type: receiver_type, method_name: node.name,
        arguments: argument_types, block: block_callable
      )
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
        # "ClassOf[Widget]" is @self_type_stack's own representation of
        # `self` inside a `def self.x` (matching Semantic::MethodAnalyzer's
        # `self_type_for` convention) -- an implicit-self call there
        # (`some_other_class_method`, not `Widget.some_other_class_method`)
        # needs singleton-mode resolution, same as an explicit constant
        # receiver gets in #resolve_call.
        if receiver_type.name == "ClassOf"
          resolve_source_method_member(receiver_type.type_arg, method_name, singleton: true)
        else
          # A container value is an instance of its class, so a method the
          # workspace adds to that class resolves on it (024.12).
          #
          # Tried *before* the built-in relation rules, because that is what
          # Ruby does: a workspace that reopens `Array` and defines its own
          # `first` has replaced the one the rules model. The rules still
          # answer everything the workspace does not declare, since
          # #resolve_source_method_member returns nil when there is no
          # declaration -- so this only changes the answer where a
          # workspace really did override the method.
          #
          # `Relation` and `CollectionProxy` cannot reach the base lookup
          # at all (`Types.base_nominal` refuses them), so the order is
          # decided entirely by `Array`, the one name in both sets.
          resolve_generic_base_member(receiver_type, method_name) ||
            resolve_relation_member(receiver_type, method_name)
        end
      when Types::Union
        resolve_union_member(receiver_type, method_name)
      end
    end

    def resolve_generic_base_member(receiver_type, method_name)
      base = Types.base_nominal(receiver_type)
      return nil unless base

      resolve_source_method_member(base, method_name)
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
    def resolve_source_method_member(receiver_type, method_name, singleton: false)
      return nil unless @method_resolver && @method_analyzer

      candidate = @method_resolver.resolve(receiver_type: receiver_type, name: method_name, context: { singleton: singleton })
                                   .min_by(&:lookup_rank)
      return nil unless candidate

      @method_analyzer.summarize(symbol_id: candidate.symbol_id).return_type
        .then { |type| type == Types::UNKNOWN ? nil : type }
    end

    def resolve_signature_call(receiver_type, node, singleton: false, direct: nil)
      return nil unless @signatures

      if receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"
        return resolve_signature_call(receiver_type.type_arg, node, singleton: true, direct: direct)
      end
      if receiver_type.is_a?(Types::Union)
        resolved = receiver_type.members.filter_map do |member|
          next if member == Types::NIL

          resolve_signature_call(member, node, singleton: singleton, direct: direct)
        end
        return Types.normalize_union(resolved) unless resolved.empty?
        return nil
      end
      generic_type_arg = receiver_type.type_arg if receiver_type.is_a?(Types::Generic)
      receiver_type = Types::Nominal.new(name: receiver_type.name) if receiver_type.is_a?(Types::Generic)
      return nil unless receiver_type.is_a?(Types::Nominal)

      owner = receiver_type.name.start_with?("::") ? receiver_type.name : "::#{receiver_type.name}"
      symbol_id = Index::SymbolId.new(
        kind: singleton ? :singleton_method : :instance_method, owner: owner, name: node.name.to_s, discriminator: nil
      )
      signature = @signatures.method_signatures(symbol_id)
      return nil unless signature
      return nil unless direct.nil? || signature.direct == direct

      arguments = node.arguments&.arguments || []
      keyword_hash = arguments.last if arguments.last.is_a?(Prism::KeywordHashNode)
      positional_arguments = keyword_hash ? arguments[0...-1] : arguments
      # `...` forwards positionals, keywords AND a block at once, so it
      # makes all three statically unknowable -- exactly like `*args`
      # already did for positionals and `**kw` for keywords. Prism models
      # it as ForwardingArgumentsNode, which is a single element of
      # `arguments`: counting it as one positional argument narrowed
      # `f(...)` to whichever overload happens to take one argument, the
      # very mis-narrowing the splat handling here exists to prevent.
      forwarding = arguments.any? { |argument| argument.is_a?(Prism::ForwardingArgumentsNode) }
      positional_count =
        if forwarding || positional_arguments.any? { |argument| argument.is_a?(Prism::SplatNode) }
          nil
        else
          positional_arguments.length
        end
      keyword_names =
        if forwarding || keyword_hash&.elements&.any? { |element| element.is_a?(Prism::AssocSplatNode) }
          nil
        elsif keyword_hash
          # Prism reports a symbol key's `value` as a String ("id"), while
          # Overload#required_keywords/#optional_keywords are keyed by the
          # Symbols RBS produces (:id). Comparing the two directly meant
          # `keyword_names.include?` was false for every keyword-bearing
          # overload, so keyword-based selection could never pick one --
          # every keyword call silently fell through to the union-of-all
          # -overloads path. Normalize here, at the boundary where the AST
          # shape is known, rather than making the resolver accept both.
          keyword_hash.elements.filter_map do |element|
            element.key.value.to_sym if element.key.is_a?(Prism::SymbolNode)
          end
        else
          []
        end
      bindings = {}
      if generic_type_arg
        # The *last* parameter, matching the single-argument model
        # TypeConverter#convert_class_type builds: for a `Hash[K, V]` it
        # keeps the value type, so a Generic's `type_arg` is `V`, never
        # `K`. Binding it to `K` did not merely fail to answer -- it
        # answered wrongly and with confidence: `["a"].tally.keys` came
        # back `Array[Integer]` when the real type is `Array[String]`,
        # while `.values` and `.fetch` degraded to Unknown. Binding the
        # last parameter makes those two right and lets `.keys` fall back
        # to the honest Unknown.
        receiver_parameters = @signatures.type_parameters(owner)
        bindings[receiver_parameters.last] = generic_type_arg unless receiver_parameters.empty?
      end
      resolved = Signatures::OverloadResolver.resolve(
        signature.overloads, positional_count: positional_count, keyword_names: keyword_names,
        # `...` forwards the caller's block too, so a forwarding call may
        # supply one even though this call site writes no literal block.
        block_given: !node.block.nil? || forwarding, receiver_bindings: bindings
      )
      return nil unless resolved

      # Also removes unbound method/block TypeParameters as Unknown, so
      # placeholders such as Hash's K or Array#map's U never escape into
      # a caller-visible final type.
      Types.substitute(resolved, bindings)
    rescue StandardError
      nil
    end

    def resolve_observed_call(receiver_type, node, singleton: false)
      return nil unless @observation_store

      if receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"
        return resolve_observed_call(receiver_type.type_arg, node, singleton: true)
      end
      if receiver_type.is_a?(Types::Union)
        resolved = receiver_type.members.filter_map do |member|
          next if member == Types::NIL

          resolve_observed_call(member, node, singleton: singleton)
        end
        return Types.normalize_union(resolved) unless resolved.empty?
        return nil
      end
      # Runtime evidence is recorded against the class, so it applies to a
      # value typed as that class' container form too -- the same reading
      # #resolve_instance_level uses (024.12).
      receiver_type = Types.base_nominal(receiver_type)
      return nil unless receiver_type.is_a?(Types::Nominal)

      owner = receiver_type.name.start_with?("::") ? receiver_type.name : "::#{receiver_type.name}"
      symbol_ids = [Index::SymbolId.new(
        kind: singleton ? :singleton_method : :instance_method, owner: owner, name: node.name.to_s, discriminator: nil
      )]
      if @method_resolver
        symbol_ids.concat(
          @method_resolver.resolve(receiver_type: receiver_type, name: node.name, context: { singleton: singleton })
                          .sort_by(&:lookup_rank).map(&:symbol_id)
        )
      end
      evidence = symbol_ids.uniq.filter_map { |symbol_id| @observation_store.evidence_for(symbol_id) }.first
      return nil if evidence.nil? || evidence.return_type == Types::UNKNOWN

      evidence.return_type
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

    class MethodMapLocator < Prism::Visitor
      attr_reader :nodes

      def initialize(owner_name)
        super()
        @owner_name = owner_name
        @owner_stack = []
        @nodes = {}
      end

      def visit_module_node(node) = visit_namespace(node)
      def visit_class_node(node) = visit_namespace(node)

      # A `class << self` body's receiverless defs are singleton methods,
      # not this owner's instance methods, so the whole node is skipped.
      def visit_singleton_class_node(node) = nil

      def visit_def_node(node)
        return unless node.receiver.nil? && @owner_stack.last == @owner_name

        # Last definition wins, as Ruby itself resolves a redefined
        # method -- and as `contributing_actions` already reads visibility
        # from the last matching declaration. `||=` kept the *first* body
        # while visibility came from the last one, so a redefined action
        # could be described by two different declarations at once.
        @nodes[node.name.to_s] = node
      end

      private

      def visit_namespace(node)
        @owner_stack.push(qualify(node.constant_path.full_name))
        node.each_child_node { |child| child.accept(self) }
      ensure
        @owner_stack.pop
      end

      def qualify(local_path)
        return local_path if local_path.start_with?("::")

        @owner_stack.last ? "#{@owner_stack.last}::#{local_path}" : "::#{local_path}"
      end
    end
    private_constant :MethodMapLocator

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

    # Extracts receiver-less before_action declarations directly from the
    # requested class body. This intentionally does not descend into
    # method bodies or nested namespaces, where a same-named call is not a
    # Rails controller callback declaration.
    class BeforeActionFinder < Prism::Visitor
      attr_reader :operations

      def initialize(owner_name, action_name)
        super()
        @owner_name = owner_name
        @action_name = action_name
        @owner_stack = []
        @operations = []
      end

      def visit_module_node(node) = visit_namespace(node)
      def visit_class_node(node) = visit_namespace(node)

      private

      def visit_namespace(node)
        @owner_stack.push(qualify(node.constant_path.full_name))
        if @owner_stack.last == @owner_name
          node.body&.body&.each { |statement| record(statement) }
        else
          node.each_child_node { |child| child.accept(self) }
        end
      ensure
        @owner_stack.pop
      end

      def qualify(local_path)
        return local_path if local_path.start_with?("::")

        @owner_stack.last ? "#{@owner_stack.last}::#{local_path}" : "::#{local_path}"
      end

      def record(node)
        return unless node.is_a?(Prism::CallNode) && node.receiver.nil?
        return unless %i[before_action skip_before_action].include?(node.name)

        arguments = node.arguments&.arguments || []
        # Not `pop`: that array belongs to Prism, so consuming the options
        # here destroyed the declaration's own `only:`/`except:` selector
        # in the tree. Every caller re-parses today, which is the only
        # reason it never showed -- and that is the callers' property, not
        # this method's.
        options = arguments.last.is_a?(Prism::KeywordHashNode) ? arguments.last : nil
        arguments = arguments[0...-1] if options
        selector = selector_status(options)
        return if selector == :excluded

        names = arguments.filter_map { |argument| literal_name(argument) }
        # A dynamic callback name makes the declaration only partially
        # understood. Ignore the declaration rather than silently applying
        # just the literal subset with misleading certainty.
        return unless names.length == arguments.length

        if node.name == :skip_before_action
          # An unresolved conditional skip may execute. Removing the
          # callback is conservative: retaining its ivars would claim
          # they definitely exist on a path where Rails may skip it.
          names.each { |name| @operations << [:skip, name] }
        elsif selector == :unresolved
          return
        else
          names.each { |name| @operations << [:add, name] }
        end
      end

      def selector_status(options)
        return :applicable unless options

        selectors = {}
        options.elements.each do |element|
          return :unresolved unless element.is_a?(Prism::AssocNode)

          key = literal_name(element.key)
          # Conditions cannot be evaluated statically. Treat the whole
          # declaration as unresolved instead of applying a callback that
          # may be disabled at runtime.
          return :unresolved unless %w[only except].include?(key)

          values = literal_names(element.value)
          return :unresolved unless values

          selectors[key] = values
        end

        return :excluded if selectors["only"] && !selectors["only"].include?(@action_name)
        return :excluded if selectors["except"]&.include?(@action_name)

        :applicable
      end

      def literal_names(node)
        elements = node.is_a?(Prism::ArrayNode) ? node.elements : [node]
        names = elements.filter_map { |element| literal_name(element) }
        names.length == elements.length ? names : nil
      end

      def literal_name(node)
        case node
        when Prism::SymbolNode then node.value.to_s
        when Prism::StringNode then node.unescaped
        end
      end
    end
    private_constant :BeforeActionFinder
  end
end
