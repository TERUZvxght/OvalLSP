# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.248`. `Engine#ancestor_names` mapped an ancestor chain through
# `AncestorEntry#name` with no `#identified?` guard, so an argument whose
# class has a parent nobody could identify **raised**
# `Semantic::UnidentifiedAncestor` out of `Engine#analyze` — and the whole
# document lost every diagnostic, not merely the comparison that asked.
#
# The raise is deliberate at its own end (`024.80`: there is no way to
# *spell* the owner of an edge nobody resolved, so a reader that forgets
# fails where the suite sees it). This is the sixth reader of the chain
# and the one that forgot. Five others already guard; the backtrace ran
#
#   AncestorEntry#name -> #ancestor_names -> #compatible_nominal?
#     -> #mismatched_arguments -> #analyze
#
# and `Server#publish_diagnostics` rescues, logs, and returns *without*
# calling `publish_findings` — so the editor keeps whatever it was last
# shown for that file. A stale answer that looks live, and it depends on
# document content, so a user typing such a call freezes that file's
# diagnostics from that keystroke on.
#
# The direction is `compatible_nominal?` declining, not guessing. The
# reachable set is a lower bound: an ancestor nobody could name may well
# *be* the expected type, so a miss computed from a chain with a hole in
# it is not evidence of a mismatch.
RSpec.describe "an argument whose class has an ancestor nobody could identify" do
  # `Data.define` is the shape that reproduces and it is ordinary modern
  # Ruby. Taken from the parser rather than assumed — every non-constant
  # superclass expression tried (`Struct.new`, a bare method call,
  # `Kernel.const_get`) produces the same unidentified `:superclass`
  # entry, and a plain unknown constant does not.
  UNIDENTIFIED_ANCESTOR_SIG = <<~RBS
    class Registry
      def label: (String text) -> String
    end
  RBS

  around do |example|
    Dir.mktmpdir("unidentified-ancestor-arg-") do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "app.rbs"), UNIDENTIFIED_ANCESTOR_SIG)
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end

  # `:safe` is the mode the shipped extension gets — nothing under
  # `vscode/` sets `initializationOptions.diagnosticsMode` — and the
  # raise happens there, which is why this entry is user-visible.
  def findings(body)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: body, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)

    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: model_registry, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new
                                .analyze(document: document, semantic_context: context, mode: :safe)
                                .map(&:message)
  end

  # The unnameable parent and, further down the same document, a call
  # nothing declares. The second is what makes the loss visible: it is
  # reported when the argument call is absent, so if it goes missing here
  # the file lost diagnostics it was already producing.
  UNIDENTIFIED_ANCESTOR_SOURCE = <<~SRC
    class Widget < Data.define(:size)
    end

    class Registry
      def use
        label(Widget.new(1))
      end

      def planted_bad
        definitely_absent
      end
    end
  SRC

  it "keeps answering about the rest of the document" do
    expect(findings(UNIDENTIFIED_ANCESTOR_SOURCE))
      .to include(a_string_including("definitely_absent"))
  end

  it "declines about the argument rather than reporting it against an incomplete chain" do
    expect(findings(UNIDENTIFIED_ANCESTOR_SOURCE))
      .not_to include(a_string_including("expects String here"))
  end

  # The controls. Without these both examples above would pass on an
  # engine that had simply stopped comparing argument types — which is
  # the failure mode a decline is one step away from.
  it "still reports a mismatch when the argument's chain has no hole in it" do
    source = <<~SRC
      class Gadget
      end

      class Registry
        def use
          label(Gadget.new)
        end
      end
    SRC

    expect(findings(source)).to contain_exactly(a_string_including("expects String here, but Gadget is given"))
  end

  it "still says nothing where the argument matches" do
    source = <<~SRC
      class Registry
        def use
          label("ok")
        end
      end
    SRC

    expect(findings(source)).to be_empty
  end
end
