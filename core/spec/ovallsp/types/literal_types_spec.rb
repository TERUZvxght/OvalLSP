# frozen_string_literal: true

# The countermeasure, rather than a test of the table itself.
#
# Two evaluators read `LiteralTypes`: `LocalInferencer#eval_type` answers
# what an expression is, for hover and completion; `MethodAnalyzer#eval_node`
# answers what a method *returns*, for every caller of it. Twice now, a
# literal has been added to one and not the other — first `Range` and
# `Regexp`, then `Lambda`, `!`, `&&` and `||` — and each time the symptom
# was the same expression typing correctly on one line and losing its type
# as the last line of a method.
#
# This asserts both evaluators answer for every entry in the table, driven
# from the table rather than from a list written out here, so adding a row
# is what extends the check. A per-literal regression test would pin the
# one case and leave the next omission to a reviewer, which is what
# happened twice.
RSpec.describe Ovallsp::Types::LiteralTypes do
  SOURCE_FOR_TYPE = {
    "Integer" => "1",
    "Float" => "1.5",
    "Rational" => "3r",
    "String" => '"s"',
    "Symbol" => ":sym",
    "Range" => "(1..5)",
    "Regexp" => "/abc/",
    "Proc" => "->(n) { n }",
    "Boolean" => "true"
  }.freeze

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index) }
  let(:analyzer) { stack.method_analyzer }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:summary_store) { Ovallsp::Semantic::MethodSummaryStore.new }

  def document(text) = Ovallsp::TextDocument.new(uri: "file:///l.rb", text: text, version: 1, language_id: "ruby")

  def expression_type(source)
    stack.local_inferencer.infer_at(document("x = #{source}\n"), { line: 0, character: 1 }).to_s
  end

  def return_type(source)
    summary = Ovallsp::ParserService.new.summarize(document("class Shapes\n  def build\n    #{source}\n  end\nend\n"))
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    symbol = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::Shapes", name: "build", discriminator: nil)
    analyzer.summarize(symbol_id: symbol).return_type.to_s
  end

  it "names a source for every type in the table, so the check cannot silently skip one" do
    expect(described_class.table.values.map(&:to_s).uniq.sort).to eq(SOURCE_FOR_TYPE.keys.sort)
  end

  SOURCE_FOR_TYPE.each do |type, source|
    it "answers #{type} for `#{source}` as an expression and as a method's return type" do
      expect(expression_type(source)).to eq(type)
      expect(return_type(source)).to eq(type)
    end
  end

  # Not in the table because both evaluators reach `CallNode` and the
  # operator nodes before it, so both have to ask separately — which is
  # exactly how they came to disagree.
  {
    "a negation" => ["!true", "Boolean"],
    "an `||` default" => ['nil || "anonymous"', "String"],
    # An instance is always truthy, so `||` never reaches its right side --
    # the mirror of the `&&` rule below, which this was missing.
    "an `||` on an always-truthy left" => ["User.new || Company.new", "User"],
    # `a && b` yields `a` only when `a` is *falsy*, so an instance --
    # always truthy -- drops out and the answer is the right-hand side.
    # Written as a plain union first, which claimed `"str" && 5` could be
    # a String.
    "an `&&` on an always-truthy left" => ["User.new && Company.new", "Company"],
    "an `&&` on a left that might be nil" => ["Article.find_by(id: 1) && \"x\"", "String | nil"],
    # A falsy `Boolean` is `false`, not `nil`. `true && false` was
    # answered `Boolean | nil` and `true && 5` `Integer | nil` -- neither
    # of which the expression can be.
    "an `&&` on a Boolean left" => ["true && 5", "Boolean | Integer"]
  }.each do |description, (source, expected)|
    it "answers the same for #{description} as an expression and as a method's return type" do
      expect(expression_type(source)).to eq(expected)
      expect(return_type(source)).to eq(expected)
    end
  end
end
