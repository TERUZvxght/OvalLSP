# frozen_string_literal: true

RSpec.describe Rslsp::Diagnostics::Engine do
  subject(:engine) { described_class.new }

  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Rslsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) { Rslsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index) }
  let(:model_registry) { Rslsp::Models::ModelRegistry.new }
  let(:local_inferencer) do
    Rslsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver,
      method_analyzer: Rslsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver, summary_store: Rslsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:route_registry) { Rslsp::Routes::RouteRegistry.new }
  let(:signatures) { Rslsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  def context(**overrides)
    Rslsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry, route_registry: route_registry,
      signatures: signatures, generation: 1, **overrides
    )
  end

  def index(text, uri: "file:///a.rb")
    document = Rslsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Rslsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  it "raises for an unrecognized mode rather than silently degrading" do
    document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "1\n", version: 1, language_id: "ruby")

    expect { engine.analyze(document: document, semantic_context: context, mode: :bogus) }.to raise_error(ArgumentError)
  end

  describe "syntax findings" do
    it "surfaces a Prism syntax error as a high-confidence finding" do
      document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: "def foo(\nend\n", version: 1, language_id: "ruby")

      findings = engine.analyze(document: document, semantic_context: context)

      expect(findings.map(&:code)).to include("syntax-error")
      expect(findings.find { |f| f.code == "syntax-error" }.confidence).to eq(:high)
    end
  end

  describe "unknown-method (Safe mode)" do
    it "flags a call with no such method on a closed, single-Nominal receiver" do
      document = index("class Widget\n  def show\n    totally_bogus_method\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)
      finding = findings.find { |f| f.code == "unknown-method" }

      expect(finding).not_to be_nil
      expect(finding.confidence).to eq(:high)
      expect(finding.range[:start][:line]).to eq(2)
    end

    it "does not flag a real Kernel/Object builtin call (resolved through RBS)" do
      document = index("class Widget\n  def show\n    puts \"hi\"\n    freeze\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call on an Unknown-typed receiver (a method parameter)" do
      document = index("class Widget\n  def show(arg)\n    arg.whatever_unknown\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call through a Union receiver (ambiguous, not a confirmed error)" do
      document = index(<<~RUBY)
        class User
          def name
          end
        end

        class Admin
          def name
          end
        end

        class Owner
          def pick(flag)
            user = flag ? User.new : Admin.new
            user.something_neither_has
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call on a receiver whose ancestor chain includes an unresolved external constant" do
      document = index("class Widget < SomeExternalGemBaseClass\n  def show\n    something_the_gem_defines\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag a call inside an open, namespaced class just because an unrelated top-level class shares its simple name" do
      # Found by the Task 014-018 independent review's live repro: a
      # closed top-level `Bar` and an open `Api::Bar` (whose real
      # ancestor is an unresolved external gem class) share the simple
      # name "Bar" -- resolving the receiver by simple name alone
      # (the previous behavior) picked the wrong, closed `Bar` and
      # wrongly flagged a call that's only unresolvable because it
      # legitimately comes from the gem.
      document = index(<<~RUBY)
        class Bar
          def known_method
          end
        end

        module Api
          class Bar < SomeExternalGemBaseClass
            def show
              mystery_call_from_the_gem
            end
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag an explicit same-named constant call inside a nested namespace as unknown, when it lexically resolves to the enclosing class itself" do
      # Found by the Task 014-018 independent review's follow-up pass:
      # the earlier fix only handled the *implicit*-self shape of this
      # false positive (`ReceiverResolution`'s owner-only fast path) --
      # an *explicit* bare receiver (`Bar.foo`, not just `foo`) written
      # inside `Api::Bar`'s own body needs the same real-Ruby lexical
      # nesting behavior: a bare `Bar` referenced from inside
      # `module Api; class Bar; ...; end; end` resolves to `Api::Bar`
      # itself (via `Api`'s own constant table), never an unrelated
      # top-level `Bar`, even when both exist -- verified live with a
      # real `ruby -e` probe before writing this test.
      document = index(<<~RUBY)
        class Bar
          def known_method
          end
        end

        module Api
          class Bar < SomeExternalGemBaseClass
            def self.show
              Bar.mystery_call_from_the_gem
            end
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "does not flag any call at all when Signatures::Environment isn't available" do
      document = index("class Widget\n  def show\n    puts \"hi\"\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context(signatures: nil), mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end

    it "suppresses unknown-method entirely for a class that declares method_missing" do
      document = index(<<~RUBY)
        class Widget
          def method_missing(name, *)
            super
          end

          def show
            anything_dynamic
          end
        end
      RUBY

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-method")
    end
  end

  describe "unresolved-constant" do
    it "does not run in :safe mode" do
      document = index("TotallyUnknownConstant.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end

    it "flags a constant that resolves neither in the workspace nor via RBS in :standard mode" do
      document = index("TotallyUnknownConstant.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).to include("unresolved-constant")
    end

    it "does not flag a workspace-declared constant" do
      document = index("class Widget\nend\n\nWidget.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end

    it "does not flag an RBS-known stdlib constant" do
      document = index("String.new\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :standard)

      expect(findings.map(&:code)).not_to include("unresolved-constant")
    end
  end

  describe "unknown-route-helper" do
    it "flags a bare _path/_url call that matches no known route" do
      document = index("class WidgetsController\n  def show\n    nope_this_route_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)
      finding = findings.find { |f| f.code == "unknown-route-helper" }

      expect(finding).not_to be_nil
      expect(finding.confidence).to eq(:high)
    end

    it "does not flag a call resolving to a real route helper" do
      route_registry.replace([
                                { name: "widget", verb: "GET", pathTemplate: "/widgets/:id", requiredParts: ["id"],
                                  optionalParts: [], defaults: { controller: "widgets", action: "show" },
                                  sourceLocation: nil, routeSet: "main_app" }
                              ])
      document = index("class WidgetsController\n  def show\n    widget_path(1)\n  end\nend\n")

      findings = engine.analyze(document: document, semantic_context: context, mode: :safe)

      expect(findings.map(&:code)).not_to include("unknown-route-helper")
    end
  end

  it "truncates the result set when budget: is given" do
    document = index("TotallyUnknownConstant.new\nAnotherOne.new\nYetAnother.new\n")

    findings = engine.analyze(document: document, semantic_context: context, mode: :standard, budget: 1)

    expect(findings.size).to eq(1)
  end
end
