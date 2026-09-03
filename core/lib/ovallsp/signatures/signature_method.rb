# frozen_string_literal: true

require_relative "../types"

module Ovallsp
  module Signatures
    # One overload of a signature method — RBS's `overload` methods and
    # Sorbet's single `sig` block both collapse to a list of these on the
    # same SignatureMethod. Positional/keyword lists are plain arrays/hashes
    # of Types values (no parameter names): the "Overload selection MVP"
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md) matches by
    # shape, not by name.
    Overload = Data.define(
      :required_positionals, :optional_positionals, :trailing_positionals, :rest_positional,
      :required_keywords, :optional_keywords, :rest_keyword,
      :block_required, :block_type, :return_type, :type_parameters, :declared_return
    ) do
      def initialize(required_positionals: [], optional_positionals: [], trailing_positionals: [],
                      rest_positional: nil,
                      required_keywords: {}, optional_keywords: {}, rest_keyword: nil,
                      block_required: false, block_type: nil, return_type: Types::UNKNOWN,
                      type_parameters: [], declared_return: nil)
        super(required_positionals: required_positionals, optional_positionals: optional_positionals,
              trailing_positionals: trailing_positionals,
              rest_positional: rest_positional, required_keywords: required_keywords,
              optional_keywords: optional_keywords, rest_keyword: rest_keyword,
              block_required: block_required, block_type: block_type, return_type: return_type,
              type_parameters: type_parameters, declared_return: declared_return)
      end

      # What the model prints where it has nothing to say. Named rather
      # than spelled twice: the branch below and the reason above have to
      # agree about it.
      UNKNOWN_WORD = Types::UNKNOWN.to_s

      # `024.42`. What a *reader* should see for this overload's return.
      #
      # `TypeConverter` maps `self`, `void`, `untyped`, `top` and
      # `bottom` all to `Types::UNKNOWN`, which is right for the type
      # model — nothing downstream can act on any of them — and wrong for
      # prose: `push(...) -> Unknown` is a worse answer than the word RBS
      # actually wrote, which is `self`.
      #
      # So `declared_return` carries the source's own word and
      # `return_type` stays the model's value: two answers to two
      # different questions, rather than one answer bent to serve both.
      # A producer that records nothing falls back to the type, so no
      # caller has to know which one built this overload.
      # **Only where the conversion lost something, at any depth.**
      # A first version asked whether the *whole* return had become
      # `Unknown`, which missed `Array#each`: RBS declares
      # `::Enumerator[Elem, self]`, the outer type converts to a
      # `Nominal` so the test was false, and inside the brackets `self`
      # had become `Unknown` and `Elem` had been dropped. A reader saw
      # `Enumerator[Unknown]` for a method the source describes exactly.
      #
      # `TypeConverter` maps
      # `self`, `void`, `untyped`, `top` and `bottom` all to
      # `Types::UNKNOWN`, and it is exactly there that the model has
      # nothing to say and the source's own word is the better answer.
      #
      # Everywhere else the converted type is what the rest of the tree
      # renders, and reaching for the declaration would make signature
      # help the one place that says `::String` where every other reader
      # says `String`. The first version of this did that, and three
      # examples caught it.
      def return_label
        rendered = return_type.to_s
        return rendered unless declared_return && rendered.include?(UNKNOWN_WORD)

        # RBS's own words, spelled the way the rest of the tree spells a
        # name. `::Enumerator[Elem, self]` is what the source says and
        # `Enumerator[Elem, self]` is what every other reader here would
        # print, so the root prefix goes and nothing else does.
        declared_return.gsub("::", "")
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
    SignatureMethod = Data.define(
      :symbol_id, :type_parameters, :overloads, :location, :source_kind, :generation, :direct
    ) do
      def initialize(symbol_id:, type_parameters:, overloads:, location:, source_kind:, generation:, direct: true)
        super(symbol_id: symbol_id, type_parameters: type_parameters, overloads: overloads, location: location,
              source_kind: source_kind, generation: generation, direct: direct)
      end
    end
  end
end
