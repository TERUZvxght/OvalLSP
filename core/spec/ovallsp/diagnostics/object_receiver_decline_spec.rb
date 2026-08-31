# frozen_string_literal: true

require "tmpdir"

# `024.230`. **`Object`'s member set is whatever the process has loaded**,
# so no static analysis can enumerate it, and the undefined-method check
# never reports about one.
#
# It became reachable when a bare call at the top level was given the
# `Object` receiver Ruby gives it. Measured over 997 files of
# activesupport, activerecord, actionpack and railties, judging that
# receiver closed produced **25 new reports and removed none**: nine
# `gem` (RubyGems puts `Kernel#gem` there), four top-level `include`,
# seven JRuby-only names. Every one false.
#
# With the decline: **0 introduced, and 2 pre-existing false reports
# removed** — activesupport's own `respond_to?(:empty?)` and
# `respond_to?(:to_hash)` duck-typing in `core_ext`.
#
# `024.239` is the same fact arriving from the other side: three names
# Ruby gives every object had to be hard-coded because the signature set
# omits them and the check was reporting them on the user's own class.
# The list can only ever be partial, which is the argument for declining
# rather than for extending it.
#
# **What it costs** is a genuine typo written at the top level of a file,
# which is not reported. `024.129` records the same decline and the same
# cost for the other core classes.
RSpec.describe "an undefined-method report about an Object receiver" do
  def reports(files, subject)
    Dir.mktmpdir("object-receiver-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)
      parser = Ovallsp::ParserService.new
      documents = {}
      files.each do |name, source|
        document = Ovallsp::TextDocument.new(uri: "file://#{root}/#{name}", text: source, version: 1,
                                             language_id: "ruby")
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
      Ovallsp::Diagnostics::Engine.new
                                  .analyze(document: documents.fetch(subject), semantic_context: context,
                                           mode: :standard)
                                  .select { |finding| finding.code == "unknown-method" }.map(&:message)
    end
  end

  # **The fixture has to reopen `Object`**, and that is not decoration.
  # The check only judges a receiver closed when the workspace declares
  # it with a chain that reaches the root; without a `class Object` in
  # the workspace nothing is reported here whatever the rule says, and
  # four examples written without one passed with the decline removed —
  # proving nothing. Every Rails application has one: activesupport's
  # `core_ext/object/blank.rb` is exactly this.
  let(:reopened_object) { "class Object\n  def blank?\n    nil\n  end\nend\n" }

  # `Kernel#gem` is real and the bundled signatures do not declare it.
  # Nine of the corpus's 25 were this exact call.
  it "says nothing about a name Ruby gives every object that the signatures omit" do
    files = { "core_ext.rb" => reopened_object,
              "top.rb" => "gem \"redis\", \">= 4.0.1\"\n" }

    expect(reports(files, "top.rb")).to be_empty
  end

  # `include Foo` written at the top level is `main`'s, and it is real.
  it "says nothing about a top-level `include`" do
    files = { "core_ext.rb" => reopened_object,
              "m.rb" => "module Extra\nend\n", "top.rb" => "include Extra\n" }

    expect(reports(files, "top.rb")).to be_empty
  end

  # **The control.** Declining about `Object` must not decline about a
  # workspace class, which is the whole check.
  it "still reports a typo on a class the workspace declares" do
    files = { "w.rb" => "class Widget\n  def build\n  end\nend\n",
              "top.rb" => "Widget.new.definitely_not_a_member\n" }

    expect(reports(files, "top.rb")).to eq(["Widget has no method named `definitely_not_a_member`"])
  end

  # And the second control: the cost, asserted rather than described. A
  # typo written at the top level is silent, and that is the trade.
  it "also says nothing about a genuine typo at the top level, which is what it costs" do
    files = { "core_ext.rb" => reopened_object,
              "helper.rb" => "def helper(a)\n  a\nend\n", "top.rb" => "helpr(1)\n" }

    expect(reports(files, "top.rb")).to be_empty
  end
end
