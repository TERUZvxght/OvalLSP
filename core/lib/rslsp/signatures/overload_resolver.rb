# frozen_string_literal: true

require_relative "../types"

module Rslsp
  module Signatures
    # Picks which of a SignatureMethod's overloads a call site actually
    # matches — the "Overload selection MVP"
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md): arity
    # (positional/keyword required-optional-rest) and block presence only,
    # no subtyping. When more than one overload's shape fits, every
    # matching overload's return type contributes to a Union rather than
    # picking one arbitrarily — a caller with genuinely ambiguous static
    # information shouldn't be told a falsely-precise single type.
    module OverloadResolver
      module_function

      def resolve(overloads, positional_count:, keyword_names: [], block_given: false)
        matches = overloads.select { |o| matches?(o, positional_count, keyword_names, block_given) }
        matches = overloads if matches.empty? # no exact shape match -- fall back to every overload's return type

        Types.normalize_union(matches.map(&:return_type))
      end

      def matches?(overload, positional_count, keyword_names, block_given)
        positional_arity_matches?(overload, positional_count) &&
          keyword_arity_matches?(overload, keyword_names) &&
          block_arity_matches?(overload, block_given)
      end

      def positional_arity_matches?(overload, count)
        return true if overload.rest_positional

        min = overload.required_positionals.size
        max = min + overload.optional_positionals.size
        count.between?(min, max)
      end

      def keyword_arity_matches?(overload, keyword_names)
        return true if overload.rest_keyword
        return true if overload.required_keywords.empty? && overload.optional_keywords.empty?

        known = overload.required_keywords.keys + overload.optional_keywords.keys
        required_present = overload.required_keywords.keys.all? { |k| keyword_names.include?(k) }
        all_known = keyword_names.all? { |k| known.include?(k) }
        required_present && all_known
      end

      def block_arity_matches?(overload, block_given)
        return true unless overload.block_required

        block_given
      end
    end
  end
end
