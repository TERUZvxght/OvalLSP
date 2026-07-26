# frozen_string_literal: true

# The contract three separate subprocess boundaries (Observation::Runner,
# Plugins::Loader, AgentProcessManager) used to re-derive by hand, two of
# them wrongly -- see Ovallsp::ChildProcess' own docs. Pinned directly
# here so a future caller can rely on it without re-reading every call
# site, and so the two properties that actually matter (totality of the
# signal, boundedness of the reap) are asserted independent of any one
# caller's surrounding logic.
RSpec.describe Ovallsp::ChildProcess do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  # Captured before any example installs a Process.kill stub, so cleanup
  # can always reach the real one -- a leftover `sleep 60` reaped with the
  # very stub that made the example interesting would survive the example
  # that created it.
  let!(:real_kill) { Process.method(:kill) }

  def spawn_sleeper(seconds = 30)
    Process.spawn(RbConfig.ruby, "-e", "sleep #{seconds}")
  end

  def reap_leftover(pid, killer)
    return unless pid

    killer.call("KILL", pid)
    Process.waitpid(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  describe ".signal" do
    it "reports true when the signal genuinely lands" do
      pid = spawn_sleeper
      expect(described_class.signal(pid)).to be(true)
    ensure
      reap_leftover(pid, real_kill)
    end

    # The round-11 defect in one line: a signal failure that is NOT ESRCH
    # must be reported as "nothing was signalled", because that is exactly
    # the case where a live child is left un-killed. Special-casing ESRCH
    # (which means "already gone", i.e. nothing left to do) is what made
    # two separate call sites skip their own fallback.
    it "reports false -- never raises -- for a signal failure that isn't ESRCH" do
      allow(Process).to receive(:kill).and_raise(Errno::EPERM)

      result = :unset
      expect { result = described_class.signal(4_242) }.not_to raise_error
      expect(result).to be(false)
    end

    # Deliberately a real, already-reaped pid rather than a literal like
    # -1: `Process.kill("KILL", -1)` means "every process this uid may
    # signal", which in a test suite is a machine-wide logout rather than
    # an assertion about ESRCH.
    it "reports false, without raising, for a pid that no longer exists" do
      dead = spawn_sleeper(0)
      Process.waitpid(dead)

      expect(described_class.signal(dead)).to be(false)
    end
  end

  describe ".signal_group" do
    it "falls back to the bare pid when the group signal fails for a non-ESRCH reason" do
      pid = spawn_sleeper
      attempts = []
      allow(Process).to receive(:kill) do |name, target|
        attempts << target
        raise Errno::EPERM if target.negative?

        real_kill.call(name, target)
      end

      expect(described_class.signal_group(pid)).to be(true)
      expect(attempts).to eq([-pid, pid])
    ensure
      reap_leftover(pid, real_kill)
    end
  end

  describe ".reap" do
    it "reaps a child that has actually died, well inside its budget" do
      pid = spawn_sleeper
      Process.kill("KILL", pid)

      expect(described_class.reap(pid, timeout: 2)).to be(true)
    end

    # The other half of round 11, and the half Plugins::Loader was still
    # missing in round 12: a child that outlives its kill signal must not
    # be waited on indefinitely. Every caller runs on a thread whose
    # responsiveness is the point -- the LSP transport thread, or a
    # timeout path -- so an unbounded wait converts the timeout into a
    # hang. Bounded by Thread#join rather than Timeout.timeout because
    # Timeout::Error is a StandardError and every caller here rescues
    # those by contract, so an outer Timeout would be swallowed by the
    # code under test rather than failing it.
    it "gives up and detaches, rather than blocking, on a child that never dies" do
      pid = spawn_sleeper(60)
      allow(Process).to receive(:kill).and_raise(Errno::EPERM) # so it is never actually signalled
      described_class.signal(pid)

      result = :unset
      worker = Thread.new { result = described_class.reap(pid, timeout: 1, logger: logger) }

      expect(worker.join(10)).not_to be_nil, "ChildProcess.reap blocked past its own timeout"
      expect(result).to be(false)
      expect(logger).to have_received(:error).with(a_string_matching(/outlived its kill signal/))
    ensure
      worker&.kill
      reap_leftover(pid, real_kill)
    end

    it "never raises for a pid that was already reaped by somebody else" do
      pid = spawn_sleeper(0)
      Process.waitpid(pid)

      result = :unset
      expect { result = described_class.reap(pid, timeout: 1) }.not_to raise_error
      expect(result).to be(true)
    end
  end

  # The property that matters here is the one `Thread#join` does *not*
  # have: it re-raises whatever exception killed the joined thread, in the
  # joiner. Every caller of this joins a child's pipe-pump thread from a
  # teardown path, so adopting that thread's exception means abandoning
  # the rest of the teardown -- which is exactly what round 16 found
  # AgentProcessManager#terminate_process_locked doing (see its own docs).
  describe ".join_quietly" do
    it "never adopts the exception that killed the joined thread" do
      thread = Thread.new { sleep 60 }
      thread.raise(Errno::EIO)

      result = :unset
      expect { result = described_class.join_quietly(thread, 2) }.not_to raise_error
      expect(result).to be(true)
    end

    it "returns true for a thread that finished, and tolerates a nil thread" do
      expect(described_class.join_quietly(Thread.new { nil }, 2)).to be(true)
      expect(described_class.join_quietly(nil, 2)).to be(false)
    end

    it "is bounded: gives up on a thread that never finishes rather than blocking" do
      thread = Thread.new { sleep 60 }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(described_class.join_quietly(thread, 0.2)).to be(false)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    ensure
      thread&.kill
    end
  end
end
