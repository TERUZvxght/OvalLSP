# frozen_string_literal: true

require "rbs"
require_relative "../types"
require_relative "../index/symbol_id"
require_relative "../index/source_location"
require_relative "signature_method"
require_relative "type_converter"
require_relative "rbi_parser"

module Ovallsp
  module Signatures
    # Loads RBS signatures -- Ruby stdlib, a project's `sig/` directory, and
    # (best-effort) Gem RBS reachable from a Bundler environment -- and
    # answers method-signature/ancestor queries against them
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md).
    #
    # Every failure mode in #load degrades rather than raises: a broken
    # project RBS file, a missing rbs_collection, an unreachable Gem --
    # none of them may stop Ruby source parsing/inference elsewhere in the
    # server ("RBS/RBIロード失敗でRuby source解析を停止しない"). Diagnostics
    # collect *what* was skipped so a caller (e.g. explainType evidence) can
    # still explain the gap.
    #
    # Definitions are built lazily per symbol_id and memoized -- stdlib
    # alone is thousands of classes; eagerly building every one of them at
    # #load time would make every project's cold-start pay for types it
    # will never query.
    class Environment
      def initialize
        @mutex = Mutex.new
        @generation = 0
        @diagnostics = []
        @method_cache = {}
        @ancestor_cache = {}
        @member_name_cache = {}
        @type_parameter_cache = {}
        @rbs_environment = nil
        @definition_builder = nil
        @rbi_methods = {}
      end

      def generation
        @mutex.synchronize { @generation }
      end

      def diagnostics
        @mutex.synchronize { @diagnostics.dup }
      end

      # `bundle_context` is anything responding to #each yielding Gem RBS
      # signature directories to additionally load (e.g. a Bundler
      # environment's resolved gem paths under `sig/` or an
      # rbs_collection.yaml's resolved sources) -- deliberately loosely
      # typed so a caller with no Bundler integration yet can pass nil.
      def load(workspace_root:, bundle_context: nil)
        @mutex.synchronize do
          diagnostics = []
          env = load_environment(workspace_root, bundle_context, diagnostics)

          @rbs_environment = env
          @definition_builder = RBS::DefinitionBuilder.new(env: env)
          @rbi_methods = load_rbi_methods(workspace_root, diagnostics)
          @diagnostics = diagnostics
          @method_cache = {}
          @ancestor_cache = {}
          @member_name_cache = {}
          @type_parameter_cache = {}
          @generation += 1
        end
      end

      # A broken project/Gem RBS file makes RBS::EnvironmentLoader#load
      # raise for the *whole* combined load (RBS doesn't isolate failures
      # per-source) -- so on failure this retries with stdlib alone,
      # guaranteeing stdlib method resolution survives a broken project
      # sig/ file rather than silently losing everything
      # ("stdlib methodの戻り値がUnknownで途切れない" must hold even when a
      # project/Gem signature is broken). Only if even the stdlib-only
      # load fails (should not happen in practice) does this fall back to
      # a bare empty environment.
      def load_environment(workspace_root, bundle_context, diagnostics)
        loader = build_loader(workspace_root, bundle_context, diagnostics)
        env = RBS::Environment.new
        loader.load(env: env)
        env.resolve_type_names
      rescue StandardError => e
        diagnostics << { severity: :error, message: "failed to load RBS environment: #{e.message}", location: nil }
        load_stdlib_only(diagnostics)
      end

      def load_stdlib_only(diagnostics)
        env = RBS::Environment.new
        RBS::EnvironmentLoader.new.load(env: env)
        env.resolve_type_names
      rescue StandardError => e
        diagnostics << { severity: :error, message: "failed to load even stdlib-only RBS environment: #{e.message}",
                          location: nil }
        RBS::Environment.new.resolve_type_names
      end

      # Returns a SignatureMethod (one per symbol_id, packing every RBS
      # `overload` into its own Overload) or nil if the owning type isn't
      # known to the loaded environment, or it has no such method.
      def method_signatures(symbol_id)
        @mutex.synchronize { @rbi_methods[symbol_id] || (@method_cache[symbol_id] ||= build_signature_method(symbol_id)) }
      end

      # Ordered ancestor names (most specific first) for a fully-qualified
      # type name (e.g. "::String"), or [] if the type isn't known to the
      # loaded environment.
      def ancestors(type_name)
        @mutex.synchronize { @ancestor_cache[type_name] ||= compute_ancestors(type_name) }
      end

      # Every method name (including inherited ones) starting with
      # `prefix`, for completion against a receiver whose type has no
      # source declaration to complete against (Task 013's "RBS/Gem
      # methods" completion source) — [] if the type isn't known.
      def member_names(type_name, prefix: "", singleton: false)
        @mutex.synchronize do
          key = [type_name, singleton]
          names = (@member_name_cache[key] ||= compute_member_names(type_name, singleton))
          names.select { |name| name.start_with?(prefix) }
        end
      end

      def type_parameters(type_name)
        @mutex.synchronize do
          @type_parameter_cache[type_name] ||= begin
            type = rbs_type_name(type_name)
            definition = type && build_definition(type, singleton: false)
            definition ? definition.type_params.map(&:to_s) : []
          end
        end
      rescue StandardError
        []
      end

      private

      def build_loader(workspace_root, bundle_context, diagnostics)
        loader = RBS::EnvironmentLoader.new
        add_project_sig(loader, workspace_root, diagnostics)
        add_gem_signatures(loader, bundle_context, diagnostics)
        loader
      end

      def load_rbi_methods(workspace_root, diagnostics)
        return {} unless workspace_root

        patterns = [
          File.join(workspace_root, "sorbet", "rbi", "**", "*.rbi"),
          File.join(workspace_root, "sig", "**", "*.rbi")
        ]
        patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.sort.each_with_object({}) do |path, methods|
          uri = "file://#{path}"
          result = RbiParser.parse(File.read(path, encoding: Encoding::UTF_8), uri: uri)
          diagnostics.concat(result.diagnostics)
          result.signature_methods.each do |signature|
            methods[signature.symbol_id] = signature.with(generation: @generation + 1)
          end
        rescue StandardError => e
          diagnostics << { severity: :warning, message: "failed to load RBI at #{path}: #{e.message}", location: nil }
        end
      end

      def add_project_sig(loader, workspace_root, diagnostics)
        return unless workspace_root

        sig_dir = File.join(workspace_root, "sig")
        return unless File.directory?(sig_dir)

        loader.add(path: Pathname(sig_dir))
      rescue StandardError => e
        diagnostics << { severity: :warning, message: "failed to load project sig/: #{e.message}", location: nil }
      end

      # Best-effort only: a Bundler-resolved Gem's own `sig/` directory (the
      # common convention for a gem that ships its own RBS) is added
      # directly; a Gem with no bundled RBS and no rbs_collection entry
      # simply contributes nothing, silently -- "absent rbs_collection" is
      # an explicit acceptance scenario, not an error.
      def add_gem_signatures(loader, bundle_context, diagnostics)
        return unless bundle_context

        bundle_context.each do |gem_sig_dir|
          loader.add(path: Pathname(gem_sig_dir))
        rescue StandardError => e
          diagnostics << { severity: :warning, message: "failed to load Gem RBS at #{gem_sig_dir}: #{e.message}",
                            location: nil }
        end
      rescue StandardError => e
        diagnostics << { severity: :warning, message: "failed to enumerate Gem RBS sources: #{e.message}",
                          location: nil }
      end

      def build_signature_method(symbol_id)
        type_name = rbs_type_name(symbol_id.owner)
        return nil unless type_name

        definition = build_definition(type_name, singleton: symbol_id.kind == :singleton_method)
        return nil unless definition

        method = definition.methods[symbol_id.name.to_sym]
        return nil unless method

        overloads = method.method_types.map { |method_type| convert_method_type(method_type) }
        return nil if overloads.empty?

        SignatureMethod.new(
          symbol_id: symbol_id,
          type_parameters: method.method_types.flat_map { |mt| mt.type_params.map(&:to_s) }.uniq,
          overloads: overloads,
          location: signature_location(method),
          source_kind: :rbs,
          generation: @generation,
          direct: method.defined_in == type_name
        )
      rescue StandardError => e
        @diagnostics << { severity: :warning, message: "failed to build signature for #{symbol_id.owner}##{symbol_id.name}: #{e.message}",
                           location: nil }
        nil
      end

      def build_definition(type_name, singleton:)
        if singleton
          @definition_builder.build_singleton(type_name)
        else
          @definition_builder.build_instance(type_name)
        end
      rescue StandardError
        nil
      end

      def convert_method_type(method_type)
        fn = method_type.type
        # `(?)` -- see TypeConverter.positional_parameter_types. Every list
        # below is absent on an UntypedFunction, so the whole shape has to
        # degrade to "nothing declared about the parameters", not to "no
        # signature at all".
        return untyped_overload(method_type, fn) unless fn.respond_to?(:required_positionals)

        Overload.new(
          required_positionals: fn.required_positionals.map { |p| TypeConverter.convert(p.type) },
          optional_positionals: fn.optional_positionals.map { |p| TypeConverter.convert(p.type) },
          # A parameter written *after* an optional one -- `(String, ?Integer, Symbol)`.
          # Dropped entirely until 0.2.0's type check needed the positional
          # order, which made the omission visible as a wrong report rather
          # than a missing one.
          trailing_positionals: fn.trailing_positionals.map { |p| TypeConverter.convert(p.type) },
          rest_positional: fn.rest_positionals && TypeConverter.convert(fn.rest_positionals.type),
          required_keywords: fn.required_keywords.transform_values { |p| TypeConverter.convert(p.type) },
          optional_keywords: fn.optional_keywords.transform_values { |p| TypeConverter.convert(p.type) },
          rest_keyword: fn.rest_keywords && TypeConverter.convert(fn.rest_keywords.type),
          block_required: !method_type.block.nil? && method_type.block.required,
          block_type: method_type.block && TypeConverter.convert_function(method_type.block.type),
          return_type: TypeConverter.convert(fn.return_type),
          type_parameters: method_type.type_params.map(&:to_s)
        )
      end

      # `(?)` means "takes anything", so the two *rest* slots carry that and
      # the named lists stay empty -- `OverloadResolver` reads the rest
      # slots for truthiness, so this is what makes such a method accept
      # any call rather than only a zero-argument one.
      #
      # The block is literally absent: RBS refuses to parse a block on an
      # untyped method type ("A method type with untyped method parameter
      # cannot have block"), so `method_type.block` is always nil here and
      # an expression reading it would imply a case that cannot arise.
      #
      # The return type and the type parameters are the two things a `(?)`
      # declaration still states, and both are carried through:
      # `def f: (?) -> String` really does return a String, and
      # `[U] (?) -> U` really does declare `U`. A project `sig/` reaches
      # here unnormalised, so both are pinned by fixtures.
      def untyped_overload(method_type, fn)
        Overload.new(
          required_positionals: [], optional_positionals: [], rest_positional: Types::UNKNOWN,
          required_keywords: {}, optional_keywords: {}, rest_keyword: Types::UNKNOWN,
          block_required: false, block_type: nil,
          return_type: TypeConverter.convert(fn.return_type),
          type_parameters: method_type.type_params.map(&:to_s)
        )
      end

      def signature_location(method)
        loc = method.method_types.first&.location
        return nil unless loc&.buffer

        {
          uri: "file://#{loc.buffer.name}",
          range: Index::SourceLocation.to_range(loc, loc.buffer.content.lines)
        }
      rescue StandardError
        nil
      end

      def compute_member_names(type_name_string, singleton)
        type_name = rbs_type_name(type_name_string)
        return [] unless type_name

        definition = build_definition(type_name, singleton: singleton)
        return rbi_member_names(type_name_string, singleton) unless definition

        rbs_names = definition.methods.keys.map(&:to_s)
        rbi_names = rbi_member_names(type_name_string, singleton)
        (rbs_names + rbi_names).uniq.sort
      rescue StandardError
        rbi_member_names(type_name_string, singleton)
      end

      def rbi_member_names(type_name_string, singleton)
        owner = Index::SymbolId.qualify_owner(type_name_string)
        kind = singleton ? :singleton_method : :instance_method
        @rbi_methods.keys.filter_map { |symbol_id| symbol_id.name if symbol_id.owner == owner && symbol_id.kind == kind }
      end

      def compute_ancestors(type_name_string)
        type_name = rbs_type_name(type_name_string)
        return [] unless type_name

        chain = @definition_builder.ancestor_builder.instance_ancestors(type_name)
        chain.ancestors.filter_map { |a| a.respond_to?(:name) ? TypeConverter.simple_name(a.name) : nil }
      rescue StandardError
        []
      end

      def rbs_type_name(owner)
        return nil unless owner

        RBS::TypeName.parse(owner)
      rescue StandardError
        nil
      end
    end
  end
end
