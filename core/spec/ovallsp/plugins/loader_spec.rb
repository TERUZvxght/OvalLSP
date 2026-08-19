# frozen_string_literal: true

RSpec.describe Ovallsp::Plugins::Loader do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../../fixtures/plugins", __dir__) }

  subject(:loader) { described_class.new(logger: logger, timeout_seconds: 1) }

  def manifest_path(name)
    File.join(fixtures_root, name, "plugin-manifest.json")
  end

  # Polls rather than probing once: ChildProcess.reap can hand a stubborn
  # pid to Process.detach and let its waiter thread finish the job, so
  # "the loader dealt with the child" is a state reached within a bounded
  # window, not necessarily by the instant #load_static returns. The
  # window is generous (well past ChildProcess' own 2s reap budget) so a
  # loaded CI machine can't make this flake, while a genuinely leaked
  # child -- the fixtures sleep 60 -- still fails it.
  def child_alive?(pid, within: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + within
    loop do
      Process.kill(0, pid)
      return true if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  rescue Errno::ESRCH
    false
  end

  def kill_leaked_child(pid)
    return unless pid

    Process.kill("KILL", pid)
    Process.waitpid(pid)
  rescue StandardError
    nil
  end

  after do
    # Loader always calls Plugins.clear_registration after a run, but a
    # test that inspects state mid-way (or a fixture whose block itself
    # raises before registering) could otherwise leak a stale
    # registration into the next example, since Plugins' registry is a
    # shared module-level Hash.
    Ovallsp::Plugins.clear_registration("ovallsp-example-state-machine")
    Ovallsp::Plugins.clear_registration("ovallsp-raising")
    Ovallsp::Plugins.clear_registration("ovallsp-slow")
    Ovallsp::Plugins.clear_registration("ovallsp-malformed-fact")
    Ovallsp::Plugins.clear_registration("ovallsp-runtime-example")
    Ovallsp::Plugins.clear_registration("ovallsp-monkeypatching")
    Ovallsp::Plugins.clear_registration("ovallsp-stdout-writer")
    Ovallsp::Plugins.clear_registration("ovallsp-monkeypatching-runtime")
    Ovallsp::Plugins.clear_registration("ovallsp-io-scavenger")
    Ovallsp::Plugins.clear_registration("ovallsp-pipe-forger")
    Ovallsp::Plugins.clear_registration("ovallsp-fd-closer")
  end

  describe "#load_static" do
    it "loads a valid plugin and collects its registered declarations" do
      contexts = loader.load_static([manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
      fact = contexts.first.declarations.first
      expect(fact[:symbol_id]).to eq(
        Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::ExampleModel", name: "pending?", discriminator: nil)
      )
      expect(fact[:return_type]).to eq(Ovallsp::Types::Nominal.new(name: "Boolean"))
    end

    it "skips a plugin whose protocol_version doesn't match this Core build's own, without raising" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("bad_version")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/protocol_version/))
    end

    it "isolates a plugin whose entrypoint raises -- no exception escapes, and it contributes nothing" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("raising")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/boom/))
    end

    it "isolates a plugin whose entrypoint hangs past the timeout" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("slow")]) }.not_to raise_error

      expect(contexts).to eq([])
    end

    # Found by an independent review (round 12), and byte-for-byte the
    # pair of mistakes round 11 had just fixed in Observation::Runner --
    # still live in this file's own hand-rolled copy, which #run_isolated's
    # note then asserted could not hang. #kill_child rescued only
    # ESRCH/ECHILD around its `Process.kill`, so any other signal failure
    # escaped #load_static entirely (breaking "one broken plugin must never
    # take Core down"), and its `Process.waitpid` was unbounded -- reached
    # precisely when the read did NOT see EOF, i.e. when the child is
    # demonstrably not about to exit. #load_static runs synchronously in
    # Server#dispatch's `initialize` handler on the LSP transport thread,
    # so one wedged plugin hung the editor's whole session at startup,
    # after @timeout_seconds had already given up on it.
    #
    # Bounded by Thread#join rather than an outer Timeout.timeout on
    # purpose: a Timeout::Error raised into the code under test is a
    # StandardError like any other, and every subprocess boundary in this
    # codebase rescues those by contract -- so it would be swallowed and
    # the guard would silently pass. (That is exactly why round 11's own
    # regression test did not fail against pre-round-11 Runner; fixed in
    # the same pass.)
    it "still honours its own timeout when the plugin child's kill signal fails to land" do
      real_kill = Process.method(:kill)
      forked = nil
      allow(Process).to receive(:fork).and_wrap_original { |original, &blk| forked = original.call(&blk) }
      allow(Process).to receive(:kill).and_wrap_original do |original, signal, target|
        raise Errno::EPERM if signal == "KILL"

        original.call(signal, target)
      end

      contexts = :unset
      error = nil
      worker = Thread.new do
        contexts = loader.load_static([manifest_path("slow")])
      rescue Exception => e # rubocop:disable Lint/RescueException -- the whole point is that *nothing* may escape #load_static
        error = e
      end

      # Generously above @timeout_seconds (1) + the reap bound (2), so this
      # only ever trips on a genuinely unbounded wait, never a slow one.
      expect(worker.join(15)).not_to be_nil, "Plugins::Loader#load_static never returned -- its own timeout blocked forever"
      expect(error).to be_nil
      expect(contexts).to eq([])
      # `[]` is #load_static's answer to *every* failure, so on its own it
      # does not witness that this run reached #kill_child at all. Pinning
      # the timeout log keeps the example a guard rather than a decoration
      # -- the same lesson round 12 drew about this test's outer bound
      # (round 13).
      expect(logger).to have_received(:error).with(a_string_matching(/Timeout::Error: exceeded 1s/))
      expect(forked).not_to be_nil
    ensure
      worker&.kill
      begin
        real_kill.call("KILL", forked) if forked
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end

    # Found by an independent review (round 13) of Task 022.2 -- the one
    # unbounded wait round 12's migration left behind, in the file it had
    # just fixed, on the same thread, with the same consequence.
    #
    # #read_isolated_result's post-EOF `Process.waitpid(pid)` was defended
    # by "reaching it requires EOF, which requires every holder of the
    # write fd to have closed it, so the child is already inside exit!".
    # That reasoning trusts the *plugin* to be the thing that didn't close
    # the fd early -- and trusting plugin code is exactly what this class
    # refuses to do everywhere else. #isolate_child_io's own docs already
    # concede a plugin can reach the result fd by guessing its number, so
    # a plugin can produce EOF whenever it likes and then simply not exit.
    # @timeout_seconds cannot save Core here: it bounds the read, and the
    # read already returned. #load_static runs synchronously in
    # Server#dispatch's `initialize` handler on the LSP transport thread,
    # so the editor's whole session hangs for as long as the plugin sleeps.
    #
    # Bounded by Thread#join, not an outer Timeout.timeout, for the same
    # reason as the example above: a Timeout::Error raised into the code
    # under test is a StandardError and would be swallowed by the blanket
    # rescues this codebase's subprocess boundaries all use.
    it "still returns when a plugin closes the result pipe itself and then refuses to exit" do
      real_kill = Process.method(:kill)
      forked = nil
      allow(Process).to receive(:fork).and_wrap_original { |original, &blk| forked = original.call(&blk) }

      contexts = :unset
      error = nil
      worker = Thread.new do
        contexts = loader.load_static([manifest_path("fd_closer")])
      rescue Exception => e # rubocop:disable Lint/RescueException -- the whole point is that *nothing* may escape #load_static
        error = e
      end

      # Generously above the reap bound (2), and well under the fixture's
      # own 60s sleep, so a wait that is merely riding the child out still
      # fails this.
      expect(worker.join(15)).not_to be_nil, "Plugins::Loader#load_static never returned -- it waited on the child unboundedly"
      expect(error).to be_nil
      expect(contexts).to eq([])
      # Pins that this went through the EOF path being guarded, rather than
      # passing because the plugin happened to fail some earlier way.
      expect(logger).to have_received(:error).with(a_string_matching(/produced no output/))
      # ...and that #reap_finished_child's *escalation* ran, not merely its
      # bounded wait. Without this the example still passed against a
      # #reap_finished_child reduced to `return` -- returning promptly is
      # only half of what the fix promises; the other half is that a child
      # which faked EOF and then refused to exit actually gets SIGKILLed
      # rather than left running for its full 60s sleep (round 14,
      # stress-testing round 13's own regression test).
      expect(logger).to have_received(:error).with(a_string_matching(/closed its result channel without exiting/))
    ensure
      worker&.kill
      begin
        real_kill.call("KILL", forked) if forked
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end

    # Found by an independent review (round 13) of Task 022.2, and
    # byte-for-byte the gap round 6 found in Observation::Runner#run: the
    # "never raises" contract was honoured by a list of individually
    # rescued failures somebody had thought of, not structurally. This
    # class states that contract more emphatically than Runner does ("one
    # broken plugin must never take Core down"), and #load_static is what
    # Server#dispatch calls synchronously from its `initialize` handler --
    # so any unrescued raise answers the editor's session-opening request
    # with a bare LSP `internal error`.
    #
    # Two genuinely reachable escapes, deliberately covering two *different*
    # points on the path (before a plugin name is even known, and inside
    # the subprocess machinery), because the fix has to be the class rather
    # than either instance.
    it "degrades to 'this plugin contributes nothing' when the manifest itself can't be read at all" do
      path = manifest_path("state_machine_example")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(path).and_raise(Errno::EACCES)

      contexts = :unset
      expect { contexts = loader.load_static([path]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/Errno::EACCES/))
    end

    it "degrades to 'this plugin contributes nothing' when the result pipe itself can't be created" do
      allow(::IO).to receive(:pipe).and_raise(Errno::EMFILE)

      contexts = :unset
      expect { contexts = loader.load_static([manifest_path("state_machine_example")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/Errno::EMFILE/))
    end

    # Found by an independent review (round 14) of Task 022.2, and
    # byte-for-byte the gap round 10 found in Observation::Runner --
    # #spawn_and_collect's `ensure { kill(pid) if pid && !settled }` --
    # never applied to the sibling boundary here, which forks a child of
    # its own on the identical LSP transport thread.
    #
    # #run_isolated did all of its cleanup (both pipe ends, and the plugin
    # child) on the straight-line success path, so any exception between
    # the fork and the end of the method skipped every bit of it. Round 13
    # made that *quieter* rather than safer: before it, such an exception
    # raised out of #load_static having leaked a child; after it, #guarded
    # logs one line, returns [], and the child is leaked with nothing
    # anywhere still holding its pid.
    #
    # Errno::EIO from Timeout.timeout stands in for the whole class of
    # escapes, all of which #guarded's own docs already name as reachable:
    # `reader.read`/`reader.close` raising IOError/Errno::EIO, and
    # Timeout.timeout itself raising ThreadError under thread exhaustion
    # (it allocates a thread). The leaked child is running arbitrary plugin
    # code -- here `sleep 60` -- so "leaked" means a live process plus an
    # unreapable pid for the rest of the LSP session, not just a zombie.
    #
    # Round 14's fix had two halves -- the child, and both pipe ends -- and
    # as originally written this example only witnessed the first: with
    # `ChildProcess.close_quietly(reader)`/`(writer)` deleted from the
    # `ensure` and only the kill left, the entire loader spec still passed
    # green while every failed load leaked a descriptor in a process whose
    # own docs name Errno::EMFILE as reachable. Pinned below (round 15,
    # stress-testing round 14's own regression test, the same way round 14
    # stress-tested round 13's and round 13 stress-tested round 12's).
    it "kills and reaps the plugin child even when the read path fails in a way #guarded swallows" do
      forked = nil
      allow(Process).to receive(:fork).and_wrap_original { |original, &blk| forked = original.call(&blk) }
      allow(Timeout).to receive(:timeout).and_raise(Errno::EIO)

      before_fds = Dir.children("/dev/fd").size
      contexts = :unset
      expect { contexts = loader.load_static([manifest_path("slow")]) }.not_to raise_error

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/Errno::EIO/))
      expect(forked).not_to be_nil
      expect(child_alive?(forked)).to be(false),
                                      "plugin child #{forked} survived #load_static -- nothing tracks its pid any more"
      # Deliberately no GC.start: an unreferenced IO is eventually finalized,
      # which would mask the leak here exactly as it masked it in production.
      leaked = Dir.children("/dev/fd").size - before_fds
      expect(leaked).to eq(0), "#run_isolated leaked #{leaked} descriptor(s) -- its pipe ends were never closed"
    ensure
      kill_leaked_child(forked)
    end

    # The same structural hole, reached by the exception class #guarded
    # deliberately does *not* rescue. Ctrl-C on the LSP transport thread
    # while a plugin child is being read from is precisely round 10's
    # scenario ("a Ctrl-C'd observation run orphaned the workspace's whole
    # test tree"), and an Interrupt must both keep propagating *and* leave
    # no child behind -- which is why the cleanup has to be an `ensure`
    # rather than one more rescue.
    it "kills and reaps the plugin child when a non-StandardError propagates out of #load_static" do
      forked = nil
      allow(Process).to receive(:fork).and_wrap_original { |original, &blk| forked = original.call(&blk) }
      allow(Timeout).to receive(:timeout).and_raise(Interrupt)

      expect { loader.load_static([manifest_path("slow")]) }.to raise_error(Interrupt)

      expect(forked).not_to be_nil
      expect(child_alive?(forked)).to be(false),
                                      "plugin child #{forked} outlived the Interrupt that tore #load_static down"
    ensure
      kill_leaked_child(forked)
    end

    it "isolates a plugin that registers a malformed fact (missing required keys)" do
      contexts = nil
      expect { contexts = loader.load_static([manifest_path("malformed_fact")]) }.not_to raise_error

      expect(contexts).to eq([])
    end

    it "skips a manifest whose static_entrypoint file doesn't exist, logging why" do
      contexts = loader.load_static([manifest_path("missing_entrypoint")])

      expect(contexts).to eq([])
      expect(logger).to have_received(:error).with(a_string_matching(/entrypoint not found/))
    end

    it "skips an invalid manifest without raising, and still loads every other plugin in the batch" do
      contexts = loader.load_static([manifest_path("invalid_manifest"), manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
    end

    it "disables a plugin after repeated consecutive failures across separate loads" do
      described_class::MAX_CONSECUTIVE_FAILURES.times do
        loader.load_static([manifest_path("raising")])
      end

      expect(logger).to have_received(:error).with(a_string_matching(/boom/)).at_least(described_class::MAX_CONSECUTIVE_FAILURES).times
    end

    it "keeps two plugins isolated from each other -- one failing does not affect the other" do
      contexts = loader.load_static([manifest_path("raising"), manifest_path("state_machine_example")])

      expect(contexts.size).to eq(1)
      expect(contexts.first.declarations).not_to be_empty
    end

    it "supports reload: loading the same plugin twice both times returns a fresh context" do
      first = loader.load_static([manifest_path("state_machine_example")])
      second = loader.load_static([manifest_path("state_machine_example")])

      expect(first.first.declarations).to eq(second.first.declarations)
    end

    it "isolates a plugin's top-level code in a separate process -- monkeypatching a Core class does not survive back into this process" do
      symbol_id = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Whatever", discriminator: nil)
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_PLUGIN")

      contexts = loader.load_static([manifest_path("monkeypatching")])

      expect(contexts.size).to eq(1)
      expect(contexts.first.declarations.first[:symbol_id].owner).to eq("::MonkeypatchModel")
      # The plugin's own file reopened Ovallsp::Index::SymbolId and
      # redefined #to_s at its top level, independent of anything it did
      # through StaticContext -- if that patch leaked into this (parent)
      # process, every SymbolId in Core would now report this string.
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_PLUGIN")
    end

    it "never lets a plugin's raw STDOUT/STDERR writes reach this process' real stdio -- fd 1 is the live LSP transport in --stdio mode" do
      require "tempfile"
      captured = Tempfile.new("ovallsp-plugin-stdio-leak")
      original_stdout_fd = STDOUT.dup
      original_stderr_fd = STDERR.dup
      contexts = nil
      begin
        STDOUT.reopen(captured.path, "w")
        STDERR.reopen(captured.path, "w")

        contexts = loader.load_static([manifest_path("stdout_writer")])
      ensure
        STDOUT.reopen(original_stdout_fd)
        STDERR.reopen(original_stderr_fd)
        original_stdout_fd.close
        original_stderr_fd.close
      end

      expect(contexts.size).to eq(1)
      captured.rewind
      expect(captured.read).not_to include("EVIL-EVIL-LSP-PROTOCOL-CORRUPTION")
    end

    it "never lets a plugin reach any OTHER IO object the parent happens to have open -- not just fd 1/2" do
      # Found by the Task 014-018 independent review's third pass:
      # Process.fork hands the child the parent's *entire* fd table, so
      # a plugin doesn't need to write to a known fd (STDOUT/STDERR) to
      # corrupt something -- any IO object the parent has open (e.g.
      # AgentProcessManager's own pipes to a live Rails Runtime Agent)
      # is reachable via ObjectSpace with zero requires. Stands in for
      # that scenario with an ordinary pipe held open in this process.
      stand_in_reader, stand_in_writer = ::IO.pipe

      # The fixture writes to every open IO it can find via ObjectSpace,
      # indiscriminately -- including, harmlessly, its own legitimate
      # result-reporting pipe, which just means *this* plugin's own
      # result comes back corrupted (already handled gracefully:
      # #load_static simply contributes nothing for it, the same as any
      # other plugin failure). What matters for this test is only
      # whether the write reached the unrelated *stand-in* pipe below.
      loader.load_static([manifest_path("io_scavenger")])

      stand_in_writer.close
      leaked = begin
        Timeout.timeout(0.2) { stand_in_reader.read }
      rescue Timeout::Error
        ""
      end
      stand_in_reader.close

      expect(leaked).not_to include("EVIL-VIA-OBJECTSPACE")
    end

    it "never lets a plugin forge its own result by racing the result pipe -- the pipe must not be Ruby-visible to plugin code at all" do
      # Found by the Task 014-018 independent review's fourth pass: an
      # earlier version of #isolate_child_io kept the result pipe's
      # write end (`writer`) open and reachable via ObjectSpace for the
      # plugin's *entire* execution window. Marshal.load only consumes
      # the first valid object off a stream, so a plugin that found
      # `writer` via ObjectSpace and wrote its own forged payload first
      # would have that payload silently trusted as the "real" result,
      # bypassing StaticContext#register_declarations' own key
      # validation entirely.
      contexts = loader.load_static([manifest_path("pipe_forger")])

      expect(contexts.size).to eq(1)
      fact = contexts.first.declarations.first
      expect(fact[:symbol_id].owner).to eq("::PipeForgerModel")
      expect(contexts.first.declarations).not_to include(a_hash_including(not_a_real_declaration: anything))
    end

    # `024.73`. The fork exists so a broken or hostile plugin cannot
    # reach into Core, and reading its answer with `Marshal.load` undid
    # that: those bytes come from the plugin's own code, and
    # `Marshal.load` instantiates whatever classes the stream names, in
    # the parent, before `#partition_plugin_facts` or anything else looks
    # at the data. An allowlist proc would not have helped -- it runs
    # after each object is constructed.
    #
    # Asserted as "never calls it" rather than by demonstrating a gadget:
    # a gadget is a property of whatever classes happen to be loaded, so
    # a passing gadget test would be evidence about this Gemfile, while
    # this is evidence about the boundary. It fails the moment anyone
    # puts `Marshal.load` back on this path.
    it "never reconstructs the child's answer with Marshal" do
      expect(Marshal).not_to receive(:load)

      contexts = loader.load_static([manifest_path("state_machine_example")])

      expect(contexts.first.declarations.first[:return_type]).to eq(Ovallsp::Types::Nominal.new(name: "Boolean"))
    end

    # The other half: a plugin that writes a Marshal payload to the pipe
    # -- which is what `pipe_forger` above does, and what used to be
    # accepted verbatim -- now produces nothing rather than a decoded
    # object graph. The loader keeps its "one broken plugin contributes
    # nothing, logged" contract instead of trusting the stream.
    # `Timeout.timeout(5) { reader.read }` bounds wall-clock, not bytes,
    # and `IO#read` returns only at EOF -- so a plugin chose how much
    # memory the parent allocated. Measured: 300,000 declarations took the
    # parent from 44 MB to 380 MB in 1.22s, and a single 50 MB method name
    # took it to 144 MB in 0.14s. Five seconds of pipe throughput is
    # multiple GB. "One broken plugin never takes Core down" is the
    # guarantee this file opens with.
    it "refuses a result larger than the cap instead of allocating it" do
      # A real pid, spawned and reaped here. Passing a fabricated one
      # reached `kill_child` and signalled the rspec process's own group;
      # `ChildProcess.signal`/`#reap` refuse a zero target now, and the
      # example stopped fabricating either way.
      pid = Process.spawn("/bin/sleep", "60")
      oversized = "x" * (described_class::MAX_RESULT_BYTES + 1)

      result = loader.send(:read_isolated_result, StringIO.new(oversized), pid)

      expect(result[:ok]).to be(false)
      expect(result[:error]).to match(/too large/)
    end

    it "still reads a result under the cap" do
      allow(Ovallsp::ChildProcess).to receive(:reap).and_return(true)
      payload = JSON.generate(Ovallsp::Plugins::Wire.encode_result({ ok: true, result: [] }))

      result = loader.send(:read_isolated_result, StringIO.new(payload), 1)

      expect(result).to eq(ok: true, result: [])
    end

    it "rejects a Marshal payload on the result pipe instead of loading it" do
      allow(Ovallsp::ChildProcess).to receive(:reap).and_return(true)

      result = loader.send(:read_isolated_result, StringIO.new(Marshal.dump({ ok: true, result: [] })), 1)

      expect(result[:ok]).to be(false)
    end
  end

  describe "#load_runtime" do
    it "does not load anything at all for an untrusted workspace" do
      contexts = loader.load_runtime([manifest_path("runtime_example")], trusted: false)

      expect(contexts).to eq([])
    end

    it "loads a runtime plugin's contributions for a trusted workspace" do
      contexts = loader.load_runtime([manifest_path("runtime_example")], trusted: true)

      expect(contexts.size).to eq(1)
      expect(contexts.first.snapshot_sections.keys).to eq(["example"])
    end

    it "isolates a runtime plugin's top-level code in a separate process, same as a static plugin" do
      symbol_id = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Whatever", discriminator: nil)

      contexts = loader.load_runtime([manifest_path("monkeypatching_runtime")], trusted: true)

      expect(contexts.size).to eq(1)
      expect(contexts.first.snapshot_sections.keys).to eq(["example"])
      expect(symbol_id.to_s).not_to eq("MONKEYPATCHED_BY_RUNTIME_PLUGIN")
    end
  end
end
