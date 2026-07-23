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

  it "fetches a single model's columns and associations via #fetch_model" do
    @manager = build_manager
    @manager.start

    result = @manager.fetch_model(name: "User")

    expect(result[:associations]).to include(a_hash_including(name: "company", macro: "belongs_to"))
  end

  it "serializes concurrent requests from multiple threads instead of losing responses to each other" do
    @manager = build_manager
    @manager.start

    # Simulates many files changing at once (e.g. a git checkout touching
    # many app/models/*.rb files), each refreshed on its own background
    # thread — exactly what Server#refresh_model does per changed file.
    # Without serializing the write-then-await round trip in
    # AgentProcessManager#request, one thread's response can be read and
    # discarded by another thread waiting on a different request id,
    # leaving the rightful recipient to time out.
    names = %w[User Company Order] * 8
    threads = names.map { |name| Thread.new(name) { |n| @manager.fetch_model(name: n) } }
    results = threads.map(&:value)

    # Every thread must get back the model it actually asked for — not
    # nil (a timed-out request) and not another thread's response.
    expect(results.map { |r| r && r[:name] }).to eq(names)
  end

  describe "#reload" do
    let(:disable_flag) { File.join(fixture_root, "config", ".disable_archived_route") }

    after { File.delete(disable_flag) if File.exist?(disable_flag) }

    it "removes a route from a fresh snapshot after routes.rb changes and #reload runs (Task 006)" do
      File.delete(disable_flag) if File.exist?(disable_flag)

      @manager = build_manager
      @manager.start

      before_routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(before_routes.map { |r| r[:name] }).to include("archived")

      # Simulate editing routes.rb to remove the route, then Core telling
      # the Agent to reload — mirrors docs/04-runtime-agent.md section 8's
      # file-change -> agent/reload flow.
      File.write(disable_flag, "1")
      reload_result = @manager.reload

      expect(reload_result[:changedSections]).to eq(["routes"])
      expect(reload_result[:generation]).to be > 0

      after_routes = @manager.fetch_snapshot(sections: ["routes"])[:routes]
      expect(after_routes.map { |r| r[:name] }).not_to include("archived")
    end
  end
end
