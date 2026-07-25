# frozen_string_literal: true

module Rslsp
  # Pure restart-attempt policy for the Runtime Agent (Task 022 "Agent
  # restart policy: exponential backoff, restart上限, manual restart,
  # static-only継続"). Knows nothing about AgentProcessManager,
  # threading, or actually restarting anything -- Server calls
  # #record_failure_and_next_delay when an Agent becomes unavailable
  # unexpectedly (AgentProcessManager's `on_unavailable` callback) and
  # schedules the actual retry itself, so this class stays trivially
  # unit-testable (no subprocess, no sleeping in specs).
  class AgentSupervisor
    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_BASE_DELAY_SECONDS = 1.0
    DEFAULT_MAX_DELAY_SECONDS = 60.0

    def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, base_delay_seconds: DEFAULT_BASE_DELAY_SECONDS,
                   max_delay_seconds: DEFAULT_MAX_DELAY_SECONDS)
      @max_attempts = max_attempts
      @base_delay_seconds = base_delay_seconds
      @max_delay_seconds = max_delay_seconds
      @consecutive_failures = 0
      # Server calls into this instance from at least three different
      # background threads (the initial bootstrap thread, #restart_agent's
      # thread, and whichever thread AgentProcessManager's on_unavailable
      # callback runs on) -- found unguarded by an independent review of
      # Task 022: a bare `@consecutive_failures += 1`/`= 0` across
      # concurrent callers could lose an update or interleave a read with
      # a write, corrupting the backoff/crash-loop-cap bookkeeping (not a
      # process-lifecycle correctness issue -- that stays serialized via
      # Server's own @agent_restart_mutex -- but wrong retry counts/timing
      # is exactly what this class exists to get right).
      @mutex = Mutex.new
    end

    # Call once per unexpected "Agent became unavailable" event. Returns
    # the delay (seconds) to wait before the next automatic restart
    # attempt, or nil once `max_attempts` consecutive failures have
    # happened without an intervening success -- "crash loopを無限再起動
    # しない": from that point on, only an explicit manual restart
    # (#reset, then a fresh attempt) tries again, matching "Agent crash
    #後にstatic-onlyを維持して再起動できる".
    def record_failure_and_next_delay
      @mutex.synchronize do
        @consecutive_failures += 1
        next nil if @consecutive_failures > @max_attempts

        [@base_delay_seconds * (2**(@consecutive_failures - 1)), @max_delay_seconds].min
      end
    end

    def exhausted?
      @mutex.synchronize { @consecutive_failures > @max_attempts }
    end

    # A healthy connection resets the streak -- one crash after a long
    # stable run is a fresh first failure next time, not the Nth in a
    # streak that happened days ago.
    def record_success
      @mutex.synchronize { @consecutive_failures = 0 }
    end

    # An explicit, user-initiated restart (`RSLSP: Restart Rails Agent`)
    # always gets a fresh attempt regardless of how many *automatic*
    # attempts were already exhausted -- "manual restart" is explicitly
    # its own capability in the design doc, not gated by the automatic
    # backoff's own cap.
    def reset
      @mutex.synchronize { @consecutive_failures = 0 }
    end
  end
end
