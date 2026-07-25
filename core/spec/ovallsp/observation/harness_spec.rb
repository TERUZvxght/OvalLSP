# frozen_string_literal: true

require "open3"
require "tmpdir"

# Harness is loaded into the *workspace's own* test process via
# `RUBYOPT="-r<harness.rb>"`, so every assertion here is made against a
# genuinely separate Ruby process spawned exactly the way
# Observation::Runner spawns one -- loading harness.rb into this process
# would install a TracePoint and an at_exit hook over Core's own suite
# (which is also why harness.rb is deliberately never `require`d by the
# gem, and why this describe takes a String, not the constant).
RSpec.describe "Ovallsp::Observation::Harness" do
  let(:fixtures_root) { File.expand_path("../../fixtures/observation_runner", __dir__) }

  # `env`/`args` mirror Observation::Runner#harness_env's three
  # OvalLSP_OBSERVATION_* variables plus its `-r<harness>` RUBYOPT
  # injection -- the only channel Harness#install reads at all.
  def run_under_harness(script)
    output_path = File.join(Dir.mktmpdir("ovallsp-harness-spec"), "results.marshal")
    env = {
      "OvalLSP_OBSERVATION_WORKSPACE_ROOT" => fixtures_root,
      "OvalLSP_OBSERVATION_OUTPUT_PATH" => output_path,
      "OvalLSP_OBSERVATION_RUN_ID" => "harness-spec",
      "RUBYOPT" => [ENV.fetch("RUBYOPT", nil), "-r#{Ovallsp::Observation::Runner::HARNESS_PATH}"].compact.join(" ")
    }

    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, script, chdir: fixtures_root)
    { stdout: stdout, stderr: stderr, status: status, output_path: output_path }
  end

  it "observes a passing suite without disturbing its exit status or stderr" do
    result = run_under_harness("run_tests.rb")

    expect(result[:status].exitstatus).to eq(0)
    expect(result[:stderr]).to be_empty
    expect(File.binread(result[:output_path])).not_to be_empty
  end

  # Found by an independent review (round 9) of Task 022.2. #install
  # wraps its own body in `rescue StandardError` precisely so "a broken
  # harness must never break the actual test run it's silently riding
  # along with" -- but the at_exit block runs long after #install has
  # returned, entirely outside that rescue. Ruby does not swallow an
  # exception escaping an at_exit handler: it prints the backtrace to
  # stderr *and* forces the process' exit status to 1. So any bug in
  # Collector#stop/#results (the two calls in that block that, unlike
  # #dump, had no rescue of their own) reported the workspace's own
  # passing suite as a failure, with a backtrace naming a file the user
  # never asked to load -- and in CI, failed the build outright.
  it "never turns a passing suite red when the harness itself breaks at exit" do
    result = run_under_harness("broken_harness.rb")

    expect(result[:stdout]).to include("workspace suite passed")
    expect(result[:status].exitstatus).to eq(0)
    expect(result[:stderr]).not_to include("simulated broken harness")
    expect(result[:stderr]).not_to include("harness.rb")
  end
end
