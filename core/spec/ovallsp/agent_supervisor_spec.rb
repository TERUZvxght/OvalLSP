# frozen_string_literal: true

RSpec.describe Ovallsp::AgentSupervisor do
  subject(:supervisor) { described_class.new(max_attempts: 3, base_delay_seconds: 1.0, max_delay_seconds: 60.0) }

  it "returns an exponentially increasing delay for each consecutive failure" do
    expect(supervisor.record_failure_and_next_delay).to eq(1.0)
    expect(supervisor.record_failure_and_next_delay).to eq(2.0)
    expect(supervisor.record_failure_and_next_delay).to eq(4.0)
  end

  it "caps the delay at max_delay_seconds" do
    supervisor = described_class.new(max_attempts: 100, base_delay_seconds: 1.0, max_delay_seconds: 5.0)
    6.times { supervisor.record_failure_and_next_delay }

    expect(supervisor.record_failure_and_next_delay).to eq(5.0)
  end

  it "returns nil once max_attempts consecutive failures have happened -- crash loop protection" do
    3.times { expect(supervisor.record_failure_and_next_delay).not_to be_nil }

    expect(supervisor.record_failure_and_next_delay).to be_nil
    expect(supervisor.exhausted?).to be(true)
  end

  it "resets the streak on a successful connection, so a later crash starts a fresh backoff" do
    2.times { supervisor.record_failure_and_next_delay }
    supervisor.record_success

    expect(supervisor.record_failure_and_next_delay).to eq(1.0)
  end

  it "#reset always clears the streak, even after the automatic cap was already exhausted" do
    5.times { supervisor.record_failure_and_next_delay }
    expect(supervisor.exhausted?).to be(true)

    supervisor.reset

    expect(supervisor.exhausted?).to be(false)
    expect(supervisor.record_failure_and_next_delay).to eq(1.0)
  end

  # Found by an independent review of Task 022: Server calls into one
  # AgentSupervisor instance from several different background threads
  # (the initial bootstrap thread, #restart_agent's thread, and whichever
  # thread AgentProcessManager's on_unavailable callback runs on) -- the
  # class is documented as being called this way, so its own state
  # mutations are now guarded by an internal Mutex (see #initialize's own
  # comment). NOT included: a statistical "hammer it with threads and
  # check for lost updates" test -- verified experimentally that a bare
  # `@x += 1` under real thread contention on CRuby practically never
  # loses an update even at 100,000+ concurrent increments (MRI's GIL
  # keeps that specific bytecode sequence effectively atomic in
  # practice), so such a test would pass identically with or without the
  # mutex and give false confidence rather than real coverage. The mutex
  # is still the correct fix for what this class is documented and
  # exercised to do (guard against a *theoretical* interleaving CRuby's
  # own scheduler doesn't currently expose, but no other Ruby
  # implementation is obligated to avoid) -- this test only confirms
  # concurrent access completes correctly and without deadlocking.
  it "completes correctly under concurrent access from multiple threads, without deadlocking or raising" do
    supervisor = described_class.new(max_attempts: 100_000, base_delay_seconds: 0.0, max_delay_seconds: 0.0)

    threads = Array.new(50) { Thread.new { supervisor.record_failure_and_next_delay } }
    threads << Thread.new { supervisor.record_success }
    threads << Thread.new { supervisor.reset }
    threads << Thread.new { supervisor.exhausted? }

    expect { threads.each(&:join) }.not_to raise_error
  end
end
