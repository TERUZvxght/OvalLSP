# frozen_string_literal: true

# `HierarchyIndex` records a parent it cannot identify -- `class Foo <
# (expression)` -- as a nameless `AncestorEntry`. `nil` is also the owner
# a *top-level* `def` is indexed under, so asking that entry for its
# methods answers with every top-level method in the workspace.
#
# `MethodResolver#build_candidate` knows this and returns early, with a
# comment recording the bug: "Every class with an unknown parent
# inherited every top-level method in the workspace."
#
# `#names_for_type`, which is what completion asks, had no such guard.
# Found by an external review (GPT-5.6 Sol) reading the two consumers
# against each other, and reproduced here before fixing: one consumer
# sealed an ambiguous representation locally and the other did not, which
# is the shape the review was asked to look for.
RSpec.describe "Ovallsp::Semantic::MethodResolver and a parent it cannot name" do
  def build(sources)
    index = Ovallsp::WorkspaceIndex.new
    hierarchy = build_analysis_stack(workspace_index: index).hierarchy_index
    sources.each do |uri, text|
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      index.replace_file(summary)
      hierarchy.replace_file(summary)
    end
    [index, hierarchy]
  end

  let(:sources) do
    {
      "file:///top.rb" => "def top_level_helper_zzz; end\n",
      "file:///sub.rb" => "class Unknowable < (SomethingDynamic.call)\nend\n"
    }
  end

  it "records the unidentifiable parent as a nameless entry" do
    _index, hierarchy = build(sources)

    expect(hierarchy.ancestors("Unknowable", singleton: false).map(&:name)).to include(nil)
  end

  it "does not offer the workspace's top-level methods as members of that class" do
    index, hierarchy = build(sources)
    resolver = build_analysis_stack(workspace_index: index).method_resolver

    names = resolver.send(:names_for_type, Ovallsp::Types::Nominal.new(name: "Unknowable"), "top_level", {})

    expect(names.map { |n| n.respond_to?(:name) ? n.name : n }).to be_empty
  end

  # The control: an ordinary class must still complete its own methods,
  # or "return nothing for everything" would satisfy the example above.
  it "still offers a nameable owner's own methods" do
    index, hierarchy = build("file:///w.rb" => "class Widget\n  def widget_thing_zzz; end\nend\n")
    resolver = build_analysis_stack(workspace_index: index).method_resolver

    names = resolver.send(:names_for_type, Ovallsp::Types::Nominal.new(name: "Widget"), "widget", {})

    expect(names.map { |n| n.respond_to?(:name) ? n.name : n }).to include("widget_thing_zzz")
  end
end
