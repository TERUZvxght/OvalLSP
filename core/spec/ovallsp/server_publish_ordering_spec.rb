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
  # buffer -- the funnel drops one for a uri nobody has open, and one
  # whose version is above what the open buffer has reached. Opened at
  # 100 so an example can name any version below it without that second
  # rule getting in the way of the one it is about.
  before do
    store = server.instance_variable_get(:@document_store)
    store.open(uri: uri, text: "x = 1\n", version: 100, language_id: "ruby")
    store.open(uri: "file:///b.rb", text: "y = 2\n", version: 100, language_id: "ruby")
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

  # Publishes *and* asserts it went out. The funnel's whole job is to
  # refuse a publish, so a setup step that is silently refused leaves the
  # example testing a state it never reached -- which is what happened to
  # the watched-files example below: the version-9 publish it set up was
  # itself dropped, and it passed against both branches of the change it
  # was written to pin.
  #
  # "An assertion that cannot fail is not a test" is a rule this project
  # already has and enforces on expectations. This is the same defect
  # arriving through the setup, where nothing was looking.
  def publish!(target_uri, findings, **kwargs)
    before = published.length
    server.send(:publish_findings, target_uri, findings, **kwargs)

    raise "setup did not reach the client: publish_findings(#{target_uri}, #{kwargs}) was refused" \
      unless published.length == before + 1
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

  # The whole point of the lock spanning the write: an admitted publish
  # cannot be overtaken on the wire by one admitted after it. Asserted by
  # driving real threads through the funnel and checking that what the
  # client is left holding is the highest version, every time.
  it "leaves the client holding the newest version under concurrent publishes" do
    threads = (1..20).map do |v|
      Thread.new { server.send(:publish_findings, uri, [finding], version: v) }
    end
    threads.each(&:join)

    versions = published.map(&:first)
    expect(versions.last).to eq(versions.max)
    expect(versions).to eq(versions.sort)
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
  # files nobody has open, so it is not ordered against a buffer's
  # numbers. But it is refused while the buffer *is* open: answering from
  # disk for a file someone is editing races the buffer path for the last
  # word, which is the property `WorkspaceDiagnostics` already believes it
  # holds and guards with a two-statement check a `didOpen` can land
  # inside. Demonstrated by a reviewer: one versionless publish left the
  # panel empty for a buffer that had two findings.
  it "refuses a versionless publish while the buffer is open" do
    server.send(:publish_findings, uri, [finding], version: 7)
    server.send(:publish_findings, uri, [])

    expect(published).to eq([[7, 1]])
  end

  it "publishes a versionless answer once nobody has the file open" do
    server.instance_variable_get(:@document_store).close(uri: uri)

    server.send(:publish_findings, uri, [finding, finding])

    expect(published).to eq([[nil, 2]])
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
    publish!(uri, [finding], version: 9)
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [finding], version: 1)

    # Without the clear going through the funnel, the memory still says 9
    # and the reopened buffer's version 1 is refused as old -- so the file
    # shows nothing until it is edited nine times.
    expect(published).to eq([[9, 1], [nil, 0], [1, 1]])
  end

  # A file leaving the workspace clears through the funnel too, for the
  # same reason `didClose` does: `publish_findings(uri, [])` writes an
  # empty list without touching the memory, so the uri kept the version it
  # was last published at. A rename arrives here as a delete plus a
  # create, so the file coming back at a lower version is the ordinary
  # case, not a contrived one -- and it would then publish nothing until
  # it had been edited past the old number.
  #
  # Found by the hunk-by-hunk sweep: the one behavioural line in this
  # change set that could be reverted with the whole suite still green.
  it "clears through the funnel when a file leaves the workspace" do
    publish!(uri, [finding], version: 9)
    server.instance_variable_get(:@document_store).close(uri: uri)
    server.send(:handle_did_change_watched_files,
                { changes: [{ uri: uri, type: Ovallsp::Server::FILE_CHANGE_DELETED }] })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [finding], version: 1)

    expect(published.last).to eq([1, 1])
  end

  # **The regression the first version of this funnel introduced, found by
  # two independent review rounds at once and worse than what it fixes.**
  #
  # The open-buffer rule asked whether *anyone* has the file open now, not
  # whether the buffer these findings belong to is the one open. Close a
  # tab while a republish is in flight, reopen it -- VS Code hands out a
  # fresh document at version 1 -- and the stale publish at version 47
  # finds an open buffer and an empty memory, is admitted, and sets the
  # memory to 47. Every edit after that is refused as older.
  #
  # So the panel shows the pre-close errors on text the user has already
  # fixed, and stays wrong for as many edits as the old buffer had
  # accumulated -- hundreds, since the version bumps per keystroke.
  # `main` self-corrects on the very next edit. Measured on both sides.
  #
  # A buffer never publishes ahead of itself: the document a publish was
  # computed from came out of the store, so its version cannot exceed what
  # the store holds now. A version that *does* exceed it belongs to a
  # different buffer instance -- a closed one.
  it "refuses a publish from a buffer instance that is no longer the open one" do
    publish!(uri, [finding, finding], version: 47)
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "fixed\n", version: 1, language_id: "ruby")

    server.send(:publish_findings, uri, [finding, finding], version: 47)
    server.send(:publish_findings, uri, [], version: 1)
    server.instance_variable_get(:@document_store).change(uri: uri, version: 2, changes: [{ text: "fixed!\n" }])
    server.send(:publish_findings, uri, [], version: 2)

    expect(published).to eq([[47, 2], [nil, 0], [1, 0], [2, 0]])
  end

  # The control: an answer for a version the buffer has since moved past
  # is still published -- the analysis that produced it started when that
  # version was current, and this is the ordinary case every keystroke
  # produces. The rule is about a version from this buffer's *future*,
  # which only a different instance can hold.
  it "still publishes an answer computed before the buffer moved on" do
    store = server.instance_variable_get(:@document_store)
    store.change(uri: uri, version: 4, changes: [{ text: "a\n" }])

    server.send(:publish_findings, uri, [finding], version: 3)
    server.send(:publish_findings, uri, [finding, finding], version: 4)

    expect(published).to eq([[3, 1], [4, 2]])
  end
end

