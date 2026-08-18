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
# the price bought a field nobody reads.
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
# What it does *not* reach, which that branch's rounds 35 and 36 both
# found and 024.56 records: `#republish_open_diagnostics` is another
# publisher, and no row here involves one -- so the tree violates the
# closed-document half of this property today, by that path. **A
# property is only as wide as its table**, and the header above it must
# not claim more than the table covers.

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
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
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
end
