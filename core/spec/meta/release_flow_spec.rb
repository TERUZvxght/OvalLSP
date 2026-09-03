# frozen_string_literal: true

require "fileutils"
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
    stub_const("Release::ROOT", root)
  end

  # Assembled for the same reason as the task document above.
  def register_path = unspellable("docs", "design", "tasks", "024-deferred-review-findings.md")

  def write(relative, content)
    FileUtils.mkdir_p(File.join(root, File.dirname(relative)))
    File.write(File.join(root, relative), content)
  end

  def branch(name) = RepoFiles.run(root, "checkout", "-q", "-b", name, out: File::NULL, err: File::NULL)

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

    it "refuses a tree that is not clean" do
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

    it "writes a section for the version at the top of both changelogs" do
      run("open", prepared)

      %w[vscode/CHANGELOG.md vscode/CHANGELOG.ja.md].each do |relative|
        body = File.read(File.join(root, relative), encoding: "UTF-8")
        expect(Changelog.sections(body).first.version).to eq(prepared)
      end
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

      expect { run("gate") }.to output(/#{Regexp.escape(open_entry)}/).to_stderr
    end

    it "accepts one by number, with a reason, rather than skipping the check" do
      bump_version_files
      run("gate", "--accept", open_entry, "--reason", "It is a plan, and the release does not owe it.")

      accepted = File.read(File.join(root, "core", "tmp", "release-#{prepared}.json"), encoding: "UTF-8")
      expect(JSON.parse(accepted).dig("accepted", open_entry)).to include("does not owe it")
    end

    # Asserted on what was *recorded*, not on the exit code: `gate` ends
    # in a refusal here whatever happens, because gitleaks runs last and
    # this is a throwaway tree. The mutation manifest said so.
    it "refuses an --accept with no reason, and records nothing" do
      bump_version_files

      expect(run("gate", "--accept", open_entry)).to eq(2)
      expect(Release.state(prepared)["accepted"]).to be_nil
    end

    # The fourth of the four steps `docs/RELEASE_CHECKLIST.md` used to
    # ask a person to do by hand: grep the previous version across the
    # repository and fix anything still naming it that is not history.
    it "names a file still carrying the version before it" do
      bump_version_files
      published_artifacts
      write("vscode/README.md", "Install Preview 9.9.8 from the Marketplace.\n")

      expect { run("gate") }.to output(%r{vscode/README\.md}).to_stderr
    end

    # **The control**, and it is the half that decides whether the check
    # is worth having: a release's own record, its artifact table and the
    # changelogs name every version this project has cut, and always
    # will. A check that reported those would be reported as noise and
    # switched off.
    it "says nothing about the places a past version belongs" do
      bump_version_files
      published_artifacts
      write(unspellable("docs", "design", "tasks", "057-an-older-release.md"), "0.0.0 and 9.9.8 are history.\n")
      write("vscode/CHANGELOG.md", "# Changelog\n\n## #{prepared} - new\n\n- **A thing.** It changed.\n\n" \
                                   "### Details\n\nWhy.\n\n## 9.9.8 - shipped\n\n- **Old.** It changed.\n")

      expect { run("gate") }.not_to output(/still names 9\.9\.8/).to_stderr
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

  describe "record" do
    it "refuses when no artifact for the version has been built" do
      branch("release/#{prepared}")
      bump_version_files

      expect(run("record")).to eq(2)
    end
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
