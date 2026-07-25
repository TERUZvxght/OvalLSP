# frozen_string_literal: true

module Ovallsp
  module Index
    # One resolved reference — a ReferenceCandidate that's been matched
    # against a confirmed SymbolId (docs/design/tasks/014-reference-index-and-find-references.md
    # required interface).
    #
    # - symbol_id: what this reference points at. For :local_variable/
    #   :ivar/:cvar this is synthesized directly from lexical structure
    #   (never ambiguous); for :constant/:method_call it's the result of
    #   resolving against WorkspaceIndex/Semantic::MethodResolver.
    # - kind: same vocabulary as ReferenceCandidate#kind, carried through
    #   unchanged.
    # - confidence: :high (unambiguous resolution) or :low (resolved to
    #   *something*, but only tentatively — e.g. a Union receiver where
    #   this method isn't present on every member). An unresolvable
    #   candidate (no matching declaration/route/AR fact at all) simply
    #   produces no Reference rather than a :low-confidence one with
    #   nothing to point at — "ambiguous callを確定参照として扱わない"
    #   is enforced by ReferenceIndex#references' `minimum_confidence:`
    #   filter, not by omission at resolve time.
    # - origin: :source, :route_helper, or :active_record — where the
    #   resolved target itself lives, mirroring Semantic::MethodCandidate#origin's
    #   role for definitions.
    # - receiver_type: the receiver's own resolved type for a
    #   :method_call reference (nil otherwise) — kept for explain/hover-
    #   style evidence, not needed for lookup.
    # - generation: the owning ReferenceIndex#generation this was built
    #   under.
    # - uri: which file this reference occurs in -- not part of the
    #   task's originally-specified fields, added the same intentional,
    #   documented way WorkspaceIndex#declarations_with_uri pairs a
    #   Declaration with its uri (Task 002's required interface didn't
    #   carry one either): a caller building an LSP Location from a Find
    #   References result needs to know *which file*, not just *where in
    #   it*.
    Reference = Data.define(:symbol_id, :location, :kind, :confidence, :origin, :receiver_type, :generation, :uri)
  end
end
