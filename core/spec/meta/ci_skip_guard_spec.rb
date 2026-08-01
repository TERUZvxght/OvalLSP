# frozen_string_literal: true

# 024.16's whole deliverable is one step in `.github/workflows/ci.yml`:
# both suites that skip themselves when rails/sqlite3 are unresolvable
# must be checked, not just the integration one. Nothing in this
# repository noticed that the capability row was missing for as long as it
# was missing, and nothing would notice it being deleted again -- CI stays
# green either way, which is exactly the failure mode the guard exists to
# close. So the guard needs a guard, the way `versionPairing.test.ts` and
# `clientPresentation.test.ts` assert on source they cannot execute.
#
# Asserting on the workflow's text rather than running it: a GitHub
# Actions job is not executable from here, and the decision worth pinning
# is which suites are named, which is text.
RSpec.describe "the CI guard against a silently skipped suite" do
  let(:workflow) { read_utf8(File.expand_path("../../../.github/workflows/ci.yml", __dir__)) }

  # The Japanese capability document is not ASCII, and this suite runs
  # under whatever locale the machine has -- `File.read` alone raises
  # `invalid byte sequence in US-ASCII` on a CI runner with none set,
  # which is the same trap the workflow's own guard names.
  def read_utf8(path)
    File.read(path, encoding: "UTF-8")
  end

  # Both paths, and both must be the *real* spec files -- a typo'd path
  # yields zero examples, which the guard's own "contributed zero
  # examples" branch turns into a failure rather than a silent pass.
  it "checks both suites that can skip themselves for want of an environment" do
    %w[spec/integration/real_rails_spec.rb spec/e2e/capabilities_spec.rb].each do |path|
      expect(File).to exist(File.expand_path("../../#{path}", __dir__))
      expect(workflow).to include(path)
    end
  end

  it "fails the build on a skip rather than only reporting it" do
    guard = workflow[/Fail if the real-Rails or capability suites were skipped.*?(?=\n  \w)/m]

    # The *skip* branch's own `exit 1`, sliced out: the guard has a
    # second one for the zero-examples branch, so asking whether the step
    # contains the string anywhere passes with the skip branch reduced to
    # a warning -- which is the whole failure being guarded against.
    skip_branch = guard[/unless skipped\.empty\?.*?\n              end/m]

    expect(skip_branch).to include("exit 1")
    expect(guard).to include('ex.fetch("status") != "pending"')

    # And the other branch, on its own terms. A path that stops matching
    # any example -- a typo, a renamed spec file -- is the failure the
    # example above cites as its reason for checking the paths, so
    # leaving its `exit 1` unasserted would pin the reason and not the
    # mechanism.
    empty_branch = guard[/if examples\.empty\?.*?\n              end/m]

    expect(empty_branch).to include("exit 1")
  end

  # docs/EXTENSION_CAPABILITIES.md tells authors to mark a row that cannot
  # pass yet as `NOT YET`, and capability_coverage_spec.rb accepts that
  # status. A guard that failed on every pending example would make the
  # documented state unexpressible, so the exemption is part of the
  # contract between the two, not an oversight.
  it "leaves the documented NOT YET status expressible" do
    expect(workflow).to include('pending_message").to_s.include?("NOT YET")')
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
end
