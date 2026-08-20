# frozen_string_literal: true

RSpec.describe "Ovallsp::Diagnostics::Engine and a receiver written with a leading ::" do
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

  def index_second(text) = index(text, uri: "file:///b.rb")

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    engine.analyze(document: document, semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "unknown-method" }
          .map { |finding| finding.message[/named `(.+)`/, 1] }
  end
  # `::JSON` is rooted, and Ruby gives a rooted name exactly one referent.
  # `ReceiverResolution` strips the `::` before anything downstream sees
  # it, so `HierarchyIndex` re-resolved the bare `JSON` and found i18n's
  # own `I18n::Backend::KeyValue::JSON` -- whose singleton chain is closed
  # -- and the check reported `::JSON.parse` missing over ordinary i18n
  # source. Two of the 18 remaining false reports over the gem corpus, on
  # a shape (`::JSON`, `::File`, `::Rails`) written every day.
  #
  # Declined here rather than in resolution: 024.47 moved a rule of this
  # kind into resolution and broke every bare name written inside its own
  # namespace, and was rolled back. Completion and go-to-definition keep
  # their plausible answer; only the assertion is withheld.
  it "does not assert about a rooted receiver the workspace answers for from another namespace" do
    index(<<~RUBY_SRC)
      module Outer
        module Inner
          class Jsonish
            def self.mine; end
          end
        end
      end
    RUBY_SRC
    document = index_second(<<~RUBY_SRC)
      module Outer
        module Inner
          class Reader
            def read(text)
              ::Jsonish.parse(text)
            end
          end
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  # The control: written bare, the same call is the ordinary ambiguous
  # reference 024.15 made deterministic, and the check still answers.
  it "still asserts about the same receiver written without the ::" do
    index(<<~RUBY_SRC)
      module Outer
        module Inner
          class Jsonish
            def self.mine; end
          end
        end
      end
    RUBY_SRC
    document = index_second(<<~RUBY_SRC)
      module Outer
        module Inner
          class Reader
            def read(text)
              Jsonish.parse(text)
            end
          end
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["parse"])
  end
end
