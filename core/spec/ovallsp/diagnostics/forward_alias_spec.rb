# frozen_string_literal: true

# `alias_method :create, :new` binds `create` to whatever `new` means at
# the moment the statement runs -- not to a `def new` written five lines
# below it. ActiveSupport's `TimeZone` is exactly that shape:
#
#   class << self
#     alias_method :create, :new    # :212 -- binds Class#new
#     def new(name) ... end         # :217
#   end
#
# so `TimeZone.create(name, utc_offset, tzinfo)` really does reach
# `initialize(name, utc_offset = nil, tzinfo = nil)` and takes three
# arguments. The engine resolved the alias to the later `def new(name)`
# and reported "`create` takes 1 argument, but 3 given" twice, on
# ActiveSupport's own source. In a smaller workspace the same construct
# instead produced "has no method named `create`" -- two checks, two
# different wrong answers about one alias.
#
# Found by an independent review round bisecting real gem source.
RSpec.describe "Ovallsp::Diagnostics::Engine and an alias written before its target" do
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
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def findings(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    engine.analyze(document: document, semantic_context: context, mode: :standard).map { |f| [f.code, f.message] }
  end

  it "says nothing about a call through an alias whose target is written later" do
    document = index(<<~RUBY_SRC)
      class Zone
        def initialize(name, offset = nil, info = nil)
        end

        class << self
          alias_method :create, :new

          def new(name)
            self[name]
          end
        end
      end

      class Caller
        def go = Zone.create("a", 1, 2)
      end
    RUBY_SRC

    expect(findings(document)).to be_empty
  end

  # The control, and the reason this is a narrowing rather than a
  # retreat: an alias written *after* its target still resolves, and a
  # call that genuinely cannot bind is still reported.
  it "still resolves an alias written after its target, and still checks its arity" do
    document = index(<<~RUBY_SRC)
      class Zone
        class << self
          def build(name)
            name
          end

          alias_method :create, :build
        end
      end

      class Caller
        def go = Zone.create("a", 1, 2)
      end
    RUBY_SRC

    expect(findings(document)).to eq([["argument-count", "`create` takes 1 argument, but 3 given"]])
  end
end
