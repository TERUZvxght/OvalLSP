# frozen_string_literal: true

require "prism"
require_relative "../types"
require_relative "../index/symbol_id"
require_relative "../index/source_location"
require_relative "signature_method"

module Ovallsp
  module Signatures
    # A deliberately limited Sorbet `sig {}` DSL parser -- "限定的RBI
    # parser" (docs/design/tasks/012-rbs-rbi-and-external-signatures.md).
    # Recognizes `sig { params(...).returns(...) }` / `sig { void }`
    # immediately followed by a `def`, and a small vocabulary of type
    # expressions (`T.nilable`, `T.any`, `T::Array[...]`, `T::Hash[...]`,
    # plain constants, `T.untyped`). Everything else -- DSL calls this
    # doesn't recognize, abstract/override annotations, mixins expressed as
    # `include`/`extend` of a Sorbet module -- is simply skipped: an
    # unsupported construct is recorded to #diagnostics and never raises
    # ("対応不能なRBIはdiagnosticへ記録し、serverを落とさない").
    class RbiParser
      Result = Struct.new(:signature_methods, :diagnostics)

      def self.parse(source, uri: "file:///unknown.rbi")
        new(source, uri).parse
      end

      def initialize(source, uri)
        @source = source
        @uri = uri
        @lines = source.lines
        @signature_methods = []
        @diagnostics = []
        @owner_stack = []
      end

      def parse
        result = Prism.parse(@source)
        walk_statements(result.value.statements)
      rescue StandardError => e
        @diagnostics << { severity: :error, message: "failed to parse RBI: #{e.message}", location: nil }
      ensure
        return Result.new(@signature_methods, @diagnostics)
      end

      private

      def walk_statements(statements_node)
        return unless statements_node

        body = statements_node.body
        index = 0
        while index < body.size
          node = body[index]
          case node
          when Prism::ClassNode, Prism::ModuleNode
            walk_namespace(node)
          when Prism::CallNode
            if node.name == :sig && node.block.is_a?(Prism::BlockNode) && body[index + 1].is_a?(Prism::DefNode)
              handle_sig(node, body[index + 1])
              index += 1 # the def itself needs no separate handling
            end
          end
          index += 1
        end
      end

      def walk_namespace(node)
        @owner_stack.push(qualify(node.constant_path.full_name))
        walk_statements(node.body)
      ensure
        @owner_stack.pop
      end

      def qualify(local_path)
        return local_path if local_path.start_with?("::")

        @owner_stack.last ? "#{@owner_stack.last}::#{local_path}" : "::#{local_path}"
      end

      def handle_sig(sig_call, def_node)
        overload = parse_sig_body(sig_call.block.body, def_node)
        return unless overload

        singleton = def_node.receiver.is_a?(Prism::SelfNode)
        symbol_id = Index::SymbolId.new(
          kind: singleton ? :singleton_method : :instance_method,
          owner: @owner_stack.last, name: def_node.name.to_s, discriminator: nil
        )

        @signature_methods << SignatureMethod.new(
          symbol_id: symbol_id, type_parameters: [], overloads: [overload],
          location: { uri: @uri, range: Index::SourceLocation.to_range(sig_call.location, @lines) },
          source_kind: :rbi, generation: 0
        )
      rescue StandardError => e
        @diagnostics << { severity: :warning, message: "failed to convert sig for #{def_node&.name}: #{e.message}",
                           location: Index::SourceLocation.to_range(sig_call.location, @lines) }
      end

      # The sig block's body is one call chain: `params(...).returns(...)`,
      # `params(...).void`, `returns(...)`, or bare `void`. `abstract.`/
      # `override.`/`.checked(...)` prefixes and anything else this doesn't
      # recognize fall through to nil (recorded as a skipped signature by
      # the caller, not a crash).
      def parse_sig_body(block_body, def_node)
        return nil unless block_body

        chain = block_body.body.last
        return nil unless chain.is_a?(Prism::CallNode)

        params_call, return_type = split_chain(chain)
        return nil unless params_call || return_type

        Overload.new(
          **parameter_slots(params_call, def_node),
          block_required: false, block_type: nil,
          return_type: return_type || Types::UNKNOWN
        )
      end

      # Walks the `.returns(X)`/`.void` tail off of the chain and finds the
      # `params(...)` call underneath it, if any -- Sorbet always writes
      # `params` first and `returns`/`void` last, but either may be absent.
      def split_chain(chain)
        case chain.name
        when :returns
          [find_params(chain.receiver), convert_type_expr(chain.arguments&.arguments&.first)]
        when :void
          [find_params(chain.receiver), Types::UNKNOWN]
        when :params
          [chain, nil]
        else
          [find_params(chain.receiver), nil]
        end
      end

      def find_params(node)
        return nil unless node.is_a?(Prism::CallNode)

        node.name == :params ? node : find_params(node.receiver)
      end

      def self.empty_slots
        { required_positionals: [], optional_positionals: [], rest_positional: nil,
          required_keywords: {}, optional_keywords: {}, rest_keyword: nil }
      end

      # Sorbet's `params(...)` is a name-to-type map and nothing more:
      # `params(x: Integer)` describes `def f(x)` and `def f(x:)`
      # identically, so it cannot say which slot a parameter occupies.
      # The `def` immediately below the sig can, and `handle_sig` already
      # has that node -- so shape is read from the def and type is looked
      # up by name.
      #
      # The previous rule filed every entry as a required keyword, with a
      # comment that this was only "for arity matching purposes". That was
      # invisible until 0.1.12 taught the signature label to render
      # keywords, at which point `def combine(x, y)` began telling the
      # user to type `x:`. It was also wrong about arity in both
      # directions: a positional call did not match, and a `sig { void }`
      # over a two-argument def claimed the method took nothing.
      #
      # A parameter the sig does not mention still gets its slot, typed
      # Unknown -- the method takes it either way. A `params` entry naming
      # something the def does not declare is a broken RBI and is dropped:
      # inventing an argument the method cannot accept is the one outcome
      # worse than having no type for it.
      def parameter_slots(params_call, def_node)
        declared = declared_param_types(params_call)
        parameters = def_node&.parameters
        return RbiParser.empty_slots unless parameters

        forwarding = parameters.keyword_rest.is_a?(Prism::ForwardingParameterNode)
        {
          required_positionals: (parameters.requireds + parameters.posts).map { |n| type_of(declared, n) },
          optional_positionals: parameters.optionals.map { |n| type_of(declared, n) },
          rest_positional: rest_slot(declared, parameters.rest, forwarding),
          required_keywords: keyword_slot(parameters, Prism::RequiredKeywordParameterNode, declared),
          optional_keywords: keyword_slot(parameters, Prism::OptionalKeywordParameterNode, declared),
          rest_keyword: keyword_rest_slot(declared, parameters.keyword_rest)
        }
      end

      # Not every node in a parameter list answers `#name`. A destructured
      # positional (`def f(a, (b, c))`) is a `MultiTargetNode`, and both
      # `...` and `**nil` put a nameless node in the keyword-rest slot.
      # Asking any of them for a name raised, `handle_sig`'s blanket
      # rescue turned that into a warning, and the whole method's
      # signature was dropped -- so a `.rbi` that parsed before 0.1.12
      # stopped producing one. A slot with no name still exists; it just
      # has no type to look up (0.1.12, round 6).
      def type_of(declared, node)
        return Types::UNKNOWN unless node.respond_to?(:name)

        declared.fetch(node.name, Types::UNKNOWN)
      end

      # `def f(...)` forwards positionals, keywords and a block alike, and
      # Prism records the whole of it as a single keyword-rest node -- so
      # the positional rest slot has to be opened from there too, or a
      # forwarding method rejects arguments it does accept.
      def rest_slot(declared, rest_node, forwarding)
        return Types::UNKNOWN if forwarding
        return nil unless rest_node

        type_of(declared, rest_node)
      end

      # `**nil` is the opposite of `**rest`: it declares that the method
      # takes no keywords at all, so it must leave the slot closed rather
      # than open it to anything.
      #
      # `...` needs no branch of its own: it is nameless, so `type_of`
      # already answers Unknown, which is what an open slot is. A branch
      # for it was written here and removed once a mutation showed nothing
      # could tell the two paths apart -- the behaviour is pinned by the
      # `...` specs either way, and an unreachable line is worse than none.
      def keyword_rest_slot(declared, node)
        return nil if node.nil? || node.is_a?(Prism::NoKeywordsParameterNode)

        type_of(declared, node)
      end

      def keyword_slot(parameters, node_class, declared)
        parameters.keywords.grep(node_class).to_h { |node| [node.name, type_of(declared, node)] }
      end

      # `def f(*)` / `def f(**)` are anonymous: the node has no name, so
      # there is nothing to look a type up by, and `nil` must not become a
      # hash key that a named parameter could collide with.
      def declared_param_types(params_call)
        return {} unless params_call&.arguments

        hash_node = params_call.arguments.arguments.first
        return {} unless hash_node.is_a?(Prism::KeywordHashNode)

        hash_node.elements.filter_map do |assoc|
          next unless assoc.is_a?(Prism::AssocNode) && assoc.key.is_a?(Prism::SymbolNode)

          [assoc.key.unescaped.to_sym, convert_type_expr(assoc.value)]
        end.to_h
      end

      # `Integer`, `T.nilable(X)`, `T.any(X, Y)`, `T::Array[X]`,
      # `T::Hash[K, V]`, `T.untyped` -- the "RBI scope" vocabulary
      # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md). Anything
      # else widens to Unknown rather than guessing.
      def convert_type_expr(node)
        case node
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          convert_constant(node)
        when Prism::CallNode
          convert_call_type(node)
        else
          Types::UNKNOWN
        end
      rescue StandardError
        Types::UNKNOWN
      end

      def convert_constant(node)
        name = node.full_name
        return Types::NIL if name == "NilClass"
        return Types::Nominal.new(name: "Boolean") if name == "T::Boolean"

        Types::Nominal.new(name: name.split("::").last)
      end

      def convert_call_type(node)
        receiver_name = node.receiver.respond_to?(:full_name) ? node.receiver.full_name : nil

        case [receiver_name, node.name]
        in ["T", :nilable]
          Types.normalize_union([convert_type_expr(node.arguments.arguments.first), Types::NIL])
        in ["T", :any]
          Types.normalize_union(node.arguments.arguments.map { |arg| convert_type_expr(arg) })
        in ["T", :untyped]
          Types::UNKNOWN
        in [_, :[]]
          convert_generic_application(receiver_name, node.arguments&.arguments || [])
        else
          Types::UNKNOWN
        end
      end

      def convert_generic_application(receiver_name, args)
        return Types::UNKNOWN if args.empty?

        simple = receiver_name.to_s.split("::").last
        # T::Hash[K, V] keeps only the value type, matching Generic's
        # single-argument model (same simplification TypeConverter makes
        # for RBS's Hash[K, V]).
        Types::Generic.new(name: simple, type_arg: convert_type_expr(args.last))
      end
    end
  end
end
