# frozen_string_literal: true

require "open3"
require "rbconfig"

# The decision half is required rather than shelled out to, which is
# what makes it testable without a network. The script runs itself only
# when it is the program.
require_relative "../../../scripts/ci_status"

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

  # **What it said about this branch was a coin toss between two
  # workflows.** `gh run list --limit 1` returns the newest run of *any*
  # workflow, and this repository runs two on every push. 0.3.0's release
  # branch had `CI` red and `Site` green; `Site` finished last, so the
  # line under a green preflight read `release/0.3.0 success` while the
  # branch's own suite had been failing for two commits. That is 024.284's
  # own failure mode arriving through the door 024.284 opened, and it cost
  # the release two pushes before anyone read the run list.
  #
  # The decision is tested here rather than against GitHub: the network
  # half stays untested on purpose -- its failures are ordinary and the
  # examples above cover them -- and what was wrong was never the network.
  describe "the verdict it computes from the runs gh returned" do
    # A method rather than a constant: a constant written inside a
    # `describe` is defined on Object, and this release has already lost
    # a run to two spec files choosing the same name.
    def head_sha = "0123456789abcdef0123456789abcdef01234567"

    def run_json(workflow, status:, conclusion:, sha: head_sha)
      { "status" => status, "conclusion" => conclusion, "workflowName" => workflow,
        "headSha" => sha, "url" => "https://example.invalid/#{workflow}" }
    end

    def line(runs, head: head_sha)
      CiStatus.verdict_line(branch: "release/probe", runs: runs, head: head)
    end

    it "reports a workflow that failed even when a later one on the same commit passed" do
      result = line([run_json("Site", status: "completed", conclusion: "success"),
                     run_json("CI", status: "completed", conclusion: "failure")])

      expect(result).to include("failure")
      expect(result).to include("CI")
    end

    # The control, and it is what makes the example above mean something:
    # the same shape with nothing failing must still read as success, so a
    # fix that reports failure unconditionally fails this file.
    it "still says success when every workflow on the commit passed" do
      result = line([run_json("Site", status: "completed", conclusion: "success"),
                     run_json("CI", status: "completed", conclusion: "success")])

      expect(result).to include("success")
      expect(result).not_to include("failure")
    end

    # A run still going is not a verdict, and reading `conclusion` off one
    # gives the empty string -- which prints as though the branch were
    # fine.
    it "says a run is still going rather than reading a conclusion it has not got" do
      result = line([run_json("Site", status: "completed", conclusion: "success"),
                     run_json("CI", status: "in_progress", conclusion: nil)])

      expect(result).not_to include("success")
      expect(result).to match(/in progress/)
    end

    it "says so when the newest runs belong to a commit that is not HEAD" do
      result = line([run_json("CI", status: "completed", conclusion: "success", sha: "f" * 40)])

      expect(result).to match(/older commit/)
    end

    it "reports having nothing rather than inventing a verdict" do
      expect(line([])).to match(/no runs recorded/)
    end
  end


  it "is invoked by preflight" do
    expect(File.read(File.join(root, "scripts", "preflight.rb"))).to include("ci_status.rb")
  end
end
