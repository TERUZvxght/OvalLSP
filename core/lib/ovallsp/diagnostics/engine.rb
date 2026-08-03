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

        context.hierarchy_index.ancestors(receiver_type.name, singleton: candidate.singleton).any? do |entry|
          kind = entry.declaration_kind(singleton: candidate.singleton)
          symbol_id = Index::SymbolId.new(kind: kind, owner: entry.name, name: candidate.name,
                                          discriminator: nil)
          !context.signatures.method_signatures(symbol_id).nil?
        end
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
