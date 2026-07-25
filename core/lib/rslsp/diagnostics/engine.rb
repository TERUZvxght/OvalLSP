# frozen_string_literal: true

require_relative "finding"
require_relative "semantic_context"
require_relative "../parser_service"
require_relative "../semantic/reference_resolver"
require_relative "../types"
require_relative "../index/symbol_id"

module Rslsp
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

        budget ? findings.first(budget) : findings
      end

      private

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

          receiver_type = receiver_type_for(document, candidate, context)
          next unless receiver_type.is_a?(Types::Nominal)
          next unless closed_nominal?(receiver_type, candidate.singleton, context)
          next if rbs_resolves?(candidate, receiver_type, context)

          Finding.new(
            code: "unknown-method",
            message: "#{receiver_type} has no method named `#{candidate.name}`",
            range: candidate.location, severity: :warning, confidence: :high,
            evidence: { receiver: receiver_type.to_s, ancestors_closed: true }, generation: context.generation
          )
        end
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
        !signatures.ancestors("::#{name}").empty?
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

      # Duplicated (deliberately small) from Semantic::ReferenceResolver's
      # own private #receiver_type_for rather than exposing it: Engine
      # only needs the receiver's *type*, not a full resolved Reference,
      # to decide whether an unresolved candidate is even eligible for
      # the closed-receiver check below.
      #
      # Must stay in sync with ReferenceResolver#canonical_receiver_name:
      # strip only the leading "::", never an inner namespace segment --
      # collapsing to the simple name here caused exactly the false
      # positive the Task 014-018 independent review reproduced live (a
      # closed top-level `Bar` plus an open `Api::Bar`; querying inside
      # `Api::Bar` incorrectly resolved the receiver to the *wrong*,
      # unrelated top-level `Bar`, flagging a legitimately-unresolvable
      # external-gem method as "unknown method").
      def receiver_type_for(document, candidate, context)
        case candidate.receiver
        when nil
          candidate.owner && Types::Nominal.new(name: candidate.owner.to_s.delete_prefix("::"))
        when Hash
          context.local_inferencer.infer_at(document, candidate.receiver.fetch(:position))
        else
          Types::Nominal.new(name: candidate.receiver.to_s.delete_prefix("::"))
        end
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
      def closed_nominal?(nominal, singleton, context)
        entries = context.hierarchy_index.ancestors(nominal.name, singleton: singleton)
        return false if entries.empty?

        entries.all? { |entry| ancestor_known?(entry, context) } &&
          entries.none? { |entry| declares_method_missing?(entry.name, context) }
      end

      # A builtin ancestor (Object/Kernel/BasicObject, or any RBS-known
      # module/class in the chain) contributes real methods
      # (`puts`/`freeze`/`class`/...) that WorkspaceIndex/MethodResolver
      # have no idea about, since they were never Prism-parsed from any
      # workspace source file -- without this, *every* implicit-self
      # call to a Kernel method would misfire as "unknown method". Tried
      # across the whole ancestor chain, not just the receiver's own
      # name, the same reason #closed_nominal? checks every ancestor.
      def rbs_resolves?(candidate, receiver_type, context)
        return false unless context.signatures

        context.hierarchy_index.ancestors(receiver_type.name, singleton: candidate.singleton).any? do |entry|
          kind = candidate.singleton && entry.origin != :extend ? :singleton_method : :instance_method
          symbol_id = Index::SymbolId.new(kind: kind, owner: "::#{entry.name}", name: candidate.name, discriminator: nil)
          !context.signatures.method_signatures(symbol_id).nil?
        end
      end

      def ancestor_known?(entry, context)
        return true if entry.kind

        context.signatures && !context.signatures.ancestors("::#{entry.name}").empty?
      end

      def declares_method_missing?(owner, context)
        context.workspace_index.method_symbol_ids(owner, kind: :instance_method).any? { |sid| sid.name == "method_missing" }
      end
    end
  end
end
