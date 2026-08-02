# frozen_string_literal: true

# Semantic highlighting (0.2.0).
#
# Ruby's `foo` is ambiguous between a local variable and a method call on
# self. A grammar has no scope and cannot tell them apart; the engine
# parses the file and can.
RSpec.describe Ovallsp::SemanticTokens do
  def document(text, uri: "file:///a.rb", language_id: "ruby")
    Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: language_id)
  end

  def tokens(text, **options)
    described_class.collect(document(text, **options))
  end

  def types_on_line(text, line, **options)
    tokens(text, **options).select { |t| t.line == line }.map(&:type)
  end

  ERB_URI = "file:///app/views/users/show.html.erb"

  # The headline: the same three characters, two different things,
  # distinguished only by whether an assignment came first.
  it "tells a local variable read from a receiverless method call" do
    text = <<~RUBY
      def run
        value = 1
        value
        compute
      end
    RUBY

    expect(types_on_line(text, 2)).to eq([:variable])
    expect(types_on_line(text, 3)).to eq([:method])
  end

  it "marks an instance variable as a property" do
    expect(types_on_line("@user = 1\n@user\n", 1)).to eq([:property])
  end

  it "marks a method's parameters" do
    text = "def run(first, second = 2, third:)\nend\n"

    expect(types_on_line(text, 0).count(:parameter)).to eq(3)
  end

  it "marks a constant read as a class" do
    expect(types_on_line("Widget\n", 0)).to eq([:class])
  end

  it "marks a module name as a namespace, not a class" do
    expect(types_on_line("module Billing\nend\n", 0)).to eq([:namespace])
  end

  # The template's Ruby lives in its tags. Parsing the raw template means
  # parsing HTML as Ruby, which is how a partial's local was once read as
  # a String.
  it "reports tokens for an ERB template's Ruby regions" do
    text = "<p><%= @user %></p>\n"

    expect(types_on_line(text, 0, uri: ERB_URI, language_id: "erb")).to eq([:property])
  end

  it "places an ERB token at its position in the template, not in the extracted Ruby" do
    token = tokens("<p><%= @user %></p>\n", uri: ERB_URI, language_id: "erb").first

    expect(token.line).to eq(0)
    expect(token.character).to eq(7)
  end

  # VS Code assigns no built-in language id to `.erb`, so the extension
  # registers those files by pattern with no id at all -- a template
  # arrives with whatever id the editor guessed, or none. Keying on it
  # means producing nothing for exactly the files this advertises.
  it "recognises a template by its name, not by the language id it arrives with" do
    expect(types_on_line("<p><%= @user %></p>\n", 0, uri: ERB_URI, language_id: "html")).to eq([:property])
  end

  # A file mid-edit does not parse, and a partial tree yields tokens above
  # the break and none below it -- which reads as highlighting that keeps
  # falling off as you type.
  it "reports nothing for a file that does not parse, rather than half of it" do
    expect(tokens("value = 1\nvalue\ndef\n")).to be_empty
  end

  it "counts a character before the token in UTF-16 units, as the protocol requires" do
    token = tokens("# 日本語\nvalue = 1\n").find { |t| t.type == :variable }

    expect(token.line).to eq(1)
    expect(token.character).to eq(0)
  end

  describe ".encode" do
    it "emits five integers per token" do
      data = described_class.encode(document("value = 1\nvalue\n"))

      expect(data.size).to eq(described_class.collect(document("value = 1\nvalue\n")).size * 5)
    end

    # The protocol's deltas are what make the array compact, and getting
    # them wrong shifts every token after the first. Both fixtures need a
    # *third* position: with two tokens starting from zero, a relative
    # delta and an absolute one are the same number.
    it "encodes each line relative to the line of the token before it" do
      data = described_class.encode(document("value = 1\nvalue\n\nvalue\n"))

      expect(data.each_slice(5).map(&:first)).to eq([0, 1, 2])
    end

    it "measures a second token on the same line from the start of the first" do
      data = described_class.encode(document("  first = second\n"))

      expect(data[0, 2]).to eq([0, 2])
      expect(data[5, 2]).to eq([0, 8])
    end

    it "emits nothing for a file with no tokens" do
      expect(described_class.encode(document("\n"))).to eq([])
    end
  end

  # Prism visits a call's *message* before descending into its receiver,
  # so the tree hands these back in the opposite order to the one the
  # protocol requires -- and an out-of-order token makes every delta after
  # it negative.
  it "sorts tokens by position, not by the order the tree yields them" do
    positions = tokens("widget = 1\nwidget.charge\n").select { |t| t.line == 1 }.map(&:character)

    expect(positions).to eq(positions.sort)
    expect(positions).to eq([0, 7])
  end

  # `class Foo::\n          Bar` is valid Ruby and its constant path spans
  # two lines. The protocol's `length` is within one line, so subtracting
  # the two columns measures nothing real -- and with the continuation
  # indented far enough the result is *positive*, so it survives the
  # length check and ships a token covering seven characters of a
  # three-character name. `Foo` itself is still marked, on its own line.
  it "does not encode a name that spans two lines as if it were on one" do
    on_first_line = tokens("class Foo::\n          Bar\nend\n").select { |t| t.line.zero? }

    expect(on_first_line.map(&:length)).to eq([3])
  end

  # `list[idx]`'s message location spans the brackets *and the index
  # expression*, so marking it produces a token that contains the one for
  # `idx`. The protocol requires tokens not to overlap, and this is
  # `hash[key]` -- as ordinary as Ruby gets.
  it "does not mark an index call, whose message contains the index itself" do
    positions = tokens("idx = 0\nlist = []\nlist[idx]\n").select { |t| t.line == 2 }

    expect(positions.map { |t| [t.character, t.length] }).to eq([[0, 4], [5, 3]])
  end

  # The class comment says it does not re-colour what the grammar already
  # gets right; an operator is exactly that.
  it "does not mark an operator as a method call" do
    expect(types_on_line("a = 1\nb = 2\na + b\n", 2)).to eq(%i[variable variable])
  end

  # Index into the legend *is* the token type on the wire, so reordering
  # it silently recolours every file in every editor already running.
  it "keeps the legend order it published" do
    expect(described_class::LEGEND).to eq(%w[variable parameter property method class namespace])
  end

  # The same identifier was classified on one line and left unclassified
  # on the next, inside one method: `sum = 1` marked and `sum += 1` not,
  # `@memo = 1` marked and `@memo ||= 1` not, and `*rest`/`**kw`/`&blk`
  # never. A user sees one variable change colour mid-method.
  {
    "an operator assignment" => ["sum = 1\nsum += 1\n", "variable", 2],
    "an or-assignment to an ivar" => ["@memo = 1\n@memo ||= 2\n", "property", 2],
    "a multiple assignment" => ["a, b = 1, 2\n", "variable", 2],
    "a splat parameter" => ["def go(*rest)\nend\n", "parameter", 1],
    "a double-splat parameter" => ["def go(**kw)\nend\n", "parameter", 1],
    "a block parameter" => ["def go(&blk)\nend\n", "parameter", 1]
  }.each do |description, (source, type, count)|
    it "classifies #{description}" do
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      types = described_class.collect(document).map { |token| token.type.to_s }

      expect(types.count(type)).to be >= count
    end
  end

  # The token is the *name*, not the statement. `node.location` for an
  # operator write is the whole `sum += 1`, which overlaps the token for
  # the `sum` on its right-hand side -- and overlapping tokens are a
  # protocol violation, not a rendering preference.
  it "marks the name in an operator assignment, not the whole statement" do
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", version: 1, language_id: "ruby",
                                         text: "sum = 0\nsum += 1\n@memo ||= sum\n")

    lengths = described_class.collect(document).map { |token| token.length }

    expect(lengths).to all(be <= 5)
  end

  # A new line resets the column to absolute. Every other fixture here
  # either keeps every token at column 0 or keeps them all on one line,
  # and in both of those the absolute and relative numbers are the same
  # -- so a later line starting left of the previous line's last token is
  # what tells them apart, and produces a negative delta if it is wrong.
  it "encodes the first token of a line as an absolute column" do
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", version: 1, language_id: "ruby",
                                         text: "  first = second\nvalue = 1\n")

    data = described_class.encode(document)

    expect(data.each_slice(5).map { |token| token[1] }).to all(be >= 0)
    expect(data.each_slice(5).to_a.last[1]).to eq(0)
  end
end
