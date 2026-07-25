# frozen_string_literal: true

RSpec.describe Rslsp::AgentSupervisor do
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
end
