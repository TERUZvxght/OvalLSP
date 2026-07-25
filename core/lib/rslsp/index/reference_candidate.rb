# frozen_string_literal: true

module Rslsp
  module Index
    # One raw, unresolved reference site extracted by ParserService's
    # Visitor — the "collect call site candidates" half of Task 014's two-
    # phase design (docs/design/tasks/014-reference-index-and-find-references.md
    # "parser/index phaseではcall site候補を収集する。semantic resolution後に
    # 確定SymbolIdを付与する"). Never resolved against the workspace itself;
    # that's Semantic::ReferenceResolver's job, once every file's
    # declarations are known.
    #
    # - kind: :constant, :local_variable, :ivar, :cvar, or :method_call
    # - name: raw name as written (no lexical-scope constant resolution —
    #   same "動的解決はしない" boundary AncestorFact already draws)
    # - location: the reference's own LSP range
    # - scope_id: for :local_variable only — uniquely identifies the
    #   enclosing def/block within this one file, so two same-named locals
    #   in different scopes are never conflated (`nil` for every other
    #   kind, whose identity comes from `owner` instead — see
    #   ReferenceResolver)
    # - owner: the lexically enclosing class/module at this reference's
    #   position (nil at the top level) — used to scope :ivar/:cvar
    #   identity and as the implicit receiver for a receiverless
    #   :method_call
    # - singleton: whether this reference sits in a singleton
    #   (`class << self` / `def self.x`) context
    # - receiver: for :method_call only — nil for an implicit-self call, a
    #   raw constant name String for `Foo.bar`-shaped calls, or a
    #   `{ position: }` Hash (an LSP position, the exact spot
    #   ReferenceResolver should query for the receiver expression's own
    #   type) for anything else. `nil` for every other kind.
    ReferenceCandidate = Data.define(:kind, :name, :location, :scope_id, :owner, :singleton, :receiver)
  end
end
