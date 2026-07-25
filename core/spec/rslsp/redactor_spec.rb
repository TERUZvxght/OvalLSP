# frozen_string_literal: true

RSpec.describe Rslsp::Redactor do
  describe ".redact" do
    it "redacts a password= assignment" do
      expect(described_class.redact("connecting with password=hunter2verysecret")).to eq(
        "connecting with password=[REDACTED]"
      )
    end

    it "redacts an api_key: value in a hash-like log message" do
      expect(described_class.redact('config: {api_key: "sk-abc123def456"}')).to eq(
        'config: {api_key: "[REDACTED]"}'
      )
    end

    it "redacts a Bearer authorization token wherever it appears" do
      expect(described_class.redact("request failed: Authorization: Bearer abcDEF123.xyz789")).to eq(
        "request failed: Authorization: Bearer [REDACTED]"
      )
    end

    it "is case-insensitive for credential key names" do
      expect(described_class.redact("SECRET=abcdef123456")).to eq("SECRET=[REDACTED]")
    end

    it "leaves an ordinary message with no credential-shaped content untouched" do
      message = "failed to summarize file:///a.rb: NoMethodError: undefined method 'foo'"

      expect(described_class.redact(message)).to eq(message)
    end

    it "replaces this process' own HOME directory with ~" do
      original_home = ENV["HOME"]
      begin
        ENV["HOME"] = "/Users/exampleuser"
        expect(described_class.redact("reading /Users/exampleuser/project/Gemfile")).to eq("reading ~/project/Gemfile")
      ensure
        ENV["HOME"] = original_home
      end
    end

    it "handles a non-string message without raising" do
      expect { described_class.redact(nil) }.not_to raise_error
      expect { described_class.redact(:a_symbol) }.not_to raise_error
    end
  end

  describe ".redact_generic_tokens" do
    it "redacts a long token-shaped run of characters even without a credential-sounding key name" do
      expect(described_class.redact_generic_tokens("value: aGVsbG93b3JsZHRoaXNpc2FzZWNyZXQ")).to eq("value: [REDACTED]")
    end

    it "is not applied by .redact's own default pipeline" do
      message = "commit deadbeefdeadbeefdeadbeefdeadbeefdeadbeef succeeded"

      expect(described_class.redact(message)).to eq(message)
    end
  end
end
