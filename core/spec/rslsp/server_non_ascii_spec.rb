# frozen_string_literal: true

require "stringio"

# End-to-end (full Server dispatch, not a single unit) coverage for
# non-ASCII source content, per Task 008.5's explicit requirement that
# Japanese comments/strings, emoji, and other multibyte content preceding
# a query position must never shift which node -- or which declaration --
# a request resolves to. TextDocument/LocalInferencer's own unit specs
# already cover the underlying byte/char/UTF-16 offset math in isolation;
# this file exists to prove the full request pipeline (parsing ->
# WorkspaceIndex -> LocalInferencer -> LSP response) is wired correctly
# end to end (docs/design/tasks/008.5-runtime-and-index-corrections.md).
RSpec.describe "Rslsp::Server non-ASCII position handling (Task 008.5)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Rslsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Rslsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  # The exact fixture content Task 008.5 specifies: a Japanese comment, a
  # string containing Japanese text plus an astral (2-UTF-16-code-unit)
  # emoji, a `User.new` assignment, and a bare reference -- each on its
  # own line so a position-shift bug reliably lands on the wrong node.
  # Top-level (not class/method-wrapped): LocalInferencer#infer_at only
  # descends into a bare top-level StatementsNode/DefNode, matching every
  # other local_inferencer_spec.rb fixture -- traversing into a ClassNode
  # is a separate, pre-existing scope boundary this task doesn't touch.
  FIXTURE_SOURCE = <<~RUBY
    # 日本語コメントです
    label = "日本語😀"
    user = User.new
    user
  RUBY

  it "resolves rslsp/explainType to User (not shifted by the preceding Japanese comment/string) on the bare `user` line" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: FIXTURE_SOURCE, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 3, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User")
  end

  it "resolves rslsp/explainType on the line containing the emoji itself, past the emoji's 2 UTF-16 code units" do
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: FIXTURE_SOURCE, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
        params: { textDocument: { uri: "file:///a.rb" }, position: { line: 1, character: 2 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "String")
  end

  it "documentSymbol reports the correct 0-based line for a class declared after Japanese/emoji lines" do
    source = "# 日本語コメントです\nlabel = \"日本語😀\"\nclass Widget\nend\n"
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///a.rb", text: source, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: "file:///a.rb" } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    symbols = sent_messages.first[:result]
    widget = symbols.find { |s| s[:name] == "Widget" }

    expect(widget[:range][:start][:line]).to eq(2)
  end

  it "textDocument/definition finds a class declared after a Japanese-commented, emoji-containing file" do
    referencing_source = <<~RUBY
      # 日本語コメントです
      # "日本語😀" というコメントも含む
      widget = Widget.new
    RUBY

    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///widget.rb", text: "class Widget\nend\n", version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///use_widget.rb", text: referencing_source, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///use_widget.rb" }, position: { line: 2, character: 10 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    locations = sent_messages.first[:result]
    expect(locations).to include(
      uri: "file:///widget.rb", range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } }
    )
  end

  describe "ERB position correspondence with non-ASCII content" do
    it "keeps Ruby code recoverable alongside Japanese/emoji HTML content" do
      source = "<p>日本語😀</p><%= @user.name %>\n"

      extracted = Rslsp::Erb::RubyRegionExtractor.extract_ruby_source(source)
      offset = source.index("@user")

      expect(offset).to be > 0 # sanity: the Japanese/emoji text really does precede the code
      # The astral emoji makes the *character*-offset invariant this test
      # used to assert (Task 008.5) impossible to hold simultaneously with
      # UTF-16 alignment (Task 008.6) -- `extracted` is UTF-16-aligned,
      # not character-offset-aligned, with the original, so recover the
      # token by content rather than by the original's character offset.
      expect(extracted).to include("@user.name")
      expect(extracted.count("\n")).to eq(source.count("\n"))
      expect(Prism.parse(extracted).errors).to be_empty
    end

    # Task 008.6: end to end through the real Server dispatch, at the
    # exact LSP Position (UTF-16 code units) a real client would send —
    # not a Ruby character count — proving the astral-emoji fix holds all
    # the way from didOpen through rslsp/explainType, not just inside the
    # extractor in isolation.
    it "resolves rslsp/explainType at the correct UTF-16 Position after several astral emoji earlier on the same .erb line" do
      # 5 astral emoji before the tag: a per-character drift big enough
      # (5 UTF-16 units) to push a naive char-count-preserving blank
      # *past* the 4-character `user` token entirely if the client's LSP
      # Position (computed from the real, UTF-16 document) were mapped
      # against such a drifted synthetic source -- one or two emoji can
      # drift by less than the target token's own width and still
      # (mis)land inside it by coincidence, which wouldn't actually catch
      # a regression here.
      source = "<p>#{"\u{1F600}" * 5}</p><%= user = User.new; user %>\n"
      input =
        frame(
          jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: "file:///view.html.erb", text: source, version: 1, languageId: "erb" } }
        ) +
        frame(
          jsonrpc: "2.0", id: 1, method: "rslsp/explainType",
          params: { textDocument: { uri: "file:///view.html.erb" }, position: { line: 0, character: 38 } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run

      expect(sent_messages.first[:result]).to eq(type: "User")
    end
  end
end
