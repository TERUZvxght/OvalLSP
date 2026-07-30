# frozen_string_literal: true

require "stringio"

# Documentation in hover and completion (0.2.0).
#
# Hover said what a thing *is* and never what it is *for*, though the
# RDoc/YARD comment was sitting right above the `def`.
RSpec.describe "Ovallsp::Server documentation in hover and completion (0.2.0)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def open(uri, text, language_id: "ruby")
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: language_id } }
    )
  end

  def responses
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  WIDGET = <<~RUBY
    class Widget
      # Charges the card.
      # Raises on a declined payment.
      def charge
      end

      def undocumented
      end
    end
  RUBY

  def run(*requests)
    input = open("file:///widget.rb", WIDGET) +
            open("file:///use.rb", "Widget.new.charge\n") +
            requests.join +
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    responses
  end

  def hover_at(line, character)
    run(frame(jsonrpc: "2.0", id: 1, method: "textDocument/hover",
              params: { textDocument: { uri: "file:///use.rb" }, position: { line: line, character: character } }))
      .first[:result][:contents][:value]
  end

  it "shows the comment block above the method being hovered" do
    expect(hover_at(0, 13)).to include("Charges the card.").and include("Raises on a declined payment.")
  end

  it "still answers for a method with no comment above it" do
    input = open("file:///widget.rb", WIDGET) +
            open("file:///use.rb", "Widget.new.undocumented\n") +
            frame(jsonrpc: "2.0", id: 1, method: "textDocument/hover",
                  params: { textDocument: { uri: "file:///use.rb" }, position: { line: 0, character: 13 } }) +
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

    value = responses.first[:result][:contents][:value]
    expect(value).to include("Defined:")
    expect(value).not_to include("Charges the card.")
  end

  # Documentation is prose, and the rest of the hover is a type, an
  # origin and a path. Running them together makes the first line of the
  # comment read as part of the signature.
  it "separates the documentation from the type and origin lines" do
    expect(hover_at(0, 13)).to match(/\n\n/)
  end

  describe "completion" do
    def completion_items
      run(frame(jsonrpc: "2.0", id: 1, method: "textDocument/completion",
                params: { textDocument: { uri: "file:///use.rb" }, position: { line: 0, character: 14 } }))
        .first[:result][:items]
    end

    # Reading the source for every candidate would put a file read per
    # item on the request path, for documentation the user sees for one of
    # them at most. `completionItem/resolve` exists for exactly this, and
    # the list carries only what the resolve needs to find the source.
    it "advertises that it resolves completion items" do
      result = run(frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {})).first[:result]

      expect(result[:capabilities][:completionProvider][:resolveProvider]).to be(true)
    end

    it "does not put documentation on the list itself" do
      item = completion_items.find { |i| i[:label] == "charge" }

      expect(item).not_to be_nil
      expect(item[:documentation]).to be_nil
      expect(item[:data]).not_to be_nil
    end

    it "fills in the documentation when the item is resolved" do
      item = completion_items.find { |i| i[:label] == "charge" }
      resolved = run(frame(jsonrpc: "2.0", id: 2, method: "completionItem/resolve", params: item))
                 .find { |m| m[:id] == 2 }[:result]

      expect(resolved[:documentation][:value]).to include("Charges the card.")
    end

    # A Hash literal infers as `Hash[Unknown]`, a Generic -- and a Generic
    # over a real class *is* an instance of that class, which is what
    # `Types.base_nominal` says in the one place that says it. Carrying
    # the receiver as a plain Nominal check instead loses every container
    # receiver, silently, on a shape as ordinary as `{}`.
    it "resolves an item whose receiver is a container over a real class" do
      input = open("file:///hash.rb", "h = {}\nh.ke\n") +
              frame(jsonrpc: "2.0", id: 1, method: "textDocument/completion",
                    params: { textDocument: { uri: "file:///hash.rb" }, position: { line: 1, character: 4 } }) +
              frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
      item = responses.first[:result][:items].find { |i| i[:label] == "keys" }

      expect(item).not_to be_nil
      expect(item[:data]).to eq(receiver: "Hash", name: "keys")
    end

    it "returns an item it cannot document unchanged, rather than failing" do
      resolved = run(frame(jsonrpc: "2.0", id: 2, method: "completionItem/resolve",
                            params: { label: "mystery", kind: 2 }))
                 .find { |m| m[:id] == 2 }[:result]

      expect(resolved[:label]).to eq("mystery")
      expect(resolved[:documentation]).to be_nil
    end
  end
end
