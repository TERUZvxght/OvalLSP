# frozen_string_literal: true

RSpec.describe Rslsp::Routes::ControllerNaming do
  describe ".owner_name" do
    it "converts a simple controller path to its fully-qualified class name" do
      expect(described_class.owner_name("posts")).to eq("::PostsController")
    end

    it "converts a namespaced controller path" do
      expect(described_class.owner_name("admin/projects")).to eq("::Admin::ProjectsController")
    end

    it "handles underscored controller segments" do
      expect(described_class.owner_name("line_items")).to eq("::LineItemsController")
    end
  end
end
