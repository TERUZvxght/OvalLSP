# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"
require "ovallsp/vendor_bootstrap"

RSpec.describe Ovallsp::VendorBootstrap do
  # Bundler lays a payload out one directory per ABI --
  # `vendor/bundle/ruby/3.4.0`, `vendor/bundle/ruby/4.0.0` -- and the
  # native extensions inside each are the wrong machine code for every
  # other one. A packaged VSIX has exactly one, which is why this went
  # unnoticed; a development checkout that has run `bundle install` under
  # two Rubies has two, and that is the configuration `docs/SUPPORT_MATRIX.md`
  # asks a contributor to create when it says 4.0 is verified by hand.
  # A platform this interpreter is definitely not on. The fixture used to
  # name `x86_64-linux` literally, which is "another Ruby" on the
  # maintainer's Mac and *this* Ruby on CI -- so the payload was
  # compatible there, nothing was refused, and the example failed on
  # Linux only. Derived from the running platform instead, so it is wrong
  # everywhere it needs to be.
  def other_platform = RUBY_PLATFORM.include?("darwin") ? "x86_64-linux" : "arm64-darwin99"

  def this_abi = RbConfig::CONFIG["ruby_version"]
  def other_abi = this_abi.start_with?("3.") ? "4.0.0" : "3.4.0"

  def vendor_gem(root, abi, gem_name)
    File.join(root, "ruby", abi, "gems", gem_name, "lib").tap { |lib| FileUtils.mkdir_p(lib) }
  end

  def manifest(dir, engine: RUBY_ENGINE, version: RUBY_VERSION.split(".").first(2).join("."), platform: RUBY_PLATFORM)
    File.join(dir, "PLATFORM_MANIFEST.json").tap do |path|
      File.write(path, JSON.generate("rubyEngine" => engine, "rubyVersionMajorMinor" => version, "rubyPlatform" => platform))
    end
  end

  it "adds only the running interpreter's ABI directory when a checkout has bundled under two Rubies" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      mine = vendor_gem(vendor_root, this_abi, "prism-1.9.0")
      theirs = vendor_gem(vendor_root, other_abi, "prism-1.9.0")
      load_path = []

      added = described_class.activate!(
        vendor_root: vendor_root, manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), load_path: load_path
      )

      expect(added).to contain_exactly(mine)
      expect(load_path).to contain_exactly(mine)
      expect(load_path).not_to include(theirs)
    end
  end

  it "adds every gem in the running ABI's directory" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      prism = vendor_gem(vendor_root, this_abi, "prism-1.9.0")
      rbs = vendor_gem(vendor_root, this_abi, "rbs-4.0.3")
      load_path = []

      described_class.activate!(
        vendor_root: vendor_root, manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), load_path: load_path
      )

      expect(load_path).to contain_exactly(prism, rbs)
    end
  end

  it "puts the vendored payload ahead of whatever the interpreter would otherwise find" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      mine = vendor_gem(vendor_root, this_abi, "prism-1.9.0")
      load_path = ["/an/already/installed/prism/lib"]

      described_class.activate!(
        vendor_root: vendor_root, manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), load_path: load_path
      )

      expect(load_path.first).to eq(mine)
    end
  end

  it "adds nothing and warns when the manifest says the payload was built for another Ruby" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      vendor_gem(vendor_root, this_abi, "prism-1.9.0")
      load_path = []
      warnings = []

      added = described_class.activate!(
        vendor_root: vendor_root,
        manifest_path: manifest(dir, platform: other_platform),
        load_path: load_path,
        warner: ->(message) { warnings << message }
      )

      expect(added).to be_empty
      expect(load_path).to be_empty
      expect(warnings.join).to include("ovallsp:").and include(other_platform)
    end
  end

  it "adds nothing and warns nothing when there is no vendor directory at all (a plain dev checkout)" do
    Dir.mktmpdir do |dir|
      load_path = []
      warnings = []

      added = described_class.activate!(
        vendor_root: File.join(dir, "vendor", "bundle"),
        manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"),
        load_path: load_path,
        warner: ->(message) { warnings << message }
      )

      expect(added).to be_empty
      expect(load_path).to be_empty
      expect(warnings).to be_empty
    end
  end

  # The payload is permitted by the manifest but laid out for an ABI this
  # interpreter cannot load. Adding it would be the crash ADR-0005 exists
  # to prevent, so the answer is the same as "no payload": add nothing and
  # let ordinary gem resolution decide.
  it "adds nothing when the payload's only ABI directory is not this interpreter's" do
    Dir.mktmpdir do |dir|
      vendor_root = File.join(dir, "vendor", "bundle")
      theirs = vendor_gem(vendor_root, other_abi, "prism-1.9.0")
      load_path = []

      added = described_class.activate!(
        vendor_root: vendor_root, manifest_path: File.join(dir, "PLATFORM_MANIFEST.json"), load_path: load_path
      )

      expect(added).to be_empty
      expect(load_path).not_to include(theirs)
    end
  end
end
