# frozen_string_literal: true

# `Rack::Reloader` writes `extend backend` inside its constructor, where
# `backend` is a parameter defaulting to `Stat`. `ParserService` dropped
# that call entirely -- `raw_constant_name` returns nil for anything but
# a written constant, and the loop `next`ed -- so "this class extends a
# module I cannot name" and "this class extends nothing" were the same
# fact downstream. The chain then looked complete and `#reload!`'s call
# to `rotation`, which `Stat` supplies, was reported missing. One of the
# ten findings the gem corpus still produced after 0.2.6's other changes.
#
# The answer is the one 024.76 already uses for macros: a surface whose
# members were decided at runtime cannot be enumerated, so absence cannot
# be asserted about it.
RSpec.describe "Ovallsp::Diagnostics::Engine and an ancestor chosen at runtime" do
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

  it "says nothing about a class that extends a module named at runtime" do
    document = index(<<~RUBY_SRC)
      module Stat
        def rotation; end
      end

      class Reloader
        def initialize(backend = Stat)
          extend backend
        end

        def reload!
          rotation
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end

  # The control: the same class without the dynamic `extend` still
  # answers, so the example above distinguishes two behaviours rather
  # than passing on a fixture where neither says anything.
  it "still reports the same call when nothing is extended" do
    document = index(<<~RUBY_SRC)
      module Stat
        def rotation; end
      end

      class Reloader
        def initialize(backend = Stat)
          @backend = backend
        end

        def reload!
          rotation
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["rotation"])
  end

  # A written constant is not this shape: the ancestor is known, so the
  # chain is complete and the check must keep working through it.
  it "still reports a genuinely missing method when the module is written out" do
    document = index(<<~RUBY_SRC)
      module Stat
        def rotation; end
      end

      class Reloader
        include Stat

        def reload!
          rotation
          definitely_not_defined_zzz
        end
      end
    RUBY_SRC

    expect(unknown_methods(document)).to eq(["definitely_not_defined_zzz"])
  end

  # A dynamic `extend` in a *class body* changes what the class object
  # responds to, not what its instances do. Keeping the two apart is the
  # same decision the macro rule makes, and for the same reason: opening
  # both surfaces silences reports the other half is still right about.
  it "opens the class-level surface when the class body extends dynamically" do
    document = index(<<~RUBY_SRC)
      module Stat
        def rotation; end
      end

      class Reloader
        extend Object.const_get(:Stat)
      end

      class Caller
        def go = Reloader.rotation
      end
    RUBY_SRC

    expect(unknown_methods(document)).to be_empty
  end
end
