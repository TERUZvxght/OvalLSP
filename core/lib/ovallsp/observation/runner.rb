# frozen_string_literal: true

require "json"
require "tempfile"
require "timeout"
require_relative "observed_signature"
require_relative "wire"
require_relative "../bundle_environment"
require_relative "../child_process"

module Ovallsp
  module Observation
    # Spawns the workspace's own configured test command as a genuinely
    # separate OS process, with Harness injected via `RUBYOPT` -- never
    # runs test/observation code inside Core's own process ("production
    # process injection" is explicitly out of scope;
    # docs/design/tasks/019-runtime-observation.md). A runner crash,
    # hang, or empty/corrupt result never raises out of #run; it's
    # exactly one more "this run produced no evidence" outcome (`nil`),
    # logged, the same fail-closed posture every other subprocess
    # boundary in this codebase (Plugins::Loader, AgentProcessManager)
    # already uses -- and, per #run's own docs, kept distinct from the
    # genuinely-empty `[]` a run that completed and observed nothing
    # returns.
    class Runner
      DEFAULT_TIMEOUT_SECONDS = 300
      HARNESS_PATH = File.expand_path("harness.rb", __dir__)
      # How long the kill path is willing to wait for a SIGKILL'd child to
      # actually die before handing it to Process.detach -- see
      # ChildProcess.reap.
      REAP_TIMEOUT_SECONDS = ChildProcess::DEFAULT_REAP_TIMEOUT_SECONDS

      def initialize(logger:)
        @logger = logger
      end

      # `command`/`args` are the workspace's own configured test command
      # (e.g. `["bundle", "exec", "rspec"]`), run with `workspace_root`
      # as both cwd and the Collector's own workspace-path filter root.
      # Never raises.
      #
      # Returns an Array of ObservedSignature -- possibly empty -- for a
      # run that actually *completed*, and `nil` when no run outcome
      # could be obtained at all: Core couldn't even start the command
      # (a deleted/renamed workspace, a command that isn't on PATH), the
      # command was killed on timeout, it exited non-zero having
      # produced no evidence, or its result file came back corrupt or
      # was never written at all (see #read_results -- an empty file
      # means the harness never ran, however cleanly the command itself
      # exited).
      #
      # `nil` and `[]` are deliberately different values rather than
      # both flattened to `[]` (found by an independent review, round 7).
      # Store#replace_run is a full generation swap, so a caller that
      # treats a failed run as "the suite genuinely observed nothing"
      # silently destroys every previously observed signature the user
      # had accumulated -- a broken test command, or a workspace
      # directory renamed while the editor is open, would wipe the whole
      # evidence store as a side effect of a run that produced no
      # information whatsoever. That is the identical conflation Task
      # 008.6 already had to fix one code path over, in
      # RailsBootstrap#populate_registries' `fetch_all_models || []`
      # (see its own docs), and the distinguishing information was
      # already being computed here -- #spawn_and_collect has always
      # returned nil for failure -- and then discarded one line later by
      # a `results || []`.
      #
      # `env_source:` (default: the real `ENV`) is the environment
      # BundleEnvironment.for_workspace reads Core's own Bundler/RubyGems
      # pollution *from* -- production always leaves it as the default;
      # it exists so a test can simulate "what if Core's own process had X
      # polluted" with a plain Hash, without ever mutating global ENV
      # (mirrors RailsBootstrap.start's own `env_source:`).
      def run(command:, args:, workspace_root:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS, env_source: ENV)
        run_id = "#{Time.now.to_f}-#{Process.pid}-#{rand(1_000_000)}"
        output_file = Tempfile.new(["ovallsp-observation", ".json"])
        log_file = Tempfile.new(["ovallsp-observation", ".log"])
        output_file.close
        log_file.close

        env = harness_env(workspace_root: workspace_root, output_path: output_file.path, run_id: run_id,
                          env_source: env_source)
        spawn_and_collect(command, args, workspace_root, env, output_file.path, log_file.path, timeout_seconds)
      rescue StandardError => e
        # The "never raises" half of this method's own contract, made
        # structural rather than aspirational (found by an independent
        # review, round 6). #spawn_and_collect has always had this rescue,
        # but everything *before* the spawn -- Tempfile creation, and
        # (since round 5 moved env construction through
        # BundleEnvironment.for_workspace) `File.realpath(workspace_root)`
        # plus the workspace Gemfile probe -- ran outside any rescue at
        # all. A workspace directory that has been deleted or renamed
        # while the editor is still open is enough: `File.realpath` raises
        # Errno::ENOENT straight out of #run, so
        # Server#run_observed_tests_result answers the user's explicit
        # `Run Tests with Type Observation` command with a bare LSP
        # `internal error` instead of the "this run produced no evidence"
        # outcome the class docs above promise. Rescued as a class, not
        # by special-casing realpath, per this repo's "fix the class of
        # bug, not the reported instance" discipline -- and matching the
        # identical blanket rescue every other subprocess boundary here
        # (#spawn_and_collect, #read_results, Plugins::Loader) already
        # uses.
        #
        # `StandardError`, not `Exception`, and that is a decision rather
        # than an oversight (reviewed explicitly in round 9). Everything
        # this method can realistically hit is under StandardError:
        # Errno::* (SystemCallError), Timeout::Error (RuntimeError),
        # JSON::ParserError/IOError, ArgumentError. What `Exception` would
        # additionally catch is exactly what must NOT be caught here --
        # Interrupt/SignalException (the user Ctrl-C'ing the editor's
        # server must still terminate it, not be logged as "this run
        # produced no evidence"), SystemExit (an `exit` swallowed here
        # would hang the process), and NoMemoryError/SystemStackError
        # (unrecoverable; continuing to serve LSP requests afterwards is
        # worse than dying). "Never raises" means "never raises for any
        # failure of the observed run", not "converts a fatal
        # interpreter condition into a silent nil".
        @logger.error("observation runner could not start: #{e.class}: #{e.message}")
        nil
      ensure
        # `close!`, not `unlink`: Tempfile#unlink only removes the directory
        # entry and leaves the descriptor open, so the narrow path where the
        # *second* `Tempfile.new` raises (a full or unwritable TMPDIR,
        # Errno::EMFILE) used to strand the first one's fd until GC got to
        # it -- the same "cleanup that only runs when nothing went wrong"
        # shape round 15 found in AgentProcessManager#spawn_process, in the
        # one method here that owns something other than a child process.
        # On every ordinary path both files are already closed by then and
        # `close!` just unlinks, exactly as before.
        #
        # Each discard is *total* (found by an independent review, round
        # 19). Round 15's lesson -- cleanup must not sit on the
        # straight-line success path -- was applied here as an `ensure`,
        # but the `ensure` *body* was itself left a bare two-step straight
        # line, which is the same shape one level in: see #discard_quietly
        # for what that costs. Cache::Store#save's own `ensure` already
        # guards its single step this way; this was the last unguarded one
        # in Core.
        discard_quietly(output_file)
        discard_quietly(log_file)
      end

      private

      # `Tempfile#close!` is not total: `_close` is a real `IO#close`, and
      # `unlink` rescues only Errno::ENOENT and Errno::EACCES, so
      # Errno::EROFS (a TMPDIR remounted read-only, e.g. after the disk
      # filled), EPERM (an immutable or append-only TMPDIR), EIO or EBUSY
      # all escape it. Two distinct costs, both of them ones this repo has
      # already paid at other boundaries:
      #
      # 1. It abandons every step after it in the `ensure`. `output_file`
      #    raising means `log_file` is never closed *nor* unlinked -- one
      #    leaked descriptor and one stranded on-disk file per attempt, in
      #    the method Server runs for every `Run Tests with Type
      #    Observation`, with nothing left that would ever clean either up
      #    deterministically. Identical to round 15's finding in
      #    AgentProcessManager#spawn_process and round 16's in its
      #    teardown.
      # 2. It escapes #run, whose contract is "Never raises" (see its own
      #    docs) -- the contract round 6 was opened to make structural
      #    rather than aspirational, and round 13 had to re-open for a
      #    second method whose "never raises" still wasn't. A raise out of
      #    an `ensure` is the worst version of that: it does not merely
      #    add an exception, it *replaces* the one already propagating --
      #    and #run deliberately lets Interrupt through (round 9: a Ctrl-C
      #    must really kill the editor's server, not be logged as "this
      #    run produced no evidence"), so the one exception this class is
      #    most careful to preserve is exactly the one an Errno here would
      #    silently convert into something else.
      def discard_quietly(tempfile)
        tempfile&.close!
      rescue StandardError
        nil
      end

      # The command spawned here is the *workspace's* own test command --
      # in practice literally `bundle exec rspec` (see #run's own docs) --
      # so it is a second instance of exactly the boundary the Runtime
      # Agent's own spawn already goes through: Core and the analyzed
      # workspace are two entirely separate Bundle graphs, and Core's own
      # BUNDLE_GEMFILE/BUNDLE_PATH/BUNDLER_SETUP/BUNDLER_VERSION,
      # bundle-exec-derived GEM_HOME/GEM_PATH, PATH/MANPATH entries and
      # RUBYLIB/RUBYOPT injections must not leak into it (see
      # BundleEnvironment's own docs).
      #
      # Found by an independent review (round 5) of Task 022.2: rounds 1-4
      # hardened BundleEnvironment itself and wired it into
      # RailsBootstrap.start, but this sibling spawn site still built its
      # env as bare overrides on top of a fully inherited ENV, so the
      # workspace's own `bundle exec rspec` resolved against *Core's*
      # Gemfile/gem install (and, per the round-4 PATH finding, resolved
      # the bare command name `bundle` out of Core's own bundle bin dir).
      # The old RUBYOPT line made it worse rather than merely missing it:
      # it explicitly *propagated* Core's raw `ENV["RUBYOPT"]`, i.e. the
      # `-r<core bundler>/setup` `bundle exec` injects, which runs
      # `Bundler.setup` against Core's Gemfile before the workspace's own
      # test command has a say.
      #
      # RUBYOPT is composed from the *isolated* value (Core's
      # bundler/setup flag already stripped by BundleEnvironment, any other
      # legitimate flag preserved) rather than from `env_source` directly.
      # The harness itself only ever uses `require_relative`, so it needs
      # nothing from Core's bundle to load.
      def harness_env(workspace_root:, output_path:, run_id:, env_source:)
        base = Ovallsp::BundleEnvironment.for_workspace(workspace_root, env: env_source)
        rubyopt = [base["RUBYOPT"], "-r#{HARNESS_PATH}"].compact.reject(&:empty?).join(" ")

        base.merge(
          "OvalLSP_OBSERVATION_WORKSPACE_ROOT" => File.realpath(workspace_root),
          "OvalLSP_OBSERVATION_OUTPUT_PATH" => output_path,
          "OvalLSP_OBSERVATION_RUN_ID" => run_id,
          "RUBYOPT" => rubyopt
        )
      end

      # Never lets the spawned process inherit this process' real
      # stdout/stderr -- in `--stdio` mode fd 1 is the live LSP JSON-RPC
      # transport, the same class of leak already found and fixed for
      # Plugins::Loader (Task 014-018's independent review) -- both
      # streams are captured to `log_path` instead, never forwarded to
      # this process' own fd 1/2. Keeping them off fd 1 is the *only*
      # reason the file exists: nothing opens, reads, indexes or surfaces
      # it, and it is unlinked when the run ends. An earlier revision of
      # this comment said it was "for the caller's own diagnostics (e.g.
      # surfacing the test command's output back to the editor)", which
      # describes a feature that does not exist (0.1.12).
      #
      # `pgroup: true` makes the child the leader of its own process
      # group, so #kill can signal the whole tree rather than just the
      # one pid (found by an independent review, round 9). `command` is
      # the workspace's *arbitrary user-configured* test command, and
      # most real shapes of it are a wrapper that forks: `bin/rails
      # test`, `make test`, `npm test`, `docker compose run ...`, any
      # shell wrapper -- and Ruby's own `Process.spawn(env, single_string)`
      # shell fallback when `args` is empty. Killing only `pid` on
      # timeout reaped the wrapper and left the actual test suite running
      # unsupervised forever, holding DB connections, ports and CPU, with
      # nothing left that knows its pid. Verified before the fix by
      # timing out a wrapper that had spawned a `sleep 300` grandchild:
      # the grandchild outlived the kill. A command that exits *normally*
      # having deliberately backgrounded something is its own business,
      # not Core's to reap -- the group is only ever signalled when the
      # child is still ours (see `settled` below).
      #
      # `settled`/the `ensure` are the other half of that guarantee
      # (found by an independent review, round 10). Round 9 covered the
      # timeout path, but timing out is not the only way control leaves
      # this method with the child still running, and every other way
      # leaked the workspace's entire test tree -- reparented to init,
      # holding its DB connections, ports and CPU forever, with nothing
      # left that knows its pid. The reachable one is Interrupt: #run's
      # rescue is deliberately `StandardError`, so a Ctrl-C arriving
      # while this method blocks in #wait_for_exit propagates straight
      # out (round 9 documented that as required -- the editor's server
      # must actually die), past a rescue that never sees it. Before
      # round 9 the kernel happened to paper over this in a terminal:
      # the child shared Core's process group, so the tty delivered the
      # same SIGINT to it. `pgroup: true` deliberately ends that
      # membership, which makes the leak unconditional rather than
      # merely likely -- and under an editor (`--stdio`, no controlling
      # tty) there was never any such delivery to begin with. Errno::EPERM
      # out of #kill, or any other non-ESRCH signal failure, lands the
      # same way. Guarding on "did the wait settle" rather than on
      # Interrupt specifically covers the class, per this repo's
      # discipline.
      #
      # The guard is also what keeps #kill's negative-pid signal safe.
      # #wait_for_exit only returns normally once the child is no longer
      # ours (a Process::Status means we reaped it, `:unknown` means
      # ECHILD, `nil` means #kill already reaped it), and a reaped pid is
      # free for the kernel to reuse -- so signalling `-pid` after that
      # point could hit an unrelated process group. Firing only when the
      # wait did *not* settle means the child is always still unreaped
      # here, and an unreaped child holds its pid (as a zombie at worst),
      # so no other process or group can have acquired that id yet.
      #
      # (Reviewed in round 11 and left as-is: an asynchronous Interrupt
      # landing in the single VM instruction between #wait_for_exit
      # returning and `settled = true` would kill an already-reaped pid.
      # There is no blocking call in that window, and hitting it would
      # additionally require the kernel to have recycled that exact pid
      # onto a new *group leader* within it -- pids are handed out
      # monotonically, so that is tens of thousands of intervening
      # spawns. Closing it properly would need Thread.handle_interrupt
      # around the wait, which makes Ctrl-C itself less responsive: a
      # strictly worse trade for the failure it removes.)
      def spawn_and_collect(command, args, workspace_root, env, output_path, log_path, timeout_seconds)
        settled = false
        pid = Process.spawn(env, command, *Array(args),
                            chdir: workspace_root, out: log_path, err: log_path, pgroup: true)
        status = wait_for_exit(pid, timeout_seconds)
        settled = true
        return nil if status.nil?

        results = read_results(output_path)
        return nil if results.nil?
        return nil if failed_without_evidence?(status, results)

        results
      rescue StandardError => e
        @logger.error("observation runner failed: #{e.class}: #{e.message}")
        nil
      ensure
        kill(pid) if pid && !settled
      end

      # A non-zero exit *and* nothing observed is the shape of "the test
      # command didn't run" (a syntax error, a missing gem, a typo'd
      # command name), not "the suite ran and genuinely observed
      # nothing" -- see #run's own docs for why the two must not be
      # conflated. A non-zero exit that still produced evidence is left
      # alone: an ordinary red test suite exits non-zero and its
      # observations are perfectly good evidence.
      #
      # `:unknown` (the child was reaped out from under us, so its exit
      # status is genuinely unavailable) is deliberately *not* treated as
      # a failure, and that is safe only because of #read_results'
      # empty-file rule: an empty `results` here can only have come from a
      # payload Harness' own at_exit hook wrote, i.e. the test
      # process demonstrably ran to completion under observation and
      # observed nothing. That written payload is stronger evidence than
      # the exit code we couldn't read. Were an empty *file* still to
      # reach here as `[]` (pre-round-8), `:unknown` would additionally
      # mean "we know nothing at all, so assume success and wipe the
      # store".
      def failed_without_evidence?(status, results)
        return false unless results.empty?
        return false if status == :unknown

        !status.success?
      end

      # Returns the child's Process::Status, `:unknown` when it had
      # already been reaped out from under us (Errno::ECHILD), or nil
      # when it had to be killed for exceeding `timeout_seconds`.
      def wait_for_exit(pid, timeout_seconds)
        Timeout.timeout(timeout_seconds) { Process.waitpid2(pid).last }
      rescue Timeout::Error
        @logger.error("observation runner exceeded #{timeout_seconds}s -- killing it")
        kill(pid)
        nil
      rescue Errno::ECHILD
        :unknown
      end

      # Signals the child's whole process group (negative pid -- the
      # group #spawn_and_collect's `pgroup: true` created, whose id is
      # the child's own pid), not just the child, so a wrapper's forked
      # test suite dies with it; see #spawn_and_collect's own docs for
      # why `-pid` cannot collide with an unrelated group. Falls back to
      # the bare pid whenever that group signal did not actually land --
      # the group already gone, or refused for any other reason.
      #
      # Never raises, and always reaps: one of its two call sites is
      # #spawn_and_collect's own `ensure`, where an exception escaping
      # here would *replace* the Interrupt (or other exception) currently
      # propagating -- silently converting "the user Ctrl-C'd the server"
      # into an unrelated Errno. And the reap moved into an `ensure` of
      # its own because it previously sat after the kill on the happy
      # path only: had both kills raised ESRCH, Core would have kept the
      # child as a zombie for the rest of the session, since nothing else
      # tracks that pid.
      #
      # The bare-pid retry fires on *any* failure of the group signal, not
      # only Errno::ESRCH (found by an independent review, round 11), and
      # the reap is bounded rather than an unbounded
      # `Process.waitpid(pid)` (same round). Both now live in
      # ChildProcess, which carries the full rationale -- round 12 found
      # Plugins::Loader had made byte-for-byte the same two mistakes in
      # its own hand-rolled copy, so the contract belongs in one place
      # rather than being re-derived per call site.
      #
      # The bounded reap matters more here than "don't strand a zombie":
      # this is the last thing #wait_for_exit's *timeout* path runs, and
      # #run is called synchronously on the LSP transport thread
      # (Server#run_observed_tests_result), so blocking here converts the
      # entire `timeout_seconds` mechanism this class exists to enforce
      # into "hang the editor's whole LSP loop forever".
      def kill(pid)
        ChildProcess.signal_group(pid)
      ensure
        ChildProcess.reap(pid, timeout: REAP_TIMEOUT_SECONDS, logger: @logger)
      end

      # `[]` -- "the suite ran and genuinely observed nothing" -- only
      # ever comes from a payload Harness itself wrote; `nil` --
      # "no outcome", per #run's docs -- for anything else, so neither a
      # corrupt/truncated payload nor a result file the harness never got
      # to write masquerades as "the suite observed zero methods" and
      # wipes the store.
      #
      # The payload is JSON since 0.2.16 (`024.135`). It was Marshal, and
      # the shape check below ran *after* `Marshal.load` had already
      # constructed every object the stream named -- which is the whole of
      # `024.73`, on the channel that entry did not cover.
      # `Observation::Wire` validates fields and only then builds the
      # typed values, so a payload this Core did not write produces `nil`
      # having constructed nothing.
      #
      # An *empty* file is specifically the latter, not the former (found
      # by an independent review, round 8). Harness#dump always writes a
      # complete envelope from its at_exit hook -- never zero bytes, even
      # for zero observations -- so a zero-byte file means the harness
      # never ran to completion at all -- and it is the *normal* shape of
      # a perfectly ordinary configuration, not an exotic crash: a test
      # command that isn't a Ruby process (`make test`, `npm test`,
      # `docker compose run ...`), a wrapper script that re-execs with a
      # sanitized environment (dropping the `-r<harness>` RUBYOPT this
      # class injects), or a Spring/Zeus-style preloader whose client
      # hands the run to an already-running server process and exits 0
      # having loaded nothing. Every one of those exits *zero*, so
      # #failed_without_evidence? sees a clean exit and the old `return []
      # if raw.empty?` handed Server a trusted empty run -- a full
      # Store#replace_run generation swap that destroyed every signature
      # the user had accumulated, reported as an ordinary
      # `methodCount: 0`. That is the identical conflation round 7 fixed
      # for the other failure modes, still reachable through the
      # empty-file door.
      def read_results(output_path)
        raw = File.binread(output_path)
        if raw.empty?
          @logger.error("observation runner produced no results file -- the harness never ran in the test command")
          return nil
        end

        results = Wire.decode(JSON.parse(raw, symbolize_names: true))
        return results if results

        @logger.error("observation runner produced results of an unexpected shape")
        nil
      rescue StandardError => e
        @logger.error("observation runner produced unreadable results: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
