# frozen_string_literal: true

require "prism"
require_relative "../types"
require_relative "method_summary_store"
require_relative "receiver_resolution"

module Ovallsp
  module Semantic
    # Infers a method's return type from its body: the implicit value of
    # its last reached statement, unioned with every explicit `return`'s
    # value across every path that can reach one — and, along the way,
    # resolves the methods it calls (through Semantic::MethodResolver,
    # Task 009) to recursively summarize *their* return types too, so a
    # multi-step call chain (`current_user.company.orders.first.total`)
    # propagates real types end to end instead of stopping at the first
    # unresolved hop (docs/design/tasks/010-method-summaries-and-call-chains.md).
    #
    # Each #summarize call consults MethodSummaryStore's cache first; a
    # cache miss computes fresh and stores the result (with its
    # dependency edges) before returning it. Recursion (direct or mutual)
    # is cut off by an in-flight guard, and an overall call-depth budget
    # prevents runaway analysis from occupying the calling thread
    # indefinitely — both degrade to a widened (Unknown-leaning, low-
    # confidence) result rather than hanging or raising.
    class MethodAnalyzer
      DEFAULT_BUDGET = 12

      # A single evaluation outcome: `type` is what an expression (or a
      # run of statements) evaluates to; `terminated` means this path
      # definitely exits via an explicit `return` here, so anything
      # lexically after it in the same statement run never executes —
      # mirrors LocalInferencer's own branch-termination tracking (Task
      # 008.5 item 7), but this evaluator is otherwise independent of
      # LocalInferencer: it resolves calls through Semantic::MethodResolver
      # (Task 009) instead of LocalInferencer's own ad hoc heuristics,
      # which is the whole point of this task.
      Flow = Struct.new(:type, :terminated)
      private_constant :Flow

      def initialize(workspace_index:, method_resolver:, summary_store:, model_registry: nil, generated_method_index: nil)
        @workspace_index = workspace_index
        @method_resolver = method_resolver
        @summary_store = summary_store
        @model_registry = model_registry
        @generated_method_index = generated_method_index
      end

      # `context` accepts `in_progress:` (a Set of SymbolIds currently
      # being computed, for recursion detection — callers normally never
      # pass this themselves; it's threaded through recursive calls this
      # method makes into itself) and `budget:` is the max call-chain
      # depth before further analysis widens to Unknown rather than
      # continuing indefinitely.
      def summarize(symbol_id:, context: {}, budget: DEFAULT_BUDGET)
        cached = @summary_store.fetch(symbol_id)
        return cached if cached

        compute(symbol_id, in_progress: context[:in_progress] || Set.new, depth: context[:depth] || 0, budget: budget)
      end

      private

      def compute(symbol_id, in_progress:, depth:, budget:)
        return widened(symbol_id, :recursive_widened) if in_progress.include?(symbol_id)
        return widened(symbol_id, :timeout) if depth >= budget

        declarations = @workspace_index.declarations_with_uri(symbol_id)
        return widened(symbol_id, :partial) if declarations.empty?

        nested_in_progress = in_progress | [symbol_id]
        self_type = self_type_for(symbol_id)

        results = declarations.map do |(_uri, decl)|
          analyze_declaration(symbol_id, decl, self_type, nested_in_progress, depth, budget)
        end

        summary = build_summary(symbol_id, declarations, results)
        @summary_store.replace(summary)
        summary
      end

      # "overloaded declarations without RBS degrade conservatively": more
      # than one declaration for the same symbol_id (a reopened class
      # redefining the method, or a genuine ambiguity we can't resolve
      # without RBS overloads — out of scope) unions every declaration's
      # own inferred type and drops confidence to :low, rather than
      # picking one arbitrarily and presenting it as certain.
      def build_summary(symbol_id, declarations, results)
        return_type = Types.normalize_union(results.map(&:type))
        dependencies = results.flat_map(&:dependencies).uniq
        multiple_declarations = declarations.size > 1
        confidence = results.any? { |r| r.confidence == :low } || multiple_declarations ? :low : :high
        status =
          if results.any? { |r| r.status == :timeout }
            :timeout
          elsif results.any? { |r| r.status == :recursive_widened }
            :recursive_widened
          else
            :complete
          end

        MethodSummary.new(
          symbol_id: symbol_id, parameter_types: parameter_types_for(declarations.first.last), return_type: return_type,
          effects: [], dependencies: dependencies, confidence: confidence, generation: @summary_store.generation,
          status: status
        )
      end

      def parameter_types_for(declaration)
        declaration.parameters.each_with_object({}) { |param, hash| hash[param.name] = Types::UNKNOWN if param.name }
      end

      DeclResult = Struct.new(:type, :dependencies, :confidence, :status)
      private_constant :DeclResult

      # Task 017: a `declaration.origin == :generated` (a `enum`/`scope`/
      # `delegate`-produced method, per ParserService's synthetic
      # Declaration) never has real body_source to analyze -- its return
      # type comes from GeneratedMethodIndex instead, checked here first
      # rather than falling through to the `unless declaration.body_source`
      # guard below (which would otherwise widen it to Unknown/:partial,
      # discarding a fact we actually have).
      def analyze_declaration(symbol_id, declaration, self_type, in_progress, depth, budget)
        generated = @generated_method_index&.fact_for(symbol_id)
        return DeclResult.new(resolved_generated_return_type(generated), [], generated.confidence, :complete) if generated

        return DeclResult.new(Types::UNKNOWN, [], :low, :partial) unless declaration.body_source

        result = Prism.parse(declaration.body_source)
        return DeclResult.new(Types::UNKNOWN, [], :low, :partial) unless result.errors.empty?

        ctx = { self_type: self_type, in_progress: in_progress, depth: depth, budget: budget, dependencies: [],
                degraded: false, returns: [], nested_status: nil }
        outcome = eval_node(result.value.statements, ctx)

        # #eval_conditional's own branch-merge deliberately excludes a
        # terminated (returned-from) branch's type from what flows to
        # *subsequent statements* — that's correct for computing the
        # implicit fall-through value, but it means an explicit `return`'s
        # value must be collected separately here, or "return nil unless
        # flag; User.new" would only ever produce "User", silently
        # dropping the nil exit path entirely.
        overall_type = Types.normalize_union([outcome.type, *ctx[:returns]])

        DeclResult.new(overall_type, ctx[:dependencies].uniq, ctx[:degraded] ? :low : :high, ctx[:nested_status] || :complete)
      end

      # `enum`/`scope` already carry their real return type directly on
      # the fact; `delegate` deliberately doesn't (ParserService has no
      # access to Model registry facts at parse time) -- resolved here,
      # lazily, once @model_registry's association/column data is
      # actually available.
      def resolved_generated_return_type(fact)
        return fact.return_type unless fact.origin == :delegate

        resolve_delegate_return_type(fact)
      end

      # `delegate :name, to: :company` -- resolves by chasing `to:`'s
      # target through @model_registry the same way an ordinary
      # `company.name` association/column access would: `to:` must
      # itself be a known association on the delegating model, and the
      # delegated attribute must be a known column or association on
      # *that* model. Anything this can't establish statically (the
      # target isn't a real model association, the delegated name isn't
      # a real column/association on it, no Model registry data at all)
      # widens to Unknown rather than guessing.
      def resolve_delegate_return_type(fact)
        return Types::UNKNOWN unless @model_registry

        # The owner as written, minus a leading `::` -- not its simple
        # name. `split("::").last` is match-by-simple-name, so
        # `Admin::User`, which is not a model at all, resolved its
        # delegates against the top-level `User`'s associations. The
        # registry keys itself; this only has to stop mangling the name
        # before handing it over (0.1.12).
        owner_name = ReceiverResolution.canonical_receiver_name(fact.owner)
        association = @model_registry.association(owner_name, fact.metadata[:to])
        return Types::UNKNOWN unless association

        target_model = association.class_name
        delegated_name = fact.metadata[:delegated_name]
        type =
          if (column = @model_registry.column(target_model, delegated_name))
            base = Types::Nominal.new(name: column.ruby_type)
            column.nullable ? Types.normalize_union([base, Types::NIL]) : base
          elsif (nested = @model_registry.association(target_model, delegated_name))
            Types::Nominal.new(name: nested.class_name)
          end
        return Types::UNKNOWN unless type

        fact.metadata[:allow_nil] ? Types.normalize_union([type, Types::NIL]) : type
      end

      # `SymbolId#owner` is always `::`-qualified -- `SymbolId.qualify_owner`
      # guarantees it -- and that is the index's domain, not the type
      # model's. Spelling `self`'s type `::Widget` made it a different
      # Nominal from the `Widget` a constant receiver produces (0.1.12).
      def self_type_for(symbol_id)
        owner = Types::Nominal.new(name: ReceiverResolution.canonical_receiver_name(symbol_id.owner))
        symbol_id.kind == :singleton_method ? Types::Generic.new(name: "ClassOf", type_arg: owner) : owner
      end

      # A summary that was never actually computed (recursion/timeout cut
      # it off before any analysis ran, or no declaration exists at all)
      # -- deliberately NOT cached via #compute's normal @summary_store.replace
      # path (see #compute's callers), so a transient recursion-guard hit
      # during one call chain never poisons the cache for a later,
      # independent query of the same symbol_id.
      def widened(symbol_id, status)
        MethodSummary.new(
          symbol_id: symbol_id, parameter_types: {}, return_type: Types::UNKNOWN, effects: [], dependencies: [],
          confidence: :low, generation: @summary_store.generation, status: status
        )
      end

      # ---- expression/statement evaluation ----

      def eval_node(node, ctx)
        case node
        when nil then flow(Types::NIL, false)
        when Prism::StatementsNode then eval_statements(node, ctx)
        when Prism::ReturnNode then eval_return(node, ctx)
        when Prism::IfNode, Prism::UnlessNode then eval_conditional(node, ctx)
        when Prism::ParenthesesNode then eval_node(node.body, ctx)
        when Prism::SelfNode then flow(ctx[:self_type], false)
        when Prism::CallNode
          Types::LiteralTypes.negation?(node) ? literal(Types::LiteralTypes::NEGATION_TYPE) : eval_call(node, ctx)
        # `LiteralTypes` is one table read by this walk and by
        # `LocalInferencer#eval_type`, because they kept drifting: a
        # literal added to the other alone made a method *ending* in one
        # return Unknown to every caller, while the same expression
        # assigned to a local typed correctly. It has happened twice.
        when Prism::AndNode, Prism::OrNode
          left = eval_node(node.left, ctx)
          right = eval_node(node.right, ctx)
          literal(Types::LiteralTypes.boolean_operator(node, left.type, right.type))
        else literal_or_other(node, ctx)
        end
      end

      # The table first, then the shapes this walk models itself.
      def literal_or_other(node, ctx)
        known = Types::LiteralTypes.for_node(node)
        return literal(known) if known

        eval_other(node, ctx)
      end

      def eval_other(node, ctx)
        case node
        when Prism::NilNode then flow(Types::NIL, false)
        # Generic with an unknown element type: otherwise hovering `{}`
        # and hovering a method that returns `{}` disagree, which is 024.12
        # one call away. The element type is genuinely unknown here --
        # unlike LocalInferencer, this analyzer does not evaluate the
        # elements, so `["a"]` summarises as `Array[Unknown]` where the
        # literal itself infers `Array[String]`.
        when Prism::ArrayNode then literal(Types::Generic.new(name: "Array", type_arg: Types::UNKNOWN))
        when Prism::HashNode then literal(Types::Generic.new(name: "Hash", type_arg: Types::UNKNOWN))
        else
          ctx[:degraded] = true
          flow(Types::UNKNOWN, false)
        end
      end

      def literal(type)
        flow(type, false)
      end

      def flow(type, terminated)
        Flow.new(type, terminated)
      end

      def eval_statements(node, ctx)
        result = flow(Types::NIL, false)
        node.body.each do |stmt|
          result = eval_node(stmt, ctx)
          return result if result.terminated # dead code after an unconditional return never runs
        end
        result
      end

      def eval_return(node, ctx)
        value = node.arguments&.arguments&.first
        type = value ? eval_node(value, ctx).type : Types::NIL
        ctx[:returns] << type
        flow(type, true)
      end

      # Same branch-merge shape as LocalInferencer's #eval_conditional
      # (Task 008.5 item 7): both arms are evaluated, and if either
      # survives (doesn't unconditionally return), the merged result
      # flows onward; if *both* terminate, the whole conditional itself
      # counts as terminated too (e.g. every branch of an exhaustive
      # if/else returns). elsif is Prism's own IfNode nested in
      # `consequent`, recursed into directly so its predicate is actually
      # evaluated rather than treated as an unconditional else.
      def eval_conditional(node, ctx)
        then_outcome = node.statements ? eval_node(node.statements, ctx) : flow(Types::NIL, false)

        subsequent = node.consequent
        else_outcome =
          if subsequent.nil?
            flow(Types::NIL, false)
          elsif subsequent.is_a?(Prism::IfNode)
            eval_node(subsequent, ctx)
          else
            subsequent.statements ? eval_node(subsequent.statements, ctx) : flow(Types::NIL, false)
          end

        surviving = [then_outcome, else_outcome].reject(&:terminated)
        merged_type = Types.normalize_union((surviving.empty? ? [then_outcome, else_outcome] : surviving).map(&:type))
        flow(merged_type, surviving.empty?)
      end

      def eval_call(node, ctx)
        if node.receiver.nil?
          eval_implicit_self_call(node, ctx)
        elsif node.receiver.is_a?(Prism::SelfNode)
          eval_resolved_call(ctx[:self_type], node, ctx, implicit_self: true)
        elsif constant_receiver?(node.receiver)
          eval_constant_receiver_call(node, ctx)
        else
          receiver_type = eval_node(node.receiver, ctx).type
          eval_resolved_call(receiver_type, node, ctx, implicit_self: false)
        end
      end

      def eval_implicit_self_call(node, ctx)
        eval_resolved_call(ctx[:self_type], node, ctx, implicit_self: true)
      end

      def constant_receiver?(node)
        node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
      end

      # `Klass.new` -> Nominal(Klass); a known Active Record model's
      # `.find`/`.find_by` mirror LocalInferencer's own handling (Task
      # 007) at the same minimal level — full Relation/CollectionProxy
      # chaining stays LocalInferencer's territory for now, matching
      # Task 010's "block generic inference" out-of-scope boundary.
      def eval_constant_receiver_call(node, ctx)
        receiver = node.receiver
        return flow(Types::UNKNOWN, false) unless receiver.respond_to?(:full_name)

        # `full_name` answers whatever the source wrote, so `::Widget.new`
        # gives `::Widget` where `Widget.new` gives `Widget`. The type
        # model's names are bare; leaving the prefix on made the two
        # spellings two different Nominals, and a variable fed by both
        # became a union -- which the unknown-method check cannot use, so
        # it stopped reporting (0.1.12, the same fix as
        # `LocalInferencer#resolve_call`).
        class_name = ReceiverResolution.canonical_receiver_name(receiver.full_name)
        case node.name
        when :new
          flow(Types::Nominal.new(name: class_name), false)
        when :find
          flow(Types::Nominal.new(name: class_name), false)
        when :find_by
          flow(Types.normalize_union([Types::Nominal.new(name: class_name), Types::NIL]), false)
        else
          ctx[:degraded] = true
          flow(Types::UNKNOWN, false)
        end
      rescue StandardError
        ctx[:degraded] = true
        flow(Types::UNKNOWN, false)
      end

      # Resolves `node.name` against `receiver_type` via
      # Semantic::MethodResolver and recursively summarizes the winning
      # candidate (lowest lookup_rank), tracking it as a dependency so a
      # later change to *that* method invalidates this one too. An
      # unresolved call (no candidate found) degrades to Unknown without
      # raising — "unresolved ancestorでCoreが落ちず" applies just as much
      # to call resolution as to hierarchy lookups.
      def eval_resolved_call(receiver_type, node, ctx, implicit_self:)
        candidates = @method_resolver.resolve(
          receiver_type: receiver_type, name: node.name, context: { implicit_self: implicit_self }
        )
        best = candidates.min_by(&:lookup_rank)
        unless best
          ctx[:degraded] = true
          return flow(Types::UNKNOWN, false)
        end

        ctx[:dependencies] << best.symbol_id
        called = summarize(
          symbol_id: best.symbol_id, context: { in_progress: ctx[:in_progress], depth: ctx[:depth] + 1 },
          budget: ctx[:budget]
        )
        ctx[:degraded] = true if called.confidence == :low
        # A nested call that itself got cut off by recursion/timeout means
        # *this* declaration's own analysis is equally incomplete, not
        # just lower-confidence — propagate the strongest signal seen
        # anywhere in the call tree so the outer MethodSummary#status
        # reflects it too, matching build_summary's own :timeout >
        # :recursive_widened priority.
        if called.status == :timeout
          ctx[:nested_status] = :timeout
        elsif called.status == :recursive_widened && ctx[:nested_status] != :timeout
          ctx[:nested_status] = :recursive_widened
        end
        flow(called.return_type, false)
      end
    end
  end
end
