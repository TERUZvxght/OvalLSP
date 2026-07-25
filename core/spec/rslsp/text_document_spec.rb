# frozen_string_literal: true

RSpec.describe Rslsp::TextDocument do
  def document(text)
    described_class.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby")
  end

  describe "#position_to_byte_offset" do
    it "matches the char offset for pure ASCII text" do
      doc = document("hello\nworld\n")
      pos = { line: 1, character: 3 }

      expect(doc.position_to_byte_offset(pos)).to eq(doc.position_to_char_offset(pos))
    end

    it "diverges from the char offset once a multibyte line precedes the target" do
      # "日本語" is 3 Ruby characters but 9 UTF-8 bytes.
      doc = document("日本語\nuser\n")
      pos = { line: 1, character: 2 } # "us|er" on line 1

      char_offset = doc.position_to_char_offset(pos)
      byte_offset = doc.position_to_byte_offset(pos)

      expect(char_offset).to eq(3 + 1 + 2) # 3 chars + newline + 2 chars into line 1
      expect(byte_offset).to eq(9 + 1 + 2) # 9 bytes + newline + 2 ASCII bytes into line 1
      expect(byte_offset).not_to eq(char_offset)
    end

    it "accounts for an astral character (emoji, 2 UTF-16 units / 4 bytes) within the target line" do
      line = "label = \"😀\"\n"
      doc = document(line)
      # UTF-16 character 12 is right after the emoji (8 chars + quote + 2 units for the emoji = 11,
      # so char 11 is the closing quote's position).
      pos = { line: 0, character: 11 }

      # "label = \"" is 9 ASCII bytes/chars, then the emoji is 1 char / 2 UTF-16 units / 4 bytes.
      expect(doc.position_to_char_offset(pos)).to eq(10) # 9 + 1 (the emoji itself, as one Ruby char)
      expect(doc.position_to_byte_offset(pos)).to eq(13) # 9 + 4 (the emoji's 4 UTF-8 bytes)
    end

    it "handles a line mixing ASCII and non-ASCII characters" do
      doc = document("x = 1 # 日本語コメント\ny\n")
      pos = { line: 1, character: 0 }

      # Line 0 is "x = 1 # " (8 ASCII chars/bytes) + "日本語コメント" (7 chars, 21 bytes) + newline.
      expect(doc.position_to_char_offset(pos)).to eq(8 + 7 + 1)
      expect(doc.position_to_byte_offset(pos)).to eq(8 + 21 + 1)
    end

    it "treats a CRLF line ending the same way as LF for offset purposes" do
      doc = document("a\r\nb\r\n")
      pos = { line: 1, character: 0 }

      expect(doc.position_to_char_offset(pos)).to eq(3) # "a" + "\r\n"
      expect(doc.position_to_byte_offset(pos)).to eq(3)
    end

    it "returns the line's start offset for an empty line" do
      doc = document("a\n\nb\n")
      pos = { line: 1, character: 0 }

      expect(doc.position_to_byte_offset(pos)).to eq(2)
    end

    it "clamps to the end of the text for a position past the last line" do
      doc = document("abc\n")
      pos = { line: 5, character: 0 }

      expect(doc.position_to_byte_offset(pos)).to eq("abc\n".bytesize)
    end

    it "handles a position at the very end of a multibyte file (no trailing newline)" do
      text = "日本語😀" # 3 chars (3 UTF-16 units) + 1 emoji (2 UTF-16 units) = character 5 is the end
      doc = document(text)

      expect(doc.position_to_byte_offset({ line: 0, character: 5 })).to eq(text.bytesize)
    end
  end

  describe "#char_offset_to_position (Task 013)" do
    it "round-trips through #position_to_char_offset for pure ASCII text" do
      doc = document("user.company\nnext_line\n")
      pos = { line: 0, character: 4 } # the "." in "user.company"

      offset = doc.position_to_char_offset(pos)

      expect(doc.char_offset_to_position(offset)).to eq(pos)
    end

    it "finds the correct line for an offset on a later line" do
      doc = document("user.company\nnext_line\n")

      expect(doc.char_offset_to_position(13)).to eq({ line: 1, character: 0 })
    end

    it "accounts for a multibyte character earlier in the line, reporting UTF-16 units, not char count" do
      doc = document("日本語.foo\n")

      expect(doc.char_offset_to_position(3)).to eq({ line: 0, character: 3 }) # the "." right after 日本語
    end

    it "round-trips through an astral character (emoji) earlier on the line" do
      doc = document("😀.foo\n")
      pos = { line: 0, character: 2 } # the "." right after the emoji (2 UTF-16 units)

      offset = doc.position_to_char_offset(pos)

      expect(doc.char_offset_to_position(offset)).to eq(pos)
    end
  end
end
