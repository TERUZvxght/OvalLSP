# frozen_string_literal: true

require "stringio"

# 0.3.0's `textDocument/inlayHint`. Every example here drives the real
# server over a real document, because each of the defects these pin is
# invisible to a fixture with one call in it -- they are all about what
# happens to the *second* thing on the page.
RSpec.describe "Ovallsp::Server textDocument/inlayHint" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def sent_messages(output)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  # `[line, character, label]` for each hint the server answers. Its own
  # output buffer per call: an example here asks twice and compares the
  # answers, and a shared buffer would hand back the first answer both
  # times -- which looked exactly like the defect under test.
  def hints(source, range: { start: { line: 0, character: 0 }, end: { line: 999, character: 0 } })
    output = StringIO.new
    input =
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: "file:///h.rb", text: source, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/inlayHint",
            params: { textDocument: { uri: "file:///h.rb" }, range: range }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    Array(sent_messages(output).first[:result])
      .map { |h| [h[:position][:line], h[:position][:character], h[:label]] }
      .sort
  end

  # **`ReferenceResolver#resolve` is a `filter_map`**, so the array it
  # returns is shorter than the candidate list whenever one call cannot
  # be resolved -- and `calls.zip(resolved)` then pairs every later call
  # with the wrong callee's parameters. The visible result is one
  # method's parameter names rendered beside another method's arguments,
  # which is the engine asserting something false in the margin.
  #
  # The unresolvable call has to come *first*; the CONTROL is the same
  # file with the two calls swapped, where the shift cannot happen and
  # the labels land correctly. An example with one call cannot tell the
  # two behaviours apart, which is why none did.
  # `let` rather than a constant: a constant assigned inside a
  # `describe` block lands on `Object`, where another spec file using
  # the same word silently redefines it for both.
  let(:resize) do
    <<~RUBY
    class Callee
      def resize(width, height)
        [width, height]
      end
    end
  RUBY
  end

  it "labels the call the parameters came from, not the one after an unresolvable call" do
    shifted = hints("#{resize}thing.mystery(1, 2)\nCallee.new.resize(10, 20)\n")
    control = hints("#{resize}Callee.new.resize(10, 20)\nthing.mystery(1, 2)\n")

    expect(control).to eq([[5, 18, "width:"], [5, 22, "height:"]].sort)
    expect(shifted).to eq([[6, 18, "width:"], [6, 22, "height:"]].sort)
  end

  # **The range is tested against the hint, not against the call.** The
  # candidate's location is the call's *message* -- `resize(` -- so on a
  # call whose arguments are on later lines, a request for the lines the
  # arguments are on returned nothing while a request for the opener's
  # line returned hints outside the range the client asked for.
  let(:multiline) do
    <<~RUBY
    class Callee
      def resize(width, height)
        [width, height]
      end
    end
    Callee.new.resize(
      10,
      20
    )
  RUBY
  end

  it "answers by where each hint goes, not by where the call's name is" do
    opener_only = hints(multiline, range: { start: { line: 5, character: 0 }, end: { line: 6, character: 99 } })
    arguments_only = hints(multiline, range: { start: { line: 6, character: 0 }, end: { line: 8, character: 99 } })
    whole = hints(multiline, range: { start: { line: 0, character: 0 }, end: { line: 9, character: 0 } })

    # CONTROL: over the whole file both hints are answered, so an
    # example that simply returned nothing would not pass.
    expect(whole).to eq([[6, 2, "width:"], [7, 2, "height:"]].sort)
    expect(opener_only).to eq([[6, 2, "width:"]])
    expect(arguments_only).to eq([[6, 2, "width:"], [7, 2, "height:"]].sort)
  end

  # **An attribute write is not a call worth labelling.** `named_call?`
  # asks "does this begin like an identifier", which the writer `name=`
  # does, so `obj.name = "x"` rendered as `obj.name = value: "x"`. The
  # index form of the same construct, `arr[0] = 1`, is already silent
  # because `[]=` does not begin like an identifier -- two spellings of
  # one thing treated oppositely.
  it "says nothing beside an attribute write, and still labels an ordinary call" do
    source = <<~RUBY
      class Writer
        def name=(value)
          @name = value
        end

        def take(count)
          count
        end
      end
      Writer.new.name = "x"
      Writer.new.take(5)
    RUBY

    # CONTROL: the ordinary call in the same fixture keeps its label.
    expect(hints(source)).to eq([[10, 16, "count:"]])
  end

  # **A destructuring parameter has no name.** `Index::Parameter#name`
  # is nil for a `MultiTargetNode`, and the label was interpolated
  # unguarded, so the editor rendered a bare `:` before the argument.
  it "skips a parameter with no name, and keeps the named one beside it" do
    source = <<~RUBY
      class Pairs
        def pairwise((a, b), tail)
          [a, b, tail]
        end
      end
      Pairs.new.pairwise([1, 2], 3)
    RUBY

    # CONTROL: `tail:` in the same call must survive; dropping the whole
    # call would also remove the bare `:`.
    expect(hints(source)).to eq([[5, 27, "tail:"]])
  end
end
