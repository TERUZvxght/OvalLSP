# frozen_string_literal: true

module Ovallsp
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
    # - lexical_nesting: the real Ruby `Module.nesting` at this reference's
    #   position, innermost first (e.g. `["::Api::Bar", "::Api"]` for a
    #   reference inside `module Api; class Bar; ...; end; end`'s own
    #   body) — used to resolve an *explicit*, unqualified constant
    #   receiver (`Bar.foo`) the same way real Ruby does: by walking
    #   enclosing lexical scopes outward, not by naively re-splitting
    #   `owner`'s dotted string (which can't tell a `module Api; class Bar`
    #   nesting apart from a compact `class Api::Bar`, whose own real
    #   nesting is `["::Api::Bar"]` only — Ruby's compact class-opening
    #   syntax does NOT implicitly add the outer segment to nesting, even
    #   though `owner` looks identical either way). `[]` for a top-level
    #   reference. See Semantic::ReceiverResolution.
    # - arguments: for :method_call only -- what the call site passes, as
    #   `{ positional:, positional_locations:, splat:, keywords:, block: }`.
    #   `positional_locations` is the source range of each positional
    #   argument, in the same order, and has four readers: the
    #   argument-type check, inlay hints, the surplus-argument action and
    #   `Server#diagnostic_maximum`. It was absent from this list while
    #   0.3.0 added the fourth of them. `nil` for every
    #   other kind, and for a call whose shape the parser deliberately
    #   does not model. `splat` being true means the positional count is
    #   a lower bound, not a count, so no arity conclusion may be drawn
    #   from it.
    # - implicit_hash_value: this site is Ruby's shorthand -- `{ name: }`,
    #   `take(name:)` -- where **one token is both the hash key and the
    #   value**. `location` covers that whole token, colon included,
    #   because that is what the reference occupies; there is no
    #   sub-range of it that is only the value. A caller rewriting the
    #   name has to expand rather than substitute (`Rename::Planner`),
    #   and a caller that only highlights can ignore this. `false`
    #   everywhere else, which is every site where `location` is exactly
    #   the identifier.
    # `write` -- true where this occurrence *assigns* the name. Only
    # meaningful for `:local_variable`, and `nil` everywhere else.
    #
    # The parser has always known: `#visit_local_variable_write_node`
    # and its three operator siblings are separate visitors from
    # `#visit_local_variable_read_node`. It threw the distinction away
    # at `#record_local_variable`, so 0.3.0's documentHighlight
    # answered `Text` for every local -- correct as a statement about
    # what *that layer* could tell, and wrong about what was knowable.
    # Added for inlay hints, which need the assignment sites, and read
    # by highlighting for the same reason.
    ReferenceCandidate = Data.define(:kind, :name, :location, :scope_id, :owner, :singleton, :receiver,
                                      :lexical_nesting, :arguments, :implicit_hash_value, :write) do
      def initialize(lexical_nesting: [], arguments: nil, implicit_hash_value: false, write: nil, **rest)
        super(lexical_nesting: lexical_nesting, arguments: arguments,
              implicit_hash_value: implicit_hash_value, write: write, **rest)
      end
    end
  end
end
