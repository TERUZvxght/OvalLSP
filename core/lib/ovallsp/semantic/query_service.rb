# frozen_string_literal: true

require_relative "../types"
require_relative "../index/symbol_id"
require_relative "method_resolver"

module Ovallsp
  module Semantic
    # One completion/member candidate, already carrying enough for a
    # caller to rank and render it without reaching back into whichever
    # subsystem produced it — the "same expression -> same receiver type"
    # guarantee (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md
    # acceptance: "同一式についてHoverとCompletionが同じreceiver型を利用する")
    # comes from every one of Completion/Hover/Definition/SignatureHelp
    # calling #type_at the same way, then feeding the result into these
    # same #members_of/#definitions_of/#signatures_of methods.
    #
    # - origin: :source (a workspace Declaration), :model_column,
    #   :model_association (Active Record facts), :signature (RBS/RBI) —
    #   "Overload selection MVP"'s authority ranking
    #   (docs/design/tasks/012-rbs-rbi-and-external-signatures.md
    #   Precedence) reduced to what's actually wired at this layer:
    #   project source ranks above Active Record deterministic facts,
    #   which rank above a Gem/stdlib signature.
    # - conditional: true if this candidate isn't present on every member
    #   of a Union receiver.
    # `parameters` is what a completion needs to write a call: the
    # declared parameter names where they are known, `:unknown_arity`
    # where the method takes arguments whose names are not (Rails' own
    # `(*, **, &)` methods), and `[]` where it takes none.
    Member = Data.define(:name, :origin, :conditional, :visibility, :detail, :parameters) do
      def initialize(parameters: [], **rest)
        super(parameters: parameters, **rest)
      end
    end

    ORIGIN_AUTHORITY = {
      source: 0, model_column: 1, model_association: 1, signature: 2, model_api: 3
    }.freeze
    private_constant :ORIGIN_AUTHORITY

    # The shared semantic layer behind Completion/Hover/Definition/
    # Signature Help (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md).
    # Every one of these calls the *same* #type_at for a given
    # document/position, then answers member/definition/signature queries
    # off that one type — the point being that a hover and a completion
    # request for the identical expression can never quietly disagree.
    #
    # Every dependency after `local_inferencer` is optional (nil-safe):
    # a caller with no Rails Runtime Agent connected, or no RBS
    # environment loaded, still gets source-only results rather than an
    # error — matching the same "degrade, never crash" posture every
    # other subsystem in this codebase already follows.
    class QueryService
      def initialize(local_inferencer:, method_resolver: nil, model_registry: nil, signatures: nil, workspace_index: nil)
        @local_inferencer = local_inferencer
        @method_resolver = method_resolver
        @model_registry = model_registry
        @signatures = signatures
        @workspace_index = workspace_index
      end

      # The type of the expression at `document`/`position` — the single
      # source of truth every other QueryService method builds on.
      # `budget` (typically a QueryContext#budget) overrides
      # LocalInferencer's own per-instance step budget for this one call.
      def type_at(document, position, initial_env: {}, budget: nil)
        @local_inferencer.infer_at(document, position, initial_env: initial_env, max_steps: budget)
      end

      # The names in scope at a position, rather than the type of the
      # expression there -- what completion from a bare prefix needs
      # (0.2.0). Passes through for the same reason `type_at` does: the
      # inference budget and the inferencer instance are this service's to
      # own, not every caller's.
      def scope_at(document, position, budget: nil)
        @local_inferencer.scope_at(document, position, max_steps: budget)
      end

      # Every distinct member name starting with `prefix` reachable from
      # `receiver_type`, merged across source declarations, Active Record
      # model facts, and RBS/Gem signatures, ranked by
      # [conditional, origin authority, name].
      def members_of(receiver_type, prefix: "", context: {})
        candidates = {}
        add_source_members(candidates, receiver_type, prefix, context)
        add_model_members(candidates, receiver_type, prefix)
        add_active_record_api_members(candidates, receiver_type, prefix)
        add_signature_members(candidates, receiver_type, prefix, context)
        normalize_union_conditionals(candidates, receiver_type, context)

        candidates.values.sort_by { |m| [m.conditional ? 1 : 0, ORIGIN_AUTHORITY.fetch(m.origin, 9), m.name] }
      end

      # Every location `receiver_type#method_name` could resolve to:
      # source declarations first (in ancestor order), then a signature's
      # own file location (RBS/RBI) if nothing in the workspace declares
      # it, then — for an Active Record association/column with no
      # physical declaration of its own — the owning model class's
      # declaration as a best-effort "go to the generating type"
      # (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md
      # "generated symbol自体に物理位置がない場合は、生成元DSLまたはschemaへ移動する").
      def definitions_of(receiver_type, method_name, context: {})
        source = @method_resolver ? @method_resolver.resolve(receiver_type: receiver_type, name: method_name, context: context) : []
        locations = source.flat_map { |candidate| candidate.declarations.map { |uri, decl| { uri: uri, range: decl.location } } }
        return locations unless locations.empty?

        signature_locations = signature_definition_locations(receiver_type, method_name, context)
        return signature_locations unless signature_locations.empty?

        model_definition_locations(receiver_type, method_name)
      end

      # Overload label/parameter info for `receiver_type#method_name`,
      # from whichever of source declarations or a loaded signature
      # actually has it — "route/通常method/RBSでSignature Helpが統一的に
      #動く": this is the non-route half; Server still merges in route
      # helper signatures itself, since routes have no Types receiver at
      # all.
      def signatures_of(receiver_type, method_name, context: {})
        if receiver_type.is_a?(Types::Union)
          return receiver_type.members.flat_map do |member|
            member == Types::NIL ? [] : signatures_of(member, method_name, context: context)
          end.uniq
        end

        rbs_signatures(receiver_type, method_name, context, direct: true) ||
          source_signatures(receiver_type, method_name, context) ||
          rbs_signatures(receiver_type, method_name, context, direct: false) || []
      end

      # A minimal evidence trail for `type_at`'s result: what the type
      # is, and (best-effort) which subsystem is why. Never more precise
      # than "the first subsystem that produced a non-Unknown answer" —
      # full precedence-aware evidence merging across every contributing
      # source is deferred (docs/design/tasks/012-rbs-rbi-and-external-signatures.md's
      # own "矛盾時は...evidenceへ残す" is explicitly left to a future
      # richer evidence model; this is the MVP "型の根拠を確認できる" slice).
      # Left exactly as it was: no production code calls #explain
      # (`explain_type_result` uses #type_at, `show_type_evidence_result`
      # reads the observation store directly). Routing it through a new
      # two-pass evidence API added a second full inference per query and
      # an `origin:` field for a caller that does not exist -- AGENTS.md
      # is explicit that functionality is not implemented in advance. If
      # #explain is to be wired up, that is the change to make; until
      # then there is nothing here to enrich.
      def explain(document, position, initial_env: {})
        type = type_at(document, position, initial_env: initial_env)
        { type: type, confidence: type == Types::UNKNOWN ? :low : :high }
      end

      private

      # A name can be supplied by different origins on different Union
      # members (for example, a model column on one member and RBS on
      # another). Per-origin occurrence counts incorrectly label that
      # common name conditional, so recompute availability by receiver.
      def normalize_union_conditionals(candidates, receiver_type, context)
        return unless receiver_type.is_a?(Types::Union)

        variants = receiver_type.members
        candidates.transform_values! do |member|
          conditional = variants.any? { |variant| !member_available_on?(variant, member.name, context) }
          member.with(conditional: conditional)
        end
      end

      def member_available_on?(receiver_type, name, context)
        source = @method_resolver&.resolve(receiver_type: receiver_type, name: name, context: context)
        return true unless source.nil? || source.empty?

        nominal = case receiver_type
                  when Types::Nominal then receiver_type
                  when Types::Generic then Types::Nominal.new(name: receiver_type.name)
                  end
        return false unless nominal

        if @model_registry&.known_model?(nominal.name)
          return true if @model_registry.column(nominal.name, name) || @model_registry.association(nominal.name, name)
        end

        singleton = context[:singleton] == true
        @signatures&.member_names(qualify(nominal.name), prefix: name, singleton: singleton)&.include?(name) || false
      end

      def add_source_members(candidates, receiver_type, prefix, context)
        return unless @method_resolver

        @method_resolver.complete(receiver_type: receiver_type, prefix: prefix, context: context).each do |result|
          candidates[result[:name]] ||= Member.new(
            name: result[:name], origin: :source, conditional: result[:conditional],
            visibility: nil, detail: nil,
            parameters: source_parameter_names(receiver_type, result[:name], context)
          )
        end
      end

      # Active Record's own API, as the Runtime Agent read it off the
      # really-loaded classes. A model's ancestors above ApplicationRecord
      # are outside the workspace and have no signatures, so without this
      # completion on a model offered its columns and nothing else -- no
      # `save`, no `destroy`, and on the class no `find`, `where` or
      # `all`. Ranked below columns, associations and source declarations,
      # all of which say something more specific about *this* model.
      #
      # `ClassOf[Model]` takes the class API, a plain `Model` the instance
      # API. That distinction is the whole reason a constant now infers as
      # a class object rather than Unknown.
      def add_active_record_api_members(candidates, receiver_type, prefix)
        return unless @model_registry

        singleton = receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"
        subject = singleton ? receiver_type.type_arg : receiver_type
        return unless each_nominal(subject).any? { |nominal| @model_registry.known_model?(nominal.name) }

        api = @model_registry.active_record_api
        names = singleton ? api[:singleton] : api[:instance]
        # Plus whatever each model adds on top: attribute and dirty
        # methods, association accessors, enum predicates, scopes.
        each_nominal(subject).each do |nominal|
          model = @model_registry.model(nominal.name)
          next unless model

          names += singleton ? model.singleton_methods : model.instance_methods
        end
        takes_arguments = singleton ? api[:singleton_with_arguments] : api[:instance_with_arguments]
        names.uniq.each do |name|
          next unless name.start_with?(prefix)

          candidates[name] ||= Member.new(
            name: name, origin: :model_api, conditional: false, visibility: nil, detail: nil,
            parameters: takes_arguments&.include?(name) ? :unknown_arity : []
          )
        end
      end

      # Declared parameter names for a source method, in call order, so a
      # completion can offer them as tab stops. Only positional and
      # keyword parameters are offered: a block is written after the call,
      # and a splat has no name worth typing.
      def source_parameter_names(receiver_type, method_name, context)
        return [] unless @method_resolver

        found = @method_resolver.resolve(receiver_type: receiver_type, name: method_name, context: context)
        declaration = found.first&.declarations&.first&.last
        return [] unless declaration

        Array(declaration.parameters).filter_map do |parameter|
          parameter.name if %i[required optional keyword keyword_optional].include?(parameter.kind)
        end
      end

      def add_model_members(candidates, receiver_type, prefix)
        return unless @model_registry

        nominals = each_nominal(receiver_type).to_a
        occurrences = Hash.new(0)
        details = {}
        nominals.each do |nominal|
          next unless @model_registry.known_model?(nominal.name)

          model = @model_registry.model(nominal.name)
          next unless model

          model.columns.each do |column|
            next unless column.name.start_with?(prefix)

            occurrences[[:model_column, column.name]] += 1
            details[[:model_column, column.name]] = column.ruby_type
          end
          model.associations.each do |association|
            next unless association.name.start_with?(prefix)

            occurrences[[:model_association, association.name]] += 1
            details[[:model_association, association.name]] = association.class_name
          end
        end

        occurrences.each do |(origin, name), count|
          candidates[name] ||= Member.new(
            name: name, origin: origin, conditional: count < nominals.length, visibility: :public,
            detail: details[[origin, name]]
          )
        end
      end

      def add_signature_members(candidates, receiver_type, prefix, context)
        return unless @signatures

        # `ClassOf[X]` is the class object, and a member of it lives on
        # X's *singleton* chain -- the same normalisation
        # `#add_active_record_api_members` makes and
        # `MethodResolver#normalize_class_receiver` makes. This source made
        # neither, so `each_nominal` yielded a nominal named "ClassOf" and
        # RBS was asked about a class of that name, which does not exist.
        class_object = receiver_type.is_a?(Types::Generic) && receiver_type.name == "ClassOf"
        singleton = class_object || context[:singleton] == true
        subject = class_object ? receiver_type.type_arg : receiver_type
        nominals = each_nominal(subject).to_a
        occurrences = Hash.new(0)
        nominals.each do |nominal|
          # Once per *nominal*, not once per ancestor: the count decides
          # whether a member is conditional on which branch of a Union the
          # receiver took, and a name declared by three ancestors of one
          # nominal is not three receivers agreeing.
          names = signature_owners(nominal, singleton).flat_map do |owner, owner_singleton|
            @signatures.member_names(qualify(owner), prefix: prefix, singleton: owner_singleton)
          end
          names.uniq.each { |name| occurrences[name] += 1 }
        end
        occurrences.each do |name, count|
          candidates[name] ||= Member.new(
            name: name, origin: :signature, conditional: count < nominals.length, visibility: nil, detail: nil
          )
        end
      end

      # Which RBS/RBI owners a receiver's members can come from, paired
      # with the side to ask each for.
      #
      # It was the receiver's own name and nothing else, so a signature
      # inherited from an ancestor was never offered. The visible one is
      # `new`: `Article.` is a class object, `new` is `Class`'s *instance*
      # method, and `EXTENSION_CAPABILITIES.md`'s C5 row names it in the
      # list it promises. Its example asked for `find`, `where` and `all`
      # -- all of which the Runtime Agent supplies -- so the row read PASS
      # with the one member RBS had to answer for missing.
      #
      # The side comes from `AncestorEntry#declaration_kind`, which is
      # where this project keeps that rule: a class object is an
      # *instance* of `Class`, so the tail is asked for instance members
      # even though the walk is a singleton one. `MethodResolver` and
      # `Diagnostics::Engine` were taught this in 0.1.15; completion is
      # the third reader and was not.
      def signature_owners(nominal, singleton)
        return [[nominal.name, singleton]] unless @method_resolver

        owners = @method_resolver.lookup_owners(nominal, singleton: singleton)
        owners.empty? ? [[nominal.name, singleton]] : owners
      end

      def signature_definition_locations(receiver_type, method_name, context)
        return [] unless @signatures

        singleton = context[:singleton] == true
        each_nominal(receiver_type).filter_map do |nominal|
          symbol_id = Index::SymbolId.new(
            kind: singleton ? :singleton_method : :instance_method, owner: qualify(nominal.name), name: method_name,
            discriminator: nil
          )
          sm = @signatures.method_signatures(symbol_id)
          sm&.location
        end
      end

      def model_definition_locations(receiver_type, method_name)
        return [] unless @workspace_index && @model_registry

        each_nominal(receiver_type).filter_map do |nominal|
          next unless @model_registry.known_model?(nominal.name)
          next unless @model_registry.column(nominal.name, method_name) || @model_registry.association(nominal.name, method_name)

          # Ask by qualified name, never by a reconstructed SymbolId:
          # `owner` is recorded lexically, so `module Admin; class
          # Company` and `class Admin::Company` are two different keys for
          # one class and an `owner: nil` guess only ever matches the
          # second (0.1.12, the same move as `Server#find_controller_uri`).
          @workspace_index.class_declarations(nominal.name).first
        end
      end

      def source_signatures(receiver_type, method_name, context)
        return nil unless @method_resolver

        candidates = @method_resolver.resolve(receiver_type: receiver_type, name: method_name, context: context)
        return nil if candidates.empty?

        candidates.map do |candidate|
          decl = candidate.declarations.first&.last
          next unless decl

          { label: signature_label(method_name, decl.parameters), parameters: decl.parameters.map { |p| { label: p.name.to_s } } }
        end.compact
      end

      def rbs_signatures(receiver_type, method_name, context, direct: nil)
        return nil unless @signatures

        singleton = context[:singleton] == true
        each_nominal(receiver_type).filter_map do |nominal|
          symbol_id = Index::SymbolId.new(
            kind: singleton ? :singleton_method : :instance_method, owner: qualify(nominal.name), name: method_name,
            discriminator: nil
          )
          sm = @signatures.method_signatures(symbol_id)
          next unless sm
          next unless direct.nil? || sm.direct == direct

          sm.overloads.map { |overload| { label: rbs_signature_label(method_name, overload), parameters: [] } }
        end.flatten.tap { |result| return nil if result.empty? }
      end

      def signature_label(method_name, parameters)
        "#{method_name}(#{parameters.map(&:name).join(', ')})"
      end

      # The label is what signature help shows while the user is typing
      # arguments into the call, so anything it leaves out reads as "this
      # takes nothing more".
      #
      # Positionals were all it rendered. That made `(?)` -- RBS for
      # "takes anything", which `Proc#call` and `Method#call` are declared
      # as -- come out as `call()`, and made every signature with no
      # *named* positionals but some keyword come out the same way (29
      # methods in the RBS core this loads, 33 counting each overload,
      # `Array#shuffle` among them; three of them -- `Dir.[]`,
      # `Kernel#warn`, `Ractor.new` -- also take a `*rest` *positional*,
      # which is the whole difference between this count and the 26 an
      # earlier revision gave. `Exception#detailed_message` has a `**`
      # rest and is not one of the three; a reviewer read "`*rest`" as
      # "any rest slot" and made it four, so it is spelled out here).
      # Before 0.1.12 the `(?)` ones failed to build at all so
      # nothing was shown; making them build has to not make them lie, and
      # the keyword case was already lying.
      def rbs_signature_label(method_name, overload)
        parts = overload.required_positionals.map(&:to_s) +
                overload.optional_positionals.map { |t| "?#{t}" } +
                overload.trailing_positionals.map(&:to_s)
        parts.concat(overload.required_keywords.keys.map { |name| "#{name}:" })
        parts.concat(overload.optional_keywords.keys.map { |name| "?#{name}:" })
        # One marker for either rest slot: the label says the call accepts
        # more than it names, and which slot that came from is not
        # something a reader of the label can act on.
        parts << "..." if overload.rest_positional || overload.rest_keyword
        "#{method_name}(#{parts.join(', ')}) -> #{overload.return_type}"
      end

      def each_nominal(type)
        return to_enum(:each_nominal, type) unless block_given?

        case type
        when Types::Nominal then yield type
        when Types::Generic then yield Types::Nominal.new(name: type.name)
        when Types::Union then type.members.each { |member| each_nominal(member) { |nominal| yield nominal } }
        end
      end

      # Signatures::Environment keys everything by RBS's fully-qualified
      # "::Name" form; the internal type model uses bare simple names
      # (Types::Nominal#name). Delegates rather than restating the rule:
      # writing it per call site is what 0.1.11 was spent undoing.
      def qualify(name)
        Index::SymbolId.qualify_owner(name)
      end
    end
  end
end
