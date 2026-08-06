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
#   followed by `b = "str"` is valid Ruby meaning `a.b = "str"`.
#
# **The debounce does not remove 024.41's report, and this file used to
# claim it did.** It delays it and no more; a user who pauses to read the
# completion popup — which is exactly what one does after typing `.` —
# waits out the debounce and gets it. The example that was here asserted
# the report never came, and passed only because it ran with a 30-second
# debounce and then exited, so *nothing at all* was published. It would
# have passed identically with diagnostics broken outright.
#
# It also asserted the wrong thing. Ruby reads those two lines the same
# way OvalLSP does: `ruby -c` says `Syntax OK`, running it raises
# `undefined method 'b='` on the line OvalLSP marks, and a real `b=`
# setter is really called. The report is *correct* about text the user
# has not finished writing, which is a question about when to publish and
# not about what to report — retargeted to 0.4.0, where withholding it
# means using the edit position and accepting that real errors on that
# line are hidden too.
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
  # comment at the top of this file: the report the debounce was
  # described as removing is right here, once the wait is over — and it
  # agrees with `ruby`, which raises `undefined method 'b='` on the same
  # line. Whoever withholds it at 0.4.0 will have to change this example,
  # which is the point of writing it down.
  it "still reports the next line's assignment as a method once the wait is over" do
    open_and_change(MID_EDIT, debounce: 0)

    messages_for = diagnostics_for("file:///w.rb").flat_map { |m| m[:params][:diagnostics] }.map { |d| d[:message] }
    expect(messages_for.join(" ")).to include("b=")
  end

  # Three keystrokes, one report.
  #
  # Asserted twice, because the two halves have different mechanisms and
  # round 33 found only one of them pinned. What the client is *left with*
  # is guaranteed by the version re-check inside the waiter, and that
  # holds even if every keystroke starts its own waiter. What the burst
  # actually costs -- one analysis rather than three -- is the
  # supersession latch in `#schedule_diagnostics`, and nothing observed it:
  # replacing `first = !@pending_publish.key?(uri)` with `first = true`
  # left this example green while tripling the work.
  BURST = (1..3).map { |n| "class Widget\n  def run\n    1\n  end\nend\n# #{"a" * n}\n" }.freeze

  def burst_input
    did_open +
      did_change(BURST[0], version: 2) +
      did_change(BURST[1], version: 3) +
      did_change(BURST[2], version: 4)
  end

  it "leaves the client holding only the last version of a burst" do
    run_server(burst_input, diagnostics_debounce: 0)

    versions = diagnostics_for("file:///w.rb").map { |m| m[:params][:version] }
    expect(versions.count { |v| [2, 3].include?(v) }).to eq(0)
    expect(versions).to include(4)
  end

  it "analyses a burst once rather than once per keystroke" do
    counting = Class.new(Ovallsp::Server) do
      def self.waiters = @waiters ||= []

      def await_and_publish(uri)
        self.class.waiters << uri
        super
      end
    end

    run_server(burst_input, server_class: counting, diagnostics_debounce: 0)

    expect(counting.waiters.length).to eq(1)
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

    # Bounded at both ends, because only one end is a promise and the
    # other is the whole feature.
    #
    # Above: `docs/design/docs/01-product-requirements.md` states 300 ms
    # for single-file re-analysis, and a user who has stopped typing must
    # not wait longer than the document they were sold.
    #
    # Below: the point is to coalesce a burst of typing, and ordinary
    # typing puts 100--200 ms between keystrokes. A debounce shorter than
    # that coalesces nothing and is 024.45 unfixed — round 33 set the
    # constant to 0.002 and every one of 1,929 examples stayed green,
    # because the only value the examples excluded was exactly zero.
    it "waits long enough to coalesce typing and no longer than the requirements promise" do
      expect(Ovallsp::Server::DEFAULT_DIAGNOSTICS_DEBOUNCE).to be_between(0.1, 0.3)
    end
  end

  # Shutting down costs one budget, however many files are being analysed
  # and however many things join them on the way out.
  #
  # Written as a bound on the *whole* of `#run` rather than on any one
  # join, because the join is where two rounds in a row found a defect and
  # neither was the same mistake twice at that level of detail. Round 32
  # found each waiter given its own full timeout —
  # O(task_count * timeout), the shape `BackgroundTasks#reclaim_batch`'s
  # comment already records an earlier review removing. Round 33 found the
  # shared deadline that replaced it *additive* with
  # `BackgroundTasks#shutdown`'s own, which joins the same threads because
  # they are tracked. Both are invisible to an assertion about one
  # deadline, and both are caught by this.
  #
  # `CLAUDE.md`'s same-place rule asks for a countermeasure rather than a
  # third hand fix. Whatever the next thing to join on the way out turns
  # out to be, it has to fit inside this.
  #
  # Timing, unavoidably: elapsed time is the only observer of "how long
  # shutdown takes". The margin carries it — five waiters, each of which
  # would take 3 s to finish, against a 0.2 s background budget, asserted
  # under 1.5 s. A per-waiter budget is 1 s+ and an additive second one is
  # more; the correct answer is a fifth of a second plus the overhead of
  # starting a server.
  describe "shutting down with several files still being analysed" do
    never_finishes = Class.new(Ovallsp::Server) do
      def with_index_snapshot(&block)
        sleep(3) unless Thread.current == Thread.main
        super
      end
    end

    it "costs one budget in total, whatever joins the waiters" do
      input = (1..5).map do |n|
        uri = "file:///w#{n}.rb"
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: uri, text: SOURCE, version: 1, languageId: "ruby" } }) +
          frame(jsonrpc: "2.0", method: "textDocument/didChange",
                params: { textDocument: { uri: uri, version: 2 }, contentChanges: [{ text: MID_EDIT }] })
      end.join

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_server(input, server_class: never_finishes, diagnostics_debounce: 0,
                        background_task_shutdown_timeout: 0.2)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(elapsed).to be < 1.5
    end

    # And the waiters that have *not* earned their publish do not spend
    # that budget asleep: with a debounce longer than the run, shutdown
    # must not wait for it to elapse.
    it "does not wait out a debounce nobody earned" do
      input = (1..5).map do |n|
        uri = "file:///w#{n}.rb"
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: uri, text: SOURCE, version: 1, languageId: "ruby" } }) +
          frame(jsonrpc: "2.0", method: "textDocument/didChange",
                params: { textDocument: { uri: uri, version: 2 }, contentChanges: [{ text: MID_EDIT }] })
      end.join

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_server(input, diagnostics_debounce: 30, background_task_shutdown_timeout: 0.2)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(elapsed).to be < 1.5
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
        did_open + did_change(UNCLOSED, version: 2) + did_close,
        server_class: slow_publish, diagnostics_debounce: 0
      )

      published = diagnostics_for("file:///w.rb")
      expect(published.map { |m| m[:params][:version] }).not_to include(2)
      expect(published.last[:params][:diagnostics]).to be_empty
    end
  end

  def did_close
    frame(jsonrpc: "2.0", method: "textDocument/didClose",
          params: { textDocument: { uri: "file:///w.rb" } })
  end

  # The *other* half of the same guarantee, and the half the example above
  # cannot reach.
  #
  # Above, the waiter is held before it re-reads the document store, so
  # what stops the publish is the store already being closed — which works
  # whether or not `#handle_did_close` takes `@pending_publish_mutex`.
  # Round 33 removed that call and the whole suite stayed green: a fixture
  # that cannot distinguish the two candidate behaviours, which is the
  # shape this very file's header calls out about the example it replaced.
  #
  # So hold the waiter *after* the re-read instead, inside the write. Now
  # the store is still open when it checks, and only the mutex decides
  # what the client is left holding: taken, `didClose` waits and its clear
  # is the last word; not taken, the clear lands first and the findings
  # after it, on a file nobody has open.
  describe "a document closed while its diagnostics are being written" do
    slow_write = Class.new(Ovallsp::Server) do
      def initialize(**kwargs)
        @writing = Queue.new
        super
      end

      def publish_findings(uri, findings, version: nil)
        unless Thread.current == Thread.main
          @writing << :reached
          sleep(0.3)
        end
        super
      end

      def handle_did_close(params)
        @writing.pop(timeout: 2)
        super
      end
    end

    it "leaves the panel clear rather than the findings" do
      run_server(
        did_open + did_change(UNCLOSED, version: 2) + did_close,
        server_class: slow_write, diagnostics_debounce: 0
      )

      expect(diagnostics_for("file:///w.rb").last[:params][:diagnostics]).to be_empty
    end
  end
end
