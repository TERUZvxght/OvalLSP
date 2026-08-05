# frozen_string_literal: true

require "prism"
require_relative "../types"

module Ovallsp
  module Types
    # The Prism nodes whose type Ruby settles outright, and what it is.
    #
    # One table, because two evaluators read it and they kept drifting
    # apart. `LocalInferencer#eval_type` answers "what is this expression"
    # for hover and completion; `Semantic::MethodAnalyzer#eval_node`
    # answers "what does this method return" for every *caller* of it.
    # A literal missing from the second means a method ending in one
    # returns Unknown, so hovering the local it was assigned to answers an
    # empty popup — the same expression typed correctly on one line and
    # not on the next.
    #
    # It has happened twice. 0.2.1 added `Range` and `Regexp` to both,
    # then added `Lambda`, `!`, `&&` and `||` to the inferencer alone, and
    # the review after that found `def m; nil || "x"; end` losing its
    # type. `#covered?` is what stops a third round finding a third one:
    # the table is the list, and a spec asserts both evaluators answer for
    # every entry in it.
    #
    # Only what needs no lookup at all. A container's element type, a
    # method call's return type and anything reached through the index
    # belong to their own evaluator, which is why they are not here.
    module LiteralTypes
      module_function

      # Nodes whose class alone gives the answer.
      def table
        @table ||= {
          Prism::IntegerNode => Nominal.new(name: "Integer"),
          Prism::FloatNode => Nominal.new(name: "Float"),
          Prism::RationalNode => Nominal.new(name: "Rational"),
          Prism::StringNode => Nominal.new(name: "String"),
          Prism::InterpolatedStringNode => Nominal.new(name: "String"),
          Prism::SymbolNode => Nominal.new(name: "Symbol"),
          Prism::RangeNode => Nominal.new(name: "Range"),
          Prism::RegularExpressionNode => Nominal.new(name: "Regexp"),
          Prism::InterpolatedRegularExpressionNode => Nominal.new(name: "Regexp"),
          Prism::LambdaNode => Nominal.new(name: "Proc"),
          Prism::TrueNode => Nominal.new(name: "Boolean"),
          Prism::FalseNode => Nominal.new(name: "Boolean")
        }.freeze
      end

      def for_node(node) = table[node.class]

      # `!x` is a call rather than a literal, and its class is settled
      # whatever `x` is — one of the few calls that needs no lookup. Both
      # evaluators have to ask this separately because both reach
      # `CallNode` before they reach the table.
      def negation?(node) = node.is_a?(Prism::CallNode) && node.name == :!

      NEGATION_TYPE = Nominal.new(name: "Boolean")

      # `a && b` and `a || b` return one of their two operands, so the
      # answer is the union of both — not Boolean, which is what neither
      # returns. `||` yields its left side only when that side is truthy,
      # which is what makes `name || "anonymous"` a String rather than a
      # `String | nil`, and is the idiom worth having the case for.
      def boolean_operator(node, left, right)
        return Types.normalize_union([left, right]) unless node.is_a?(Prism::OrNode)
        return right if left == Types::NIL

        Types.normalize_union([Types.remove_nil(left), right])
      end
    end
  end
end
