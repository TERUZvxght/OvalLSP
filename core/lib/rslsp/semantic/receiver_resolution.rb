# frozen_string_literal: true

require_relative "../types"

module Rslsp
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

      # Drops only the leading "::" ParserService's own #current_owner
      # always prefixes fully-qualified names with -- never any inner
      # namespace segment. Collapsing to the *simple* name (an earlier
      # version of this logic) threw away exactly the information that
      # disambiguates two same-named classes in different namespaces
      # (e.g. a closed top-level `Bar` vs. an open `Api::Bar`),
      # resolving to whichever candidate WorkspaceIndex#resolve_type_name
      # happened to index first. WorkspaceIndex#resolve_type_symbol_locked
      # already does its own exact-full-name-first matching internally,
      # so passing the full (colon-stripped) name through lets that
      # matching actually work; ModelRegistry's own keys (Rails' own
      # `model.name`) never carry a leading "::" either, so this is also
      # what #resolve_via_model_registry needs.
      def canonical_receiver_name(name)
        name.to_s.delete_prefix("::")
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
      # never the unrelated top-level `Bar`, even when both exist.
      # Approximated here (real Module.nesting also depends on
      # compact-vs-nested class-opening syntax, which ParserService's
      # single-owner-per-level @owner_stack doesn't distinguish) by
      # trying "<owner>::Bar", then each of the owner's own enclosing
      # namespaces in turn, before WorkspaceIndex#resolve_type_name's
      # raw/global "先勝ち" heuristic fallback -- found missing by the
      # Task 014-018 independent review's follow-up pass via a live
      # repro of exactly that shape.
      def resolve_explicit_receiver_name(workspace_index, candidate)
        raw = canonical_receiver_name(candidate.receiver)
        return raw if candidate.receiver.to_s.start_with?("::")

        lexical_scope_chain(candidate.owner).each do |scope|
          qualified = "#{scope}::#{raw}"
          resolved = workspace_index.resolve_type_name(qualified)
          return canonical_receiver_name(resolved) if resolved && canonical_receiver_name(resolved) == canonical_receiver_name(qualified)
        end
        raw
      end

      # `owner` ("::Api::Bar") -> ["::Api::Bar", "::Api"], innermost
      # first -- the enclosing-namespace walk #resolve_explicit_receiver_name
      # tries before giving up and using the raw, unqualified name.
      def lexical_scope_chain(owner)
        return [] unless owner

        segments = canonical_receiver_name(owner).split("::")
        (segments.length - 1).downto(0).map { |i| "::#{segments.first(i + 1).join('::')}" }
      end
    end
  end
end
