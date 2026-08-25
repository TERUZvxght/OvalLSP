# frozen_string_literal: true

require "tmpdir"

# `024.85` gave `self` a type, which is what makes `self.` complete. The
# undefined-method check then started asserting about it, and asserting about
# `self` is a different question from knowing what it is.
#
# **A type inferred from an assignment names the actual class. A type inferred
# from the lexical class body names an upper bound.** Inside
# `class Numeric; def kilobytes; self * KILOBYTE; end; end`, `self` at run time
# is whatever subclass instance received the call — never a bare `Numeric`.
#
# Taken from Ruby rather than reasoned about:
#
#   $ ruby -e '
#   p [Numeric.method_defined?(:*), Integer.method_defined?(:*)]
#   p 2.kilobytes rescue p $!.class
#   '
#   # => [false, true]
#   # => NoMethodError
#   # ruby 3.4.10
#
# `*` is on `Integer` and `Float`, not on `Numeric` — so a check reading
# `Instance[Numeric]` as the receiver's real class concludes absence, and says
# it about activesupport's own `self * KILOBYTE`. Measured over
# activesupport-8.1.3.1/lib, 289 files, with `unresolved-constant` held at 827
# as the control: `unknown-method` went 21 -> 30 when `self` became typed, all
# nine of them this shape, and zero reports removed.
#
# Nothing is lost by declining: before `self` had a type the check said nothing
# here either. What is kept is the completion and hover that `024.85` is about,
# which do not assert.
RSpec.describe "an undefined-method report about a written `self`" do
  def reports(source)
    Dir.mktmpdir("self-bound-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)

      document = Ovallsp::TextDocument.new(uri: "file://#{root}/core_ext.rb", text: source, version: 1,
                                           language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)

      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: Ovallsp::Models::ModelRegistry.new,
        route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
      )
      Ovallsp::Diagnostics::Engine.new
                                  .analyze(document: document, semantic_context: context, mode: :standard)
                                  .select { |f| f.code == "unknown-method" }.map(&:message)
    end
  end

  # activesupport's own shape, reduced. `Numeric` declares no `*`; every
  # instance that reaches this body does.
  it "says nothing about a method the receiver's subclasses supply" do
    source = "class Numeric\n  KILOBYTE = 1024\n  def kilobytes\n    self * KILOBYTE\n  end\nend\n"
    expect(reports(source)).to be_empty
  end

  it "says nothing about `self.` either, where the surface is the same bound" do
    source = "class Numeric\n  def kilobytes\n    self.abs2\n  end\nend\n"
    expect(reports(source)).to be_empty
  end

  # The control, and the whole reason the rule is about `self` and not about
  # `Instance[C]` generally: a receiver whose type came from an assignment
  # names the class exactly, and a genuine typo on it is still reported.
  it "still reports a typo on a receiver whose class an assignment named" do
    source = "class Widget\n  def go\n    w = Widget.new\n    w.definitely_not_a_member\n  end\nend\n"
    expect(reports(source)).to eq(["Widget has no method named `definitely_not_a_member`"])
  end

  # And the second control: declining on `self` must not disable the check for
  # the body it is written in.
  it "still reports a typo written beside the `self` call" do
    source = "class Numeric\n  KILOBYTE = 1024\n  def kilobytes\n    self * KILOBYTE\n    " \
             "Widget.new.definitely_not_a_member\n  end\nend\nclass Widget\nend\n"
    expect(reports(source)).to eq(["Widget has no method named `definitely_not_a_member`"])
  end
end
