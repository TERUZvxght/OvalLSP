# frozen_string_literal: true

require_relative "../../../scripts/check_home_paths"

# 0.2.3's countermeasure for a class the norm alone failed to hold twice.
# CLAUDE.md has said since the repository went public that local absolute
# paths must not be committed, and it names Git metadata and copied
# command output as disclosure paths rather than only source files. It
# was missed anyway, twice: 0.2.1's record named a scaffolded application
# by its absolute path, and 0.2.3's pre-publish gate quoted the build
# machine's home directory into both a task document and a commit
# message. Same place twice, so CLAUDE.md's own rule says the third pass
# is a machine check rather than a third hand fix.
#
# The detector lives in `scripts/check_home_paths.rb` and this spec reads
# it, deliberately: a Ruby matcher here beside a shell `grep` in ci.yml
# would be two scanners obliged to agree about the same text, which is
# the shape 0.2.1 already spent a countermeasure removing.
#
# Scope split, and why it is this way round:
#
#   * tracked file *content* is checked here, because the suite runs
#     everywhere and needs no history to do it;
#   * commit *messages* are checked by ci.yml's secret-scan job, which
#     already fetches full history for gitleaks. They are deliberately
#     not checked here -- the Core CI jobs check out shallow, so this
#     spec would scan one commit and call the history clean. The script
#     refuses a shallow clone outright for the same reason, and
#     `ci_skip_guard_spec.rb` pins that the job still runs it.
#
# What this guards is content, not history. The already-published
# instance in `main` stays: rewriting it would orphan the `buildCommit`
# SHAs baked into the 0.2.1 and 0.2.2 VSIXs the Marketplace still serves,
# for no privacy gain -- `teruz` is the published Marketplace publisher
# id in `vscode/package.json` to begin with. 028 records that decision.
RSpec.describe "no real home directory path in tracked content" do
  # Assembled rather than written literally, so this file does not itself
  # contain the string it forbids. The first draft of this spec did write
  # one literally, in the `/home/` example below, and the guard failed on
  # its own spec -- which is the check demonstrating itself, and the
  # reason both prefixes are built the same way now.
  def path_for(name, prefix: "Users")
    ["", prefix, name, "project", "Gemfile"].join("/")
  end

  it "names no one's home directory anywhere in the tracked tree" do
    offences = HomePaths.tree_offences

    expect(offences).to be_empty, lambda {
      "Tracked content names a real home directory:\n" \
        "#{offences.join("\n")}\n\n" \
        "Write `$HOME`, `~`, or a description instead. If the name is " \
        "genuinely synthetic, add it to SYNTHETIC in " \
        "scripts/check_home_paths.rb and say why."
    }
  end

  # Without this, the example above passes for whatever reason -- a regex
  # that matches nothing, a file list that came back empty -- and reports
  # the tree clean while checking it is the one thing it did not do.
  it "detects a planted name, so a clean tree means the scan looked" do
    expect(HomePaths.names_in(path_for("alice"))).to eq(["alice"])
    expect(HomePaths.names_in("built under #{path_for('tkato', prefix: 'home')}")).to eq(["tkato"])
  end

  it "passes the synthetic fixtures the suite genuinely needs" do
    expect(HomePaths.names_in(path_for("example"))).to be_empty
    expect(HomePaths.names_in(path_for("runner", prefix: "home"))).to be_empty
    expect(HomePaths.offences_in_file("core/spec/ovallsp/redactor_spec.rb")).to be_empty
  end

  it "reads an ellipsis as prose about the class rather than a name" do
    expect(HomePaths.names_in("#{path_for('...')} strings are synthetic")).to be_empty
  end

  it "reports where, so a failure is actionable rather than a bare no" do
    offences = HomePaths.offences_in_file("scripts/check_home_paths.rb")

    # The scanner's own file is clean, and the reporting format is pinned
    # against a string instead, since a real offence must never exist to
    # test against.
    expect(offences).to be_empty
    expect(HomePaths.names_in("a #{path_for('bob')} b")).to eq(["bob"])
  end

  it "actually enumerated the repository, rather than an empty list" do
    files = HomePaths.tracked_files

    expect(files).to include("CLAUDE.md", "docs/SUPPORT_MATRIX.md", "scripts/check_home_paths.rb")
    expect(files.size).to be > 100
  end

  it "skips compiled payloads, which carry build paths that are not authored" do
    expect(HomePaths.offences_in_file("does/not/exist.bundle")).to be_empty
  end
end
