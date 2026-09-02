# frozen_string_literal: true

# `024.238`, and `024.91`'s shape C. An `alias` whose target is declared
# by an *included module* was reported as unknown -- a false positive on
# code that runs, which is the direction section 0 ranks worst.
#
#   $ ruby -e '
#   module Escaping
#     def escape(s) = s
#   end
#   class Page
#     include Escaping
#     alias safe_escape escape
#   end
#   p [Page.new.respond_to?(:safe_escape), Page.new.safe_escape("x")]
#   '
#   # => [true, "x"]
#   # ruby 3.4.10
#
# `#resolve_alias` is asked of one ancestor at a time, so the alias
# recorded on `Page` resolved to `escape` and then looked for `Page#escape`
# -- which does not exist, because `escape` is on `Escaping`. Nothing
# looked for the *resolved* name along the rest of the chain.
#
# `alias` to a `def` in the same class body already worked, which is why
# the third example is here: it is the case that must keep working.
RSpec.describe "Ovallsp::Semantic::MethodResolver and an alias to an included module's method" do
  def findings(source)
    workspace_index = Ovallsp::WorkspaceIndex.new
    document = Ovallsp::TextDocument.new(uri: "file:///alias_probe.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack = Ovallsp::AnalysisStack.build(
      signatures: AnalysisStackHelper.shared_signatures, workspace_index: workspace_index
    )
    stack.hierarchy_index.replace_file(summary)
    context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, generation: 1)
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
  end

  def unknown_names(source)
    findings(source).select { |f| f.code == "unknown-method" }.map { |f| f.message[/`([^`]+)`/, 1] }.sort
  end

  THROUGH_MODULE = <<~RUBY
    module Escaping
      def escape(s) = s
    end

    class Page
      include Escaping
      alias safe_escape escape
    end

    class PageCaller
      def go
        Page.new.safe_escape("x")
      end

      def control
        Page.new.definitely_not_a_member
      end
    end
  RUBY

  it "does not report an alias whose target an included module declares" do
    expect(unknown_names(THROUGH_MODULE)).not_to include("safe_escape")
  end

  # **The control, in the same fixture.** Without it the example passes
  # by the check being switched off for this receiver, which is exactly
  # what the fix must not do.
  it "still reports a name nothing in the chain declares" do
    expect(unknown_names(THROUGH_MODULE)).to include("definitely_not_a_member")
  end

  it "keeps reporting nothing for an alias to a `def` in the same body" do
    source = <<~RUBY
      class Plain
        def escape(s) = s
        alias safe_escape escape
      end

      class PlainCaller
        def go
          Plain.new.safe_escape("x")
        end
      end
    RUBY

    expect(unknown_names(source)).to be_empty
  end
end
