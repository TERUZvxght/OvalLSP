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
      throwaway_repo(root)
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
      throwaway_repo(root)

      out = IO.popen(["bash", File.join(root, "vscode", "scripts", "release.sh")],
                     err: %i[child out], &:read)

      expect(out).not_to include("uncommitted changes"),
                         "a clean tree was refused as dirty:\n#{out}"
    end
  end

  # Anchored on the condition that decides, not on the line that asks
  # git. `024.158`: the exit status is captured before the branch now, so
  # a window opened at the first `diff --quiet` would start at the check
  # *above* this one and pin that check's `exit 1` instead -- the window
  # defect this file's own helper comment describes, arriving through a
  # change to the script rather than to the matcher.
  it "refuses to publish from a tree with uncommitted changes, from inside that check" do
    block = block_containing(/TREE_STATUS" -ne 0/)

    expect(block).not_to be_nil, "the clean-tree check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  # The other branch, and the second half of `024.158`. `git diff
  # --quiet` answers 0 clean, 1 dirty, and **more than 1 for "I cannot
  # tell you"** -- not a repository, an unreadable index, a broken object
  # store. The `if ! git ...` form collapsed the third into the second,
  # so a tree git could not read was announced to the user as a tree with
  # uncommitted changes: a failure to *ask* turned into an assertion
  # about their tree, which is docs/CODE_DISCIPLINE.md's swallowed-failure rule
  # arriving from the other side. Refusing is still right; saying the
  # wrong reason is not.
  it "refuses on a tree git could not read, and says that is what happened" do
    block = block_containing(/TREE_STATUS" -gt 1/)

    expect(block).not_to be_nil,
                         "release.sh no longer tells 'git says dirty' from 'git could not answer'"
    expect(block).to include("cannot read the tracked tree")
    expect(block).to include("exit 1")
  end

  it "refuses to publish a token readable beyond its owner, from inside that check" do
    block = block_containing(/8#077/)

    expect(block).not_to be_nil, "the PAT-mode check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  it "refuses to publish an artifact carrying this machine's paths, from inside that check" do
    block = block_containing(/grep -rlF .*INSPECT_PATTERN.*INSPECT_ROOT/)

    expect(block).not_to be_nil, "the packaged-artifact path check is gone, or is no longer an if block"
    expect(block).to include("exit 1")
  end

  # **The clean-tree refusal is about *this* repository.**
  #
  # `024.157`: git's location variables override the working directory
  # and `-C` does not, so an inherited `GIT_DIR` points the `git diff
  # --quiet` below at whatever repository that variable names. The
  # refusal would then be about someone else's tree, and a dirty one
  # could publish a VSIX whose baked-in commit SHA names content that
  # does not exist -- which is exactly what that refusal exists to stop.
  #
  # Text, because nothing in the suite executes this script's opening,
  # and paired with the variables rather than with the word `unset`, so
  # dropping one from the list is what fails.
  it "unsets the variables that would aim its git commands at another repository" do
    scrub = code[/^unset .*(?:\n\s+.*)*/]

    expect(scrub).not_to be_nil, "release.sh no longer scrubs git's location variables (024.157)"
    %w[GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY
       GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE].each do |name|
      expect(scrub).to include(name), "#{name} is not unset, so it can still redirect git"
    end
    expect(code.index("unset")).to be < code.index("git -C"),
                                   "the scrub runs after a git command, which is too late"
  end

  # **One exclusion set, and no invocation may add to it.**
  #
  # The inspection, the count it prints and the control that proves the
  # search works are three greps that have to agree about what they skip.
  # Written out three times they did not have to: widening the exclusions
  # on the inspection grep alone left the count healthy and the control
  # green, and the artifact shipped with the leak. Measured against a
  # 151-file fake artifact holding exactly one. `024.198`.
  #
  # A text assertion, deliberately, and about *internal agreement* rather
  # than about a value: what it forbids is a second place where the
  # answer could differ. The runtime half -- that the set is not widened
  # everywhere at once -- is the control inside the script, which fails
  # when a planted match goes unfound.
  it "gives every path-inspection grep the same exclusion set, from one list" do
    invocations = code.lines.select { |line| line.match?(%r{/usr/bin/grep -r[lL]F}) }
    inspection = invocations.reject { |line| line.include?("--include=") }

    expect(inspection.length).to be >= 3,
                                 "expected the inspection, its count and its control; found " \
                                 "#{inspection.length}:\n#{inspection.join}"

    inspection.each do |line|
      expect(line).to include('"${INSPECT_EXCLUDE[@]}"'),
                      "this grep does not read the shared exclusion list:\n#{line}"
      expect(line).not_to match(/--exclude/),
                          "this grep adds an exclusion of its own, so the three can disagree " \
                          "about what was skipped -- which is 024.198:\n#{line}"
    end
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

      # `024.158`. This used to assert `status.success? == false` plus the
      # message, and neither is tied to *this* check. Demote the refusal
      # to a warning and the message is still printed, while the non-zero
      # status arrives from the clean-tree check further down -- which,
      # against this fixture's non-repository tmpdir, exits 128. So the
      # example passed on a release.sh that only warns about a
      # world-readable publish token.
      #
      # Reaching any later check at all is the regression, so that is
      # what is asserted: exactly 1, and nothing the clean-tree check
      # says. Both of its branches name the tracked tree, so one string
      # covers "has uncommitted changes" and "cannot read".
      expect(status.exitstatus).to eq(1),
                                   "release.sh did not refuse at the PAT check " \
                                   "(exit #{status.exitstatus}):\n#{output}"
      expect(output).to include("readable beyond its owner")
      expect(output).not_to include("tracked tree"),
                            "the run continued past the PAT refusal into a later check:\n#{output}"
    end
  end

  # By absolute path, never the shell's `grep`: where the name resolves
  # to a ugrep wrapper it skips binary files without -a and clears an
  # artifact it never read. `if ! grep` was missed by the first version
  # of this matcher, which anchored on an optional `if` and no negation.
  #
  # `024.199`, two holes in one example. (a) The pin was `include` over
  # the whole file, and the *advisory* grep -- the one whose output goes
  # to /dev/null and whose only effect is printing a note -- satisfies it
  # on its own, so the refusal's grep need not have been absolute at all.
  # It is asserted inside that refusal's own block now. (b) The scan
  # required `grep` at a line start with no leading whitespace, or
  # straight after `| & ; ( if !`, so any *indented* bare `grep` escaped
  # -- and almost every grep inside an `if` or a function body is
  # indented. Position is not the property; being a bare word is. The
  # lookbehind excludes a path (`/usr/bin/grep`) and a longer word
  # (`ugrep`), and nothing else -- including a `grep` written on a
  # continuation line, after `; then`, or inside backticks.
  it "calls the grep it means, not whatever the shell resolves" do
    # The needle is the *call*, not its flags. It was
    # `grep -rlF --exclude`, and the change that moved those flags into an
    # `INSPECT_EXCLUDE` array — in the same patch as this example — left
    # the needle matching nothing, so the guard reported the check gone.
    # It found a real inconsistency in its own change set, which is what
    # it is for; a needle that a refactor of the thing it guards can
    # invalidate is a needle that goes quiet exactly when it should not.
    hard_failure = block_containing(/grep -rlF/)

    expect(hard_failure).not_to be_nil,
                                "the packaged-artifact path check is gone, or is no longer an if block"
    expect(hard_failure).to include("/usr/bin/grep -rlF")
    expect(code.scan(%r{(?<![/\w.-])grep\s})).to be_empty
  end

  # `024.200`. Everything above this line is either a text match or one
  # of three executed examples that exit at the PAT or clean-tree check,
  # so bash's parser never reaches the rest of the file: an unterminated
  # `if` introduced past the clean-tree block leaves the only publish
  # path unrunnable with every example green, and is discovered by the
  # person attempting the release, at the moment they attempt it.
  #
  # `verify-installed-extension.sh` had no spec at all and the same
  # exposure, so both shell scripts beside it are parsed rather than only
  # this one. `include(SCRIPT)` is there because an empty glob would make
  # the loop assert nothing.
  it "parses, and so does every shell script beside it" do
    scripts = Dir.glob(File.join(File.dirname(SCRIPT), "*.sh")).sort

    expect(scripts).to include(SCRIPT)
    scripts.each do |path|
      complaint = IO.popen(["bash", "-n", path], err: %i[child out], &:read)

      expect($?).to be_success, "#{path} does not parse:\n#{complaint}"
    end
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
