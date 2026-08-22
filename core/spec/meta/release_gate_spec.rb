# frozen_string_literal: true

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

  # Anything that could be run: a script by path, or an npm script name.
  RELEASE_GATE_EXECUTABLE = /`([A-Za-z0-9_.\/-]+\.(?:rb|sh|js))`|`(test:[a-z:]+)`/

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
  def haystack
    @haystack ||= begin
      specs = IO.popen(%w[git ls-files core/spec scripts], chdir: RELEASE_GATE_ROOT, &:read).split("\n")
      (RELEASE_GATE_CALLERS + specs)
        .map { |rel| self.class.read(rel) }
        .join("\n")
        .each_line
        .reject { |line| line.strip.start_with?("#", "//") }
        .join
    end
  end

  it "cites only executables that exist and that something actually runs" do
    unwired = evidence_cells.flat_map do |number, cell|
      next [] if cell.include?("<!-- unwired -->")

      cell.scan(RELEASE_GATE_EXECUTABLE).flatten.compact.uniq.filter_map do |cited|
        base = File.basename(cited)
        exists = cited.start_with?("test:") ||
                 !IO.popen(["git", "ls-files", "*#{base}"], chdir: RELEASE_GATE_ROOT, &:read).strip.empty?
        next "gate #{number}: #{cited} is cited as evidence and does not exist" unless exists
        # A spec is invoked by the suite by existing; nothing names it,
        # and that is not the same as nothing running it.
        next if base.end_with?("_spec.rb", ".test.ts")
        next if haystack.include?(base)

        "gate #{number}: #{cited} exists but nothing invokes it"
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
  it "finds evidence to check in the first place" do
    cited = evidence_cells.flat_map { |_, cell| cell.scan(RELEASE_GATE_EXECUTABLE).flatten.compact }

    expect(evidence_cells.length).to be >= 20
    expect(cited.uniq.length).to be >= 8
  end

  it "would catch a row citing a script nothing runs" do
    planted = "| 99 | a gate | ✅ `scripts/nothing_runs_this.rb` |"
    cited = planted.scan(RELEASE_GATE_EXECUTABLE).flatten.compact

    expect(cited).to eq(["scripts/nothing_runs_this.rb"])
    expect(haystack).not_to include("nothing_runs_this.rb")
  end
end
