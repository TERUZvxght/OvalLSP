# frozen_string_literal: true

# **A core class is not up for reinterpretation by a gem.**
#
# `HierarchyIndex#canonical_name` asks the gem index what a bare name
# stands for where the workspace does not own it, so that `Relation` --
# which is how the type model spells `ActiveRecord::Relation` -- reaches
# the right chain. The rule was written with only one way of being
# wrong in mind: two gems claiming one simple name, which it declines.
#
# It has another. `Integer` is a core class, so it is structurally
# absent from the gem index -- `Object.const_source_location("Integer")`
# is `[]`, and the Agent keeps only what a gem path can be attributed
# to -- and nothing therefore contests a gem's nested `Type::Integer`.
# The bare name resolves to it, the receiver takes that class's chain,
# and every core method on it is reported as one that does not exist.
#
# Driven against the real Rails fixture rather than reasoned about:
#
#     Integer     n=2  JSON::…::Integer, ActiveModel::Type::Integer
#     Symbol      n=1  -> ActionDispatch::Journey::Nodes::Symbol
#     Range       n=1  -> Arel::Nodes::Range
#     Regexp      n=1  -> Arel::Nodes::Regexp
#     Relation    n=1  -> ActiveRecord::Relation
#
# Three core classes already captured on the machine this was measured
# on, and `Integer` captured on a machine where the second claimant
# happened not to be loaded -- which is how it reached CI as
# ``Integer has no method named `+` `` over `assert_equal 2, 1 + 1`
# while the same tree was green locally. Whether a core class keeps its
# meaning cannot depend on which gems a process has required.
#
# `Relation` is the same rule's good case and is asserted here too, in
# the same shape, so a fix that buys silence by switching the whole
# rule off fails this file rather than passing it.
RSpec.describe "a bare core name a gem's nested class would claim" do
  def gem_index_with(*classes)
    Ovallsp::Semantic::GemIndex.from_agent(
      { gems: { "typegem-1.0.0": { classes: classes } } }
    )
  end

  # Exactly one claimant each, which is the case the rule accepts.
  let(:gem_index) do
    gem_index_with(
      { name: "TypeGem::Integer",
        ancestors: %w[TypeGem::Integer TypeGem::Value Object Kernel BasicObject],
        instanceMethods: %w[cast serialize], singletonMethods: [], definesMethodMissing: false },
      { name: "TypeGem::Value", ancestors: %w[TypeGem::Value Object Kernel BasicObject],
        instanceMethods: %w[cast], singletonMethods: [], definesMethodMissing: false },
      { name: "TypeGem::Relation",
        ancestors: %w[TypeGem::Relation Object Kernel BasicObject],
        instanceMethods: %w[to_sql], singletonMethods: [], definesMethodMissing: false }
    )
  end

  def stack(index: gem_index, source: "")
    workspace_index = Ovallsp::WorkspaceIndex.new
    document = Ovallsp::TextDocument.new(uri: "file:///probe.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    built = Ovallsp::AnalysisStack.build(
      signatures: AnalysisStackHelper.shared_signatures, workspace_index: workspace_index, gem_index: index
    )
    built.hierarchy_index.replace_file(summary)
    [built, document]
  end

  def findings(source, index: gem_index)
    built, document = stack(index: index, source: source)
    context = built.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, generation: 1)
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
      .map(&:message)
  end

  def ancestor_names(name)
    built, = stack
    built.hierarchy_index.ancestors(name).map(&:name)
  end

  it "leaves a core class its own chain rather than the gem class that shares its last segment" do
    expect(ancestor_names("Integer")).not_to include("TypeGem::Value")
  end

  it "reports nothing for arithmetic on an Integer" do
    expect(findings("def go\n  1 + 1\nend\n")).to be_empty
  end

  # The other half of the same rule, and the reason it exists. A fix
  # that declines every bare name passes the two above and fails here.
  it "still lets a bare name no core class claims reach the gem's chain" do
    expect(ancestor_names("Relation")).to include("TypeGem::Relation")
  end

  # The control: this file's fixture is being diagnosed at all, so the
  # silence above is the check declining rather than nothing running.
  it "still reports a name the gem class genuinely does not declare" do
    expect(findings("def go\n  TypeGem::Value.new.no_such_thing\nend\n").join(" "))
      .to match(/no_such_thing/)
  end
end
