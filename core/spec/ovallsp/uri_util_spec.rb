# frozen_string_literal: true

RSpec.describe Ovallsp::UriUtil do
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

  # **A backslash is a filename character on POSIX and a separator on
  # Windows, and `#from_path` treated every one as a separator.** So
  # `/tmp/one\\two.rb` -- a legal, if unusual, POSIX filename -- produced
  # a URI naming `/tmp/one/two.rb`, a different file, and the round trip
  # did not come back. Found by the 2026-09-05 critical review, R10.
  #
  # The normalisation is kept for the paths it is *for*: a drive letter or
  # a UNC prefix is what says a backslash is a separator, and neither can
  # appear in a POSIX path that means something else.
  describe "a backslash in a POSIX filename" do
    it "round-trips a path whose name contains one" do
      path = "/tmp/one\\two.rb"

      expect(described_class.to_path(described_class.from_path(path))).to eq(path)
    end

    it "still normalises a Windows drive path written with backslashes" do
      expect(described_class.from_path("C:\\work\\a.rb")).to eq("file:///C:/work/a.rb")
    end

    it "still normalises a UNC path written with backslashes" do
      expect(described_class.from_path("\\\\server\\share\\a.rb")).to eq("file://server/share/a.rb")
    end
  end

  # **A `#` in a path is a URI fragment**, so a workspace under a
  # directory named with one produced a URI whose path stopped at the
  # `#`. `#from_path` escapes; the signature loaders concatenated
  # `"file://#{path}"` by hand and did not.
  describe "characters that need escaping" do
    { "a hash" => "/tmp/proj#1/a.rb", "a space" => "/tmp/my proj/a.rb",
      "a percent" => "/tmp/100%/a.rb", "a question mark" => "/tmp/what?/a.rb" }.each do |what, path|
      it "round-trips #{what}" do
        expect(described_class.to_path(described_class.from_path(path))).to eq(path)
      end
    end
  end
end
