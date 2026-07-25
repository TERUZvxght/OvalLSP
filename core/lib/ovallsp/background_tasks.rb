# frozen_string_literal: true

module Ovallsp
  # Server's own registry of every background Thread (and every
  # AgentProcessManager born on one of those threads) it spawns, so a single
  # #shutdown call can reclaim all of it deterministically before
  # `Server#run` returns -- instead of Threads left to finish (or never
  # finish) entirely on their own.
  #
  # Found necessary by a leaked Runtime Agent bootstrap thread surviving
  # past the end of the RSpec example that spawned it
  # (spec/ovallsp/server_workspace_trust_spec.rb's "slow bootstrap" case):
  # the thread wasn't tracked anywhere, so nothing ever joined or cancelled
  # it, and it woke up inside a *later* example, touching that example's
  # RSpec doubles (`RSpec::Mocks::ExpiredTestDoubleError`) after they'd
  # already been torn down. Every `Thread.new` in Server now registers
  # itself here instead of being left to run untracked.
  #
  # Deliberately two separate registries (managers, threads) rather than
  # one: an AgentProcessManager can be mid-#start (blocked on the
  # agent/hello handshake, with an already-spawned child OS process) on a
  # thread that itself hasn't finished yet -- #shutdown needs to *ask* the
  # *manager* to stop (which force-terminates its child process and, as a
  # side effect, unblocks anything blocked inside that manager's own
  # #start/#request) before it can expect the *thread* that's blocked
  # inside it to actually finish and become joinable.
  #
  # `shutdown_timeout` is fixed at construction (not passed per-#shutdown-call)
  # specifically so a thread/manager registered *after* #shutdown has
  # already run -- and therefore reclaimed inline, on the calling thread,
  # by #track_thread/#track_manager themselves -- uses the exact same bound
  # a caller configured, not some other default (found by an independent
  # review: an earlier version hardcoded DEFAULT_SHUTDOWN_TIMEOUT on that
  # path regardless of what #shutdown itself had been called with).
  class BackgroundTasks
    DEFAULT_SHUTDOWN_TIMEOUT = 5

    # A small, fixed grace period after #kill is called, independent of
    # `shutdown_timeout` -- #kill doesn't take effect instantaneously (in
    # particular, AgentProcessManager#stop's own `ensure`-guaranteed
    # teardown, see #shutdown's comment, still has real work left to do:
    # terminating a child process, waiting for it to exit, force-killing
    # it if it doesn't), so some grace period after #kill is unavoidable.
    # #reclaim_batch applies this once per *call*, not once per thread --
    # see its own comment for why an earlier version that applied it
    # per-thread reintroduced the same O(task_count) shape #shutdown's
    # shared `deadline` had just fixed for the graceful-join phase (found
    # by an independent review).
    POST_KILL_JOIN_GRACE = 0.2

    def initialize(shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT)
      @mutex = Mutex.new
      @threads = []
      @managers = []
      @shutting_down = false
      @shutdown_timeout = shutdown_timeout
    end

    # Registers `thread`. Returns `thread` so call sites can write
    # `@background_tasks.track_thread(Thread.new { ... })` inline. A
    # thread registered after #shutdown has already run is joined/killed
    # immediately, on the calling thread, rather than silently left
    # untracked -- shutdown can, in principle, race a thread that's only
    # just about to spawn another (e.g. #handle_agent_unavailable's
    # retry-delay thread, scheduled from inside the very bootstrap thread
    # #shutdown is simultaneously reclaiming).
    #
    # Opportunistically prunes already-finished threads before appending --
    # keeps this registry from growing without bound across a long-lived
    # Server process where #refresh_routes/#refresh_models/#refresh_all_models
    # each spawn a fresh thread per file-change batch (found by an
    # independent review: nothing previously pruned a thread once it had
    # naturally finished, so the array grew for the lifetime of the
    # process). O(n) per call, but n is realistically small -- pruning
    # every call rather than sampling (contrast Cache::Store's
    # probabilistic pruning) since a Thread object's own #alive? check is
    # cheap, not a filesystem operation.
    def track_thread(thread)
      already_shutting_down = @mutex.synchronize do
        if @shutting_down
          true
        else
          @threads.reject! { |t| !t.alive? }
          @threads << thread
          false
        end
      end
      reclaim_batch([thread], deadline_from_now) if already_shutting_down
      thread
    end

    # Registers `manager` (anything responding to #stop -- in production
    # always a real AgentProcessManager, in tests sometimes a duck-typed
    # fake) so #shutdown can stop it. Returns `manager` unchanged so call
    # sites can assign its result directly to @agent_manager. If #shutdown
    # has already run by the time this fires -- the exact race a bootstrap
    # thread that's only just constructed its AgentProcessManager (but
    # hasn't yet reached the blocking #start call) can lose against a
    # concurrent Server shutdown -- stops it immediately (on a bounded,
    # rescued wrapper thread, exactly like #shutdown's own manager
    # reclamation -- an independent review found the original version of
    # this method called `manager.stop` inline here, unbounded and
    # unrescued, meaning a manager whose #stop hung or raised could hang
    # or crash whatever thread happened to call #track_manager, e.g. a
    # bootstrap thread's own on_manager_created hook) instead of
    # registering it into a registry #shutdown will never look at again --
    # which is what closes the "orphaned child process from a bootstrap
    # that started after shutdown began" gap.
    #
    # Idempotent by identity: calling this twice with the *same* manager
    # instance (Server does, deliberately -- once from
    # RailsBootstrap.start's on_manager_created: hook the moment the
    # manager exists, and again when wrapping whatever #start eventually
    # returns, so a manager is tracked even if some future/test bootstrap
    # never calls the hook at all) registers it only once. Also prunes any
    # manager that has already reached a terminal status (:stopped or
    # :static_only -- the latter added by an independent review: a
    # manager that degraded to static-only already tore down its own
    # process internally, via AgentProcessManager#start's own failure
    # paths, so there's nothing left for a future #stop to do) before
    # appending, for the same unbounded-growth reason as #track_thread.
    TERMINAL_MANAGER_STATUSES = %i[stopped static_only].freeze

    def track_manager(manager)
      return manager if manager.nil?

      already_shutting_down = @mutex.synchronize do
        if @shutting_down
          true
        elsif @managers.any? { |tracked| tracked.equal?(manager) }
          false
        else
          @managers.reject! { |tracked| tracked.respond_to?(:status) && TERMINAL_MANAGER_STATUSES.include?(tracked.status) }
          @managers << manager
          false
        end
      end
      reclaim_batch([Thread.new { safely { manager.stop } }], deadline_from_now) if already_shutting_down
      manager
    end

    # Idempotent (a second call is a no-op returning immediately), bounded
    # (the graceful-join phase of every manager #stop and every tracked
    # thread shares one `deadline` computed from `shutdown_timeout` --an
    # independent review found an earlier version gave each task its own
    # full `shutdown_timeout`, making that phase's worst-case time
    # O(task_count * shutdown_timeout) -- and any threads still alive
    # after that deadline are all killed and then given exactly one more
    # shared POST_KILL_JOIN_GRACE window together, not one each, keeping
    # the *whole* call's worst case at roughly
    # `shutdown_timeout + POST_KILL_JOIN_GRACE` regardless of how many
    # tasks were tracked -- see #reclaim_batch's own comment), and never
    # raises (every manager #stop / thread #join is individually rescued
    # -- #kill itself doesn't raise on a live thread in practice, and
    # Server#shutdown_background_tasks rescues one level up regardless --
    # so one stuck task can't stop the rest from being reclaimed, and a
    # caller running this from an `ensure` block never itself raises out
    # of it).
    #
    # A caller must not assume every tracked manager's OS process is
    # actually gone by the time this method returns: AgentProcessManager#stop's
    # own `ensure`-guaranteed teardown can still be running on a killed
    # wrapper thread after #shutdown itself has already moved on (bounded
    # only by that thread's own eventual completion, not by this method's
    # deadline) -- what #shutdown guarantees is that teardown was asked
    # for and will run to completion *eventually*, not that it already has
    # by the time control returns here.
    #
    # Every tracked manager's #stop is *started* (each on its own
    # short-lived thread, so they run concurrently with each other and
    # with the join loop below) before any join happens -- a thread
    # blocked inside that manager's own #start (mid agent/hello) or a
    # request method (#reload, #fetch_snapshot, ...) is unblocked as a
    # side effect of the manager's pipes/process being torn down, so by
    # the time this reaches that thread in the join loop, it's either
    # already finished or about to be within its own normal control flow,
    # not still genuinely blocked on external I/O.
    #
    # AgentProcessManager#stop itself guarantees its own teardown runs via
    # `ensure`, specifically so that killing one of these wrapper threads
    # (this deadline being exceeded) can never skip tearing down the
    # process it owns -- see that method's own comment. Without that
    # guarantee, killing a wrapper thread mid-#stop (e.g. one blocked
    # inside an `agent/shutdown` RPC that's waiting on a mutex some other
    # slow request already holds) would abandon a live child process
    # (found by an independent review).
    def shutdown
      managers, threads = @mutex.synchronize do
        next [[], []] if @shutting_down

        @shutting_down = true
        [@managers.dup, @threads.dup]
      end

      stoppers = managers.map { |manager| Thread.new { safely { manager.stop } } }
      reclaim_batch(stoppers + threads, deadline_from_now)
    end

    def alive_thread_count
      @mutex.synchronize { @threads.count(&:alive?) }
    end

    private

    def deadline_from_now
      monotonic_now + @shutdown_timeout
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Two phases, each bounded by one shared deadline covering the whole
    # batch -- not one deadline per thread -- so the *total* cost of
    # reclaiming N threads stays close to a single budget regardless of N:
    #
    # 1. Graceful join: each thread in turn is joined against whatever
    #    remains of `deadline` (the caller's `shutdown_timeout`-derived
    #    absolute time) when its turn comes -- not a fresh duration each
    #    -- so a first thread that's still alive when `deadline` arrives
    #    consumes the whole shared budget, and every thread after it gets
    #    `join(0)` (a non-blocking check) and falls straight through to
    #    the kill phase below; that's the intended cost of sharing one
    #    deadline, not a bug. A thread blocked on Agent I/O has already
    #    been unblocked by this point (every tracked manager's #stop was
    #    started, concurrently, before this runs -- see #shutdown's own
    #    comment) and should wind down almost immediately; a thread with
    #    no owned resource at all (the crash-loop restart delay thread,
    #    purely `sleep`ing) won't.
    # 2. Kill-and-reclaim: whatever's still alive once `deadline` passes
    #    is killed, then every one of *those* threads shares exactly one
    #    more POST_KILL_JOIN_GRACE-long window (not one window each) --
    #    found by an independent review: an earlier version gave each
    #    killed thread its own fresh grace period, so N threads all
    #    needing a kill could still add up to N * POST_KILL_JOIN_GRACE on
    #    top of `deadline`, even though every one of them is already
    #    running concurrently on its own OS thread and there's no reason
    #    their post-kill grace periods can't overlap too.
    #
    # #kill is safe here specifically because AgentProcessManager#stop's
    # own `ensure` guarantees a killed manager-#stop wrapper thread still
    # tears down whatever process it owns; nothing here abandons a live
    # subprocess (see #shutdown's own comment for why that guarantee
    # matters).
    def reclaim_batch(threads, deadline)
      live = threads.select { |t| t.is_a?(Thread) }

      live.each { |t| safely { t.join(remaining(deadline)) } }

      still_alive = live.select(&:alive?)
      return if still_alive.empty?

      still_alive.each(&:kill)
      post_kill_deadline = monotonic_now + POST_KILL_JOIN_GRACE
      still_alive.each { |t| safely { t.join(remaining(post_kill_deadline)) } }
    end

    def remaining(deadline)
      [deadline - monotonic_now, 0].max
    end

    def safely
      yield
    rescue StandardError
      nil
    end
  end
end
