# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"
require_relative "../../../scripts/deferred_findings"

require "open3"
require "tmpdir"

# A number in a document that describes this tree is a claim about it, and
# this project has now had three of them fail re-derivation in two
# releases — each written while doing the work and never re-run:
#
# - 0.2.6 recorded the open-surface rule as opening "24 of 257 classes,
#   and every name among them can define a method". The rule that shipped
#   counted calls inside blocks, which the prototype did not, and gives
#   52 of 329 with `warn` and `lambda` among the triggers. The figure
#   described a rule nobody ran.
# - 0.2.7 recorded its hunk sweep as "5 pinned, two of the unpinned
#   comment-only". Re-run: 6 pinned, one comment-only.
# - 0.2.7's architecture section said "27 `Mutex.new` sites" against 29 —
#   in the section whose stated purpose is that it stopped contradicting
#   the code.
#
# Each was found by somebody else re-running it. `documented_counts_spec`
# already re-derives exactly one such number, the suite's own size, and
# that one has never been wrong.
#
# So: a number that is a claim about the tree gets marked, and this
# recomputes it. Writing an unmarked number stays possible — this cannot
# know which numbers in prose are claims — but a number that matters is
# then a two-part deliberate edit, the same shape `check_home_paths.rb`'s
# `SYNTHETIC` list already uses.
#
#     <!-- measured: mutex-sites = 29 -->
#
# Adding a claim means adding its deriver below. A marker naming a
# deriver that does not exist fails, so a claim cannot be marked and left
# uncomputed.
RSpec.describe "numbers documented about this tree" do
  TREE_ROOT = File.expand_path("../../..", __dir__)

  # `@<rev>` makes the claim historical: it is derived from the file as
  # it stood at that revision, not as it stands now.
  #
  # Round 1 found why this is needed. `037` is 0.2.7's record, and its
  # sentence "N open defects ... sort into eight classes" is a statement
  # about the register *as the classification was made*. Bound to a
  # present-tense deriver, every later release rewrote it — so a
  # historical document ended up asserting a number nobody had measured
  # against the thing it describes, and the eight classes were derived
  # from a register a hundred entries smaller.
  #
  # The alternative was an unmarked hand-typed number, which is what the
  # sentence *had* before and what got it wrong (53 against the deriver's
  # own answer). A dated claim stays checkable; an undated one is a
  # promise to remember.
  MARKER = /<!--\s*measured:\s*(?<name>[a-z0-9-]+)(?:@(?<rev>[0-9a-f]{7,40}))?\s*=\s*(?<value>[0-9]+)\s*-->/

  # Each deriver answers the current truth. Keep them cheap: this runs on
  # every suite run.
  DERIVERS = {
    # Every `Mutex.new` in the shipped library. The architecture
    # document's threading section states the lock order and was wrong
    # about this count on the release that introduced it.
    "mutex-sites" => lambda { |_rev = nil|
      Dir.glob(File.join(TREE_ROOT, "core", "lib", "**", "*.rb"))
         .sum { |f| File.read(f, encoding: "UTF-8").scan("Mutex.new").length }
    },
    # Entries in the deferred-findings register, and the open defects in
    # it -- the number a reader of `036` is deciding against.
    #
    # Both read through `DeferredFindings`, which `046`'s C4 made the
    # single parser of this file. They did not until round 1 found them:
    # this file carried a *third* and *fourth* reader, a heading regex
    # that could not match a sub-numbered entry and a hand-rolled
    # `key: value` scanner -- the same scanner C4 had just deleted from
    # `reindex_findings.rb`, with the same divergence. A quoted
    # `status: "fixed"` reads as `"fixed"` with its quotes, fails the
    # resolved test, and counts a closed entry as open.
    #
    # **And the failure mode is inverted, which is why it matters.** The
    # deriver is the side that would be wrong, so the *correct*
    # documented number is what fails, and the message below tells the
    # author to write the false count into the document.
    "register-entries" => ->(rev = nil) { DeferredFindings.headings(register(rev)).length },
    "register-open-defects" => ->(rev = nil) { DeferredFindings.open_defects(register(rev)).length }
  }.freeze

  REGISTER = "docs/design/tasks/024-deferred-review-findings.md"

  # At `rev` when the claim is dated, otherwise as it stands.
  def self.register(rev = nil)
    return File.read(File.join(TREE_ROOT, REGISTER), encoding: "UTF-8") if rev.nil?

    out = IO.popen(["git", "show", "#{rev}:#{REGISTER}"], chdir: TREE_ROOT, err: %i[child out], &:read)
    raise "cannot read #{REGISTER} at #{rev}: #{out}" unless $?.success?

    out
  end

  def claims
    patterns = %w[docs/**/*.md core/lib/**/*.rb core/spec/**/*.rb vscode/src/**/*.ts]
    # This file writes a sample marker to exercise the scanner, so it
    # scans everything but itself.
    patterns.flat_map { |glob| Dir.glob(File.join(TREE_ROOT, glob)) }
            .reject { |path| path.end_with?(File.basename(__FILE__)) }
            .sort.flat_map do |path|
      File.read(path, encoding: "UTF-8").lines.each_with_index.filter_map do |line, index|
        next unless (m = line.match(MARKER))

        { path: path.delete_prefix("#{TREE_ROOT}/"), line: index + 1, name: m[:name],
          rev: m[:rev], value: Integer(m[:value]) }
      end
    end
  end

  it "names a deriver for every claim, so none can be marked and left uncomputed" do
    unknown = claims.reject { |c| DERIVERS.key?(c[:name]) }

    expect(unknown).to be_empty,
                       "marked as measured with no deriver: " \
                       "#{unknown.map { |c| "#{c[:path]}:#{c[:line]} #{c[:name]}" }.join(', ')}"
  end

  it "matches what the tree actually says" do
    wrong = claims.select { |c| DERIVERS.key?(c[:name]) }.filter_map do |c|
      actual = DERIVERS.fetch(c[:name]).call(c[:rev])
      next if actual == c[:value]

      "#{c[:path]}:#{c[:line]}: #{c[:name]} says #{c[:value]}, the tree has #{actual}"
    end

    expect(wrong).to be_empty, "#{wrong.join("\n")}\nRe-derive the number rather than editing the prose around it."
  end

  # Every deriver is attached to a claim somewhere. Without this the file
  # passes with **zero** claims in the tree -- a reviewer measured that
  # deleting the single marker left it green at 4 examples, so the guard
  # was one edit away from checking nothing while reading as a guarantee.
  # A deriver nobody cites is either a claim somebody forgot to mark or a
  # deriver to delete, and both should be said out loud.
  it "has every deriver attached to a claim that exists" do
    cited = claims.map { |c| c[:name] }.uniq
    orphaned = DERIVERS.keys - cited

    expect(orphaned).to be_empty,
                        "derivers with no claim to check: #{orphaned.join(', ')}. " \
                        "Mark the number where it is written, or delete the deriver."
  end

  # And the marker machinery is exercised rather than assumed: the file's
  # positive control used to call one deriver directly and assert it was
  # not 27, which passes whether or not anything scans for markers at all.
  it "reads a claim out of a document and compares it" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.md")
      File.write(path, "the tree has 4 of them <!-- measured: sample-claim = 4 -->\n")
      parsed = File.read(path).lines.filter_map { |line| line.match(MARKER) }

      expect(parsed.map { |m| [m[:name], Integer(m[:value])] }).to eq([["sample-claim", 4]])
    end
  end

  # The check is worth having only if it would catch what it was written
  # for, so it is run against that rather than trusted: the count the
  # architecture section shipped wrong.
  it "would have caught the count that shipped wrong" do
    expect(DERIVERS.fetch("mutex-sites").call).not_to eq(27)
  end

  # The same failure without a number: a pointer into the register that
  # resolves to nothing. `024.67` records seven of them, across source
  # comments, spec comments and both changelogs -- each a route to a
  # reason that leads nowhere, and each written when the entry existed.
  # The register's legend says to grep before deleting an entry; this is
  # that grep, run every time instead of remembered.
  describe "pointers into the deferred-findings register" do
    CITATION = /\b024\.(?<number>[0-9]+|R[0-9]+)\b/

    # An entry that is still here, or a row in the register's
    # "Retired numbers" table -- a deleted entry keeps its number
    # resolvable, which is the whole point of citing one.
    def register_numbers
      register = File.read(File.join(TREE_ROOT, "docs", "design", "tasks", "024-deferred-review-findings.md"),
                           encoding: "UTF-8")
      (register.scan(/^## (024\.[0-9R]+) /).flatten + register.scan(/^\| `(024\.[0-9R]+)` \|/).flatten).to_set
    end

    # Every tracked text file, not a hand-written list of directories.
    # The first version of this scanned four globs and missed both
    # changelogs -- which `024.67`'s own Area list names -- so it reported
    # clean while `024.5` was cited in both, in the same sentence as three
    # numbers that did resolve. A guard whose scope is a list somebody
    # remembered has the defect it was built to catch.
    def scanned_files
      RepoFiles.list(TREE_ROOT)
             .select { |path| path.match?(/\.(rb|ts|js|md|json|yml|yaml|sh|erb)\z/) }
             .reject { |path| path.end_with?("024-deferred-review-findings.md") }
             .reject { |path| path.end_with?(File.basename(__FILE__)) }
             .map { |path| File.join(TREE_ROOT, path) }
    end

    def citations
      known = register_numbers
      scanned_files
              .sort.flat_map do |path|
        File.read(path, encoding: "UTF-8").lines.each_with_index.filter_map do |line, index|
          line.scan(CITATION).flatten.filter_map do |number|
            cited = "024.#{number}"
            "#{path.delete_prefix("#{TREE_ROOT}/")}:#{index + 1}: #{cited}" unless known.include?(cited)
          end
        end.flatten
      end
    end

    it "all resolve to an entry that exists" do
      expect(citations).to be_empty,
                           "these point at register entries that are not there:\n#{citations.join("\n")}\n" \
                           "Either the entry was deleted without the grep its legend asks for, or the number " \
                           "is a typo. Both read as a reason the reader can go and check, and neither is."
    end
  end
end
