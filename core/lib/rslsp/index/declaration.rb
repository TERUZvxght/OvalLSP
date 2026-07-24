# frozen_string_literal: true

module Rslsp
  module Index
    # One physical occurrence of a SymbolId in source. A class reopened in
    # three places yields three Declarations sharing one SymbolId.
    #
    # - location: LSP range ({ start: { line, character }, end: { line, character } })
    # - visibility: :public, :private, :protected, or nil for non-methods
    # - parameters: array of Rslsp::Index::Parameter (empty for non-methods)
    # - origin: where this declaration came from (:source for Prism-parsed code)
    # - body_source (Task 010): the raw source text of a method's body
    #   statements (nil for anything that isn't a method, and for a method
    #   with an empty body) — captured once at parse time so
    #   Semantic::MethodAnalyzer can re-parse and evaluate it later without
    #   needing to re-read/re-parse the whole owning file (which may not
    #   even be open — see WorkspaceIndex's disk-sourced entries). Standalone
    #   and self-contained: re-parsing this slice alone via Prism produces a
    #   valid AST even though it was extracted from inside a `def`.
    Declaration = Data.define(:symbol_id, :location, :visibility, :parameters, :origin, :body_source) do
      def initialize(body_source: nil, **rest)
        super(body_source: body_source, **rest)
      end
    end
  end
end
