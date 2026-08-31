# frozen_string_literal: true

module Ovallsp
  module Diagnostics
    # **A call the caret is still inside is not a call the user wrote.**
    #
    # Typing `.` is how completion is asked for, and on a line that
    # already has something under it that leaves:
    #
    #     a = Article.new
    #     a.
    #     b = "str"
    #
    # Ruby says that is `a.b = "str"`, and the undefined-method check is
    # right to say `Article` has no `b=`. `024.41` is that report, and it
    # reaches every shape the next line can take -- an assignment, a bare
    # name, a `return`, an ordinary call.
    #
    # **No rule about the text can fix it**, because the text of a
    # half-typed call and the text of a deliberate one are the same text.
    # A rule that suppressed "a message on the line below its receiver"
    # would suppress trailing-dot chain style, which is ordinary Ruby:
    #
    #   $ ruby -e '
    #   p "hello".
    #     upcase.
    #     reverse
    #   '
    #   # => "OLLEH"
    #   # ruby 3.4.10
    #
    # The one thing that does distinguish them is the client's own edit,
    # which `didChange` carries and `TextDocument` now keeps. If the last
    # edit ended immediately after a `.` that ends its line, the message
    # on the next line is what the user is in the middle of typing.
    #
    # **This is a decline, and it expires.** The next edit puts the caret
    # somewhere else and the report comes back -- which is right: at that
    # point it is code the user left rather than code being typed. And a
    # document that was only opened has no caret at all, so an opened file
    # says exactly what Ruby says.
    #
    # **Why it is not wider.** The obvious generalisation is "suppress
    # while the caret is at the end of the message too", which would also
    # silence `a.tit` while the user is halfway through `title`. Measured,
    # that shape does reach the user -- typing `a.tit` and pausing
    # publishes one report naming `tit`. It is deliberately left alone,
    # because the two differ in one way that decides it: **`a.` can never
    # be a finished expression, and `a.titel` can.** Suppressing a
    # half-typed *name* would silence a genuine typo for as long as the
    # caret stays on it, which is the whole time someone types one and
    # looks -- the commonest way a typo report is seen at all.
    #
    # `024.57`'s direction was a debounce, written when `didChange`
    # published synchronously. Since 0.2.10 analysis already waits for the
    # input queue to settle, and a *pause* is what settles it -- so the
    # debounce cannot reach this: reading the completion popup is the
    # scenario, and pausing is how it happens.
    module MidEditCall
      module_function

      # The findings a caret-suppression applies to. Only
      # `unknown-method`: the other codes do not name a call's message,
      # and widening this would suppress a syntax error the same keystroke
      # produced, which the user does want to see.
      SUPPRESSED_CODE = "unknown-method"

      def filter(findings, document)
        start = suppressed_start(document)
        return findings unless start

        findings.reject { |finding| finding.code == SUPPRESSED_CODE && finding.range[:start] == start }
      end

      # The position of the message a trailing-dot caret leads to, or nil.
      #
      # Three conditions, and each is doing work: an edit happened, it
      # ended just after a `.`, and that `.` is the last thing on its line.
      # The third is what keeps `a.b` -- a caret mid-identifier in a
      # complete call -- from being suppressed.
      def suppressed_start(document)
        caret = document.last_edit_end
        return nil unless caret&.positive?

        text = document.text
        return nil unless text[caret - 1] == "."

        rest = text[caret..] || ""
        newline = rest.index("\n")
        return nil unless newline && rest[0...newline].strip.empty?

        message_offset = caret + newline + 1 + (rest[(newline + 1)..] || "")[/\A[ \t]*/].length
        return nil if message_offset >= text.length

        document.char_offset_to_position(message_offset)
      end
    end
  end
end
