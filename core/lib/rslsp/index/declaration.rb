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
    Declaration = Data.define(:symbol_id, :location, :visibility, :parameters, :origin)
  end
end
