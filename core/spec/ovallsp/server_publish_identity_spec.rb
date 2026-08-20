# frozen_string_literal: true

require "stringio"

# C3: an answer is computed from a particular text and then attributed to
# a `uri` and an integer, and neither identifies the text it was computed
# from. The integer is chosen by the client, which is free to start again
# at 1 -- or at anything else -- when a file is closed and reopened, so
# `version < last` can be comparing two numbers that are not on the same
# scale.
#
# `024.56`'s fix caught the reopen-*below* case, because a version above
# the open buffer's cannot be that buffer's. It cannot catch the reopen
# -*above* case, which is the same defect with the client's numbering
# going the other way, and which no integer comparison can see.
RSpec.describe "Ovallsp::Server publish identity (037 C3)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:server) { Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger) }
  let(:store) { server.instance_variable_get(:@document_store) }
  let(:uri) { "file:///a.rb" }

  def published
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" }
            .map { |m| [m[:params][:version], m[:params][:diagnostics].length] }
  end

  def finding
    Ovallsp::Diagnostics::Finding.new(
      code: "x", message: "m", range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
      severity: :warning, confidence: :high, evidence: {}, generation: 1
    )
  end

  def publish!(document, findings)
    before = published.length
    server.send(:publish_findings, document.uri, findings, document: document)
    raise "setup did not reach the client" unless published.length == before + 1
  end

  it "refuses an answer computed from a buffer the editor has closed, reopened above it" do
    opened = store.open(uri: uri, text: "x = 1\n", version: 47, language_id: "ruby")
    publish!(opened, [finding])

    server.send(:handle_did_close, { textDocument: { uri: uri } })
    store.open(uri: uri, text: "totally different\n", version: 90, language_id: "ruby")

    # 47 is below 90, so no comparison of integers refuses this. It is a
    # different buffer, which is the only thing that does.
    server.send(:publish_findings, uri, [finding, finding], document: opened)

    expect(published).to eq([[47, 1], [nil, 0]])
  end

  it "still publishes an answer computed before the same buffer moved on" do
    opened = store.open(uri: uri, text: "x = 1\n", version: 3, language_id: "ruby")
    store.change(uri: uri, version: 4, changes: [{ text: "a\n" }])

    server.send(:publish_findings, uri, [finding], document: opened)

    expect(published).to eq([[3, 1]])
  end

  it "refuses a workspace-path answer while a buffer is open, as before" do
    store.open(uri: uri, text: "x = 1\n", version: 3, language_id: "ruby")
    disk = Ovallsp::TextDocument.new(uri: uri, text: "from disk\n", version: nil, language_id: "ruby")

    server.send(:publish_findings, uri, [finding], document: disk)

    expect(published).to be_empty
  end
end
