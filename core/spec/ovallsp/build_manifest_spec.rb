# frozen_string_literal: true

require "tmpdir"
require "json"

RSpec.describe Ovallsp::BuildManifest do
  it "returns nil when no manifest file exists at all (a plain dev checkout)" do
    Dir.mktmpdir do |dir|
      expect(described_class.load(path: File.join(dir, "PLATFORM_MANIFEST.json"))).to be_nil
    end
  end

  it "returns nil, not a raised error, for a manifest that fails to parse" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "PLATFORM_MANIFEST.json")
      File.write(path, "not valid json{{{")

      expect(described_class.load(path: path)).to be_nil
    end
  end

  it "parses a well-formed manifest into a Hash" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "PLATFORM_MANIFEST.json")
      File.write(path, JSON.generate(extensionVersion: "0.1.0", buildCommit: "abc123", buildTarget: "darwin-arm64"))

      manifest = described_class.load(path: path)

      expect(manifest).to eq("extensionVersion" => "0.1.0", "buildCommit" => "abc123", "buildTarget" => "darwin-arm64")
    end
  end

  it "defaults to core/PLATFORM_MANIFEST.json, sibling to lib/ and bin/ -- the same path bin/ovallsp and VendorCompatibility already use" do
    path = described_class.default_path

    expect(File.basename(path)).to eq("PLATFORM_MANIFEST.json")
    expect(File.basename(File.dirname(path))).to eq("core")
  end
end
