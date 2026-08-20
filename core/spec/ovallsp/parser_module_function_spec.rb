# frozen_string_literal: true

# `024.106`. `module_function` and `extend self` are the two everyday
# ways of writing a module whose methods you call on the module, and
# neither produced anything: `MF.` completed 190 items with no `mf_a`
# among them. `def self.x` and `class << self` in a module already
# worked, so it is these two idioms specifically.
#
# Ground truth, taken from the interpreter rather than from memory:
#
#   $ ruby -e '
#   module MF
#     module_function
#     def mf_a; end
#   end
#   module MF2
#     def mf_c; end
#     def mf_d; end
#     module_function :mf_c
#   end
#   module ES
#     extend self
#     def es_a; end
#   end
#   p [MF.respond_to?(:mf_a), MF.private_instance_methods(false)]
#   #   => [true, [:mf_a]]
#   p [MF2.respond_to?(:mf_c), MF2.respond_to?(:mf_d)]
#   #   => [true, false]
#   p [MF2.instance_methods(false), MF2.private_instance_methods(false)]
#   #   => [[:mf_d], [:mf_c]]
#   p [ES.respond_to?(:es_a), ES.instance_methods(false)]
#   #   => [true, [:es_a]]
#   '
#   # ruby 3.4.10
#
# Two different shapes, which is why they are fixed differently:
# `module_function` copies each method to the singleton side and makes
# the instance copy *private*; `extend self` adds no methods at all, it
# puts the module in its own singleton chain.
RSpec.describe "Ovallsp::ParserService and module-level self-calling idioms" do
  def summarize(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///mf.rb", text: text, version: 1, language_id: "ruby")
    )
  end

  def declared(summary, kind)
    summary.declarations.select { |d| d.symbol_id.kind == kind }
           .map { |d| [d.symbol_id.name, d.visibility] }.sort
  end

  describe "a bare module_function" do
    let(:summary) { summarize("module MF\n  module_function\n  def mf_a; end\n  def mf_b; end\nend\n") }

    it "puts every method after it on the module's singleton side" do
      expect(declared(summary, :singleton_method).map(&:first)).to eq(%w[mf_a mf_b])
    end

    it "makes the instance copy private, which is what stops it being offered on an instance" do
      expect(declared(summary, :instance_method)).to eq([["mf_a", :private], ["mf_b", :private]])
    end
  end

  describe "module_function with names" do
    let(:summary) do
      summarize("module MF2\n  def mf_c; end\n  def mf_d; end\n  module_function :mf_c\nend\n")
    end

    # The distinguishing half: `mf_d` is *not* named, so it stays a public
    # instance method and off the singleton side entirely. An
    # implementation that treated the argument form as the bare form
    # would pass the first assertion and fail this one.
    it "moves only the methods it names" do
      expect(declared(summary, :singleton_method).map(&:first)).to eq(["mf_c"])
      expect(declared(summary, :instance_method)).to eq([["mf_c", :private], ["mf_d", :public]])
    end
  end

  describe "extend self" do
    let(:summary) { summarize("module ES\n  extend self\n  def es_a; end\nend\n") }

    # No singleton declaration: Ruby adds no methods here, it puts the
    # module in its own singleton chain, and the methods stay public
    # instance methods. Recording a singleton copy would answer the same
    # completion question by the wrong means and would be wrong about
    # `ES.instance_methods(false)`.
    it "records the module extending itself, and leaves the methods where they are" do
      expect(declared(summary, :instance_method)).to eq([["es_a", :public]])
      expect(declared(summary, :singleton_method)).to be_empty
      expect(summary.ancestor_facts.map { |f| [f.owner, f.relation, f.target] })
        .to include(["::ES", :extend, "::ES"])
    end
  end
end

# The other half of `024.106`: **nothing checked a module's class-level
# calls at all.** `PlainClass.nope_y` was reported and `PlainMod.nope_x`
# was not, on a module whose `def self.` methods the engine does know.
#
# The cause was one line asking every receiver's *instance* chain to
# reach `::BasicObject` before anything may be asserted about it. A
# module's does not, and correctly so:
#
#   $ ruby -e '
#   module PlainMod; def self.known; end; end
#   p PlainMod.ancestors                          # => [PlainMod]
#   p (PlainMod.nope_x rescue $!.class)           # => NoMethodError
#   '
#   # ruby 3.4.10
RSpec.describe "Ovallsp::Diagnostics::Engine and a module's class-level calls" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver, workspace_index: workspace_index,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
  end

  def index(text, uri:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "unknown-method" }
                                .map { |f| f.message[/named `(.+)`/, 1] }
  end

  before do
    index("module PlainMod\n  def self.known; end\nend\n", uri: "file:///pm.rb")
    index("class PlainClass\n  def self.known; end\nend\n", uri: "file:///pc.rb")
  end

  it "reports a typo on a module exactly as it does on a class" do
    document = index("PlainMod.nope_x\nPlainClass.nope_y\n", uri: "file:///use.rb")

    expect(unknown_methods(document)).to contain_exactly("nope_x", "nope_y")
  end

  # The control: the methods that *are* there stay silent, on both.
  it "says nothing about the calls that work" do
    document = index("PlainMod.known\nPlainClass.known\n", uri: "file:///ok.rb")

    expect(unknown_methods(document)).to be_empty
  end
end
