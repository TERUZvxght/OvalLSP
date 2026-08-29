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

  # Windows' backslash form was not matched at all. Assembled, like every
  # other fixture here, so this spec is not itself the thing the scanner
  # reports.
  it "catches the Windows separator form" do
    expect(HomePaths.names_in(["C:", "Users", "carol", "project"].join("\\"))).to eq(["carol"])
  end

  # The variant deliberately *not* matched, pinned so the decision is
  # visible rather than looking like an oversight. Case-insensitivity
  # would catch a lowercase spelling of a home path -- and flag the
  # ordinary Rails resource directories that appear throughout the specs
  # and the design docs. The reasoning is in the scanner beside the
  # pattern; if someone later decides the trade is worth it, this example
  # is what they must consciously change.
  it "does not treat a lowercase Rails resource directory as a home path" do
    expect(HomePaths.names_in(["", "users", "alice", "project"].join("/"))).to be_empty
    expect(HomePaths.names_in("app/views/users/show.html.erb")).to be_empty
  end

  # The example above pins the decision; this one re-derives the *reason*
  # for it, which until 0.2.16 was a hand-typed count in two places that
  # was wrong at every revision it was checked against (`024.192`).
  #
  # A floor rather than a number: the argument is "so many false reports
  # that the check gets switched off", and that argument is about an
  # order of magnitude, not about a total. Asserting the total would put
  # back exactly the maintained figure this replaces. The floor is set
  # well under the current answer so ordinary churn does not move it, and
  # the case-sensitive side is asserted at zero in the same example so a
  # scan that read nothing cannot satisfy either half.
  it "would cry wolf if it were case-insensitive, which is why it is not" do
    insensitive = Regexp.new(HomePaths::PATTERN.source, Regexp::IGNORECASE)

    would_flag = HomePaths.tracked_files.sum do |relative|
      absolute = File.join(HomePaths::ROOT, relative)
      next 0 unless File.file?(absolute)

      content = File.binread(absolute)
      next 0 if content.include?("\0")

      content.force_encoding(Encoding::UTF_8)
      next 0 unless content.valid_encoding?

      content.lines.count do |line|
        line.scan(insensitive).flatten.reject { |name| HomePaths::SYNTHETIC.include?(name) }.any?
      end
    end

    expect(would_flag).to be >= 20,
                          "the case-insensitive pattern flags #{would_flag} line(s). The decision to keep " \
                          "PATTERN case-sensitive rests on that number being large; if it has fallen to " \
                          "nearly nothing, revisit the decision rather than lowering this floor."
    expect(HomePaths.tree_offences).to be_empty
  end

  # A file this scanner cannot read is a file it cannot clear, and until
  # 0.2.5 both skips returned an empty list silently -- so a compiled
  # artefact or a mis-encoded file simply did not exist as far as the
  # guard's answer was concerned. It still skips them, for the reason its
  # own comment gives, but it says so.
  it "reports what it skipped rather than returning silence" do
    skipped = HomePaths.skipped_files

    expect(skipped).to be_an(Array)
    expect(skipped.map { |entry| entry[:reason] }.uniq - %i[binary invalid_encoding]).to be_empty
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
