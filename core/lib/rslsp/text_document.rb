# frozen_string_literal: true

module Rslsp
  # In-memory representation of a single open document. Three different
  # position units are in play and none of them line up for non-ASCII
  # text, so this class is careful to keep them distinct rather than
  # implicitly converting between them:
  #
  # - UTF-16 code units: what LSP positions (`{ line, character }`) use on
  #   the wire. A character outside the Basic Multilingual Plane (many
  #   emoji) is 2 code units.
  # - Ruby character (codepoint) offsets: what Ruby String indexing/slicing
  #   (`#[]`, `#[]=`) uses. #position_to_char_offset returns this — it's
  #   what #apply_incremental_change needs to splice `@text` in place.
  # - UTF-8 byte offsets: what Prism's parsed node locations
  #   (`location.start_offset`/`end_offset`) use. #position_to_byte_offset
  #   returns this — callers comparing an LSP position against a Prism
  #   node's location (e.g. LocalInferencer's `contains?`) must use this,
  #   not #position_to_char_offset, or a multibyte character anywhere
  #   before the target position throws the comparison off by however many
  #   extra bytes it took (docs/design/tasks/008.5-runtime-and-index-corrections.md).
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

    # Ruby character (codepoint) offset — use for indexing/slicing `@text`
    # itself (that's all this class uses it for internally).
    def position_to_char_offset(position)
      line_index = position.fetch(:line)
      character = position.fetch(:character)

      return @text.length if line_index >= @line_offsets.length

      line_start = @line_offsets[line_index]
      line_start + self.class.char_offset_for_utf16(line_content(line_index), character)
    end

    # UTF-8 byte offset — use when comparing against a Prism node's
    # `location.start_offset`/`end_offset`, which are byte offsets, not
    # character offsets. Never mix this with #position_to_char_offset.
    def position_to_byte_offset(position)
      line_index = position.fetch(:line)
      character = position.fetch(:character)

      return @text.bytesize if line_index >= @line_byte_offsets.length

      line_start = @line_byte_offsets[line_index]
      line_start + self.class.byte_offset_for_utf16(line_content(line_index), character)
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

    def self.byte_offset_for_utf16(line, utf16_offset)
      return 0 if utf16_offset <= 0

      units = 0
      bytes = 0
      line.each_char do |char|
        return bytes if units >= utf16_offset

        units += utf16_unit_count(char)
        bytes += char.bytesize
      end
      bytes
    end

    def self.utf16_unit_count(char)
      char.ord > 0xFFFF ? 2 : 1
    end

    private

    def text=(new_text)
      @text = new_text
      @line_offsets, @line_byte_offsets = compute_line_offsets(new_text)
    end

    def line_content(line_index)
      start = @line_offsets[line_index]
      finish = line_index + 1 < @line_offsets.length ? @line_offsets[line_index + 1] : @text.length
      @text[start...finish].sub(/\r?\n\z/, "")
    end

    def compute_line_offsets(text)
      char_offsets = [0]
      byte_offsets = [0]
      bytes = 0
      text.each_char.with_index do |char, idx|
        bytes += char.bytesize
        if char == "\n"
          char_offsets << idx + 1
          byte_offsets << bytes
        end
      end
      [char_offsets, byte_offsets]
    end
  end
end
