# frozen_string_literal: true

require_relative "../text_document"

module Ovallsp
  module Index
    # Converts Prism::Location objects to LSP ranges. Prism reports
    # `start_line` as 1-based and `start_column`/`end_column` as **byte**
    # offsets within that line, while LSP wants 0-based lines and UTF-16
    # code unit offsets — three different units, none of which line up for
    # non-ASCII source.
    module SourceLocation
      module_function

      def to_range(location, lines)
        {
          start: to_position(location.start_line, location.start_column, lines),
          end: to_position(location.end_line, location.end_column, lines)
        }
      end

      def to_position(prism_line, byte_column, lines)
        line_text = lines[prism_line - 1] || ""
        { line: prism_line - 1, character: byte_offset_to_utf16(line_text, byte_column) }
      end

      def byte_offset_to_utf16(line, byte_offset)
        return 0 if byte_offset <= 0

        bytes = 0
        units = 0
        line.each_char do |char|
          return units if bytes >= byte_offset

          bytes += char.bytesize
          units += Ovallsp::TextDocument.utf16_unit_count(char)
        end
        units
      end
    end
  end
end
