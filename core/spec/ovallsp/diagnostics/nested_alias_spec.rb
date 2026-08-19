# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# RBS aliases like `int`, `string` and `selector` mean "anything that
# converts", not a class, so reporting an argument against one is a false
# positive by construction. The argument checker skipped them by testing
# whether the expected type's name is capitalised -- true of every Ruby
# constant, false of every alias.
#
# 0.2.5 stopped RBS names losing their namespace, and `String::selector`
# is capitalised. The guard stopped firing, and `"a.b".tr('.', '')` --
# ordinary, correct Ruby -- started being reported. 50 nested aliases in
# rbs 4.0.3 flip the same way: `String::selector` behind `tr`, `tr_s`,
# `delete`, `squeeze`, `count`; `IO::cmd_array`; `FileUtils::mode`;
# `JSON::options`.
#
# Found by driving a real corpus, not by the suite: no fixture called a
# selector-typed method on a *known* String, so "the whole suite, one
# failure" measured a blast radius that could not include this.
#
# A Ruby constant must begin with an uppercase letter, so what tells a
# class from an alias is the **last segment**, not the first character of
# the whole path. That is the rule the guard always meant.
RSpec.describe "Ovallsp::Diagnostics::Engine and nested RBS aliases" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  def context
    Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
  end

  def codes_for(source, mode: :standard)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    engine.analyze(document: document, semantic_context: context, mode: mode).map(&:code)
  end

  it "does not report a selector-typed argument on a known String" do
    expect(codes_for(%(value = "a.b"\nvalue.tr(".", "")\n))).not_to include("argument-type")
  end

  it "does not report the same call written literally" do
    expect(codes_for(%("a.b".tr(".", "")\n))).not_to include("argument-type")
  end

  # `delete`, `squeeze` and `count` take the same alias. Kept, but marked
  # for what it is: a re-derivation round found these three pass under
  # *both* behaviours, so they do not distinguish anything on their own.
  # They are here because the fix should generalise, not because they
  # prove it did -- the two examples above are what prove it.
  it "does not report the other String methods that take the same alias" do
    %w[delete squeeze count].each do |method|
      expect(codes_for(%("a.b".#{method}(".")\n))).not_to include("argument-type"), method
    end
  end

  # The control, and it has to be one that can fail.
  #
  # Two earlier versions could not. The first asserted `be_an(Array)` on a
  # method ending in `map`; the second passed a class where a class was
  # declared, which produces no finding either way. Both survived
  # disabling argument checking entirely -- which is the third time in
  # this release that a "watched failing" claim rested on an assertion
  # that could not, and the reason this one was verified by actually
  # removing the check rather than by reasoning about it.
  #
  # This one needs a *declared* signature, because the check only reports
  # where the expected type is stated rather than inferred -- so it uses
  # a project `sig/` the way `argument_type_spec.rb` does, and asserts the
  # report exists.
  it "still reports a wrong argument against a stated, real class" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "fixtures.rbs"), <<~RBS)
        class Widget
          def resize: (Integer size) -> void
        end
      RBS
      env = Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: root) }
      document = Ovallsp::TextDocument.new(
        uri: "file:///a.rb", text: %(Widget.new.resize("large")\n), version: 1, language_id: "ruby"
      )
      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
        local_inferencer: local_inferencer, model_registry: model_registry,
        route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: env, generation: 1
      )

      codes = engine.analyze(document: document, semantic_context: context, mode: :strict).map(&:code)

      expect(codes).to include("argument-type")
    end
  end

end
