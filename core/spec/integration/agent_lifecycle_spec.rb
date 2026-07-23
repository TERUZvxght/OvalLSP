# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "AgentProcessManager lifecycle (subprocess integration)" do
  let(:core_root) { File.expand_path("../..", __dir__) }

  # Spawns a throwaway "Core" process that starts a Runtime Agent and then
  # exits normally (relying on AgentProcessManager's at_exit hook, not an
  # explicit #stop) — proving that when Core goes away, no Agent process
  # survives it (docs/design/tasks/005-runtime-agent-heartbeat.md).
  it "cleans up the Runtime Agent when the parent (Core) process exits normally" do
    fixture_root = File.join(core_root, "spec/fixtures/rails_minimal")
    boot_script = File.join(core_root, "lib/rslsp/runtime_agent/boot.rb")
    environment_file = File.join(fixture_root, "config/environment.rb")

    script = <<~RUBY
      require #{File.join(core_root, "lib/rslsp").inspect}
      require "logger"

      manager = Rslsp::AgentProcessManager.new(
        command: #{RbConfig.ruby.inspect},
        args: ["-I", #{File.join(core_root, "lib").inspect}, #{boot_script.inspect}, "start", #{environment_file.inspect}],
        chdir: #{fixture_root.inspect},
        logger: Logger.new(File::NULL),
        hello_timeout: 5
      )
      manager.start
      puts manager.pid
      # No explicit manager.stop: only the at_exit hook registered inside
      # AgentProcessManager#start should clean this up.
    RUBY

    stdout_str, _stderr_str, status = Open3.capture3(RbConfig.ruby, stdin_data: script)

    expect(status.exitstatus).to eq(0)
    agent_pid = Integer(stdout_str.strip)

    expect { Process.kill(0, agent_pid) }.to raise_error(Errno::ESRCH)
  end
end
