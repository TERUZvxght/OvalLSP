# frozen_string_literal: true

require "stringio"

# What "a call with no receiver" means, asked of the parse tree rather
# than of the characters to the left of the cursor.
#
# 0.2.0 gave go-to-definition and signature help a receiverless reading
# and 0.2.1 gave hover one, all three gated on the same text test: is
# there a `.` in front of this word. That test says yes to every word in
# the file. Resting on prose inside a comment, on the contents of a
# string, on a parameter name in a `def`, or on a local variable that
# happens to share a name with a method opened a popup asserting a call
# that is not there -- with a signature, an origin, a "Defined:" link
# leading away from the cursor, and the method's doc comment.
#
# Ruby's own rule is the second half of this: a local variable in scope
# always wins over a same-named method, which is why `article = ...`
# inside a class with `def article` is not ambiguous at all. The engine
# already knew -- rename at that position edits the local and leaves the
# method alone -- and only these three readers did not ask.
#
# `ParserService` already records every call site with its message range
# and whether it had a receiver, so the question has an exact answer and
# does not need a better heuristic.
RSpec.describe "Ovallsp::Server receiverless readings" do
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

  def ask(method, source, line:, character:, uri: "file:///probe.rb")
    input =
      did_open(uri, source) +
      frame(
        jsonrpc: "2.0", id: 1, method: method,
        params: { textDocument: { uri: uri }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run
    sent_messages.first[:result]
  end

  def hover_text(source, line:, character:)
    result = ask("textDocument/hover", source, line: line, character: character)
    result && result[:contents] && result[:contents][:value]
  end

  # Every position below is a word that matches `balance`, a real method
  # of this class with a doc comment and a parameter -- so anything that
  # answers about the method rather than about the position is visible in
  # the popup rather than merely wrong in principle.
  SOURCE = <<~RUBY
    class Account
      # Returns the balance in cents.
      def balance(currency)
        currency
      end

      def report(balance)
        balance
      end

      def summary
        balance = 42
        balance
        note = "balance is high"
        balance(:usd)
      end
    end
  RUBY

  describe "hover" do
    it "answers about a local variable, not about a method of the same name" do
      expect(hover_text(SOURCE, line: 12, character: 5)).to eq("Integer")
    end

    it "says nothing about a method for prose inside a comment" do
      expect(hover_text(SOURCE, line: 1, character: 18).to_s).to be_empty
    end

    it "answers about the string, not about a method named in it" do
      expect(hover_text(SOURCE, line: 13, character: 15)).to eq("String")
    end

    it "says nothing about a method for a parameter name in a def" do
      expect(hover_text(SOURCE, line: 6, character: 15).to_s).to be_empty
    end

    # The reading itself, which all of the above are the boundary of:
    # a real call with no receiver still answers with its parameters.
    it "still answers a real call written with no receiver" do
      expect(hover_text(SOURCE, line: 14, character: 6)).to include("balance(currency)")
    end
  end

  describe "go to definition" do
    it "does not jump to a method from a local variable of the same name" do
      expect(ask("textDocument/definition", SOURCE, line: 12, character: 5)).to eq([])
    end

    it "does not jump from prose inside a comment" do
      expect(ask("textDocument/definition", SOURCE, line: 1, character: 18)).to eq([])
    end

    it "still jumps from a real call written with no receiver" do
      locations = ask("textDocument/definition", SOURCE, line: 14, character: 6)

      expect(locations.map { |l| l[:range][:start][:line] }).to include(2)
    end
  end
  # A Ruby method name can end in `!` or `?`, and the text scans that find
  # the word under the cursor stopped at those characters -- so the name
  # looked up was `destroy`, not `destroy!`. Hover opened an empty popup,
  # F12 said "No definition found", and signature help returned nothing
  # at all, on `save!`, `valid?`, `destroy!`, `update!` -- the names a
  # Rails controller is mostly made of. Completion offers them, so a user
  # is led straight into it.
  #
  # Rows H5, D1 and S1 all read PASS, and Find References, Rename and
  # occurrence highlighting were unaffected throughout, because they read
  # the parser's call records rather than scanning text.
  describe "a method whose name ends in `!` or `?`" do
    BANG_SOURCE = <<~RUBY
      class Account
        def refresh!(currency)
          currency
        end

        def stale?
          false
        end

        def run
          refresh!(:usd)
          stale?
        end
      end
    RUBY

    def bang(method, line:, character:)
      input =
        did_open("file:///bang.rb", BANG_SOURCE) +
        frame(
          jsonrpc: "2.0", id: 1, method: method,
          params: { textDocument: { uri: "file:///bang.rb" }, position: { line: line, character: character } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run
      sent_messages.first[:result]
    end

    it "hovers it with its parameters" do
      result = bang("textDocument/hover", line: 10, character: 6)

      expect(result[:contents][:value]).to include("refresh!(currency)")
    end

    it "hovers a predicate too" do
      expect(bang("textDocument/hover", line: 11, character: 6)[:contents][:value]).to include("stale?")
    end

    it "jumps to its declaration" do
      locations = bang("textDocument/definition", line: 10, character: 6)

      expect(locations.map { |l| l[:range][:start][:line] }).to include(1)
    end

    it "offers signature help inside its arguments" do
      labels = bang("textDocument/signatureHelp", line: 10, character: 14)[:signatures].map { |s| s[:label] }

      expect(labels).to include("refresh!(currency)")
    end
  end
end
