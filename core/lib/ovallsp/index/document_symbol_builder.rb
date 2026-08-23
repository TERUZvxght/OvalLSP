# frozen_string_literal: true

module Ovallsp
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
            # **`selectionRange` is not `range`.** The protocol types call
            # it "the range that should be selected and revealed when this
            # symbol is being picked, e.g the name of a function"
            # (`docs/CLIENT_BEHAVIOUR.md`). Writing `decl.location` into
            # both meant picking a class in the outline selected its whole
            # body. `name_location` is populated for these symbols and is
            # what `prepareRename` already returns from the same
            # Declaration -- the narrow range was being emitted for one
            # feature and discarded for another (`024.27`).
            #
            # The fallback is `location` rather than nil: the field is not
            # optional, and the whole range is contained by `range`, which
            # is what the types require.
            selectionRange: decl.name_location || decl.location,
            children: namespace ? build_children(symbol.name, by_owner) : []
          }
        end
      end
    end
  end
end
