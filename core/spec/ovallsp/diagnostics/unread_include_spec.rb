# frozen_string_literal: true

require "tmpdir"

# `024.35`. A class that `include`s a module the workspace has not read
# has an unbounded class-level surface: whatever that module's
# `class_methods do` block installs is real and invisible from here. The
# entry recorded the check judging such a class *closed* and reporting
# its macros.
#
# It does not reproduce, and this file is the control that says so —
# 0.2.15's assessment reached the same conclusion and was refused,
# because its fixture could not tell "the defect is gone" from "nothing
# of this kind is reported at all". That refusal was right: driven
# again, a receiverless macro in a class body is reported in *no*
# arrangement, so a fixture built from one proves nothing either way.
#
# An explicit receiver is reported, so it is what these examples use.
#
# **The cost the entry predicted is real and is asserted here too.**
# "It will silence genuine class-level reports on every class that
# includes anything unread" — it does, and the last example pins that
# rather than leaving it to be rediscovered as a regression.
RSpec.describe "a class-level call on a class that includes an unread module" do
  def reports(files, subject)
    Dir.mktmpdir("unread-include-") do |root|
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

  it "says nothing, because the module could add it" do
    source = "class Configish\n  include SomeGem::Model\nend\nConfigish.validate(:ensure_ok)\n"

    expect(reports({ "c.rb" => source }, "c.rb")).to be_empty
  end

  # **The control that 0.2.15's assessment lacked.** Without an include
  # the same call is reported, so the silence above is this rule and not
  # the check being asleep.
  it "still reports the same call on a class that includes nothing" do
    source = "class Plain\nend\nPlain.validate(:ensure_ok)\n"

    expect(reports({ "p.rb" => source }, "p.rb")).to eq(["Plain has no method named `validate`"])
  end

  # And the second: including a module the workspace *can* read does not
  # buy the same silence, so the rule turns on the module being unread
  # rather than on there being an include at all.
  it "still reports it on a class that includes a module it can read" do
    files = { "m.rb" => "module Readable\nend\n",
              "k.rb" => "class Known\n  include Readable\nend\nKnown.validate(:ensure_ok)\n" }

    expect(reports(files, "k.rb")).to eq(["Known has no method named `validate`"])
  end

  # **What the silence costs**, stated as an assertion rather than left
  # in prose. A genuine typo on such a class is not reported either —
  # the entry predicted this in as many words, and it is the trade the
  # rule makes, not a second defect.
  it "also says nothing about a genuine typo there, which is what the rule costs" do
    source = "class Configish\n  include SomeGem::Model\nend\nConfigish.definitely_not_a_member\n"

    expect(reports({ "c.rb" => source }, "c.rb")).to be_empty
  end
end
