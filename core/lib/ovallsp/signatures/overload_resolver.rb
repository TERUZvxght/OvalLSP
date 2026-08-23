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

      def resolve(overloads, positional_count:, keyword_names: [], block_given: false, receiver_bindings: {},
                  argument_types: nil)
        matches = overloads.select { |o| matches?(o, positional_count, keyword_names, block_given) }
        exact_match = !matches.empty?
        matches = overloads unless exact_match # no exact shape match -- fall back to every overload's return type
        if exact_match && block_given
          block_matches = matches.select(&:block_type)
          matches = block_matches unless block_matches.empty?
        end
        matches = narrow_by_argument_types(matches, argument_types) if exact_match

        Types.normalize_union(matches.map do |overload|
          bindings = receiver_bindings.reject { |name, _type| overload.type_parameters.include?(name) }
          Types.substitute(overload.return_type, bindings)
        end)
      end

      # `024.128`. Shape alone fits every `Integer#*` overload, because
      # all four take one argument -- so `price * qty` on two Integers
      # answered `Complex | Float | Integer | Rational`, with the
      # argument sitting right there. RBS keys those overloads on the
      # argument's type and this reads that key.
      #
      # **Only on the exact-shape path.** The fall-back to every overload
      # is already an admission that nothing is known about the call, and
      # narrowing an admission is inventing.
      #
      # **And only where every argument's type is known.** A single
      # `Unknown` means the call is not identified, so the whole set
      # stands: picking an overload from information that is not there is
      # exactly the wrong-answer half of section 0.
      #
      # This picks the overload; it never touches the return type. RBS
      # declares `Integer#**(Integer) -> Numeric` deliberately -- the
      # answer depends on the value, `2 ** 3` being an Integer and
      # `2 ** -1` a Rational -- and narrowing must leave that `Numeric`
      # alone.
      def narrow_by_argument_types(matches, argument_types)
        return matches if argument_types.nil? || argument_types.empty?
        return matches if argument_types.any? { |t| t.nil? || t == Types::UNKNOWN }

        narrowed = matches.select { |overload| accepts_arguments?(overload, argument_types) }
        narrowed.empty? ? matches : narrowed
      end

      # Exact type identity, not subtyping. The resolver's own header
      # says it does no subtyping, and a partial one here would answer
      # confidently where it happened to be right and silently wrongly
      # everywhere else.
      def accepts_arguments?(overload, argument_types)
        expected = overload.required_positionals + overload.optional_positionals
        return false if expected.length < argument_types.length && !overload.rest_positional

        argument_types.each_with_index.all? do |actual, index|
          declared = expected[index]
          declared.nil? || declared == actual
        end
      end

      def matches?(overload, positional_count, keyword_names, block_given)
        return false if positional_count.nil? || keyword_names.nil?

        positional_arity_matches?(overload, positional_count) &&
          keyword_arity_matches?(overload, keyword_names) &&
          block_arity_matches?(overload, block_given)
      end

      def positional_arity_matches?(overload, count)
        return true if overload.rest_positional

        # A trailing positional -- `(String, ?Integer, Symbol)` -- is
        # required too, so it raises the floor as well as the ceiling.
        min = overload.required_positionals.size + overload.trailing_positionals.size
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
