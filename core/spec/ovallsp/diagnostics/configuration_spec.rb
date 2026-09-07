# frozen_string_literal: true

require_relative "../../unit_spec_helper"
require_relative "../../../lib/ovallsp/diagnostics/configuration"

RSpec.describe Ovallsp::Diagnostics::Configuration do
  it "owns an immutable snapshot independent of the input map and strings" do
    code = +"unknown-method"
    value = +"hint"
    raw = { code => value }
    config = described_class.new(severities: raw)
    value.replace("none")
    code.replace("syntax-error")
    raw.clear

    expect(config.severities).to eq("unknown-method" => :hint)
    expect(config).to be_frozen
    expect { config.severities["unknown-method"] = :none }.to raise_error(FrozenError)
    expect { config.severities.keys.first.replace("syntax-error") }.to raise_error(FrozenError)
  end

  it "normalizes the approved checks without accepting aliases or escalations" do
    config = described_class.new(severities: {
      "syntax-error" => "warning", "unknown-method" => "error", "argument-count" => "information",
      "argument-type" => "hint", "unassigned-ivar" => "none", "unknown-route-helper" => "warning",
      "unresolved-constant" => "hint", "future-check" => "warning"
    })
    expect(config.severities).to eq(
      "syntax-error" => :warning, "argument-count" => :information, "argument-type" => :hint,
      "unassigned-ivar" => :none, "unknown-route-helper" => :warning
    )
  end

  it "treats malformed maps and severity values as no override" do
    [nil, false, [], "hint", 1].each do |raw|
      expect(described_class.new(severities: raw).severities).to eq({})
    end
    [nil, false, [], {}, 1, :hint, "info", "off", "HINT"].each do |value|
      expect(described_class.new(severities: { "unknown-method" => value }).severities).to eq({})
    end
    expect(described_class.new(severities: { "syntax-error" => "error" }).severities).to eq("syntax-error" => :error)
  end

  it "compares normalized snapshots by value while retaining distinct identities" do
    a = described_class.new(severities: { "unknown-method" => "hint" })
    b = described_class.new(severities: { "unknown-method" => "none" })
    again = described_class.new(severities: { "unknown-method": "hint", "ignored" => "error" })
    expect(a).to eq(again)
    expect(a).not_to equal(again)
    expect(a).not_to eq(b)
    expect(a).not_to eq(described_class.new(mode: :standard, severities: { "unknown-method" => "hint" }))
  end

  it "preserves the existing modes and refuses an unknown direct Engine mode" do
    %i[safe standard strict].each { |mode| expect(described_class.new(mode: mode).mode).to eq(mode) }
    expect { described_class.new(mode: :bogus) }.to raise_error(ArgumentError, /unknown mode/)
  end
end
