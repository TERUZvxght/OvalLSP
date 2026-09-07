# frozen_string_literal: true

module Ovallsp
  module CodeActions
    # Builds the one text edit that adds `require "<path>"` to a document:
    # after the shebang and magic comments, alphabetically within the first
    # require group when one exists, and in the document's own line ending.
    module RequireInsertion
      MAGIC_COMMENT = /\A#\s*(?:frozen_string_literal|encoding|coding|warn_indent|shareable_constant_value)\s*:/
      EMACS_MAGIC_COMMENT = /\A#.*-\*-.*-\*-/
      REQUIRE_LINE = /\A\s*require\s+["']([^"']+)["']/

      module_function

      def build(source_text, require_path)
        return nil if require_path.nil? || require_path.empty?

        eol = source_text.include?("\r\n") ? "\r\n" : "\n"
        lines = source_text.lines
        chomped = lines.map(&:chomp)
        return nil if chomped.any? { |line| line[REQUIRE_LINE, 1] == require_path }

        line = insertion_line(chomped, require_path)
        text = %(require "#{require_path}") + eol
        if line == lines.length && !lines.empty? && !lines.last.end_with?("\n")
          character = chomped.last.encode("UTF-16LE").bytesize / 2
          edit(line - 1, character, eol + text.chomp(eol))
        else
          edit(line, 0, text)
        end
      end

      def insertion_line(chomped, require_path)
        line = 0
        line += 1 if chomped[line]&.start_with?("#!")
        line += 1 while chomped[line]&.match?(MAGIC_COMMENT) || chomped[line]&.match?(EMACS_MAGIC_COMMENT)

        first_require = chomped.index { |l| l.match?(REQUIRE_LINE) }
        return line unless first_require

        line = first_require
        while (existing = chomped[line]&.[](REQUIRE_LINE, 1))
          return line if require_path < existing

          line += 1
        end
        line
      end

      def edit(line, character, new_text)
        position = { line: line, character: character }
        { range: { start: position, end: position.dup }, new_text: new_text }
      end
    end
  end
end
