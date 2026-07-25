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

    # Found by an independent review of Task 022: the module's own
    # docstring names "a DB connection string" and an API client's own
    # exception text as its motivating examples, but neither actually
    # matched anything before this fix -- only an explicit
    # `password=`-labeled assignment was ever redacted.
    it "redacts the password in a DB connection string URL, keeping the username" do
      message = "PG::ConnectionBad: could not connect to postgres://myapp_user:hunter2Secret@db.internal:5432/production"

      redacted = described_class.redact(message)

      expect(redacted).to include("postgres://myapp_user:[REDACTED]@db.internal:5432/production")
      expect(redacted).not_to include("hunter2Secret")
    end

    it "redacts a live Stripe API key with no credential-sounding label in front of it" do
      message = "Stripe::AuthenticationError: Invalid API Key provided: sk_live_51H8xJ2eZvKYloExampleKeyValue123"

      redacted = described_class.redact(message)

      expect(redacted).not_to include("sk_live_51H8xJ2eZvKYloExampleKeyValue123")
      expect(redacted).to include("[REDACTED]")
    end

    it "redacts an AWS-style access key ID embedded in a URL query string" do
      message = "Net::HTTPServerException: 401 for https://api.example.com/v1/resource?key=AKIAIOSFODNN7EXAMPLE"

      redacted = described_class.redact(message)

      expect(redacted).not_to include("AKIAIOSFODNN7EXAMPLE")
    end

    it "redacts a GitHub personal access token with no label" do
      message = "fatal: unable to access 'https://github.com/org/repo.git/': ghp_1234567890abcdefghij1234567890ABCD"

      redacted = described_class.redact(message)

      expect(redacted).not_to include("ghp_1234567890abcdefghij1234567890ABCD")
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
