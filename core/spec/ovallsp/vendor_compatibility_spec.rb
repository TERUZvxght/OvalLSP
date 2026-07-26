# frozen_string_literal: true

require "tmpdir"
require "json"

RSpec.describe Ovallsp::VendorCompatibility do
  def write_manifest(dir, engine: "ruby", version: "3.4", platform: "arm64-darwin25")
    File.write(
      File.join(dir, "PLATFORM_MANIFEST.json"),
      JSON.generate(rubyEngine: engine, rubyVersionMajorMinor: version, rubyPlatform: platform)
    )
  end

  it "is compatible when no vendor directory exists at all (a plain dev checkout)" do
    Dir.mktmpdir do |dir|
      result = described_class.check(
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"),
        vendor_root: File.join(dir, "vendor", "bundle")
      )

      expect(result).to be_compatible
    end
  end

  it "is compatible when a vendor directory exists but has no manifest (an older, pre-ADR-0005 VSIX)" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)

      result = described_class.check(manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root)

      expect(result).to be_compatible
    end
  end

  it "is compatible when the manifest matches the running Ruby's engine/version/platform exactly" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)
      write_manifest(dir)

      result = described_class.check(
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root,
        ruby_engine: "ruby", ruby_version: "3.4.7", ruby_platform: "arm64-darwin25"
      )

      expect(result).to be_compatible
      expect(result.reason).to be_nil
    end
  end

  it "compares only the major.minor Ruby version, not the full patch version" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)
      write_manifest(dir, version: "3.4")

      result = described_class.check(
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root,
        ruby_engine: "ruby", ruby_version: "3.4.0", ruby_platform: "arm64-darwin25"
      )

      expect(result).to be_compatible
    end
  end

  it "is incompatible when the Ruby platform differs, with a clear, actionable reason" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)
      write_manifest(dir, platform: "arm64-darwin25")

      result = described_class.check(
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root,
        ruby_engine: "ruby", ruby_version: "3.3.8", ruby_platform: "x86_64-linux"
      )

      expect(result).not_to be_compatible
      expect(result.reason).to include("ruby 3.4 (arm64-darwin25)")
      expect(result.reason).to include("ruby 3.3 (x86_64-linux)")
      expect(result.reason).to include("ovallsp.rubyExecutablePath")
    end
  end

  it "is incompatible when only the Ruby engine differs (e.g. jruby vs ruby)" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)
      write_manifest(dir, engine: "ruby")

      result = described_class.check(
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root,
        ruby_engine: "jruby", ruby_version: "3.4.0", ruby_platform: "arm64-darwin25"
      )

      expect(result).not_to be_compatible
    end
  end

  it "is incompatible (fail-closed), not compatible, when the manifest exists but cannot be parsed" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      FileUtils.mkdir_p(vendor_root)
      File.write(File.join(dir, "PLATFORM_MANIFEST.json"), "not valid json{{{")

      result = described_class.check(manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), vendor_root: vendor_root)

      expect(result).not_to be_compatible
      expect(result.reason).to include("could not read vendor platform manifest")
    end
  end
end
