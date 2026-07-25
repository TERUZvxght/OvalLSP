# frozen_string_literal: true

require "tmpdir"

RSpec.describe Ovallsp::Plugins::Manifest do
  let(:fixtures_root) { File.expand_path("../../fixtures/plugins", __dir__) }

  def manifest_path(name)
    File.join(fixtures_root, name, "plugin-manifest.json")
  end

  it "loads a valid manifest, resolving entrypoints relative to the manifest's own directory" do
    manifest = described_class.load(manifest_path("state_machine_example"))

    expect(manifest.name).to eq("ovallsp-example-state-machine")
    expect(manifest.protocol_version).to eq(1)
    expect(manifest.static_entrypoint_path).to eq(
      File.join(fixtures_root, "state_machine_example", "lib", "plugin.rb")
    )
  end

  it "reports protocol_version compatibility against this Core build's own version" do
    manifest = described_class.load(manifest_path("state_machine_example"))
    incompatible = described_class.load(manifest_path("bad_version"))

    expect(manifest.compatible_protocol_version?).to be(true)
    expect(incompatible.compatible_protocol_version?).to be(false)
  end

  it "raises InvalidManifest for a manifest missing a required field" do
    expect { described_class.load(manifest_path("invalid_manifest")) }
      .to raise_error(Ovallsp::Plugins::InvalidManifest, /name/)
  end

  it "raises InvalidManifest for a nonexistent manifest file" do
    expect { described_class.load(File.join(fixtures_root, "does_not_exist", "plugin-manifest.json")) }
      .to raise_error(Ovallsp::Plugins::InvalidManifest)
  end

  it "raises InvalidManifest for malformed JSON" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "plugin-manifest.json")
      File.write(path, "{ not valid json")

      expect { described_class.load(path) }.to raise_error(Ovallsp::Plugins::InvalidManifest, /JSON/)
    end
  end

  it "rejects a name that doesn't match the schema's ^[a-z0-9_-]+$ pattern" do
    expect { described_class.from_hash({ name: "Not Valid!", version: "0.1.0", protocol_version: 1 }, dir: ".") }
      .to raise_error(Ovallsp::Plugins::InvalidManifest, /name/)
  end
end
