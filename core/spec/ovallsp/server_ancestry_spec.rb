# frozen_string_literal: true

require "stringio"

# The reopened-gem-class false positive (024.R5) end to end through
# Server: the check meets a receiver it cannot judge statically, the
# question reaches the Runtime Agent, and the already-open document is
# answered again once it comes back.
RSpec.describe "Ovallsp::Server ancestry questions for the Runtime Agent" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:ancestry_registry) { Ovallsp::Runtime::AncestryRegistry.new }

  # Every Rails application's test/test_helper.rb, reduced to the shape
  # that matters: a class whose real definition lives in a gem, reopened
  # by a workspace file, calling the gem's own API.
  #
  # A `let`, not a constant: a constant assigned inside a describe block
  # lands on Object and is visible to every other spec file in the run.
  # This suite has already been bitten by that once, when two files
  # defined the same fixture constant and the second silently won.
  let(:reopened_gem_class) do
    <<~RUBY
      module ActiveSupport
        class TestCase
          fixtures :all
        end
      end
    RUBY
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def open_and_exit(uri: "file:///workspace/test/test_helper.rb", text: reopened_gem_class)
    frame(jsonrpc: "2.0", method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)
  end

  def build_server(input_string, agent_manager:)
    server = Ovallsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger,
      workspace_root: "/workspace", ancestry_registry: ancestry_registry
    )
    server.instance_variable_set(:@agent_manager, agent_manager)
    server
  end

  def manager_answering(answers, asked: nil)
    Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        asked&.<<(names)
        { objectAncestors: %w[Object Kernel BasicObject],
          classes: names.to_h { |name| [name.to_sym, answers[name]] } }
      end
    end
  end

  def published_diagnostics(uri)
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

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "asks the Agent about a receiver the static chain cannot judge" do
    asked = Queue.new
    server = build_server(open_and_exit, agent_manager: manager_answering({}, asked: asked))

    server.run
    server.shutdown_background_tasks if server.respond_to?(:shutdown_background_tasks)

    expect(wait_until { asked.size.positive? }).to be(true)
    expect(asked.pop).to include("ActiveSupport::TestCase")
  end

  it "installs the answer, so the receiver is judged rather than re-asked" do
    server = build_server(
      open_and_exit,
      agent_manager: manager_answering(
        { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
      )
    )

    server.run

    expect(wait_until { !ancestry_registry.entry("ActiveSupport::TestCase").nil? }).to be(true)
    expect(ancestry_registry.entry("ActiveSupport::TestCase").foreign_ancestors)
      .to eq(["ActiveSupport::Testing::Assertions"])
  end

  # The ordering a user actually has: the file is already open, diagnosed
  # against no answer at all, when the answer lands. Without a republish
  # the first (empty) result would stand until the file was edited.
  it "answers the already-open document again once the ancestors arrive" do
    server = build_server(
      open_and_exit,
      agent_manager: manager_answering({ "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase Object Kernel BasicObject] } })
    )

    server.run

    expect(wait_until { published_diagnostics("file:///workspace/test/test_helper.rb").size >= 2 }).to be(true)
    # The application confirms the workspace's own ancestry, so the call
    # really is unknown and the second answer says so.
    last = published_diagnostics("file:///workspace/test/test_helper.rb").last
    expect(last[:params][:diagnostics].map { |d| d[:code] }).to include("unknown-method")
  end

  it "reports nothing for the reopened class once the Agent has confirmed it is foreign" do
    server = build_server(
      open_and_exit,
      agent_manager: manager_answering(
        { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
      )
    )

    server.run

    expect(wait_until { !ancestry_registry.entry("ActiveSupport::TestCase").nil? }).to be(true)
    expect(wait_until { published_diagnostics("file:///workspace/test/test_helper.rb").size >= 2 }).to be(true)
    last = published_diagnostics("file:///workspace/test/test_helper.rb").last
    expect(last[:params][:diagnostics].map { |d| d[:code] }).not_to include("unknown-method")
  end

  it "does not ask when no Agent is connected, and still reports statically" do
    server = build_server(open_and_exit, agent_manager: nil)

    server.run

    expect(ancestry_registry.drain_pending).to be_empty
    first = published_diagnostics("file:///workspace/test/test_helper.rb").first
    expect(first[:params][:diagnostics].map { |d| d[:code] }).to include("unknown-method")
  end

  # Ancestors cannot change without a restart, which is exactly why a
  # restart must drop them: the application that comes back may have a
  # different Gemfile, a different environment, different ancestors.
  it "forgets every answer when the Agent restarts" do
    ancestry_registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } })
    server = build_server("", agent_manager: nil)

    server.send(:restart_agent)

    expect(wait_until { ancestry_registry.entry("Widget").nil? }).to be(true)
  end

  # A crash-looped Agent is indistinguishable from no Agent to the user,
  # and the check must treat it that way. Deferring is only right while an
  # answer can still arrive; once the supervisor has given up, deferring
  # forever *is* disabling the check -- which is precisely what the
  # deferral rule exists to avoid.
  it "stops deferring once the Agent has crash-looped past its retry budget" do
    server = build_server("", agent_manager: nil)
    ancestry_registry.activate!
    ancestry_registry.install(object_ancestors: %w[Object], classes: { "Known" => nil })
    supervisor = server.instance_variable_get(:@agent_supervisor)
    allow(supervisor).to receive(:record_failure_and_next_delay).and_return(nil)

    server.send(:handle_agent_unavailable, "crash")

    expect(ancestry_registry).not_to be_active
    # Answers already given stay: they were true about the application that
    # was running, and dropping them would be a fresh crop of false reports.
    expect(ancestry_registry.entry("Known")).not_to be_nil
  end

  # The ordinary VS Code startup path: editors are restored and opened
  # immediately, and a real Rails boot then takes tens of seconds. The
  # document is diagnosed with no Agent in place, so the check does not
  # defer and reports the very false positives this release removes -- and
  # the snapshot's own republish runs from inside the bootstrap, before
  # @agent_manager is assigned, so it does not fix them either.
  it "answers an already-open document once the Agent is actually in place" do
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:status) { :ready }
      define_singleton_method(:stop) { nil }
      define_singleton_method(:fetch_ancestors) do |names, **|
        { objectAncestors: %w[Object Kernel BasicObject],
          classes: names.to_h { |n| [n.to_sym, { definedOutsideWorkspace: true }] } }
      end
    end
    bootstrap = Class.new do
      define_singleton_method(:start) { |**| manager }
    end
    server = Ovallsp::Server.new(
      input: StringIO.new(""), output: output, logger: logger,
      workspace_root: "/workspace", ancestry_registry: ancestry_registry, agent_bootstrap: bootstrap
    )

    # The document is opened and diagnosed first, with no Agent assigned --
    # the ordering VS Code produces by restoring its editors at startup.
    uri = "file:///workspace/test/test_helper.rb"
    document = server.instance_variable_get(:@document_store)
                     .open(uri: uri, text: reopened_gem_class, version: 1, language_id: "ruby")
    server.send(:reindex, document)
    server.send(:publish_diagnostics, document)
    before = published_diagnostics(uri).size
    expect(before).to be_positive

    # Then the Agent arrives.
    server.send(:restart_agent)
    expect(wait_until { published_diagnostics(uri).size > before }).to be(true)
    expect(published_diagnostics(uri).last[:params][:diagnostics].map { |d| d[:code] })
      .not_to include("unknown-method")
  end

  # `install_agent_snapshot` republishes too, and that call was pinned by
  # nothing: commenting it out left the whole suite green, the G12
  # capability example included. G12 could not see it because 024.24's
  # fix means a route diagnostic is no longer published before the Agent
  # arrives, so "it clears" is satisfied by a world where nothing was
  # ever published.
  #
  # An end-to-end example was tried first and was flaky: it needs a
  # second Core and a second Rails boot against the one fixture app, and
  # failed under some orderings. The property is about the Server, so it
  # is pinned at the Server.
  it "answers an already-open document when a snapshot is installed" do
    server = Ovallsp::Server.new(
      input: StringIO.new(""), output: output, logger: logger,
      workspace_root: "/workspace", ancestry_registry: ancestry_registry
    )
    uri = "file:///workspace/test/test_helper.rb"
    document = server.instance_variable_get(:@document_store)
                     .open(uri: uri, text: reopened_gem_class, version: 1, language_id: "ruby")
    server.send(:reindex, document)
    server.send(:publish_diagnostics, document)
    before = published_diagnostics(uri).size
    expect(before).to be_positive

    server.send(:install_agent_snapshot, routes: [], models: [])

    expect(wait_until { published_diagnostics(uri).size > before }).to be(true)
  end

  # The same ordering on the *first* boot rather than a restart, which is
  # the path an ordinary session actually takes: `initialized` starts the
  # bootstrap, the editor opens its restored files while it runs, and the
  # manager is only assigned when it returns.
  it "answers an already-open document once the initial bootstrap finishes" do
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:status) { :ready }
      define_singleton_method(:stop) { nil }
      define_singleton_method(:fetch_ancestors) do |names, **|
        { objectAncestors: %w[Object Kernel BasicObject],
          classes: names.to_h { |n| [n.to_sym, { definedOutsideWorkspace: true }] } }
      end
    end
    bootstrap = Class.new { define_singleton_method(:start) { |**| manager } }
    server = Ovallsp::Server.new(
      input: StringIO.new(""), output: output, logger: logger,
      workspace_root: "/workspace", ancestry_registry: ancestry_registry, agent_bootstrap: bootstrap
    )

    uri = "file:///workspace/test/test_helper.rb"
    document = server.instance_variable_get(:@document_store)
                     .open(uri: uri, text: reopened_gem_class, version: 1, language_id: "ruby")
    server.send(:reindex, document)
    server.send(:publish_diagnostics, document)
    before = published_diagnostics(uri).size

    # Trust is server state now, not an argument -- `maybe_start_agent`
    # takes none, so that no caller can believe it grants permission by
    # passing one.
    server.instance_variable_set(:@workspace_trusted, true)
    server.send(:maybe_start_agent)

    expect(wait_until { published_diagnostics(uri).size > before }).to be(true)

    # Reported at first, because there was no Agent to ask yet; silent once
    # there is one, without the user touching the file.
    expect(published_diagnostics(uri).first[:params][:diagnostics].map { |d| d[:code] }).to include("unknown-method")
    expect(published_diagnostics(uri).last[:params][:diagnostics].map { |d| d[:code] }).not_to include("unknown-method")
  end

  # Giving up has to mean giving up *asking*. The failure path re-queues
  # its names, so the queue never empties again after a give-up -- and
  # every later publish would spawn another worker to block for the full
  # timeout against an Agent already known not to answer.
  it "stops asking once it has given up on the Agent" do
    calls = 0
    lock = Mutex.new
    warnings = []
    allow(logger).to receive(:warn) { |message| warnings << message }
    failing = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |_names, **|
        lock.synchronize { calls += 1 }
        nil
      end
    end
    server = build_server("", agent_manager: failing)
    ancestry_registry.activate!

    8.times do |i|
      ancestry_registry.request("Widget#{i}")
      server.send(:answer_pending_ancestry_questions)
      expect(wait_until { !server.instance_variable_get(:@ancestry_question_worker)&.alive? }).to be(true)
    end

    expect(ancestry_registry).not_to be_active
    expect(lock.synchronize { calls }).to eq(Ovallsp::Runtime::AncestryRegistry::FAILURE_LIMIT)
    # Said once, at the moment the decision is made -- not on every failure
    # from then on, which would fill the log without adding information.
    expect(warnings.count { |w| w.include?("falling back to static analysis") }).to eq(1)
  end

  # A retired manager refuses every request, so its `nil` is evidence that
  # the Agent was replaced, not that the application stopped answering.
  # The worker therefore reports the failure against the epoch it started
  # in, not whatever the current one has become.
  it "does not count a failure against an Agent that was replaced mid-fetch" do
    gate = Queue.new
    started = Queue.new
    retiring = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |_names, **|
        started << :fetching
        gate.pop
        nil
      end
    end
    server = build_server("", agent_manager: retiring)
    ancestry_registry.activate!

    ancestry_registry.request("Widget")
    server.send(:answer_pending_ancestry_questions)
    expect(wait_until { started.size == 1 }).to be(true)
    ancestry_registry.reset # the Agent is replaced while the fetch is out
    gate << :go
    expect(wait_until { !server.instance_variable_get(:@ancestry_question_worker)&.alive? }).to be(true)

    # That failure belonged to the old Agent, so the new one still has its
    # whole budget: one short of the limit must not trip it.
    ancestry_registry.activate!
    (Ovallsp::Runtime::AncestryRegistry::FAILURE_LIMIT - 1).times do
      ancestry_registry.note_failure(epoch: ancestry_registry.epoch)
    end

    expect(ancestry_registry).to be_active
  end

  # If spawning the worker raises, the slot is held by :claiming and no
  # worker exists to hand it back -- every deferred receiver would stay
  # silent for the rest of the session.
  it "frees the slot when the fetch thread cannot be spawned" do
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| nil }
    end
    server = build_server("", agent_manager: manager)
    ancestry_registry.activate!
    ancestry_registry.request("Widget")
    allow(Thread).to receive(:new).and_raise(ThreadError, "cannot create thread")

    expect { server.send(:answer_pending_ancestry_questions) }.to raise_error(ThreadError)

    expect(server.instance_variable_get(:@ancestry_question_worker)).to be_nil
  end

  # The dispatch runs in publish_diagnostics' ensure, so a failure there
  # escapes into whatever rescued the caller and is reported as that
  # caller's problem -- "failed to summarize <uri>" for a failure that had
  # nothing to do with summarising.
  it "reports a dispatch failure as its own, not as the document's" do
    errors = []
    allow(logger).to receive(:error) { |message| errors << message }
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| nil }
    end
    server = build_server("", agent_manager: manager)
    uri = "file:///workspace/test/test_helper.rb"
    document = server.instance_variable_get(:@document_store)
                     .open(uri: uri, text: reopened_gem_class, version: 1, language_id: "ruby")
    ancestry_registry.activate!
    ancestry_registry.request("ActiveSupport::TestCase")
    allow(Thread).to receive(:new).and_raise(ThreadError, "cannot create thread")

    expect { server.send(:publish_diagnostics, document) }.not_to raise_error

    expect(errors.find { |e| e.include?("pending ancestries") }).to include("ThreadError")
    expect(errors).to all(satisfy { |e| !e.include?("failed to compute diagnostics") })
  end

  # The slot bookkeeping is what single-flight rests on, and both guards
  # exist so a finishing worker cannot trample a successor's claim. Driven
  # directly, because a test that only runs one worker's lifetime cannot
  # tell a guarded assignment from an unguarded one.
  describe "slot ownership" do
    let(:server) { build_server("", agent_manager: nil) }
    let(:incumbent) { Thread.new { sleep 5 } }

    after { incumbent.kill }

    it "does not let a departing worker clear a successor's slot" do
      server.instance_variable_set(:@ancestry_question_worker, incumbent)

      # A different thread than the incumbent, i.e. an earlier worker
      # finishing after the slot has already been handed on.
      Thread.new { server.send(:release_ancestry_question_slot) }.join

      expect(server.instance_variable_get(:@ancestry_question_worker)).to eq(incumbent)
    end

    it "does not let a stale adoption overwrite a live worker" do
      server.instance_variable_set(:@ancestry_question_worker, incumbent)

      server.send(:adopt_ancestry_question_worker, Thread.new { nil })

      expect(server.instance_variable_get(:@ancestry_question_worker)).to eq(incumbent)
    end

    it "clears the slot for the worker that actually holds it" do
      done = Queue.new
      worker = Thread.new do
        server.instance_variable_set(:@ancestry_question_worker, Thread.current)
        server.send(:release_ancestry_question_slot)
        done << :released
      end
      done.pop
      worker.join

      expect(server.instance_variable_get(:@ancestry_question_worker)).to be_nil
    end
  end

  # An Agent that is `ready?` but has stopped answering is the state
  # nothing else notices: the ancestry fetch deliberately does not tear the
  # Agent down over a timeout, and the retry is deliberately not automatic.
  # Without a bound the check just defers forever and goes silent.
  it "falls back to static analysis after the Agent has failed to answer repeatedly" do
    failing = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| nil }
    end
    server = build_server("", agent_manager: failing)
    ancestry_registry.activate!

    Ovallsp::Runtime::AncestryRegistry::FAILURE_LIMIT.times do |i|
      ancestry_registry.request("Widget#{i}")
      server.send(:answer_pending_ancestry_questions)
      expect(wait_until { !server.instance_variable_get(:@ancestry_question_worker)&.alive? }).to be(true)
    end

    expect(ancestry_registry).not_to be_active
  end

  it "forgets earlier failures once the Agent answers again" do
    answers = 0
    lock = Mutex.new
    flaky = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        lock.synchronize { answers += 1 }
        next nil if lock.synchronize { answers } == 1

        { objectAncestors: %w[Object], classes: names.to_h { |n| [n.to_sym, nil] } }
      end
    end
    server = build_server("", agent_manager: flaky)
    ancestry_registry.activate!

    2.times do |i|
      ancestry_registry.request("Widget#{i}")
      server.send(:answer_pending_ancestry_questions)
      expect(wait_until { !server.instance_variable_get(:@ancestry_question_worker)&.alive? }).to be(true)
    end

    expect(ancestry_registry).to be_active
  end

  # Re-queueing on failure and re-dispatching after a pass are each right
  # on their own and, paired, are a perpetual motion machine: fail,
  # re-queue, re-dispatch, fail. It only ends if something stops it, and
  # the thing that used to -- an ancestry timeout degrading the Agent --
  # was deliberately removed, because one slow answer about one class is
  # not worth tearing down routes and models. Measured at ~19,000 worker
  # threads a second before this was pinned.
  it "does not retry forever against an Agent that answers nothing" do
    calls = 0
    lock = Mutex.new
    failing = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |_names, **|
        lock.synchronize { calls += 1 }
        nil
      end
    end
    server = build_server("", agent_manager: failing)

    ancestry_registry.activate!
    ancestry_registry.request("Widget")
    server.send(:answer_pending_ancestry_questions)
    sleep 0.5

    # One dispatch, one attempt. The name stays queued for the next real
    # diagnostics run, which is bounded by what the user does.
    expect(lock.synchronize { calls }).to eq(1)
    expect(ancestry_registry.pending?).to be(true)
  end

  # A failed fetch must not leave the name pending-and-unasked forever,
  # nor mark it answered. The names have already left the queue by the
  # time the fetch fails, so they have to be put back -- otherwise one
  # timeout silences those receivers for the rest of the session.
  #
  # Asserts on the registry's own queue rather than re-requesting by hand:
  # a test that calls `request` itself passes under any implementation,
  # including one that recorded the names as absent.
  it "puts the questions back when the Agent cannot answer" do
    failing = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| nil }
    end
    server = build_server(open_and_exit, agent_manager: failing)

    server.run

    expect(wait_until { ancestry_registry.pending? }).to be(true)
    expect(ancestry_registry.drain_pending).to include("ActiveSupport::TestCase")
    expect(ancestry_registry.entry("ActiveSupport::TestCase")).to be_nil
  end

  # The defect an independent review found, and the reason G2 became an
  # order-dependent flake: every caller but the running worker bows out on
  # the single-flight guard, so a question raised while a fetch was in
  # flight had nobody left to carry it. VS Code opens every restored
  # editor at once, so this is the ordinary startup path, not a race.
  it "answers a question raised while an earlier fetch was still running" do
    gate = Queue.new
    asked = Queue.new
    threads = Queue.new
    slow = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        asked << names
        threads << Thread.current
        gate.pop if asked.size == 1 # hold the first fetch open
        { objectAncestors: %w[Object Kernel BasicObject],
          classes: names.to_h { |name| [name.to_sym, nil] } }
      end
    end
    server = build_server("", agent_manager: slow)

    # First question starts a worker and blocks inside its fetch.
    ancestry_registry.activate!
    ancestry_registry.request("First")
    server.send(:answer_pending_ancestry_questions)
    expect(wait_until { asked.size == 1 }).to be(true)

    # Second question arrives while that worker holds the only slot.
    ancestry_registry.request("Second")
    server.send(:answer_pending_ancestry_questions)
    gate << :go

    expect(wait_until { !ancestry_registry.entry("Second").nil? }).to be(true)
    # The same worker carried both, which is what the drain loop is for.
    # Without it the second question is answered too, by a *successor*
    # worker -- so asserting only that it was answered cannot tell the two
    # designs apart.
    expect(asked.size).to eq(2)
    carried_by = []
    carried_by << threads.pop until threads.empty?
    expect(carried_by.uniq.size).to eq(1)
  end

  # Every open buffer's diagnostics come back through here, so without a
  # single-flight guard a batch of questions spawns one fetch per buffer,
  # all against the same Agent. The drain loop makes them harmless, which
  # is exactly why nothing else would notice them.
  it "keeps only one fetch in flight however many documents ask at once" do
    gate = Queue.new
    concurrent = 0
    peak = 0
    lock = Mutex.new
    slow = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        lock.synchronize { concurrent += 1; peak = [peak, concurrent].max }
        gate.pop
        lock.synchronize { concurrent -= 1 }
        { objectAncestors: %w[Object], classes: names.to_h { |n| [n.to_sym, nil] } }
      end
    end
    server = build_server("", agent_manager: slow)

    # The second ask happens only once the first fetch is provably in
    # flight. Asking both up front proves nothing: whichever worker runs
    # first drains the whole queue and the others find it empty, so even
    # an unguarded version would show one fetch.
    ancestry_registry.activate!
    ancestry_registry.request("First")
    server.send(:answer_pending_ancestry_questions)
    expect(wait_until { lock.synchronize { concurrent } == 1 }).to be(true)

    ancestry_registry.request("Second")
    server.send(:answer_pending_ancestry_questions)
    sleep 0.15 # long enough for a second worker to reach the fetch, if one exists

    expect(peak).to eq(1)
    2.times { gate << :go }
    expect(wait_until { !ancestry_registry.entry("Second").nil? }).to be(true)
  end

  # Every test above lives inside one worker's lifetime, so none of them
  # notices whether the slot is ever handed back. If it is not, the first
  # batch is answered and no question is ever fetched again for the rest
  # of the session -- which looks exactly like the feature working.
  it "asks again for a batch raised after the previous worker finished" do
    asked = Queue.new
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        asked << names
        { objectAncestors: %w[Object], classes: names.to_h { |n| [n.to_sym, nil] } }
      end
    end
    server = build_server("", agent_manager: manager)

    ancestry_registry.activate!
    ancestry_registry.request("First")
    server.send(:answer_pending_ancestry_questions)
    expect(wait_until { !ancestry_registry.entry("First").nil? }).to be(true)

    ancestry_registry.request("Second")
    server.send(:answer_pending_ancestry_questions)

    expect(wait_until { !ancestry_registry.entry("Second").nil? }).to be(true)
    expect(asked.size).to eq(2)
  end

  # The window between the worker's last empty drain and it handing the
  # slot back: a question raised in there finds the slot taken, bows out,
  # and has nobody left to carry it. Driven deterministically by asking at
  # exactly that moment rather than hoping to hit it.
  it "carries a question raised between the last drain and the slot being freed" do
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) do |names, **|
        { objectAncestors: %w[Object], classes: names.to_h { |n| [n.to_sym, nil] } }
      end
    end
    server = build_server("", agent_manager: manager)
    late = false
    allow(server).to receive(:release_ancestry_question_slot).and_wrap_original do |original, *args|
      unless late
        late = true
        ancestry_registry.request("Late")
      end
      original.call(*args)
    end

    ancestry_registry.activate!
    ancestry_registry.request("Early")
    server.send(:answer_pending_ancestry_questions)

    expect(wait_until { !ancestry_registry.entry("Late").nil? }).to be(true)
  end

  it "tracks the fetch thread, so it cannot outlive the server" do
    manager = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |names, **| { objectAncestors: [], classes: {} } }
    end
    server = build_server("", agent_manager: manager)
    tasks = server.instance_variable_get(:@background_tasks)
    allow(tasks).to receive(:track_thread).and_call_original

    ancestry_registry.activate!
    ancestry_registry.request("Widget")
    server.send(:answer_pending_ancestry_questions)

    # `at_least(:once)`, because this example is about the *ancestry*
    # thread and the server may legitimately start others while it runs --
    # a workspace-diagnostics pass, most often. The default "exactly once"
    # made this pass on darwin and fail on both CI jobs, which is a red
    # gate that says nothing about the behaviour it names.
    expect(tasks).to have_received(:track_thread).with(an_instance_of(Thread)).at_least(:once)
  end

  # A worker that raises leaves its drained names answered by nothing, and
  # they are gone from the queue -- so without a report the receivers go
  # silent for the session and nothing says why. Every other background
  # Agent path in Server logs its own failures for the same reason.
  it "reports a failure inside the fetch worker rather than dying quietly" do
    errors = []
    allow(logger).to receive(:error) { |message| errors << message }
    exploding = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| raise "boom" }
    end
    server = build_server("", agent_manager: exploding)

    ancestry_registry.activate!
    ancestry_registry.request("Widget")
    server.send(:answer_pending_ancestry_questions)

    expect(wait_until { errors.any? { |e| e.include?("ancestors") } }).to be(true)
  end

  # An answer about a process that has since been replaced must not be
  # installed: answered names are never re-asked, so it would be permanent.
  it "discards an in-flight answer when the Agent is restarted underneath it" do
    gate = Queue.new
    started = Queue.new
    slow = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:stop) { nil }
      define_singleton_method(:fetch_ancestors) do |names, **|
        started << :fetching
        gate.pop
        { objectAncestors: %w[Object], classes: names.to_h { |n| [n.to_sym, { ancestors: [n, "Object"] }] } }
      end
    end
    server = build_server("", agent_manager: slow)

    ancestry_registry.activate!
    ancestry_registry.request("Widget")
    server.send(:answer_pending_ancestry_questions)
    expect(wait_until { started.size == 1 }).to be(true)

    server.send(:restart_agent)
    sleep 0.1
    gate << :go

    sleep 0.3
    expect(ancestry_registry.entry("Widget")).to be_nil
  end

  # A degraded Agent that answers nothing must not look identical to a
  # working one that had nothing to say -- the same reason a failed routes
  # or models fetch is logged.
  it "says so when the Agent cannot answer, rather than failing silently" do
    warnings = []
    allow(logger).to receive(:warn) { |message| warnings << message }
    failing = Class.new do
      define_singleton_method(:ready?) { true }
      define_singleton_method(:fetch_ancestors) { |_names, **| nil }
    end
    server = build_server(open_and_exit, agent_manager: failing)

    server.run

    expect(wait_until { warnings.any? { |w| w.include?("ancestors") } }).to be(true)
    expect(warnings.find { |w| w.include?("ancestors") }).to include("ActiveSupport::TestCase")
  end
end
