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

  def published_for(target_uri)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == target_uri }
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
  # An answer computed from the open buffer at `version`. The funnel takes
  # the document rather than an integer since 037's C3, and a snapshot
  # built through `#with_full_change` carries the same `buffer_id` -- so
  # this is the same buffer at another point, which is what every example
  # below is about. A document built from scratch would be a *different*
  # buffer and would be refused for that reason instead.
  def at(version, target_uri = uri)
    server.instance_variable_get(:@document_store)
          .fetch(uri: target_uri)
          .with_full_change(text: "x = #{version}\n", version: version)
  end

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
    server.send(:publish_findings, uri, [finding, finding], document: at(5))
    server.send(:publish_findings, uri, [finding], document: at(3))

    expect(published).to eq([[5, 2]])
  end

  it "accepts the same version again, since a later pass may know more" do
    server.send(:publish_findings, uri, [], document: at(5))
    server.send(:publish_findings, uri, [finding], document: at(5))

    expect(published).to eq([[5, 0], [5, 1]])
  end

  # `024.56`'s sequence, in order: findings for an open file, the clear
  # when it is closed, and then a background pass that was already in
  # flight arriving with the findings again.
  it "does not let a background publish undo a clear" do
    in_flight = at(2)
    server.send(:publish_findings, uri, [finding, finding], document: in_flight)
    server.instance_variable_get(:@document_store).close(uri: uri)
    server.send(:clear_findings, uri)
    # The document the background pass is still holding -- captured before
    # the close, which is the whole point: it outlives the buffer.
    server.send(:publish_findings, uri, [finding, finding], document: in_flight)

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

  # The lock has to span the *write*, not just the decision: holding it
  # only over the admission rules orders which publishes are allowed, not
  # which one the client is left holding.
  #
  # **Twenty threads racing did not pin this.** A review round measured
  # it: moving `write_diagnostics` outside the `synchronize`, and then
  # removing the synchronisation altogether, both left the whole suite
  # green. `versions == versions.sort` follows from the admission rules
  # alone, and the window between deciding and writing is too small for
  # ordinary scheduling to land in.
  #
  # So the window is made visible instead of raced for: a publish is
  # parked inside `to_lsp_diagnostic`, which `write_diagnostics` calls
  # while (with the fix) still holding the lock. A second publish then
  # either waits -- because the lock spans the write -- or overtakes it,
  # which is the defect. That is a property of the lock's scope rather
  # than of the scheduler, so it fails deterministically.
  it "holds the lock across the write, so a later publish cannot overtake an earlier one" do
    inside_first_write = Queue.new
    let_it_finish = Queue.new
    first = true

    allow(server).to receive(:to_lsp_diagnostic).and_wrap_original do |original, *args|
      if first
        first = false
        inside_first_write << :parked
        let_it_finish.pop
      end
      original.call(*args)
    end

    slow = Thread.new { server.send(:publish_findings, uri, [finding], document: at(3)) }
    inside_first_write.pop

    overtaker = Thread.new { server.send(:publish_findings, uri, [finding, finding], document: at(4)) }
    # If the lock spans the write, the second publish cannot even reach
    # its decision while the first is parked mid-write.
    expect(overtaker.join(0.5)).to be_nil

    let_it_finish << :go
    [slow, overtaker].each(&:join)

    expect(published).to eq([[3, 1], [4, 2]])
  end

  # And a clear always wins, whatever came before it -- closing a file is
  # not something a stale computation may overrule.
  it "lets a clear through even when a newer version was just published" do
    server.send(:publish_findings, uri, [finding], document: at(9))
    server.send(:clear_findings, uri)

    expect(published).to eq([[9, 1], [nil, 0]])
  end

  # Reopening starts over: the memory is per-uri and a clear resets it,
  # so the file's diagnostics come back rather than being refused as old.
  it "publishes again after a clear, at any version, once the file is open again" do
    server.send(:publish_findings, uri, [finding], document: at(9))
    server.send(:clear_findings, uri)
    server.send(:publish_findings, uri, [finding], document: at(1))

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
    server.send(:publish_findings, uri, [finding], document: at(7))
    server.send(:publish_findings, uri, [])

    expect(published).to eq([[7, 1]])
  end

  it "publishes a versionless answer once nobody has the file open" do
    server.instance_variable_get(:@document_store).close(uri: uri)

    server.send(:publish_findings, uri, [finding, finding])

    expect(published).to eq([[nil, 2]])
  end

  it "keeps each uri's memory to itself" do
    server.send(:publish_findings, uri, [finding], document: at(5))
    server.send(:publish_findings, "file:///b.rb", [finding], document: at(1, "file:///b.rb"))

    expect(published).to eq([[5, 1], [1, 1]])
  end

  # And `didClose` has to go *through* the funnel, or the memory is not
  # the funnel's. There were two clear paths until 0.2.7 --
  # `#clear_diagnostics` wrote straight to the writer -- which is the
  # "four writer kinds, no state" shape 029's M-3 names, surviving inside
  # the fix for it.
  it "clears through the funnel when a buffer closes, so reopening starts over" do
    publish!(uri, [finding], document: at(9))
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [finding], document: at(1))

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
    publish!(uri, [finding], document: at(9))
    server.instance_variable_get(:@document_store).close(uri: uri)
    server.send(:handle_did_change_watched_files,
                { changes: [{ uri: uri, type: Ovallsp::Server::FILE_CHANGE_DELETED }] })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "x = 1\n", version: 1, language_id: "ruby")
    server.send(:publish_findings, uri, [finding], document: at(1))

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
    publish!(uri, [finding, finding], document: at(47))
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    server.instance_variable_get(:@document_store)
          .open(uri: uri, text: "fixed\n", version: 1, language_id: "ruby")

    server.send(:publish_findings, uri, [finding, finding], document: at(47))
    server.send(:publish_findings, uri, [], document: at(1))
    server.instance_variable_get(:@document_store).change(uri: uri, version: 2, changes: [{ text: "fixed!\n" }])
    server.send(:publish_findings, uri, [], document: at(2))

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

    server.send(:publish_findings, uri, [finding], document: at(3))
    server.send(:publish_findings, uri, [finding, finding], document: at(4))

    expect(published).to eq([[3, 1], [4, 2]])
  end

  # **The disk half of the funnel had no ordering at all.** A publish with
  # `version: nil` is a result for a file nobody has open, and the only
  # thing checked was that nobody has it open -- so a stale answer landed
  # over a newer one, and a result computed before a deletion landed after
  # the clear that deletion sent. The Problems panel then holds findings
  # about a file that is gone, and `WorkspaceDiagnostics#publish_for`
  # returns early on a missing path, so nothing publishes for that uri
  # again.
  #
  # **The empty list is the same design gap.** `Finding#generation` is
  # what dates a buffer publish, and an empty result has no findings to
  # read one from -- which is exactly the "this file is clean now" answer
  # that most needs to be ordered against a stale warning. So the caller
  # states the generation rather than the funnel inferring it.
  #
  # Found by the 2026-09-05 critical review, R06.
  describe "a result for a file nobody has open" do
    let(:disk_uri) { "file:///disk.rb" }

    it "refuses a result older than the one already sent" do
      server.send(:publish_findings, disk_uri, [], generation: 5)
      server.send(:publish_findings, disk_uri, [finding], generation: 3)

      expect(published_for(disk_uri).length).to eq(1)
    end

    it "accepts a result at the same generation, since a later pass may know more" do
      server.send(:publish_findings, disk_uri, [], generation: 5)
      server.send(:publish_findings, disk_uri, [finding], generation: 5)

      expect(published_for(disk_uri).length).to eq(2)
    end

    # **A clear with nothing published before it still voids what came
    # after.** Keeping only the last published generation recorded `nil`
    # here and refused nothing -- the first workspace pass over a file
    # deleted during it. The index generation is the floor: a deletion
    # bumps it before the clear is sent, so anything computed before the
    # removal is strictly below it. Found by cold review.
    it "refuses a result after a clear that had nothing before it" do
      server.send(:clear_findings, disk_uri)
      server.send(:publish_findings, disk_uri, [finding], generation: 0)

      expect(published_for(disk_uri).length).to eq(1) # the clear alone
    end

    it "refuses a result one generation above the last publish, after a clear" do
      server.send(:publish_findings, disk_uri, [finding], generation: 3)
      server.send(:clear_findings, disk_uri)
      server.send(:publish_findings, disk_uri, [finding], generation: 3)

      expect(published_for(disk_uri).length).to eq(2)
    end

    it "refuses a result computed before the file was cleared" do
      server.send(:publish_findings, disk_uri, [finding], generation: 5)
      server.send(:clear_findings, disk_uri)
      server.send(:publish_findings, disk_uri, [finding], generation: 5)

      expect(published_for(disk_uri).length).to eq(2) # the finding, then the clear
    end

    # **The controls.** Without them a funnel that refused every disk
    # publish would pass all three.
    it "still sends a newer result" do
      server.send(:publish_findings, disk_uri, [finding], generation: 3)
      server.send(:publish_findings, disk_uri, [], generation: 5)

      expect(published_for(disk_uri).length).to eq(2)
    end

    it "still sends a result carrying no generation at all" do
      server.send(:publish_findings, disk_uri, [finding])
      server.send(:publish_findings, disk_uri, [])

      expect(published_for(disk_uri).length).to eq(2)
    end
  end
