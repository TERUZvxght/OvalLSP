# frozen_string_literal: true

require "stringio"

# What the client is holding when the dust settles.
#
# One invariant, over sequences of the notifications a client actually
# sends: **the last diagnostics published for an open document describe
# its current text, and a closed document's are empty.**
#
# Stated about the *text*, not about the version number, and that is the
# correction the 0.2.4-bound branch's round 36 forced. The first version asserted that the last
# publish carried the document's current `version`, which is a stronger
# claim than the server needs to make -- a `didChange` whose text is
# byte-identical to what is indexed has nothing new to say, and the
# report already on the client is still right about the text. Making that
# assertion true cost a full re-analysis of the file: measured 0.015 s
# before and 2.098 s after on a 2,574-line file, under the lock hover and
# completion need. VS Code does not discard diagnostics on version, so
# the price bought a field nobody reads -- `docs/CLIENT_BEHAVIOUR.md`
# carries that fact and the source line showing it. This file said it
# first and was contradicted by three others for a release, which is why
# the fact now has one home.
#
# What the property is *for* survives the correction. That branch's
# round 33 found the shape it guards against -- a byte-identical
# `didChange` discarding the previous edit's pending report under the
# debounce -- leaving the panel showing a clean file whose text had a
# syntax error, which is a text mismatch and fails here.
#
# It was written as the countermeasure for a didChange debounce built
# and rolled back on the 0.2.4-bound branch (fix/0.2.3 -- its own
# review-loop record holds that thread), and it **outlived the change
# it was written for**: the debounce is gone and this holds for the
# synchronous path every release ships. That is the argument for
# writing a property rather than a regression test.
#
# **The publisher this did not reach, until 0.2.18.** Rounds 35 and 36 of
# that branch found `#republish_open_diagnostics` to be a fourth writer
# with no row here, and this header used to end by saying the tree
# violated the closed-document half of the property by that path. It
# does not any more -- `#publish_findings`' rule that a versioned publish
# belongs to a buffer still open was built after those rounds, for
# exactly this -- and there are three rows for it now, including the
# ordering that actually was the defect: computed while the buffer was
# open, published after the close landed. `024.57`.
#
# **A property is only as wide as its table** stays true, and is why the
# rows exist rather than why the note did.

