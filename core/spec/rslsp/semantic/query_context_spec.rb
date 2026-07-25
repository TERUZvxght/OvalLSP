# frozen_string_literal: true

RSpec.describe Rslsp::Semantic::QueryContext do
  def context(**overrides)
    described_class.new(uri: "file:///a.rb", position: { line: 0, character: 0 }, **overrides)
  end

  describe "#stale?" do
    it "is not stale when every captured generation still matches" do
      ctx = context(workspace_generation: 1, signature_generation: 2)

      expect(ctx.stale?(workspace_generation: 1, signature_generation: 2)).to be(false)
    end

    it "is stale when a captured generation has since moved on" do
      ctx = context(workspace_generation: 1)

      expect(ctx.stale?(workspace_generation: 2)).to be(true)
    end

    it "ignores a generation dimension the context never captured" do
      ctx = context(workspace_generation: 1)

      expect(ctx.stale?(workspace_generation: 1, signature_generation: 99)).to be(false)
    end
  end

  describe "#cancelled?" do
    it "is false when no cancellation_token was given" do
      expect(context.cancelled?).to be(false)
    end

    it "reflects the token's own #cancelled? when one is given" do
      token = Struct.new(:cancelled?).new(true)

      expect(context(cancellation_token: token).cancelled?).to be(true)
    end
  end
end
