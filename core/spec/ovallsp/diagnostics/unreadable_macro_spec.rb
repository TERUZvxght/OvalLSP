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

  # **Rolled back inside 0.2.11, and this example records why.** The fix
  # marked the owner's *class* surface open as well as its instance one.
  # That is right for the class in front of you and catastrophic for
  # `class Module`, `class Object` or `class Kernel`: they are in every
  # class's singleton chain, so one bare `alias_method` in a `core_ext`
  # file switched off `Foo.bar` checking for the whole workspace. A
  # `drive` round measured it over 1,659 files of 16 gems --
  # constant-receiver `unknown-method` findings **117 -> 0**, and among
  # the removals a real latent `NoMethodError`
  # (`ActiveRecord::Promise.wrap`).
  #
  # The measurement that justified the reversal had the same
  # contamination: its corpus contained activesupport's
  # `core_ext/module/attr_internal.rb`, a bare `alias_method` in
  # `class Module`, and the sampling missed it. So the engine still
  # contradicts itself about one fact -- `024.110`, open, with what a real
  # fix has to distinguish written down.
  it "still reports the macro itself, which is what 024.110 is about" do
    document = index("class HostC\n  attr_atomic :thing\nend\n")

    expect(unknown_methods(document)).to eq(["attr_atomic"])
  end

  # **The reproduction that decided it.** `Widget` has no macros and
  # lives in another file; the only unreadable call in the workspace is
  # in a reopened `Module`.
  it "does not let a reopened core class silence an unrelated class's class-level call" do
    index("class Module\n  def blank_slate?; false; end\n  alias_method :blank?, :blank_slate?\nend\n",
          uri: "file:///core_ext.rb")
    index("class Widget\n  def go; 1; end\nend\n", uri: "file:///widget.rb")
    document = index("Widget.tpyo_class\n", uri: "file:///caller.rb")

    expect(unknown_methods(document)).to eq(["tpyo_class"])
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
