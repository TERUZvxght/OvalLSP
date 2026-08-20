# frozen_string_literal: true

# A workspace that reopens a core class in `lib/core_ext/` (0.1.11).
#
# `HierarchyIndex`'s default chain names `Object`/`Kernel`/`BasicObject`
# bare while declarations are indexed qualified, and `SymbolId` equality
# is exact -- so every lookup that walked an ancestor chain and then asked
# the index missed for exactly those three. Adding a method by reopening
# `class Object` is as ordinary as Rails itself, and it produced a false
# `unknown-method` on every closed receiver in the workspace.
RSpec.describe "Ovallsp reopened core class lookups (0.1.11)" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:widget) { Ovallsp::Types::Nominal.new(name: "Widget") }

  before do
    {
      "file:///core_ext.rb" => "class Object\n  def blank?\n  end\n\n  private\n\n  def secret_helper\n  end\nend\n",
      "file:///widget.rb" => "class Widget\nend\n"
    }.each do |uri, text|
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
    end
  end

  it "resolves a method the workspace added to Object" do
    expect(method_resolver.resolve(receiver_type: widget, name: "blank?")).not_to be_empty
  end

  it "offers it in completion" do
    names = method_resolver.complete(receiver_type: widget, prefix: "bl").map { |m| m[:name] }

    expect(names).to include("blank?")
  end

  # The visibility lookup is the same qualified/bare comparison one line
  # further on. Fixing only the name lookup surfaces the names *and*
  # loses the filter, which is worse than either: a private helper on
  # `Object` offered on every receiver in the workspace.
  it "does not offer a private one through an explicit receiver" do
    names = method_resolver.complete(
      receiver_type: widget, prefix: "s", context: { implicit_self: false }
    ).map { |m| m[:name] }

    expect(names).not_to include("secret_helper")
  end

  it "does not report it as an unknown method" do
    local_inferencer = stack.local_inferencer
    document = Ovallsp::TextDocument.new(uri: "file:///u.rb", text: "Widget.new.blank?\n",
                                         version: 1, language_id: "ruby")
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: Ovallsp::Models::ModelRegistry.new,
      route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) }, generation: 1
    )

    findings = Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context,
                                                       mode: :standard)

    expect(findings.select { |f| f.code == "unknown-method" }).to be_empty
  end

  # The fix must not turn into matching by simple name.
  it "still reports a method nothing declares on Object or Widget" do
    expect(method_resolver.resolve(receiver_type: widget, name: "definitely_not_here")).to be_empty
  end
end
