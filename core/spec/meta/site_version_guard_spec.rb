# frozen_string_literal: true

require "yaml"

# 0.2.3's countermeasure for the badge drift 0.2.2 shipped: the site
# check compares the version the index pages advertise against
# vscode/package.json, but it ran only from pages.yml, which fires only
# on site/ changes -- so a version bump alone could turn the check red
# with nothing to run it, and did, for five days on main. The fix is
# wiring: the check runs in ci.yml too, and pages.yml also triggers on
# the version file. Both halves are workflow text that nothing executes
# locally, so -- exactly as `ci_skip_guard_spec.rb` puts it for the other
# CI-only guard -- nothing would notice either being deleted again. The
# guard needs a guard.
#
# Asserting on parsed YAML rather than a regex where the claim is about
# structure (which paths fire a workflow), and on the job's own step text
# where it is about what a job runs.
RSpec.describe "the CI wiring that keeps the site's version badge honest" do
  def workflow(name)
    YAML.safe_load(File.read(File.expand_path("../../../.github/workflows/#{name}", __dir__), encoding: "UTF-8"))
  end

  # YAML 1.1 reads a bare `on` key as boolean true, and GitHub's own
  # parser accepts either -- so this reader takes both, rather than
  # pinning an accident of the serializer.
  def triggers(name)
    data = workflow(name)
    data["on"] || data[true]
  end

  it "runs the site check from ci.yml, so a version bump cannot dodge it" do
    steps = workflow("ci.yml").fetch("jobs").fetch("site-consistency").fetch("steps")
    run_lines = steps.filter_map { |step| step["run"] }

    expect(run_lines).to include(a_string_including("scripts/check_site_links.rb"))
  end

  it "fires the deploy workflow on the version file, both for pushes and for pull requests" do
    on = triggers("pages.yml")

    expect(on.dig("push", "paths")).to include("vscode/package.json")
    expect(on.dig("pull_request", "paths")).to include("vscode/package.json")
  end

  # The other side of the comparison: the deploy must still fire on the
  # pages themselves, or the badge fix would trade one blind spot for
  # another.
  it "still fires the deploy workflow on site changes" do
    on = triggers("pages.yml")

    expect(on.dig("push", "paths")).to include("site/**")
    expect(on.dig("pull_request", "paths")).to include("site/**")
  end
end
