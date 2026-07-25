# frozen_string_literal: true

require_relative "../text_document"

module Ovallsp
  module Erb
    # Extracts the Ruby code inside `<% %>` / `<%= %>` tags from an ERB
    # template, producing a synthetic Ruby source that preserves every
    # line's **UTF-16 code unit count** (not its Ruby character count, and
    # not its byte count) relative to the original: each non-code
    # character (HTML, tag delimiters) is replaced with as many ASCII
    # spaces as that character occupies in UTF-16 — one for any BMP
    # character (Latin, CJK, ...) and two for an astral character (most
    # emoji), matching `Ovallsp::TextDocument.utf16_unit_count`. `\n`/`\r`
    # pass through unchanged.
    #
    # This is the invariant that actually matters: positions everywhere in
    # this codebase (and in the LSP protocol itself) are UTF-16 code
    # units, computed by converting Prism's byte-offset locations against
    # a line's own text (`Index::SourceLocation.byte_offset_to_utf16`). As
    # long as the synthetic line's UTF-16 length matches the original
    # line's at every point, that conversion produces the same UTF-16
    # position on both sides — even though the synthetic line's *byte*
    # length and *character* length can now legitimately differ from the
    # original's (an astral emoji is 1 Ruby character / 4 bytes / 2 UTF-16
    # units in the original; its blanked replacement is 2 Ruby characters
    # / 2 bytes / 2 UTF-16 units — same UTF-16 length, different
    # length/bytesize). A byte-count-preserving or char-count-preserving
    # blank (Task 008.5's implementation) silently drifted by one UTF-16
    # unit per astral character on a line, shifting every position after
    # it (docs/design/tasks/008.6-agent-and-index-hardening.md). `<%# ... %>`
    # comments are blanked out along with the surrounding HTML — no Ruby
    # is extracted from them.
    #
    # Adjacent tags on the same rendered line (`<%= @a %><%= @b %>`, or
    # separated only by HTML: `<%= @a %><span><%= @b %>`) get a `;`
    # inserted immediately before the second tag's code — each tag is its
    # own independent Ruby statement at render time regardless of what's
    # between them, and without a separator the two extracted expressions
    # would sit next to each other with only blanked-out whitespace
    # between them, which Prism rejects as a syntax error
    # (docs/design/tasks/008.5-runtime-and-index-corrections.md). The
    # semicolon replaces the single blanked space standing in for the
    # tag's own closing delimiter character, which is always ASCII (1
    # UTF-16 unit), so the UTF-16 length invariant above is unaffected.
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

        result = +""
        text.each_char do |char|
          result << (char == "\n" || char == "\r" ? char : " " * Ovallsp::TextDocument.utf16_unit_count(char))
        end
        result
      end
    end
  end
end
