# frozen_string_literal: true

# `Order.recent.first.no_such_method` was reported by nothing, while
# `Order.find(id).no_such_method` was reported normally. The cause is one
# line: `unknown_method_findings` proceeds only for a `Types::Nominal`
# receiver, and `Relation[T]#first` infers `T | nil` -- a Union -- so the
# check exits before asking anything. Completion at the same position
# already knows the method is absent.
#
# `Model.scope.first` is an everyday Rails idiom, and undefined-call
# detection is half of what section 0 says 1.0.0 is, so this is the
# headline capability missing on a headline path (`024.77`).
#
# The rule for a negative diagnostic over a Union, from the external
# review: report absence only when **every** non-nil branch establishes
# it. If any branch has the method, or any branch is not closed, the
# answer is silence -- a Union is more uncertain than a Nominal, not
# less, and this check's policy is that a false report is worse than a
# missed one.
RSpec.describe "Ovallsp::Diagnostics::Engine over a Union receiver" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def codes_for(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    engine.analyze(document: document, semantic_context: context, mode: :standard).map(&:code)
  end

  # A plain nilable receiver, built without Rails: a ternary yields
  # `Widget | nil`, the same shape `Relation[Widget]#first` produces, and
  # needs no model registry to construct.
  #
  # Verified before being relied on. The first version of this fixture
  # routed the value through a method call and inferred `Unknown`, not a
  # Union -- so it would have failed for a reason that had nothing to do
  # with the change, and passing it would have proved nothing either.
  let(:nilable_source) do
    <<~RUBY_SRC
      class Widget
        def real_thing; end
      end

      flag = true
      value = flag ? Widget.new : nil
      value.definitely_not_a_method_zzz
    RUBY_SRC
  end

  it "infers the fixture's receiver as a Union, which the rest of this file assumes" do
    document = index(nilable_source)
    inferred = local_inferencer.infer_at(document, { line: 6, character: 0 })

    expect(inferred).to be_a(Ovallsp::Types::Union)
    expect(inferred.to_s).to include("nil")
  end

  it "reports a method absent from every non-nil branch" do
    expect(codes_for(index(nilable_source))).to include("unknown-method")
  end

  # The control that keeps the fix honest: a method the branch *has* must
  # stay silent, or "report everything on a Union" would satisfy the
  # example above.
  it "stays silent about a method the branch does have" do
    source = nilable_source.sub("definitely_not_a_method_zzz", "real_thing")

    expect(codes_for(index(source))).not_to include("unknown-method")
  end

  # A Union with a branch the engine cannot close is *more* uncertain than
  # a Nominal, so it must not become reportable by being split up.
  it "stays silent when a branch is not closed" do
    source = <<~RUBY_SRC
      class Widget
        def real_thing; end
      end

      def maybe(flag)
        flag ? Widget.new : Unknowable.new
      end

      value = maybe(true)
      value.definitely_not_a_method_zzz
    RUBY_SRC

    expect(codes_for(index(source))).not_to include("unknown-method")
  end
end
