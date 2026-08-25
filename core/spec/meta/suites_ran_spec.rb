# frozen_string_literal: true

require "json"
require_relative "../../../scripts/check_suites_ran"

# `024.148`. Three spec files skip themselves when their environment is
# absent, and `rspec` still exits 0 -- so a green run can mean the suite
# that decides whether a capability row is true never executed.
#
# `scripts/preflight.rb`'s first version guarded this by asserting a
# non-zero example count. **A skipped example is still an example**, so
# "45 examples, 0 failures, 41 pending" satisfied it, and the check could
# not fail in the one case it existed for. Review round 1 found that.
#
# The working logic lived only inside `.github/workflows/ci.yml` -- forty
# lines of Ruby embedded in YAML, tested by nothing and callable by
# nothing else. It is a script now, and this is its test.
RSpec.describe "did the environment-dependent suites actually run" do
  def report(examples) = { "examples" => examples }

  def example_for(path, status:, message: nil)
    { "file_path" => "./#{path}", "status" => status, "pending_message" => message,
      "full_description" => "#{path} something" }
  end

  let(:suites) { { "real-Rails integration" => "spec/integration/real_rails_spec.rb" } }

  it "passes when the examples ran" do
    r = report([example_for("spec/integration/real_rails_spec.rb", status: "passed")])

    expect(CheckSuitesRan.complaints(r, suites: suites)).to be_empty
  end

  # The shape the count-based check could not see, reproduced exactly:
  # every example present, none failing, all pending.
  it "fails when every example was skipped for want of an environment" do
    r = report([
      example_for("spec/integration/real_rails_spec.rb", status: "pending", message: "rails and sqlite3 not installed"),
      example_for("spec/integration/real_rails_spec.rb", status: "pending", message: "rails and sqlite3 not installed")
    ])

    complaints = CheckSuitesRan.complaints(r, suites: suites)

    expect(complaints.length).to eq(1)
    expect(complaints.first).to include("2/2")
    expect(complaints.first).to include("skipped rather than run")
  end

  it "fails when the file contributed nothing at all" do
    r = report([example_for("spec/meta/other_spec.rb", status: "passed")])

    expect(CheckSuitesRan.complaints(r, suites: suites).first).to include("zero examples")
  end

  # `docs/EXTENSION_CAPABILITIES.md` defines a `NOT YET` row as
  # specified, having an E2E row, and currently failing or pending. That
  # is a state the document tells authors to use, so failing on it would
  # make the documented state unexpressible.
  it "allows a pending example that declares itself NOT YET" do
    r = report([example_for("spec/integration/real_rails_spec.rb", status: "pending",
                            message: "NOT YET -- specified, not implemented")])

    expect(CheckSuitesRan.complaints(r, suites: suites)).to be_empty
  end

  # The three names are the point of the module; a list that silently
  # emptied would make every example above vacuous.
  it "names the three suites that can skip themselves" do
    expect(CheckSuitesRan::SUITES.values).to contain_exactly(
      "spec/integration/real_rails_spec.rb",
      "spec/e2e/capabilities_spec.rb",
      "spec/meta/client_behaviour_spec.rb"
    )
  end

  # And CI must call the same script rather than keeping its own copy --
  # the divergence is what let preflight ship a weaker rule.
  #
  # `024.203`. This read the whole workflow file and asserted the
  # substring `scripts/check_suites_ran.rb`. A commented-out step keeps
  # that text, as does one carrying `if: false` or `continue-on-error:
  # true`, so the example passed under every mutation it appeared to
  # guard against -- and it reads as an independent guard on the link
  # `024.148` established, which is what made it worth more than
  # nothing to a reader and nothing to the build. The step is located in
  # the structure GitHub executes now, through the same helper its
  # neighbour uses.
  it "is what ci.yml runs, not a second implementation" do
    step = CiWorkflow.core_step("Fail if the real-Rails or capability suites were skipped instead of run")

    expect(step).not_to be_nil, "the skip guard is no longer a step of the core job"
    expect(CiWorkflow.executed?(step)).to be(true),
                                          "the step is present but disabled by `if:` or `continue-on-error:`"
    expect(step.fetch("run")).to include("scripts/check_suites_ran.rb")
  end
end
