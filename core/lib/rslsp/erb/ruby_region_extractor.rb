# frozen_string_literal: true

module Rslsp
  module Erb
    # Extracts the Ruby code inside `<% %>` / `<%= %>` tags from an ERB
    # template, producing a synthetic Ruby source of the *same length and
    # line count* as the original: every non-code byte (HTML, tag
    # delimiters) is replaced with a space, and newlines are preserved
    # as-is. Every Ruby token therefore keeps its original line/column, so
    # positions computed against this synthetic source map back to the
    # real .erb file without any translation step. `<%# ... %>` comments
    # are blanked out along with the surrounding HTML — no Ruby is
    # extracted from them.
    #
    # Arbitrary template engines (Slim, HAML) and dynamic render strings
    # are out of scope (docs/design/tasks/008-controller-view-propagation.md).
    module RubyRegionExtractor
      TAG_PATTERN = /<%(-|=)?(.*?)-?%>/m

      module_function

      def extract_ruby_source(erb_source)
        result = +""
        cursor = 0

        erb_source.scan(TAG_PATTERN) do |marker, code|
          match = Regexp.last_match
          result << blank(erb_source[cursor...match.begin(0)])
          result << (comment_tag?(erb_source, match.begin(0)) ? blank(match[0]) : blank_wrap(match[0], code))
          cursor = match.end(0)
        end

        result << blank(erb_source[cursor..])
        result
      end

      def comment_tag?(source, tag_start)
        source[tag_start, 3] == "<%#"
      end

      # Keeps `code` at its original byte offset within the full tag,
      # blanking everything else in the tag (the `<%`/`<%=`/`-%>`/`%>`
      # delimiters).
      def blank_wrap(full_tag, code)
        code_offset = full_tag.index(code)
        blank(full_tag[0...code_offset]) + code + blank(full_tag[(code_offset + code.length)..])
      end

      def blank(text)
        return "" if text.nil?

        text.gsub(/[^\n]/, " ")
      end
    end
  end
end
