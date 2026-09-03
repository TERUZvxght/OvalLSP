# frozen_string_literal: true

require "stringio"

# What it means for the cursor to be "on" a declaration.
#
# A `def`'s recorded range spans its whole body, and the shared lookup
# behind Find References, Rename and occurrence highlighting fell back to
# the smallest declaration *containing* the position. Every position
# inside a method therefore resolved to the method itself: a word in a
# comment, the contents of a string, a bare number, the `def` keyword, the
# `end`, a parameter name.
#
# Find References and F2 both read it, so a click on a word in a comment
# offered to rename the method around it. Occurrence highlighting would
# have made it continuous; that capability was deferred to 0.3.0 and
# shipped there, so the readers are no longer the two this sentence was
# written for. `#symbol_id_and_range_at` now has six call sites across
# five capabilities -- show type evidence, Find References,
# documentHighlight, prepareCallHierarchy and Rename (prepare and
# rename) -- and this rule stays because every one of them is wrong
# without it.
#
# The rule is that the cursor must be on the declaration's *name*. Fixed
# here rather than in each reader, because all three had it and a fourth
# would have inherited it.
RSpec.describe "Ovallsp::Server declarations under the cursor" do
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

  def ask(method, line:, character:, extra: {})
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///probe.rb", text: DECLARATION_POSITION_SOURCE, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: method,
        params: { textDocument: { uri: "file:///probe.rb" },
                  position: { line: line, character: character } }.merge(extra)
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run
    sent_messages.first[:result]
  end

  # Named for this file: a constant declared inside `RSpec.describe` is
  # defined at top level, so a generic name collides silently with
  # another spec file's -- this file passed alone and used
  # `server_receiverless_spec.rb`'s fixture when the whole suite ran.
  DECLARATION_POSITION_SOURCE = <<~RUBY
    class Probe
      def run(first)
        # run is mentioned here
        note = "run again"
        42
        first
      end

      def caller_of_run
        run(1)
      end
    end
  RUBY

  # line 1 is `  def run(first)`; `run` starts at 6.
  {
    "a word inside a comment" => [2, 6],
    "the contents of a string" => [3, 14],
    "a bare number" => [4, 4],
    "the `def` keyword" => [1, 3],
    "the `end` that closes the method" => [6, 3]
  }.each do |description, (line, character)|
    it "does not resolve #{description} to the enclosing method" do
      expect(ask("textDocument/prepareRename", line: line, character: character)).to be_nil
    end
  end

  it "still resolves the declaration's own name" do
    result = ask("textDocument/prepareRename", line: 1, character: 7)

    expect(result[:range][:start][:line]).to eq(1)
  end

  # The same fallback, and the reason it was worth fixing at the source:
  # F2 on a word in a comment offered to rename the method around it.
  it "refuses to rename from a word inside a comment" do
    result = ask("textDocument/rename", line: 2, character: 6, extra: { newName: "renamed" })

    expect(result).to be_nil
  end

  it "refuses prepareRename from a word inside a comment" do
    expect(ask("textDocument/prepareRename", line: 2, character: 6)).to be_nil
  end

  it "still renames from the declaration's own name" do
    result = ask("textDocument/rename", line: 1, character: 7, extra: { newName: "renamed" })

    expect(result[:changes]["file:///probe.rb".to_sym] || result[:changes]["file:///probe.rb"]).not_to be_empty
  end
  # The 0.2.1 changelog says hover, go to definition *and signature help*
  # stopped answering about a method for something that is not a call,
  # and named a parameter name in a `def` as one of the positions. Two of
  # the three did; signature help kept answering, because the cursor is
  # inside the `def`'s own parentheses and the scan that finds a call
  # cannot tell those from a call's.
  it "offers no signature help from inside a def's parameter list" do
    expect(ask("textDocument/signatureHelp", line: 1, character: 12)[:signatures]).to be_empty
  end

  # This example asserted `be_empty` at line 5 -- a bare local, not a call
  # and not inside any argument list -- so it passed with signature help
  # working and passed with signature help deleted. It was the only
  # counterweight to the `def` guard two examples above, which left that
  # guard's direction untested: nothing failed if it started refusing
  # every call in the file.
  it "still offers signature help from inside a real call's arguments" do
    result = ask("textDocument/signatureHelp", line: 9, character: 8)

    expect(result[:signatures].map { |signature| signature[:label] }).to include("run(first)")
  end

  # The `def` guard reads the characters before the name, and a Ruby
  # method name can end in `!` or `?` -- which stopped that scan dead, so
  # `def save!(a|)` answered with the method being *declared*. `def self.`
  # missed the same guard for a different reason: the regex anchors on
  # `def\s+`, and `self.` sits between.
  {
    "a bang" => ["def bang!(beta)", 15],
    "a question mark" => ["def query?(gamma)", 16],
    "a singleton receiver" => ["def self.built(delta)", 20]
  }.each do |description, (declaration, character)|
    it "offers no signature help inside the parameter list of a def with #{description}" do
      source = "class Probe\n  #{declaration}\n  end\nend\n"
      input =
        frame(
          jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: "file:///d.rb", text: source, version: 1, languageId: "ruby" } }
        ) +
        frame(
          jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
          params: { textDocument: { uri: "file:///d.rb" }, position: { line: 1, character: character } }
        ) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run

      expect(sent_messages.first[:result][:signatures]).to be_empty
    end
  end

  # Jumping from a declaration to itself is a no-op, and returning nothing
  # makes the editor say "No definition found" instead -- which reads as a
  # failure. 0.2.1 changed it by tightening the receiverless path and
  # recorded nothing, so it is restored and pinned.
  it "answers its own declaration for a position on a def's name" do
    locations = ask("textDocument/definition", line: 1, character: 7)

    expect(locations.map { |l| l[:range][:start][:line] }).to eq([1])
  end
end
