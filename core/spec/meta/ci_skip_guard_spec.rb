# frozen_string_literal: true

require "yaml"

# 024.16's whole deliverable is one step in `.github/workflows/ci.yml`:
# both suites that skip themselves when rails/sqlite3 are unresolvable
# must be checked, not just the integration one. Nothing in this
# repository noticed that the capability row was missing for as long as it
# was missing, and nothing would notice it being deleted again -- CI stays
# green either way, which is exactly the failure mode the guard exists to
# close. So the guard needs a guard, the way `versionPairing.test.ts` and
# `clientPresentation.test.ts` assert on source they cannot execute.
#
# The steps are located in *parsed* YAML, not by slicing the file's text:
# merge round 6 of 0.2.3's loop showed that a text slice stays green when
# the step is commented out -- the workflow stops running it while the
# file still contains every asserted string. Parsed structure is what
# GitHub Actions executes; the run-text assertions then pin what the
# located step does.
RSpec.describe "the CI guard against a silently skipped suite" do
  def read_utf8(path)
    # The Japanese capability document is not ASCII, and this suite runs
    # under whatever locale the machine has -- `File.read` alone raises
    # `invalid byte sequence in US-ASCII` on a CI runner with none set,
    # which is the same trap the workflow's own guard names.
    File.read(path, encoding: "UTF-8")
  end

  let(:workflow_text) do
    read_utf8(File.expand_path("../../../.github/workflows/ci.yml", __dir__))
  end

  let(:core_steps) do
    YAML.safe_load(workflow_text).fetch("jobs").fetch("core").fetch("steps")
  end

  let(:guard_step) do
    core_steps.find { |step| step["name"] == "Fail if the real-Rails or capability suites were skipped instead of run" }
  end

  # The guard step's own run text. Both spec paths are also named in the
  # install step's comment, so asking whether the *file* mentions a path
  # passes with the path deleted from the table the guard iterates --
  # which is 024.16's gap, reopened.
  let(:guard) { guard_step&.fetch("run") }

  # `024.148`. The logic used to be forty lines of Ruby inline in this
  # step; it is `scripts/check_suites_ran.rb` now, because `preflight.rb`
  # needed the same rule and -- unable to call it -- wrote a weaker one
  # that could not fail. So these examples now assert two links: the step
  # runs the script, and the script still carries each guarantee.
  let(:checker) do
    File.read(File.expand_path("../../../scripts/check_suites_ran.rb", __dir__), encoding: "UTF-8")
  end

  it "still runs in the core job at all" do
    expect(guard_step).not_to be_nil,
                              "the real-Rails/capability skip guard is no longer an executed step of the core job"
  end

  # Both paths, and both must be the *real* spec files -- a typo'd path
  # yields zero examples, which the guard's own "contributed zero
  # examples" branch turns into a failure rather than a silent pass.
  it "runs the shared checker rather than a copy of its logic" do
    expect(guard).to include("scripts/check_suites_ran.rb"),
                     "the step no longer runs the shared checker -- a second copy of this rule is how " \
                     "024.148 happened"
  end

  # All three, and each must be a *real* spec file -- a typo'd path
  # yields zero examples, which the checker's own "contributed zero
  # examples" branch turns into a failure rather than a silent pass.
  it "checks every suite that can skip itself for want of an environment" do
    %w[
      spec/integration/real_rails_spec.rb
      spec/e2e/capabilities_spec.rb
      spec/meta/client_behaviour_spec.rb
    ].each do |path|
      expect(File).to exist(File.expand_path("../../#{path}", __dir__))
      expect(checker).to include(path)
    end
  end

  it "fails the build on a skip rather than only reporting it" do
    expect(checker).to include("exit 1")
    expect(checker).to include('ex.fetch("status") == "pending"')
  end

  # A path that stops matching any example -- a typo, a renamed spec file
  # -- is the failure the example above cites as its reason for checking
  # the paths, so leaving it unasserted would pin the reason and not the
  # mechanism.
  it "treats a suite that contributed nothing as a failure" do
    expect(checker).to include("contributed zero examples")
  end

  # docs/EXTENSION_CAPABILITIES.md tells authors to mark a row that cannot
  # pass yet as `NOT YET`, and capability_coverage_spec.rb accepts that
  # status. A guard that failed on every pending example would make the
  # documented state unexpressible, so the exemption is part of the
  # contract between the two, not an oversight.
  it "leaves the documented NOT YET status expressible" do
    expect(checker).to include("ALLOWED_PENDING")
    expect(checker).to include('"NOT YET"')
  end

  # The exemption is an authoring rule -- a pending row has to *say* `NOT
  # YET` -- and a rule enforced by CI but recorded only in a YAML comment
  # is one an author meets as a red build with no way to find out why.
  # Both languages, because the JA document is not generated from the EN
  # one.
  it "is documented in the capability document that defines the status" do
    %w[docs/EXTENSION_CAPABILITIES.md docs/EXTENSION_CAPABILITIES.ja.md].each do |doc|
      text = read_utf8(File.expand_path("../../../#{doc}", __dir__))

      # Not merely that `NOT YET` appears -- it is the status's own name
      # and appears in both documents already. The authoring rule is that
      # a *pending* row's message must carry it, and that sentence is
      # what has to survive.
      expect(text).to include("`pending`/`skip`")
      expect(text).to include(".github/workflows/ci.yml")
    end
  end

  # The exemption must not swallow the skip the guard is about: neither
  # suite's environment-skip message may contain the escape hatch.
  it "does not exempt the environment skip it exists to catch" do
    %w[spec/integration/real_rails_spec.rb spec/e2e/capabilities_spec.rb].each do |path|
      source = read_utf8(File.expand_path("../../#{path}", __dir__))
      skip_messages = source.scan(/^\s*skip\s+"([^"]+)"/).flatten

      expect(skip_messages).not_to be_empty
      expect(skip_messages.grep(/NOT YET/)).to be_empty
    end
  end

  # The two guards 0.2.3 imported are CI-only text too, and deleting
  # either -- the documented-count step whole, the `core-ruby-4` job
  # whole -- left every check in the repository green while the published
  # sentences resting on them stayed put: `SUPPORT_MATRIX`'s 4.0 row and
  # both READMEs cite the job as what runs now, and the changelog says the
  # count check "actually runs now". Same defect class as above, same fix
  # shape: pin the structure GitHub executes, then what the step runs.
  describe "the CI-only guards the published documents cite" do
    it "fails a full run whose documented-count checks skipped" do
      dc_step = core_steps.find { |step| step["name"] == "Fail if a documented-count check skipped" }

      expect(dc_step).not_to be_nil,
                             "the documented-count guard is no longer an executed step of the core job"

      run = dc_step.fetch("run")
      expect(run).to include("documented_counts_spec.rb")
      expect(run).to include('ex.fetch("status") == "pending"')
      expect(run).to include("exit 1")

      # It reads tmp/rspec.json, which the full-suite step writes -- so
      # it must come after that step, in the same job, or it reads a
      # stale file (or none) and the guard guards nothing.
      suite_index = core_steps.index { |step| step["name"] == "Run full test suite" }
      expect(suite_index).not_to be_nil, "the full-suite step is no longer an executed step of the core job"
      expect(core_steps.index(dc_step)).to be > suite_index
    end

    it "keeps the 4.0 job reporting its example count, and failing when nothing ran" do
      job = YAML.safe_load(workflow_text).fetch("jobs")["core-ruby-4"]

      expect(job).not_to be_nil, "the core-ruby-4 job is no longer in ci.yml"
      # Non-gating is the recorded decision -- a 4.0-specific failure is
      # recorded, not fixed, in the 0.2.x line -- and the count is what
      # the documents cite. Both halves pinned.
      expect(job.fetch("continue-on-error")).to be(true)

      run_lines = job.fetch("steps").filter_map { |step| step["run"] }
      expect(run_lines).to include(a_string_including("bundle exec rspec"))

      count_step = job.fetch("steps").find { |step| step["run"]&.include?("example_count") }
      expect(count_step).not_to be_nil, "the 4.0 job no longer reports its example count"
      expect(count_step.fetch("run")).to include("count.zero?")
      expect(count_step.fetch("run")).to include("exit 1")

      # The external review of the release PR: without an `if`, GitHub
      # applies the default `success()` and skips this step exactly when
      # the count matters most -- a red 4.0 suite, or RSpec dying before
      # it wrote the JSON -- so "passed" and "never started" stop being
      # distinguishable by count. The step must run on failure too, and
      # say so when the JSON is missing.
      expect(count_step["if"].to_s).to include("!cancelled()")
      expect(count_step.fetch("run")).to include("File.exist?")
    end
  end

  # 0.2.3 committed a home directory path into a task document *and* a
  # commit message. The tree half is caught by
  # `home_path_guard_spec.rb`, which runs everywhere; the message half
  # has nowhere to run but CI, because the Core jobs check out shallow
  # and a shallow scan would call the whole history clean. So it lives in
  # the one job that already fetches full history -- and, being CI-only
  # text, it is the same class as everything above: deleting the step
  # leaves every check green while the disclosure path reopens.
  describe "the commit-message half of the home-path guard" do
    let(:secret_scan_job) do
      YAML.safe_load(workflow_text).fetch("jobs").fetch("secret-scan")
    end

    it "still runs the message scan as an executed step" do
      step = secret_scan_job.fetch("steps").find { |s| s["run"]&.include?("check_home_paths.rb") }

      expect(step).not_to be_nil,
                          "the commit-message home-path scan is no longer an executed step of secret-scan"
      expect(step.fetch("run")).to include("--messages")
    end

    it "keeps the full history the scan refuses to run without" do
      checkout = secret_scan_job.fetch("steps").find { |s| s["uses"].to_s.start_with?("actions/checkout") }

      expect(checkout).not_to be_nil, "secret-scan no longer checks the repository out"
      expect(checkout.fetch("with").fetch("fetch-depth")).to eq(0)
    end

    it "has a Ruby to run it with" do
      uses = secret_scan_job.fetch("steps").filter_map { |s| s["uses"] }

      expect(uses).to include(a_string_including("ruby/setup-ruby"))
    end
  end
end
