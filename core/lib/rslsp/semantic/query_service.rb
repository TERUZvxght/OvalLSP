# frozen_string_literal: true

require_relative "../types"
require_relative "../index/symbol_id"
require_relative "method_resolver"

module Rslsp
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
    Member = Data.define(:name, :origin, :conditional, :visibility, :detail)

    ORIGIN_AUTHORITY = { source: 0, model_column: 1, model_association: 1, signature: 2 }.freeze
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
      def type_at(document, position, initial_env: {})
        @local_inferencer.infer_at(document, position, initial_env: initial_env)
      end

      # Every distinct member name starting with `prefix` reachable from
      # `receiver_type`, merged across source declarations, Active Record
      # model facts, and RBS/Gem signatures, ranked by
      # [conditional, origin authority, name].
      def members_of(receiver_type, prefix: "", context: {})
        candidates = {}
        add_source_members(candidates, receiver_type, prefix, context)
        add_model_members(candidates, receiver_type, prefix)
        add_signature_members(candidates, receiver_type, prefix, context)

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
        source_signatures(receiver_type, method_name, context) || rbs_signatures(receiver_type, method_name, context) || []
      end

      # A minimal evidence trail for `type_at`'s result: what the type
      # is, and (best-effort) which subsystem is why. Never more precise
      # than "the first subsystem that produced a non-Unknown answer" —
      # full precedence-aware evidence merging across every contributing
      # source is deferred (docs/design/tasks/012-rbs-rbi-and-external-signatures.md's
      # own "矛盾時は...evidenceへ残す" is explicitly left to a future
      # richer evidence model; this is the MVP "型の根拠を確認できる" slice).
      def explain(document, position, initial_env: {})
        type = type_at(document, position, initial_env: initial_env)
        { type: type, confidence: type == Types::UNKNOWN ? :low : :high }
      end

      private

      def add_source_members(candidates, receiver_type, prefix, context)
        return unless @method_resolver

        @method_resolver.complete(receiver_type: receiver_type, prefix: prefix, context: context).each do |result|
          candidates[result[:name]] ||= Member.new(name: result[:name], origin: :source, conditional: result[:conditional],
                                                     visibility: nil, detail: nil)
        end
      end

      def add_model_members(candidates, receiver_type, prefix)
        return unless @model_registry

        each_nominal(receiver_type) do |nominal|
          next unless @model_registry.known_model?(nominal.name)

          add_model_columns_and_associations(candidates, nominal.name, prefix)
        end
      end

      def add_model_columns_and_associations(candidates, model_name, prefix)
        model = @model_registry.model(model_name)
        return unless model

        model.columns.each do |column|
          next unless column.name.start_with?(prefix)

          candidates[column.name] ||= Member.new(name: column.name, origin: :model_column, conditional: false,
                                                   visibility: :public, detail: column.ruby_type)
        end
        model.associations.each do |assoc|
          next unless assoc.name.start_with?(prefix)

          candidates[assoc.name] ||= Member.new(name: assoc.name, origin: :model_association, conditional: false,
                                                 visibility: :public, detail: assoc.class_name)
        end
      end

      def add_signature_members(candidates, receiver_type, prefix, context)
        return unless @signatures

        singleton = context[:singleton] == true
        each_nominal(receiver_type) do |nominal|
          @signatures.member_names(qualify(nominal.name), prefix: prefix, singleton: singleton).each do |name|
            candidates[name] ||= Member.new(name: name, origin: :signature, conditional: false, visibility: nil, detail: nil)
          end
        end
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

          class_symbol = Index::SymbolId.new(kind: :class, owner: nil, name: qualify(nominal.name), discriminator: nil)
          @workspace_index.declarations_with_uri(class_symbol).first
        end.map { |uri, decl| { uri: uri, range: decl.location } }
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

      def rbs_signatures(receiver_type, method_name, context)
        return nil unless @signatures

        singleton = context[:singleton] == true
        each_nominal(receiver_type).filter_map do |nominal|
          symbol_id = Index::SymbolId.new(
            kind: singleton ? :singleton_method : :instance_method, owner: qualify(nominal.name), name: method_name,
            discriminator: nil
          )
          sm = @signatures.method_signatures(symbol_id)
          next unless sm

          sm.overloads.map { |overload| { label: rbs_signature_label(method_name, overload), parameters: [] } }
        end.flatten.tap { |result| return nil if result.empty? }
      end

      def signature_label(method_name, parameters)
        "#{method_name}(#{parameters.map(&:name).join(', ')})"
      end

      def rbs_signature_label(method_name, overload)
        parts = overload.required_positionals.map(&:to_s) + overload.optional_positionals.map { |t| "?#{t}" }
        "#{method_name}(#{parts.join(', ')}) -> #{overload.return_type}"
      end

      def each_nominal(type)
        return to_enum(:each_nominal, type) unless block_given?

        case type
        when Types::Nominal then yield type
        when Types::Generic then yield Types::Nominal.new(name: type.name)
        when Types::Union then type.members.each { |m| yield m if m.is_a?(Types::Nominal) }
        end
      end

      # Signatures::Environment keys everything by RBS's fully-qualified
      # "::Name" form; the internal type model uses bare simple names
      # (Types::Nominal#name) — this is the one place QueryService bridges
      # the two naming conventions.
      def qualify(name)
        name.start_with?("::") ? name : "::#{name}"
      end
    end
  end
end
