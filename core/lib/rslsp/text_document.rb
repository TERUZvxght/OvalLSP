# frozen_string_literal: true

module Rslsp
  # In-memory representation of a single open document. Positions on the
  # wire are LSP `{ line, character }` pairs where `character` counts UTF-16
  # code units, while Ruby strings are indexed by codepoint. Characters
  # outside the Basic Multilingual Plane (e.g. many emoji) are one Ruby
  # character but two UTF-16 code units, so offsets must be converted
  # explicitly rather than assumed to line up.
  class TextDocument
    attr_reader :uri, :version, :language_id, :text

    def initialize(uri:, text:, version:, language_id:)
      @uri = uri
      @language_id = language_id
      @version = version
      self.text = text
    end

    def apply_full_change(text:, version:)
      self.text = text
      @version = version
    end

    def apply_incremental_change(range:, new_text:, version:)
      start_offset = position_to_char_offset(range.fetch(:start))
      end_offset = position_to_char_offset(range.fetch(:end))

      updated = @text.dup
      updated[start_offset...end_offset] = new_text
      self.text = updated
      @version = version
    end

    def position_to_char_offset(position)
      line_index = position.fetch(:line)
      character = position.fetch(:character)

      return @text.length if line_index >= @line_offsets.length

      line_start = @line_offsets[line_index]
      line_start + self.class.char_offset_for_utf16(line_content(line_index), character)
    end

    def self.char_offset_for_utf16(line, utf16_offset)
      return 0 if utf16_offset <= 0

      units = 0
      line.each_char.with_index do |char, idx|
        return idx if units >= utf16_offset

        units += utf16_unit_count(char)
      end
      line.length
    end

    def self.utf16_unit_count(char)
      char.ord > 0xFFFF ? 2 : 1
    end

    private

    def text=(new_text)
      @text = new_text
      @line_offsets = compute_line_offsets(new_text)
    end

    def line_content(line_index)
      start = @line_offsets[line_index]
      finish = line_index + 1 < @line_offsets.length ? @line_offsets[line_index + 1] : @text.length
      @text[start...finish].sub(/\r?\n\z/, "")
    end

    def compute_line_offsets(text)
      offsets = [0]
      text.each_char.with_index do |char, idx|
        offsets << idx + 1 if char == "\n"
      end
      offsets
    end
  end
end
