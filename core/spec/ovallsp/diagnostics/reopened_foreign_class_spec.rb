# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# `024.13`. A workspace that reopens a class it did not originate makes
# that class look closed, and every method the *original* declares
# elsewhere is then reported as missing.
#
#     # lib/core_ext.rb — an ordinary Rails-shaped monkey patch
#     class String
#       def to_sentence_ish = "x"
#     end
#
#     s = "x"
#     s.squish     # reported: String has no method named `squish`
#     s.blank?     # reported
#     s.upcase     # not reported — RBS is loaded and resolving
#
# `upcase` staying silent is the control that matters: the signature
# environment is present and working. What changes is that the workspace
# now *declares* `String`, and `#accounted_for?` reads "the workspace
# declares this ancestor" as "the workspace can enumerate it".
#
# It cannot. `activesupport` declares `squish` and `blank?` in a gem this
# engine does not index, and the interpreter never has this problem
# because at the moment of the call every file is loaded. This is the
# enumeration question, not a modelling error.
RSpec.describe "a workspace that reopens a class it did not originate" do
  def findings(files)
    Dir.mktmpdir("reopened-foreign-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)

      documents = files.map do |rel, text|
        document = Ovallsp::TextDocument.new(uri: "file://#{root}/#{rel}", text: text, version: 1,
                                             language_id: "ruby")
        summary = Ovallsp::ParserService.new.summarize(document)
        workspace_index.replace_file(summary)
        stack.hierarchy_index.replace_file(summary)
        document
      end

      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: Ovallsp::Models::ModelRegistry.new,
        route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
      )
      Ovallsp::Diagnostics::Engine.new
                                  .analyze(document: documents.last, semantic_context: context, mode: :standard)
                                  .select { |f| f.code == "unknown-method" }.map(&:message)
    end
  end

  REOPENING = "class String\n  def to_sentence_ish\n    \"x\"\n  end\nend\n"
  USES = "s = \"x\"\ns.squish\ns.blank?\ns.upcase\n"

  # **Pending, deliberately.** This is the defect, reproduced with a
  # control this entry previously had none of. The fix is not in 0.2.16
  # because the only one found is a proxy that costs more than it buys.
  #
  # Measured: declining whenever the workspace declares a class the
  # signature environment already knew removes 11 false reports over a
  # real gem corpus and introduces none — and then takes
  #
  #     class Object
  #       def self.foo; end   # an innocuous reopening
  #     end
  #     Widget.nope           # a typo
  #
  # from reported to silent, in four examples across three files. One of
  # them says why it exists: "a name `Object` does *not* declare is still
  # reported, so the chain gained a link rather than losing its edge."
  #
  # `squish` and `blank?` are activesupport's, and this engine does not
  # index what gems define. That was read as `024.R7`'s, scheduled for
  # 0.3.0 — and `024.R7` shipped there without answering it. Measured
  # against the release's own Rails fixture, the index held 2,078 gem
  # classes and no core ones (`String instanceMethods=0`), because
  # `Agent#gem_index_result` reports a module only where
  # `const_source_location` puts it under a gem path, and a core class is
  # not there. `024.290` records it.
  #
  # Reopening is a proxy for "this project probably loads gems
  # that patch core classes", and a proxy that cannot tell activesupport
  # from `def self.foo` is not one to ship. See `024.13`, open at 0.4.0.
  it "says nothing about the original's methods it cannot enumerate" do
    pending("the only fix found silences real typos; see 024.13")
    expect(findings([["core_ext.rb", REOPENING], ["app.rb", USES]])).to be_empty
  end

  # The controls, and each is load-bearing.

  # Without the reopening there is nothing to report either — so this
  # proves the reports above come from the reopening and not from the
  # signature environment being absent.
  it "says nothing when the workspace does not reopen it" do
    expect(findings([["core_ext.rb", "# nothing here\n"], ["app.rb", USES]])).to be_empty
  end

  # A class the workspace really does originate stays fully enumerable:
  # this is the case the check exists for, and it must keep firing.
  it "still reports a missing method on a class the workspace owns" do
    own = "class Widget\n  def build\n  end\nend\n"
    call = "Widget.new.definitely_not_here\n"

    expect(findings([["widget.rb", own], ["app.rb", call]]))
      .to contain_exactly(a_string_including("definitely_not_here"))
  end

  # And the reopened class's *own* new method is still known, so the
  # decline is about what the workspace cannot see, not about the file
  # it just read.
  it "still resolves the method the reopening itself declares" do
    call = "s = \"x\"\ns.to_sentence_ish\n"

    expect(findings([["core_ext.rb", REOPENING], ["app.rb", call]])).to be_empty
  end
end
