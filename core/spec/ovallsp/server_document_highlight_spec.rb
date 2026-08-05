# frozen_string_literal: true

require "stringio"

# Occurrence highlighting -- the boxes an editor draws around the other
# uses of whatever the cursor is on.
#
# It exists because *not* answering is not neutral. With no provider,
# VS Code falls back to matching the word under the cursor as text, and
# `@` is not a word character, so on a scaffolded Rails controller:
#
# - the cursor in `@articles` highlighted the word `articles` inside
#   every `# GET /articles` comment, which is not a variable at all;
# - the cursor in a local named `article` highlighted every `@article`
#   in the file, because `article` is a whole word inside `@article`.
#
# Both were reported from a real editor session. The engine has always
# been able to tell those apart -- rename at the same position edits the
# local's three occurrences and leaves the ivar alone -- so this asks the
# question the same way rename does and answers with what it already
# knows, rather than teaching the client a better word pattern. A word
# pattern cannot distinguish `article` from `@article`; only resolution
# can.
RSpec.describe "Ovallsp::Server textDocument/documentHighlight" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  def highlights(source, line:, character:, uri: "file:///articles_controller.rb")
    input =
      did_open(uri, source) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentHighlight",
        params: { textDocument: { uri: uri }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run
    sent_messages.first[:result]
  end

  # Shortened from the scaffolded controller the report came from, keeping
  # the three things that made it wrong: a comment containing the bare
  # word, a local variable named like the ivar without its sigil, and
  # several uses of each.
  CONTROLLER = <<~RUBY
    class ArticlesController < ApplicationController
      # GET /articles or /articles.json
      def index
        @articles = Article.all
      end

      def show
        article = Article.find(1)
        article
      end

      def create
        @article = Article.new
        @article.save
      end
    end
  RUBY

  it "highlights an instance variable including its sigil, and nothing in a comment" do
    result = highlights(CONTROLLER, line: 3, character: 6)

    expect(result.map { |h| h[:range][:start][:line] }).to eq([3])
    expect(result.first[:range][:start][:character]).to eq(4)
    expect(result.first[:range][:end][:character]).to eq(13)
  end

  # The second screenshot in the report: the cursor was on the local and
  # every `@article` in the file lit up.
  it "does not highlight an instance variable for a local variable of the same name without the sigil" do
    result = highlights(CONTROLLER, line: 7, character: 6)

    expect(result.map { |h| h[:range][:start][:line] }).to contain_exactly(7, 8)
  end

  it "highlights every use of a method, wherever it is called" do
    source = "class Widget\n  def build\n  end\n\n  def run\n    build\n    build\n  end\nend\n"

    result = highlights(source, line: 5, character: 5, uri: "file:///widget.rb")

    expect(result.map { |h| h[:range][:start][:line] }).to include(5, 6)
  end

  it "answers nothing for a position with no symbol under it" do
    expect(highlights("  \n", line: 0, character: 1, uri: "file:///blank.rb")).to eq([])
  end

  it "advertises the capability" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: { rootUri: nil, capabilities: {} }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result][:capabilities][:documentHighlightProvider]).to be(true)
  end
end
