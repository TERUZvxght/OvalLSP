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
end
