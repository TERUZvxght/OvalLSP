# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.19`. The argument-type check judged a call against a class the
# receiver is not — and finding the fixture that shows it took three
# tries, two of which said "does not reproduce".
#
# **The two that were wrong, and why.** A rooted
# `::Vendor::Gadgets::Widget` is silent: 0.2.11 stopped a rooted path
# reaching the index's last-segment fallback. A bare `Widget` written
# inside `Vendor::Gadgets` where the workspace *does* declare
# `Vendor::Gadgets::Widget` is silent too: the nesting rule finds it and
# no fallback runs. Both were driven, both came back empty, and either
# alone reads as "fixed". `024.35` records the same trap and the same
# refusal to close on it.
#
# The shape that reproduces is the one the published limitation names: a
# **bare** name in a namespace whose own class the workspace *cannot*
# see.
#
# **And the engine is right about the code it can see.** With no
# `Vendor::Gadgets::Widget` anywhere, Ruby resolves a bare `Widget`
# written there to the top-level one:
#
#   $ ruby -e '
#   class Widget; def make(n) = n; end
#   module Vendor; module Gadgets
#     class Caller; def go = Widget.new.make("s"); end
#   end; end
#   p Vendor::Gadgets::Caller.new.go
#   '
#   # => "s"
#   # ruby 3.4.10
#
# So this is not a rule the check gets wrong. It is the check asserting
# on a workspace that cannot see the gem where the real
# `Vendor::Gadgets::Widget` lives — which was read as `024.R7`'s, and why
# the entry was moved there rather than being fixed here.
#
# **That reading did not hold.** `024.R7` shipped in 0.3.0 and this did
# not follow it — the fixture below has no gem in it at all — while
# `024.19` was retargeted past 0.3.0 twice, to 0.3.2 in 0.3.0's closing
# sweep and then to 0.4.0, for reasons of its own. Its residual is
# constant resolution respecting `Module.nesting` for a bare name, which
# is that entry's own Direction.
RSpec.describe "an argument-type report about a bare name in a namespace" do
  subject(:engine) { Ovallsp::Diagnostics::Engine.new }

  around do |example|
    Dir.mktmpdir("bare-argtype-") do |root|
      FileUtils.mkdir_p(File.join(root, "sig"))
      File.write(File.join(root, "sig", "app.rbs"), <<~RBS)
        class Widget
          def make: (Integer n) -> void
        end
      RBS
      @workspace_root = root
      example.run
    end
  end

  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:signatures) do
    Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @workspace_root) }
  end
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, signatures: signatures) }

  TOP_LEVEL_WIDGET = "class Widget\n  def make(n)\n  end\nend\n"
  NESTED_WIDGET = "module Vendor\n  module Gadgets\n    class Widget\n      def make(s)\n      end\n" \
                  "    end\n  end\nend\n"
  BARE_CALL = "module Vendor\n  module Gadgets\n    class Caller\n      def go\n" \
              "        Widget.new.make(\"s\")\n      end\n    end\n  end\nend\n"

  def findings(files, subject)
    parser = Ovallsp::ParserService.new
    documents = {}
    files.each do |name, source|
      document = Ovallsp::TextDocument.new(uri: "file:///#{name}", text: source, version: 1, language_id: "ruby")
      documents[name] = document
      summary = parser.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)
    end
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
      method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
      model_registry: Ovallsp::Models::ModelRegistry.new,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    engine.analyze(document: documents.fetch(subject), semantic_context: context, mode: :standard)
          .select { |finding| finding.code == "argument-type" }.map(&:message)
  end

  # **The defect, reproduced.** Pending deliberately: the engine's answer
  # is correct for the workspace it can see, and making it decline needs
  # constant resolution to respect `Module.nesting` for a bare name.
  # `024.19`, open at 0.4.0. The reason recorded here was `024.R7`, which
  # shipped in 0.3.0 and did not answer this.
  it "does not judge it against a same-named class from another namespace" do
    pending("correct for the workspace it can see; needs Module.nesting respected for a bare name — 024.19")

    expect(findings({ "w.rb" => TOP_LEVEL_WIDGET, "s.rb" => BARE_CALL }, "s.rb")).to be_empty
  end

  # The first fixture that said "does not reproduce": with the nested
  # class visible, Ruby's nesting rule finds it and no fallback runs.
  it "is silent when the workspace can see the namespace's own class" do
    files = { "w.rb" => TOP_LEVEL_WIDGET, "n.rb" => NESTED_WIDGET, "s.rb" => BARE_CALL }

    expect(findings(files, "s.rb")).to be_empty
  end

  # The second: a rooted path has one possible referent and 0.2.11
  # stopped it reaching the fallback at all.
  it "is silent for a rooted path, which 0.2.11 fixed" do
    files = { "w.rb" => TOP_LEVEL_WIDGET,
              "s.rb" => "::Vendor::Gadgets::Widget.new.make(\"s\")\n" }

    expect(findings(files, "s.rb")).to be_empty
  end

  # **The control that makes the three above mean anything.** A real
  # mismatch on the class that really is declared must still be reported,
  # or "silent" proves only that the check is asleep.
  it "still reports a real mismatch on the class the signature declares" do
    files = { "w.rb" => TOP_LEVEL_WIDGET, "s.rb" => "Widget.new.make(\"s\")\n" }

    expect(findings(files, "s.rb")).to eq(["`make` expects Integer here, but String is given"])
  end
end
