# frozen_string_literal: true

# `024.82`. A class created by assignment rather than by the `class`
# keyword was recorded as a **constant**, so nothing that looks for a
# class ever saw it.
#
# Measured with a control, which is what makes it a defect rather than a
# preference — the two forms are given the same two calls:
#
#     class Keyworded < Base   ...   reports `definitely_absent`
#     Assigned = Class.new(Base) ... reports nothing at all
#
# The engine declines rather than answering wrongly, so this is a missed
# report and not a false one. It is common in real code:
# `Concurrent::Error` and the rest of `concurrent/errors.rb` are written
# this way, as is `Rack::Utils::ParameterTypeError`.
#
# Ruby's own view of the two, read rather than assumed:
#
#     $ ruby -e 'class B; end; A = Class.new(B); p [A.class, A.superclass, A.name]'
#     [Class, B, "A"]
RSpec.describe "a class created by assignment" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end

  def index(text, uri)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    [document, summary]
  end

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "unknown-method" }.map { |f| f.message[/named `(.+?)`/, 1] }
  end

  before do
    index("class Base\n  def shared; 1; end\nend\nAssigned = Class.new(Base)\nclass Keyworded < Base\nend\n",
          "file:///a.rb")
  end

  # Compared against the keyword form rather than against a literal,
  # because the point is that the two are recorded the same way — and a
  # literal would have to guess at the qualification, which is exactly
  # what this example got wrong on its first run.
  it "is recorded the way the keyword form is" do
    _, assigned = index("Other = Class.new\n", "file:///b.rb")
    _, keyworded = index("class Other; end\n", "file:///b2.rb")

    shape = ->(summary) { summary.declarations.map { |d| [d.symbol_id.kind, d.symbol_id.name] } }

    expect(shape.call(assigned)).to eq(shape.call(keyworded))
    expect(shape.call(assigned).map(&:first)).to eq([:class])
  end

  it "reports an absent method on it, as the keyword form does" do
    document, = index("z = Assigned.new\nz.definitely_absent\n", "file:///c.rb")

    expect(unknown_methods(document)).to eq(["definitely_absent"])
  end

  it "inherits from the superclass it was given" do
    document, = index("z = Assigned.new\nz.shared\n", "file:///d.rb")

    expect(unknown_methods(document)).to be_empty
  end

  # The control that makes the two comparable, and the reason this is a
  # defect: the keyword form has always behaved this way.
  it "matches what the keyword form does" do
    assigned, = index("z = Assigned.new\nz.definitely_absent\n", "file:///e.rb")
    keyworded, = index("z = Keyworded.new\nz.definitely_absent\n", "file:///f.rb")

    expect(unknown_methods(assigned)).to eq(unknown_methods(keyworded))
  end

  # **A form that generates members must not be enumerated**, and the
  # corpus is what taught this. Naming these classes removed six
  # `unresolved-constant` reports over 269 files of real gem source and
  # added one wrong `unknown-method` --
  # ``HeredocData has no method named `common_whitespace=` `` -- on a
  # `Struct.new` accessor that plainly exists.
  #
  # Asked of Ruby rather than assumed:
  #
  #     Class.new(B).instance_methods(false)        # => []
  #     Struct.new(:a, :b).instance_methods(false)  # => [:a, :a=, :b, :b=]
  #     Data.define(:x).instance_methods(false)     # => [:x]
  #     Class.new(B) { def own_m; end }             # => [:own_m]
  it "declines about a Struct, whose accessors it never sees" do
    index("Point = Struct.new(:x, :y)\n", "file:///s.rb")
    document, = index("p = Point.new\np.x\np.definitely_absent\n", "file:///s2.rb")

    expect(unknown_methods(document)).to be_empty
  end

  it "declines about any of them given a block, whose body it does not attribute here" do
    index("Blocky = Class.new(Base) do\n  def own_m; end\nend\n", "file:///bl.rb")
    document, = index("b = Blocky.new\nb.definitely_absent\n", "file:///bl2.rb")

    expect(unknown_methods(document)).to be_empty
  end

  # And the half that is kept: a plain `Class.new(Base)` generates
  # nothing, so it stays enumerable and the check goes on working.
  it "still enumerates a plain Class.new with no block" do
    document, = index("z = Assigned.new\nz.definitely_absent\n", "file:///pl.rb")

    expect(unknown_methods(document)).to eq(["definitely_absent"])
  end

  # **Nested, because a top-level fixture cannot tell.** With no
  # enclosing namespace the qualified and unqualified names are the same
  # string, so the first version of this spec passed while the name was
  # being recorded as `::HeredocData` instead of `::M::L::HeredocData` —
  # which meant the open surface, keyed on the qualified name, was never
  # found. The corpus caught it; this example is what would have.
  it "records the qualified name when it is nested" do
    _, summary = index("module M\n  class L\n    Inner = Class.new\n  end\nend\n", "file:///n.rb")
    names = summary.declarations.select { |d| d.symbol_id.kind == :class }.map { |d| d.symbol_id.name }

    expect(names).to include("::M::L::Inner")
  end

  # The distinguishing half: an ordinary constant must stay a constant.
  # "Every constant assignment is a class" would pass everything above
  # and be wrong on the commonest line in Ruby.
  it "leaves an ordinary constant a constant" do
    _, summary = index("LIMIT = 10\nNAMES = %w[a b]\n", "file:///g.rb")
    kinds = summary.declarations.map { |d| [d.symbol_id.kind, d.symbol_id.name] }

    expect(kinds).to contain_exactly([:constant, "LIMIT"], [:constant, "NAMES"])
  end
end
