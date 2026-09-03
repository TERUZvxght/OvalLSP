# frozen_string_literal: true

# `024.128`. `price * qty` on two Integers hovered
# `Complex | Float | Integer | Rational`.
#
# RBS declares four `Integer#*` overloads, each keyed on the argument's
# type, and the resolver matched on **shape only** — arity and block
# presence — so all four fitted a one-argument call and every return
# type joined the union. The argument was sitting right there.
#
# Both authorities, read rather than remembered:
#
#     $ ruby -e 'p [(10 * 3).class, (10 * 1.5).class, (2 ** 3).class, (2 ** -1).class]'
#     [Integer, Float, Integer, Rational]
#
#     Integer#*  : (::Float) -> ::Float
#     Integer#*  : (::Rational) -> ::Rational
#     Integer#*  : (::Complex) -> ::Complex
#     Integer#*  : (::Integer) -> ::Integer
#     Integer#** : (::Integer) -> ::Numeric      <- deliberately not Integer
#
# `**` is the case that must **not** narrow to `Integer`: RBS says
# `Numeric` for an Integer exponent, and Ruby agrees — `2 ** -1` is a
# Rational. Narrowing by argument type must therefore pick the overload,
# not invent the return.
RSpec.describe "Ovallsp::Signatures::OverloadResolver narrowing by argument type" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: Ovallsp::Models::ModelRegistry.new,
                         signatures: Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) })
  end

  def type_of(source, line)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    stack.local_inferencer.infer_at(document, { line: line, character: 0 }).to_s
  end

  it "answers Integer for Integer arithmetic" do
    expect(type_of("price = 10\nqty = 3\ntotal = price * qty\ntotal\n", 3)).to eq("Integer")
  end

  it "answers Float when one side is a Float" do
    expect(type_of("a = 10\nb = 1.5\nc = a * b\nc\n", 3)).to eq("Float")
  end

  # The guard against over-narrowing. RBS declares `Integer#**(Integer)`
  # as `Numeric` on purpose, because the answer depends on the *value*:
  # `2 ** 3` is an Integer and `2 ** -1` is a Rational. Picking the
  # overload must not become inventing its return type.
  it "keeps Numeric where RBS declares Numeric, rather than guessing Integer" do
    expect(type_of("a = 2\nb = 3\nc = a ** b\nc\n", 3)).to eq("Numeric")
  end

  # The guard against narrowing on information that is not there. When
  # the argument's type is unknown, no overload may be picked.
  #
  # **The expectation here was written wrong first and the tree
  # corrected it.** It asserted a union, on the belief that an unknown
  # argument leaves every overload contributing; the engine answers
  # `Unknown` for the whole expression instead, which is a different and
  # more honest thing. Recorded because `docs/CODE_DISCIPLINE.md` asks where an
  # expected value came from, and the answer here is "a belief, until it
  # was run".
  it "answers Unknown, not a narrowed type, when the argument's type is unknown" do
    source = "def f(x)\n  y = 10 * x\n  y\nend\n"

    expect(type_of(source, 2)).to eq("Unknown")
  end
end
