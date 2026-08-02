# frozen_string_literal: true

require_relative "finding"
require_relative "semantic_context"
require_relative "../parser_service"
require_relative "../semantic/reference_resolver"
require_relative "../semantic/receiver_resolution"
require_relative "../types"
require_relative "../index/symbol_id"

module Ovallsp
  module Diagnostics
    # Reports only high-confidence errors, by design -- "Core policy:
    # 誤検出率を最優先する" (false-positive rate is the top priority,
    # above catching everything) (docs/design/tasks/015-confidence-aware-diagnostics.md).
    #
    # Every check here reuses Semantic::ReferenceResolver's own
    # candidate resolution (Task 014) rather than re-implementing
    # receiver-type/method-lookup logic: a :method_call candidate that
    # ReferenceResolver couldn't resolve to *anything* -- not a source
    # declaration, not an RBS/Gem signature, not a route helper, not an
    # Active Record association/column -- against a receiver whose type
    # is a single, fully-*closed* Nominal (every ancestor is either a
    # workspace-declared type or a known RBS one, and nothing in the
    # chain declares `method_missing`) is the one shape "誤検出のない
    # unknown method" can safely mean. A Union receiver, an Unknown
    # receiver, or any external/unresolved ancestor in the chain simply
    # produces no finding at all -- never a guess.
    class Engine
      MODES = %i[safe standard strict].freeze
      MODE_RANK = { safe: 0, standard: 1, strict: 2 }.freeze
      ROUTE_HELPER_PATTERN = /\A(?<base>.+)_(?:path|url)\z/

      def analyze(document:, semantic_context:, mode: :safe, budget: nil)
        raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)

        summary = ParserService.new.summarize(document)
        # Everything below asks the type engine about positions in
        # `summary`'s coordinates, and for an .erb file those are the
        # *extracted* Ruby regions -- ParserService extracts before
        # parsing. Passing the raw template on meant every receiver in a
        # template was resolved against HTML, so a partial's local read as
        # a String and its own methods were reported missing. Extraction
        # preserves line and column layout, so no range needs remapping.
        document = analysis_document(document)
        resolver = build_resolver(semantic_context)
        resolved = resolver.resolve(document, summary.reference_candidates, uri: document.uri,
                                                                             generation: semantic_context.generation)
        resolved_locations = resolved.each_with_object({}) { |r, h| h[r.location] = true }

        findings = []
        findings.concat(syntax_findings(summary, semantic_context.generation))
        findings.concat(unknown_method_findings(document, summary, resolved_locations, semantic_context))
        if MODE_RANK.fetch(mode) >= MODE_RANK.fetch(:standard)
          findings.concat(unresolved_constant_findings(summary, semantic_context))
        end
        findings.concat(unknown_route_helper_findings(summary, resolved_locations, semantic_context))
        findings.concat(argument_count_findings(document, summary, semantic_context))
        findings.concat(argument_type_findings(document, summary, semantic_context))
        findings.concat(unassigned_ivar_findings(document, summary, semantic_context))

        budget ? findings.first(budget) : findings
      end

      private

      def analysis_document(document)
        return document unless document.uri.to_s.end_with?(".erb")

        TextDocument.new(
          uri: document.uri, text: Erb::RubyRegionExtractor.extract_ruby_source(document.text),
          version: document.version, language_id: "ruby"
        )
      end

      def build_resolver(context)
        Semantic::ReferenceResolver.new(
          workspace_index: context.workspace_index, method_resolver: context.method_resolver,
          local_inferencer: context.local_inferencer, model_registry: context.model_registry,
          route_registry: context.route_registry
        )
      end

      def syntax_findings(summary, generation)
        summary.diagnostics.map do |d|
          Finding.new(code: "syntax-error", message: d[:message], range: d[:range], severity: :error,
                      confidence: :high, generation: generation)
        end
      end

      def unknown_method_findings(document, summary, resolved_locations, context)
        # Without a loaded RBS environment there's no way to distinguish
        # "genuinely undefined method" from "an untracked Kernel/Object
        # builtin" (see #rbs_resolves?) -- rather than risk flagging
        # `puts` as unknown, this whole check simply doesn't run.
        return [] unless context.signatures

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :method_call
          next if resolved_locations[candidate.location]
          # `Class.new` (and friends: `allocate`, `name`, `superclass`, ...)
          # come from Class/Module's own ancestry, which HierarchyIndex's
          # singleton chain doesn't model (only Object/Kernel/BasicObject
          # on the instance side) -- LocalInferencer already special-cases
          # `.new` the same way (`resolve_call`'s `node.name == :new &&
          # constant_receiver?` check) rather than resolving it through
          # ordinary method lookup, so this must not flag what that path
          # already treats as always-available.
          next if candidate.singleton && candidate.name == "new"

          # Deliberately *not* `Types.base_nominal` here, unlike everywhere
          # else that reads a container receiver. A workspace that reopens
          # a core class makes its chain look closed while gems keep adding
          # to it, so admitting container receivers reported
          # `[1,2].second` -- ActiveSupport's, absent from stdlib RBS -- as
          # unknown. That trade is the wrong way round for this check,
          # whose whole policy is that a false report is worse than a
          # missed one. See 024.13.
          receiver_type = receiver_type_for(document, candidate, context)
          next unless receiver_type.is_a?(Types::Nominal)
          next unless closed_nominal?(receiver_type, candidate.singleton, context) ||
                      model_closed?(receiver_type, context)
          next if rbs_resolves?(candidate, receiver_type, context)
          next if model_resolves?(candidate, receiver_type, context)

          Finding.new(
            code: "unknown-method",
            message: "#{receiver_type} has no method named `#{candidate.name}`",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { receiver: receiver_type.to_s, ancestors_closed: true }, generation: context.generation
          )
        end
      end

      # Reports a call that cannot possibly bind, by comparing the call
      # site's positional arguments against the parameters of the source
      # declaration it resolves to.
      #
      # Deliberately the narrowest useful version. It reports only when
      # every input is certain:
      #
      # - the receiver resolves to exactly one source declaration, so
      #   there is one parameter list and no overload to choose between;
      # - the call passes no splat and no `...`, either of which makes the
      #   positional count a lower bound rather than a count;
      # - the declaration takes no `*rest`, which makes its maximum
      #   unbounded.
      #
      # Anything outside that says nothing rather than guessing. A false
      # "wrong number of arguments" on code that runs is worse than no
      # arity checking at all, which is what shipped until now.
      def argument_count_findings(document, summary, context)
        return [] unless context.method_resolver

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :method_call
          next unless (shape = candidate.arguments)
          next if shape[:splat]

          declaration = sole_source_declaration(document, candidate, context)
          next unless declaration

          parameters = declaration.parameters || []
          next if parameters.any? { |parameter| parameter.kind == :rest }

          required = parameters.count { |parameter| parameter.kind == :required }
          maximum = required + parameters.count { |parameter| parameter.kind == :optional }
          passed = shape[:positional]
          next if passed >= required && passed <= maximum

          Finding.new(
            code: "argument-count",
            message: "`#{candidate.name}` takes #{expected_arity(required, maximum)}, but #{passed} given",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { required: required, maximum: maximum, passed: passed }, generation: context.generation
          )
        end
      end

      # Reports a read of an instance variable that nothing assigns
      # (0.2.0, closes 024.R6).
      #
      # Ruby answers `nil` for an unassigned ivar rather than raising, so
      # `@usr` where the code meant `@user` is a mistake the language
      # never surfaces -- the view renders empty and nobody is told why.
      #
      # Runs only where a caller has worked out what this document is
      # actually given: `assigned_ivars` nil means no such context exists,
      # and reporting every `@ivar` in a file nobody established a context
      # for is exactly the wrong report. An *empty* set is a real answer
      # (an action that assigns nothing) and is checked.
      def unassigned_ivar_findings(document, summary, context)
        assigned = context.assigned_ivars
        return [] unless assigned

        # A name the document assigns itself is assigned, whatever its
        # caller does or does not hand it.
        local = ivar_writes(document)

        return [] if local.nil?

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :ivar
          next if local.include?(candidate.name)
          next if assigned.include?(candidate.name)

          Finding.new(
            code: "unassigned-ivar",
            message: "`#{candidate.name}` is never assigned before this is read",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { ivar: candidate.name }, generation: context.generation
          )
        end
      end

      # The parser records a read and a write as the same `:ivar`
      # candidate kind -- rename and references both want them together --
      # so the writes are recovered here instead. This is what makes
      # `<% @total = 1 %><%= @total %>` in a view not a mistake.
      def ivar_writes(document)
        result = Prism.parse(document.text)
        # A document that will not parse has already been reported as a
        # syntax error, and Prism still hands back whatever it could make
        # of it -- so the assignments below the break are simply missing
        # rather than absent. Reporting from that list adds a second,
        # wrong finding to a file whose real problem is already named.
        return nil if result.failure?

        collector = IvarWriteCollector.new
        result.value.accept(collector)
        collector.names
      rescue StandardError
        nil
      end

      # Every form of `@x = ...`: plain, `||=`/`&&=`, `+=` and friends,
      # and a block/rescue target. Missing one reports a variable the file
      # visibly assigns two lines up.
      class IvarWriteCollector < Prism::Visitor
        attr_reader :names

        def initialize
          @names = []
          super
        end

        %i[instance_variable_write_node instance_variable_or_write_node
           instance_variable_and_write_node instance_variable_operator_write_node
           instance_variable_target_node].each do |suffix|
          define_method(:"visit_#{suffix}") do |node|
            @names << node.name.to_s
            super(node)
          end
        end
      end

      # Reports a positional argument whose own inferred type cannot be
      # the type the signature declares for that parameter (0.2.0, closes
      # 024.R2).
      #
      # Held to the same standard as the count check above: a wrong
      # "expected Integer, got String" on code that runs is worse than no
      # type checking at all. So this reports only where every input is
      # stated rather than inferred:
      #
      # - the expected type comes from RBS/RBI, not from guessing at what
      #   a Ruby parameter is "used like" -- Ruby source declares no
      #   parameter types, and inferring them is a different project;
      # - the signature has exactly one overload, because an argument that
      #   cannot match one overload may be exactly right for another, and
      #   choosing between them is the guessing this refuses to do;
      # - the declared type is a plain class, not a union or an interface:
      #   "cannot be any member of this union" is a question this narrow
      #   version does not answer;
      # - the argument's own type is a plain class too, and is not that
      #   class or any of its descendants.
      #
      # Everything else stays silent.
      # Converted RBS names that look like Ruby constants and are not.
      NOT_A_RUBY_CLASS = %w[Boolean].freeze

      def argument_type_findings(document, summary, context)
        return [] unless context.signatures

        summary.reference_candidates.flat_map do |candidate|
          next [] unless candidate.kind == :method_call
          next [] unless (shape = candidate.arguments)
          next [] if shape[:splat]

          overload = sole_declared_overload(document, candidate, context)
          next [] unless overload

          mismatched_arguments(document, shape, overload, candidate, context)
        end
      end

      def mismatched_arguments(document, shape, overload, candidate, context)
        expected_types = overload.required_positionals + overload.optional_positionals
        locations = shape[:positional_locations] || []

        locations.each_with_index.filter_map do |range, index|
          expected = expected_types[index]
          next unless expected.is_a?(Types::Nominal)
          # RBS's `int`/`string`/`boolish` are aliases meaning "anything
          # that converts", not classes -- an object of an entirely
          # unrelated class satisfies one, so reporting against it is a
          # false positive by construction. A Ruby constant is
          # capitalised; these are not, which is what tells them apart.
          next unless expected.name.to_s.match?(/\A[A-Z]/)
          # `bool` converts to `Boolean`, which is capitalised and so
          # survives the rule above -- but there is no such Ruby class, so
          # its ancestor walk can never succeed and every argument would
          # be reported.
          next if NOT_A_RUBY_CLASS.include?(expected.name)

          # The *end* of the argument, not its start: at the start of
          # `SmallInteger.new` the innermost node containing the offset is
          # the constant, so the answer was `ClassOf[SmallInteger]` -- the
          # class object rather than the instance being passed. The end
          # offset is inclusive, so a literal still resolves to itself.
          # An argument whose source carries a top-level operator is not
          # judged at all. `infer_at` answers about the innermost node at
          # the offset it is given, and for `"=" * 80` that is the right
          # operand -- so the end offset says Integer about a String
          # argument, and the start offset says `ClassOf[...]` about
          # `SmallInteger.new`, which is why the end is used at all.
          # Neither is the argument's own type, and asking for that means
          # carrying the argument *node* here rather than a range. Until
          # it does, an expression is a shape this check declines rather
          # than one it guesses at.
          next if operator_expression?(document, range)

          actual = context.local_inferencer.infer_at(document, range[:end])
          next unless actual.is_a?(Types::Nominal)
          next if compatible_nominal?(actual, expected, context)

          Finding.new(
            code: "argument-type",
            message: "`#{candidate.name}` expects #{expected.name} here, but #{actual.name} is given",
            range: range, severity: :warning, confidence: :high,
            evidence: { expected: expected.name, actual: actual.name, position: index },
            generation: context.generation
          )
        end
      end

      # A subclass is a perfectly good instance of its parent, and
      # reporting one is the false positive this check most has to avoid:
      # it fires on correct, idiomatic code.
      #
      # The two ancestry sources have to be *joined*, not asked in
      # parallel. A real chain crosses the boundary -- `MyError <
      # StandardError` is in the workspace index and `StandardError <
      # Exception` is only in RBS -- so neither source alone contains the
      # pair, and asking both about the same class answers "no" for a
      # relation that plainly holds. The workspace chain is walked first,
      # then RBS is asked about every name it reached.
      #
      # Every name is compared bare. `HierarchyIndex` returns a
      # workspace-resolved entry `::`-prefixed and an external one without,
      # while a signature always names a type bare -- so comparing raw
      # meant no workspace-declared ancestor ever matched, including the
      # class itself.
      # Ruby's numeric tower is not its class hierarchy. `Integer` does
      # not inherit `Float`, but `zoom(2)` where a Float is declared is
      # ordinary working code: Ruby coerces, and every arithmetic
      # operation such a method can perform accepts both. `Numeric` needs
      # no entry -- `Integer < Numeric` is a real ancestry. The other
      # direction stays reported, because a Float where an Integer is
      # declared is what an array index or `String#*` actually breaks on.
      COERCES_TO = { "Integer" => %w[Float Complex Rational] }.freeze

      # A name a Ruby method can have *and* a reader would call an
      # identifier. Anything else -- `<=>`, `==`, `..`, `!`, `[]`, `<<`,
      # `+` -- is an operator, and the node at the argument's end offset
      # is then its right operand rather than the argument.
      IDENTIFIER_METHOD_NAME = /\A[A-Za-z_]\w*[?!]?\z/

      # Node types that are a composition rather than a value: their end
      # offset belongs to a sub-expression whose type is not the
      # argument's.
      COMPOSED_ARGUMENT_NODES = [Prism::RangeNode, Prism::AndNode, Prism::OrNode,
                                 Prism::IfNode, Prism::UnlessNode].freeze

      # Parsed rather than pattern-matched. The first version of this
      # listed the arithmetic operators, which is a list that cannot be
      # finished -- `"a" <=> "b"` is an Integer and was reported as a
      # String, and `1..5` as an Integer. Asking Prism what the argument
      # *is* answers for every shape at once, and an argument that does
      # not parse on its own is declined rather than guessed at.
      def operator_expression?(document, range)
        first = document.position_to_char_offset(range[:start])
        last = document.position_to_char_offset(range[:end])
        return true unless first && last && last > first

        node = Prism.parse(document.text[first...last].to_s).value.statements.body.first
        return true if node.nil?
        return true if COMPOSED_ARGUMENT_NODES.any? { |type| node.is_a?(type) }

        node.is_a?(Prism::CallNode) && !node.name.to_s.match?(IDENTIFIER_METHOD_NAME)
      rescue StandardError
        true
      end

      def compatible_nominal?(actual, expected, context)
        target = simple_name(expected.name)
        return true if COERCES_TO.fetch(simple_name(actual.name), []).include?(target)

        reachable = ancestor_names(actual.name, context)
        reachable.include?(target)
      end

      # No normalisation of the workspace side. `HierarchyIndex` returns a
      # class's own entry qualified (`::Widget`) and its inherited ones
      # bare, and the `expected` side arrives bare -- but the expected
      # type is necessarily RBS-declared, so `via_signatures` below
      # returns a bare name for it whichever way the workspace spelled it.
      # An earlier version mapped the workspace entries through
      # `simple_name` and claimed that without it no workspace ancestor
      # ever matched; no input reaches that, and both removing it and
      # doubling it leave every answer unchanged.
      def ancestor_names(name, context)
        workspace = ([name] + context.hierarchy_index.ancestors(name).map(&:name)).uniq

        # `Signatures::Environment#ancestors` resolves a *qualified* name:
        # `ancestors("Integer")` is empty while `ancestors("::Integer")` is
        # the real chain.
        via_signatures = workspace.flat_map do |entry|
          (context.signatures&.ancestors(qualified_owner(entry)) || []).map { |ancestor| simple_name(ancestor) }
        end

        (workspace + via_signatures).uniq
      end

      def simple_name(name)
        Index::SymbolId.bare_name(name)
      end

      # The one RBS/RBI overload this call's parameters are declared by, or
      # nil when the answer is not singular. Deliberately mirrors
      # #sole_source_declaration's shape: same receiver rule, same refusal
      # to choose between candidates.
      def sole_declared_overload(document, candidate, context)
        receiver_type = receiver_type_for(document, candidate, context)
        return nil unless receiver_type.is_a?(Types::Nominal)

        signature = declared_signature_for(receiver_type, candidate, context)
        return nil unless signature
        return nil unless signature.overloads.size == 1

        overload = signature.overloads.first
        # A `*rest` parameter makes the positional list a prefix rather
        # than a mapping, so index N is no longer necessarily parameter N.
        return nil if overload.rest_positional
        overload
      end

      def expected_arity(required, maximum)
        count = required == maximum ? required.to_s : "#{required}..#{maximum}"
        "#{count} argument#{maximum == 1 ? '' : 's'}"
      end

      # The one source declaration this call resolves to, or nil when the
      # answer is not singular: no candidate, a conditional (Union
      # receiver) candidate, or several declarations for the same name
      # (a reopened class, an override) whose parameter lists may differ.
      def sole_source_declaration(document, candidate, context)
        # Same as #unknown_method_findings: a container receiver is kept out
        # of this check rather than admitted (024.13).
        receiver_type = receiver_type_for(document, candidate, context)
        return nil unless receiver_type.is_a?(Types::Nominal)

        candidates = context.method_resolver.resolve(
          receiver_type: receiver_type, name: candidate.name,
          context: { singleton: candidate.singleton }
        )
        return nil unless candidates.size == 1
        return nil if candidates.first.conditional

        declarations = candidates.first.declarations
        return nil unless declarations.size == 1

        declarations.first[1]
      end

      def unresolved_constant_findings(summary, context)
        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :constant
          next if context.workspace_index.resolve_type_name(candidate.name)
          next if context.signatures && rbs_known_constant?(candidate.name, context.signatures)

          Finding.new(
            code: "unresolved-constant", message: "cannot resolve constant `#{candidate.name}`",
            range: candidate.location, severity: :warning, confidence: :low,
            evidence: { name: candidate.name }, generation: context.generation
          )
        end
      end

      def rbs_known_constant?(name, signatures)
        !signatures.ancestors(qualified_owner(name)).empty?
      rescue StandardError
        false
      end

      def unknown_route_helper_findings(summary, resolved_locations, context)
        return [] unless context.route_registry

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :method_call && candidate.receiver.nil?
          next if resolved_locations[candidate.location]

          match = ROUTE_HELPER_PATTERN.match(candidate.name)
          next unless match
          next if context.route_registry.helper(match[:base])

          Finding.new(
            code: "unknown-route-helper", message: "no route named `#{match[:base]}` (`#{candidate.name}` is unresolved)",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { helper: candidate.name }, generation: context.generation
          )
        end
      end

      # Delegates to Semantic::ReceiverResolution rather than keeping its
      # own copy of this logic: an earlier version duplicated it ad hoc
      # ("deliberately small"), and the Task 014-018 independent review
      # found the SAME namespace-collapsing false-positive bug in both
      # copies at once -- exactly the drift duplicating this logic
      # invites. Engine only needs the receiver's *type*, not a full
      # resolved Reference, to decide whether an unresolved candidate is
      # even eligible for the closed-receiver check below.
      def receiver_type_for(document, candidate, context)
        Semantic::ReceiverResolution.receiver_type_for(context.workspace_index, document, candidate, context.local_inferencer)
      end

      # "closed" means every ancestor is either a workspace-declared type
      # (its own method set is fully known to us) or a type Signatures::Environment
      # (RBS: stdlib/project sig/Gem) actually declares -- an ancestor
      # this codebase has *no* information about at all (an unresolved
      # constant, an unrecognized Gem class) means the receiver's real
      # method set could include anything, so nothing about it is ever
      # flagged. Also refuses to call anything "closed" if any ancestor
      # declares `method_missing` -- "method_missing、respond_to_missing?、
      # known DSL boundaryを考慮する".
      # An Active Record model is never *statically* closed: its ancestors
      # above ApplicationRecord are outside the workspace and have no
      # signatures, so #closed_nominal? is false for every model and this
      # check was silently inert for exactly the classes a Rails developer
      # writes most.
      #
      # The Runtime Agent closes it instead, by reporting what the loaded
      # class actually responds to. Three conditions, all necessary:
      #
      # - the model is known, so there is a method list to check against;
      # - `partial` is false, meaning columns were read successfully -- a
      #   model whose table is missing reports no attribute methods, and
      #   flagging `user.email` because the database was not migrated
      #   would be worse than saying nothing;
      # - the model does not define `method_missing`, which would make any
      #   name potentially valid. Read from the reported list rather than
      #   from the workspace index, so a `method_missing` inherited from a
      #   gem or a concern counts too.
      def model_closed?(nominal, context)
        registry = context.model_registry
        model = registry && registry.model(nominal.name)
        return false unless model
        return false if model.partial

        !model.instance_methods.include?("method_missing")
      end

      # Everything the running app says this model responds to: Active
      # Record's own API, plus this model's attribute/dirty/association/
      # enum/scope methods. Columns and associations are covered by the
      # method lists (Rails defines a reader for each), but are checked
      # too so a model whose method list could not be read still resolves
      # its own columns rather than reporting them as unknown.
      def model_resolves?(candidate, nominal, context)
        registry = context.model_registry
        model = registry && registry.model(nominal.name)
        return false unless model

        api = registry.active_record_api
        names = candidate.singleton ? model.singleton_methods + api[:singleton] : model.instance_methods + api[:instance]
        return true if names.include?(candidate.name)

        !candidate.singleton &&
          (model.columns.any? { |column| column.name == candidate.name } ||
            model.associations.any? { |association| association.name == candidate.name })
      end

      def closed_nominal?(nominal, singleton, context)
        entries = context.hierarchy_index.ancestors(nominal.name, singleton: singleton)
        return false if entries.empty?
        # Always asked of the *instance* chain, even for a singleton
        # lookup: a singleton chain ends at the class itself and never
        # reaches BasicObject, so asking it directly would call every
        # `Foo.bar` open and silence the check entirely.
        return false unless chain_reaches_root?(context.hierarchy_index.ancestors(nominal.name, singleton: false))
        return false unless entries.all? { |entry| ancestor_known?(entry, context) }
        return false if entries.any? { |entry| declares_method_missing?(entry.name, context) }

        # Asked of every link in the chain, not just the receiver. Once
        # `test/test_helper.rb` has reopened `ActiveSupport::TestCase`,
        # that name is workspace-declared, so every test file inheriting
        # from it has a chain that reaches BasicObject *through* it --
        # and the subclass itself is a genuine workspace class the Agent
        # rightly cannot place. Asking only about the receiver left every
        # `class FooTest < ActiveSupport::TestCase` reporting the whole
        # gem's API as unknown, which is the same false positive this
        # check came out of, one level down.
        #
        # Asked last, and only of a receiver every cheaper test has already
        # called closed: this is the one test that costs a round trip to
        # another process, and asking it first meant every Active Record
        # model and every module -- receivers the static tests were about
        # to rule out anyway -- queued a question whose answer could not
        # change the outcome.
        # Skipping `origin: :default` -- the Object/Kernel/BasicObject tail
        # HierarchyIndex appends to every class. Those are not links the
        # workspace wrote, so they cannot be ones it reopened, and asking
        # would spend a round trip to be told what RBS already says.
        entries.none? do |entry|
          entry.origin != :default && reopened_elsewhere?(entry.name, context)
        end
      end

      # Reopening a class that lives in a gem is syntactically identical
      # to defining it, so #chain_reaches_root? succeeds and the class
      # looks complete when it is not -- `module ActiveSupport; class
      # TestCase` in every Rails application's test/test_helper.rb indexes
      # as [itself, Object, Kernel, BasicObject] (024.R5). Static analysis
      # cannot tell the two apart; only the running application can.
      #
      # So it is asked, for the ancestors it really has. An ancestor
      # beyond the running Object's own, that the workspace does not
      # declare and RBS does not know, is code this class carries from
      # somewhere the static chain never walked -- which is exactly the
      # claim #closed_nominal? is making, disproved.
      #
      # Before the answer arrives the check stays silent for that
      # receiver, because reporting would be the guess already known to be
      # wrong for this shape. That deferral applies only while an Agent is
      # actually connected: with no Agent the answer can never come, so an
      # inactive registry leaves the static reading alone rather than
      # disabling the check for the whole session.
      def reopened_elsewhere?(raw_name, context)
        registry = context.ancestry_registry
        return false unless registry&.active?
        return false if raw_name.nil?

        # HierarchyIndex names workspace ancestors from the root ("::Foo")
        # while the registry and the Agent speak in plain names -- the
        # Agent would split a leading "::" into an empty first namespace
        # segment and answer "no such constant", which is a permanent
        # answer. Normalised here, at the one boundary between them.
        name = Index::SymbolId.bare_name(raw_name)
        entry = registry.entry(name)
        if entry.nil?
          registry.request(name)
          return true
        end

        case entry.status
        when :external then true
        when :loaded then entry.foreign_ancestors.any? { |ancestor| !locally_accounted_for?(ancestor, context) }
        else false
        end
      end

      # The Agent reports ancestors as the application names them
      # ("Shared"), while the index stores them fully qualified from root
      # ("::Shared") -- #resolve_type_name is the existing resolver for
      # exactly that mismatch, and is used here rather than an exact-name
      # lookup so a workspace concern is recognised as the workspace's own.
      # The resolved name has to *be* the ancestor, not merely share its
      # last segment. `#resolve_type_name` matches by unqualified simple
      # name, which is right for resolving what a user typed and wrong for
      # this: here the question is "is this exact ancestor the workspace's
      # own code", and a workspace `Assertions` answering for a gem's
      # `ActiveSupport::Testing::Assertions` is how one same-named constant
      # anywhere in the project silently defeated the evidence.
      def locally_accounted_for?(name, context)
        resolved = context.workspace_index.resolve_type_name(name)
        return true if resolved && Index::SymbolId.bare_name(resolved) == Index::SymbolId.bare_name(name)

        context.signatures && !context.signatures.ancestors(qualified_owner(name)).empty?
      end

      # Every Ruby class inherits from BasicObject, so a chain that does
      # not reach it did not end -- it stopped. Two ways that happens, and
      # both produced false "has no method named" against a real Rails
      # application:
      #
      # - the superclass name resolved to the class itself. `class
      #   Application < Rails::Application` inside `module Ovaldev` finds
      #   the workspace's own `Ovaldev::Application` by unqualified name,
      #   the walk detects the cycle and stops, and the class is left
      #   looking like its own complete ancestry.
      # - the superclass named something the workspace does not declare,
      #   so the walk had nowhere to continue.
      #
      # Requiring BasicObject makes both of those open rather than closed,
      # without needing to tell them apart. A class the workspace really
      # does define completely always reaches it, through the default
      # Object chain if it declares no parent at all.
      # Both spellings, because both reach here: `HierarchyIndex`'s default
      # chain names `BasicObject` bare, while a class written
      # `< ::BasicObject` produces an entry carrying the `::`. Comparing
      # one spelling judged such a class's chain not to reach the root,
      # which switched the unknown-method check off for it silently.
      #
      # One more place this rule was written by hand instead of delegated
      # (0.1.12) -- `SymbolId.qualify_owner` is the rule, and
      # `ROOT_SUPERCLASS_NAMES` in `HierarchyIndex` already listed both
      # forms, which is what made this an oversight rather than a choice.
      def chain_reaches_root?(entries)
        entries.any? { |entry| Index::SymbolId.qualify_owner(entry.name) == "::BasicObject" }
      end

      # A builtin ancestor (Object/Kernel/BasicObject, or any RBS-known
      # module/class in the chain) contributes real methods
      # (`puts`/`freeze`/`class`/...) that WorkspaceIndex/MethodResolver
      # have no idea about, since they were never Prism-parsed from any
      # workspace source file -- without this, *every* implicit-self
      # call to a Kernel method would misfire as "unknown method". Tried
      # across the whole ancestor chain, not just the receiver's own
      # name, the same reason #closed_nominal? checks every ancestor.
      # `HierarchyIndex` reports a class's *own* entry already qualified
      # (`::Widget`) while its inherited ones are bare (`Object`), so the
      # prefix has to be normalized rather than prepended. Prepending it
      # asked for `::::Widget`, which matches nothing -- and the visible
      # consequence was a false "has no method named" for anything a
      # project declared in its own `sig/` without also writing it in
      # Ruby, which is precisely the report this check exists not to make.
      def rbs_resolves?(candidate, receiver_type, context)
        return false unless context.signatures

        !declared_signature_for(receiver_type, candidate, context).nil?
      end

      # The signature declared for this call on the receiver or any of its
      # ancestors, or nil. Returns the signature rather than a boolean
      # because 0.2.0's argument check needs the parameter list, and
      # `rbs_resolves?` above only needs to know whether there was one.
      def declared_signature_for(receiver_type, candidate, context)
        # `lazy`, because this stops at the first ancestor that declares
        # the method and the chain can be long -- the shape it replaced
        # (`any?`) short-circuited, and turning it into a value lookup
        # lost that.
        context.hierarchy_index.ancestors(receiver_type.name, singleton: candidate.singleton).lazy.filter_map do |entry|
          kind = candidate.singleton && entry.origin != :extend ? :singleton_method : :instance_method
          # `owner:` is not qualified here: `SymbolId#initialize` does it
          # (0.1.12). This call site needed it before that existed, and
          # keeping it made a line no input could reach.
          symbol_id = Index::SymbolId.new(kind: kind, owner: entry.name, name: candidate.name,
                                          discriminator: nil)
          context.signatures.method_signatures(symbol_id)
        end.first
      end

      # `Signatures::Environment` resolves a *qualified* name, and the
      # names reaching it arrive both ways: `HierarchyIndex` returns a
      # class's own entry already qualified (`::Widget`) and its inherited
      # ones bare (`Object`), while a constant reference carries whatever
      # the source wrote (`::JSON` or `JSON`). Prepending rather than
      # normalizing asked for `::::JSON`, which matches nothing.
      #
      # Every caller goes through here, including the one whose input is
      # always plain today (`locally_accounted_for?`, whose name comes
      # from the Agent): four call sites and three of them wrong is what
      # having the rule stated in four places bought.
      def qualified_owner(name)
        Index::SymbolId.qualify_owner(name)
      end

      def ancestor_known?(entry, context)
        # A nameless ancestor is `class Foo < <expression>` -- there is
        # nothing to look up and nothing to know.
        return false if entry.name.nil?
        return true if entry.kind

        context.signatures && !context.signatures.ancestors(qualified_owner(entry.name)).empty?
      end

      def declares_method_missing?(owner, context)
        context.workspace_index.method_symbol_ids(owner, kind: :instance_method).any? { |sid| sid.name == "method_missing" }
      end
    end
  end
end