end

# Task 064's P2, the state half: a *configuration* change moves the
# answer without the buffer moving at all. Every ordering rule the funnel
# already has is about a version or a generation, and neither of them
# changes when `ovallsp.diagnostics.severities` does -- so an answer
# computed under the previous setting carries a version and a generation
# that make it look current, and lands on top of the one computed under
# the new setting.
#
# The publish that is *not* a keystroke's is the one this is about:
# `update_configuration` marks every open buffer for analysis, and the six
# `republish_open_diagnostics` sites and the workspace pass reach the same
# funnel from their own threads. So "an answer already in flight when the
# setting changed" is the ordinary case, not a contrived one.
#
# **The stop point is an existing collaborator, not an added hook.**
# `publish_diagnostics` reads the configuration once, analyses under the
# index lock, and then calls `Diagnostics::MidEditCall.filter` before
# handing the findings to the funnel. Parking inside that call holds a
# thread in exactly the window the defect lives in -- after the analysis,
# with the index lock already released, so the configuration change and
# the re-analysis it asks for can both complete while it waits. Nothing
# here waits for a duration or names a lock: each example is fixed by the
# queue the parked thread posts to and by the notifications the client
# received.
RSpec.describe "Ovallsp::Server publish ordering across a configuration change (064 P2)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:server) { Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger) }
  let(:store) { server.instance_variable_get(:@document_store) }
  let(:uri) { "file:///worker.rb" }
  # `baz` is a call to a method the enclosing class does not declare, on a
  # receiver whose ancestry is entirely in the workspace -- the plainest
  # thing `unknown-method` reports, and a check the published settings may
  # reduce to `hint` or switch off. Nothing here is about which check it
  # is; it is about which *configuration* the reported answer was computed
  # under.
  let(:source) { "class Bar\n  def run\n    baz\n  end\nend\n" }

  after { server.instance_variable_get(:@background_tasks).shutdown }

  def notifications
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == uri }
  end

  # What the client is holding, in the order it arrived: each publish as
  # its version and the `[code, severity]` of every diagnostic in it. The
  # severity is included because `hint` and `warning` are the same finding
  # reported under two settings, and an example about which setting won
  # cannot tell them apart without it.
  def reported
    notifications.map { |m| [m[:params][:version], m[:params][:diagnostics].map { |d| [d[:code], d[:severity]] }] }
  end

  def warning
    [["unknown-method", 2]]
  end

  def hint
    [["unknown-method", 4]]
  end

  # `didOpen` rather than `DocumentStore#open`: the declaration has to
  # reach the index for the call to be judged at all, and the point of
  # every example here is that a real answer -- not a hand-built `Finding`
  # -- is the thing being ordered.
  def open_buffer(version: 1)
    server.send(:handle_did_open,
                { textDocument: { uri: uri, text: source, version: version, languageId: "ruby" } })
  end

  def analyse_and_publish
    server.send(:publish_diagnostics, store.fetch(uri: uri))
  end

  # The production entry for `workspace/didChangeConfiguration`, followed
  # by the drain the run loop performs once the input is quiet. Together
  # they are "the setting changed and nothing else did".
  def configure(severities)
    server.send(:update_configuration, { settings: { ovallsp: { diagnostics: { severities: severities } } } })
    server.send(:drain_settled_analyses)
  end

  # Parks the *first* answer to reach the filter and lets every later one
  # through. The caller launches the thread it wants parked and waits on
  # `arrived` before doing anything else, so which answer is held is
  # decided by the order the example starts them in, not by scheduling.
  def park_the_next_answer
    arrived = Queue.new
    release = Queue.new
    parked = false
    allow(Ovallsp::Diagnostics::MidEditCall).to receive(:filter).and_wrap_original do |original, *args|
      unless parked
        parked = true
        arrived << :parked
        release.pop
      end
      original.call(*args)
    end
    [arrived, release]
  end

  def in_flight_answer
    arrived, release = park_the_next_answer
    document = store.fetch(uri: uri)
    thread = Thread.new { server.send(:publish_diagnostics, document) }
    arrived.pop
    [thread, release]
  end

  # **The control the three race examples rest on.** They all assert that
  # some publish did *not* happen, and a funnel that refused every second
  # answer at a version it has already published would satisfy all of
  # them. This is the case that must still get through: the setting
  # changed, nothing else did, and the buffer's answer is re-sent at the
  # version it already published at.
  it "publishes the new answer for a buffer nobody edited when only the setting changed" do
    open_buffer
    analyse_and_publish

    configure({ "unknown-method" => "hint" })

    expect(reported).to eq([[1, warning], [1, hint]])
  end

  # **The race, in the direction that reports something the setting says
  # not to report.** Before the fix the client is left holding the
  # `unknown-method` warning for a check the user has just switched off:
  # the answer computed under the previous setting is at the same version
  # and the same generation as the empty one, and the funnel lets an equal
  # version through on purpose -- a later pass usually knows more.
  #
  # Reverting the guard reports `[[1, warning], [1, []], [1, warning]]`:
  # the empty answer arrives, and the switched-off warning comes back
  # after it.
  it "refuses an answer computed under a configuration that has since been replaced" do
    open_buffer
    analyse_and_publish
    expect(reported).to eq([[1, warning]]) # the check really does report, before anything is switched off

    thread, release = in_flight_answer
    configure({ "unknown-method" => "none" })
    expect(reported.last).to eq([1, []]) # the answer under the new setting reached the client first

    release << :go
    thread.join

    expect(reported).to eq([[1, warning], [1, []]])
  end

  # **The same race in the direction that hides something.** The
  # switched-off answer is the one in flight, and the setting is put back
  # before it lands -- so the client ends up with an empty Problems panel
  # for a file that has a finding under the setting now in force, and
  # nothing corrects it until the file is edited.
  #
  # Reverting the guard reports a fourth publish, `[1, []]`, after the
  # restored warning.
  it "does not let an answer computed while a check was off erase the answer after it is back on" do
    open_buffer
    analyse_and_publish
    configure({ "unknown-method" => "none" })

    thread, release = in_flight_answer # computed with the check off
    configure({})                      # and the user puts it back
    expect(reported.last).to eq([1, warning])

    release << :go
    thread.join

    expect(reported).to eq([[1, warning], [1, []], [1, warning]])
  end

  # **A → B → A.** The value the user ends on is the value they started
  # from, so a guard that compares configuration *values* admits the
  # answer computed before B and calls it current. P2 requires the
  # comparison to be on the snapshot the analysis actually held: the
  # server exchanges one reference, and the answer in flight belongs to
  # the reference that was replaced.
  #
  # The payload of the refused publish is identical to the one before it,
  # which is exactly why the count is what this example reads -- there is
  # nothing else to see. It distinguishes a value comparison from an
  # identity comparison and nothing else, and that is the decision P2
  # states.
  it "refuses an answer from the replaced configuration even when the current value is equal to it" do
    open_buffer
    analyse_and_publish

    thread, release = in_flight_answer         # computed under the first A
    configure({ "unknown-method" => "none" })  # B
    configure({})                              # A again, a new snapshot with the same value
    expect(reported).to eq([[1, warning], [1, []], [1, warning]])

    release << :go
    thread.join

    expect(reported).to eq([[1, warning], [1, []], [1, warning]])
  end

  # Closing a buffer clears its diagnostics; it does not clear the
  # setting. Reopening the file has to produce the answer the *current*
  # setting asks for -- not the one published before the close, and not
  # the default -- and putting the setting back has to bring the finding
  # back for the reopened buffer.
  it "keeps the configuration across a close and reopen, and regenerates on reset" do
    open_buffer
    analyse_and_publish
    configure({ "unknown-method" => "none" })

    server.send(:handle_did_close, { textDocument: { uri: uri } })
    open_buffer
    analyse_and_publish

    expect(reported).to eq([[1, warning], [1, []], [nil, []], [1, []]])

    configure({})

    expect(reported.last).to eq([1, warning])
  end

  # The close and the configuration change together. The answer in flight
  # belongs to the buffer that was closed, and the reopened buffer is a
  # different one at the same version -- so neither the version nor the
  # generation separates them, and without the buffer identity rule the
  # pre-close warning lands on a buffer whose setting says nothing should
  # be reported. The rule is already there (`037` C3); what this pins is
  # that a configuration change in the gap does not reopen the door.
  it "refuses an answer from the buffer that was closed while the setting changed" do
    open_buffer
    analyse_and_publish

    thread, release = in_flight_answer
    server.send(:handle_did_close, { textDocument: { uri: uri } })
    configure({ "unknown-method" => "none" })
    open_buffer
    analyse_and_publish

    release << :go
    thread.join

    expect(reported).to eq([[1, warning], [nil, []], [1, []]])
  end
end
