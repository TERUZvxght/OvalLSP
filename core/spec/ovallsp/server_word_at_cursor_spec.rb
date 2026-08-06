# frozen_string_literal: true

require "stringio"

# Which characters make up the name under the cursor — every shape, at
# every position in it, from a table.
#
# Four rounds running found a defect here, and each was a different
# position in the same small question: the name ends at `!` (so `save!`
# was looked up as `save`), then the caret *after* the `!` found no word,
# then the `!` of `!ready` — negation, not a suffix — swallowed itself
# into the name. Each fix was correct and each opened the next hole,
# because each was written against one position.
#
# So the positions are enumerated rather than chosen. Every row asserts
# an *answer*, because an empty answer is what every one of those defects
# produced and what a `not_to include` assertion cannot see.
RSpec.describe "Ovallsp::Server the word under the cursor" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def definition_lines(source, line, character)
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///w.rb", text: source, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/definition",
        params: { textDocument: { uri: "file:///w.rb" }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    Array(sent_messages.first[:result]).map { |location| location[:range][:start][:line] }
  end

  # Each fixture declares the method on line 1 and uses it on line 4. The
  # `use` string says exactly what is written; the name inside it is what
  # every caret position in that name must resolve to.
  {
    "a plain name" => ["def target(a); a; end", "target(1)", "target"],
    "a name ending in `!`" => ["def target!(a); a; end", "target!(1)", "target!"],
    "a name ending in `?`" => ["def target?; true; end", "target?", "target?"],
    "a name being negated" => ["def target?; true; end", "return 0 if !target?", "target?"],
    "a name doubly negated" => ["def target?; true; end", "return 0 if !!target?", "target?"],
    "a name after a receiver" => ["def target!(a); a; end", "W.new.target!(1)", "target!"]
  }.each do |description, (declaration, use, name)|
    source = "class W\n  #{declaration}\n\n  def run\n    #{use}\n  end\nend\n"
    line = 4
    first = "    #{use}".index(name)

    # Every caret position *within* the name, and the one just past it --
    # which is where the caret lands after typing the name, and which is
    # the position round 29 found answering nothing.
    (first..(first + name.length)).each do |character|
      it "resolves #{description} with the caret at column #{character - first} of it" do
        expect(definition_lines(source, line, character)).to include(1)
      end
    end
  end

  # `self.target!` is deliberately absent: `self` has no type (024.46 --
  # giving it one cost 55 false diagnostics over the standard library),
  # so the receiver resolves to Unknown and the answer is silence. This
  # file is about which characters make up the *name*, and that question
  # is answered correctly there; what happens next is the receiver's.

  # The boundary: the characters around a name are not part of it.
  it "resolves nothing from the `!` that negates a name" do
    source = "class W\n  def target?; true; end\n\n  def run\n    return 0 if !target?\n  end\nend\n"

    expect(definition_lines(source, 4, "    return 0 if !target?".index("!"))).to eq([])
  end
end
