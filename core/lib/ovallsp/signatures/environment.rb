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
      # **A chain that could not be built is not an absent chain.**
      # `AncestorBuilder` raises when a project's own RBS `include`s an
      # interface no loaded signature declares -- `include _ToJson`,
      # declared in `stdlib/json/0/json.rbs`, which `#build_loader` never
      # adds. Swallowing that into `[]` made it identical to the value a
      # type RBS has never heard of produces, and the chain contains the
      # class *itself*, so every method the class declares vanished with
      # it. One line of RBS turned `App::Key#digest` into
      # "App::Key has no method named `digest`" (`024.223`).
      #
      # The value is an ordinary empty Array, so a caller that only adds
      # to a set of reachable names keeps working and keeps reading it as
      # *less* knowledge. A caller that is about to conclude something
      # from the emptiness asks `.unavailable?` and declines instead --
      # the same shape as `Engine#rbs_known_constant?` failing towards
      # "known", and the same trick as asking a returned cref whether a
      # frame was opened rather than re-deriving it.
      UNAVAILABLE = [].freeze

      # Identity, not equality: `[] == UNAVAILABLE` is true and would make
      # every genuinely-unknown type look like a failure.
      def self.unavailable?(value) = value.equal?(UNAVAILABLE)

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
        @definition_cache = {}
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
          @definition_cache = {}
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
      # **`fetch` with a block, not `||=`, because the answer is usually
      # `nil` and `||=` does not remember one.**
      #
      # `#build_signature_method` answers `nil` for every name the type
      # does not declare, and that is precisely what the undefined-method
      # check asks about — it is the question that check exists to
      # answer. So each such ask missed the cache for ever and rebuilt
      # the owner's whole RBS definition. Counted over one `analyze` of
      # Ruby 3.4.10's `net/http.rb`: 76,365 builds for 42 distinct
      # (type, singleton) pairs, 62,644 of them `::HTTP`'s singleton
      # side, every one through here. `024.45`.
      #
      # The header above this class said definitions were "memoized" and
      # meant it; what it did not say is that the memo could only hold an
      # answer that was not `nil`.
      def method_signatures(symbol_id)
        @mutex.synchronize do
          @rbi_methods[symbol_id] ||
            @method_cache.fetch(symbol_id) { @method_cache[symbol_id] = build_signature_method(symbol_id) }
        end
      end

      # Ordered ancestor names (most specific first) for a fully-qualified
      # type name (e.g. "::String"), or [] if the type isn't known to the
      # loaded environment.
      #
      # A third answer is `UNAVAILABLE` -- also empty, so nothing that
      # merely adds names needs to change, but `.unavailable?` tells it
      # apart from the `[]` above. Anything about to conclude "not
      # declared anywhere" from an empty chain must ask (`024.223`).
      def ancestors(type_name)
        @mutex.synchronize { @ancestor_cache[type_name] ||= compute_ancestors(type_name) }
      end

      # Whether the loaded signatures declare `name`. Four callers derived
      # this from `!ancestors(...).empty?`, and each had to remember two
      # things the chain does not tell them: to qualify the name first,
      # and that one of the empty chains is the sentinel above. Two of
      # them forgot the second, so a class the project's own `sig/`
      # declares read as a name signatures have never heard of --
      # `024.246` and `024.247`. Both decisions live here now, so a reader
      # that forgets cannot be the reason a declared name looks absent.
      #
      #   true  -- declared, and the chain was built, so what the type
      #            contributes can be enumerated.
      #   nil   -- declared, and the chain could not be built (`024.223`).
      #            **Not an absence.** Nothing can say what this type
      #            contributes, so the caller has to choose which way it
      #            declines rather than being handed one.
      #   false -- the signature set has never heard of this name.
      #
      # Three answers rather than two because the questions the callers
      # ask have opposite safe directions -- "is this constant known"
      # must fail towards *known*, "is this receiver's surface complete"
      # must fail towards *incomplete* -- so no single boolean is safe
      # for both. What the third value buys over the sentinel is that
      # neither `== true` nor `!= false` can be written by accident,
      # which `[] == UNAVAILABLE` could.
      def declares?(name)
        chain = ancestors(Index::SymbolId.qualify_owner(name))
        return nil if Environment.unavailable?(chain)

        !chain.empty?
      end

      # Every method name (including inherited ones) starting with
      # `prefix`, for completion against a receiver whose type has no
      # source declaration to complete against (Task 013's "RBS/Gem
      # methods" completion source) — [] if the type isn't known.
      def member_names(type_name, prefix: "", singleton: false)
        @mutex.synchronize do
          key = [type_name, singleton]
          names = (@member_name_cache[key] ||= compute_member_names(type_name, singleton))
          # `select` would build a new Array and lose the sentinel's
          # identity, turning "could not look" back into "no members".
          next names if Environment.unavailable?(names)

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

      # Names the interpreter gives *every* object that the signature
      # set does not declare on `::Object` (`024.91` shape D). Each was
      # reported as missing on the user's own class -- a gap in this
      # engine's signature set, stated as an assertion about somebody's
      # code, which is the shape section 0 ranks worst.
      #
      # Taken from Ruby, per the expected-value rule, and from RBS:
      #
      #     $ ruby --disable-gems --disable-did_you_mean -e \
      #         'puts (Object.private_instance_methods + Object.instance_methods).size'
      #     122
      #     ruby=3.4.10 rbs=4.0.3
      #     (bare Ruby's names) - (RBS ::Object's) => ["iterator?", "set_trace_func", "trap"]
      #
      # **Derived with no gem loaded, deliberately.** A first version
      # asked this process's own `Object` and got nineteen names rather
      # than three: `json` puts `to_json` there, `uri` puts `URI`, `pp`
      # puts `pretty_inspect`. Declining on those would be this engine
      # guessing that the user's project loads whatever *it* happens to
      # load. What a gem defines is `024.R7`'s question, answered by
      # indexing the gems rather than inferred from in here -- and
      # replacing a guess with an index is the direction, so a fix for
      # one gap may not smuggle a guess about another one in with it.
      #
      # What is left is only core Ruby: names no gem can supply, no index
      # can discover, and every object has had since the process started.
      # `object_signature_gap_spec.rb` re-derives both sides in a
      # subprocess and fails if a new Ruby or a new RBS moves either,
      # which is what keeps a written list from going stale.
      #
      # **One-directional, which is why it is safe to apply at all.** It
      # can only remove a report, and only for a name Ruby genuinely
      # gives every object -- so it cannot silence a typo, a typo not
      # being such a name. `024.13` proposed declining on a *proxy*
      # instead ("the workspace reopens a foreign class"); measured, that
      # took four real typo reports with it, and was reverted.
      UNIVERSAL_RUBY_NAMES = %w[iterator? set_trace_func trap].freeze

      # Not asked per receiver: everything inherits from `Object`, so a
      # name in the gap is present on whatever branch a report would name.
      def self.universal_ruby_name?(name) = UNIVERSAL_RUBY_NAMES.include?(name)

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

      # **Keyed by the type, not by the symbol.** `#method_signatures`
      # memoises per `symbol_id`, so a *second* name on the same owner
      # missed that cache and rebuilt the owner's entire definition. The
      # undefined-method check asks about many names on one receiver by
      # construction, so that is the common case rather than the corner:
      # 40 absent names on `::String` rebuilt `::String` 40 times.
      #
      # A failed build is remembered too. It is `nil` either way to every
      # caller, and not remembering it is the same defect one layer up —
      # `#method_signatures`' `||=`, which is what `024.45` found first.
      #
      # Reset wherever `@definition_builder` is, because that is the only
      # thing that can change what a definition is.
      def build_definition(type_name, singleton:)
        key = [type_name.to_s, singleton]
        return @definition_cache[key] if @definition_cache.key?(key)

        @definition_cache[key] = build_definition_uncached(type_name, singleton: singleton)
      end

      def build_definition_uncached(type_name, singleton:)
        if singleton
          @definition_builder.build_singleton(type_name)
        else
          @definition_builder.build_instance(type_name)
        end
      rescue StandardError => e
        # **Contained** (`024.122`, extended by `024.223`): `nil` still
        # reads as "no definition", which every caller already treats as
        # cannot-say. What it did not do was leave a trace, so a class
        # whose whole definition failed to build looked exactly like one
        # RBS does not carry.
        record_signature_failure("definition of #{type_name}", e)
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
          # The word RBS wrote, for the label (`024.42`). Taken from the
          # RBS node rather than reconstructed from the converted type,
          # because the conversion is exactly what loses it.
          declared_return: fn.return_type.to_s,
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
        # `#build_definition` already caught the failure and recorded it,
        # so the rescue below never sees one -- this early return is where
        # a failed build actually arrives, and it used to leave by the
        # same door as a type RBS does not carry.
        return unavailable_or(rbi_member_names(type_name_string, singleton), type_name) unless definition

        rbs_names = definition.methods.keys.map(&:to_s)
        rbi_names = rbi_member_names(type_name_string, singleton)
        (rbs_names + rbi_names).uniq.sort
      rescue StandardError => e
        # **Contained** (`024.223`): the RBI half is a genuinely narrower
        # answer and is returned when it has anything to say. When it has
        # nothing, the result would be an `[]` indistinguishable from "this
        # type declares no methods" -- which is the assertion that produced
        # the false report -- so it is marked instead.
        record_signature_failure("members of #{type_name_string}", e)
        unavailable_or(rbi_member_names(type_name_string, singleton), type_name)
      end

      # The RBI half is a genuinely narrower answer, so it wins when it
      # has anything to say. When it has nothing, an `[]` here would be
      # indistinguishable from "this type declares no methods" -- the
      # assertion that produced `024.223`'s false report -- so a type RBS
      # does carry is marked instead.
      def unavailable_or(names, type_name)
        return names unless names.empty? && rbs_declares?(type_name)

        UNAVAILABLE
      end

      # Every caller of this already holds `@mutex` -- `#ancestors`,
      # `#member_names` and `#method_signatures` all compute inside it,
      # and Ruby's Mutex is not reentrant, so taking it here would
      # deadlock rather than protect anything.
      #
      # Deduplicated by message: a workspace with one bad `include` fails
      # once per type that reaches it, and an unbounded list of the same
      # sentence is not more information -- it is what makes a person stop
      # reading the channel that carries the one line they need.
      # Whether RBS carries a declaration for this name at all.
      #
      # `AncestorBuilder` raises the same way for "no such type" as for
      # "declared, but its ancestry cannot be built", so without this the
      # sentinel would mark every unknown type too -- the same conflation
      # `024.223` is about, pointing the other way. `class_decls` holds
      # module entries as well as class ones (probed: `::Kernel` and
      # `::Comparable` are both `true`).
      def rbs_declares?(type_name)
        return false unless @rbs_environment && type_name

        @rbs_environment.class_decls.key?(type_name)
      rescue StandardError
        # **Contained** (`024.223`): `false` means "treat this as an
        # ordinary absence", which is the behaviour that existed before
        # the sentinel. It cannot manufacture an `UNAVAILABLE`, so a
        # failure here can only lose the new distinction, never invent it.
        false
      end

      def record_signature_failure(what, error)
        message = "failed to build #{what}: #{error.message.lines.first.to_s.strip}"
        return if @diagnostics.any? { |d| d[:message] == message }

        @diagnostics << { severity: :warning, message: message, location: nil }
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
      rescue StandardError => e
        # **Contained** (`024.122`, corrected by `024.223`): the value is
        # `UNAVAILABLE`, which reads as an empty chain for every caller
        # that only adds reachable names, and which a caller about to
        # conclude "not declared anywhere" can tell apart from the `[]`
        # an unknown type gives. The earlier verdict here said no
        # consumer could turn the emptiness into an assertion about the
        # user's code; two could, and did.
        return [] unless rbs_declares?(type_name)

        record_signature_failure("ancestors of #{type_name_string}", e)
        UNAVAILABLE
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
