# frozen_string_literal: true

RSpec.describe Ovallsp::BackgroundTasks do
  def fake_manager(status: :ready, &stop_body)
    manager = Class.new do
      define_singleton_method(:status) { status }
    end
    manager.define_singleton_method(:stop, &(stop_body || -> {}))
    manager
  end

  it "joins a fast-finishing tracked thread without needing to kill it" do
    bt = described_class.new(shutdown_timeout: 2)
    finished = Queue.new
    bt.track_thread(Thread.new { finished << true })

    bt.shutdown

    expect(finished.pop(timeout: 1)).to be(true)
  end

  it "kills and reclaims a tracked thread that has no owned resource and never finishes on its own" do
    bt = described_class.new(shutdown_timeout: 0.1)
    thread = Thread.new { sleep 30 }
    bt.track_thread(thread)

    bt.shutdown

    expect(thread).not_to be_alive
  end

  it "is idempotent -- a second #shutdown call is a no-op that doesn't re-stop already-stopped managers" do
    stop_calls = Queue.new
    manager = fake_manager { stop_calls << true }
    bt = described_class.new(shutdown_timeout: 1)
    bt.track_manager(manager)

    bt.shutdown
    bt.shutdown

    expect(stop_calls.pop(timeout: 1)).to be(true)
    expect(stop_calls.pop(timeout: 0.2)).to be_nil
  end

  # Found by an independent review: an earlier version gave each tracked
  # task (manager #stop, thread join) its own fresh `shutdown_timeout`
  # budget, so #shutdown's *total* worst-case time was
  # O(task_count * shutdown_timeout) rather than the O(shutdown_timeout)
  # the class's own docs already claimed.
  it "bounds the entire #shutdown call by shutdown_timeout, not shutdown_timeout per tracked manager" do
    slow_managers = Array.new(10) { fake_manager { sleep 10 } }
    bt = described_class.new(shutdown_timeout: 0.3)
    slow_managers.each { |m| bt.track_manager(m) }

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    bt.shutdown
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

    # A per-task budget would take roughly 10 * 0.3s = 3s+; a shared
    # deadline keeps total time close to a single 0.3s budget regardless
    # of how many managers were stuck.
    # perf-guard: a shared deadline vs. a per-task budget; 10 * 0.3s would be 3s+
    expect(elapsed).to be < 1.5
  end

  # Found by an independent review, across two rounds: a first fix bounded
  # only the *graceful* join phase to one shared deadline, leaving the
  # post-#kill grace period an unconditional fixed cost applied once per
  # killed thread (1s each, later reduced but still per-thread) -- real
  # teardown (e.g. AgentProcessManager#stop's own `ensure`-guaranteed
  # process termination) doesn't complete instantly just because #kill was
  # called, so N killed threads could still add up to N * that per-thread
  # cost. #reclaim_batch now kills every still-alive thread first, *then*
  # gives the whole batch exactly one more shared grace window together
  # (see its own comment) -- this test verifies that by comparing the
  # *same* per-manager teardown shape at two different task counts: a
  # per-task cost would make elapsed time scale with N; a genuinely shared
  # budget keeps it close to flat.
  it "keeps the entire #shutdown call close to one shared budget regardless of how many managers need killing, even when each needs real time to tear down" do
    build_and_shutdown = lambda do |manager_count|
      managers = Array.new(manager_count) do
        fake_manager do
          sleep 10
        ensure
          sleep 0.3
        end
      end
      bt = described_class.new(shutdown_timeout: 0.3)
      managers.each { |m| bt.track_manager(m) }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      bt.shutdown
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    elapsed_for_5 = build_and_shutdown.call(5)
    elapsed_for_20 = build_and_shutdown.call(20)

    # A per-task residual (the pre-fix shape) would make 20 managers take
    # roughly 4x as long as 5; a shared budget keeps both close to
    # shutdown_timeout (0.3s) + POST_KILL_JOIN_GRACE (0.2s) regardless of
    # count.
    expect(elapsed_for_5).to be < 1.5
    expect(elapsed_for_20).to be < 1.5
  end

  # Verifies the contract #shutdown's own comment relies on:
  # AgentProcessManager#stop puts its own teardown in `ensure` specifically
  # so that killing a manager's #stop wrapper thread (this class's own
  # bounded-reclaim mechanism) can never skip tearing down whatever
  # process/resource it owns. This test models that contract with a fake
  # rather than a real AgentProcessManager (which would need a real
  # spawned process to exercise the same way) -- the fake's own `ensure`
  # stands in for AgentProcessManager#stop's `ensure { terminate_process_locked }`.
  it "guarantees a manager's own teardown runs even when its #stop wrapper thread is killed mid-#stop" do
    torn_down = Queue.new
    manager = fake_manager do
      sleep 5
    ensure
      torn_down << true
    end
    bt = described_class.new(shutdown_timeout: 0.1)
    bt.track_manager(manager)

    bt.shutdown

    expect(torn_down.pop(timeout: 1)).to be(true)
  end

  it "never raises out of #shutdown even when a tracked manager's #stop itself raises" do
    manager = fake_manager { raise "boom" }
    bt = described_class.new(shutdown_timeout: 1)
    bt.track_manager(manager)

    expect { bt.shutdown }.not_to raise_error
  end

  it "registers the same manager instance only once, even when #track_manager is called twice for it" do
    stop_calls = Queue.new
    manager = fake_manager { stop_calls << true }
    bt = described_class.new(shutdown_timeout: 1)

    bt.track_manager(manager)
    bt.track_manager(manager)
    bt.shutdown

    expect(stop_calls.pop(timeout: 1)).to be(true)
    expect(stop_calls.pop(timeout: 0.2)).to be_nil # only stopped once, not twice
  end

  it "prunes an already-:stopped or :static_only manager instead of growing the registry forever" do
    stop_calls = Queue.new
    stopped_manager = fake_manager(status: :stopped) { stop_calls << :stopped_manager }
    static_only_manager = fake_manager(status: :static_only) { stop_calls << :static_only_manager }
    bt = described_class.new(shutdown_timeout: 1)

    bt.track_manager(stopped_manager)
    bt.track_manager(static_only_manager)
    # A fresh, still-live manager tracked afterward triggers the pruning
    # pass inside #track_manager itself (pruning happens on every append,
    # not just at #shutdown time).
    live_manager = fake_manager { stop_calls << :live_manager }
    bt.track_manager(live_manager)

    bt.shutdown

    # Only the live manager was ever actually stopped by #shutdown --
    # the terminal-status ones were pruned before #shutdown even ran, so
    # calling #stop on them again (redundant, since they're already
    # torn down) never happens.
    expect(stop_calls.pop(timeout: 1)).to eq(:live_manager)
    expect(stop_calls.pop(timeout: 0.2)).to be_nil
  end

  it "immediately stops (on a bounded, rescued wrapper thread) a manager registered after #shutdown already ran" do
    stop_calls = Queue.new
    bt = described_class.new(shutdown_timeout: 1)
    bt.shutdown # nothing tracked yet -- a no-op, but @shutting_down is now true

    late_manager = fake_manager { stop_calls << true }
    bt.track_manager(late_manager)

    expect(stop_calls.pop(timeout: 1)).to be(true)
  end

  it "does not hang or raise when a manager registered after #shutdown has a #stop that itself hangs or raises" do
    bt = described_class.new(shutdown_timeout: 0.1)
    bt.shutdown

    hanging_manager = fake_manager { sleep 10 }
    raising_manager = fake_manager { raise "boom" }

    expect { bt.track_manager(hanging_manager) }.not_to raise_error
    expect { bt.track_manager(raising_manager) }.not_to raise_error
  end

  it "immediately joins/kills a thread registered after #shutdown already ran" do
    bt = described_class.new(shutdown_timeout: 0.1)
    bt.shutdown

    late_thread = Thread.new { sleep 10 }
    bt.track_thread(late_thread)

    expect(late_thread).not_to be_alive
  end

  it "prunes finished threads from its own registry instead of growing it forever" do
    bt = described_class.new(shutdown_timeout: 1)
    tracked = Array.new(200) { bt.track_thread(Thread.new {}) }
    # #join, not just popping a "done" signal off a Queue, so every
    # thread is genuinely non-#alive? (not merely about to become so)
    # before the next #track_thread call's own pruning pass runs --
    # avoids a race between a thread's body finishing and its #alive?
    # actually flipping to false.
    tracked.each { |t| t.join(1) }

    bt.track_thread(Thread.new { sleep 1 })

    # `alive_thread_count` alone doesn't distinguish "the registry was
    # actually pruned down to 1 entry" from "the registry still holds all
    # 201 entries, 200 of them merely dead" -- both read as 1 -- so an
    # earlier version of this test passed even with #track_thread's own
    # `@threads.reject! { |t| !t.alive? }` line deleted entirely (found by
    # an independent review). Asserting on the registry's own size is
    # what actually exercises the pruning.
    expect(bt.instance_variable_get(:@threads).size).to eq(1)
    expect(bt.alive_thread_count).to eq(1)
  end
end
