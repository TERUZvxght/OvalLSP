# frozen_string_literal: true

require_relative "../types"
require_relative "../index/symbol_id"

module Ovallsp
  module Semantic
    # Resolves an Index::ReferenceCandidate's receiver into the
    # Types::Nominal used to decide method-call resolution -- shared by
    # ReferenceResolver (Task 014) and Diagnostics::Engine (Task 015)
    # since both need exactly the same "what type is this call against"
    # answer, just for different purposes (confirming a reference vs.
    # deciding a receiver is eligible for the unknown-method check).
    # Previously duplicated ad hoc in both places ("Duplicated
    # (deliberately small)..."); pulled into one implementation after
    # the Task 014-018 independent review found the identical
    # namespace-collapsing bug in both copies at once -- exactly the
    # drift risk duplicating semantic resolution logic invites, so
    # fixing the symptom in each copy separately (again) would leave the
    # same structural hazard in place for the next such bug.
    module ReceiverResolution
      module_function

      def receiver_type_for(workspace_index, document, candidate, local_inferencer)
        case candidate.receiver
        when nil
          candidate.owner && Types::Nominal.new(name: canonical_receiver_name(candidate.owner))
        when Hash
          return nil unless document

          local_inferencer.infer_at(document, candidate.receiver.fetch(:position))
        else
          Types::Nominal.new(name: resolve_explicit_receiver_name(workspace_index, candidate))
        end
      end

      # The semantic layer's name for one decision `Index::SymbolId` owns:
      # drop the leading "::" that ParserService's #current_owner prefixes
      # every fully-qualified name with, and **nothing else** -- never an
      # inner namespace segment. Delegates rather than restating, because
      # round 7 of the 0.1.12 review found eleven hand-written copies of
      # this rule across its three directions; this method's old body was
      # one of two byte-identical to what it now calls (`ModelRegistry
      # #lookup_key` was the other).
      #
      # Why not the simple name, which an earlier version used: it threw
      # away exactly what distinguishes two same-named classes in
      # different namespaces (a closed top-level `Bar` from an open
      # `Api::Bar`), so resolution went to whichever
      # WorkspaceIndex#resolve_type_name had indexed first.
      # #resolve_type_symbol_locked does exact-full-name-first matching
      # internally, and passing the full colon-stripped name is what lets
      # that work. ModelRegistry's keys (Rails' own `model.name`) carry no
      # leading "::" either, so #resolve_via_model_registry needs the same.
      #
      # (Until 0.2.14 these were two paragraphs run together with no break,
      # the first describing the body this method no longer has. A reader
      # could not tell which one was about the code underneath.)
      def canonical_receiver_name(name)
        Index::SymbolId.bare_name(name)
      end

      # An explicit constant receiver written unqualified (`Bar.foo`, no
      # leading "::") is textually ambiguous the same way an implicit-self
      # call is -- but there's no single already-fully-qualified name to
      # fall back on here, since ParserService records the receiver
      # exactly as written in source, never lexically qualified. Real
      # Ruby resolves an unqualified constant by walking its *lexical*
      # nesting outward (`Module.nesting`) before ever falling back to
      # the top level -- verified live: a bare `Bar` referenced from
      # inside `module Api; class Bar; ...; end; end`'s own methods
      # resolves to `Api::Bar` itself (via `Api`'s own constant table),
      # never the unrelated top-level `Bar`, even when both exist. Uses
      # `candidate.lexical_nesting` -- ParserService's own captured
      # `Module.nesting` equivalent -- rather than re-deriving it from
      # `candidate.owner`'s dotted string: an earlier version of this fix
      # did that (`owner.split("::")`), which can't tell a
      # `module Api; class Bar` nesting (real nesting: `[Api::Bar, Api]`,
      # two frames) apart from a compact `class Api::Bar` (real nesting:
      # `[Api::Bar]` *only* -- compact syntax does NOT implicitly add the
      # outer segment to nesting), even though `owner` is the identical
      # string ("::Api::Bar") either way -- found live by the Task
      # 014-018 independent review's third pass. Tries
      # "<innermost nesting frame>::Bar", then each enclosing frame in
      # turn, before WorkspaceIndex#resolve_type_name's raw/global
      # "先勝ち" heuristic fallback.
      def resolve_explicit_receiver_name(workspace_index, candidate)
        raw = canonical_receiver_name(candidate.receiver)
        return raw if candidate.receiver.to_s.start_with?("::")

        Array(candidate.lexical_nesting).each do |scope|
          qualified = "#{scope}::#{raw}"
          resolved = workspace_index.resolve_type_name(qualified)
          return canonical_receiver_name(resolved) if resolved && canonical_receiver_name(resolved) == canonical_receiver_name(qualified)
        end
        raw
      end
    end
  end
end
