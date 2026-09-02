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

  # **`prepend` puts the module ahead of the class**, and both gem
  # chain-builders assumed the payload's first element was the class
  # itself and dropped it by position:
  #
  #   $ ruby -e '
  #   module Pre; end
  #   module Inc; end
  #   class Prepended; prepend Pre; end
  #   class Included; include Inc; end
  #   p Prepended.ancestors.first(2).map(&:to_s)
  #   p Included.ancestors.first(2).map(&:to_s)
  #   '
  #   # => ["Pre", "Prepended"]
  #   # => ["Included", "Inc"]
  #   # ruby 3.4.10
  #
  # APM and instrumentation gems prepend into ActiveRecord and
  # ActionController routinely, so this is not a corner: the prepended
  # module vanished from the chain, its methods were reported missing on
  # correct code, and the class itself was left on the chain twice.
  let(:prepended_index) do
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "patchgem-1.0.0": { classes: [
        { name: "SomeGem::Patch", ancestors: %w[SomeGem::Patch Object Kernel BasicObject],
          instanceMethods: %w[patched], singletonMethods: [], definesMethodMissing: false },
        { name: "PatchGem::Base",
          ancestors: %w[SomeGem::Patch PatchGem::Base Object Kernel BasicObject],
          instanceMethods: %w[persist], singletonMethods: [], definesMethodMissing: false }
      ] } } }
    )
  end

  it "keeps a prepended module on a gem class's chain" do
    source = "class Widget < PatchGem::Base\n  def go\n    patched\n    persist\n    no_such_thing\n  end\nend\n"
    messages = findings(source, index: prepended_index).select { |f| f.code == "unknown-method" }
                                                       .map(&:message).join(" ")

    expect(messages).not_to include("`patched`"), "the prepended module was dropped off the chain"
    expect(messages).not_to include("`persist`")
    # CONTROL: with the chain no longer trimmed by position, a real typo
    # must still be reported -- otherwise keeping every name would pass.
    expect(messages).to include("`no_such_thing`")
  end

  # The singleton side has the same idiom and the same defect, and its
  # branch was inert in the suite because no fixture carried
  # `singletonAncestors` at all -- `Array(nil).drop(1)` is `[]`, so the
  # bug could not show. The Agent has already removed the anonymous
  # `#<Class:X>` (it has no `module_name`), so element 0 is the first
  # *extended* module -- exactly the thing this method exists to add.
  #
  # A **module** rather than a class, so the second half of the defect
  # shows too: `Class` and `Module` survived the default-chain reject,
  # which made the result non-empty for any receiver at all and handed a
  # module the class-object tail.
  let(:extended_index) do
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "extgem-1.0.0": { classes: [
        { name: "ExtGem::Naming", ancestors: %w[ExtGem::Naming Object Kernel BasicObject],
          instanceMethods: %w[human_name], singletonMethods: [], definesMethodMissing: false },
        { name: "ExtGem::Base", ancestors: %w[ExtGem::Base Object Kernel BasicObject],
          singletonAncestors: %w[ExtGem::Naming Class Module Object Kernel BasicObject],
          instanceMethods: [], singletonMethods: %w[configure], definesMethodMissing: false }
      ] } } }
    )
  end

  it "keeps an extended module on a gem class's singleton chain" do
    source = "ExtGem::Base.human_name\nExtGem::Base.configure\nExtGem::Base.no_such_thing\n"
    messages = findings(source, index: extended_index).select { |f| f.code == "unknown-method" }
                                                      .map(&:message).join(" ")

    expect(messages).not_to include("`human_name`"), "the extended module was dropped off the singleton chain"
    expect(messages).not_to include("`configure`")
    # CONTROL, same fixture: a name nothing on the chain declares.
    expect(messages).to include("`no_such_thing`")
  end

  # **A receiverless call may legally reach an inherited private
  # method**, and the Agent sent only `instance_methods(false)`, which
  # Ruby says excludes them:
  #
  #   $ ruby -e '
  #   class PrivProbe
  #     def pub; end
  #     private def helper; end
  #   end
  #   p PrivProbe.instance_methods(false).sort
  #   p PrivProbe.private_instance_methods(false).sort
  #   p PrivProbe.protected_instance_methods(false).sort
  #   '
  #   # => [:pub]
  #   # => [:helper]
  #   # => []
  #   # ruby 3.4.10
  #
  # So a subclass of a gem class calling the gem's own private helper --
  # `process_action` on an ActionController subclass, to name the one
  # this was driven against -- was reported as calling a method that
  # does not exist, on correct code.
  #
  # The visibility split is kept rather than merged: the private name
  # arrives as a candidate whose `visibility` is `:private`, so the
  # explicit-receiver check still refuses `obj.helper`.
  let(:visibility_index) do
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "vizgem-1.0.0": { classes: [
        { name: "VizGem::Base", ancestors: %w[VizGem::Base Object Kernel BasicObject],
          instanceMethods: %w[persist], privateInstanceMethods: %w[helper],
          protectedInstanceMethods: %w[compare], singletonMethods: [], definesMethodMissing: false }
      ] } } }
    )
  end

  it "lets a subclass call a gem's inherited private and protected methods" do
    source = "class Widget < VizGem::Base\n  def go\n    persist\n    helper\n    compare\n    no_such_thing\n  end\nend\n"
    messages = findings(source, index: visibility_index).select { |f| f.code == "unknown-method" }
                                                        .map(&:message).join(" ")

    expect(messages).not_to include("`helper`"), "an inherited private gem method was called missing"
    expect(messages).not_to include("`compare`")
    expect(messages).not_to include("`persist`")
    # CONTROL, same fixture: adding the two sets must not open the class.
    expect(messages).to include("`no_such_thing`")
  end

  # **The gem index resolved any bare name by unique last segment**, on
  # the private method every public reader goes through -- so a
  # workspace class called `Widget` was answered from a gem's
  # `WidgetGem::Widget`. It was then "closed" with a method set that is
  # not its own: a typo went unreported, and the foreign class's methods
  # were offered on it.
  #
  # The simple-name resolution exists for the type model, where
  # `Relation[Post]` must find `ActiveRecord::Relation`, and it belongs
  # where a name the *workspace* does not own is being resolved -- not
  # on the lookup that answers "what is on this class".
  let(:collision_index) do
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "othergem-1.0.0": { classes: [
        { name: "OtherGem::Widget", ancestors: %w[OtherGem::Widget Object Kernel BasicObject],
          instanceMethods: %w[persist], singletonMethods: [], definesMethodMissing: false }
      ] } } }
    )
  end

  it "does not answer for a workspace class from a gem class that shares its last segment" do
    source = "class Widget\n  def go\n    own\n    persist\n  end\n\n  def own\n  end\nend\n"
    messages = findings(source, index: collision_index).select { |f| f.code == "unknown-method" }
                                                       .map(&:message).join(" ")

    expect(messages).to include("`persist`"), "a foreign gem class's method was lent to a workspace class"
    # CONTROL, same fixture: the class's own method is still accounted for.
    expect(messages).not_to include("`own`")
  end
end
