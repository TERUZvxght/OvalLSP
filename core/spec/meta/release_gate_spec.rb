# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"

require "json"
require "yaml"

# `046`'s C6. `docs/RELEASE_CHECKLIST.md`'s gate table has an evidence
# column naming what enforces each item. Until 0.2.14 seven rows named
# `make-final-review-bundle.sh` -- 919 lines that nothing invoked: not
# CI, not `release.sh`, not the suite. Those gates were written down and
# run by nobody, and one of them (SBOM regeneration determinism) was
# enforced nowhere else at all, so it had silently not been checked since
# the last time somebody ran the script by hand.
#
# Reading the table could not reveal it. Every row said the same kind of
# thing, and the difference between "a script that runs" and "a script
# that exists" is not visible in prose.
#
# The rule: an executable cited in the evidence column must exist and be
# invoked by something that runs -- a workflow, `release.sh`, or a spec.
# This does not check that a gate *passes*. It checks that "enforced by
# X" has an X wired to something.
#
# A row may cite something nothing runs if it marks itself
# `<!-- unwired -->` -- for a genuinely manual gate, or for a mention of
# something since deleted. Row 17 is both: its "VS Code isolated install"
# step lived in the deleted script, and `verify-installed-extension.sh`
# has always been run by hand. The marker renders as nothing and is a
# deliberate edit on the row that needs it, the same shape
# `check_doc_links.rb` uses for a recorded deletion -- and the row must
# still say what does enforce the item now.
RSpec.describe "RELEASE_CHECKLIST's evidence column" do
  RELEASE_GATE_ROOT = File.expand_path("../../..", __dir__)

  # The evidence column's own header names three kinds of thing: a CI job
  # name, a spec, or a `release.sh` step. Until 0.2.16 the extractor
  # recognised a script path and an npm script name, and nothing else --
  # so a row whose evidence was a TypeScript test or a CI job produced no
  # citation at all and was reported clean. Not "unrecognised": *absent*,
  # which reads exactly like a row with nothing to check.
  #
  # Nine rows were in that state, including the delayed-start race test,
  # the E1/C1->E2/C2 update test, the payload-hash test and the Workspace
  # Trust manifest test -- each deletable with its gate still green. The
  # spec even carried a branch skipping the invocation test for a
  # TypeScript test file, which could never fire because no pattern here
  # could produce one. `024.156`.
  #
  # Four shapes now, and each is checked against a real list rather than
  # against a glob:
  RELEASE_GATE_SCRIPT = /`([A-Za-z0-9_.\/-]+\.(?:rb|sh|js))`/
  RELEASE_GATE_TS_TEST = /`([A-Za-z0-9_.\/-]+\.test\.ts)`/
  RELEASE_GATE_NPM = /`(test:[a-z:]+)`/

  # A CI job is named in prose rather than by a shape a regex can tell
  # from any other backticked word, so the citation form is what is
  # matched: the table writes "CI の `<job>` ジョブ", and the English
  # equivalent is accepted for a row written later in English.
  #
  # Matching the *form* rather than intersecting backticked words with
  # the job list is the point. An intersection would silently drop a
  # renamed job -- the citation would simply stop being a citation, which
  # is the defect this whole example exists about, arriving one level in.
  RELEASE_GATE_CI_JOB = /CI\s*(?:の|'s)\s*`([A-Za-z0-9_-]+)`\s*(?:ジョブ|job)/

  # Every job name any workflow defines, parsed rather than grepped.
  def self.ci_job_names
    @ci_job_names ||= Dir.glob(File.join(RELEASE_GATE_ROOT, ".github/workflows/*.yml")).sort.flat_map do |path|
      (YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: true)["jobs"] || {}).keys
    end.uniq
  end

  # Every npm script `npm run` could actually invoke.
  def self.npm_script_names
    @npm_script_names ||= JSON.parse(read("vscode/package.json")).fetch("scripts").keys
  end

  # Every path this tree carries, and every basename among them. The
  # existence test was `RepoFiles.list(ROOT, "*#{basename}")` -- a suffix
  # glob that accepted any file whose name merely *ends with* the cited
  # one, and never compared the cited path itself. Two paths that exist
  # nowhere were accepted because a real file's name ended with theirs,
  # and a traversal path was accepted as gate 8's evidence. `024.193`.
  def self.tracked_paths
    @tracked_paths ||= RepoFiles.list(RELEASE_GATE_ROOT)
  end

  def self.tracked_basenames
    @tracked_basenames ||= tracked_paths.map { |rel| File.basename(rel) }.to_set
  end

  # Where an invocation could live. A spec counts: the suite runs it.
  RELEASE_GATE_CALLERS = %w[
    .github/workflows/ci.yml
    .github/workflows/pages.yml
    .github/workflows/apple-silicon-release.yml
    vscode/scripts/release.sh
    vscode/package.json
  ].freeze

  def self.read(rel)
    path = File.join(RELEASE_GATE_ROOT, rel)
    File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
  end

  # Every table row of the gate table, as [row-number, evidence-cell].
  # Only table rows: the surrounding prose narrates the 0.2.14 rewrite
  # and names the deleted script on purpose.
  def evidence_cells
    self.class.read("docs/RELEASE_CHECKLIST.md").each_line.filter_map do |line|
      next unless line.start_with?("|")

      cells = line.split("|").map(&:strip)
      next if cells.length < 3
      next unless cells[1].match?(/\A[\d.]+\z/)

      [cells[1], cells[2..].join(" ")]
    end
  end

  # Everything the suite could invoke, plus the named callers -- with
  # comment lines removed.
  #
  # Without that removal this check is close to useless, and in a way
  # that reads as working: `release_script_guard_spec.rb` and
  # `check_home_paths.rb` both *name* `make-final-review-bundle.sh` in
  # comments explaining that it was deleted, so a plain text search finds
  # it and calls the gate wired. A check whose evidence is that a string
  # appears somewhere is the same mistake as the table it is checking.
  #
  # Ruby, YAML and shell all comment with `#`, which is why one rule
  # covers every file here.
  # A file naming *itself* is not an invocation. `verify_sbom_against_vsix.rb`
  # line 23 is `fail!("usage: verify_sbom_against_vsix.rb ...")` -- a
  # non-comment line carrying its own basename -- so a haystack that
  # included the script's own text reported gate 11 wired while `046`
  # itself records that the script is invoked by nothing.
  #
  # This was C6 failing in the exact way C6 exists to catch, and round 1
  # found it: a check that passes for a reason other than the one it
  # states. So the haystack is built *per candidate*, excluding the
  # candidate's own file.
  #
  # `RepoFiles.tracked`, not `.list`, and the difference is deliberate --
  # `024.194`. This corpus is not what the check *inspects*, it is what
  # the check accepts as evidence that something invokes a script, and an
  # uncommitted scratch file merely naming a basename flipped a gate from
  # "nothing invokes this" to "wired". A reason that exists in no commit
  # is not a reason. The `exists` test below keeps `024.147`'s behaviour,
  # because there a file being written is exactly what must be visible.
  def haystack_excluding(base)
    @sources ||= (RELEASE_GATE_CALLERS + RepoFiles.tracked(RELEASE_GATE_ROOT, "core/spec", "scripts"))
                 .uniq
                 .to_h { |rel| [rel, self.class.read(rel)] }

    @sources
      .reject { |rel, _| base && File.basename(rel) == base }
      .values
      .join("\n")
      .each_line
      .reject { |line| line.strip.start_with?("#", "//") }
      .join
  end

  # Every citation in one cell, as [kind, name], in the four shapes the
  # column's header allows.
  def citations_in(cell)
    [[:script, RELEASE_GATE_SCRIPT], [:ts_test, RELEASE_GATE_TS_TEST],
     [:npm, RELEASE_GATE_NPM], [:ci_job, RELEASE_GATE_CI_JOB]].flat_map do |kind, pattern|
      cell.scan(pattern).flatten.compact.map { |name| [kind, name] }
    end.uniq
  end

  # A cited path must be a path this tree carries. A citation written as
  # a bare basename -- which four of the TypeScript rows are -- must
  # match some file's basename *exactly*; that is the honest equivalent
  # of exact membership when no directory was written, and it still
  # rejects a name that is merely a suffix of a real one.
  def exists?(kind, name)
    case kind
    when :script, :ts_test
      name.include?("/") ? self.class.tracked_paths.include?(name) : self.class.tracked_basenames.include?(name)
    when :npm    then self.class.npm_script_names.include?(name)
    when :ci_job then self.class.ci_job_names.include?(name)
    end
  end

  # Does something run it? A spec and a TypeScript test are run by their
  # suite by existing, and a workflow job *is* the thing that runs, so
  # for those three existence is the whole question. A script and an npm
  # script have to be named by a caller.
  #
  # The npm test is bounded rather than a plain substring: `test:integ`
  # is a substring of `test:integration`, so an unbounded search reported
  # a name nobody could invoke as wired.
  def wired?(kind, name)
    case kind
    when :ts_test, :ci_job then true
    when :npm
      haystack_excluding(nil).match?(/(?<![A-Za-z0-9:._-])#{Regexp.escape(name)}(?![A-Za-z0-9:._-])/)
    when :script
      base = File.basename(name)
      base.end_with?("_spec.rb") || haystack_excluding(base).include?(base)
    end
  end

  it "cites only executables that exist and that something actually runs" do
    unwired = evidence_cells.flat_map do |number, cell|
      next [] if cell.include?("<!-- unwired -->")

      citations_in(cell).filter_map do |kind, name|
        next "gate #{number}: #{kind} #{name} is cited as evidence and does not exist" unless exists?(kind, name)
        next if wired?(kind, name)

        "gate #{number}: #{name} exists but nothing invokes it"
      end
    end

    expect(unwired).to be_empty,
                       "#{unwired.join("\n")}\n" \
                       "A gate whose evidence nothing runs is a gate that is written down and not " \
                       "enforced. Wire it, or mark the row <!-- unwired --> and say what does " \
                       "enforce the item now."
  end

  # Without this, the example above passes if the extractor stops
  # matching anything -- which is exactly what a table reformat would do.
  #
  # **A floor per shape, not one total.** `024.156` was a branch for a
  # shape the extractor could not produce: the total was healthy, and one
  # whole kind of citation was contributing nothing to it. A single
  # number cannot see that; four can. If a shape's pattern stops matching
  # -- a table reformat, a regex edit, a convention that drifts -- the
  # floor for that shape fails and names it, instead of the rows quietly
  # becoming unchecked.
  it "extracts every shape of evidence the column's header allows" do
    found = evidence_cells.flat_map { |_, cell| citations_in(cell) }
    by_kind = found.group_by(&:first).transform_values { |v| v.map(&:last).uniq }

    expect(evidence_cells.length).to be >= 20
    expect(found.map(&:last).uniq.length).to be >= 8

    %i[script ts_test npm ci_job].each do |kind|
      expect(by_kind[kind].to_a).not_to be_empty,
                                        "no #{kind} citation was extracted from any gate row. Either the " \
                                        "table stopped citing that kind of evidence, or the pattern for it " \
                                        "stopped matching and those rows are now silently unchecked -- " \
                                        "which is 024.156."
    end
  end

  # The planted name is assembled, never spelled. This file is scanned by
  # the haystack it builds, so a name written whole is *in* the haystack
  # and the example asserts the opposite of what it means.
  #
  # It shipped that way: the suite was green when run, because the file
  # was still untracked and `git ls-files` could not see it, and red the
  # moment it was committed. `024.126` (a scanner matching its own prose)
  # and `024.147` (a check blind to a file until it is committed) meeting
  # in one example.
  it "would catch a row citing a script nothing runs" do
    absent = "scripts/#{%w[nothing runs this].join("_")}.rb"
    planted = "| 99 | a gate | ✅ `#{absent}` |"

    expect(citations_in(planted)).to eq([[:script, absent]])
    expect(exists?(:script, absent)).to be(false)
    expect(haystack_excluding(File.basename(absent))).not_to include(absent)
  end

  # `024.194`, and the reason the corpus above is `RepoFiles.tracked`.
  # An uncommitted scratch file under `scripts/` that merely *names* a
  # script flipped a gate from "nothing invokes this" to "wired", so the
  # check passed on evidence no commit contains -- green on the machine
  # that happened to hold the file, red everywhere else.
  #
  # The probe is written into the real tree because that is the only
  # place the corpus reads from; both names are assembled so neither the
  # scanners nor this file's own haystack can read them as real. It is
  # removed in `ensure`, and the path is built from `RELEASE_GATE_ROOT`
  # rather than fabricated.
  it "does not accept an uncommitted file as evidence that something runs" do
    needle = "#{%w[nothing runs this].join("_")}.rb"
    probe = File.join(RELEASE_GATE_ROOT, "scripts", "#{%w[uncommitted evidence probe].join("-")}.txt")
    File.write(probe, "todo: look at #{needle} tomorrow\n")

    expect(File.exist?(probe)).to be(true)
    expect(haystack_excluding("release.sh")).not_to include(needle),
                                                    "an untracked file is being read as an invocation"
  ensure
    File.unlink(probe) if probe && File.exist?(probe)
  end

  # The three shapes 0.2.16 added, each planted the way `024.156` and
  # `024.193` report them, and each assembled so this file does not carry
  # a citation-shaped literal of its own.
  it "would catch a row citing a TypeScript test, a CI job or an npm script that does not exist" do
    ts = "#{%w[never was written].join("_")}.test.ts"
    job = %w[no such job].join("-")
    npm = "test:#{%w[not a script].join("")}"
    planted = "| 99 | a gate | ✅ `#{ts}` + CI の `#{job}` ジョブ + `#{npm}` |"

    expect(citations_in(planted)).to match_array([[:ts_test, ts], [:ci_job, job], [:npm, npm]])
    expect(exists?(:ts_test, ts)).to be(false)
    expect(exists?(:ci_job, job)).to be(false)
    expect(exists?(:npm, npm)).to be(false)
  end

  # The suffix glob `024.193` records: a name that exists nowhere, whose
  # basename is a suffix of a real file's, used to be accepted. So did a
  # traversal path, because the cited path itself was never compared
  # against anything.
  it "would catch a citation that is only a suffix of a real path, and one that escapes the tree" do
    real = self.class.tracked_paths.find { |f| File.basename(f).start_with?(%w[generate sbom].join("_")) }
    suffix_only = File.basename(real)[-7..]
    traversal = "#{"../" * 4}etc/generate_sbom.rb"

    expect(self.class.tracked_paths.any? { |f| f.end_with?(suffix_only) }).to be(true)
    expect(exists?(:script, suffix_only)).to be(false)
    expect(exists?(:script, traversal)).to be(false)
  end
end
