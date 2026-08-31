# frozen_string_literal: true

require "open3"
require "rbconfig"

# 024.284: preflight's nine checks are the Ruby suites and the tree
# checks, so "all 9 checks passed" is a statement about the Core and says
# nothing about the extension -- and nothing local reads CI at all. That
# is why 024.281 and 024.282 survived a week of green local runs.
#
# The form chosen there is a line that *reports* rather than gates: it
# must never fail preflight, because the two ways it can fail to answer
# (no network, no `gh`) are ordinary and neither means the tree is bad.
RSpec.describe "scripts/ci_status.rb" do
  root = File.expand_path("../../..", __dir__)
  script = File.join(root, "scripts", "ci_status.rb")

  it "exists" do
    expect(File).to exist(script)
  end

  # The whole point of this script is that it is safe to run at the end
  # of the most-run gate in the repository. An exit status other than 0 --
  # for any reason, including the ones it cannot control -- would make it
  # a gate.
  it "exits 0 and prints one line, whatever it can or cannot reach" do
    out, err, status = Open3.capture3("ruby", script, chdir: root)
    expect(status.exitstatus).to eq(0), "stderr: #{err}"
    expect(out.lines.length).to eq(1), "expected one line, got: #{out.inspect}"
    expect(out).to start_with("ci: ")
  end

  # And it must say which of the two it is, rather than printing an empty
  # verdict that reads like "CI is fine".
  it "names the reason when it cannot tell" do
    out, = Open3.capture3(
      # An absolute interpreter, because the point is to hide `gh`
      # from the script, not to hide `ruby` from this example -- which
      # is what a bare "ruby" here did on the first run.
      { "PATH" => "/nonexistent-path-for-this-example" }, RbConfig.ruby, script, chdir: root
    )
    expect(out).to start_with("ci: ")
    expect(out).to match(/cannot tell|unavailable|not installed|gh/i)
    expect(out).not_to match(/\bpass(ing|ed)\b|\bgreen\b|\bsuccess\b/i)
  end

  it "is invoked by preflight" do
    expect(File.read(File.join(root, "scripts", "preflight.rb"))).to include("ci_status.rb")
  end
end
