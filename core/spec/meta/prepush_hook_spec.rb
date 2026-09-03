# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "../../../scripts/repo_files"
require_relative "../../../scripts/preflight"

# **The two checks that must run before a push, as a hook rather than as
# a paragraph.**
#
# `docs/DEVELOPMENT.md` says to inspect the outgoing range and run the
# secret scan before pushing. Nothing ran either: `preflight` is a
# pre-*commit* gate and neither of these is in it — the tree scan cannot
# see a commit message, and gitleaks is not something a commit hook
# should pay for on every commit.
#
# The hook is driven here, not merely installed: a hook whose text looks
# right and refuses nothing is the shape this repository keeps meeting,
# and `024.148` is the entry for a check that could not fail in the case
# it existed for.
RSpec.describe "the pre-push hook" do
  PREPUSH_REPO = File.expand_path("../../..", __dir__)

  let(:root) { example_tmpdir("prepush") }
  let(:bin) { example_tmpdir("prepush-bin") }
  let(:hook) { File.join(root, "hook") }

  # A name that is not on `check_home_paths.rb`'s synthetic list, built
  # at runtime: this file is tracked content and that scanner reads
  # tracked content, so a literal here would be a finding about the spec
  # that drives it (`024.126`).
  def planted_home_path = "/#{unspellable('Users', 'plantedperson')}/somewhere"

  before do
    FileUtils.cp_r(File.join(PREPUSH_REPO, "scripts"), root)
    FileUtils.cp(File.join(PREPUSH_REPO, ".gitleaks.toml"), root)
    File.write(File.join(root, "a.txt"), "one\n")
    throwaway_repo(root, "a first commit")
    File.write(hook, Preflight::PREPUSH_HOOK)
    File.chmod(0o755, hook)
  end

  # `gitleaks` is not installed on every machine this suite runs on, and
  # what is under test is the hook's own sequence rather than gitleaks.
  # A stub on PATH that exits how the example needs is the seam; the
  # example below that removes it is what pins the hook's answer when the
  # real one is absent.
  def stub_gitleaks(exit_status)
    File.write(File.join(bin, "gitleaks"), "#!/bin/sh\nexit #{exit_status}\n")
    File.chmod(0o755, File.join(bin, "gitleaks"))
  end

  def head = RepoFiles.capture(root, %w[rev-parse HEAD]).strip

  # A PATH holding `git` and `ruby` and nothing else, so `gitleaks` is
  # genuinely absent. Emptying PATH instead would take the hook's other
  # two tools with it, and the example would pass on a hook that refused
  # because it could not find `git`.
  #
  # Shims rather than symlinks: a symlinked interpreter resolves its own
  # prefix from the link's target on some builds and from the link on
  # others, and this example is not about that.
  def path_without_gitleaks
    dir = example_tmpdir("prepush-noleaks")
    { "ruby" => RbConfig.ruby, "git" => executable_on_path("git") }.each do |tool, real|
      File.write(File.join(dir, tool), "#!/bin/sh\nexec #{real} \"$@\"\n")
      File.chmod(0o755, File.join(dir, tool))
    end
    dir
  end

  def executable_on_path(tool)
    found = ENV.fetch("PATH").split(File::PATH_SEPARATOR)
               .map { |dir| File.join(dir, tool) }
               .find { |candidate| File.executable?(candidate) }
    found or raise "#{tool} is not on PATH, and this example needs it to be"
  end

  # What git feeds a pre-push hook on stdin: local ref, local sha, remote
  # ref, remote sha. All zeros on the remote side is a branch the remote
  # does not have yet.
  def push(local: head, remote: "0" * 40, path: "#{bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}")
    Open3.capture3({ "PATH" => path }, hook,
                   stdin_data: "refs/heads/x #{local} refs/heads/x #{remote}\n", chdir: root)
  end

  def commit_with_message(message)
    File.write(File.join(root, "b.txt"), "two\n")
    commit_throwaway(root, message)
  end

  it "is a script the shell will accept" do
    _, err, status = Open3.capture3("sh", "-n", hook)

    expect(status).to be_success, err
  end

  # **The control.** Every example below asserts a refusal, and a hook
  # that refused every push would satisfy all of them.
  it "lets a clean range through" do
    stub_gitleaks(0)
    commit_with_message("an ordinary message")

    _, err, status = push

    expect(status).to be_success, err
  end

  it "refuses when gitleaks reports something in the outgoing range" do
    stub_gitleaks(1)
    commit_with_message("an ordinary message")

    _, err, status = push

    expect(status).not_to be_success
    expect(err).to match(/gitleaks/i)
  end

  # The channel a tree scan cannot see. 0.2.3 pasted a build machine's
  # home directory into a commit message, and the rule against it was
  # prose at the time.
  it "refuses a commit message carrying a real home path" do
    stub_gitleaks(0)
    commit_with_message("built under #{planted_home_path}")

    _, err, status = push

    expect(status).not_to be_success
    expect(err).to match(/home path/i)
  end

  # A checker that cannot run reports exactly what a working one reports
  # when nothing is wrong, so the hook says so instead of passing.
  it "refuses rather than passing when gitleaks is not installed" do
    commit_with_message("an ordinary message")

    _, err, status = push(path: path_without_gitleaks)

    expect(status).not_to be_success
    expect(err).to match(/not installed/i)
  end

  it "lets a push carrying nothing through without running either scan" do
    commit_with_message("an ordinary message")

    _, _, status = push(local: "0" * 40, path: path_without_gitleaks)

    expect(status).to be_success, "a deletion pushes no commits and has no range to scan"
  end

  describe "installing it" do
    let(:hooks_dir) { example_tmpdir("prepush-hooks") }

    it "writes an executable hook" do
      expect(Preflight.install_hook(hooks_dir, "pre-push", Preflight::PREPUSH_HOOK)).to be(0)

      installed = File.join(hooks_dir, "pre-push")
      expect(File.read(installed)).to eq(Preflight::PREPUSH_HOOK)
      expect(File.stat(installed).mode & 0o111).not_to be_zero
    end

    it "refuses to overwrite a hook somebody else wrote" do
      File.write(File.join(hooks_dir, "pre-push"), "#!/bin/sh\necho mine\n")

      expect(Preflight.install_hook(hooks_dir, "pre-push", Preflight::PREPUSH_HOOK)).to eq(1)
      expect(File.read(File.join(hooks_dir, "pre-push"))).to include("echo mine")
    end

    it "is content to rewrite its own" do
      Preflight.install_hook(hooks_dir, "pre-push", Preflight::PREPUSH_HOOK)

      expect(Preflight.install_hook(hooks_dir, "pre-push", Preflight::PREPUSH_HOOK)).to be(0)
    end
  end
end
