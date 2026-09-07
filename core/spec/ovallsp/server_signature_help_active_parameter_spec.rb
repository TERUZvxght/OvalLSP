# frozen_string_literal: true

require "stringio"
require_relative "../unit_spec_helper"
require_relative "../test_hygiene"

RSpec.describe "Ovallsp::Server signature help active parameter" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def ask_signature(source, line, character)
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///test.rb", text: source, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/signatureHelp",
        params: { textDocument: { uri: "file:///test.rb" }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    out = StringIO.new
    server = Ovallsp::Server.new(input: StringIO.new(input), output: out, logger: logger)
    server.run

    out.rewind
    reader = Ovallsp::IO::FramedReader.new(out)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.first[:result]
  end

  let(:source) do
    <<~RUBY
      class Calculator
        def add(first, second, third = 0); end

        def run
          add(1, 2, 3)
          add([10, 20, 30], { a: 1, b: 2 }, 3)
        end
      end
    RUBY
  end

  def ask_marked_signature(source)
    offset = source.index("|")
    text = source.delete("|")
    document = Ovallsp::TextDocument.new(uri: "file:///test.rb", text: text, version: 1, language_id: "ruby")
    position = document.char_offset_to_position(offset)
    ask_signature(text, position[:line], position[:character])
  end

  # Ruby binds keyword arguments by name, independently of their order:
  #   $ ruby -e 'def render(body:, status:); [body, status]; end; p method(:render).parameters; p render(status: 200, body: "x")'
  #   # => [[:keyreq, :body], [:keyreq, :status]]
  #   # => ["x", 200]
  #   # ruby 3.4.10

  {
    "the first supplied keyword by name" => ["body:, status:", "target(status: |200, body: 'x')", 1],
    "the second supplied keyword by name" => ["body:, status:", "target(status: 200, body: |'x')", 0],
    "a keyword with a default after positional rest" => ["*args, body:, status: 200", "target(status: |200, body: 'x')", 2],
    "a keyword whose label is under the cursor" => ["body:, status:", "target(sta|tus: 200, body: 'x')", 1],
    "a keyword after a comment" => ["body:, status:", "target( # comment\n status: |200, body: 'x')", 1],
    "an unknown keyword without a highlight" => ["body:, **others", "target(missing: |1)", nil],
    "an excess positional argument without a highlight" => ["first, second", "target(1, 2, |3)", nil],
    "an excess positional argument before keywords without a highlight" => ["first, status:", "target(1, |2, status: 200)", nil],
    "an empty signature without a highlight" => ["", "target(|)", nil],
    "an excess positional argument before a block without a highlight" => ["first, &block", "target(1, |2)", nil],
    "an ambiguous rest followed by a positional parameter without a highlight" => ["first, *middle, last", "target(1, |2, 3)", nil]
  }.each do |behavior, (parameters, call, expected)|
    it "selects #{behavior}" do
      result = ask_marked_signature("class Target\n  def target(#{parameters}); end\n  def run\n    #{call}\n  end\nend\n")
      expect(result[:signatures]).not_to be_empty
      expect(result).to have_key(:activeParameter)
      expect(result[:activeParameter]).to eq(expected)
      expect(result[:signatures].fetch(result[:activeSignature])[:parameters]).to eq([]) if expected.nil?
    end
  end

  it "highlights the first parameter when cursor is on first argument" do
    # `    add(1|` -> line 4, char 9
    result = ask_signature(source, 4, 9)
    expect(result[:activeParameter]).to eq(0)
    expect(result[:activeSignature]).to eq(0)
  end

  it "highlights the second parameter after the first comma" do
    # `    add(1, |2` -> line 4, char 11
    result = ask_signature(source, 4, 11)
    expect(result[:activeParameter]).to eq(1)
  end

  it "highlights the third parameter after the second comma" do
    # `    add(1, 2, 3|)` -> line 4, char 15
    result = ask_signature(source, 4, 15)
    expect(result[:activeParameter]).to eq(2)
  end

  it "ignores commas inside nested array and hash literals" do
    # line 5: `    add([10, 20, 30], { a: 1, b: 2 }, 3)`
    # inside array literal: char 13 (`[10, |20`) -> still parameter 0
    result_in_array = ask_signature(source, 5, 13)
    expect(result_in_array[:activeParameter]).to eq(0)

    # inside hash literal: char 28 (`{ a: 1, |b: 2 }`) -> parameter 1
    result_in_hash = ask_signature(source, 5, 28)
    expect(result_in_hash[:activeParameter]).to eq(1)

    # after hash literal: char 37 (`}, 3|`) -> parameter 2
    result_after_hash = ask_signature(source, 5, 37)
    expect(result_after_hash[:activeParameter]).to eq(2)
  end

  it "hands the cursor to the nested call inside it and back to the outer one after it" do
    nested = <<~RUBY
      class Nested
        def compute(a, b); 0; end
        def add(first, second, third = 0); end

        def run
          add(compute(1, 2), 3)
        end
      end
    RUBY
    # `    add(compute(1, |2), 3)` -> line 5, char 19: the nested call owns the cursor
    inside = ask_signature(nested, 5, 19)
    expect(inside[:signatures].first[:label]).to include("compute")
    expect(inside[:activeParameter]).to eq(1)

    # `    add(compute(1, 2), |3)` -> line 5, char 23: back in `add`, one comma deep
    outside = ask_signature(nested, 5, 23)
    expect(outside[:signatures].first[:label]).to include("add")
    expect(outside[:activeParameter]).to eq(1)
  end

  it "ignores the comma between a lambda argument's own parameters" do
    lambdas = <<~RUBY
      class Lambdas
        def add(first, second, third = 0); end

        def run
          add(->(x, y) { x + y }, 2)
        end
      end
    RUBY
    # `    add(->(x, y) { x + |y }, 2)` -> line 4, char 23: inside the lambda body
    in_body = ask_signature(lambdas, 4, 23)
    expect(in_body[:activeParameter]).to eq(0)

    # `    add(->(x, y) { x + y }, |2)` -> line 4, char 28: past the lambda
    after = ask_signature(lambdas, 4, 28)
    expect(after[:activeParameter]).to eq(1)
  end

  it "ignores a comma and parenthesis inside a string literal" do
    strings = <<~RUBY
      class Strings
        def add(first, second, third = 0); end

        def run
          add("a, (b", 2)
        end
      end
    RUBY
    # `    add("a,| (b", 2)` -> line 4, char 11: inside the string, still argument 0
    in_string = ask_signature(strings, 4, 11)
    expect(in_string[:activeParameter]).to eq(0)

    # `    add("a, (b", |2)` -> line 4, char 17: the string's comma did not count
    after_string = ask_signature(strings, 4, 17)
    expect(after_string[:activeParameter]).to eq(1)
  end

  it "ignores a comma and parenthesis inside a comment, across a newline" do
    commented = <<~RUBY
      class Comments
        def add(first, second, third = 0); end

        def run
          add(1, # comma, and (paren
              2)
        end
      end
    RUBY
    # `        |2)` -> line 5, char 8: one real comma before the cursor, not two
    result = ask_signature(commented, 5, 8)
    expect(result[:activeParameter]).to eq(1)
  end

  it "counts the argument after a non-ASCII string, in UTF-16 columns" do
    japanese = <<~RUBY
      class NonAscii
        def add(first, second, third = 0); end

        def run
          add("あ, い", 2)
        end
      end
    RUBY
    # `    add("あ,| い", 2)` -> line 4, char 11: inside the string
    in_string = ask_signature(japanese, 4, 11)
    expect(in_string[:activeParameter]).to eq(0)

    # `    add("あ, い", |2)` -> line 4, char 16
    after = ask_signature(japanese, 4, 16)
    expect(after[:activeParameter]).to eq(1)

    emoji = <<~RUBY
      class Surrogate
        def add(first, second, third = 0); end

        def run
          add("😀", 2)
        end
      end
    RUBY
    # `😀` is one character but two UTF-16 units, so `|2` is column 14 while the
    # comma Prism reports in bytes sits at character offset 11.
    surrogate = ask_signature(emoji, 4, 14)
    expect(surrogate[:activeParameter]).to eq(1)
  end

  it "counts an argument the author has not finished typing" do
    unclosed = <<~RUBY
      class Unclosed
        def add(first, second, third = 0); end

        def run
          add(1,
        end
      end
    RUBY
    # `    add(1, |` -> line 4, char 10: the call is still open
    result = ask_signature(unclosed, 4, 10)
    expect(result[:activeParameter]).to eq(1)
  end

  it "maps every argument the rest parameter receives onto the rest parameter" do
    rest = <<~RUBY
      class Gatherer
        def gather(first, *rest); end

        def run
          gather(1, 2, 3, 4)
        end
      end
    RUBY
    # `    gather(1, |2, 3, 4)` -> line 4, char 14: the rest's first element
    second = ask_signature(rest, 4, 14)
    expect(second[:activeParameter]).to eq(1)

    # `    gather(1, 2, |3, 4)` -> line 4, char 17: still `*rest`, not an index
    # past the label's end that LSP 3.17 tells the client to read as 0 (`first`)
    third = ask_signature(rest, 4, 17)
    expect(third[:activeParameter]).to eq(1)

    # `    gather(1, 2, 3, |4)` -> line 4, char 20
    fourth = ask_signature(rest, 4, 20)
    expect(fourth[:activeParameter]).to eq(1)
  end

  it "selects an overload whose rest can receive an argument past every fixed parameter" do
    kernel_p = <<~RUBY
      class Prober
        def run
          p(1, 2, 3, 4)
        end
      end
    RUBY
    # `    p(1, 2, 3, |4)` -> line 2, char 15: past every fixed parameter of
    # every overload, so only `p(_Inspect, _Inspect, ...)`'s rest receives it
    result = ask_signature(kernel_p, 2, 15)
    selected = result[:signatures].fetch(result[:activeSignature])
    rest = selected[:parameters].fetch(result[:activeParameter])[:label]
    expect(selected[:label][rest[0]...rest[1]]).to eq("...")
  end

  it "keeps the highlight inside the signature it selects among RBS overloads" do
    overloads = <<~RUBY
      class Splitter
        def run
          text = "s"
          text.split("a", 2)
        end
      end
    RUBY
    # `    text.split("a", |2)` -> line 3, char 20: the second argument, so the
    # selected overload has to have a second parameter for the index to land in
    result = ask_signature(overloads, 3, 20)
    expect(result[:signatures]).not_to be_empty
    selected = result[:signatures].fetch(result[:activeSignature])
    expect(selected[:parameters].length).to be > result[:activeParameter]
  end
end
