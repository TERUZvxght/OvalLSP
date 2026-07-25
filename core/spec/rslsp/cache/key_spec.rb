# frozen_string_literal: true

require "tmpdir"

RSpec.describe Rslsp::Cache::Key do
  it "produces the same digest for identical inputs" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, gemfile_lock_digest: "g1", rbs_digest: "r1",
                                            settings_digest: "s1")
      b = described_class.workspace_digest(workspace_root: root, gemfile_lock_digest: "g1", rbs_digest: "r1",
                                            settings_digest: "s1")

      expect(a).to eq(b)
    end
  end

  it "produces a different digest when the Gemfile.lock digest differs" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, gemfile_lock_digest: "g1")
      b = described_class.workspace_digest(workspace_root: root, gemfile_lock_digest: "g2")

      expect(a).not_to eq(b)
    end
  end

  it "produces a different digest when the RBS digest differs" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, rbs_digest: "r1")
      b = described_class.workspace_digest(workspace_root: root, rbs_digest: "r2")

      expect(a).not_to eq(b)
    end
  end

  it "produces a different digest when the settings digest differs" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, settings_digest: "s1")
      b = described_class.workspace_digest(workspace_root: root, settings_digest: "s2")

      expect(a).not_to eq(b)
    end
  end

  it "produces a different digest for a different Ruby version" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, ruby_version: "3.2.0")
      b = described_class.workspace_digest(workspace_root: root, ruby_version: "3.3.0")

      expect(a).not_to eq(b)
    end
  end

  it "produces a different digest for a different Prism version" do
    Dir.mktmpdir do |root|
      a = described_class.workspace_digest(workspace_root: root, prism_version: "1.0.0")
      b = described_class.workspace_digest(workspace_root: root, prism_version: "1.1.0")

      expect(a).not_to eq(b)
    end
  end

  it "produces a different digest for a different workspace root" do
    Dir.mktmpdir do |root1|
      Dir.mktmpdir do |root2|
        a = described_class.workspace_digest(workspace_root: root1)
        b = described_class.workspace_digest(workspace_root: root2)

        expect(a).not_to eq(b)
      end
    end
  end
end
