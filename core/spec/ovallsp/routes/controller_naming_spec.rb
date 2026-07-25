# frozen_string_literal: true

RSpec.describe Ovallsp::Routes::ControllerNaming do
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

  describe ".view_directory" do
    it "is the inverse of .owner_name for a simple controller" do
      expect(described_class.view_directory("::UsersController")).to eq("users")
    end

    it "is the inverse of .owner_name for a namespaced controller" do
      expect(described_class.view_directory("::Admin::ProjectsController")).to eq("admin/projects")
    end

    it "underscores a multi-word controller name" do
      expect(described_class.view_directory("::LineItemsController")).to eq("line_items")
    end
  end
end
