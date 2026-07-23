# frozen_string_literal: true

module Rslsp
  module Index
    # Builds a hierarchical `textDocument/documentSymbol` response from a
    # flat FileSummary#declarations list, nesting methods and constants
    # under their owning class/module by matching SymbolId#owner.
    module DocumentSymbolBuilder
      # LSP 3.17 SymbolKind values.
      SYMBOL_KIND = {
        module: 2,
        class: 5,
        constant: 14,
        instance_method: 6,
        singleton_method: 6
      }.freeze

      module_function

      def build(declarations)
        by_owner = Hash.new { |h, k| h[k] = [] }
        declarations.each { |decl| by_owner[decl.symbol_id.owner] << decl }

        build_children(nil, by_owner)
      end

      def build_children(owner_name, by_owner)
        by_owner[owner_name].map do |decl|
          symbol = decl.symbol_id
          namespace = %i[class module].include?(symbol.kind)

          {
            name: symbol.name.split("::").last,
            kind: SYMBOL_KIND.fetch(symbol.kind, 13),
            range: decl.location,
            selectionRange: decl.location,
            children: namespace ? build_children(symbol.name, by_owner) : []
          }
        end
      end
    end
  end
end
