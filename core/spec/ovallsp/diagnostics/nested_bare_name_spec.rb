# frozen_string_literal: true

# `024.103`. Two classes of your own sharing a short name in different
# namespaces, and a bare reference to one of them *from inside its own
# namespace* answered with the other. Both directions inverted: the call
# that works is reported, and the call that raises is silent.
#
# The layout is ordinary -- `Billing::Comment` beside an ActiveRecord
# `Comment` is the Rails form of it. Ruby's rule is `Module.nesting`,
# innermost first, and nothing consulted it:
#
#   $ ruby -e '
#   class Config; def top_only; end; end
#   module App
#     class Config; def app_only; end; end
#     class Runner; def go = Config.new.app_only; end
#   end
#   p App::Runner.new.go            # => nil, and it does not raise
#   p(begin; App::Runner.new.instance_eval { Config.new.top_only }
#     rescue NoMethodError => e; e.class; end)   # => NoMethodError
#   '
#   # ruby 3.4.10
RSpec.describe "Ovallsp::Diagnostics::Engine and a bare class name inside a namespace" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:method_resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:local_inferencer) do
    Ovallsp::LocalInferencer.new(
      model_registry: model_registry, method_resolver: method_resolver, workspace_index: workspace_index,
      hierarchy_index: hierarchy_index,
      method_analyzer: Ovallsp::Semantic::MethodAnalyzer.new(
        workspace_index: workspace_index, method_resolver: method_resolver,
        summary_store: Ovallsp::Semantic::MethodSummaryStore.new
      )
    )
  end
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri:)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

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

  before do
    index("class Config\n  def top_only; end\nend\n", uri: "file:///config.rb")
    index("module App\n  class Config\n    def app_only; end\n  end\nend\n", uri: "file:///app/config.rb")
  end

  it "says nothing about a call that the nesting makes correct" do
    document = index("module App\n  class Runner\n    def go\n      Config.new.app_only\n    end\n  end\nend\n",
                     uri: "file:///app/runner.rb")

    expect(unknown_methods(document)).to be_empty
  end

  # The other direction, and the one that makes this example distinguish
  # rather than merely pass: `top_only` is the top-level `Config`'s
  # method, unreachable from inside `App` where `App::Config` shadows it.
  # An implementation that resolved bare names to the top-level class
  # would pass the example above and fail this one.
  it "reports the call the nesting makes wrong" do
    document = index("module App\n  class Runner\n    def go\n      Config.new.top_only\n    end\n  end\nend\n",
                     uri: "file:///app/runner.rb")

    expect(unknown_methods(document)).to eq(["top_only"])
  end

  # **Ruby's second step**, which `024.103` did not implement: nesting
  # first, *then the ancestors of the innermost cref*, then Object.
  #
  # The namespace here is `Other`, not `App`: this file's `before` already
  # declares `App::Config`, and Ruby's *first* step would find it. Asked
  # with the fixture these examples actually build --
  #
  #   $ ruby -e '
  #   class Config; def top_only; end; end
  #   module App; class Config; def app_only; end; end; end
  #   class Zbase; class Config; def zbase_only; end; end; end
  #   module App;   class Runner < Zbase; def which = Config; end; end
  #   module Other; class Runner < Zbase; def which = Config; end; end
  #   p App::Runner.new.which     # => App::Config
  #   p Other::Runner.new.which   # => Zbase::Config
  #   '
  #   # ruby 3.4.10
  #
  # -- which is the difference between step 1 and step 2, and the reason
  # the first draft of these examples was wrong about what Ruby answers.
  describe "a class name the enclosing class inherits" do
    before do
      index("class Zbase\n  class Config\n    def zbase_only; end\n  end\nend\n", uri: "file:///zbase.rb")
    end

    it "says nothing about the call the superclass's namespace makes correct" do
      document = index("module Other\n  class Runner < Zbase\n    def go\n      Config.new.zbase_only\n" \
                       "    end\n  end\nend\n", uri: "file:///other/runner.rb")

      expect(unknown_methods(document)).to be_empty
    end

    # The other direction, which is what makes the pair distinguish: the
    # top-level `Config`'s method is unreachable from inside `Runner`,
    # because `Zbase::Config` shadows it.
    it "reports the call that same namespace makes wrong" do
      document = index("module Other\n  class Runner < Zbase\n    def go\n      Config.new.top_only\n" \
                       "    end\n  end\nend\n", uri: "file:///other/runner.rb")

      expect(unknown_methods(document)).to eq(["top_only"])
    end

    # And the control: with no such class in the superclass's namespace,
    # the top-level one is still what a bare name means.
    it "falls through to the top-level class when the superclass declares none" do
      document = index("module Other\n  class Plain\n    def go\n      Config.new.top_only\n" \
                       "    end\n  end\nend\n", uri: "file:///other/plain.rb")

      expect(unknown_methods(document)).to be_empty
    end
  end

  # No top-level `Config` at all: the winner must still be the nesting's,
  # not whichever was indexed first or sorts earliest. `024.103` measured
  # `Alpha::Config` winning inside `module Beta`.
  it "does not answer with an unrelated namespace's class when neither is top-level" do
    workspace_index.replace_file(
      Ovallsp::ParserService.new.summarize(
        Ovallsp::TextDocument.new(uri: "file:///alpha.rb", version: 1, language_id: "ruby",
                                   text: "module Alpha\n  class Config\n    def alpha_only; end\n  end\nend\n")
      )
    )
    index("module Beta\n  class Config\n    def beta_only; end\n  end\nend\n", uri: "file:///beta.rb")
    document = index("module Beta\n  class Runner\n    def go\n      Config.new.beta_only\n    end\n  end\nend\n",
                     uri: "file:///beta/runner.rb")

    expect(unknown_methods(document)).to be_empty
  end
end
