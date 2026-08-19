# frozen_string_literal: true

require "stringio"

# `#publish_findings` was four lines with no state, and four kinds of
# writer reach it: the dispatch thread, the workspace pass on its own
# thread, six background `republish_open_diagnostics` sites, and the
# changed-files batch thread. Nothing ordered a background publish
# against `didClose`'s clear, and `024.56` records the reproduced
# publish sequence for a closed file -- **findings, the clear, the
# findings again** -- present in every shipped build.
#
# The same gap in the other direction: a background publish computed for
# an older version can land after the dispatch thread has already
# published a newer one, putting stale findings back. `TextDocument` is
# an immutable snapshot as of this release (029's M-2), which is what
# makes a version number worth ordering by at all -- before it, text and
# version could be read torn.
#
# 029's M-3: one small per-uri memory in the funnel itself. Every writer
# is ordered by it without knowing about the others.
RSpec.describe "Ovallsp::Server publish ordering (029 M-3, 024.56)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:server) { Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger) }
  let(:uri) { "file:///a.rb" }

  # A versioned publish is a buffer's answer, so these examples open the
  # buffer -- the funnel drops one for a uri nobody has open, which is
  # half of what makes `024.56`'s sequence impossible.
  before do
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.instance_variable_get(:@document_store)
          .open(uri: "file:///b.rb", text: "y = 2\n", version: 1, language_id: "ruby")
  end

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

  it "refuses a publish for a version older than the one already sent" do
    server.send(:publish_findings, uri, [finding, finding], version: 5)
    server.send(:publish_findings, uri, [finding], version: 3)

    expect(published).to eq([[5, 2]])
  end

  it "accepts the same version again, since a later pass may know more" do
    server.send(:publish_findings, uri, [], version: 5)
    server.send(:publish_findings, uri, [finding], version: 5)

    expect(published).to eq([[5, 0], [5, 1]])
  end

  # `024.56`'s sequence, in order: findings for an open file, the clear
  # when it is closed, and then a background pass that was already in
  # flight arriving with the findings again.
  it "does not let a background publish undo a clear" do
    server.send(:publish_findings, uri, [finding, finding], version: 2)
    server.instance_variable_get(:@document_store).close(uri: uri)
    server.send(:clear_findings, uri)
    server.send(:publish_findings, uri, [finding, finding], version: 2)

    expect(published).to eq([[2, 2], [nil, 0]])
  end

  # The distinguishing case for the open-buffer half of the rule: the
  # workspace pass publishes for files nobody has open, and must keep
  # working after a clear.
  it "still lets the workspace pass publish for a file nobody has open" do
    server.instance_variable_get(:@document_store).close(uri: uri)
    server.send(:clear_findings, uri)
    server.send(:publish_findings, uri, [finding])

    expect(published).to eq([[nil, 0], [nil, 1]])
  end

  # And a clear always wins, whatever came before it -- closing a file is
  # not something a stale computation may overrule.
  it "lets a clear through even when a newer version was just published" do
    server.send(:publish_findings, uri, [finding], version: 9)
    server.send(:clear_findings, uri)

    expect(published).to eq([[9, 1], [nil, 0]])
  end

  # Reopening starts over: the memory is per-uri and a clear resets it,
  # so the file's diagnostics come back rather than being refused as old.
  it "publishes again after a clear, at any version, once the file is open again" do
    server.send(:publish_findings, uri, [finding], version: 9)
    server.send(:clear_findings, uri)
    server.send(:publish_findings, uri, [finding], version: 1)

    expect(published).to eq([[9, 1], [nil, 0], [1, 1]])
  end

  # A versionless publish is the workspace pass's shape -- it analyses
  # files nobody has open. It must not be silently ordered against a
  # buffer's version numbers.
  it "does not order a versionless publish against a versioned one" do
    server.send(:publish_findings, uri, [finding], version: 7)
    server.send(:publish_findings, uri, [finding, finding])

    expect(published).to eq([[7, 1], [nil, 2]])
  end

  it "keeps each uri's memory to itself" do
    server.send(:publish_findings, uri, [finding], version: 5)
    server.send(:publish_findings, "file:///b.rb", [finding], version: 1)

    expect(published).to eq([[5, 1], [1, 1]])
  end

  # And `didClose` has to go *through* the funnel, or the memory is not
  # the funnel's. There were two clear paths until 0.2.7 --
  # `#clear_diagnostics` wrote straight to the writer -- which is the
  # "four writer kinds, no state" shape 029's M-3 names, surviving inside
  # the fix for it.
  it "clears through the funnel when a buffer closes, so reopening starts over" do
    server.send(:publish_findings, uri, [finding], version: 9)
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [finding], version: 1)

    # Without the clear going through the funnel, the memory still says 9
    # and the reopened buffer's version 1 is refused as old -- so the file
    # shows nothing until it is edited nine times.
    expect(published).to eq([[9, 1], [nil, 0], [1, 1]])
  end
end

