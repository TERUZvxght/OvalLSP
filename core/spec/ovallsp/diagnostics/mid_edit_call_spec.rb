# frozen_string_literal: true

# `024.41`. Typing a `.` is how completion is asked for, and it leaves a
# document whose next line reads as the message of that call:
#
#     a = Article.new
#     a.
#     b = "str"
#
# Ruby says that is `a.b = "str"`, and the engine is right to say
# `Article` has no `b=`. **The text does not say the user is mid-edit** —
# so no static rule can tell this apart from the same code written
# deliberately, and one that suppressed "a message on a line below its
# receiver" would suppress trailing-dot chain style, which is ordinary
# Ruby:
#
#   $ ruby -e '
#   p "hello".
#     upcase.
#     reverse
#   '
#   # => "OLLEH"
#   # ruby 3.4.10
#
# The one thing that does say it is the client's own edit. `didChange`
# carries the range it replaced, this server takes incremental sync, and
# `TextDocument` threw the position away. It keeps the end of the last
# edit now, and a call whose dot sits exactly there is one the user is
# still typing.
#
# **The rule is deliberately about the caret and not about the text.**
# Move on and the report comes back, because the next edit puts the caret
# somewhere else — which is right: at that point it is code the user
# left, not code being typed.
RSpec.describe "an unknown-method report about the call the caret is inside" do
  let(:article) { "class Article\n  def title = \"t\"\nend\n" }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def messages_for(uri, input)
    output = StringIO.new
    logger = instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    seen = []
    begin
      loop { seen << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    # The uri arrives as a *value*, so it is a String -- comparing it to a
    # Symbol matched nothing, every suppression example passed with an
    # empty list, and only the two controls said so.
    seen.select { |m| m[:method] == "textDocument/publishDiagnostics" && m.dig(:params, :uri).to_s == uri }
        .flat_map { |m| m.dig(:params, :diagnostics) || [] }
        .select { |d| d[:code] == "unknown-method" }
  end

  # The whole scenario, driven the way it happens: the buffer already has
  # a next line, and the user types the `.` that asks for completion.
  def report_after_typing_dot(rest, uri: "file:///w/app.rb")
    before = "a = Article.new\na\n#{rest}"
    input =
      frame(jsonrpc: "2.0", id: 0, method: "initialize",
            params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///w/article.rb", text: article, version: 1,
                                      languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: before, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: 2 },
                      contentChanges: [{ range: { start: { line: 1, character: 1 },
                                                  end: { line: 1, character: 1 } },
                                         text: "." }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
    messages_for(uri, input)
  end

  # The six shapes `024.41` re-measured. `puts 1` is not in the list
  # because `Kernel#puts` really is a method `Article` has, so it was
  # never reported.
  ["b = \"str\"\n", "value\n", "return 1\n", "other_thing(1)\n"].each do |rest|
    it "says nothing about #{rest.strip.inspect}, which the caret is still inside" do
      expect(report_after_typing_dot(rest)).to be_empty
    end
  end

  # **The control, and it is the reason this is a rule about the caret.**
  # The same text, opened rather than typed: no edit, so no caret, and the
  # engine says what Ruby says. Without this, "never report a call whose
  # message is on the next line" passes every example above and silences
  # trailing-dot chain style for everyone.
  it "still reports the same text when no edit put the caret at the dot" do
    uri = "file:///w/opened.rb"
    input =
      frame(jsonrpc: "2.0", id: 0, method: "initialize",
            params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///w/article.rb", text: article, version: 1,
                                      languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: "a = Article.new\na.\nb = \"str\"\n", version: 1,
                                      languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(messages_for(uri, input).map { |d| d[:message] })
      .to eq(["Article has no method named `b=`"])
  end

  # And the second control: an edit that lands somewhere else must not
  # suppress anything. This is what stops the rule from becoming "any
  # document that was edited reports nothing".
  it "still reports once the caret has moved on" do
    uri = "file:///w/moved.rb"
    before = "a = Article.new\na\nb = \"str\"\n"
    input =
      frame(jsonrpc: "2.0", id: 0, method: "initialize",
            params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///w/article.rb", text: article, version: 1,
                                      languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: before, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: 2 },
                      contentChanges: [{ range: { start: { line: 1, character: 1 },
                                                  end: { line: 1, character: 1 } },
                                         text: "." }] }) +
      # a second edit, on another line: the caret leaves the dot
      frame(jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: 3 },
                      contentChanges: [{ range: { start: { line: 2, character: 9 },
                                                  end: { line: 2, character: 9 } },
                                         text: " " }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(messages_for(uri, input).map { |d| d[:message] })
      .to include("Article has no method named `b=`")
  end

  # The third control, and the one that pins the *dot* rather than the
  # end of the line. The edit puts a space after an existing `.`, so the
  # caret ends the line and the next line is still a reported call — but
  # the character before the caret is a space, not a dot. Without that
  # condition every edit that ends a line would suppress whatever the
  # next line reports, which is most of the check.
  it "still reports when the caret ends a line but not at a dot" do
    uri = "file:///w/space.rb"
    before = "a = Article.new\na.\nb = \"str\"\n"
    input =
      frame(jsonrpc: "2.0", id: 0, method: "initialize",
            params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///w/article.rb", text: article, version: 1,
                                      languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: before, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: 2 },
                      contentChanges: [{ range: { start: { line: 1, character: 2 },
                                                  end: { line: 1, character: 2 } },
                                         text: " " }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(messages_for(uri, input).map { |d| d[:message] })
      .to include("Article has no method named `b=`")
  end

  # The fourth control, and the one that pins the *end of the line*. Two
  # dots on one line, and the caret is at the first:
  #
  #     a.other.
  #     b = "str"
  #
  # The report belongs to the trailing dot, which the user is not editing
  # — they are editing the one in the middle. Without the end-of-line
  # condition the caret's dot would reach forward to the next line anyway
  # and suppress a report the edit had nothing to do with.
  #
  # `Other` rather than a core class on purpose: with a `String` receiver
  # nothing is reported at all (`024.129`), so the fixture could not tell
  # a suppression from a decline.
  it "still reports a trailing dot's call when the caret is at an earlier dot on the line" do
    uri = "file:///w/two.rb"
    base = "class Other\nend\nclass Article\n  def other = Other.new\nend\n"
    before = "a = Article.new\naother.\nb = \"str\"\n"
    input =
      frame(jsonrpc: "2.0", id: 0, method: "initialize",
            params: { processId: nil, rootUri: "file:///w", capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///w/base.rb", text: base, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: before, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "textDocument/didChange",
            params: { textDocument: { uri: uri, version: 2 },
                      contentChanges: [{ range: { start: { line: 1, character: 1 },
                                                  end: { line: 1, character: 1 } },
                                         text: "." }] }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(messages_for(uri, input).map { |d| d[:message] })
      .to eq(["Other has no method named `b=`"])
  end
end
