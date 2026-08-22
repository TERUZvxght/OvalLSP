# frozen_string_literal: true

# `024.122`. `LocalInferencer#assigned_ivar_names` answered `[]` when its
# parse raised, and both callers build a *union* the unassigned-ivar
# check compares a view's reads against. An empty list from a failed
# parse is indistinguishable from a document that assigns none -- so one
# unreadable ancestor file silently removed its ivars from the union and
# every read of one became a false report.
#
# `Server#assigned_ivars_for` already refuses in that situation, by
# answering `nil` and switching the check off for the view. The failure
# was being caught one layer below the layer that knows what to do with
# it.
RSpec.describe "Ovallsp::LocalInferencer and a document it cannot parse" do
  # One stack, assembled where the server assembles its own (042's D8).
  let(:inferencer) { build_analysis_stack.local_inferencer }

  def document(text)
    Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
  end

  it "answers the names a readable document assigns" do
    expect(inferencer.assigned_ivar_names(document("class A\n  def go\n    @x = 1\n  end\nend\n")))
      .to eq(["@x"])
  end

  # The distinguishing half: a failure must not look like "this document
  # assigns nothing". An implementation that rescued into `[]` would pass
  # the example above and fail this one.
  it "raises rather than answering an empty list when it cannot look" do
    broken = instance_double(Ovallsp::TextDocument)
    allow(broken).to receive(:text).and_raise(IOError, "gone")

    expect { inferencer.assigned_ivar_names(broken) }.to raise_error(IOError)
  end
end
