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
    "register-open-defects" => ->(rev = nil) { DeferredFindings.open_defects(register(rev)).length },
    # How many times `ParserService` asks each of `Index::Cref`'s two
    # surface questions. `Cref#surface_for`'s own comment argues from the
    # gap between them, and it argued from a number typed out of 0.2.11's
    # stocktake that had since drifted from seven to ten (`024.102`).
    #
    # Counted as the call, `@cref.` and all: every mention in a comment
    # writes the bare `#name` form instead, so the receiver is what tells
    # a call from a citation without stripping comments first.
    "cref-defines-surface-parser-sites" => ->(_rev = nil) { parser_calls("defines_surface?") },
    "cref-declares-singleton-parser-sites" => ->(_rev = nil) { parser_calls("declares_singleton?") }
  }.freeze

  def self.parser_calls(name)
    File.read(File.join(TREE_ROOT, "core", "lib", "ovallsp", "parser_service.rb"), encoding: "UTF-8")
        .scan("@cref.#{name}").length
  end

  REGISTER = "docs/design/tasks/024-deferred-review-findings.md"

  # At `rev` when the claim is dated, otherwise as it stands.
  def self.register(rev = nil)
    return File.read(File.join(TREE_ROOT, REGISTER), encoding: "UTF-8") if rev.nil?

    # Through `RepoFiles`, which unsets `GIT_DIR` and its family at the
    # spawn -- `024.157`. `chdir:` does not override them, so under a
    # pre-commit hook's environment this would read a dated claim's
    # revision out of whichever repository the hook named.
    out = RepoFiles.capture(TREE_ROOT, ["show", "#{rev}:#{REGISTER}"])
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
    # `024.182`/`024.216`. Derived from the register's own number grammar
    # rather than written here a second time. The hand-rolled version
    # could not express a sub-number, so a pointer at a sub-entry that
    # has never existed matched as its *parent*, which does exist, and
    # the dangling pointer resolved. (Shape described rather than
    # spelled: this file is excluded from its own scan, and an
    # illustration written out here would be a finding the day that
    # exclusion is removed. `024.126`.)
    CITATION = DeferredFindings::CITATION
    REGISTER_BASENAME = "024-deferred-review-findings.md"

    # An entry that is still here, or a row in the register's
    # "Retired numbers" table -- a deleted entry keeps its number
    # resolvable, which is the whole point of citing one.
    #
    # Both halves come from `DeferredFindings`: `024.216` counted six
    # readers of the entry number in three grammars, and these were two
    # of them.
    def register_numbers
      register = File.read(File.join(TREE_ROOT, "docs", "design", "tasks", REGISTER_BASENAME), encoding: "UTF-8")
      (DeferredFindings.headings(register) + DeferredFindings.retired_numbers(register)).to_set
    end

    # Every tracked text file, not a hand-written list of directories.
    # The first version of this scanned four globs and missed both
    # changelogs -- which `024.67`'s own Area list names -- so it reported
    # clean while `024.5` was cited in both, in the same sentence as three
    # numbers that did resolve. A guard whose scope is a list somebody
    # remembered has the defect it was built to catch.
    #
    # Two entries meet on this one method, and both fixes are kept.
    #
    # **The register is *in* scope** -- `024.183`. It used to be rejected
    # outright, so the densest place `024.N` cross-references are written,
    # and the place a reader most often follows one from, was the one
    # place a typo could not be caught. What the rejection was really
    # avoiding is the file's own structure reporting itself, and that is
    # what `structural_line?` skips instead.
    #
    # **And the scope is stated as what it excludes** -- `024.180`. It was
    # a list of nine extensions, which is the same shape one turn further
    # on from the defect that entry is about. Measured, that list dropped
    # 38 files: every published `site/` page, four of which cite a
    # register entry; every extensionless file; the `.rbs` signatures; the
    # gemspec; the PowerShell job script. No other check reads any of
    # those for register pointers, so renumbering an entry they cite would
    # have left four dangling pointers on the public site with the whole
    # suite green.
    #
    # A denylist is the shape `check_doc_links.rb`'s `SKIP` already uses:
    # vendored trees, and files that are not authored text. Getting it
    # wrong is noisy rather than silent, which is the direction a
    # scanner's scope should fail in.
    NOT_AUTHORED_TEXT = %r{
      \A(?:core/vendor/|vscode/node_modules/)
      |
      \.(?:png|ico|jpg|jpeg|gif|pdf|zip|gz|vsix|sqlite3|woff2?|ttf|otf|eot|wasm|lock)\z
    }x

    def scanned_files
      RepoFiles.list(TREE_ROOT)
             .reject { |path| path.match?(NOT_AUTHORED_TEXT) }
             .reject { |path| path.end_with?(File.basename(__FILE__)) }
             .map { |path| File.join(TREE_ROOT, path) }
    end

    # The register's own scaffolding: an entry heading, a generated index
    # row, a "Retired numbers" row. Each states a number rather than
    # citing one, and each is checked by `deferred_findings_spec` on its
    # own terms.
    def structural_line?(line)
      line.start_with?("## 024.") || line.match?(/\A\| \[?`#{DeferredFindings::NUMBER}`/)
    end

    def dangling_in(text, known, label:, register: false)
      text.lines.each_with_index.flat_map do |line, index|
        next [] if register && structural_line?(line)

        line.scan(CITATION).flatten
            .reject { |number| known.include?(number) }
            .map { |number| "#{label}:#{index + 1}: #{number}" }
      end
    end

    def citations
      known = register_numbers
      scanned_files.sort.flat_map do |path|
        label = path.delete_prefix("#{TREE_ROOT}/")
        dangling_in(File.read(path, encoding: "UTF-8"), known, label: label, register: label.end_with?(REGISTER_BASENAME))
      end
    end

    # The scope, asserted against content that exists rather than trusted.
    # `024.180`: the filter above was a list of nine extensions, and the
    # published site is HTML — so four pages carrying a register pointer
    # sat outside this check, outside `check_site_links.rb` (which
    # verifies links, anchors and assets and has no register handling)
    # and outside `check_doc_links.rb` (which verifies file paths).
    # Deleting or renumbering the entry they cite would have left four
    # dangling pointers on the published site with the suite green.
    #
    # Stated as "a published page that carries a pointer is read",
    # because that is the property; asserting the denylist back would
    # only restate the mechanism.
    it "reads the published pages too, not only the file types somebody listed" do
      pages = scanned_files.select { |path| path.end_with?(".html") }
      expect(pages).not_to be_empty, "no published page is being read; the scope has narrowed to a list again"

      carrying = pages.select { |path| File.read(path, encoding: "UTF-8").match?(CITATION) }
      expect(carrying).not_to be_empty,
                              "the site's pages point into the register, and none of those pointers is being read"
    end

    it "all resolve to an entry that exists" do
      expect(citations).to be_empty,
                           "these point at register entries that are not there:\n#{citations.join("\n")}\n" \
                           "Either the entry was deleted without the grep its legend asks for, or the number " \
                           "is a typo. Both read as a reason the reader can go and check, and neither is."
    end

    # `024.183`. The scan the exclusion made impossible, run against a
    # register-shaped text rather than the real file: a stray pointer in
    # an entry's body is reported, while the heading and index row that
    # state the same number are not.
    #
    # The three structural lines state a number the fixture's `known` set
    # does not hold, so each of them would be reported if the skip stopped
    # working. Given a number that resolves, the example would pass
    # whether or not anything was skipped -- an assertion that cannot
    # fail, which is the shape this whole batch is about.
    it "reports a stray pointer written inside the register's own body" do
      stated = unspellable_number(995)
      body = "## #{stated} An entry\n\n| [`#{stated}`](#0-an-entry) | open | 0.2.16 | An entry |\n" \
             "| `#{stated}` | what it recorded |\n" \
             "See #{unspellable_number(996)} for the reasoning.\n"

      expect(dangling_in(body, Set[], label: "reg", register: true))
        .to eq(["reg:5: #{unspellable_number(996)}"])

      # And the skip is the register's alone: those three lines are
      # ordinary content in any other file, where nothing states an entry
      # number except by citing it.
      expect(dangling_in(body, Set[], label: "doc").length).to eq(4)
    end

    # `024.182`. The half that needs no register change: a citation of a
    # sub-entry that has never existed used to truncate to its parent and
    # resolve.
    it "reports a citation of a sub-entry that does not exist" do
      known = Set["024.13"]

      expect(dangling_in("see #{unspellable_number('13.9')} for why\n", known, label: "doc"))
        .to eq(["doc:1: #{unspellable_number('13.9')}"])
    end

    # And the control, or the pair cannot tell a working grammar from one
    # that reports every citation: the parent still resolves.
    it "accepts a citation of an entry that exists" do
      expect(dangling_in("see 024.13 for why\n", Set["024.13"], label: "doc")).to be_empty
    end
  end
end
