# frozen_string_literal: true

require "stringio"

# What the client is holding when the dust settles.
#
# One invariant, over sequences of the notifications a client actually
# sends: **an open document's last published diagnostics are for its
# current version, and a closed document's are empty.** Nothing else here
# is about a particular bug.
#
# It exists because the debounce is the second place two review rounds in
# a row have found a defect, and each was a different way for the same
# three pieces of state to disagree -- `@pending_publish`'s captured
# version, `@document_store`'s current one, and whether a waiter is alive
# to reconcile them:
#
# - **Round 32** found `didClose` racing a publish that was already
#   computing, so findings landed after the panel was cleared.
# - **Round 33** found a `didChange` whose text is byte-identical to the
#   indexed text discarding the *previous* edit's pending report, because
#   `#reindex` reached `#schedule_diagnostics` only when
#   `apply_file_summary` returned true, and `WorkspaceIndex#replace_file`
#   returns false for identical content. The pending entry kept the older
#   version, the waiter fired, saw a mismatch and published nothing. A
#   file with a syntax error, and an empty Problems panel until the next
#   edit that changes bytes.
#
# `CLAUDE.md`'s same-place rule asks for a mechanical countermeasure at
# that point rather than a third hand-written regression test. This is it:
# a regression test pins the one sequence someone thought of, and this
# pins the property for every sequence in the table -- including the ones
# added by whoever finds the next defect.
#
# Run with a zero debounce, so nothing is dropped for not having been
# earned and every publish the design promises is one the example can
# demand.
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
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                        diagnostics_debounce: 0).run
  end

  # `[description, notifications, final version]`. A `nil` final version
  # means the document ends closed.
  [
    ["one edit",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2)] }, 2],
    ["two edits",
     -> { [did_open(CLEAN), did_change(CLEAN_AGAIN, version: 2), did_change(BROKEN, version: 3)] }, 3],
    ["an edit whose text is identical to the one before it",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2), did_change(BROKEN, version: 3)] }, 3],
    ["an edit whose text is identical to what was opened",
     -> { [did_open(BROKEN), did_change(BROKEN, version: 2)] }, 2],
    ["an identical edit followed by a real one",
     -> { [did_open(CLEAN), did_change(CLEAN, version: 2), did_change(BROKEN, version: 3)] }, 3],
    ["an edit and then a close",
     -> { [did_open(CLEAN), did_change(BROKEN, version: 2), did_close] }, nil]
  ].each do |description, notifications, final_version|
    context "after #{description}" do
      before { run_sequence(*instance_exec(&notifications)) }

      if final_version
        it "leaves the client holding diagnostics for version #{final_version}" do
          expect(published).not_to be_empty
          expect(published.last[:version]).to eq(final_version)
        end

        # The half that makes the version assertion mean something: a
        # server that published an empty report for the right version
        # would satisfy it, and the panel would still be wrong.
        it "leaves the syntax error visible" do
          expect(published.last[:diagnostics]).not_to be_empty
        end
      else
        it "leaves the client holding nothing" do
          expect(published.last[:diagnostics]).to be_empty
        end
      end
    end
  end
end
