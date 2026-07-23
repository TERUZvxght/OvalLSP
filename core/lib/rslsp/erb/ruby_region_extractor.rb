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
    # Adjacent tags on the same rendered line (`<%= @a %><%= @b %>`, or
    # separated only by HTML: `<%= @a %><span><%= @b %>`) get a `;`
    # inserted immediately before the second tag's code — each tag is its
    # own independent Ruby statement at render time regardless of what's
    # between them, and without a separator the two extracted expressions
    # would sit next to each other with only blanked-out whitespace
    # between them, which Prism rejects as a syntax error
    # (docs/design/tasks/008.5-runtime-and-index-corrections.md). The
    # semicolon replaces one blanked character, so the byte length (and
    # therefore every position mapping) is unaffected.
    #
    # Arbitrary template engines (Slim, HAML) and dynamic render strings
    # are out of scope (docs/design/tasks/008-controller-view-propagation.md).
    module RubyRegionExtractor
      TAG_PATTERN = /<%(-|=)?(.*?)-?%>/m

      module_function

      def extract_ruby_source(erb_source)
        result = +""
        cursor = 0
        needs_separator = false

        erb_source.scan(TAG_PATTERN) do |_marker, code|
          match = Regexp.last_match
          gap = erb_source[cursor...match.begin(0)]
          result << blank(gap)

          same_line_as_previous_code = needs_separator && !gap.include?("\n")

          if comment_tag?(erb_source, match.begin(0))
            result << blank(match[0])
          else
            result << blank_wrap(match[0], code, needs_semicolon: same_line_as_previous_code)
            needs_separator = true
          end

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
      # delimiters). When `needs_semicolon` is set, the last blanked
      # character immediately before `code` becomes `;` instead of a
      # space.
      def blank_wrap(full_tag, code, needs_semicolon: false)
        code_offset = full_tag.index(code)
        prefix = blank(full_tag[0...code_offset])
        prefix = "#{prefix[0..-2]};" if needs_semicolon && !prefix.empty?

        prefix + code + blank(full_tag[(code_offset + code.length)..])
      end

      def blank(text)
        return "" if text.nil?

        text.gsub(/[^\n]/, " ")
      end
    end
  end
end
