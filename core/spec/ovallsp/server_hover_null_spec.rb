# frozen_string_literal: true

require "stringio"

# `024.127`. For a position it knows nothing about — inside a comment, on
# whitespace — hover answered `{contents: {kind: "plaintext", value: ""}}`.
#
# That is a `Hover` object. The protocol declares the result
# `Hover | null` (`docs/CLIENT_BEHAVIOUR.md`, derived from the client's
# own `protocol.d.ts` rather than from memory), so an empty-string hover
# is a hover that *exists* and happens to be blank, and a client is
# entitled to render a frame for it. `null` is how the protocol says
# "nothing here".
RSpec.describe "Ovallsp::Server hover on a position with nothing to say" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:server) { Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger) }
  let(:uri) { "file:///a.rb" }

  before do
    store = server.instance_variable_get(:@document_store)
    store.open(uri: uri, text: "# just a comment\nx = 1\n", version: 1, language_id: "ruby")
  end

  def hover_at(line:, character:)
    server.send(:hover_result, { textDocument: { uri: uri }, position: { line: line, character: character } })
  end

  it "answers null inside a comment" do
    expect(hover_at(line: 0, character: 5)).to be_nil
  end

  it "answers null for a document it does not have" do
    result = server.send(:hover_result,
                         { textDocument: { uri: "file:///nope.rb" }, position: { line: 0, character: 0 } })

    expect(result).to be_nil
  end

  # The distinguishing half: a position that *does* have something must
  # still answer a Hover, or "return null" would be satisfied by
  # returning null always.
  it "still answers a hover where there is something to say" do
    result = hover_at(line: 1, character: 0)

    expect(result).to be_a(Hash)
    expect(result.dig(:contents, :value)).to eq("Integer")
  end
end
