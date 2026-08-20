# frozen_string_literal: true

# `024.110`. An unrecognised class-body macro correctly opens the owner's
# surface, so nothing it *might* define is reported. The call that opened
# it was reported anyway — the engine saying "I cannot enumerate this
# class's members because something unreadable ran here" and then
# asserting that the unreadable thing does not exist.
#
# One fact, two contradictory answers. A false report on ordinary code
# whenever a macro comes from a gem, a `Concern`, or an `extend` this
# parser cannot follow.
RSpec.describe "Ovallsp::Diagnostics::Engine and a macro it cannot read" do
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

  def index(text, uri: "file:///a.rb")
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

  # `024.116`. `declares_method_missing?` asked the index for
  # `kind: :instance_method` only, so a class answering class-level calls
  # through `def self.method_missing` was judged closed and every call it
  # handles was reported. Ruby:
  #
  #   $ ruby -e '
  #   class CWithMM
  #     def self.method_missing(n, *a) = :mm
  #     def self.respond_to_missing?(n, p = false) = true
  #   end
  #   p CWithMM.anything
  #   class CDynamic
  #     %w[dyn_a dyn_b].each { |n| define_singleton_method(n) { n } }
  #   end
  #   p CDynamic.dyn_a
  #   '
  #   # => :mm  and  "dyn_a"
  #   # ruby 3.4.10
  describe "a class that answers class-level calls it does not declare" do
    it "says nothing when the class defines def self.method_missing" do
      index("class CWithMM\n  def self.method_missing(name, *args); end\nend\n", uri: "file:///mm.rb")
      document = index("CWithMM.anything\n", uri: "file:///use_mm.rb")

      expect(unknown_methods(document)).to be_empty
    end

    it "says nothing when its class methods are made by define_singleton_method" do
      index("class CDynamic\n  %w[dyn_a dyn_b].each { |n| define_singleton_method(n) { n } }\nend\n",
            uri: "file:///dyn.rb")
      document = index("CDynamic.dyn_a\n", uri: "file:///use_dyn.rb")

      expect(unknown_methods(document)).to be_empty
    end

    # The control: a class doing neither still answers. Without this,
    # "stop reporting class-level calls" would pass both examples above.
    it "still reports a class-level typo on a class that does neither" do
      index("class COrdinary\n  def self.known; end\nend\n", uri: "file:///ord.rb")
      document = index("COrdinary.nope_x\n", uri: "file:///use_ord.rb")

      expect(unknown_methods(document)).to eq(["nope_x"])
    end
  end

  it "says nothing about the macro itself, having declined to enumerate what it defines" do
    document = index("class HostC\n  attr_atomic :thing\nend\n")

    expect(unknown_methods(document)).to be_empty
  end

  # The control that keeps this from being "stop reporting class-level
  # calls": a class whose body ran nothing unreadable still answers.
  it "still reports a class-level typo on a class whose body it could read" do
    index("class Plain\n  def self.known; end\nend\n", uri: "file:///plain.rb")
    document = index("Plain.known\nPlain.nope_x\n", uri: "file:///use.rb")

    expect(unknown_methods(document)).to eq(["nope_x"])
  end

  # And the distinguishing pair: the *same* file, with and without the
  # unreadable macro. An implementation that silenced the owner entirely
  # would pass the first example and fail this one.
  it "still reports a typo on a class that also ran a macro, once the call is elsewhere" do
    index("class Mixed\n  attr_atomic :thing\n  def self.known; end\nend\n", uri: "file:///mixed.rb")
    document = index("Mixed.known\n", uri: "file:///ok.rb")

    expect(unknown_methods(document)).to be_empty
  end
end
