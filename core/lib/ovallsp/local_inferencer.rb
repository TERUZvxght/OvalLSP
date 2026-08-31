# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "models/model_registry"
require_relative "semantic/generic_rule_registry"
require_relative "semantic/receiver_resolution"
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

    # How far `#assigned_constant_type` will follow one constant into
    # another. `KLASS = Widget` needs one level; `A = B` beside `B = A` is
    # a program somebody can write, and this is what makes that a decline
    # rather than a hang. `024.84`.
    MAX_CONSTANT_DEPTH = 3

    def initialize(max_steps: 5000, model_registry: Models::ModelRegistry.new, generic_rules: nil,
                   method_resolver: nil, method_analyzer: nil, signatures: nil, observation_store: nil,
                   workspace_index: nil, hierarchy_index: nil)
      @max_steps = max_steps
      @constant_depth = 0
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
      # Optional like the rest: without it a bare constant stays exactly
      # as written, which is what every release before 0.2.10 did. With
      # it, a bare constant is resolved through the lexical nesting the
      # way Ruby resolves one (`024.103`).
      @workspace_index = workspace_index
      # For Ruby's *second* constant-lookup step: after the nesting, the
      # ancestors of the innermost cref. Optional like the rest -- without
      # it the lookup stops after the nesting, which is what 0.2.10
      # shipped.
      @hierarchy_index = hierarchy_index
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
    # What is nameable at a cursor position: the local bindings visible
    # there (name String => Types value) and the type of `self`, or nil
    # for `self` at the top level of a file, where there is no useful
    # enclosing type to offer members from.
    Scope = Data.define(:locals, :self_type)

    # The environment `locate` builds on its way to `offset`, rather than
    # the type it arrives at. Completion from a bare prefix needs the
    # names in scope; `infer_at` computes them and then discards them.
    #
    # Returns the *innermost* scope containing the position, so a local
    # declared in a method the cursor is not in does not appear -- the
    # descent already starts a fresh environment per `def`, which is what
    # makes that true rather than anything here.
    # `initial_env` seeds bindings before the walk, exactly as `#infer_at`
    # takes one: an ERB template assigns no instance variables of its own,
    # so without it the ivars a controller action put there are invisible
    # to everything that reads a scope -- which is why completion after
    # `@` answered nothing in a view while hovering the same name in the
    # same view answered its type.
    def scope_at(document, position, max_steps: nil)
      offset = document.position_to_byte_offset(position)
      result = parse_cached(document)
      @steps = 0
      @step_budget = max_steps || @max_steps
      @self_type_stack = []
      @scope_capture = nil
      @capturing_scope = true

      locate(result.value.statements, offset, {})
      @scope_capture || Scope.new(locals: {}, self_type: nil)
    rescue BudgetExceeded, StandardError
      @scope_capture || Scope.new(locals: {}, self_type: nil)
    ensure
      @capturing_scope = false
      @scope_capture = nil
    end

    def infer_at(document, position, initial_env: {}, max_steps: nil)
      # Prism node locations are UTF-8 byte offsets, not Ruby character
      # offsets — using #position_to_char_offset here would select the
      # wrong node whenever a multibyte character appears anywhere before
      # the target position (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      offset = document.position_to_byte_offset(position)
      result = parse_cached(document)
      @steps = 0
      @step_budget = max_steps || @max_steps
      @self_type_stack = []
      @lexical_nesting = []
      @in_singleton_class = false
      @target_span = nil

      locate(result.value.statements, offset, initial_env.dup)
    rescue BudgetExceeded, StandardError
      Types::UNKNOWN
    end

    # The type of the node spanning exactly `range`, for a caller that
    # already knows which node it means.
    #
    # `#infer_at` answers about the *innermost* node at an offset, which
    # is the right question for a cursor and the wrong one for an
    # argument. The end offset was used because the start of
    # `SmallInteger.new` lands on the constant and answers
    # `ClassOf[SmallInteger]` -- but for an argument written as a
    # paren-less call the argument's own end is also its last argument's
    # end:
    #
    #   Widget.new.label(Widget.new.make 1)
    #   #                ^ argument       17...34
    #   #                                 ^ its `1`  33...34
    #
    # so the innermost node at 34 is the Integer, and a String argument
    # was reported as an Integer -- while the same mechanism reversed
    # kept a real String-for-Integer mismatch silent (`024.20`).
    #
    # Both offsets, so the answer is decided by the node the caller
    # named rather than by whatever else happens to touch one end of it.
    def infer_span(document, range, initial_env: {}, max_steps: nil)
      start_offset = document.position_to_byte_offset(range[:start])
      end_offset = document.position_to_byte_offset(range[:end])
      return Types::UNKNOWN unless start_offset && end_offset

      result = parse_cached(document)
      @steps = 0
      @step_budget = max_steps || @max_steps
      @self_type_stack = []
      @lexical_nesting = []
      @in_singleton_class = false
      @target_span = [start_offset, end_offset]

      locate(result.value.statements, end_offset, initial_env.dup)
    rescue BudgetExceeded, StandardError
      # **Contained** (`024.20`): `Types::UNKNOWN` is this engine's own
      # not-knowing, and the one caller declines to report on it.
      Types::UNKNOWN
    ensure
      @target_span = nil
    end

    def spans_target?(node)
      return false unless @target_span

      location = node.location
      location.start_offset == @target_span[0] && location.end_offset == @target_span[1]
    end

    def infer_ivars_for_method_node(method_node, initial_env: {}, self_type_name:, reset_budget: true)
      return ivars_from(initial_env) unless method_node
      return ivars_from(initial_env) unless method_node.body

      begin_ivar_inference if reset_budget
      @self_type_stack = [Types::Nominal.new(name: Semantic::ReceiverResolution.canonical_receiver_name(self_type_name))]
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

    # Every instance variable `document` assigns anywhere, by any of the
    # five write shapes Ruby has.
    #
    # Syntactic on purpose. The inference walk above answers "what type
    # does this ivar have", and folds only the statement shapes it models
    # -- which is right for types, where an unfolded shape infers Unknown
    # and nothing is lost, and wrong for "was it assigned at all", where
    # an unfolded shape produces a complete-looking set with a name
    # missing. `@user ||= ...`, an assignment inside `respond_to do
    # |format|`, inside a `case`, inside a `rescue`, and a multiple
    # assignment all reached that second question and each produced a
    # warning on a view that renders (0.2.0).
    # **No rescue, deliberately** (`024.122`). This answers "which ivars
    # does this document assign", and both callers build a *union* the
    # unassigned-ivar check compares against. An empty list from a failed
    # parse is indistinguishable from a document that assigns none, so a
    # single unreadable ancestor file silently removed its ivars from the
    # union and every read of one became a false report -- the direction
    # `Server#assigned_ivars_for` already refuses, by answering `nil` and
    # switching the check off for that view.
    #
    # Letting it raise is what reaches that refusal. The failure was being
    # caught one layer below the layer that knows what to do with it.
    def assigned_ivar_names(document)
      collector = Diagnostics::Engine::IvarWriteCollector.new
      Prism.parse(document.text).value.accept(collector)
      collector.names.uniq
    end

    # One parse, remembered, because the argument-type check asks for a
    # type at each positional argument of each call and `infer_at` parsed
    # the whole file again every time -- on a 1,000-line file that is
    # 5,001 parses where 3,001 would do, on the path the workspace pass
    # runs over every file while holding the index mutex.
    #
    # Keyed by uri, version and text so a hit cannot be another document's
    # tree, and stored as one frozen pair so a reader sees either the
    # whole entry or the previous one. One entry is enough: the callers
    # that repeat are repeating within one document.
    def parse_cached(document)
      key = [document.uri, document.version, document.text.hash].freeze
      cached = @parse_cache
      return cached[1] if cached && cached[0] == key

      parsed = Prism.parse(document.text)
      @parse_cache = [key, parsed].freeze
      parsed
    end

    # Receiverless calls made directly in `owner_name`'s class body --
    # not inside its method bodies, where a same-named call is an ordinary
    # call rather than a class-level declaration.
    #
    # `BeforeActionFinder` walks the same statements looking for the two
    # names it models; this reports all of them, so a caller can ask the
    # different question of whether anything *unmodelled* is there.
    def class_body_call_names(document, owner_name:)
      finder = ClassBodyCallFinder.new(owner_name)
      Prism.parse(document.text).value.accept(finder)
      finder.names
    rescue StandardError
      []
    end

    private

    def ivars_from(env)
      env.select { |key, _| key.to_s.start_with?("@") }
    end

    def step!
      @steps += 1
      raise BudgetExceeded if @steps > @step_budget
    end

    # Recorded on every step of the descent, so the last write is the
    # innermost scope containing the cursor. `env` is duplicated because
    # the caller keeps mutating the same Hash as it evaluates the
    # statements that follow the one we descended into -- holding the
    # reference would report bindings from after the cursor.
    #
    # Guarded at both call sites by `@capturing_scope` rather than here,
    # so that "an ordinary #infer_at builds no snapshots" is a fact a test
    # can state directly. The saving is real: this copies the whole
    # environment, and `locate` runs once per step of the descent.
    # Locals and instance variables live in the same environment and are
    # told apart by the `@` their key carries. They are handed back
    # *separately* because no caller wants both at once: a bare prefix can
    # never be completed by an ivar, and a prefix that opens with `@` can
    # never be completed by a local.

    ANONYMOUS_CLASS_FACTORIES = { "Struct" => %i[new], "Class" => %i[new], "Data" => %i[define] }.freeze

    def anonymous_class_factory?(constant_type, node)
      return false unless constant_type.is_a?(Types::Nominal)

      ANONYMOUS_CLASS_FACTORIES.fetch(Index::SymbolId.bare_name(constant_type.name), []).include?(node.name)
    end

    def capture_scope(env)
      locals = env.each_with_object({}) do |(key, value), acc|
        name = key.to_s
        acc[name] = value unless name.start_with?("@")
      end
      @scope_capture = Scope.new(locals: locals, self_type: @self_type_stack.last)
    end

    # Inclusive of `end_offset`, which is one past the node's last
    # character -- so an offset equal to it answers about a node it is
    # actually just past. That is wrong, and it is why a receiver ending
    # in `)` resolves to its own last argument (024.20); making it
    # exclusive is the right rule and breaks 39 examples, because every
    # caller that hands it an LSP range end depends on the current one.
    # Recorded rather than changed here.
    def contains?(location, offset)
      location.start_offset <= offset && offset <= location.end_offset
    end

    # Finds the most specific node containing `offset`, threading (and
    # mutating) `env` exactly as eval_type does, so bindings and narrowing
    # accumulate correctly on the way down to the target.
    def locate(node, offset, env)
      step!
      capture_scope(env) if @capturing_scope
      return Types::UNKNOWN if node.nil?
      # `#infer_span` asked about a node it already had, and stopping the
      # descent here is what lets it keep the env threading this walk
      # does rather than growing a second walker that has to agree with
      # it (`024.20`). Nil for every other caller, so the line cannot
      # fire on a cursor query.
      return eval_type(node, env) if spans_target?(node)

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
      # Read before the guard, because `ensure` runs on the early return
      # too and a value captured after it would restore nil -- which is
      # `false` to every reader, and would clear the flag for the rest of
      # an enclosing `class << self`.
      #
      # The *restore* below is **unpinned and known to be**, like the two
      # lines this method already says that about: a descent visits one
      # path down to the offset and nothing reads the flag on the way back
      # out, so no fixture can distinguish restoring from not. It is the
      # symmetry `#locate_in_singleton_class` already keeps, and the entry
      # point resets the flag per query. Only the clearing is observable,
      # and `self_receiver_spec.rb` pins that.
      previous_in_singleton_class = @in_singleton_class
      return Types::UNKNOWN unless contains?(node.location, offset)

      # `full_name` answers `::Widget` for `class ::Widget`, and the type
      # model's names are bare.
      #
      # This line and the `self_type_name` seed in #infer_ivars_for_method_node
      # are both **unpinned and known to be**: reverting either leaves the
      # whole suite green (rounds 6 and 8 both measured it). Every reader of
      # `@self_type_stack` re-normalises -- `MethodResolver` through
      # `resolve_type_name`, `ModelRegistry` through `lookup_key`,
      # `SymbolId` through `qualify_owner` -- so the spelling is absorbed
      # before it reaches an answer, and no probe has produced a
      # distinguishing input.
      #
      # Kept rather than reverted, and the reason is cost rather than
      # doubt: normalising here is free, and a consumer that stops
      # normalising would be a silent wrong answer rather than a loud one.
      #
      # An earlier version of this comment cited `constant_path_type` as a
      # precedent -- "a site declared unobservable that turned out to be
      # observable". That was wrong. 0.1.11 already normalised that site;
      # the difference a later round measured came from a *mutation* of
      # it, which proves the line was untested, not that it was broken.
      # The distinction matters because the two call for different things:
      # untested wants a spec, broken wants a fix (0.1.12).
      #
      # **The class object, not an instance of it** (`024.85`). `self` in
      # a class body is the class -- `class W; p self` prints `W` -- and
      # a receiverless call written there is a singleton call. The stack
      # held the instance type because the reader it was written for was
      # `#locate_in_def`, which wants the instance type and now derives
      # it; leaving the two conflated is what made `self.` in a class
      # body offer the wrong side's members.
      #
      # It has four readers, not one. `#eval_type`'s `SelfNode` case is
      # the one this entry is about, and two more see the class-body
      # change: `#eval_call`'s receiverless branch, so a bare call written
      # in a class body resolves as the singleton call Ruby makes it; and
      # `#capture_scope`, which is what `scope_at` hands prefix
      # completion, so receiverless completion there offers the singleton
      # surface. Both are what Ruby does in a class body, and neither was
      # pinned -- `local_inferencer_spec.rb` covers the scope one now.
      #
      # **And `@in_singleton_class` does not survive a nested class.** A
      # class opened inside `class << self` is an ordinary class, and a
      # `def` in it an ordinary instance method:
      #
      #   $ ruby -e '
      #   class W
      #     class << self
      #       class Inner; def a; self; end; end
      #     end
      #   end
      #   inner = W.singleton_class.const_get(:Inner)
      #   p inner.new.a.class == inner
      #   '
      #   # => true
      #   # ruby 3.4.10
      #
      # Leaving the flag set made `#def_self_type` answer `ClassOf[Inner]`
      # where Ruby has an `Inner`. Before `024.85` the flag's only reader
      # was `#ancestor_type_name`, where a stale `true` merely skipped a
      # resolution step -- a decline. It asserts now, so it is scoped.
      @in_singleton_class = false
      @self_type_stack.push(
        Types.class_object(
          Types::Nominal.new(name: Semantic::ReceiverResolution.canonical_receiver_name(node.constant_path.full_name))
        )
      )
      push_nesting(node.constant_path.full_name)
      locate(node.body, offset, {})
    ensure
      @in_singleton_class = previous_in_singleton_class
      @self_type_stack.pop
      @lexical_nesting&.pop
    end

    # `Module.nesting`, kept in its own stack rather than read back out of
    # `@self_type_stack`: that stack is pushed again by `#locate_in_def`
    # with the *same* value, so `module App; class Runner; def go` leaves
    # `["App", "Runner", "Runner"]` there and the duplicate is not
    # distinguishable from a real frame. A `def` opens no nesting frame.
    #
    # A compact `class App::Runner` is one frame, not two, which is why
    # the resolved path is pushed whole rather than split.
    def push_nesting(written)
      @lexical_nesting ||= []
      @lexical_nesting.push(nesting_frame_for(written.to_s, @lexical_nesting.last))
    end

    # **A compact path's head is looked up; a simple name is not.**
    # `class Runner` inside `module App` always means `App::Runner`
    # whatever else exists. `class Other::Runner` written there means
    # whichever `Other` the enclosing nesting resolves to, and `Runner`
    # inside *that*:
    #
    #   $ ruby -e '
    #   class Other; class Runner; end; end
    #   module App
    #     class Other::Runner
    #       def nesting_here = Module.nesting
    #     end
    #   end
    #   p Other::Runner.new.nesting_here
    #   '
    #   # => [Other::Runner, App]
    #   # ruby 3.4.10
    #
    # and the same source with `App::Other` present resolves the other
    # way, to `[App::Other::Runner, App]` -- so this is a lookup, not a
    # rule about compact paths. `024.257`: gluing the whole written path
    # onto the enclosing frame built `App::Other::Runner`, which names
    # nothing, and a bare constant in that body fell through to the
    # top-level class. Both directions inverted -- the call that runs
    # reported, the call that raises silent.
    #
    # `#qualify_constant` is exactly Ruby's rule for the head, and at
    # this point `@lexical_nesting` still holds the *parent* frames,
    # which is the cref the head is resolved against.
    def nesting_frame_for(written, parent)
      # `class ::Widget` opens the top level whatever encloses it, and
      # the type model's names are bare.
      return written.delete_prefix("::") if written.start_with?("::")
      return parent ? "#{parent}::#{written}" : written unless written.include?("::")

      head, rest = written.split("::", 2)
      resolved = qualify_constant(head).to_s.delete_prefix("::")
      "#{resolved}::#{rest}"
    end

    # `class << self` -- unlike ClassNode/ModuleNode, Prism::SingletonClassNode
    # has no `constant_path` (it reopens `self`'s own singleton class, not
    # a named constant), so self inside it is the enclosing class object,
    # the same value `def self.x` already computes.
    #
    # Ruby's own answer for the body itself is one step further out than
    # that -- `class W; class << self; p self` prints the *singleton*
    # class, not `W` -- and this engine has no type for a singleton class.
    # The approximation is deliberate and is what every `def` written
    # there needs; the direction it errs in is offering a member the
    # singleton class does not have, never asserting one is missing, since
    # a `ClassOf` receiver is not something the unknown-method check
    # reports about. `024.85`.
    def locate_in_singleton_class(node, offset)
      return Types::UNKNOWN unless contains?(node.location, offset)

      # `class << self` and `def self.x` both make self a class object,
      # and only the first changes what a bare constant means:
      #
      #   $ ruby -e '
      #   class Config; def top_only; end; end
      #   class SBase; class Config; def sbase_only; end; end; end
      #   class SSub < SBase
      #     def self.probe = Config
      #     class << self; def probe2 = Config; end
      #   end
      #   p [SSub.probe, SSub.probe2]
      #   '
      #   # => [SBase::Config, Config]
      #   # ruby 3.4.10
      #
      # A guard reading `@self_type_stack.last.is_a?(Types::Generic)`
      # cannot tell them apart, and disabling step 2 inside `def self.x`
      # left both directions inverted there -- which is what this release
      # marked `024.112` fixed while it was still true.
      previous_in_singleton_class = @in_singleton_class
      @in_singleton_class = true
      # `class << obj` is the same node with a different expression, and
      # the enclosing class object is not that object's singleton class.
      # Declining is the honest answer; `024.85` records that the parser's
      # `Cref` makes the same approximation on the declaration side.
      #
      # `#enclosing_class_object` rather than a bare wrap: after `024.85`
      # a class body already holds the class object, and wrapping it again
      # would make `class << self` `ClassOf[ClassOf[W]]`.
      @self_type_stack.push(node.expression.is_a?(Prism::SelfNode) ? enclosing_class_object : nil)
      locate(node.body, offset, {})
    ensure
      @in_singleton_class = previous_in_singleton_class
      @self_type_stack.pop
    end

    def locate_in_def(node, offset)
      return Types::UNKNOWN unless contains?(node.location, offset)

      @self_type_stack.push(def_self_type(node))
      locate(node.body, offset, parameter_env(node))
    ensure
      @self_type_stack.pop
    end

    # What `self` is inside a `def`, which is not what the body around it
    # answered. The four shapes, each taken from Ruby -- the interpreter
    # sessions are pasted into `core/spec/ovallsp/self_receiver_spec.rb`,
    # which drives every one of them:
    #
    # - `def x` -- an instance of the owner, so the enclosing class object
    #   is unwrapped.
    # - `def x` written anywhere inside `class << self` -- still the class
    #   object. Ruby's default definee does not change when a method body
    #   opens, so a `def` nested two deep there is *still* a singleton
    #   method and its `self` is still the class. This is the case
    #   `Cref#declares_singleton?` exists for, and the reason this reads a
    #   context flag rather than the enclosing frame's type: after the
    #   change above, a class body and a `class << self` body both hold a
    #   class object, so the type alone cannot tell them apart.
    # - `def self.x` -- the class object, whatever the enclosing body is.
    # - `def Widget.x` -- *that* constant's class object. The lexical
    #   enclosure cannot supply it (a top-level `def Const.x` has none),
    #   so it is read off the receiver, through the same constant
    #   resolution a written `Widget` gets.
    #
    # A receiver this engine cannot name -- `def obj.x` -- answers nil.
    # Handing back the enclosing class instead is precisely the wrong
    # assertion `024.46` measured 55 false reports of.
    def def_self_type(node)
      case node.receiver
      when nil then @in_singleton_class ? enclosing_class_object : enclosing_instance
      when Prism::SelfNode then enclosing_class_object
      when Prism::ConstantReadNode, Prism::ConstantPathNode then eval_constant(node.receiver)
      end
    end

    # The class object the enclosing frame already denotes, or nil where
    # there is no enclosing frame -- a `def self.x` or a `class << self`
    # at the top level of a file, whose `self` is `main` rather than any
    # class. `Types.class_object` is not idempotent (`W.class` is
    # `Class`), so a frame that is already a class object is returned as
    # it stands rather than wrapped a second time.
    def enclosing_class_object
      enclosing = @self_type_stack.last
      return nil if enclosing.nil?

      Types.class_object?(enclosing) ? enclosing : Types.class_object(enclosing)
    end

    # And its inverse: an instance of whatever the enclosing frame is the
    # class object of. `Types.class_object_lookup` is the one place that
    # takes a `ClassOf` apart, so this does not re-derive the rule -- and
    # it already answers nil for nil (`class_object?(nil)` is false, so it
    # hands the value straight back), which is why there is no guard here.
    # There was one; it could be removed with the whole suite green,
    # because it could not change an answer.
    def enclosing_instance
      Types.class_object_lookup(@self_type_stack.last).first
    end

    # A method's parameters are bindings its body can see, so a cursor
    # inside that body is in their scope. Nothing infers their types
    # without a call site, so they enter as Unknown -- which is the honest
    # answer and still lets completion offer the name.
    #
    # It reaches `infer_at` as well, which an earlier version of this
    # comment denied. A branch's merge falls back to the *entering*
    # environment, so a parameter assigned in one arm used to merge
    # against an absent key and answer `Integer | nil` -- claiming the
    # method can be reached with the parameter already nil, which its
    # signature does not say. It answers `Integer | Unknown` now.
    #
    # The Symbol keys are the environment's convention everywhere else,
    # because that is how Prism names a node -- but no test can currently
    # distinguish them from String keys, and the reason is worth stating
    # rather than rediscovering: a read misses on the wrong key and
    # `eval_type` answers Unknown for a miss, which is also what a hit
    # answers while every parameter enters as Unknown. The choice stops
    # being unobservable the moment a parameter carries a real type (a
    # signature, an inferred call site), at which point a String key would
    # silently un-shadow a same-named method.
    def parameter_env(def_node)
      params = def_node.parameters
      return {} unless params

      names = []
      names.concat(params.requireds.map { |p| p.respond_to?(:name) ? p.name : nil })
      names.concat(params.optionals.map(&:name))
      # `posts` are the requireds that follow a splat -- `def go(a, *rest,
      # z)`. Legal Ruby, and `z` was simply absent from the locals.
      names.concat(params.posts.map { |p| p.respond_to?(:name) ? p.name : nil })
      names.concat(params.keywords.map(&:name))
      names << params.rest&.name
      names << params.keyword_rest&.name if params.keyword_rest.respond_to?(:name)
      names << params.block&.name
      names.compact.to_h { |name| [name.to_sym, Types::UNKNOWN] }
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
      # Unknown, not the enclosing call's type and not a descent. The
      # receiver is not a generic, so nothing is known about what the
      # block yields -- and answering with the *call's* type said
      # `OptionParser` for a string literal inside `opts.on(...) do`,
      # which 0.2.0 publishes as an `argument-type` diagnostic. Descending
      # is the right answer and cannot be given yet: the offsets a
      # receiver is recorded at resolve to the wrong node under this
      # file's inclusive `contains?`, so descending turned that latent
      # mis-resolution into 230 new `unknown-method` reports across the
      # stdlib (024.20). Unknown is what both checks decline on.
      return Types::UNKNOWN unless nested_env

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
          # A cursor on a blank line sits inside no statement, so the
          # entry capture in #locate saw only the bindings from before
          # this one. Re-capturing here is what makes a local assigned on
          # the previous line visible -- but only for a statement that
          # *ends before* the cursor, since this loop also walks the
          # statements that follow it and their bindings are not in scope
          # yet (0.2.0).
          capture_scope(env) if @capturing_scope && stmt.location.end_offset <= offset
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

    # The type of `a` after `a ||= b`, from what Ruby actually does:
    #
    #     b = nil;  b ||= "x";  b.class   # => String   (the write runs)
    #     c = 1;    c ||= "x";  c.class   # => Integer  (it does not)
    #
    # Three cases, and the middle one is why this is a union rather than
    # a replacement: a variable that *may* be nil keeps what it had and
    # gains the right-hand side.
    #
    # `Unknown` in, `Unknown` out: if the prior type is not known, then
    # whether the write runs is not known either, and a union built on
    # that guess would be an assertion made from a question that could
    # not be asked.
    def or_write_type(existing, written)
      return written if existing == Types::NIL
      return Types::UNKNOWN if existing == Types::UNKNOWN
      return existing unless existing.is_a?(Types::Union) && existing.members.include?(Types::NIL)

      Types.normalize_union([Types.remove_nil(existing), written])
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
      # `024.131`. `a ||= b` is `a || (a = b)`. There was no case for
      # either `OrWrite` node, so the write was never seen and whatever
      # the variable held before stood -- `b = nil; b ||= "x"` answered
      # `nil` for a `String`, which is a wrong answer rather than an
      # absent one.
      when Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode
        env[node.name] = or_write_type(env.fetch(node.name, Types::UNKNOWN), eval_type(node.value, env))
      # One table, shared with `MethodAnalyzer#eval_node`. They drifted
      # twice -- `Range`/`Regexp` added to both, then `Lambda`/`!`/`&&`/
      # `||` added here alone -- and each time the symptom was the same
      # expression typing correctly on one line and losing its type as
      # the last line of a method.
      when Prism::AndNode, Prism::OrNode
        Types::LiteralTypes.boolean_operator(node, eval_type(node.left, env), eval_type(node.right, env))
      when Prism::NilNode then Types::NIL
      when Prism::ArrayNode then eval_array(node, env)
      # Generic, matching `[]` and `Hash.new`: one kind of value renders
      # one way, whichever spelling produced it (024.12). Not for dispatch
      # -- the container rules have no `Hash` entry -- purely so the same
      # value does not render two ways depending on how it was written.
      when Prism::HashNode then Types::Generic.new(name: "Hash", type_arg: Types::UNKNOWN)
      when ->(other) { Types::LiteralTypes.for_node(other) } then Types::LiteralTypes.for_node(node)
      # `self` is whatever the descent last pushed, and after `024.85`
      # that value is `self` at this exact point rather than "an instance
      # of the enclosing class": `#locate_in_namespace` pushes the class
      # object, `#locate_in_def` unwraps it for an instance method body,
      # and both `class << self` and `def self.x` leave it alone.
      #
      # 0.2.1 added this case reading the *old* stack and it cost **55
      # new false diagnostics over Ruby's own standard library, removing
      # none** (`024.46`). All three families it recorded were the value
      # being wrong rather than the case existing:
      #
      # - `self.class.foo` became `Class has no method named foo`, because
      #   `#class` went through RBS to `Class`. `#resolve_call` answers
      #   the receiver's class *object* now, and a `ClassOf` receiver is
      #   not something the unknown-method check asserts about.
      # - `def Const.method` bodies typed `self` as an instance, because
      #   the push looked only for a literal `self` receiver.
      #   `#def_self_type` reads the constant.
      # - a `class << self` body typed `self` as an instance one `def`
      #   down, for the same reason; `@in_singleton_class` decides it now.
      #
      # nil at the top level of a file -- `self` there is `main`, an
      # ordinary Object -- and Unknown is what a caller must be handed for
      # that, not a stack frame that is not there.
      when Prism::SelfNode then @self_type_stack.last || Types::UNKNOWN
      when Prism::ParenthesesNode then eval_type(node.body, env)
      # `!x` is a CallNode whose message is `!`, and Ruby guarantees its
      # class whatever `x` is -- one of the few calls whose return type
      # needs no lookup at all.
      when Prism::CallNode
        Types::LiteralTypes.negation?(node) ? Types::LiteralTypes::NEGATION_TYPE : eval_call(node, env)
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
    # **A constant that holds a value is not a class object.**
    # `MAX_RETRIES = 3` read as `ClassOf[MAX_RETRIES]`, and so did a
    # String, an Array, a Float and a frozen Hash — an assertion, not a
    # decline, on the most ordinary thing in Ruby, and it silenced
    # completion and the undefined-method check at every use (`024.84`).
    #
    # Three answers, in this order:
    #
    # - the workspace declares a **class or module** by that name, so it
    #   really is a class object. This is what `ClassOf` exists for and
    #   what makes `Widget.new` work.
    # - the workspace declares a **constant** by that name and recorded
    #   what it was assigned, so the type is the assigned value's. Even
    #   `KLASS = Widget` was wrong before this: it answered
    #   `ClassOf[KLASS]`, naming the constant rather than the class.
    # - neither, so nothing here knows better than the guess that was
    #   always made. An unread gem's `SomeGem::Thing.new` depends on it.
    def eval_constant(node)
      name = node.full_name
      return Types::UNKNOWN if name.nil? || name.empty?

      assigned = assigned_constant_type(name)
      return assigned if assigned

      Types.class_object(Types::Nominal.new(name: constant_type_name(name)))
    rescue StandardError
      # `full_name` raises on a dynamic constant path (`Foo::(bar)`).
      Types::UNKNOWN
    end

    # The type of what a constant was assigned, or nil when the workspace
    # cannot say — which is every case the answer above already handles.
    #
    # Depth-bounded because constants can name each other, and a cycle
    # (`A = B` beside `B = A`) is a program a user can write. One level
    # of indirection is what `KLASS = Widget` needs; the bound is what
    # stops a cycle from being a hang.
    def assigned_constant_type(written)
      return nil unless @workspace_index
      return nil if @constant_depth >= MAX_CONSTANT_DEPTH

      body = assigned_constant_body(written)
      return nil if body.nil? || body.empty?

      result = Prism.parse(body)
      statement = result.success? ? result.value.statements.body.first : nil
      return nil unless statement

      @constant_depth += 1
      begin
        type = eval_type(statement, {})
        type unless type.nil? || type == Types::UNKNOWN
      ensure
        @constant_depth -= 1
      end
    end

    # **Ruby's constant lookup, for a constant rather than a type.**
    # `#qualify_constant` answers about *type* names -- it asks
    # `WorkspaceIndex#nested_type_name` -- so `MAX` written inside
    # `class C` came back as `MAX` and every lookup missed. Written that
    # way first, and the symptom was every constant answering exactly as
    # it had before, which is what a lookup that silently finds nothing
    # looks like.
    #
    # The index keys a constant by owner and bare name (`owner: "::C",
    # name: "MAX"`), so a written name is tried against each enclosing
    # frame, innermost first, and then at the top level -- which is the
    # order Ruby resolves one in. A name written with `::` in it is
    # already qualified and is only split.
    def assigned_constant_body(written)
      text = written.to_s
      owners =
        if text.include?("::")
          owner, _, bare = text.rpartition("::")
          return nil if bare.empty?

          return constant_body(owner.empty? ? nil : owner, bare)
        else
          current_nesting + [nil]
        end

      owners.each do |owner|
        body = constant_body(owner, text)
        return body if body
      end
      nil
    end

    def constant_body(owner, bare)
      symbol = Index::SymbolId.new(kind: :constant, owner: owner, name: bare, discriminator: nil)
      # `[uri, declaration]`, in that order. Read the other way round
      # first, and the `NoMethodError` that produced was swallowed whole
      # by `#eval_constant`'s `rescue` -- which is there for `full_name`
      # raising on a dynamic path and caught this instead.
      _uri, declaration = @workspace_index.declarations_with_uri(symbol).first
      declaration&.body_source
    end

    # **The one place a constant node becomes a class name.** There were
    # two -- `#eval_constant` and `#constant_receiver_name` -- and they
    # agreed only by accident: teaching one of them the nesting rule left
    # `Config.new` resolving correctly and `Config.new.app_only` not,
    # which is `024.103` surviving its own fix. Both read this.
    #
    # `Config` written inside `module App` means `App::Config` if `App`
    # declares one, and the top-level `Config` only if it does not --
    # Ruby's `Module.nesting` rule, applied here where the nesting is
    # known. A bare `Nominal` carries no nesting, so every reader
    # downstream was guessing, and `024.103` is what they guessed.
    def constant_type_name(name)
      Semantic::ReceiverResolution.canonical_receiver_name(qualify_constant(name))
    end

    # Ruby's rule, in Ruby's order:
    #
    #   1. `Module.nesting`, innermost first;
    #   2. **the ancestors of the innermost cref**;
    #   3. Object, which is the fall-through this returns `name` for.
    #
    #   $ ruby -e '
    #   class Config; def top_only; end; end
    #   class Zbase; class Config; def zbase_only; end; end; end
    #   module App
    #     class Runner < Zbase
    #       def go  = Config.new.zbase_only
    #       def bad = Config.new.top_only
    #     end
    #   end
    #   p ["go",  (App::Runner.new.go  rescue $!.class)]
    #   p ["bad", (App::Runner.new.bad rescue $!.class)]
    #   '
    #   # => ["go", nil]
    #   # => ["bad", NoMethodError]
    #   # ruby 3.4.10
    #
    # 0.2.10 implemented step 1 and stopped, which left both directions
    # inverted for an inherited namespace: the working call reported, the
    # raising one silent (`024.112`).
    def qualify_constant(name)
      return name unless @workspace_index
      return name if name.to_s.start_with?("::")

      @workspace_index.nested_type_name(name, nesting: current_nesting) ||
        ancestor_type_name(name) ||
        name
    end

    # Step 2. Only the *innermost* cref's ancestors: Ruby does not walk
    # the outer nesting frames' ancestors, and neither does this.
    #
    # **Not inside `class << self`.** The innermost cref there is the
    # singleton class, whose ancestors are not the enclosing class's --
    # `class SSub < SBase; class << self; Config` is a `NameError` in
    # Ruby even when `SBase::Config` exists, and answering `SBase::Config`
    # there names an owner the code never reaches.
    #
    # The self entry is dropped by *name*, not by position: with
    # `prepend M` the chain starts `["::M", "::Self", …]`, and taking
    # `.drop(1)` discarded the one namespace that could have answered
    # while re-searching the frame step 1 had already tried.
    def ancestor_type_name(name)
      return nil unless @hierarchy_index
      return nil if @in_singleton_class

      innermost = current_nesting.first
      return nil unless innermost

      qualified = Index::SymbolId.qualify_owner(innermost)
      ancestors = @hierarchy_index.ancestors(innermost).map(&:name).compact
                                  .reject { |a| Index::SymbolId.qualify_owner(a) == qualified }
      @workspace_index.nested_type_name(name, nesting: ancestors)
    end

    def current_nesting = Array(@lexical_nesting).reverse

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
      # `#class` before anything else can answer it. One table, shared
      # with `MethodAnalyzer#eval_call`, for the reason `LiteralTypes`
      # is: two evaluators that answer the same expression differently
      # make a value type correctly on its own line and lose its type as
      # a method's return.
      if Types.class_call?(node) && (class_object = Types.class_of(receiver_type))
        return class_object
      end

      if (receiver_name = constant_receiver_name(node.receiver))
        # The class, not the spelling the call site used. `::Widget` and
        # `Widget` are one class, and letting both through makes two
        # different Nominals -- whose union is not a single Nominal, which
        # is what the unknown-method check requires, so the check goes
        # silent for a variable assigned both ways (0.1.12).
        constant_type = Types::Nominal.new(name: receiver_name)
        signature_method = resolve_signature_call(
          constant_type, node, singleton: true, direct: true, env: env
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

        # `Struct.new(...)`, `Class.new` and `Data.define(...)` return a
        # *class*, not an instance of the constant named -- so the
        # ordinary `X.new -> X` rule answers `Struct`, and the `.new` that
        # follows was reported as an unknown method on it. Three sites in
        # Ruby's own standard library, on the plainest value-object idiom
        # there is.
        #
        # Unknown rather than a class object over some invented name: the
        # class is anonymous, this engine has nothing true to say about
        # it, and Unknown is the answer no check acts on.
        return Types::UNKNOWN if anonymous_class_factory?(constant_type, node)

        if node.name == :new
          singleton_method = resolve_source_method_member(constant_type, node.name, singleton: true)
          inherited_signature = resolve_signature_call(constant_type, node, singleton: true, direct: false, env: env)
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
        class_level = resolve_class_level_finder(receiver_name, node.name, positionals: positional_count(node))
        return class_level if class_level

        # `Widget.some_class_method` -- an ordinary (non-Active-Record)
        # singleton method call, e.g. Task 017's `scope` (which declares
        # its generated method with kind: :singleton_method). Tried after
        # the AR class-level finder specifically fails, not unconditionally,
        # so a real Active Record finder never gets shadowed by a same-
        # named source declaration.
        singleton_method = resolve_source_method_member(constant_type, node.name, singleton: true)
        return singleton_method if singleton_method

        inherited_signature = resolve_signature_call(constant_type, node, singleton: true, direct: false, env: env)
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

      signature = receiver_type && resolve_signature_call(receiver_type, node, direct: true, env: env)
      return signature if signature

      instance_level = receiver_type && resolve_instance_level(receiver_type, node.name,
                                                               positionals: positional_count(node))
      return instance_level if instance_level

      inherited_signature = receiver_type && resolve_signature_call(receiver_type, node, direct: false, env: env)
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
    def resolve_class_level_finder(class_name, method_name, positionals: 0)
      return nil unless @model_registry.known_model?(class_name)

      # The *model's* name, not the spelling the call site used: `::User`
      # and `User` are one class, and letting the receiver's spelling
      # through produced a `Nominal("::User")` that hovered as `::User`
      # and matched nothing downstream, since every other name in the type
      # model is bare.
      model_type = Types::Nominal.new(name: Semantic::ReceiverResolution.canonical_receiver_name(class_name))
      case method_name
      when :find then model_type
      when :find_by then Types.normalize_union([model_type, Types::NIL])
      when :where, :all then Types::Generic.new(name: "Relation", type_arg: model_type)
      else
        # Anything else the relation rules model, asked as if the call had
        # been written `Model.all.<name>` -- which is what Rails does:
        # `ActiveRecord::Querying` delegates every one of these to `all`.
        #
        # `Model.first` answered nothing until 0.2.6 while
        # `Model.scope.first` answered, so the working path was the rarer
        # one (`024.79`). Answered by delegating rather than by adding
        # names to the list above, so the two stay one rule as that list
        # grows -- `#resolve_relation_member` is where a relation method's
        # return type is decided, and it stays the only place.
        resolve_relation_member(Types::Generic.new(name: "Relation", type_arg: model_type), method_name,
                                positionals: positionals)
      end
    end

    def resolve_instance_level(receiver_type, method_name, positionals: 0)
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
            resolve_relation_member(receiver_type, method_name, positionals: positionals)
        end
      when Types::Union
        resolve_union_member(receiver_type, method_name, positionals: positionals)
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

    # `env:` is threaded so the argument *types* are available here, not
    # only their count -- `024.128`. Every caller is inside
    # `#resolve_call`, which already has it.
    #
    # **And it is required**, which is the correction `024.242` bought.
    # The sentence above was true and was not enough: every caller did
    # have an env, and one of the five did not pass it -- the
    # constant-receiver rung. With no env, `argument_types` below is nil
    # and every overload of the right arity joins the union, so
    # `Zoo.pick(1)` answered both declared returns while
    # `k = Zoo; k.pick(1)` answered the one RBS keys on an Integer
    # argument. Two ladders to one question, differing by a defaulted
    # keyword.
    #
    # A regression test pins that one call; only a required keyword stops
    # the next site being written without it, which is the shape `049`
    # asked for. A caller with genuinely no environment -- a spec driving
    # this method on a bare parsed fragment -- passes `env: nil` and says
    # so.
    def resolve_signature_call(receiver_type, node, env:, singleton: false, direct: nil)
      return nil unless @signatures

      if receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"
        return resolve_signature_call(receiver_type.type_arg, node, singleton: true, direct: direct, env: env)
      end
      if receiver_type.is_a?(Types::Union)
        resolved = receiver_type.members.filter_map do |member|
          next if member == Types::NIL

          resolve_signature_call(member, node, singleton: singleton, direct: direct, env: env)
        end
        return Types.normalize_union(resolved) unless resolved.empty?
        return nil
      end
      generic_type_arg = receiver_type.type_arg if receiver_type.is_a?(Types::Generic)
      receiver_type = Types::Nominal.new(name: receiver_type.name) if receiver_type.is_a?(Types::Generic)
      return nil unless receiver_type.is_a?(Types::Nominal)

      # `owner` is reused below to ask the signature environment for the
      # receiver's own type parameters, which is a *type name* query and
      # not a `SymbolId` -- so the qualified form is still needed as a
      # value here, rather than only inside the SymbolId.
      owner = Index::SymbolId.qualify_owner(receiver_type.name)
      symbol_id = Index::SymbolId.new(
        kind: singleton ? :singleton_method : :instance_method, owner: owner,
        name: node.name.to_s, discriminator: nil
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
      # `024.128`. The argument types the call site already has, so the
      # resolver can read the key RBS puts on an overload rather than
      # unioning every one that happens to take the right number of
      # arguments. `nil` where the shape is not countable at all --
      # forwarding or a splat -- since there is then no argument list to
      # describe.
      argument_types =
        positional_count.nil? || env.nil? ? nil : positional_arguments.map { |argument| eval_type(argument, env) }

      resolved = Signatures::OverloadResolver.resolve(
        signature.overloads, positional_count: positional_count, keyword_names: keyword_names,
        # `...` forwards the caller's block too, so a forwarding call may
        # supply one even though this call site writes no literal block.
        block_given: !node.block.nil? || forwarding, receiver_bindings: bindings,
        argument_types: argument_types
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

      owner = Index::SymbolId.qualify_owner(receiver_type.name)
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
    def resolve_union_member(union_type, method_name, positionals: 0)
      resolved = union_type.members.filter_map do |member|
        next if member == Types::NIL

        resolve_instance_level(member, method_name, positionals: positionals)
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

    # The finders that answer with a *record* rather than another
    # relation. `#first` was the only one modelled until 0.2.6, so
    # `orders.last` and `User.last` both answered nothing while
    # `orders.first` answered -- and `last` is as everyday as `first`.
    #
    # `#find` is here rather than only on the model class because
    # `Relation#find` is the same method reached through a scope, and the
    # bang forms raise instead of returning nil, which is exactly the
    # difference between the two columns.
    # Keyed by how many positional arguments the call may carry, because
    # every one of these answers an *Array* at some other arity and the
    # table used to key on the name alone: `User.last(3)` inferred
    # `User | nil`, and the check then reported `recent.map` as an unknown
    # method on `User` -- a wrong answer where 0.2.5 had none, which is the
    # trade section 0.4 puts first.
    #
    # `first`/`last`/`take` answer a record only with no arguments; `find`
    # only with exactly one, since several ids give an Array too. The
    # Array shapes are deliberately not modelled here -- silence is the
    # fix, and `Array[T]` would be a capability.
    RELATION_RECORD_FINDERS = {
      first: [:optional, 0], last: [:optional, 0], take: [:optional, 0],
      first!: [:certain, 0], last!: [:certain, 0], take!: [:certain, 0],
      find: [:certain, 1]
    }.freeze

    # `Relation[T]#first`/`CollectionProxy[T]#first` -> T | nil,
    # `#first!` -> T, and the rest of RELATION_RECORD_FINDERS the same
    # way. `#resolve_class_level_finder` delegates here, so `Model.last`
    # and `Model.all.last` are one rule rather than two lists that drift.
    def resolve_relation_member(generic_type, method_name, positionals: 0)
      return nil unless RELATION_LIKE.include?(generic_type.name)

      certainty, arity = RELATION_RECORD_FINDERS[method_name]
      return nil unless certainty && positionals == arity

      certainty == :optional ? Types.normalize_union([generic_type.type_arg, Types::NIL]) : generic_type.type_arg
    end

    # How many positional arguments a call carries. A trailing keyword
    # hash is not one, and a splat makes the count a lower bound rather
    # than a count -- so it answers nil, which no arity in the table
    # matches and which therefore declines rather than guesses.
    def positional_count(node)
      arguments = node.arguments&.arguments
      return 0 if arguments.nil? || arguments.empty?
      return nil if arguments.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::ForwardingArgumentsNode) }

      arguments.count { |a| !a.is_a?(Prism::KeywordHashNode) }
    end

    def constant_receiver?(node)
      node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    end

    # The canonical name of a constant receiver, or nil when it is not one
    # -- and nil, rather than a raise, when it is a constant path whose
    # segments are not all constants (`klass::Error.new`, legal Ruby and
    # idiomatic in factory code). `#full_name` raises there, and asking it
    # unguarded meant the raise escaped to
    # `infer_ivars_for_method_node`'s blanket rescue, which answers with
    # the *initial* environment: one such expression anywhere in a
    # controller action silently voided every instance variable in it.
    # `#constant_path_type` and `MethodAnalyzer#eval_constant_receiver_call`
    # both already guarded this; this call site did not (0.1.12).
    # Measured: the kind check is redundant with the rescue below -- of
    # Prism's five node classes answering `#full_name`, only the two this
    # asks for can be a call receiver, so a non-constant receiver reaches
    # `NoMethodError` and comes back nil either way, and no input
    # distinguishes them. It stays because asking the question is not the
    # same as discovering the answer by exception, and a sweep that finds
    # this line unpinned should stop here rather than churn on it.
    def constant_receiver_name(node)
      return nil unless constant_receiver?(node)

      constant_type_name(node.full_name)
    rescue StandardError
      nil
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
        # Through the helper, not `#full_name` directly: `is_a?`'s argument
        # is the second place a constant receiver's name is read, and a
        # dynamic path there raised exactly as it did in `resolve_call`,
        # taking the whole method's instance variables with it (0.1.12).
        if (arg_name = constant_receiver_name(arg))
          env[receiver.name] = Types::Nominal.new(name: arg_name)
        end
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
        Index::SymbolId.qualify_within(@owner_stack.last, local_path)
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

    # Every receiverless call made directly in the requested class body.
    # `BeforeActionFinder` below walks the same statements looking for the
    # two names it models; this reports all of them, so a caller can ask
    # whether anything *unmodelled* is there.
    class ClassBodyCallFinder < Prism::Visitor
      attr_reader :names

      def initialize(owner_name)
        super()
        @owner_name = owner_name
        @owner_stack = []
        @names = []
      end

      def visit_module_node(node) = visit_namespace(node)
      def visit_class_node(node) = visit_namespace(node)

      private

      def visit_namespace(node)
        @owner_stack.push(Index::SymbolId.qualify_within(@owner_stack.last, node.constant_path.full_name))
        if @owner_stack.last == @owner_name
          node.body&.body&.each do |statement|
            @names << statement.name.to_s if statement.is_a?(Prism::CallNode) && statement.receiver.nil?
          end
        else
          node.each_child_node { |child| child.accept(self) }
        end
      ensure
        @owner_stack.pop
      end
    end
    private_constant :ClassBodyCallFinder

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
        Index::SymbolId.qualify_within(@owner_stack.last, local_path)
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
