# frozen_string_literal: true

require "timeout"
require_relative "../plugins"
require_relative "../child_process"
require_relative "manifest"
require_relative "static_context"
require_relative "runtime_context"

module Ovallsp
  module Plugins
    # Discovers and loads plugins from explicit manifest paths only --
    # never by scanning installed Gems ("自動検出したGemだけを理由に
    # コード実行しない" -- docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md).
    # Every failure mode (invalid manifest, version mismatch, missing
    # entrypoint, an exception or timeout from the plugin's own code)
    # degrades to "this one plugin contributes nothing", logged, never
    # raised -- one broken plugin must never take Core down, and must
    # never prevent every *other* plugin (or Core itself) from working.
    # That list is illustrative, not exhaustive, and #guarded is what makes
    # the contract structural rather than a promise kept by remembering to
    # rescue each case individually (round 13; see #guarded's own docs).
    #
    # A plugin's entrypoint runs in a genuinely separate OS process
    # (Process.fork), not merely a Timeout-wrapped Kernel.load in this
    # process -- a follow-up review of this task found that an earlier
    # version ran `Kernel.load` directly here, meaning a plugin file's
    # own top-level code (reopening `Ovallsp::WorkspaceIndex` to monkey-
    # patch a method, defining a stray top-level constant, anything at
    # all -- independent of what it does with the StaticContext object
    # it's handed) permanently corrupted this Core process for the rest
    # of its lifetime, surviving even after the "isolated" call
    # returned. Only plain data crosses back across the fork boundary
    # (declarations for a static plugin; snapshot-section/reload-hook
    # *names*, not the Procs themselves, for a runtime one, since Ruby
    # Procs can't be Marshaled across a process boundary) -- whatever
    # damage a plugin's own code does happens in a short-lived child
    # process that's discarded (successfully or not) the moment this
    # method returns, POSIX `Process.fork` semantics.
    class Loader
      DEFAULT_TIMEOUT_SECONDS = 5
      MAX_CONSECUTIVE_FAILURES = 3

      def initialize(logger:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        @logger = logger
        @timeout_seconds = timeout_seconds
        @failure_counts = Hash.new(0)
        @disabled = {}
      end

      # Returns one Plugins::StaticContext per manifest that validated,
      # version-matched, and ran without error/timeout -- a manifest that
      # failed any of those simply contributes no entry to the returned
      # array.
      def load_static(manifest_paths)
        Array(manifest_paths).filter_map { |path| guarded(path) { load_static_one(path) } }
      end

      # "untrusted workspaceでruntime pluginを実行しない" -- checked here,
      # before a single byte of any runtime entrypoint is read, let alone
      # loaded: an untrusted workspace gets `trusted: false` and this
      # returns [] unconditionally, the same fail-closed posture
      # RailsBootstrap's own Agent gating already uses
      # (docs/02-architecture.md section 11).
      def load_runtime(manifest_paths, trusted:)
        return [] unless trusted

        Array(manifest_paths).filter_map { |path| guarded(path) { load_runtime_one(path) } }
      end

      private

      # The "never raises" half of this class' own contract ("Every failure
      # mode ... degrades to 'this one plugin contributes nothing', logged,
      # never raised -- one broken plugin must never take Core down"), made
      # structural rather than aspirational (found by an independent
      # review, round 13). It is byte-for-byte the gap round 6 found and
      # fixed in Observation::Runner#run, never applied to the sibling
      # boundary that promises the same thing more emphatically.
      #
      # Individually-rescued failures were only ever the ones somebody
      # thought of: an invalid manifest (InvalidManifest), a plugin's own
      # code raising (rescued inside the fork), Process.fork itself failing.
      # Everything else on the path ran outside any rescue at all, and the
      # reachable ones are ordinary environmental faults, not exotica:
      #
      # * `Manifest.load`'s `File.read` rescues Errno::ENOENT/EISDIR but
      #   not Errno::EACCES -- a manifest the LSP process may not read (a
      #   root-owned plugin dir, a mode-600 file from another user) raises
      #   straight out of #safe_load_manifest.
      # * `::IO.pipe` in #run_isolated is the very first thing that runs
      #   and is unrescued: Errno::EMFILE/ENFILE under fd pressure, which a
      #   long-lived LSP process holding the transport, Agent pipes and
      #   index files can genuinely reach.
      # * `reader.read`/`reader.close` can raise IOError/Errno::EIO.
      #
      # Every one of those escaped #load_static, which Server#dispatch
      # calls synchronously from its `initialize` handler -- so a single
      # unreadable manifest answered the editor's session-opening request
      # with a bare LSP `internal error`, taking down not just that plugin
      # but Core's whole startup. Rescued as a class, not by adding one
      # more Errno to one more rescue list, per this repo's "fix the class
      # of bug, not the reported instance" discipline.
      #
      # `StandardError`, not `Exception`, for exactly the reasons
      # Observation::Runner#run documents at length: Interrupt/
      # SignalException, SystemExit and NoMemoryError/SystemStackError must
      # keep propagating.
      #
      # Logged by path rather than by plugin name, and deliberately NOT
      # run through #apply_isolation_result's failure counter: this fires
      # for failures that can happen *before* a name is known at all (the
      # manifest read itself), and the ones it does catch are environmental
      # rather than the plugin misbehaving -- disabling a perfectly good
      # plugin because the process was briefly out of file descriptors
      # would be the wrong lesson to draw.
      def guarded(path)
        yield
      rescue StandardError => e
        @logger.error("plugin at #{path} could not be loaded: #{e.class}: #{e.message}")
        nil
      end

      def load_static_one(path)
        manifest = safe_load_manifest(path)
        return nil unless manifest && entrypoint_ok?(manifest, manifest.static_entrypoint_path, "static")
        return nil if disabled?(manifest.name)

        declarations = run_isolated(manifest.name) { static_plugin_declarations(manifest) }
        return nil unless declarations

        StaticContext.new(manifest.name).tap { |context| context.restore_declarations(declarations) }
      end

      # Runs *inside the forked child* -- everything this touches
      # (loading the entrypoint file, invoking the plugin's registered
      # block) is thrown away with the child process; only the plain-
      # data `declarations` array returned here is Marshaled back to
      # the parent.
      def static_plugin_declarations(manifest)
        context = StaticContext.new(manifest.name)
        Kernel.load(manifest.static_entrypoint_path)
        Plugins.static_registration(manifest.name)&.call(context)
        context.declarations
      end

      def load_runtime_one(path)
        manifest = safe_load_manifest(path)
        return nil unless manifest && entrypoint_ok?(manifest, manifest.runtime_entrypoint_path, "runtime")
        return nil if disabled?(manifest.name)

        summary = run_isolated(manifest.name) { runtime_plugin_summary(manifest) }
        return nil unless summary

        RuntimeContext.new(manifest.name).tap do |context|
          context.restore_summary(summary[:snapshot_section_names], summary[:reload_hook_count])
        end
      end

      # Same "runs inside the forked child" contract as
      # #static_plugin_declarations -- but a Proc can't be Marshaled
      # across the fork boundary at all, so only the registered
      # sections'/hooks' *names* (not the callables themselves) survive
      # back into the parent. See RuntimeContext#restore_summary.
      def runtime_plugin_summary(manifest)
        context = RuntimeContext.new(manifest.name)
        Kernel.load(manifest.runtime_entrypoint_path)
        Plugins.runtime_registration(manifest.name)&.call(context)
        { snapshot_section_names: context.snapshot_sections.keys, reload_hook_count: context.reload_hooks.size }
      end

      def safe_load_manifest(path)
        manifest = Manifest.load(path)
        return manifest if manifest.compatible_protocol_version?

        @logger.error(
          "plugin #{manifest.name}: protocol_version #{manifest.protocol_version} is incompatible with this " \
          "Core build's #{CURRENT_PROTOCOL_VERSION} -- not loaded"
        )
        nil
      rescue InvalidManifest => e
        @logger.error("plugin manifest invalid at #{path}: #{e.message}")
        nil
      end

      def entrypoint_ok?(manifest, entrypoint_path, kind)
        return false unless entrypoint_path
        return true if File.file?(entrypoint_path)

        @logger.error("plugin #{manifest.name}: #{kind}_entrypoint not found at #{entrypoint_path}")
        false
      end

      def disabled?(name)
        @disabled.key?(name)
      end

      # Forks a child process to run `block`, Marshals whatever it
      # returns back to the parent through a pipe, and returns that
      # value here -- or nil (logged, failure-counted, eventually
      # disabling the plugin after MAX_CONSECUTIVE_FAILURES) for any of:
      # the child raising, the child exceeding @timeout_seconds (killed
      # with SIGKILL), or the child's result failing to Marshal/unMarshal
      # at all.
      #
      # Deliberately does NOT use Observation::Runner's `pgroup: true` +
      # whole-group kill, and that is a judged tradeoff rather than an
      # oversight (re-examined by independent reviews, rounds 6-7 and
      # again in round 11). A plugin that forks its own grandchild would
      # leak it here the way Runner's timeout path used to: the grandchild
      # inherits the result fd, so the parent never sees EOF, #kill_child
      # signals only the plugin child, and the grandchild survives. The
      # difference is what the two subprocesses *are*. Runner spawns the
      # workspace's arbitrary, user-configured test command, where being a
      # forking wrapper (`bin/rails test`, `make test`, `docker compose
      # run ...`) is the *normal* shape rather than the exotic one -- so
      # there the leak was the common case. A plugin entrypoint is
      # explicitly-configured local code whose job is to return
      # declarations, forking is not part of its contract at all, and a
      # process it forked on purpose is arguably its own to reap (the same
      # line Runner draws for a test command that exits normally having
      # backgrounded something). The cost of declining the group kill is
      # therefore bounded to a stray process, never a blocked Core.
      #
      # An earlier version of this note went further and claimed nothing
      # in this file could hang at all, on the grounds that "the read is
      # bounded by Timeout.timeout and every wait after it runs only once
      # the child has already closed the result fd and is about to
      # `exit!`". It was false of #kill_child's wait, which round 12 found
      # is reached only when the read did *not* see EOF -- and false of
      # the success-path wait too, which round 13 found rests on trusting
      # the plugin not to close the result fd early. Neither wait is
      # unbounded any more; see #kill_child and #reap_finished_child.
      def run_isolated(name)
        settled = false
        reader, writer = ::IO.pipe
        pid =
          begin
            fork_plugin_child(writer) { yield }
          rescue StandardError, NotImplementedError => e
            # Process.fork itself failing (no fork(2) on this platform/
            # runtime, ENOMEM, ...) is an environmental failure, not
            # anything the plugin's own code did -- still must degrade
            # to "this plugin contributes nothing" rather than raising
            # out of #load_static/#load_runtime, the same "one broken
            # plugin must never take Core down" invariant every other
            # failure mode here already honors.
            return apply_isolation_result(name, { ok: false, error: "#{e.class}: #{e.message}" })
          end
        writer.close

        payload = read_isolated_result(reader, pid)
        # #read_isolated_result owns the child from here: both of its exits
        # (timeout -> #kill_child, EOF -> #reap_finished_child) have already
        # signalled and reaped it. Anything that stops it from returning
        # normally leaves the child to the `ensure` below instead.
        settled = true

        apply_isolation_result(name, payload)
      ensure
        # Round 10 taught this same lesson in Observation::Runner
        # (`ensure { kill(pid) if pid && !settled }`) and it was never
        # applied to the sibling boundary here, which forks a child of its
        # own on the identical LSP transport thread. Found by an
        # independent review, round 14.
        #
        # Every cleanup this method owes -- both pipe ends, and the plugin
        # child itself -- used to sit on the straight-line success path, so
        # anything raising between the fork and the end of the method
        # skipped all of it. That was already a leak before round 13; round
        # 13's #guarded then made it *silent*, converting "raises out of
        # #load_static, having leaked a child" into "logs one line, returns
        # [], having leaked a child". The escapes are not hypothetical:
        # #guarded's own docs name `reader.read`/`reader.close` raising
        # IOError/Errno::EIO as reachable, `Timeout.timeout` allocates a
        # thread and so can raise ThreadError under thread exhaustion, and
        # an Interrupt (Ctrl-C on the transport thread, exactly round 10's
        # scenario) passes straight through #guarded's StandardError rescue.
        # In every one of those the forked child -- which is running
        # arbitrary plugin code, quite possibly a `sleep` or a loop -- was
        # left running *and* unreaped for the rest of the LSP session, with
        # nothing anywhere still tracking its pid, plus a leaked read fd per
        # occurrence in a long-lived process that can already reach EMFILE.
        #
        # #kill_child is the right primitive rather than a bare reap: on
        # this path we do not know the child is dying (that is precisely
        # what we failed to establish), so it must be signalled first, and
        # ChildProcess.reap then bounds the wait.
        #
        # (Traced line by line in round 15 and left as-is, for the reason
        # Observation::Runner#spawn_and_collect records about its own
        # identical guard: an asynchronous Interrupt landing after
        # #reap_finished_child has already reaped the child but before
        # `settled = true` would make this signal an already-reaped pid.
        # The window here is a little wider than Runner's -- it spans the
        # empty check and `Marshal.load` -- but it still contains no
        # blocking call, and reaching a live victim would additionally
        # require the kernel to have recycled that exact pid inside it,
        # which is tens of thousands of intervening spawns since pids are
        # handed out monotonically. Closing it needs Thread.handle_interrupt
        # around the read, which makes Ctrl-C itself less responsive: the
        # same strictly-worse trade Runner declined in round 11.)
        #
        # Closes go through ChildProcess.close_quietly because an IOError
        # raised out of an `ensure` would *replace* the exception currently
        # propagating -- the same reason ChildProcess.signal is total, and
        # the reason an Interrupt must survive this block intact. (It was a
        # private helper here until round 15 found AgentProcessManager
        # needed the identical primitive; it lives in ChildProcess now, with
        # #signal and #reap, rather than being re-derived a second time.)
        ChildProcess.close_quietly(reader)
        ChildProcess.close_quietly(writer)
        kill_child(pid) if pid && !settled
      end

      def fork_plugin_child(writer)
        Process.fork do
          result_fd = isolate_child_io(writer)
          result = begin
            { ok: true, result: yield }
          rescue Exception => e # rubocop:disable Lint/RescueException -- a plugin's own code, isolated in this child, may raise anything at all; none of it may ever propagate past this process boundary
            { ok: false, error: "#{e.class}: #{e.message}" }
          end
          deliver_result(result_fd, result)
        ensure
          Kernel.exit!(0)
        end
      end

      # Reconnects a plain fd number (see #isolate_child_io -- no live
      # Ruby IO object references it before this point, precisely so the
      # plugin's own code, which already ran by the time this is called,
      # never had one to find) to a writable IO just long enough to
      # deliver the Marshaled result, then closes it.
      def deliver_result(result_fd, result)
        return unless result_fd

        io = ::IO.new(result_fd, "w")
        begin
          io.write(Marshal.dump(result))
        rescue StandardError => e
          # The result itself couldn't be Marshaled (e.g. a plugin
          # somehow returned an object holding a Proc/IO/etc.) --
          # report that specific failure instead of leaving the parent
          # to time out waiting for output that will never arrive.
          io.write(Marshal.dump({ ok: false, error: "result could not be serialized: #{e.class}: #{e.message}" }))
        end
      ensure
        io&.close
      end

      # `Process.fork` duplicates the parent's *entire* fd table, not
      # just fd 1/2 -- reopening only STDOUT/STDERR (an earlier version
      # of this fix) closed the specific leak that had been reported
      # (in `--stdio` mode fd 1 *is* the live LSP JSON-RPC transport,
      # bin/ovallsp: `Server.new(..., output: $stdout)`) but left every
      # *other* IO object the parent happens to hold open -- e.g.
      # AgentProcessManager's own `@stdin_write`/`@stdout_read`/
      # `@stderr_read` pipes to a live Rails Runtime Agent
      # (agent_process_manager.rb `#spawn_process`) -- reachable from a
      # plugin with zero `require`s via `ObjectSpace.each_object(::IO)`.
      #
      # A later pass of the same review found that keeping `writer`
      # itself open and Ruby-visible for the plugin's *entire* execution
      # window (an earlier version of this method) was itself exploitable:
      # a plugin could find `writer` the exact same way via ObjectSpace
      # and write its own forged `Marshal.dump({ok: true, result: ...})`
      # payload to it *before* #deliver_result's own write runs --
      # `Marshal.load` only consumes the first valid object off a
      # stream, so whichever payload arrived first silently won, letting
      # a plugin fabricate arbitrary, unvalidated "results" the loader
      # would trust completely (reproduced live: a forged payload of
      # bogus declarations reached WorkspaceIndex and crashed the whole
      # Server process, defeating the entire "one broken plugin must
      # never take Core down" invariant this class exists for).
      #
      # Fixed by never letting plugin code run while any live Ruby IO
      # object references the result channel at all: the write end is
      # duplicated to a fresh fd, both the original `writer` and the
      # dup'd wrapper are closed at the Ruby level (`autoclose = false`
      # on the dup means closing the *wrapper* does not close the
      # underlying fd), and only the bare fd *number* -- invisible to
      # `ObjectSpace.each_object(::IO)`, which enumerates live objects,
      # not raw descriptors -- survives in a local variable across
      # `yield`. #deliver_result reconstructs a real IO from that number
      # only after the plugin's own code has already finished running.
      # (A plugin could still, in principle, brute-force-guess the fd
      # number and call `IO.for_fd` itself -- there is no way to hide a
      # POSIX fd from code running in the same process against a
      # deliberate scan of the whole fd space -- but that is a
      # fundamentally different, far higher bar than "ask ObjectSpace,
      # get a list handed to you", and genuinely eliminating it would
      # require OS-level sandboxing (seccomp/namespaces) this project
      # doesn't otherwise use anywhere.)
      #
      # Returns the raw result fd number (or nil if isolation itself
      # failed, in which case #deliver_result is a no-op and the parent
      # simply times out / sees EOF like any other unresponsive plugin).
      # Only ever runs inside the forked child -- must never touch the
      # parent's real IO objects.
      def isolate_child_io(writer)
        devnull_r = File.open(File::NULL, "r")
        devnull_w = File.open(File::NULL, "w")
        STDIN.reopen(devnull_r)
        STDOUT.reopen(devnull_w)
        STDERR.reopen(devnull_w)
        $stdin.reopen(devnull_r) unless $stdin.equal?(STDIN)
        $stdout.reopen(devnull_w) unless $stdout.equal?(STDOUT)
        $stderr.reopen(devnull_w) unless $stderr.equal?(STDERR)

        dup_writer = writer.dup
        dup_writer.autoclose = false
        result_fd = dup_writer.fileno
        writer.close
        dup_writer.close

        keep = [STDIN, STDOUT, STDERR, devnull_r, devnull_w]
        ObjectSpace.each_object(::IO) do |io|
          next if keep.any? { |kept| kept.equal?(io) }

          begin
            io.close unless io.closed?
          rescue StandardError
            nil
          end
        end

        result_fd
      rescue StandardError
        nil
      end

      def read_isolated_result(reader, pid)
        raw = nil
        begin
          Timeout.timeout(@timeout_seconds) { raw = reader.read }
        rescue Timeout::Error
          kill_child(pid)
          return { ok: false, error: "Timeout::Error: exceeded #{@timeout_seconds}s" }
        end
        reap_finished_child(pid)

        return { ok: false, error: "plugin process produced no output" } if raw.nil? || raw.empty?

        begin
          Marshal.load(raw)
        rescue StandardError => e
          { ok: false, error: "failed to read plugin process output: #{e.class}: #{e.message}" }
        end
      end

      # The EOF path's own wait, bounded for the same reason #kill_child's
      # is (found by an independent review, round 13 -- round 12 migrated
      # the timeout path in this file and left this one, on the strength of
      # an argument that turns out to trust plugin code).
      #
      # That argument was: reaching here requires EOF on the result pipe,
      # EOF requires every holder of the write fd to have closed it, the
      # child is the last such holder, and the child closes it only inside
      # #deliver_result -- whose caller's very next act is `Kernel.exit!`.
      # So the child is always already dying, and an unbounded
      # `Process.waitpid(pid)` always returns immediately.
      #
      # Every step of that holds except the premise that the child closes
      # the fd only where this class intends it to. #isolate_child_io's own
      # docs already concede the residual hole it cannot close ("A plugin
      # could still, in principle, brute-force-guess the fd number and call
      # `IO.for_fd` itself"), and considered only what a plugin might
      # *write* through such an fd. Closing it is strictly easier, needs no
      # valid payload, and produces an ordinary-looking EOF while the child
      # is still running whatever it likes. @timeout_seconds cannot bound
      # that: it bounds the read, and the read has already returned. The
      # result was a genuinely unbounded block in #load_static, which
      # Server#dispatch calls synchronously from its `initialize` handler
      # on the LSP transport thread -- the editor's entire session, hung by
      # a plugin, which is the one outcome this class exists to prevent.
      # (Reproduced before the fix; see the matching spec.)
      #
      # A child that has closed the result channel and still hasn't exited
      # within the reap budget is misbehaving by definition, so it is
      # SIGKILLed rather than merely detached -- ChildProcess.reap's
      # detach already guarantees it can't linger as a zombie, but nothing
      # else would ever have asked it to stop running.
      #
      # This also retired #read_isolated_result's trailing `rescue
      # Errno::ECHILD` ("plugin process exited unexpectedly"). The bare
      # `Process.waitpid` was its only possible source, so with that gone
      # the branch was unreachable and its message a falsehood -- and it
      # additionally used to discard a perfectly good `raw` payload
      # whenever it did fire. ChildProcess.reap treats "somebody else
      # already reaped it" as success, so that payload is now parsed
      # instead. #guarded is the structural backstop this method never had.
      #
      # The escalation deliberately signals *after* the reap rather than
      # before it (the opposite order from #kill_child), and that satisfies
      # ChildProcess.signal_group's "the pid must still be unreaped"
      # precondition rather than violating it: reaching the signal at all
      # means ChildProcess.reap polled WNOHANG for its whole budget without
      # the child ever exiting, so the child is still live and unreaped and
      # its pid cannot have been recycled. (Process.detach's waiter thread
      # could reap it in the microseconds between the last poll and the
      # signal; that is the same asynchronous pid-recycle window round 11
      # examined and accepted, and inverting the order would be strictly
      # worse -- it would SIGKILL every well-behaved plugin child on the
      # ordinary success path, when it genuinely *has* already been reaped.
      # Traced and left as-is in round 15.)
      def reap_finished_child(pid)
        return if ChildProcess.reap(pid)

        @logger.error("plugin process #{pid} closed its result channel without exiting -- killing it")
        ChildProcess.signal(pid)
      end

      # Total and bounded, via the shared ChildProcess contract (found by
      # an independent review, round 12 -- this was byte-for-byte the pair
      # of mistakes round 11 had just fixed in Observation::Runner, still
      # live here, and #run_isolated's own note above asserted the hang
      # could not happen in this file).
      #
      # Two distinct bugs, both on the *timeout* path, i.e. exactly when
      # the plugin has already proved it is misbehaving:
      #
      # 1. `Process.kill("KILL", pid)` rescued only ESRCH/ECHILD, so any
      #    other signal failure propagated out of #kill_child, out of
      #    #read_isolated_result (which rescues only Errno::ECHILD), out
      #    of #run_isolated and #load_static entirely -- breaking the
      #    "one broken plugin must never take Core down" invariant this
      #    class exists for, from the one code path most likely to run
      #    against a plugin process in a strange state.
      # 2. `Process.waitpid(pid)` was unbounded. Unlike the waitpid on the
      #    success path in #read_isolated_result, this one runs precisely
      #    when the child has *not* closed the result fd and is *not*
      #    about to `exit!` -- the read timed out, that is why we are here
      #    -- so "the child is already dying" does not hold. A plugin
      #    wedged in an uninterruptible kernel wait (a `File.read` on a
      #    hung NFS/FUSE mount is enough, and reading files is the entire
      #    job of a static plugin) cannot be preempted by SIGKILL, and a
      #    plugin whose signal failed per (1) was never even asked to die.
      #    Either way Core blocks here forever -- and #load_static is
      #    called synchronously from Server#dispatch's `initialize`
      #    handler on the LSP transport thread, so a single bad plugin
      #    wedges the editor's entire session at startup, having already
      #    been given up on. The @timeout_seconds bound became decorative
      #    at exactly the moment it fired.
      def kill_child(pid)
        ChildProcess.signal(pid)
        ChildProcess.reap(pid, logger: @logger)
      end

      def apply_isolation_result(name, payload)
        if payload[:ok]
          @failure_counts[name] = 0
          payload[:result]
        else
          @failure_counts[name] += 1
          @logger.error("plugin #{name} failed (#{@failure_counts[name]}/#{MAX_CONSECUTIVE_FAILURES}): #{payload[:error]}")
          @disabled[name] = true if @failure_counts[name] >= MAX_CONSECUTIVE_FAILURES
          nil
        end
      end
    end
  end
end
