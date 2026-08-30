# frozen_string_literal: true

require_relative "../index/reference"
require_relative "../index/symbol_id"
require_relative "../types"
require_relative "receiver_resolution"

module Ovallsp
  module Semantic
    # Turns one file's Index::ReferenceCandidate list into confirmed
    # Index::Reference values -- the "semantic resolution" half of Task
    # 014's two-phase design
    # (docs/design/tasks/014-reference-index-and-find-references.md).
    #
    # - :local_variable/:ivar/:cvar candidates resolve purely from lexical
    #   structure already captured on the candidate itself (scope id /
    #   owner) -- never ambiguous, no workspace lookup needed.
    # - :constant candidates resolve against WorkspaceIndex, scoped to
    #   class/module declarations only (the same "動的/複雑な定数解決は
    #   対象外" boundary Task 009's ancestor resolution already draws) --
    #   a plain `VALUE = 5`-style constant's *references* aren't resolved
    #   by this MVP (its declaration is still indexed, just not linked to
    #   from a usage site).
    # - :method_call candidates need a receiver type: an implicit-self or
    #   literal-constant receiver resolves without re-parsing anything;
    #   an arbitrary expression receiver (`user.name`) requires querying
    #   LocalInferencer at the position ParserService recorded for it,
    #   the same "receiver type at the position just before the call"
    #   technique Task 013's Server#receiver_type_before_dot uses.
    class ReferenceResolver
      def initialize(workspace_index:, method_resolver:, local_inferencer:, model_registry: nil, route_registry: nil)
        @workspace_index = workspace_index
        @method_resolver = method_resolver
        @local_inferencer = local_inferencer
        @model_registry = model_registry
        @route_registry = route_registry
      end

      # `document` is only consulted for :method_call candidates whose
      # receiver needs live type inference; every other candidate kind
      # ignores it entirely (may be nil for callers that already know
      # their file has none of those, though every real caller has one).
      def resolve(document, candidates, uri:, generation:)
        candidates.filter_map { |candidate| resolve_candidate(document, candidate, uri, generation) }
      end

      private

      def resolve_candidate(document, candidate, uri, generation)
        case candidate.kind
        when :local_variable then resolve_local(candidate, uri, generation)
        when :ivar, :cvar then resolve_ivar_or_cvar(candidate, uri, generation)
        when :constant then resolve_constant(candidate, uri, generation)
        when :method_call then resolve_method_call(document, candidate, uri, generation)
        end
      end

      # **A local variable never spans files, and the identity has to say
      # so.** Scope ids are counted per file, so `"#{owner}##{scope_id}"`
      # alone puts two files' locals under one id whenever their counters
      # and their cref owner agree -- which for a top-level `def` (owner
      # nil) is the first method of any two such files, and for a class
      # reopened across files is ordinary Rails.
      #
      # Renaming one then produced a WorkspaceEdit against a file the
      # user never opened. That is a worse failure than a rename that
      # leaves one file wrong, and it is why the `uri` -- already a
      # parameter here for the location -- is part of the identity now.
      # `024.278`.
      #
      # A method rename must still cross files and does: it is only this
      # kind whose scope is one file by construction, and only this
      # branch that is qualified.
      def resolve_local(candidate, uri, generation)
        symbol_id = Index::SymbolId.new(
          kind: :local_variable, owner: "#{uri}\u0000#{candidate.owner}##{candidate.scope_id}",
          name: candidate.name, discriminator: nil
        )
        build_reference(candidate, symbol_id, :high, :source, nil, uri, generation)
      end

      def resolve_ivar_or_cvar(candidate, uri, generation)
        symbol_id = Index::SymbolId.new(kind: candidate.kind, owner: candidate.owner, name: candidate.name,
                                         discriminator: nil)
        build_reference(candidate, symbol_id, :high, :source, nil, uri, generation)
      end

      # **The declaration's own SymbolId, not one rebuilt from a name and
      # a kind.** Rebuilding had to supply an `owner` that neither
      # `#resolve_type_name` nor `#type_kind` carries, and the `nil` it
      # supplied is right only for the compact spelling: `module Api;
      # class Widget` is declared under `::Api`, so the rebuilt id
      # matched no declaration at all. `Rename::Planner` found none, and
      # prepareRename -- which sees declarations and nothing else until
      # something has rebuilt the reference index -- refused the class
      # while offering `class Api2::Widget2` at the identical caret
      # (`024.244`).
      #
      # `lexical_nesting` is passed because a bare name written inside a
      # namespace means *that* namespace's class. `ReferenceCandidate`
      # has carried it since 0.2.10 and the receiver path already walks
      # it; this path did not, so a caret on one of two same-named
      # classes in different namespaces answered about the other one, and
      # renaming it rewrote both `class` lines. Handing back the declared
      # identity without this would have made that answer confident
      # rather than merely reachable.
      def resolve_constant(candidate, uri, generation)
        symbol_id = @workspace_index.resolve_type_symbol(candidate.name, nesting: candidate.lexical_nesting)
        return nil unless symbol_id

        build_reference(candidate, symbol_id, :high, :source, nil, uri, generation)
      end

      def resolve_method_call(document, candidate, uri, generation)
        receiver_type = receiver_type_for(document, candidate)

        resolved = receiver_type && (resolve_via_method_resolver(candidate, receiver_type, uri, generation) ||
                                      resolve_via_model_registry(candidate, receiver_type, uri, generation))
        return resolved if resolved

        # Tried whenever receiver-based resolution found nothing -- not
        # just when there was no receiver type at all -- since the
        # overwhelmingly common shape for a route helper call
        # (`user_path(@user)`) is a bare call written *inside* some
        # class body, where #receiver_type_for already resolves a
        # (fruitless) Nominal for that enclosing class.
        resolve_route_helper(candidate, uri, generation)
      end

      def receiver_type_for(document, candidate)
        ReceiverResolution.receiver_type_for(@workspace_index, document, candidate, @local_inferencer)
      end

      def resolve_via_method_resolver(candidate, receiver_type, uri, generation)
        context = { singleton: candidate.singleton, implicit_self: candidate.receiver.nil? }
        matches = @method_resolver.resolve(receiver_type: receiver_type, name: candidate.name, context: context)
        return nil if matches.empty?

        best = matches.min_by(&:lookup_rank)
        confidence = matches.any?(&:conditional) ? :low : :high
        build_reference(candidate, best.symbol_id, confidence, :source, receiver_type, uri, generation)
      end

      def resolve_via_model_registry(candidate, receiver_type, uri, generation)
        return nil unless @model_registry && receiver_type.is_a?(Types::Nominal)

        model_name = receiver_type.name
        return nil unless @model_registry.known_model?(model_name)

        member_kind =
          if @model_registry.column(model_name, candidate.name) then :active_record_column
          elsif @model_registry.association(model_name, candidate.name) then :active_record_association
          end
        return nil unless member_kind

        symbol_id = Index::SymbolId.new(kind: member_kind, owner: model_name, name: candidate.name, discriminator: nil)
        build_reference(candidate, symbol_id, :high, :active_record, receiver_type, uri, generation)
      end

      # A route helper call has no receiver at all (`post_path(id)`, not
      # `SomeReceiver.post_path`) -- only tried once every receiver-based
      # path has already found nothing, since a bare method name always
      # tries lexical/self resolution first.
      def resolve_route_helper(candidate, uri, generation)
        return nil unless @route_registry && candidate.receiver.nil?

        helper = @route_registry.find_by_method_name(candidate.name)
        return nil unless helper

        symbol_id = Index::SymbolId.new(kind: :route_helper, owner: nil, name: helper.name, discriminator: nil)
        build_reference(candidate, symbol_id, :high, :route_helper, nil, uri, generation)
      end

      def build_reference(candidate, symbol_id, confidence, origin, receiver_type, uri, generation)
        Index::Reference.new(
          symbol_id: symbol_id, location: candidate.location, kind: candidate.kind, confidence: confidence,
          origin: origin, receiver_type: receiver_type, uri: uri, generation: generation,
          implicit_hash_value: candidate.implicit_hash_value
        )
      end
    end
  end
end
