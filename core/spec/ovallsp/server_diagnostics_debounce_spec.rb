# frozen_string_literal: true

require "stringio"

# Diagnostics wait for you to stop typing.
#
# Until 0.2.2 every `didChange` published synchronously, in the dispatch
# turn that received it, and two of this project's oldest complaints are
# the same fact seen from different ends:
#
# - **024.41.** Typing `.` reports a method on the *next* line. `a.`
#   followed by `b = "str"` is valid Ruby meaning `a.b = "str"`, so no
#   syntax error marks it as mid-edit and the report is correct about a
#   program nobody is writing. Nothing in the text can tell the two
#   apart — but nobody stays half-way through a name, so waiting is what
#   distinguishes them.
# - **024.45.** Re-analysis costs seconds on a file of a couple of
#   thousand lines, and the Core answers one request at a time, so hover
#   and completion queue behind every keystroke.
#
# What is *not* deferred is the index. `apply_file_summary` still runs in
# the same turn, because completion and hover read it and must see the
# character just typed. Only the publish waits.
#
# A pending publish is superseded rather than queued: the version that
# arrives while waiting replaces the one waiting, so a burst of typing
# produces one publish rather than one per keystroke.
RSpec.describe "Ovallsp::Server diagnostics debounce" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    out = []
    loop { out << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    out
  end

  def diagnostics_for(uri)
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == uri }
  end

  SOURCE = "class Widget\n  def run\n    1\n  end\nend\n"
  MID_EDIT = "class Widget\n  def run\n    a = Widget.new\n    a.\n    b = \"str\"\n  end\nend\n"

  def open_and_change(text, debounce:)
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: "file:///w.rb", text: SOURCE, version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: { textDocument: { uri: "file:///w.rb", version: 2 },
                  contentChanges: [{ text: text }] }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                        diagnostics_debounce: debounce).run
  end

  # `didOpen` is not typing: the file just appeared and there is nothing to
  # wait for.
  it "publishes for a file the moment it is opened" do
    open_and_change(SOURCE, debounce: 30)

    expect(diagnostics_for("file:///w.rb")).not_to be_empty
  end

  it "does not publish again for an edit while the debounce is still running" do
    open_and_change(MID_EDIT, debounce: 30)

    published = diagnostics_for("file:///w.rb")
    expect(published.length).to eq(1)
    expect(published.first[:params][:version]).to eq(1)
  end

  # The half of 024.41 that has no syntax error to gate on: `a.` followed
  # by a clean line parses as `a.b = "str"` and is reported correctly,
  # about a program nobody is writing.
  it "does not report the next line's assignment as a method mid-edit" do
    open_and_change(MID_EDIT, debounce: 30)

    messages_for = diagnostics_for("file:///w.rb").flat_map { |m| m[:params][:diagnostics] }.map { |d| d[:message] }
    expect(messages_for.join(" ")).not_to include("b=")
  end

  # And the boundary: once typing stops, the report arrives. A zero
  # debounce is what every existing example in this suite relies on, so
  # this also states why they still pass.
  it "publishes the edit once the debounce elapses" do
    open_and_change(MID_EDIT, debounce: 0)

    published = diagnostics_for("file:///w.rb")
    expect(published.map { |m| m[:params][:version] }).to include(2)
  end
end
