# frozen_string_literal: true

require "English"
require "shellwords"
require "tmpdir"
require "fileutils"

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
  let(:code) { source.lines.reject { |line| line.strip.start_with?("#") }.join }

  # The `if ... fi` block a matcher appears in, so an assertion about a
  # refusal is about *that* refusal. The first version of this spec used
  # `(.*\n)*?.*exit 1` across the whole file, which any of the eight
  # later `exit 1`s satisfied -- an attack round disabled five different
  # refusals with all four examples still green, and the only mutation it
  # caught was commenting the whole block out. A window is the difference
  # between pinning a block and pinning the file's vocabulary.
  def block_containing(pattern)
    lines = code.lines
    start = lines.index { |line| line.match?(pattern) }
    return nil unless start

    opener = lines[0..start].rindex { |line| line.match?(/^\s*if\s/) }
    finish = (start...lines.length).find { |i| lines[i].match?(/^\s*fi\s*$/) }
    return nil unless opener && finish

    lines[opener..finish].join
  end

  # `copy-core.js` bakes `buildCommit: currentGitCommit()` into the
  # packaged Core, so a VSIX built from a dirty tree names a commit whose
  # content it does not match -- and that SHA is what an installed
  # extension reports, and what a Marketplace artifact is verified
  # against after the fact.
  #
  # `RELEASE_CHECKLIST`'s gate #1 said this was enforced by
  # `make-final-review-bundle.sh`, which nothing invoked. 046 deleted
  # that script and moved the gate here, to the one path that actually
  # publishes.
  # `RELEASE_CHECKLIST` gates 8 and 11 both cite
  # `scripts/verify_sbom_against_vsix.rb` as their evidence, and until
  # 0.2.14 nothing ran it -- `046` line 94 says so in the same release
  # that cited it. Round 1 found that C6 reported it wired anyway,
  # because the script's own usage string names it in a non-comment line.
  #
  # Wired here rather than marked unwired: the check needs an unpacked
  # VSIX, `release.sh` already has one on disk for the semantic smoke,
  # and a gate that can run is worth more than a gate that is honestly
  # labelled as not running.
  it "verifies the SBOM against the packaged artifact before publishing" do
    expect(code).to include("verify_sbom_against_vsix.rb")
    expect(code).to match(/verify_sbom_against_vsix\.rb.*UNPACK_DIR/m)
  end

  # **Executed, not matched.** Round 3 deleted the whole refusal and
  # replaced it with an unrelated `if` block carrying `# diff --quiet` as
  # a trailing comment; all eight examples stayed green. The mutation the
  # commit message cited -- replacing the condition with `if false` -- is
  # caught, but it is the one a text match cannot miss. The cheaper
  # deletion is the one that matters, and only running the script sees
  # it.
  #
  # Safe to run: the refusal sits above `npm ci` and everything that
  # follows, so the script exits 1 having done nothing but read git.
  # The scratch tree is a throwaway repository with a copy of the script,
  # a fake PAT at mode 600, and one modified tracked file.
  it "actually refuses, when run against a tree with uncommitted changes" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "vscode", "scripts"))
      FileUtils.cp(SCRIPT, File.join(root, "vscode", "scripts", "release.sh"))
      File.chmod(0o755, File.join(root, "vscode", "scripts", "release.sh"))

      pat = File.join(root, "vscode", ".vsce-pat.local")
      File.write(pat, "not-a-real-token")
      File.chmod(0o600, pat)

      File.write(File.join(root, "tracked.txt"), "one\n")
      system("git", "init", "-q", root, out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)
      File.write(File.join(root, "tracked.txt"), "two\n")

      out = IO.popen(["bash", File.join(root, "vscode", "scripts", "release.sh")],
                     err: %i[child out], &:read)

      expect($?).not_to be_success, "release.sh did not refuse a dirty tree:\n#{out}"
      expect(out).to include("uncommitted changes")
      expect(out).to include("buildCommit")
    end
  end

  # The other half: the same scratch tree, committed clean, must get
  # *past* this refusal. Without it the example above would pass on a
  # script that refuses everything.
  it "does not refuse a clean tree at that check" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "vscode", "scripts"))
      FileUtils.cp(SCRIPT, File.join(root, "vscode", "scripts", "release.sh"))
      pat = File.join(root, "vscode", ".vsce-pat.local")
      File.write(pat, "not-a-real-token")
      File.chmod(0o600, pat)
      File.write(File.join(root, "tracked.txt"), "one\n")
      system("git", "init", "-q", root, out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)

      out = IO.popen(["bash", File.join(root, "vscode", "scripts", "release.sh")],
                     err: %i[child out], &:read)

      expect(out).not_to include("uncommitted changes"),
                         "a clean tree was refused as dirty:\n#{out}"
    end
  end

  it "refuses to publish from a tree with uncommitted changes, from inside that check" do
    block = block_containing(/diff --quiet/)

    expect(block).not_to be_nil, "the clean-tree check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  it "refuses to publish a token readable beyond its owner, from inside that check" do
    block = block_containing(/8#077/)

    expect(block).not_to be_nil, "the PAT-mode check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  it "refuses to publish an artifact carrying this machine's paths, from inside that check" do
    block = block_containing(/grep -rlF --exclude/)

    expect(block).not_to be_nil, "the packaged-artifact path check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  # Semantic mutations -- negating a condition, pointing a check at an
  # empty directory -- are invisible to any text match, so the PAT
  # refusal is *executed* rather than read. It is the one refusal that
  # can be triggered without building anything, because it runs before
  # `npm ci`.
  it "actually refuses, when run against a token file readable by others" do
    Dir.mktmpdir do |dir|
      # The script derives the PAT path from its own location
      # (<script>/../.vsce-pat.local), so the fixture reproduces that
      # layout. The first attempt put them side by side; the script
      # refused for the wrong reason, which the message assertion caught
      # and an exit-status-only assertion would have called a pass.
      scripts = File.join(dir, "scripts")
      FileUtils.mkdir_p(scripts)
      pat = File.join(dir, ".vsce-pat.local")
      File.write(pat, "not-a-real-token")
      File.chmod(0o644, pat)
      skip "this filesystem does not keep the mode" unless (File.stat(pat).mode & 0o077) != 0

      script = File.join(scripts, "release.sh")
      File.write(script, File.read(SCRIPT, encoding: "UTF-8"))
      File.chmod(0o755, script)

      output = `#{script.shellescape} 2>&1`
      status = $CHILD_STATUS

      expect(status.success?).to be(false), "release.sh continued past a world-readable token file"
      expect(output).to include("readable beyond its owner")
    end
  end

  # By absolute path, never the shell's `grep`: where the name resolves
  # to a ugrep wrapper it skips binary files without -a and clears an
  # artifact it never read. `if ! grep` was missed by the first version
  # of this matcher, which anchored on an optional `if` and no negation.
  it "calls the grep it means, not whatever the shell resolves" do
    expect(code).to include("/usr/bin/grep -rlF")
    expect(code.scan(/(?:^|[|&;(]\s*|\bif\s+|!\s*)grep\s/)).to be_empty
  end

  # What this file cannot do, said plainly rather than left to be
  # discovered again. A text match cannot see a *semantic* mutation --
  # negating a condition, or pointing a check at a directory that does
  # not exist -- and an attack round demonstrated both against the
  # previous version. The PAT refusal is executed above, which closes it
  # there; the artifact check needs a built VSIX and cannot be run from a
  # unit spec, so it reports how many files it inspected instead and
  # refuses on an implausible count. That converts "aimed at nothing"
  # from silent into visible.
  it "makes the artifact check say what it inspected, and refuse an implausible count" do
    # Both halves. The refusal was pinned and **the reporting was not**:
    # the first line here computed a window and never read it, so
    # deleting release.sh's `echo "PASS: ... (${INSPECTED} files
    # inspected)"` left this file at 8 examples, 0 failures. That echo is
    # the countermeasure's visible half -- the thing that turns "aimed at
    # nothing" from silent into seen -- and it was the half no example
    # touched. Round 1 found it by deleting the line.
    expect(code).to include("INSPECTED=")
    expect(code).to match(/echo[^\n]*files inspected/)
    expect(block_containing(/INSPECTED\" -lt/)).to include("exit 1")
  end

  it "still verifies the payload hash and runs the semantic smoke" do
    expect(code).to include("verify-packaged-payload-hash.js")
    expect(code).to include("vsix_semantic_smoke.rb")
  end
end
