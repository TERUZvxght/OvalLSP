# frozen_string_literal: true

require_relative "../types"

module Rslsp
  module Signatures
    # One overload of a signature method — RBS's `overload` methods and
    # Sorbet's single `sig` block both collapse to a list of these on the
    # same SignatureMethod. Positional/keyword lists are plain arrays/hashes
    # of Types values (no parameter names): the "Overload selection MVP"
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md) matches by
    # shape, not by name.
    Overload = Data.define(
      :required_positionals, :optional_positionals, :rest_positional,
      :required_keywords, :optional_keywords, :rest_keyword,
      :block_required, :block_type, :return_type
    ) do
      def initialize(required_positionals: [], optional_positionals: [], rest_positional: nil,
                      required_keywords: {}, optional_keywords: {}, rest_keyword: nil,
                      block_required: false, block_type: nil, return_type: Types::UNKNOWN)
        super(required_positionals: required_positionals, optional_positionals: optional_positionals,
              rest_positional: rest_positional, required_keywords: required_keywords,
              optional_keywords: optional_keywords, rest_keyword: rest_keyword,
              block_required: block_required, block_type: block_type, return_type: return_type)
      end
    end

    # A signature-sourced method — the required interface's shape
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md).
    #
    # - symbol_id: Index::SymbolId (kind: :instance_method/:singleton_method)
    #   identifying the same method a source Declaration would.
    # - type_parameters: the method's own generic parameter names (e.g.
    #   ["U"] for `map`), distinct from the receiver's own type argument.
    # - overloads: one or more Overload entries (RBS methods routinely
    #   declare several; a Sorbet `sig` always contributes exactly one).
    # - location: where the signature itself was declared (an LSP range),
    #   or nil for signatures with no meaningful file location (most
    #   bundled stdlib RBS still has one — it's the .rbs file).
    # - source_kind: :rbs or :rbi — which of the two loaders produced this.
    # - generation: the owning Environment#generation this was built under.
    SignatureMethod = Data.define(:symbol_id, :type_parameters, :overloads, :location, :source_kind, :generation)
  end
end
