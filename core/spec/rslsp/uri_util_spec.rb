# frozen_string_literal: true

RSpec.describe Rslsp::UriUtil do
  describe ".from_path / .to_path round-trip (Task 008.5)" do
    it "round-trips a plain ASCII path" do
      uri = described_class.from_path("/workspace/app/models/user.rb")
      expect(uri).to eq("file:///workspace/app/models/user.rb")
      expect(described_class.to_path(uri)).to eq("/workspace/app/models/user.rb")
    end

    it "round-trips a path containing spaces" do
      uri = described_class.from_path("/workspace/My Project/user.rb")
      expect(uri).not_to include(" ")
      expect(described_class.to_path(uri)).to eq("/workspace/My Project/user.rb")
    end

    it "round-trips a path containing Japanese characters" do
      uri = described_class.from_path("/workspace/日本語/ユーザー.rb")
      expect(described_class.to_path(uri)).to eq("/workspace/日本語/ユーザー.rb")
    end

    it "round-trips a path containing a literal #" do
      uri = described_class.from_path("/workspace/app#1/user.rb")
      expect(described_class.to_path(uri)).to eq("/workspace/app#1/user.rb")
    end

    it "round-trips a path containing a literal %" do
      uri = described_class.from_path("/workspace/100%/user.rb")
      expect(described_class.to_path(uri)).to eq("/workspace/100%/user.rb")
    end

    it "round-trips a Windows drive-letter path given with backslashes" do
      uri = described_class.from_path('C:\\Users\\dev\\app\\user.rb')
      expect(uri).to eq("file:///C:/Users/dev/app/user.rb")
      expect(described_class.to_path(uri)).to eq("C:/Users/dev/app/user.rb")
    end

    it "round-trips a Windows drive-letter path already given with forward slashes" do
      uri = described_class.from_path("C:/Users/dev/app/user.rb")
      expect(described_class.to_path(uri)).to eq("C:/Users/dev/app/user.rb")
    end

    it "round-trips a UNC path" do
      uri = described_class.from_path('\\\\fileserver\\share\\project\\user.rb')
      expect(uri).to eq("file://fileserver/share/project/user.rb")
      expect(described_class.to_path(uri)).to eq("//fileserver/share/project/user.rb")
    end
  end

  describe ".from_path" do
    it "passes an already-URI-formatted input straight through instead of double-encoding it" do
      already_uri = "file:///workspace/user.rb"
      expect(described_class.from_path(already_uri)).to eq(already_uri)
    end

    it "raises rather than silently building a bogus URI from a relative path" do
      expect { described_class.from_path("app/models/user.rb") }.to raise_error(ArgumentError)
    end

    it "raises for nil or an empty path" do
      expect { described_class.from_path(nil) }.to raise_error(ArgumentError)
      expect { described_class.from_path("") }.to raise_error(ArgumentError)
    end
  end

  describe ".to_path" do
    it "returns nil for a non-file scheme" do
      expect(described_class.to_path("https://example.com/user.rb")).to be_nil
    end

    it "returns nil for a string that isn't a URI at all" do
      expect(described_class.to_path("not a uri")).to be_nil
    end

    it "returns nil rather than raising for a malformed file URI" do
      expect(described_class.to_path("file://%")).to be_nil
    end
  end
end
