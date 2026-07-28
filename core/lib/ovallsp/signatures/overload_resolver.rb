# frozen_string_literal: true

require_relative "../types"

module Ovallsp
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

      def resolve(overloads, positional_count:, keyword_names: [], block_given: false, receiver_bindings: {})
        matches = overloads.select { |o| matches?(o, positional_count, keyword_names, block_given) }
        exact_match = !matches.empty?
        matches = overloads unless exact_match # no exact shape match -- fall back to every overload's return type
        if exact_match && block_given
          block_matches = matches.select(&:block_type)
          matches = block_matches unless block_matches.empty?
        end

        Types.normalize_union(matches.map do |overload|
          bindings = receiver_bindings.reject { |name, _type| overload.type_parameters.include?(name) }
          Types.substitute(overload.return_type, bindings)
        end)
      end

      def matches?(overload, positional_count, keyword_names, block_given)
        return false if positional_count.nil? || keyword_names.nil?

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
        return keyword_names.empty? if overload.required_keywords.empty? && overload.optional_keywords.empty?

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
