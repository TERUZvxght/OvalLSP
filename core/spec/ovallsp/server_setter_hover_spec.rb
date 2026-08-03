# frozen_string_literal: true

require "stringio"

# Hovering `name` in `w.name = "y"` asks about the *setter*, `name=`.
# `word_at_position` stops at word characters, so it answered `name` and
# hover described the reader -- "takes no arguments" for a call that takes
# one.
#
# This was harmless while neither existed. 0.1.14 made `attr_accessor`
# declare both, so hover started answering, and answering the wrong one is
# worse than the empty hover it replaced.
#
# Only after an explicit receiver: `x = 1` at the top level is a local
# variable assignment, and its token really is `x`.
RSpec.describe "hover on an assignment target (0.1.15)" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:server) { Ovallsp::Server.new(input: StringIO.new(""), output: StringIO.new, logger: logger) }

  def hover(source, line:, character:)
    uri = "file:///a.rb"
    server.send(:handle_did_open, {
                  textDocument: { uri: uri, languageId: "ruby", version: 1, text: source }
                })
    result = server.send(:hover_result, {
                           textDocument: { uri: uri },
                           position: { line: line, character: character }
                         })
    result && result[:contents] && result[:contents][:value].to_s
  end

  # The receiver needs a knowable type, or hover declines before the word
  # matters at all.
  def source_with(expression)
    "class Widget\n  attr_accessor :name\nend\n\nw = Widget.new\n#{expression}\n"
  end

  it "describes the writer, not the reader, on the left of an assignment" do
    text = hover(source_with('w.name = "y"'), line: 5, character: 3)

    expect(text).to include("name=")
  end

  it "still describes the reader where no assignment follows" do
    text = hover(source_with("w.name"), line: 5, character: 3)

    expect(text.to_s).to include("name")
    expect(text.to_s).not_to include("name=")
  end

  # `==` is a comparison, not an assignment: the call is the reader.
  it "does not read a comparison as an assignment" do
    text = hover(source_with("w.name == 1"), line: 5, character: 3)

    expect(text.to_s).not_to include("name=")
  end

  # `rstrip` crossed newlines, so a comment sentence ending in a period --
  # which is every other line of this repository -- made the *next* line's
  # assignment look receiver-qualified. `LIMIT` became `LIMIT=`, and
  # go-to-definition on it found nothing.
  it "does not read a period at the end of the previous line as a receiver" do
    source = "class Config\n  # The maximum row count.\n  LIMIT = 10\nend\n"
    server.send(:handle_did_open, {
                  textDocument: { uri: "file:///c.rb", languageId: "ruby", version: 1, text: source }
                })
    document = server.instance_variable_get(:@document_store).fetch(uri: "file:///c.rb")

    expect(server.send(:word_at_position, document, { line: 2, character: 4 })).to eq("LIMIT")
  end

  # `=~` is a match, not an assignment.
  it "does not read `=~` as an assignment" do
    text = hover(source_with("w.name =~ /y/"), line: 5, character: 3)

    expect(text.to_s).not_to include("name=")
  end

  # A local variable assignment has no receiver, and its token is the
  # whole name. Without this, "extend the word when `=` follows" would
  # rename every local on the left of an assignment.
  it "does not extend a local variable's name" do
    local_source = "class Widget\n  def run\n    count = 1\n    count\n  end\nend\n"
    text = hover(local_source, line: 2, character: 5)

    expect(text.to_s).not_to include("count=")
  end
  # Accepting the writer's completion should leave `w.name = value`, not
  # `w.name=(value)`. Both run; only one is Ruby anyone writes. The
  # snippet builder has always produced `name(args)` because until 0.1.14
  # no setter was ever a completion candidate.
  describe "the writer's insert text" do
    def snippet_for(name)
      server.send(:handle_did_open, {
                    textDocument: { uri: "file:///b.rb", languageId: "ruby", version: 1,
                                    text: "class Widget\n  attr_accessor :name\n  def plain(a); end\nend\n\nw = Widget.new\nw.\n" }
                  })
      items = server.send(:completion_result, {
                            textDocument: { uri: "file:///b.rb" }, position: { line: 6, character: 2 }
                          })
      items.find { |item| item[:label] == name }
    end

    it "assigns rather than calling with parentheses" do
      expect(snippet_for("name=")[:insertText]).to eq("name = ${1:value}")
    end

    it "leaves an ordinary method's call template alone" do
      expect(snippet_for("plain")[:insertText]).to eq("plain(${1:a})")
    end
  end

end
