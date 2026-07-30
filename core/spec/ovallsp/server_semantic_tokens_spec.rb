# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server semantic tokens (0.2.0)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def responses(input)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def open(uri, text, language_id: "ruby")
    frame(jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, text: text, version: 1, languageId: language_id } })
  end

  it "advertises the legend it encodes against" do
    result = responses(frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
                       frame(jsonrpc: "2.0", method: "exit", params: nil)).first[:result]
    provider = result[:capabilities][:semanticTokensProvider]

    expect(provider[:legend][:tokenTypes]).to eq(Ovallsp::SemanticTokens::LEGEND)
    expect(provider[:full]).to be(true)
  end

  it "answers with the encoded tokens for an open document" do
    input = open("file:///a.rb", "value = 1\nvalue\n") +
            frame(jsonrpc: "2.0", id: 1, method: "textDocument/semanticTokens/full",
                  params: { textDocument: { uri: "file:///a.rb" } }) +
            frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(responses(input).first[:result][:data]).to eq([0, 0, 5, 0, 0, 1, 0, 5, 0, 0])
  end

  it "answers for an ERB view's Ruby regions" do
    input = open("file:///app/views/users/show.html.erb", "<p><%= @user %></p>\n", language_id: "html") +
            frame(jsonrpc: "2.0", id: 1, method: "textDocument/semanticTokens/full",
                  params: { textDocument: { uri: "file:///app/views/users/show.html.erb" } }) +
            frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(responses(input).first[:result][:data]).to eq([0, 7, 5, 2, 0])
  end

  # A null result tells the client the request failed, and a client told
  # that stops asking for the rest of the session.
  it "answers with an empty token list for a document it does not have" do
    input = frame(jsonrpc: "2.0", id: 1, method: "textDocument/semanticTokens/full",
                  params: { textDocument: { uri: "file:///missing.rb" } }) +
            frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect(responses(input).first[:result]).to eq(data: [])
  end
end
