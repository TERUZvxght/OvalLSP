# frozen_string_literal: true

require "rbconfig"

RSpec.describe Rslsp::AgentProcessManager do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:fixture_root) { File.join(core_root, "spec/fixtures/rails_minimal") }
  let(:boot_script) { File.join(core_root, "lib/rslsp/runtime_agent/boot.rb") }
  let(:environment_file) { File.join(fixture_root, "config/environment.rb") }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def build_manager(hello_timeout: 5)
    described_class.new(
      command: RbConfig.ruby,
      args: ["-I", File.join(core_root, "lib"), boot_script, "start", environment_file],
      chdir: fixture_root,
      logger: logger,
      hello_timeout: hello_timeout
    )
  end

  after do
    @manager&.stop
  end

  it "receives the fixture app's Rails root and version via agent/hello" do
    @manager = build_manager
    status = @manager.start

    expect(status).to eq(:ready)
    expect(@manager.hello_result[:railsVersion]).to eq("7.1.0-fixture")
    expect(@manager.hello_result[:root]).to eq(File.expand_path(fixture_root))
    expect(@manager.hello_result[:rubyVersion]).to eq(RUBY_VERSION)
  end

  it "connects successfully even though the fixture's initializer writes to stdout" do
    @manager = build_manager

    expect(@manager.start).to eq(:ready)
    # If the noisy `puts` in config/environment.rb had reached the protocol
    # stream instead of stderr, the Content-Length framing would have been
    # corrupted and hello would have timed out instead of succeeding.
    expect(logger).to have_received(:info).with(/accidental stdout from a noisy initializer/)
  end

  it "answers agent/status once ready" do
    @manager = build_manager
    @manager.start

    result = @manager.request_status
    expect(result[:pid]).to eq(@manager.pid)
  end

  it "degrades to static-only, and stops the process, when hello never arrives in time" do
    @manager = described_class.new(
      command: RbConfig.ruby,
      args: [File.join(core_root, "spec/fixtures/unresponsive_agent/boot.rb")],
      chdir: core_root,
      logger: logger,
      hello_timeout: 0.5
    )

    status = @manager.start

    expect(status).to eq(:static_only)
    expect(@manager.alive?).to be(false)
  end

  it "survives the agent being killed out from under it (crash), degrading to static-only" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    expect { Process.kill("KILL", pid) }.not_to raise_error
    sleep 0.3

    expect { @manager.request_status }.not_to raise_error
    expect(@manager.request_status).to be_nil
    expect(@manager.status).to eq(:static_only)
  end

  it "leaves no process behind after #stop" do
    @manager = build_manager
    @manager.start
    pid = @manager.pid

    @manager.stop

    expect(@manager.alive?).to be(false)
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end
end
