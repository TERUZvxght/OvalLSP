# frozen_string_literal: true

require "yaml"

# 0.2.3's countermeasure for the badge drift 0.2.2 shipped: the site
# check compares the version the index pages advertise against
# vscode/package.json, but it ran only from pages.yml, which fires only
# on site/ changes -- so a version bump alone could turn the check red
# with nothing to run it, and 0.2.2's did. The fix is wiring: the check
# runs in ci.yml too, and pages.yml also triggers on the version file
# (the measured timeline is 028's "A guard that could not see its
# input"). Both halves are workflow text that nothing executes locally,
# so -- exactly as `ci_skip_guard_spec.rb` puts it for the other
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

  # "Gating the deploy" is the half of this guard that predates 0.2.3,
  # and round 3 showed it was just as deletable: replace the check job's
  # run line with an echo and every spec stays green while the deploy
  # publishes unchecked. Both links of the gate, pinned: the check job
  # actually runs the script, and the deploy job actually needs the
  # check.
  it "keeps the deploy gated on the check actually running the script" do
    jobs = workflow("pages.yml").fetch("jobs")
    check_runs = jobs.fetch("check").fetch("steps").filter_map { |step| step["run"] }

    expect(check_runs).to include(a_string_including("scripts/check_site_links.rb"))
    expect(Array(jobs.fetch("deploy")["needs"])).to include("check")
  end
end

# The wiring above proves the script *runs*; merge round 6 of 0.2.3's
# loop proved that was the whole of it: gutting the script's badge
# comparison, or its roadmap-parity section, left the script green, this
# file green, and the full meta directory green -- CI, the deploy gate
# and every spec kept passing with the countermeasure's logic deleted.
# So the script's checking behaviour gets pinned the only way behaviour
# can be: by running the real script against a real input broken in
# exactly the way each check exists to catch. The fixture is a copy of
# the shipped site with one mutation -- never a hand-built miniature, so
# these examples do not drift as the site grows -- and the pristine-copy
# control proves a failure below is the check firing, not a broken
# fixture. All copies live under Dir.mktmpdir, per the containment rule.
RSpec.describe "the site check's own teeth" do
  require "tmpdir"
  require "fileutils"

  # Methods, not constants: a constant assigned inside a describe block
  # lands on the top level, which is the collision surface
  # `spec_constants_spec.rb` exists to police.
  def script_path
    File.expand_path("../../../scripts/check_site_links.rb", __dir__)
  end

  def repo_root
    File.expand_path("../../..", __dir__)
  end

  def run_check_against(site_dir)
    output = IO.popen(["ruby", script_path, site_dir], err: [:child, :out], &:read)
    [$?.exitstatus, output]
  end

  def with_site_copy
    Dir.mktmpdir("ovallsp-site-teeth") do |dir|
      copy = File.join(dir, "site")
      FileUtils.cp_r(File.join(repo_root, "site"), copy)
      yield copy
    end
  end

  def rewrite(path)
    File.write(path, yield(File.read(path, encoding: "UTF-8")))
  end

  it "passes a pristine copy of the shipped site, so the failures below are the checks firing" do
    with_site_copy do |copy|
      status, output = run_check_against(copy)

      expect(status).to eq(0), output
    end
  end

  it "fails a page whose advertised version disagrees with package.json" do
    with_site_copy do |copy|
      rewrite(File.join(copy, "index.html")) do |html|
        mutated = html.sub(/(Preview\s+v?)\d+\.\d+\.\d+/) { "#{Regexp.last_match(1)}9.9.9" }
        raise "fixture mutation did not apply -- no advertised version found" if mutated == html

        mutated
      end

      status, output = run_check_against(copy)

      expect(status).not_to eq(0), "a wrong advertised version passed the site check"
      expect(output).to include("package.json")
    end
  end

  it "fails a roadmap panel that loses an item the markdown still plans" do
    # The first *planned* version, read from the same source the script
    # compares against -- shipped panels answer to the changelog instead,
    # so mutating one of those would test the wrong branch.
    planned = File.read(File.join(repo_root, "docs", "ROADMAP.md"), encoding: "UTF-8")[/^## (\d+\.\d+\.\d+)/, 1]
    expect(planned).not_to be_nil, "docs/ROADMAP.md no longer opens a version section this fixture can target"

    with_site_copy do |copy|
      rewrite(File.join(copy, "roadmap.html")) do |html|
        panel = %r{(<span class="v">#{Regexp.escape(planned)}</span>.*?<ul[^>]*>)}m
        raise "fixture mutation did not apply -- no panel for #{planned}" unless html.match?(panel)

        html.sub(panel, "\\1<li>an item the markdown does not plan</li>")
      end

      status, output = run_check_against(copy)

      expect(status).not_to eq(0), "a roadmap panel disagreeing with ROADMAP.md passed the site check"
      expect(output).to include("item(s)")
    end
  end
end
