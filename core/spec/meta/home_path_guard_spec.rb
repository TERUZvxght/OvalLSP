# frozen_string_literal: true

require "tmpdir"

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

  # `024.187`. A NUL byte or one invalid UTF-8 sequence used to remove the
  # **whole file** from the scan, plain-ASCII home path and all -- the
  # rule was a property of the bytes rather than of the file, so a text
  # file that acquired a stray byte silently stopped being checked and no
  # example could fail on it. The bytes are scrubbed and read now.
  #
  # This is the distinguishing form, and it needs no fixture: the tree
  # carries two files with NUL bytes in them, they are exactly the files
  # the old rule declined, and `skipped_files` comes back empty only
  # because they were read. Put the skip back and this fails.
  # The distinguishing half: a name in the file's plain-ASCII portion is
  # reported even though the file also holds a NUL. Asserting only that
  # nothing was *skipped* would pass against a silent skip, which is the
  # arrangement 0.2.5 already had to fix once.
  it "reads a file with stray bytes rather than dropping it from the scan" do
    Dir.mktmpdir("home-path-") do |root|
      File.binwrite(File.join(root, "with-stray.md"), "built under #{path_for('frank')}\n\x00\n")

      expect(HomePaths.offences_in_file("with-stray.md", root: root)).to eq(["with-stray.md:1: frank"])
    end
  ensure
    HomePaths.skipped_files.clear
  end

  # And the same decision at tree scale, which is where it mattered: the
  # two files the old rule declined are still here, and the scan now
  # declines nothing at all.
  it "declines no file in this tree, including the two that hold stray bytes" do
    stray = HomePaths.files_with_stray_bytes

    expect(stray.length).to be >= 2,
                            "this example distinguishes nothing unless the tree still carries a file " \
                            "with a NUL byte in it. It carried two."

    HomePaths.tree_offences

    expect(HomePaths.skipped_files).to be_empty,
                                       "the scan declined #{HomePaths.skipped_files.inspect}. A skip is a file " \
                                       "the check could not clear, and it must not be one it merely would not read."
  end

  # The one skip left is for a path that is not a file at all, and it is
  # recorded rather than returned as silence -- which it was until
  # `024.188`, a third silent skip beside the two 0.2.5 announced.
  it "records a path it could not read as a file, rather than returning silence" do
    Dir.mktmpdir("home-path-") do |root|
      Dir.mkdir(File.join(root, "a-directory"))
      HomePaths.skipped_files.clear

      expect(HomePaths.offences_in_file("a-directory", root: root)).to be_empty
      expect(HomePaths.skipped_files.map { |entry| entry[:reason] }).to eq([:not_a_file])
      expect(HomePaths.skipped_files.first[:path]).to eq("a-directory")
    end
  ensure
    HomePaths.skipped_files.clear
  end

  # `024.188`. For a symlink, git stores the *target string* as the whole
  # blob -- so committing one publishes a real home path verbatim, and
  # `File.file?`/`File.binread` both dereference: a live link made the
  # scanner read bytes from outside the repository and report a line
  # number in a file that is not in it, and a broken link returned `[]`
  # with no skip recorded.
  #
  # Both halves, because they fail differently. The target here is
  # deliberately broken: the stored string is the whole content, so
  # nothing needs to exist at the other end, and pointing a fixture at a
  # real home directory is the thing this check is about.
  it "reads the target a symlink stores, not whatever it points at" do
    Dir.mktmpdir("home-path-") do |root|
      target = ["", "Users", "carol", "WorkSpace", "nothing-here"].join("/")
      File.symlink(target, File.join(root, "link"))
      HomePaths.skipped_files.clear

      expect(HomePaths.offences_in_file("link", root: root)).to eq(["link:1: carol"])
      expect(HomePaths.skipped_files).to be_empty
    end
  ensure
    HomePaths.skipped_files.clear
  end

  it "does not read a symlinked file's contents in place of its stored target" do
    Dir.mktmpdir("home-path-") do |root|
      File.write(File.join(root, "real.txt"), "#{path_for('dave')}\n")
      File.symlink(File.join(root, "real.txt"), File.join(root, "link"))

      # The link stores an absolute path built by `mktmpdir`, which names
      # no home directory; the file it points at names one. Reporting
      # `dave` here would mean the scanner had followed the link.
      expect(HomePaths.offences_in_file("link", root: root)).to be_empty
      expect(HomePaths.offences_in_file("real.txt", root: root)).to eq(["real.txt:1: dave"])
    end
  ensure
    HomePaths.skipped_files.clear
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

  # `024.189`. The pattern required exactly one separator, so every other
  # on-disk spelling of the *same real path* was invisible. Each fixture
  # is assembled, never typed: this file is scanned by the pattern it
  # tests.
  #
  # The last of them is the one that was not hypothetical. Widening the
  # scan found that spelling of the maintainer's own home directory
  # already committed to this public repository, in a register entry
  # written after `024.189` was raised -- because nothing could see it.
  it "catches every on-disk spelling of one real path, not just the first" do
    name = "carol"

    doubled_slash    = ["", "Users", name, "project"].join("//")
    doubled_backslash = ["C:", "Users", name, "project"].join("\\\\")
    json_escaped     = ["", "Users", name, "project"].join("\\/")
    hyphen_mangled   = ["", "Users", name, "WorkSpace", "Github"].join("-")

    [doubled_slash, doubled_backslash, json_escaped, hyphen_mangled].each do |spelling|
      expect(HomePaths.names_in(spelling)).to eq([name]), "missed a spelling of the same real path"
    end
  end

  # And the other side of widening: the hyphen form must not read an
  # ordinary hyphenated phrase as a path. `home` is deliberately not in
  # that pattern for this reason -- the scanner's own output strings
  # contain one.
  it "does not read a hyphenated English phrase as a path" do
    expect(HomePaths.names_in("check-home-paths: clean")).to be_empty
    expect(HomePaths.names_in("a-single-nul-clears-a-whole-file-from-the-home-path-scan")).to be_empty
  end

  # `024.190`. An annotated tag's body is written by hand at release time
  # and pushed to the public remote, and it is not a commit message --
  # so neither the tree scan, nor the commit half, nor gitleaks read a
  # byte of it. Release time is exactly when 0.2.3 pasted a build
  # machine's home directory into a commit message.
  #
  # The floor is what makes this more than a green light: a wrong format
  # string, or a clone fetched without tags, returns an empty list that
  # looks exactly like a clean one.
  it "reads the annotated tag bodies, and there are some to read" do
    bodies = HomePaths.tag_bodies
    substantial = bodies.count { |_, body| body.strip.length > 20 }

    expect(substantial).to be >= 20,
                           "only #{substantial} tag(s) came back with a body. Either the format string " \
                           "stopped reading `%(contents)`, or this clone was fetched without tags -- and " \
                           "in both cases the scan below is clean because it read nothing."
    expect(HomePaths.tag_offences).to be_empty
  end

  # The floor above says the tag bodies were read; this says `--messages`
  # actually reports them. Without it, deleting the tag half from
  # `message_offences` leaves every example green -- which is what the
  # mutation manifest found on the first run.
  it "reports the tag half under --messages, not only when asked directly" do
    allow(HomePaths).to receive(:shallow?).and_return(false)
    allow(HomePaths).to receive(:commit_offences).and_return([])
    allow(HomePaths).to receive(:tag_offences).and_return(["tag v0.0.0-synthetic: carol"])

    expect(HomePaths.message_offences).to eq(["tag v0.0.0-synthetic: carol"])
  end

  it "reports which tag, so a failure names the thing to rewrite" do
    expect(HomePaths.names_in("released from #{path_for('erin')}")).to eq(["erin"])
    expect(HomePaths.tag_bodies.map(&:first)).to all(match(/\A\S+\z/))
  end
end
