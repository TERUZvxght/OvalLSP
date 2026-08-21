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

  # `024.113`. The funnel took the document in 0.2.10 and left the memory
  # it compares against keyed by uri alone -- so a client that reopens a
  # file *without* closing it, with the new buffer numbering below the
  # old, had every edit refused until the numbering passed where the
  # previous buffer left off. A version is only meaningful inside one
  # buffer, and that is exactly as true of the remembered one.
  it "does not compare a new buffer's version against the one before it" do
    first = store.open(uri: uri, text: "x = 1\n", version: 10, language_id: "ruby")
    publish!(first, [finding])

    # No didClose: the reopen replaces the buffer in place.
    second = store.open(uri: uri, text: "y = 2\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [], document: second)
    third = store.change(uri: uri, version: 2, changes: [{ text: "y = 3\n" }])
    server.send(:publish_findings, uri, [finding, finding], document: third)

    expect(published).to eq([[10, 1], [1, 0], [2, 2]])
  end

  # The control: inside *one* buffer the ordering rule still holds, which
  # is what the memory is for. An implementation that simply stopped
  # remembering would pass the example above and fail this one.
  it "still refuses an older version of the same buffer" do
    opened = store.open(uri: uri, text: "x = 1\n", version: 10, language_id: "ruby")
    publish!(opened, [finding])
    earlier = opened.with_full_change(text: "x = 0\n", version: 4)

    server.send(:publish_findings, uri, [], document: earlier)

    expect(published).to eq([[10, 1]])
  end

  it "refuses a workspace-path answer while a buffer is open, as before" do
    store.open(uri: uri, text: "x = 1\n", version: 3, language_id: "ruby")
    disk = Ovallsp::TextDocument.new(uri: uri, text: "from disk\n", version: nil, language_id: "ruby")

    server.send(:publish_findings, uri, [finding], document: disk)

    expect(published).to be_empty
  end
  # `024.97`. The funnel lets the *same* version through twice on purpose:
  # a later pass usually knows more, not less -- the Agent has answered,
  # routes have arrived -- and refusing a repeat would switch correction
  # off. So two answers about one version were ordered only by arrival,
  # and the slower one won. Pause on a file large enough to take seconds
  # and the `*_path` reports made *before* routes arrived land after the
  # corrected ones.
  #
  # The version is the wrong key. What distinguishes the two answers is
  # what was *known* when each was computed, which the engine already
  # tracks as `generation` on every `Finding`.
  describe "two answers about one version" do
    def finding_at(generation)
      Ovallsp::Diagnostics::Finding.new(
        code: "x", message: "m", range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } },
        severity: :warning, confidence: :high, evidence: {}, generation: generation
      )
    end

    # The store's own document, not a lookalike: the funnel compares
    # `buffer_id`, so a `TextDocument` built beside the store is a
    # different buffer and is refused before generation is reached.
    let(:document) { store.open(uri: uri, text: "class A\nend\n", version: 4, language_id: "ruby") }

    before { document }

    it "refuses an answer computed from less than the one already published" do
      server.send(:publish_findings, uri, [finding_at(1)], document: document)
      server.send(:publish_findings, uri, [finding_at(0)], document: document)

      expect(published).to eq([[4, 1]])
    end

    # The control, and the repeat this must not refuse: a *later*
    # generation is the correction the same-version repeat exists for. An
    # implementation that simply refused every repeat would pass the
    # example above and fail this one.
    it "still publishes an answer computed from more" do
      server.send(:publish_findings, uri, [finding_at(0)], document: document)
      server.send(:publish_findings, uri, [finding_at(1)], document: document)

      expect(published).to eq([[4, 1], [4, 1]])
    end

    # And a publish with nothing to date it by is not refused: an empty
    # finding list is the ordinary "this file is clean now", and it has no
    # generation to read.
    it "publishes a clean result that carries no generation" do
      server.send(:publish_findings, uri, [finding_at(1)], document: document)
      server.send(:publish_findings, uri, [], document: document)

      expect(published).to eq([[4, 1], [4, 0]])
    end
  end
end
