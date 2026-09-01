# frozen_string_literal: true

# 024.R7's Core half. "Closed" stops meaning "declared in this
# workspace" and starts meaning "we know its full method set".
#
# **The two halves must arrive together.** Telling the engine a gem
# class is closed without also telling it that class's methods turns
# every correct call on a gem into a report — so every example here
# asserts both directions on the same fixture: the typo is reported and
# the real gem method is not.
RSpec.describe "a receiver whose ancestry runs into a gem" do
  let(:gem_index) do
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "widgetgem-1.0.0": { classes: [
        { name: "WidgetGem::Base",
          ancestors: %w[WidgetGem::Base WidgetGem::Naming Object Kernel BasicObject],
          instanceMethods: %w[persist], singletonMethods: %w[configure], definesMethodMissing: false },
        { name: "WidgetGem::Naming", ancestors: %w[WidgetGem::Naming Object Kernel BasicObject],
          instanceMethods: %w[human_name], singletonMethods: [], definesMethodMissing: false },
        # A **module**: its loaded ancestry does not reach `Object`,
        # which is how a bare module reads. What `self` is inside a
        # `ClassMethods`-style module at call time is whatever class
        # extended it, so rooting one is a report factory -- 795 false
        # reports over activerecord's own source, measured.
        { name: "WidgetGem::ClassMethods", ancestors: %w[WidgetGem::ClassMethods],
          instanceMethods: %w[declared], singletonMethods: [], definesMethodMissing: false },
        { name: "WidgetGem::Dynamic", ancestors: %w[WidgetGem::Dynamic Object Kernel BasicObject],
          instanceMethods: [], singletonMethods: [], definesMethodMissing: true },
        # A class whose *ancestor* answers at call time. `#knows?` is
        # asked of the receiver and says yes here; the resolver's own
        # refusal is asked of every link, and only this shape tells the
        # two apart -- with the first fixture both made the receiver
        # open and the guard was measured unpinned.
        { name: "WidgetGem::Heir",
          ancestors: %w[WidgetGem::Heir WidgetGem::Dynamic Object Kernel BasicObject],
          instanceMethods: %w[settled], singletonMethods: [], definesMethodMissing: false }
      ] } } }
    )
  end

  def findings(source, index: gem_index)
    workspace_index = Ovallsp::WorkspaceIndex.new
    document = Ovallsp::TextDocument.new(uri: "file:///probe.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack = Ovallsp::AnalysisStack.build(
      signatures: AnalysisStackHelper.shared_signatures, workspace_index: workspace_index, gem_index: index
    )
    stack.hierarchy_index.replace_file(summary)
    context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, generation: 1)
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
  end

  SUBCLASS = <<~RUBY
    class Widget < WidgetGem::Base
      def go
        persist
        human_name
        no_such_thing
      end
    end
  RUBY

  it "reports a typo on a class whose parent is in a gem" do
    messages = findings(SUBCLASS).select { |f| f.code == "unknown-method" }.map(&:message)

    expect(messages.join(" ")).to include("no_such_thing")
  end

  # The other half, and the one that decides whether this is shippable.
  it "reports nothing about the gem's own methods, inherited or direct" do
    messages = findings(SUBCLASS).select { |f| f.code == "unknown-method" }.map(&:message).join(" ")

    expect(messages).not_to include("persist"), "the gem's own method was called missing"
    expect(messages).not_to include("human_name"), "a method from the gem's ancestor was called missing"
  end

  # The control: with no gem index this is the pre-0.3.0 behaviour, and
  # the typo goes unreported. Without it these examples would pass on a
  # build that simply reports everything.
  it "says nothing at all without the index, which is what this replaces" do
    empty = Ovallsp::Semantic::GemIndex.empty

    expect(findings(SUBCLASS, index: empty).select { |f| f.code == "unknown-method" }).to be_empty
  end

  # **A `method_missing` class is never closed**, whatever the index
  # holds: it answers to names no enumeration can list.
  it "stays silent under a parent that answers at call time" do
    source = "class Widget < WidgetGem::Dynamic\n  def go\n    anything_at_all\n  end\nend\n"

    expect(findings(source).select { |f| f.code == "unknown-method" }).to be_empty
  end

  # And when the `method_missing` is an *ancestor* of the receiver
  # rather than the receiver itself. `#knows?` answers about the
  # receiver alone, so this is the shape that pins the resolver's own
  # refusal -- measured unpinned without it.
  it "stays silent when an ancestor answers at call time" do
    source = "class Widget < WidgetGem::Heir\n  def go\n    anything_at_all\n  end\nend\n"

    expect(findings(source).select { |f| f.code == "unknown-method" }).to be_empty
  end

  # The classes-only guard. Without a module in the fixture nothing
  # could tell "root a class" from "root anything", and it measured
  # unpinned.
  it "says nothing inside a module, whose self at call time it cannot know" do
    source = "module WidgetGem::ClassMethods\n  def go\n    whatever_the_extender_has\n  end\nend\n"

    expect(findings(source).select { |f| f.code == "unknown-method" }).to be_empty
  end

  # Singleton side, which is a different chain and a different half of
  # the index.
  it "tells a class method the gem defines from one it does not" do
    source = "class Widget < WidgetGem::Base\n  def self.go\n    configure\n    not_configured\n  end\nend\n"
    messages = findings(source).select { |f| f.code == "unknown-method" }.map(&:message).join(" ")

    # Backticked, because `not_configured` *contains* `configure` and
    # the plain substring test passed while the engine was reporting
    # exactly one of them. The message spells a method in backticks.
    expect(messages).to include("`not_configured`")
    expect(messages).not_to include("`configure`")
  end
end
