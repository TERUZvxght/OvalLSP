# frozen_string_literal: true

# `vscode/scripts/release.sh` is the last point at which the artifact a
# user installs exists on disk, and two of its checks exist only there.
# Nothing executes this script in the suite, so deleting either step
# leaves every check in the repository green while the guarantee goes --
# the same class `ci_skip_guard_spec.rb` was written for, and the reason
# it gives applies verbatim.
#
# Asserted against the script's text because it is a shell script; the
# `.vsce-pat.local` and `$HOME` steps are both `if` blocks whose absence
# is what matters, and a commented-out block would still contain the
# strings -- so each assertion pairs the string with the `exit 1` that
# makes it a refusal rather than a mention.
RSpec.describe "the release script's own guards" do
  SCRIPT = File.expand_path("../../../vscode/scripts/release.sh", __dir__)

  let(:source) { File.read(SCRIPT, encoding: "UTF-8") }

  # Comments in this file and in the script discuss these checks by name,
  # so prose is stripped before the source is searched.
  let(:code) { source.lines.reject { |line| line.strip.start_with?("#") }.join }

  it "refuses to publish a token readable beyond its owner" do
    expect(code).to include("PAT_MODE")
    expect(code).to match(/8#077.*\n(.*\n)*?.*exit 1/)
  end

  it "inspects the packaged artifact for this machine's own paths, and refuses on a hit" do
    expect(code).to include("--exclude='*.bundle'")
    expect(code).to match(/grep -rlF --exclude.*"\$HOME".*\n(.*\n)*?.*exit 1/)
  end

  # By absolute path, never bare `grep`: where the name resolves to a
  # ugrep wrapper it skips binary files without -a and clears an artifact
  # it never read. 0.2.3 filed and withdrew a register entry over exactly
  # that, which is why this is pinned rather than left to habit.
  it "calls the grep it means, not whatever the shell resolves" do
    expect(code).to include("/usr/bin/grep -rlF")
    expect(code.scan(/^\s*(?:if\s+)?grep\s/)).to be_empty
  end

  it "still verifies the payload hash and runs the semantic smoke" do
    expect(code).to include("verify-packaged-payload-hash.js")
    expect(code).to include("vsix_semantic_smoke.rb")
  end
end
