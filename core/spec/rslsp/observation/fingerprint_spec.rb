# frozen_string_literal: true

require "tempfile"

RSpec.describe Rslsp::Observation::Fingerprint do
  it "returns the same fingerprint for the same file content and line" do
    file = Tempfile.new("fp")
    file.write("hello")
    file.close

    expect(described_class.for_file_and_line(file.path, 3)).to eq(described_class.for_file_and_line(file.path, 3))
  ensure
    file&.unlink
  end

  it "returns a different fingerprint when the file content changes" do
    file = Tempfile.new("fp")
    file.write("hello")
    file.close
    before = described_class.for_file_and_line(file.path, 3)

    File.write(file.path, "goodbye")
    after = described_class.for_file_and_line(file.path, 3)

    expect(before).not_to eq(after)
  ensure
    file&.unlink
  end

  it "returns a different fingerprint for a different line, same content" do
    file = Tempfile.new("fp")
    file.write("hello")
    file.close

    expect(described_class.for_file_and_line(file.path, 3)).not_to eq(described_class.for_file_and_line(file.path, 4))
  ensure
    file&.unlink
  end

  it "returns nil rather than raising for a nonexistent file" do
    expect(described_class.for_file_and_line("/no/such/file", 1)).to be_nil
  end

  it "for_content_and_line matches for_file_and_line's own digest for identical content" do
    file = Tempfile.new("fp")
    file.write("hello")
    file.close

    expect(described_class.for_content_and_line("hello", 3)).to eq(described_class.for_file_and_line(file.path, 3))
  ensure
    file&.unlink
  end
end
