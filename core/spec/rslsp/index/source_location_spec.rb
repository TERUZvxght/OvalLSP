# frozen_string_literal: true

RSpec.describe Rslsp::Index::SourceLocation do
  describe ".byte_offset_to_utf16" do
    it "counts ASCII characters 1:1" do
      expect(described_class.byte_offset_to_utf16("hello", 3)).to eq(3)
    end

    it "accounts for astral characters occupying two UTF-16 units but four bytes" do
      line = "x = \"\u{1F600}y\"" # x = "😀y"
      # byte offset 9 is right after the emoji's 4 UTF-8 bytes (5 preceding + 4)
      expect(described_class.byte_offset_to_utf16(line, 9)).to eq(7)
      # byte offset 11 is after the trailing y and closing quote
      expect(described_class.byte_offset_to_utf16(line, 11)).to eq(9)
    end
  end

  describe ".to_range" do
    it "converts a 1-based Prism location into a 0-based LSP range" do
      fake_location = Struct.new(:start_line, :start_column, :end_line, :end_column).new(2, 0, 2, 5)

      expect(described_class.to_range(fake_location, ["module Foo", "class X", "end"])).to eq(
        start: { line: 1, character: 0 },
        end: { line: 1, character: 5 }
      )
    end
  end
end
