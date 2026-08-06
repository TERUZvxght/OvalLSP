# frozen_string_literal: true

require "stringio"

# Diagnostics wait for you to stop typing.
#
# Until 0.2.2 every `didChange` published synchronously, in the dispatch
# turn that received it, and two of this project's oldest complaints are
# the same fact seen from different ends:
#
# - **024.45.** Re-analysis costs seconds on a file of a couple of
#   thousand lines, and the Core answers one request at a time, so hover
#   and completion queue behind every keystroke. Waiting removes most of
#   that work outright.
# - **024.41.** Typing `.` reports a method on the *next* line. `a.`
#   followed by `b = "str"` is valid Ruby meaning `a.b = "str"`, so no
#   syntax error marks it as mid-edit and the report is correct about a
#   program nobody is writing.
#
# **The debounce does not fix 024.41, and this file used to claim it
# did.** It delays that report by the debounce and no more; a user who
# pauses to read the completion popup — which is exactly what one does
# after typing `.` — waits out the debounce and gets it. The example that
# was here asserted the report never came, and passed only because it ran
# with a 30-second debounce and then exited, so *nothing at all* was
# published. It would have passed identically with diagnostics broken
# outright. 024.41 stays open.
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

  def did_open(text = SOURCE)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: "file:///w.rb", text: text, version: 1, languageId: "ruby" } }
    )
  end

  def did_change(text, version:)
    frame(
      jsonrpc: "2.0", method: "textDocument/didChange",
      params: { textDocument: { uri: "file:///w.rb", version: version }, contentChanges: [{ text: text }] }
    )
  end

  def run_server(input, server_class: Ovallsp::Server, **options)
    server_class.new(input: StringIO.new(input + frame(jsonrpc: "2.0", method: "exit", params: nil)),
                     output: output, logger: logger, **options).run
  end

  def open_and_change(text, debounce:)
    run_server(did_open + did_change(text, version: 2), diagnostics_debounce: debounce)
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

  # And the boundary: once typing stops, the report arrives. A zero
  # debounce is what every existing example in this suite relies on, so
  # this also states why they still pass.
  it "publishes the edit once the debounce elapses" do
    open_and_change(MID_EDIT, debounce: 0)

    published = diagnostics_for("file:///w.rb")
    expect(published.map { |m| m[:params][:version] }).to include(2)
  end

  # 024.41, stated as what it actually is. Nobody has to believe the
  # comment at the top of this file: the report the debounce is described
  # as removing is right here, once the wait is over.
  it "still reports the next line's assignment as a method once the wait is over" do
    open_and_change(MID_EDIT, debounce: 0)

    messages_for = diagnostics_for("file:///w.rb").flat_map { |m| m[:params][:diagnostics] }.map { |d| d[:message] }
    expect(messages_for.join(" ")).to include("b=")
  end

  # Three keystrokes, one report. Without supersession each `didChange`
  # would start its own waiter and publish its own version; the versions
  # are what distinguish the two, so they are what is asserted.
  it "publishes once for a burst of edits rather than once per keystroke" do
    run_server(
      did_open +
      did_change("class Widget\n  def run\n    1\n  end\nend\n# a\n", version: 2) +
      did_change("class Widget\n  def run\n    1\n  end\nend\n# ab\n", version: 3) +
      did_change("class Widget\n  def run\n    1\n  end\nend\n# abc\n", version: 4),
      diagnostics_debounce: 0
    )

    versions = diagnostics_for("file:///w.rb").map { |m| m[:params][:version] }
    expect(versions.count { |v| [2, 3].include?(v) }).to eq(0)
    expect(versions).to include(4)
  end

  # The debounce a user gets. Every other example here passes an explicit
  # value, so without this the constant the whole release turns on could
  # be set to anything -- including 0, which switches the feature off, or
  # 30, which switches diagnostics off -- with the suite still green.
  describe "the default" do
    it "is what a server built without the keyword waits" do
      run_server(did_open + did_change(MID_EDIT, version: 2))

      # Reached `exit` well inside 300 ms, so the edit is still waiting
      # and shutdown drops it. A default of 0 would have published it.
      expect(diagnostics_for("file:///w.rb").map { |m| m[:params][:version] }).not_to include(2)
    end

    # `docs/design/docs/01-product-requirements.md` states 300 ms for
    # single-file re-analysis. A user who has stopped typing must not wait
    # longer than the document they were sold.
    it "does not exceed the re-analysis budget the requirements state" do
      expect(Ovallsp::Server::DEFAULT_DIAGNOSTICS_DEBOUNCE).to be <= 0.3
    end
  end

  # Shutting down joins the waiters, and the whole batch shares one
  # deadline. `BackgroundTasks#reclaim_batch` carries the same rule
  # because an independent review found an earlier version giving each
  # task its own full timeout, making shutdown
  # O(task_count * timeout) -- and this join runs *before* that budget
  # starts, so a per-thread deadline here puts the shape straight back.
  #
  # Timing, unavoidably: "one deadline or several" is a statement about
  # elapsed time and nothing else observes it. The margin is what keeps it
  # honest -- three waiters at 0.5 s each is 1.5 s against a shared 0.5 s,
  # and the assertion sits at 1.0 s.
  describe "shutting down with several files still being analysed" do
    never_finishes = Class.new(Ovallsp::Server) do
      def with_index_snapshot(&block)
        sleep(3) unless Thread.current == Thread.main
        super
      end
    end

    it "spends one timeout in total, not one per file" do
      stub_const("Ovallsp::Server::FLUSH_JOIN_TIMEOUT", 0.5)
      input = (1..3).map do |n|
        uri = "file:///w#{n}.rb"
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: uri, text: SOURCE, version: 1, languageId: "ruby" } }) +
          frame(jsonrpc: "2.0", method: "textDocument/didChange",
                params: { textDocument: { uri: uri, version: 2 }, contentChanges: [{ text: MID_EDIT }] })
      end.join

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_server(input, server_class: never_finishes, diagnostics_debounce: 0,
                        background_task_shutdown_timeout: 0.05)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(elapsed).to be < 1.0
    end
  end

  # Closing a document has to beat a publish that is already computing.
  # The analysis runs without the index lock held, so `didClose` can clear
  # the panel in the gap between "findings computed" and "findings
  # written" -- 2--5 s wide on a large file by this project's own
  # measurement (024.45). The sleep below stands in for that gap.
  describe "a document closed while its diagnostics are being computed" do
    # A rendezvous rather than two sleeps. The waiter has to have read the
    # document *before* `didClose` runs -- that is the whole scenario, and
    # if the two are merely started near each other the dispatch thread
    # wins the race every time and the example passes without testing
    # anything. So: the waiter announces that it has the document and is
    # about to analyse it, `didClose` proceeds only once that has
    # happened, and the analysis is held long enough for the close to
    # complete.
    slow_publish = Class.new(Ovallsp::Server) do
      def initialize(**kwargs)
        @computing = Queue.new
        super
      end

      # Announced before `super`, so no lock is held while the close runs
      # -- holding one would serialise the two and remove the gap.
      def with_index_snapshot(&block)
        unless Thread.current == Thread.main
          @computing << :reached
          sleep(0.3)
        end
        super
      end

      def handle_did_close(params)
        @computing.pop(timeout: 2)
        super
      end
    end

    # A syntax error, deliberately, rather than the unknown-method report
    # the other examples use. `didClose` removes the file's index
    # contribution, so a semantic finding computed after it comes back
    # empty and an assertion about *counts* would pass on a server that
    # publishes after the close anyway. A syntax error needs no index and
    # survives, which is what makes the two behaviours look different.
    UNCLOSED = "class Widget\n  def run\n    1\n  end\n"

    it "publishes nothing after the panel has been cleared" do
      run_server(
        did_open + did_change(UNCLOSED, version: 2) +
        frame(jsonrpc: "2.0", method: "textDocument/didClose",
              params: { textDocument: { uri: "file:///w.rb" } }),
        server_class: slow_publish, diagnostics_debounce: 0
      )

      published = diagnostics_for("file:///w.rb")
      expect(published.map { |m| m[:params][:version] }).not_to include(2)
      expect(published.last[:params][:diagnostics]).to be_empty
    end
  end
end
