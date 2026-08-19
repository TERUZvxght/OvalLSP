# frozen_string_literal: true

module Ovallsp
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

    # **A snapshot, not a mutable buffer.** Until 0.2.7 this class was
    # edited in place on the dispatch thread while background threads read
    # it: `apply_incremental_change` wrote `@text` and then `@version`,
    # and `text=` assigned `@text` *before* recomputing the two
    # line-offset tables. Six `republish_open_diagnostics` call sites read
    # `text` and `version` from other threads, and `handle_did_change`
    # mutated before taking any lock.
    #
    # The consequence is a torn read. **The offsets half is the one that
    # bites**: `position_to_byte_offset` reads `@line_byte_offsets`, then
    # `@line_offsets` and `@text`, and `text=` assigned `@text` before
    # recomputing either table. A reviewer measured it against a
    # concurrent change loop -- **1,977,450 of 1,977,451 calls returned a
    # byte offset belonging to neither document**, because MRI preempts
    # between those two statements and the document then sits torn for a
    # whole quantum. Every position-based answer runs through that
    # arithmetic.
    #
    # The version half is real and much narrower: a background publish
    # could send old-text findings under a new version number. It was
    # first written down here as dangerous because of what the client
    # supposedly does with a version, and that was not true --
    # `docs/CLIENT_BEHAVIOUR.md` records what it actually does, and exists
    # because this claim was written into three places unchecked. What is
    # left is that the number is wrong for any client that *does* read it,
    # which is a smaller thing.
    #
    # Text, version and offsets are computed together here and never
    # change afterwards, so a reader sees either the whole old document or
    # the whole new one. `DocumentStore` swaps its hash entry for a new
    # instance -- one reference assignment -- and is the only caller of
    # the `#with_*` builders below. 029's M-2, and the precondition for
    # M-3's version ordering to mean anything.
    def initialize(uri:, text:, version:, language_id:)
      @uri = uri
      @language_id = language_id
      @version = version
      @text = text
      @line_offsets, @line_byte_offsets = compute_line_offsets(text)
      freeze
    end

    def with_full_change(text:, version:)
      self.class.new(uri: @uri, text: text, version: version, language_id: @language_id)
    end

    def with_incremental_change(range:, new_text:, version:)
      start_offset = position_to_char_offset(range.fetch(:start))
      end_offset = position_to_char_offset(range.fetch(:end))

      updated = @text.dup
      updated[start_offset...end_offset] = new_text
      with_full_change(text: updated, version: version)
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

    # The inverse of #position_to_char_offset — given a Ruby character
    # offset into `@text`, returns the LSP `{ line:, character: }`
    # position (UTF-16 code units) it corresponds to. Task 013 needs this
    # to turn a text-scan result (e.g. "the offset of the `.` just before
    # the cursor") back into a position #infer_at can query, the same way
    # #word_at_position already scans in char-offset space for other
    # purposes.
    def char_offset_to_position(char_offset)
      line_index = @line_offsets.bsearch_index { |start| start > char_offset }
      line_index = line_index ? line_index - 1 : @line_offsets.length - 1
      line_start = @line_offsets[line_index]

      { line: line_index, character: utf16_offset_within_line(line_index, char_offset - line_start) }
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

    def line_content(line_index)
      start = @line_offsets[line_index]
      finish = line_index + 1 < @line_offsets.length ? @line_offsets[line_index + 1] : @text.length
      @text[start...finish].sub(/\r?\n\z/, "")
    end

    def utf16_offset_within_line(line_index, char_offset_in_line)
      units = 0
      line_content(line_index).each_char.with_index do |char, idx|
        break if idx >= char_offset_in_line

        units += self.class.utf16_unit_count(char)
      end
      units
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
