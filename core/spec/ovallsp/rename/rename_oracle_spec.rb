# frozen_string_literal: true

require_relative "../../../../scripts/rename_oracle"

# The countermeasure `CLAUDE.md`'s same-place rule asked for, and did not
# get until now.
#
# 0.2.17 fixed nine shapes of local-variable rename. Every one of them
# had a passing spec beside it, and none of those specs could see the
# thing that made the shapes matter: **the file the user is handed no
# longer runs.** A spec asserts an edit list; whether the program still
# parses, and still means what it meant, is a property of the program.
#
# `scripts/rename_oracle.rb` renames every local in a corpus through the
# real Server, applies the edits, re-parses, and compares the sequence of
# local-variable names with the new name mapped back. Two failures, and
# they are not equally bad:
#
#   * **unparseable** -- the editor handed back a file that does not run.
#     This is the hard invariant and it is asserted at zero.
#   * **meaning-changed** -- it parses and does something else. Reported,
#     and non-zero over real gem source for one published reason
#     (`024.273`).
#
# Measured over 1,043 files of activesupport, activerecord, actionpack,
# railties and i18n -- 3,123 renames, with `refused`, `shadowed` and the
# corpus identical on both sides as the control:
#
#   v0.2.16   unparseable=6   meaning-changed=704
#   0.2.17    unparseable=0   meaning-changed=74
#
# The 74 that remain are `024.273` and `024.274`, both published in
# `KNOWN_LIMITATIONS`: a binding whose declaration is a parameter, or an
# underscore-prefixed target, is left behind, so the uses that *were*
# rewritten stop resolving.
#
# The fixture here is small on purpose -- this runs on every suite run,
# and the gem corpus is a measurement rather than a check. What it holds
# is one instance of each shape the release fixed.
RSpec.describe "renaming a local leaves a file that still runs" do
  RENAME_ORACLE_CORPUS = File.expand_path("../../fixtures/rename_shapes", __dir__)

  let(:result) do
    counts = Hash.new(0)
    details = []
    Dir.glob(File.join(RENAME_ORACLE_CORPUS, "**", "*.rb")).sort.each do |path|
      file_counts, file_details = RenameOracle.check_file(path)
      next unless file_counts

      file_counts.each { |key, value| counts[key] += value }
      details.concat(file_details)
    end
    [counts, details]
  end

  it "renames every shape in the fixture without breaking the file" do
    counts, details = result

    expect(counts[:unparseable]).to eq(0), "#{details.join("\n")}\nA rename that leaves the file unparseable is " \
                                           "worse than a rename that is refused."
  end

  it "renames every shape completely, leaving nothing behind" do
    counts, details = result

    expect(counts[:meaning_changed]).to eq(0), details.join("\n")
  end

  # Without this the two examples above are satisfied by a corpus the
  # oracle skipped, a rename it refused, or a fixture that lost its
  # shapes -- each of which reads exactly like a clean run.
  it "actually renamed the shapes, rather than skipping or refusing them" do
    counts, = result

    expect(counts[:renames]).to be >= 5
    expect(counts[:refused]).to eq(0)
    expect(counts[:shadowed]).to eq(0)
  end

  # And that the oracle can fail at all. Every shape above is fixed, so
  # nothing in the fixture distinguishes a working oracle from one that
  # reports zero unconditionally. This drives its comparison at a rename
  # that is deliberately partial -- the shape `024.260` was.
  #
  # It is also why the comparison has two conditions. Mapping the new
  # name back and comparing sequences is *satisfied* by a partial rename,
  # because an occurrence left behind still reads as the old name and so
  # does the same position in the before-sequence. The first version of
  # the oracle had only that comparison and reported the pre-0.2.17 tree
  # clean on the very shapes this release is about. Both halves are
  # asserted here so that removing either fails.
  it "reports a rename that leaves an occurrence behind" do
    source  = "def m\n  v = 1\n  v += 2\n  v\nend\n"
    partial = "def m\n  q = 1\n  v += 2\n  v\nend\n"

    before = RenameOracle.local_names(source)
    after = RenameOracle.local_names(partial)

    complete = after.count("v").zero? && after.count("q") == before.count("v")
    expect(complete).to be(false), "the leftover condition did not see a rename that rewrote one of three uses"

    expect(after.map { |n| n == "q" ? "v" : n }).to eq(before),
                                                    "the mapped-sequence comparison is expected to *pass* here -- " \
                                                    "it is what cannot see a partial rename on its own"
  end
end
