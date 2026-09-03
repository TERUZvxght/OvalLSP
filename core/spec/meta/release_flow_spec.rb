# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require_relative "../../../scripts/release"

# **The release, as one command per step, each refusing when the step
# before it left no evidence.**
#
# `docs/RELEASE_CHECKLIST.md` is the order, and it was a list a person
# walked. The steps that can be checked mechanically are checked here;
# what `release.rb` must never become is a second implementation of any
# of them, so every check below is a delegation to the script or spec
# that already owns it, and this file drives the *refusals* — the part
# that is genuinely new.
#
# The actions behind those refusals are not driven: `bump` runs npm and
# bundler, `publish` execs the publishing script, `record` fetches from
# the Marketplace. What is asserted is that none of them is reached
# while its precondition is unmet.
RSpec.describe "scripts/release.rb" do
  RELEASE_FLOW_REPO = File.expand_path("../../..", __dir__)

  let(:root) { example_tmpdir("release-flow") }
  let(:prepared) { "9.9.9" }

  before do
    %w[vscode core/lib/ovallsp docs/design/tasks core/tmp].each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
    write("vscode/package.json", JSON.pretty_generate("name" => "ovallsp", "version" => "9.9.8"))
    write("core/lib/ovallsp/version.rb", "module Ovallsp\n  VERSION = \"9.9.8\"\nend\n")
    # Assembled, never spelled: `check_doc_links.rb` reads every tracked
    # file for citations, and a fixture path written the way a real one
    # is written is a dangling citation in this file (`024.126`).
    write(unspellable("docs", "design", "tasks", "058-a-release.md"),
          "# 058 - a release\n\n**Branch:** `release/9.9.8`\n")
    write("vscode/CHANGELOG.md", "# Changelog\n\n## 9.9.8 - shipped\n\n- **A thing.** It changed.\n\n### Details\n\nWhy.\n")
    write("vscode/CHANGELOG.ja.md", "# Changelog\n\n## 9.9.8 - shipped\n\n- **A thing.** It changed.\n\n### 詳細\n\nWhy.\n")
    write(register_path, "# Task 024\n\nA register with nothing open.\n")
    FileUtils.cp_r(File.join(RELEASE_FLOW_REPO, "scripts"), root)
    throwaway_repo(root, "a base")
    # `git init` uses whatever `init.defaultBranch` says, and a release
    # branches from `main` — so the fixture is on `main` whatever the
    # machine's default is.
    RepoFiles.run(root, "branch", "-M", "main", out: File::NULL, err: File::NULL)
    # A real clone has `origin/main`, and it is what "what has shipped"
    # means -- `open` compares HEAD against it rather than against a
    # branch name.
    RepoFiles.run(root, "update-ref", "refs/remotes/origin/main", "HEAD", out: File::NULL)
    stub_const("Release::ROOT", root)
  end

  # Assembled for the same reason as the task document above.
  def register_path = unspellable("docs", "design", "tasks", "024-deferred-review-findings.md")

  def write(relative, content)
    FileUtils.mkdir_p(File.join(root, File.dirname(relative)))
    File.write(File.join(root, relative), content)
  end

  def branch(name) = RepoFiles.run(root, "checkout", "-q", "-b", name, out: File::NULL, err: File::NULL)

  # `gate` refuses a dirty tree, so anything it is meant to read has to
  # be committed first — which is what the release itself does between
  # `bump` and `gate`.
  def commit_all(message = "the fixture") = commit_throwaway(root, message)

  def run(*argv) = Release.run(argv)

  describe "status" do
    it "answers about the packaged version and the branch it is on" do
      expect { run("status") }.to output(/9\.9\.8/).to_stdout
      expect(run("status")).to eq(0)
    end
  end

  describe "open" do
    it "refuses a version that is already tagged" do
      RepoFiles.run(root, "tag", "v#{prepared}", out: File::NULL)

      expect(run("open", prepared)).to eq(2)
    end

    # A release branch starts from what has shipped, which is `open`'s own
    # refusal text about the tree. It said nothing about the branch, so
    # `open` on a feature branch cut the release from that.
    #
    # **The rule is about the commit, not the name.** With no
    # `origin/main` to compare against there is one fewer way to say yes,
    # so this refuses.
    # And it refuses a branch that has *moved*, which is the case the
    # name test would miss in the other direction.
    it "refuses a branch that has commits main does not" do
      branch("feature-x")
      write("some-work.txt", "not shipped\n")
      commit_all("work that has not shipped")

      expect(run("open", prepared)).to eq(2)
      expect(RepoFiles.capture(root, %w[branch --show-current]).strip).to eq("feature-x")
    end

    # **The control**, and the reason the rule is not "the branch is
    # called main": a branch sitting on exactly what has shipped *is*
    # what has shipped, whatever it is called.
    it "allows a branch sitting exactly where origin/main is" do
      branch("feature-x")

      expect(run("open", prepared)).to eq(0)
    end

    # **And the name buys nothing.** `main` returned before any
    # comparison, so a local `main` nobody had pulled cut a release
    # missing whatever had merged — and would have published it. The rule
    # is HEAD against `origin/main`, whatever the branch is called.
    it "refuses a local main that origin/main is ahead of" do
      write("merged-elsewhere.txt", "landed while you were away\n")
      commit_all("what merged")
      RepoFiles.run(root, "update-ref", "refs/remotes/origin/main", "HEAD", out: File::NULL)
      RepoFiles.run(root, "reset", "-q", "--hard", "HEAD~1", out: File::NULL)

      expect { run("open", prepared) }.to output(/git pull/).to_stderr
    end

    # With no `origin/main` there is nothing to compare against, and that
    # is one fewer way to say yes rather than permission. It said so
    # through a raw `fatal: ambiguous argument` and named no remedy: the
    # rescue meant to catch that re-raised the refusal `git` had already
    # turned the error into.
    it "names the fetch when it cannot see origin/main, rather than the git error" do
      RepoFiles.run(root, "update-ref", "-d", "refs/remotes/origin/main", out: File::NULL)

      expect { run("open", prepared) }.to output(/git fetch origin/).to_stderr
    end

    it "refuses a tree that is not clean before it branches" do
      write("vscode/package.json", JSON.pretty_generate("name" => "ovallsp", "version" => "9.9.8", "x" => 1))

      expect(run("open", prepared)).to eq(2)
    end

    # **The control**, and the only one of `open`'s effects that can be
    # asserted here: it creates the branch and the record, and the record
    # names the branch. A release whose task document names no branch is
    # `028`, where 0.2.3 was prepared twice in parallel.
    it "creates the branch and a record that names it" do
      expect(run("open", prepared)).to eq(0)

      expect(RepoFiles.capture(root, %w[branch --show-current]).strip).to eq("release/#{prepared}")
      record = Dir.glob(File.join(root, "docs", "design", "tasks", "*#{prepared}*.md")).first
      expect(record).not_to be_nil, "no task document was written for #{prepared}"
      expect(File.read(record, encoding: "UTF-8")).to include("**Branch:** `release/#{prepared}`")
    end

    # `NNN-`, zero padded. `agents_card_spec`'s task-file pattern,
    # `docs/DOCUMENTATION_MAP.md`'s "highest-numbered NNN-*.md" and
    # `check_release_pointers.rb`'s lexical sort all rest on the width:
    # an unpadded `60-` sorts after `061-` for ever.
    it "numbers the record it writes to three digits" do
      run("open", prepared)

      record = Dir.glob(File.join(root, "docs", "design", "tasks", "*#{prepared}*.md")).first
      expect(File.basename(record)).to match(/\A\d{3}-/)
    end

    it "writes a section for the version at the top of both changelogs" do
      run("open", prepared)

      %w[vscode/CHANGELOG.md vscode/CHANGELOG.ja.md].each do |relative|
        body = File.read(File.join(root, relative), encoding: "UTF-8")
        expect(Changelog.sections(body).first.version).to eq(prepared)
      end
    end

    # `bump` runs `check_site_links.rb`, which requires a roadmap section
    # per shipped version - so a bump rewrote eight files and then refused
    # for a page `open` had never mentioned. The requirement is said when
    # the sections are, not after the edit.
    it "names the roadmap pages alongside the changelog sections" do
      expect { run("open", prepared) }.to output(/roadmap/i).to_stdout
    end
  end

  describe "bump" do
    it "refuses on a branch that is not the release's" do
      branch("something-else")

      expect(run("bump")).to eq(2)
    end

    # The version comes from the branch, so a branch naming a version
    # that is already tagged is a bump with nowhere to go.
    it "refuses when the branch names a version already tagged" do
      RepoFiles.run(root, "tag", "v#{prepared}", out: File::NULL)
      branch("release/#{prepared}")

      expect(run("bump")).to eq(2)
    end
  end

  describe "gate" do
    before { branch("release/#{prepared}") }

    it "refuses while the version files still say the version before it" do
      expect(run("gate")).to eq(2)
    end

    it "names the entries still open against the version, rather than only counting them" do
      bump_version_files
      open_entry
      commit_all

      expect { run("gate") }.to output(/#{Regexp.escape(open_entry)}/).to_stderr
    end

    it "accepts one by number, with a reason, rather than skipping the check" do
      bump_version_files
      open_entry
      commit_all
      run("gate", "--accept", open_entry, "--reason", "It is a plan, and the release does not owe it.")

      accepted = File.read(File.join(root, "core", "tmp", "release-#{prepared}.json"), encoding: "UTF-8")
      expect(JSON.parse(accepted).dig("accepted", open_entry)).to include("does not owe it")
    end

    # Asserted on what was *recorded*, not on the exit code: `gate` ends
    # in a refusal here whatever happens, because gitleaks runs last and
    # this is a throwaway tree. The mutation manifest said so.
    # **The reason has to outlive the working copy.** It was written only
    # to `core/tmp/`, which is untracked and gone with the machine, and
    # the quotable block did not mention it - so the decision "this
    # release does not owe 024.N, because ..." reached neither the record
    # nor the commit message, which are the two places anyone would look
    # for it later.
    it "writes an accepted entry's reason into the release record" do
      open_entry
      commit_all
      record = File.join(root, "docs", "design", "tasks", "060-#{prepared}-what-this-release-is-for.md")
      FileUtils.mkdir_p(File.dirname(record))
      File.write(record, "# #{prepared}\n\n## 残課題\n\n未処理の指摘はこの文書ではなく `024` に書く。\n")

      run("gate", "--accept", open_entry, "--reason", "It is a plan, and the release does not owe it.")

      expect(File.read(record, encoding: "UTF-8")).to include(open_entry)
      expect(File.read(record, encoding: "UTF-8")).to include("does not owe it")
    end

    it "lists an accepted entry in the block a commit message can quote" do
      expect(Release.quotable_block(prepared)).not_to include("024.")

      Release.remember(prepared, "accepted" => { unspellable_number(901) => "It is a plan." })

      expect(Release.quotable_block(prepared)).to include(unspellable_number(901))
    end

    it "refuses an --accept with no reason, and records nothing" do
      bump_version_files
      open_entry
      commit_all

      expect(run("gate", "--accept", open_entry)).to eq(2)
      expect(Release.state(prepared)["accepted"]).to be_nil
    end

    # The fourth of the four steps `docs/RELEASE_CHECKLIST.md` used to
    # ask a person to do by hand: grep the previous version across the
    # repository and read what still names it.
    it "lists a file still carrying the version before it" do
      bump_version_files
      published_artifacts
      write("vscode/README.md", "Install Preview 9.9.8 from the Marketplace.\n")
      commit_all

      expect { run("gate") }.to output(%r{vscode/README\.md}).to_stdout
    end

    # **It lists; it does not refuse.** "Not history" was a human
    # judgement in the manual step, and as "anywhere but four paths" it
    # is wrong on this tree: the roadmap pages must carry a section per
    # shipped version -- `check_site_links.rb`, which `bump` itself runs,
    # requires it -- so bump demanded what gate forbade. A refusal with
    # five false positives a release is the check `024.150` says gets
    # switched off. Same shape as preflight's `ci:` line: report, do not
    # gate.
    it "does not refuse the roadmap for naming the version that shipped" do
      bump_version_files
      published_artifacts
      write("site/roadmap.html", "<h2>9.9.8</h2>\n")
      commit_all

      expect { run("gate") }.to output(%r{site/roadmap\.html}).to_stdout
      expect(Release.stale_version_mentions(prepared)).to include("site/roadmap.html")
    end

    # **The control for the listing.** Without it, a scan that found
    # nothing anywhere would satisfy the example above by reporting the
    # planted file and nothing else would be evidence it can read a tree.
    it "says nothing about the places a past version belongs" do
      bump_version_files
      published_artifacts
      write(unspellable("docs", "design", "tasks", "057-an-older-release.md"), "0.0.0 and 9.9.8 are history.\n")
      commit_all

      expect(Release.stale_version_mentions(prepared))
        .not_to include(a_string_matching(%r{docs/design/tasks/}))
    end

    # **A dirty tree is refused.** `gate` fingerprints the index and ran
    # preflight over the working tree, so following `bump`'s own advice
    # -- "nothing is committed ... then: gate" -- gated one tree, had
    # `release.sh` refuse the dirty one at publish, and then had
    # `publish` refuse because committing had moved the index. Fifteen
    # minutes of preflight, twice.
    it "refuses a tree that is not clean, naming what is uncommitted" do
      bump_version_files
      published_artifacts
      write("a-new-file.txt", "uncommitted\n")

      expect { run("gate") }.to output(/a-new-file\.txt/).to_stderr
    end
  end

  describe "publish" do
    it "refuses when gate left no evidence at all" do
      branch("release/#{prepared}")
      bump_version_files

      expect { run("publish") }.to output(/has not been gated/).to_stderr
    end

    # **What was gated must be what is published.** Asserted on the
    # message rather than the exit code: `publish` refuses for a second
    # reason immediately afterwards in a throwaway tree, so the status
    # alone cannot tell which check spoke.
    it "refuses when the index moved after it was gated" do
      branch("release/#{prepared}")
      bump_version_files
      Release.remember(prepared, "gated" => "0" * 40)

      expect { run("publish") }.to output(/index has moved/).to_stderr
    end
  end

  # **What a patch may not do.** `docs/PUBLISHING.md`'s standing
  # permission is for a patch, and a patch is a release where no
  # capability row moves — so that is what the word has to mean here, or
  # the permission covers something nobody checked.
  describe "the capability rows a patch may not move" do
    before do
      write("docs/EXTENSION_CAPABILITIES.md", capability_table("PASS"))
      commit_all("capabilities")
      RepoFiles.run(root, "tag", "v9.9.8", out: File::NULL)
      branch("release/9.9.9")
    end

    def capability_table(status)
      "# Capabilities\n\n| # | What the user does | What must happen | Status |\n|---|---|---|---|\n" \
        "| B1 | Opens a file | Core answers | #{status} |\n| B2 | Waits | status reaches ready | PASS |\n"
    end

    it "reads the rows a tag carries" do
      expect(Release.capability_rows(Release.show("v9.9.8", "docs/EXTENSION_CAPABILITIES.md")))
        .to eq("B1" => "PASS", "B2" => "PASS")
    end

    it "reports a status a patch moved" do
      write("docs/EXTENSION_CAPABILITIES.md", capability_table("FAIL"))

      expect(Release.moved_capability_rows("9.9.9", "9.9.8")).to include(a_string_matching(/B1/))
    end

    it "reports a row a patch added" do
      write("docs/EXTENSION_CAPABILITIES.md", "#{capability_table('PASS')}| B3 | Something new | It happens | PASS |\n")

      expect(Release.moved_capability_rows("9.9.9", "9.9.8")).to include(a_string_matching(/B3/))
    end

    # And the gate itself, not only the comparison behind it: a patch
    # that moved a row is refused, which is what makes
    # `docs/PUBLISHING.md`'s standing permission about the thing it
    # names.
    it "refuses the bump of a patch that moved one" do
      write("docs/EXTENSION_CAPABILITIES.md", capability_table("FAIL"))
      published_artifacts

      expect { Release.refuse_unshaped_release("9.9.9") }.to raise_error(Release::Refused, /B1/)
    end

    # A clone without the previous tag cannot answer the question, and
    # saying nothing would be the answer a working comparison gives when
    # the table did not move. It refuses, and names the fetch.
    it "refuses when the tag it would compare against is not in this clone" do
      RepoFiles.run(root, "tag", "-d", "v9.9.8", out: File::NULL, err: File::NULL)

      expect { Release.moved_capability_rows("9.9.9", "9.9.8") }
        .to raise_error(Release::Refused, /fetch --tags/)
    end

    # **The control.** Every example above asserts something is
    # reported, and a comparison that reported every row would satisfy
    # all of them.
    it "says nothing when the table did not move" do
      expect(Release.moved_capability_rows("9.9.9", "9.9.8")).to be_empty
    end
  end

  describe "record" do
    it "refuses when no artifact for the version has been built" do
      branch("release/#{prepared}")
      bump_version_files

      expect(run("record")).to eq(2)
    end

    # **The hash is compared before the tag exists.** It tagged and wrote
    # the row first, so a mismatch between what was built and what the
    # Marketplace serves was discovered after the release had been
    # recorded as good.
    it "refuses when what was served does not match what was built" do
      branch("release/#{prepared}")
      bump_version_files
      build_a_vsix

      expect(run("record", "--served", "b" * 64)).to eq(2)
      expect(RepoFiles.capture(root, %w[tag --list]).strip).to eq("")
    end

    it "records the row and tags when the two agree" do
      branch("release/#{prepared}")
      bump_version_files
      digest = build_a_vsix
      write("docs/RELEASE_ARTIFACTS.md",
            "# Artifacts\n\n## Published\n\n| Version | SHA-256 | Channel |\n|---|---|---|\n")

      expect(run("record", "--served", digest)).to eq(0)
      expect(File.read(File.join(root, "docs", "RELEASE_ARTIFACTS.md"), encoding: "UTF-8")).to include(digest)
      expect(RepoFiles.capture(root, %w[tag --list]).strip).to eq("v#{prepared}")
    end
  end

  def build_a_vsix
    path = File.join(root, "vscode", "ovallsp-#{prepared}.vsix")
    File.write(path, "not really a zip, but it hashes\n")
    Digest::SHA256.file(path).hexdigest
  end

  # An entry targeting the version being prepared, written through the
  # register's own reader so this cannot disagree with it about what
  # "open" means.
  def open_entry
    @open_entry ||= begin
      number = ["024", "901"].join(".")
      write(register_path,
            "# Task 024\n\n## #{number} A synthetic entry\n\n" \
            "```yaml\nstatus: open\nkind: roadmap\ntarget: #{prepared}\n```\n\n" \
            "**Area:** `scripts/release.rb`\n\nWhat it says.\n\n---\n\n\n")
      number
    end
  end

  # The published table `release.rb` reads to learn which version came
  # before this one — through `DeferredFindings.published_versions`,
  # which is what every other reader of that table uses.
  def published_artifacts
    write("docs/RELEASE_ARTIFACTS.md",
          "# Artifacts\n\n## Published\n\n| Version | SHA-256 | Channel |\n|---|---|---|\n" \
          "| 9.9.8 | `#{'a' * 64}` | Pre-Release |\n")
  end

  def bump_version_files
    write("vscode/package.json", JSON.pretty_generate("name" => "ovallsp", "version" => prepared))
    write("core/lib/ovallsp/version.rb", "module Ovallsp\n  VERSION = \"#{prepared}\"\nend\n")
  end
end
