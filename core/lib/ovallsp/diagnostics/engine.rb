# frozen_string_literal: true

require_relative "finding"
require_relative "semantic_context"
require_relative "../parser_service"
require_relative "../semantic/reference_resolver"
require_relative "../semantic/receiver_resolution"
require_relative "../types"
require_relative "../index/symbol_id"
require_relative "../index/type_name_resolution"

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
      # The three receivers whose member set no static analysis can
      # enumerate: everything loaded into the process adds to them.
      # `024.230`.
      OPEN_BY_CONSTRUCTION = %w[Object Kernel BasicObject].freeze

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

        findings = syntax_findings(summary, semantic_context.generation)
        # A file that does not parse gets its syntax errors and nothing
        # else. Prism is error-tolerant, so there is still a tree -- one
        # error recovery invented parts of, and every semantic answer
        # below is computed from it. Typing a `.` at the end of a method
        # made `a.end` a call, and the engine reported that the class has
        # no method named `end`, on the commonest editing action there is.
        #
        # Gated here rather than in each check, so a check added later
        # cannot assert about a node nobody wrote.
        return budget ? findings.first(budget) : findings unless findings.empty?

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

        # A call the file guards with `respond_to?` is one the author has
        # already said may not be there, which is the same shape as the
        # `defined?(@x)` exemption the unassigned-ivar check carries. By
        # name rather than by position: a file defensive about a name is
        # defensive about it, and the typo this check exists for appears
        # in no `respond_to?`.
        guards = names_guarded_by_respond_to(document)
        return [] if guards.nil?

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :method_call
          next if resolved_locations[candidate.location]
          next if guarded_here?(guards, candidate)
          # The call this parser read as a macro, at the range it was
          # written. A recognised `delegate`/`scope`/`enum` leaves the
          # class's surface closed -- correctly, the parser read it -- and
          # that is what exposed the macro's own call here (`024.327`).
          # By range, so `delegate` stays reportable where it is not one.
          next if summary.macro_call_ranges.include?(candidate.location)
          # A name Ruby gives every object that the signature set does
          # not declare on `::Object` (`024.91` shape D). Asked before
          # the receiver because everything inherits from `Object`.
          next if Signatures::Environment.universal_ruby_name?(candidate.name)
          # Deliberately *not* `Types.base_nominal` here, unlike everywhere
          # else that reads a container receiver. A workspace that reopens
          # a core class makes its chain look closed while gems keep adding
          # to it, so admitting container receivers reported
          # `[1,2].second` -- ActiveSupport's, absent from stdlib RBS -- as
          # unknown. That trade is the wrong way round for this check,
          # whose whole policy is that a false report is worse than a
          # missed one. See 024.13.
          receiver_type = receiver_type_for(document, candidate, context)
          # A Union is asked branch by branch rather than discarded.
          # `Relation[T]#first` and `CollectionProxy[T]#first` infer
          # `T | nil`, so `Order.recent.first.missing` was reported by
          # nothing while `Order.find(id).missing` was reported normally
          # -- and `Model.scope.first` is an everyday Rails idiom
          # (`024.77`). Completion already knew the answer at that
          # position; only this check refused to ask.
          branches = reportable_branches(receiver_type)
          next if branches.empty?
          next unless branches.all? { |branch| absent_from?(branch, candidate, context) }

          reported = branches.length == 1 ? branches.first : receiver_type
          Finding.new(
            code: "unknown-method",
            message: "#{reported} has no method named `#{candidate.name}`",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { receiver: reported.to_s, ancestors_closed: true }, generation: context.generation
          )
        end
      end

      # The branches a negative answer would have to hold for. `nil` is
      # dropped: `nil.foo` is a different check and its own product
      # question, and letting it make every nilable receiver unreportable
      # is what closed this path entirely.
      #
      # Empty means "not something to assert about" -- a receiver that is
      # neither a Nominal nor a Union of them, or a Union of nothing but
      # nil.
      def reportable_branches(receiver_type)
        case receiver_type
        when Types::Nominal then [receiver_type]
        when Types::Union
          members = receiver_type.members.reject { |t| t == Types::NIL }
          members.all? { |t| t.is_a?(Types::Nominal) } ? members : []
        else []
        end
      end

      # Absence, for one branch, on the terms the whole check already
      # uses. A Union is *more* uncertain than a Nominal, never less, so
      # every branch must clear the same bar -- one branch that is not
      # closed, or that has the method, ends the report.
      def absent_from?(branch, candidate, context)
        return false unless closed_nominal?(branch, candidate.singleton, context) ||
                            model_closed?(branch, context)
        return false if rbs_resolves?(candidate, branch, context)
        return false if model_resolves?(candidate, branch, context)

        true
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
          # A brace-less trailing hash is *keywords* only if the method
          # declares some. `add("a", "K" => 1)` against `def add(name,
          # hash)` passes two positionals, and counting the hash as
          # keywords reported it as one: 526 such reports over brakeman
          # and its vendored gems, 399 of them in `sexp_processor`'s
          # `pt_testcase.rb` and the rest mostly `warn options`. The
          # miscount predates 0.1.14; what 0.1.14 changed is that a
          # receiverless call in a class body resolves, so it reached this
          # check for the first time.
          declares_keywords = parameters.any? { |parameter| %i[keyword keyword_optional keyrest].include?(parameter.kind) }
          passed = shape[:positional] + (shape[:keywords] && !declares_keywords ? 1 : 0)
          next if passed >= required && passed <= maximum

          Finding.new(
            code: "argument-count",
            message: "`#{candidate.name}` takes " \
                     "#{expected_arity(required, maximum, positional: declares_keywords)}, but #{passed} given",
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

        # `defined?(@x)` tests for existence rather than reading a value,
        # and it is the idiom written specifically to be safe about an
        # ivar that may not be there. By name rather than by location: a
        # file defensive about a name is defensive about it, and the typo
        # this check exists for appears in no `defined?`.
        # A failure here would leave `tested` empty, which reads as "this
        # file is defensive about nothing" and turns every `defined?(@x)`
        # into a report. Enumerating is what decides whether to assert,
        # so a failure to enumerate has to decline (`024.122`).
        tested = ivar_names_tested_for_existence(document)
        return [] if tested.nil?

        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :ivar
          next if local.include?(candidate.name)
          next if tested.include?(candidate.name)
          next if assigned.include?(candidate.name)

          Finding.new(
            code: "unassigned-ivar",
            message: "`#{candidate.name}` is never assigned before this is read",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { ivar: candidate.name }, generation: context.generation
          )
        end
      end

      # Every ivar named inside a `defined?`, in one parse of the document.
      # Nil, not `[]`, when it cannot look: see the caller. `[]` is the
      # answer for a file that tests nothing, and the two must not be the
      # same value.
      def ivar_names_tested_for_existence(document)
        collector = DefinedIvarCollector.new
        Prism.parse(document.text).value.accept(collector)
        collector.names
      rescue StandardError
        nil
      end

      # Every name a *receiverless* `respond_to?` names with a literal
      # symbol or string, in one parse of the document.
      #
      # **Receiverless**, because `other.respond_to?(:x)` is a statement
      # about `other` and says nothing about what `self` answers to.
      # **Literal**, because a computed name is exactly what cannot be
      # read, and a guard this cannot read must not be treated as one.
      #
      # `nil` on any failure, which every caller turns into "do not
      # assert": enumerating is what decides whether to speak, so a
      # failure to enumerate has to decline (`024.122`).
      def names_guarded_by_respond_to(document)
        collector = RespondToGuardCollector.new
        Prism.parse(document.text).value.accept(collector)
        collector.guards
      rescue StandardError
        nil
      end

      # **A guard says something about `self`, on the side of the condition
      # that runs when it is true.**
      #
      # Two versions preceded this. The first collected bare names and the
      # check read them file-wide, which said that a guard in one method
      # covers an unguarded call in another and that a guard on `self`
      # covers `Other.new.maybe_there`. The second scoped a guard to the
      # body it was written in and *documented* that it did not model the
      # branch -- and a follow-up review's verdict was that documenting
      # the gap does not satisfy the condition. It does not: a guard in
      # the false arm exempted the true arm, and Ruby raises there.
      #
      #   $ ruby -e '
      #   class W
      #     def guarded_true;  if respond_to?(:maybe) then maybe else 0 end; end
      #     def guarded_false; if respond_to?(:maybe) then 0 else maybe end; end
      #     def early;         return 1 unless respond_to?(:maybe); maybe; end
      #     def andform;       respond_to?(:maybe) && maybe; end
      #   end
      #   %i[guarded_true guarded_false early andform].each do |m|
      #     begin
      #       W.new.send(m); puts "#{m}: ran"
      #     rescue NameError => e
      #       puts "#{m}: NameError"
      #     end
      #   end'
      #   # => guarded_true: ran
      #   #    guarded_false: NameError
      #   #    early: ran
      #   #    andform: ran
      #   # ruby 3.4.10
      #
      # So the scope is the *consequent*, in four shapes:
      #
      # - `if` (block and modifier alike, which Prism gives as one node):
      #   the statements. Its `subsequent` is not guarded.
      # - `unless`: the `else_clause` -- **and**, when its statements
      #   cannot fall through (`return`, `raise`, `next`, `break`,
      #   `throw`), everything after it in the enclosing body. That is
      #   `return unless respond_to?(:x)`, the commonest spelling in Ruby
      #   and the one a rule that only reads the arms would lose.
      # - `and`: the right operand.
      # - `or` whose right cannot fall through: everything after it.
      #
      # A `respond_to?` that is not a condition at all guards nothing,
      # which is the one case the body-scoped version got backwards.
      #
      # Line ranges rather than node identity, because the check compares
      # against a `ReferenceCandidate`'s location and has no node.
      class RespondToGuardCollector < Prism::Visitor
        Guard = Struct.new(:name, :first_line, :last_line)

        # A statements node that cannot fall through to what follows it.
        # `return` and `raise` are the two this idiom is written with;
        # `next` and `break` are the same claim inside a block.
        LEAVES = [Prism::ReturnNode, Prism::NextNode, Prism::BreakNode].freeze

        attr_reader :guards

        def initialize
          @guards = []
          @bodies = []
          super
        end

        def visit_def_node(node) = within(node) { super }
        def visit_class_node(node) = within(node) { super }
        def visit_module_node(node) = within(node) { super }
        def visit_singleton_class_node(node) = within(node) { super }

        def visit_if_node(node)
          record(node.predicate, node.statements)
          super
        end

        def visit_unless_node(node)
          record(node.predicate, node.else_clause)
          record(node.predicate, rest_of_body_after(node)) if leaves?(node.statements)
          super
        end

        def visit_and_node(node)
          record(node.left, node.right)
          super
        end

        def visit_or_node(node)
          record(node.left, rest_of_body_after(node)) if leaves?(node.right)
          super
        end

        private

        # `nil` and `self` alike, which is what the parser's own
        # `#open_surface_kind` already does. Reading only `nil` left the
        # explicit spelling -- ordinary in application code -- reported.
        def about_self?(node) = node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

        def within(node)
          @bodies.push(node)
          yield
        ensure
          @bodies.pop
        end

        # Every literal name a receiverless `respond_to?` inside
        # `condition` tests. Inside rather than "is": `a && respond_to?(:x)`
        # and `respond_to?(:x) && b` both make the consequent conditional
        # on it.
        def guarded_names(condition)
          return [] unless condition

          names = []
          walk(condition) do |node|
            next unless node.is_a?(Prism::CallNode) && node.name == :respond_to? && about_self?(node)

            Array(node.arguments&.arguments).each do |argument|
              names << argument.unescaped.to_s if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
            end
          end
          names
        end

        def record(condition, consequent)
          return unless consequent

          names = guarded_names(condition)
          return if names.empty?

          names.each do |name|
            @guards << Guard.new(name, consequent.location.start_line, consequent.location.end_line)
          end
        end

        # Whether `node` transfers control rather than falling through, so
        # that reaching the line after it means the condition was true.
        # A `raise` is a call, not a node type, which is why it is named.
        def leaves?(node)
          return false unless node

          statements = node.is_a?(Prism::StatementsNode) ? node.body : [node]
          last = statements.last
          return false unless last
          return true if LEAVES.any? { |kind| last.is_a?(kind) }

          last.is_a?(Prism::CallNode) && last.receiver.nil? && %i[raise throw fail exit abort].include?(last.name)
        end

        # From just after `node` to the end of the body it is written in.
        # A struct with the two line numbers rather than a Prism node,
        # because there is no node for "the rest of this body".
        def rest_of_body_after(node)
          body = @bodies.last
          return nil unless body

          last_line = body.location.end_line
          return nil if node.location.end_line >= last_line

          Range.new(node.location.end_line + 1, last_line).then do |lines|
            Struct.new(:location).new(Struct.new(:start_line, :end_line).new(lines.first, lines.last))
          end
        end

        def walk(root, &block)
          block.call(root)
          root.compact_child_nodes.each { |child| walk(child, &block) }
        end
      end

      class DefinedIvarCollector < Prism::Visitor
        attr_reader :names

        def initialize
          @names = []
          super
        end

        def visit_defined_node(node)
          node.value&.accept(NameOfIvarRead.new(@names))
          super
        end
      end

      class NameOfIvarRead < Prism::Visitor
        def initialize(sink)
          @sink = sink
          super()
        end

        def visit_instance_variable_read_node(node)
          @sink << node.name.to_s
          super
        end
      end

      # The parser records a read and a write as the same `:ivar` candidate
      # kind -- rename and references both want them together -- so the
      # writes are recovered here instead. This is what makes
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
          # A method whose name is not an identifier is an operator, and
          # an operator call's receiver is recorded one character inside
          # itself -- which, when the receiver ends in `)`, is an offset
          # belonging to the receiver's own last argument. `(a - b) > 0`
          # then resolved `>`'s receiver to whatever `b` was. The
          # arguments already decline a composed expression; the receiver
          # gets the same care here, where the two meet.
          next [] unless candidate.name.to_s.match?(IDENTIFIER_METHOD_NAME)

          overload = sole_declared_overload(document, candidate, context)
          next [] unless overload

          mismatched_arguments(document, shape, overload, candidate, context)
        end
      end

      def mismatched_arguments(document, shape, overload, candidate, context)
        locations = shape[:positional_locations] || []
        expected_types = expected_positional_types(overload, locations.size)
        return [] unless expected_types

        locations.each_with_index.filter_map do |range, index|
          expected = expected_types[index]
          next unless expected.is_a?(Types::Nominal)
          # RBS's `int`/`string`/`boolish` are aliases meaning "anything
          # that converts", not classes -- an object of an entirely
          # unrelated class satisfies one, so reporting against it is a
          # false positive by construction. A Ruby constant is
          # capitalised; these are not, which is what tells them apart.
          #
          # The **last segment**, not the first character of the path. An
          # alias can be nested (`String::selector`, `IO::cmd_array`,
          # `FileUtils::mode`, `JSON::options`), and while RBS names were
          # being truncated to their last component the two readings
          # coincided. 0.2.5 stopped truncating, `String::selector` became
          # capitalised, this guard stopped firing, and `"a.b".tr(".", "")`
          # -- ordinary, correct Ruby -- started being reported. 45 nested
          # aliases in rbs 4.0.3 flip the same way.
          #
          # Found by driving a corpus, not by the suite, which had no
          # fixture calling a selector-typed method on a known String.
          next unless expected.name.to_s.split("::").last.to_s.match?(/\A[A-Z]/)
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

          # The argument's *node*, not an offset inside it. See
          # `LocalInferencer#infer_span` for what the end offset
          # answered about a paren-less call argument (`024.20`).
          actual = context.local_inferencer.infer_span(document, range)
          next unless actual.is_a?(Types::Nominal)
          # The same rule as the declared side above, and it was applied
          # only there: `Boolean` is what the converter calls RBS's
          # `bool`, no Ruby class has that name, and its ancestor walk can
          # never succeed -- so every `true`/`false` passed to a
          # plain-class parameter was reported.
          next if NOT_A_RUBY_CLASS.include?(actual.name)
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

      # Which declared type each of `count` arguments lands on, or nil
      # when nothing can be said.
      #
      # It depends on the count because Ruby fills the required
      # parameters first, the trailing ones last, and the optional ones
      # with whatever is left over. `def hold(a, b = 1, c)` called with
      # two arguments binds them to `a` and `c`; called with three, to
      # `a`, `b` and `c`. A fixed `required + optional` list is right only
      # when there are no trailing parameters, and was reading `c`'s type
      # at index 1.
      #
      # The two arity failures are not symmetric, and an earlier version
      # of this treated them as though they were -- returning nil for
      # both, on the stated grounds that arity is the arity check's
      # report to make. That is false for a method declared only in a
      # signature: `argument_count_findings` reads *source* declarations,
      # so for those nobody reports the arity and nobody checks the
      # arguments either.
      #
      # Too few, and the arguments still bind to the required parameters
      # in order, so those are checkable and the trailing ones simply
      # have no argument. Too many, and nothing says which parameter the
      # extra one was meant for.
      def expected_positional_types(overload, count)
        required = overload.required_positionals
        optional_taken = count - required.size - overload.trailing_positionals.size
        return required.first(count) if optional_taken.negative?
        return nil if optional_taken > overload.optional_positionals.size

        required + overload.optional_positionals.first(optional_taken) + overload.trailing_positionals
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
      # The `expected` side is compared bare; the reachable side is not
      # normalised at all. `HierarchyIndex` returns a workspace-resolved
      # entry `::`-prefixed and an external one without -- but the
      # expected type is necessarily RBS-declared, so the signature
      # environment returns a bare name for it whichever way the workspace
      # spelled it. `ancestor_names` below says why normalising there is
      # a transformation no input reaches.
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

      # Every Ruby object has these, whatever the index knows about it.
      # `HierarchyIndex` appends the implicit tail only for a name it has
      # a *class declaration* for, so a class made by `Data.define` or
      # `Struct.new` -- indexed as a constant -- reached nothing but its
      # own name and was reported incompatible with `Object`.
      UNIVERSAL_ANCESTORS = %w[Object Kernel BasicObject].freeze

      def compatible_nominal?(actual, expected, context)
        target = simple_name(expected.name)
        return true if UNIVERSAL_ANCESTORS.include?(target)
        return true if COERCES_TO.fetch(simple_name(actual.name), []).include?(target)

        # `nil` is "the chain has a hole in it", and the answer is to
        # decline. The reachable set is a lower bound even when it is
        # complete, so a miss computed from a chain with an unnameable
        # link in it is not evidence of a mismatch -- the link nobody
        # could name may well *be* the expected type (`024.248`).
        reachable = ancestor_names(actual.name, context)
        return true if reachable.nil?

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
      #
      # `nil` when the chain has a link nobody could identify. This was
      # the sixth reader of the chain and the one with no `#identified?`
      # guard, so `AncestorEntry#name` raised -- deliberately, since
      # there is no way to *spell* the owner of an edge nobody resolved
      # (`024.80`) -- straight out of `#analyze`, and the whole document
      # lost every diagnostic rather than this one comparison declining.
      # `Server#publish_diagnostics` rescues without publishing, so the
      # editor kept whatever it was last shown for that file: a stale
      # answer that looks live, frozen from the keystroke that wrote the
      # call (`024.248`).
      #
      # Skipping the unnameable link instead would answer with a set that
      # is silently short a branch, which is the shape that lets a caller
      # assert a mismatch from a question it could not ask.
      def ancestor_names(name, context)
        # Every workspace ancestor in both spellings. `HierarchyIndex`
        # returns a workspace-resolved entry `::`-qualified and an
        # external one bare, while the `expected` side is always bare --
        # and the signature environment cannot be relied on to supply the
        # bare form, because it is RBS-only: an *RBI*-declared parameter
        # type has no ancestry there at all, so `::Animal` never matched
        # `Animal` and a class was reported incompatible with itself.
        #
        # `simple_name_of`, not `bare_name`: a namespaced `::Zoo::Animal`
        # has to reach `Animal`, which stripping the prefix does not do,
        # and it is the form `TypeConverter` gives the RBS side.
        entries = context.hierarchy_index.ancestors(name)
        return nil unless entries.all?(&:identified?)

        found = entries.map(&:name)
        workspace = ([name] + found + ([name] + found).map { |entry| simple_name_of(entry) }).uniq

        # `Signatures::Environment#ancestors` resolves a *qualified* name:
        # `ancestors("Integer")` is empty while `ancestors("::Integer")` is
        # the real chain.
        #
        # `Environment#ancestors` already maps every name through
        # `TypeConverter.simple_name`, so they arrive bare -- mapping them
        # again here was the mirror of the no-op the comment above
        # confesses to on the workspace side.
        chains = workspace.map { |entry| context.signatures&.ancestors(qualified_owner(entry)) || [] }

        # `UNAVAILABLE` is RBS declaring a type whose ancestry it cannot
        # build, and it is a frozen `[]` -- so adding it to the set is
        # indistinguishable here from a type that really has no ancestors,
        # and the comparison then asserts a mismatch from a question it
        # could not ask. Same answer as the hole above, for the same
        # reason: the reachable set is a lower bound, and the link that
        # could not be built may well *be* the expected type.
        #
        # rbs's own `sig/typename.rbs` includes an interface rbs does not
        # load for itself, so `::RBS::TypeName` is exactly this -- and all
        # six of rbs 4.2.0's `argument-type` reports were the class being
        # reported incompatible with itself (`024.224`).
        return nil if chains.any? { |chain| Signatures::Environment.unavailable?(chain) }

        (workspace + chains.flatten).uniq
      end

      # The last segment, which is what `TypeConverter` gives a signature's
      # own names -- as distinct from `simple_name`, which only strips a
      # leading `::`.
      def simple_name_of(name)
        name.to_s.split("::").last.to_s
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

        signature = declared_signature_for(receiver_type, candidate, context, binding_only: true)
        return nil unless signature
        return nil unless signature.overloads.size == 1
        # **A stdlib library may be answered from and not judged against**
        # (`024.321`). Loading all 61 took the parameters this check can
        # judge from 368 to 1,699, and library signatures lag the runtime:
        # `shellwords.rbs` types `escape` as taking a `String` where the
        # implementation calls `to_s`, so `Shellwords.escape(pathname)` --
        # correct Ruby -- was reported. Core and the project's own `sig/`
        # keep judging; a library only answers.
        return nil unless context.signatures&.declared_outside_stdlib?(signature.symbol_id.owner) == true

        overload = signature.overloads.first
        # A `*rest` parameter makes the positional list a prefix rather
        # than a mapping, so index N is no longer necessarily parameter N.
        return nil if overload.rest_positional
        overload
      end

      # `024.133`. "takes 0 arguments" beside `def kwargs(name:, size: 1,
      # **rest)` reads as nonsense: the method plainly takes several, and
      # the count is of *positional* parameters only.
      #
      # Ruby makes the same count and disambiguates it with a clause --
      # `wrong number of arguments (given 1, expected 0; required
      # keyword: name)` -- so the number was right and the noun was
      # wrong. The word is added only where the method actually declares
      # keywords; adding it everywhere would be a different wrong
      # message.
      # **The noun follows the count, not the upper bound.** It used to ask
      # `maximum == 1`, so a method accepting none or one read as taking
      # "0..1 argument" -- singular over a range. Exactly one is the only
      # count that is singular, and a range is never exactly one.
      def expected_arity(required, maximum, positional: false)
        exactly_one = required == maximum && maximum == 1
        count = required == maximum ? required.to_s : "#{required}..#{maximum}"
        "#{count}#{positional ? ' positional' : ''} argument#{exactly_one ? '' : 's'}"
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
        # A declaration reached through the synthesised `Class`/`Module`/
        # `Object`/`Kernel` tail is not one the workspace stated. The tail
        # is there so class-level calls *resolve*; using it to produce
        # arity reports is the aggressive direction, and it is exactly
        # where a `module_function` or a `define_method` this engine does
        # not model can shadow the method it found. Ruby's own
        # `::JSON.load(source, proc, opts)` was reported against a reopened
        # `Kernel#load` for that reason.
        return nil if candidates.first.origin == :class_object

        declarations = candidates.first.declarations
        return nil unless declarations.size == 1

        declarations.first[1]
      end

      def unresolved_constant_findings(summary, context)
        summary.reference_candidates.filter_map do |candidate|
          next unless candidate.kind == :constant
          next if context.workspace_index.resolve_type_name(candidate.name)
          # A class or module is what `#resolve_type_name` answers about;
          # a plain `A = [1].freeze` is indexed as a `:constant` and could
          # never match it, so every reference to one was reported
          # (`024.330`). Asked beside that route rather than folded into
          # it: every other caller of `#resolve_type_name` wants a *type*,
          # and a constant is not one.
          next if constant_within_reach?(candidate, context)
          next if context.signatures && rbs_known_constant?(candidate.name, context.signatures)

          Finding.new(
            code: "unresolved-constant", message: "cannot resolve constant `#{candidate.name}`",
            range: candidate.location, severity: :warning, confidence: :low,
            evidence: { name: candidate.name }, generation: context.generation
          )
        end
      end

      # Whether a `respond_to?` guard covers *this* call: the same name,
      # a call on `self` (written or implicit -- a call with any other
      # receiver is about a different object), and inside the body the
      # guard was written in.
      def guarded_here?(guards, candidate)
        return false unless candidate.receiver.nil? || written_self?(candidate)

        name = candidate.name.to_s
        line = candidate.location[:start][:line] + 1
        guards.any? { |guard| guard.name == name && line >= guard.first_line && line <= guard.last_line }
      end

      # **Ruby's constant lookup, to the depth this index can follow it.**
      #
      # `WorkspaceIndex#constant_declaration_owners` answers which owners
      # declare a constant of this simple name; deciding from that list
      # alone is what the first version of `024.330` did, and it was wrong
      # in both directions -- a bare `LIMIT` accepted because an unrelated
      # `Foreign::LIMIT` existed, and `Child::LIMIT` reported although
      # `Parent` declares it. Ruby, 3.4.10:
      #
      #     $ ruby -e '
      #     class Parent; LIMIT = 3; end
      #     class Child < Parent; def go = LIMIT; end
      #     class Consumer; def go = LIMIT; end
      #     p [Child.new.go, Child::LIMIT]
      #     begin; Consumer.new.go; rescue NameError => e; puts e.message; end
      #     '
      #     # => [3, 3]
      #     #    uninitialized constant Consumer::LIMIT
      #
      # So the *reach* is computed: for a bare name, every lexical nesting
      # frame and its ancestors, plus the top level; for a qualified one,
      # the written namespace and its ancestors. A name outside that reach
      # is reported, which is the whole point of the check.
      #
      # **An unbuildable chain declines**, the way `#ancestor_names` does:
      # "no ancestor declares it" answered from a chain with an
      # unidentified link is an assertion made from a question that could
      # not be asked (`024.224`'s shape).
      def constant_within_reach?(candidate, context)
        written = candidate.name.to_s
        simple = written.split("::").last.to_s
        owners = context.workspace_index.constant_declaration_owners(simple)
        return false if owners.empty?

        reach = constant_reach(written, candidate, context)
        return true if reach.nil? # the chain could not be built: decline

        owners.any? { |owner| reach.include?(owner) }
      end

      # The owners a name written here can reach, or `nil` where that
      # cannot be determined. `nil` inside the set is the top level, which
      # is how `#visit_constant_write_node` records a constant written
      # outside any class or module body.
      def constant_reach(written, candidate, context)
        namespace = written.sub(/::[^:]*\z/, "")
        # **The namespace is resolved with the nesting too.** `Utils::X`
        # written inside `module Rack` means `Rack::Utils`, and resolving
        # `Utils` workspace-wide picks whichever of hashie's, i18n's and
        # rack's the index happens to rank first -- then `X` is outside
        # that one's reach and is reported. Measured on rack 3.2.7:
        # `Utils::STATUS_WITH_NO_ENTITY_BODY`, `Utils::URI_PARSER` and
        # `Parser::TEMPFILE_FACTORY` were all reported. Found by cold
        # review; `024.15`'s ambiguity, in a new reader.
        return owners_reachable_from([namespace], context, nesting: candidate.lexical_nesting) if namespace != written

        frames = Array(candidate.lexical_nesting)
        reach = owners_reachable_from(frames, context)
        reach&.<<(nil)
        reach
      end

      # Each frame, plus everything on its instance chain. `nil` from any
      # one chain propagates: a single unidentified ancestor makes the
      # whole answer "cannot tell" rather than a shorter list, because a
      # shorter list is indistinguishable from a complete one downstream.
      def owners_reachable_from(names, context, nesting: [])
        reach = Set.new
        names.each do |name|
          canonical = context.workspace_index.resolve_type_symbol(name, nesting: Array(nesting))&.name ||
                      Index::SymbolId.qualify_owner(name)
          reach << canonical
          entries = context.hierarchy_index.ancestors(canonical, singleton: false)
          return nil unless entries.all? { |entry| chain_link_understood?(entry, context) }

          entries.each { |entry| reach << Index::SymbolId.qualify_owner(entry.name_or_nil.to_s) }
        end
        reach
      end

      # **Identified is not the same as understood.** `class Pool < Impl`
      # where `Impl = case ... end` gives an entry *named* `Impl` with
      # nothing behind it -- the chain stops there, and reading it as
      # complete reported `RubyImpl`'s constants as unresolved. Measured
      # on concurrent-ruby, whose `ThreadPoolExecutorImplementation` is
      # exactly this: `Concurrent::CachedThreadPool::DEFAULT_THREAD_IDLETIMEOUT`
      # is `60` in ruby 3.4.10 and was reported. Found by cold review.
      #
      # A name is understood when something can say what is behind it:
      # the workspace declares it as a type, or the signature environment
      # declares it -- which is how `Object`, `Kernel` and `BasicObject`
      # stay understood without the workspace owning them.
      def chain_link_understood?(entry, context)
        return false unless entry.identified?
        return true if context.workspace_index.type_kind(entry.name_or_nil)

        signatures = context.signatures
        return false unless signatures

        signatures.declares?(Index::SymbolId.qualify_owner(entry.name_or_nil)) != false
      rescue StandardError
        # A question that could not be asked is not an answer of "no": the
        # same direction `#rbs_known_constant?` takes beside this.
        true
      end

      # **`true` on failure, not `false`** (`024.122`). This decides
      # whether to *report* an unresolved constant, and `false` means
      # "RBS does not know this name" -- which is an assertion about the
      # user's code made from a question that could not be asked. Failing
      # towards "known" declines instead, which is the direction §0 asks
      # for and the one every other refusal in this file takes.
      #
      # `!= false` is that same rule applied to the third answer
      # `#declares?` carries: a chain that could not be built is a name
      # the signature file *does* declare, and reading it as an absence
      # reported `cannot resolve constant` naming a class the project's
      # own `sig/` declares (`024.247`). The rescue stays because its
      # argument is about a failure of any kind, not about the one
      # failure `#declares?` now distinguishes.
      def rbs_known_constant?(name, signatures)
        signatures.declares?(name) != false
      rescue StandardError
        true
      end

      def unknown_route_helper_findings(summary, resolved_locations, context)
        return [] unless context.route_registry
        # `Server` always constructs a registry, so its presence says
        # nothing; whether a snapshot ever reached it is the question
        # (024.24).
        return [] unless context.route_registry.loaded?

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
      # Every check below names a receiver type in what it reports, so
      # none of them may act on a name the index resolved by picking
      # among same-named classes -- see
      # `WorkspaceIndex#guessed_type_name?`. Refused here, once, rather
      # than at each of the three call sites: this file has twice had a
      # rule stated in several places and wrong in one of them.
      def receiver_type_for(document, candidate, context)
        resolved = Semantic::ReceiverResolution.receiver_type_for(context.workspace_index, document, candidate,
                                                                  context.local_inferencer)
        # A written `self`. Its type comes from the enclosing class body, so
        # it is an upper bound on the receiver rather than its class --
        # every instance reaching the body may be a subclass that supplies
        # the method. `024.85` made this reachable by giving `self` a type
        # for completion and hover, which do not assert; measured over
        # activesupport-8.1.3.1/lib with `unresolved-constant` held at 827,
        # admitting it took `unknown-method` from 21 to 30, all nine new
        # ones `Numeric has no method named `*`` on that gem's own
        # `self * KILOBYTE`. Declining costs nothing that was ever
        # reported: before `self` had a type, this said nothing here either.
        return Types::UNKNOWN if written_self?(candidate)
        return Types::UNKNOWN if resolved.is_a?(Types::Nominal) && context.workspace_index.guessed_type_name?(resolved.name)
        return Types::UNKNOWN if resolved.is_a?(Types::Nominal) && shadowed_declared_type?(resolved.name, context)
        return Types::UNKNOWN if rooted_receiver_answered_elsewhere?(candidate, context)

        resolved
      end

      # Recorded by the parser at the call site rather than re-derived
      # here, because the parser had the node.
      def written_self?(candidate)
        candidate.receiver.is_a?(Hash) && candidate.receiver[:written_self]
      end

      # `::JSON` is rooted, and Ruby gives a rooted name exactly one
      # possible referent: the top-level constant. Nothing downstream can
      # see that, because `ReceiverResolution` strips the `::` on the way
      # in -- so `HierarchyIndex` re-resolved the bare `JSON` and answered
      # with i18n's own `I18n::Backend::KeyValue::JSON`, whose singleton
      # chain is closed, and this check reported `::JSON.parse` missing
      # over ordinary gem source (2 of the 18 findings the 213-file corpus
      # still produced after the open-surface rule).
      #
      # The same shape as `#shadowed_declared_type?` and declined in the
      # same place for the same reason: resolution keeps answering, since
      # moving a rule of this kind into resolution is what 024.47 rolled
      # back. Completion and go-to-definition still offer the plausible
      # class; only the assertion is withheld.
      #
      # Narrow on purpose. A rooted name the workspace does not claim at
      # all (`::String`) is left alone -- RBS answers it, and that answer
      # is right.
      def rooted_receiver_answered_elsewhere?(candidate, context)
        written = candidate.receiver.to_s
        return false unless written.start_with?("::")

        bare = Index::SymbolId.bare_name(written)
        answer = context.workspace_index.resolve_type_name(bare)
        !answer.nil? && Index::SymbolId.bare_name(answer) != bare
      end

      # Whether the index would answer a *bare* name that signatures
      # already declare with a workspace class that merely shares its last
      # segment. `Index::TypeNameResolution` owns the rule, and this is
      # its one application site: resolution deliberately does *not*
      # refuse the substitution (applying it there broke every bare name
      # written from inside its own namespace -- 024.47), so completion,
      # hover and definition keep answering while this engine declines to
      # assert -- a diagnostic about a receiver it has not identified is
      # an assertion, not a missing answer. The residual cost, recorded in
      # 024.47: the test cannot tell a written name from an inferred one,
      # so a `Billing::Range` receiver -- where the workspace's answer is
      # the right one -- has every check here silenced too.
      def shadowed_declared_type?(name, context)
        bare = Index::SymbolId.bare_name(name)
        Index::TypeNameResolution.substitution?(
          bare, context.workspace_index.resolve_type_name(bare), context.signatures
        )
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
        # **`Object`'s surface is the least knowable there is**, so this
        # never reports about one. Everything every gem, every core
        # extension and RubyGems itself adds to `Object` and `Kernel` at
        # run time lands here, and the bundled signatures declare a
        # fraction of it: `024.239` had to hard-code `trap`,
        # `set_trace_func` and `iterator?` because they were reported
        # missing on the user's own class, and `gem` is another.
        #
        # It became reachable when `024.230` gave a top-level bare call
        # the `Object` receiver Ruby gives it. Measured over 997 files of
        # activesupport, activerecord, actionpack and railties, that
        # produced **25 new reports and removed none** — nine `gem`, four
        # top-level `include`, seven JRuby-only names — every one of them
        # false. Section 0 ranks a wrong answer below a missing one, and
        # the enumeration this check needs is the one enumeration Ruby
        # makes impossible.
        #
        # What it costs is a genuine typo in top-level code, which is not
        # reported. `024.129` records the same decline for the other core
        # classes and the same reason.
        return false if OPEN_BY_CONSTRUCTION.include?(Index::SymbolId.bare_name(nominal.name.to_s))

        entries = context.hierarchy_index.ancestors(nominal.name, singleton: singleton)

        # Four of the reasons this method used to keep for itself now live
        # where the enumeration happens, as reasons on
        # `MethodResolver#availability`'s answer: a chain that does not
        # reach BasicObject, a link with no name, a class that declares
        # `method_missing`, and a surface opened by a macro the parser
        # cannot read. Each was added here a review round at a time, after
        # a false report on working code; stated once at the resolver,
        # every reader gets them without having been taught (`037`'s C2,
        # step 2).
        #
        # **All six now live there**, including the two that needed the
        # signature environment -- the resolver is given one as of C2's
        # step 3, so it can say whether an ancestor is accounted for by
        # anything at all. This method is what is left: the Runtime
        # Agent's round trip below, which the resolver has no business
        # making.
        #
        # The polarity is the point. This used to assume closure and
        # subtract the ways of not knowing it had been taught; it now asks
        # a query that assumes nothing and has to be shown a whole
        # surface. A way of not knowing nobody has thought of yet produces
        # silence rather than a report.
        return false unless context.method_resolver
                                   .availability(receiver_type: nominal, name: "",
                                                 context: { singleton: singleton },
                                                 signatures: context.signatures).absent?

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
        # Skipping every synthesised entry -- the Object/Kernel/BasicObject
        # tail HierarchyIndex appends to every class, and the Class/Module
        # tail it appends to every singleton chain. Those are not links the
        # workspace wrote, so they cannot be ones it reopened, and asking
        # would spend a round trip to be told what RBS already says.
        entries.none? do |entry|
          !entry.synthesised? && reopened_elsewhere?(entry.name, context)
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
      #
      # **`== true`, and it is the opposite direction from
      # `#rbs_known_constant?` above.** What the caller does with a `yes`
      # here is conclude the receiver is *not* reopened elsewhere and
      # report every name it cannot find, so the question is not whether
      # the signature set declares this ancestor but whether anything can
      # say what the ancestor *contributes*. A chain that could not be
      # built declares the name and enumerates nothing, and taking that
      # as an accounting is `024.223` re-entering through a different
      # door -- measured on the shape where the receiver's own chain is
      # fine and only a foreign ancestor's is broken, which is the shape
      # this method exists for. The strict comparison keeps the third
      # answer out.
      def locally_accounted_for?(name, context)
        resolved = context.workspace_index.resolve_type_name(name)
        return true if resolved && Index::SymbolId.bare_name(resolved) == Index::SymbolId.bare_name(name)

        # 024.R7. A third way a name is accounted for, and the strongest
        # of the three: the running application loaded it and told us
        # its whole surface. Without this the Agent's own evidence
        # defeats the index that came from the same Agent -- the chain
        # is rooted, the receiver is closed, and then the deferral fires
        # because a gem ancestor is neither workspace code nor declared
        # by RBS. Measured: every report this capability exists for was
        # suppressed here.
        return true if context.hierarchy_index.gem_index.knows?(name)

        # `#declared_outside_stdlib?`, not `#declares?`: `024.321` loaded
        # 61 stdlib libraries so the engine could *answer* about them, and
        # a library signature is not evidence a surface is complete enough
        # to call a name absent. Driven: `include Open3` made `popen2e` a
        # reported typo, because RBS 4.0.3 omits it.
        context.signatures&.declared_outside_stdlib?(name) == true
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
      #
      # `binding_only:` is the difference between two questions that share
      # this walk:
      #
      # - "does *anything* declare this" -- `rbs_resolves?`'s question,
      #   asked immediately before reporting `unknown-method`. Any
      #   declaration answers it, wherever it came from.
      # - "what are *this call's* parameters" -- the argument-type
      #   check's. Ruby method lookup stops at the first ancestor that
      #   defines the method, so a declaration further along the chain
      #   describes a method the call never reaches, and judging against
      #   it reports correct code.
      #
      # The second stops at a *source* declaration. `Registry.initialize(a,
      # b)`, where the workspace writes `class << self; def
      # initialize(first, second)`, was judged against RBS's
      # `Class#initialize: (?Class superclass)` -- the single
      # `argument-type` report Ruby's whole standard library produced, on
      # `ruby_vm/rjit/compiler.rb:54`.
      #
      # That one refusal is enough, and a second was tried and removed:
      # requiring the signature to be `direct` (declared on that class
      # rather than inherited by it) changed no answer any input reaches,
      # because a workspace override is a source declaration and this
      # already stops there, while a subclass that does *not* override
      # wants the parent's signature and gets it one entry later either
      # way.
      #
      # Keying on the tail's `:class_object` origin instead -- which is
      # how the arity check states the first of these -- would not reach
      # it: `Settings.load(config)` against a workspace `def self.load`
      # finds RBS's `Kernel#load`, and `Kernel` arrives on an instance
      # chain with `:default`. What the cases have in common is not where
      # the signature came from but that something nearer already
      # answered.
      def declared_signature_for(receiver_type, candidate, context, binding_only: false)
        # Returns from inside the walk rather than collecting: this stops
        # at the first ancestor that answers and the chain can be long --
        # the shape it replaced (`any?`) short-circuited, and turning it
        # into a value lookup lost that.
        context.hierarchy_index.ancestors(receiver_type.name, singleton: candidate.singleton).each do |entry|
          # An edge nobody resolved has no owner to look a signature up
          # under, and `nil` is the owner a *top-level* `def` is indexed
          # under -- so this used to ask RBS about the top level and take
          # whatever it found. One of three readers `024.80` found the
          # moment an unidentified entry stopped being able to answer
          # `#name` at all; two hand-written guards existed elsewhere and
          # none was here.
          next unless entry.identified?

          kind = entry.declaration_kind(singleton: candidate.singleton)
          # `owner:` is not qualified here: `SymbolId#initialize` does it
          # (0.1.12). This call site needed it before that existed, and
          # keeping it made a line no input could reach.
          symbol_id = Index::SymbolId.new(kind: kind, owner: entry.name, name: candidate.name,
                                          discriminator: nil)
          signature = context.signatures.method_signatures(symbol_id)
          return signature if signature
          return nil if binding_only && !context.workspace_index.declarations(symbol_id).empty?
        end
        nil
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
    end
  end
end
