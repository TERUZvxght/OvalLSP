# frozen_string_literal: true

module Ovallsp
  # The comment block a declaration is documented by (0.2.0).
  #
  # Hover says what a thing *is* and never what it is *for*, though the
  # RDoc/YARD comment is sitting right above the `def`. This reads it back
  # out of the source, because that is where it already lives -- there is
  # no separate documentation index to build or keep fresh.
  module Documentation
    # Lines that sit above a declaration but are not about it: the ones
    # the interpreter and the tools read. Including them puts
    # `frozen_string_literal: true` in the hover for the first method in
    # every file.
    #
    # A directive does not stop the walk -- a comment above one is still
    # documentation -- so this list has to name everything that can sit
    # in that position, not just the first thing found there. A shebang
    # is above the magic comment in every executable Ruby file, and
    # `vim:`/`Emacs`-style modelines and RDoc's own `:markup:`/`:stopdoc:`
    # family keep it company.
    #
    # `\s` after the word, or `:`/`=`, so that a sentence merely
    # beginning with one of them stays prose.
    DIRECTIVE = /
      \A\#!                                                   # a shebang
      | \A\#\s*(
          frozen_string_literal | encoding\s*[:=] | warn_indent
          | shareable_constant_value | rubocop: | -\*-
          | vim:\s | vi:\s | ex:\s | Local\ Variables:
          | :(nodoc|doc|markup|stopdoc|startdoc|enddoc|include|title|main|category|call-seq):
        )
    /x

    module_function

    # The contiguous `#` comment block immediately above line
    # `declaration_line` (0-indexed), as text, or nil when there is none.
    #
    # Contiguity is the whole rule, and it is what makes this safe to
    # read from arbitrary source: a blank line between a comment and a
    # `def` means the comment is about something else, most often the
    # declaration before it.
    def above(text, declaration_line)
      lines = text.to_s.lines
      # A missing line number is a caller that could not locate the
      # declaration at all; the `<= 0` case needs no guard of its own,
      # since the walk below starts at `declaration_line - 1` and stops
      # immediately.
      return nil if declaration_line.nil?

      collected = []
      index = declaration_line - 1
      while index >= 0
        line = lines[index].to_s.strip
        break unless line.start_with?("#")

        collected.unshift(line) unless line.match?(DIRECTIVE)
        index -= 1
      end

      body = collected.map { |line| strip_marker(line) }
      # `#` on its own is a paragraph break inside a block, but a block
      # that is *only* those is not documentation.
      return nil if body.all? { |line| line.strip.empty? }

      body.join("\n").strip
    end

    # `# text` -> `text`, `#text` -> `text`, `#` -> ``. The single space
    # after the marker is a convention, not a guarantee, so only one is
    # removed -- taking more would eat the indentation that makes a code
    # example in a comment readable.
    def strip_marker(line)
      without_hash = line.sub(/\A#/, "")
      without_hash.start_with?(" ") ? without_hash[1..] : without_hash
    end
  end
end