RSpec.describe "Ovallsp::Server publish invariant" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  URI_UNDER_TEST = "file:///invariant.rb"

  # Three texts: two that differ, and one byte-identical to another, which
  # is the distinction round 33's defect turned on. `BROKEN` carries a
  # syntax error so that a missing publish is visible as an empty panel
  # rather than as two indistinguishable empty ones.
  CLEAN = "class Widget\n  def run\n    1\n  end\nend\n"
  BROKEN = "class Widget\n  def run\n    1\n  end\n"
  CLEAN_AGAIN = "class Widget\n  def run\n    2\n  end\nend\n"

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def did_open(text) = frame(jsonrpc: "2.0", method: "textDocument/didOpen",
                             params: { textDocument: { uri: URI_UNDER_TEST, text: text,
                                                       version: 1, languageId: "ruby" } })

  def did_change(text, version:) = frame(jsonrpc: "2.0", method: "textDocument/didChange",
                                         params: { textDocument: { uri: URI_UNDER_TEST, version: version },
                                                   contentChanges: [{ text: text }] })

  def did_close = frame(jsonrpc: "2.0", method: "textDocument/didClose",
                        params: { textDocument: { uri: URI_UNDER_TEST } })


  def published
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    out = []
    loop do
      message = reader.read_message
      next unless message[:method] == "textDocument/publishDiagnostics"
      next unless message[:params][:uri] == URI_UNDER_TEST

      out << message[:params]
    end
  rescue Ovallsp::IO::FramedReader::EOF
    out
  end

  def run_sequence(*notifications)
    input = notifications.join + frame(jsonrpc: "2.0", method: "exit", params: nil)
    server = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger)
    server.run
    server
  end

  # `[description, notifications, ends_broken]`. `nil` means the document
  # ends closed; `true`/`false` is whether its final text has a syntax
  # error, which is what the last publish has to agree with.
  [
    ["one edit",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2)] }, true],
    ["two edits",
     -> { [did_open(CLEAN), did_change(CLEAN_AGAIN, version: 2), did_change(BROKEN, version: 3)] }, true],
    ["an edit that repairs the file",
     -> { [did_open(BROKEN), did_change(CLEAN, version: 2)] }, false],
    ["an edit whose text is identical to the one before it",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2), did_change(BROKEN, version: 3)] }, true],
    ["an edit whose text is identical to what was opened",
     -> { [did_open(BROKEN), did_change(BROKEN, version: 2)] }, true],
    ["an identical edit followed by a real one",
     -> { [did_open(CLEAN), did_change(CLEAN, version: 2), did_change(BROKEN, version: 3)] }, true],
    ["an edit and then a close",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2), did_close] }, nil]
  ].each do |description, notifications, ends_broken|
    context "after #{description}" do
      before { run_sequence(*instance_exec(&notifications)) }

      if ends_broken.nil?
        it "leaves the client holding nothing" do
          expect(published.last[:diagnostics]).to be_empty
        end
      elsif ends_broken
        it "leaves the syntax error visible" do
          expect(published).not_to be_empty
          expect(published.last[:diagnostics]).not_to be_empty
        end
      else
        # The excluding direction. Without it a server that published a
        # syntax error and then never spoke again would satisfy every
        # other row in this table.
        it "leaves nothing behind once the file parses again" do
          expect(published).not_to be_empty
          expect(published.last[:diagnostics]).to be_empty
        end
      end
    end
  end

  # **The publisher this table did not reach**, and the reason its header
  # used to end by saying so. Rounds 35 and 36 of the rolled-back
  # debounce found that `#republish_open_diagnostics` is a fourth writer
  # and no row here involved one — "a property is only as wide as its
  # table".
  #
  # Its six call sites are all Agent-driven — routes arriving, models
  # refreshing, the Agent restarting — and every one runs on a background
  # thread, which is what made the original race a race. Booting an Agent
  # to reach them would make this a different spec, so the publisher is
  # called directly: what is under test is the publisher, not the road to
  # it.
  #
  # It passes today, and it did not when the note was written. What
  # closed it is `#publish_findings`' rule that a versioned publish
  # belongs to a buffer that is still open — built after those rounds,
  # for exactly this. The note is removed rather than kept as a warning
  # about something that no longer happens.
  describe "a republish that runs after the document was closed" do
    it "publishes nothing for it" do
      server = run_sequence(did_open(CLEAN), did_change(BROKEN, version: 2), did_close)
      before = published.length

      server.send(:republish_open_diagnostics)

      expect(published.length).to eq(before), "the republish wrote for a document nobody has open"
      expect(published.last[:diagnostics]).to be_empty
    end

    # The control. If `run_sequence` left no document open for reasons of
    # its own, the example above would pass with the publisher doing
    # nothing at all — so an *open* document must still be republished.
    it "still publishes for a document that is open" do
      server = run_sequence(did_open(BROKEN))
      before = published.length

      server.send(:republish_open_diagnostics)

      expect(published.length).to be > before
      expect(published.last[:diagnostics]).not_to be_empty
    end

    # **And the sequence that actually was the defect**, which the two
    # above do not reach: the republish snapshots the open documents and
    # then computes, and the close lands *during* the computation. By the
    # time it publishes, the buffer is gone — but it is holding findings
    # it computed while the buffer was still there.
    #
    # Reproduced deterministically by closing the document from inside
    # the analysis rather than by racing a thread: the ordering under
    # test is "computed before, published after", and that is exactly
    # what this produces.
    it "publishes nothing when the close lands while it is still computing" do
      server = run_sequence(did_open(BROKEN))
      before = published.length
      store = server.instance_variable_get(:@document_store)
      engine = server.instance_variable_get(:@diagnostics_engine)
      real = engine.method(:analyze)
      allow(engine).to receive(:analyze) do |**kwargs|
        findings = real.call(**kwargs)
        store.close(uri: URI_UNDER_TEST)
        findings
      end

      server.send(:republish_open_diagnostics)

      expect(published.length).to eq(before),
                                  "wrote findings computed before a close that had already landed"
    end
  end
end
