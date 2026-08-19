# frozen_string_literal: true

require "spec_helper"

# Two readers of `context.method_resolver` each carried their own
# `return unless` -- and 0.2.9 wrote one of them twice in a row, which is
# what a guard repeated at every caller invites. The impossibility belongs
# in the value: a context without a resolver cannot answer the questions
# `Engine` asks it, so it is not a context.
RSpec.describe Ovallsp::Diagnostics::SemanticContext do
  def build(**overrides)
    described_class.new(
      workspace_index: :index, hierarchy_index: :hierarchy,
      method_resolver: :resolver, local_inferencer: :inferencer, **overrides
    )
  end

  it "refuses a nil method resolver rather than leaving each reader to check" do
    expect { build(method_resolver: nil) }.to raise_error(ArgumentError, /method_resolver/)
  end

  it "refuses the other three required collaborators for the same reason" do
    expect { build(workspace_index: nil) }.to raise_error(ArgumentError, /workspace_index/)
    expect { build(hierarchy_index: nil) }.to raise_error(ArgumentError, /hierarchy_index/)
    expect { build(local_inferencer: nil) }.to raise_error(ArgumentError, /local_inferencer/)
  end

  it "still accepts nil for every optional field, which is what nobody-worked-it-out means" do
    context = build
    expect(context.signatures).to be_nil
    expect(context.assigned_ivars).to be_nil
  end
end
