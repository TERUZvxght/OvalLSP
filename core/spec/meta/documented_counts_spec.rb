# frozen_string_literal: true

require "tmpdir"

# The example counts documents cite, against the suite that produces them.
#
# Three releases running, a document has stated a suite size that was true
# when it was written and stale by the time it shipped — 895 for six
# releases, then 1,776 taken mid-branch *in the sentence criticising the
# previous figure for not being re-measured*, then 1,833 with two commits
# still to come. `RELEASE_CHECKLIST` even carries the instruction to
# re-measure, and went stale anyway. A number a person copies is a number
# that goes stale; one a suite reads cannot.
#
# Runner shards exercise the checker against small documents; the runner
# owns the real count comparison. A direct full RSpec invocation retains
# its in-suite comparison, including CI until its runner migration.
RSpec.describe "documented example counts" do
  def whole_suite?
    RSpec.configuration.filter_manager.inclusions.empty? &&
      Dir.glob(File.expand_path("../**/*_spec.rb", __dir__)).length == RSpec.configuration.files_to_run.length
  end

  # A worker cannot prove the full count from its local RSpec.world.
  # The runner checks the documents against its independent census once
  # after all workers finish. These examples exercise that check using
  # controlled documents, so focused runs no longer need a pending escape.
  # The documents and their patterns live in `scripts/documented_counts.rb`,
  # which both this guard and the re-deriving tool read. Two readers of
  # one text with two grammars is `046`'s C4, and writing the table twice
  # inside C4's own release would be a poor joke.
  require_relative "../../../scripts/documented_counts"

  DocumentedCounts::PATTERNS.each_key do |document|
    it "states this suite's size correctly in #{document}" do
      if whole_suite?
        expect(DocumentedCounts.stated(document).uniq).to eq([RSpec.world.example_count])
      end
      Dir.mktmpdir("ovallsp-counts") do |dir|
        DocumentedCounts::PATTERNS.each_key do |name|
          path = File.join(dir, name)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, name.end_with?("RELEASE_CHECKLIST.md") ? "`core/`: 2 examples" : "2 examples")
        end
        expect(DocumentedCounts.complaints(2, root: dir)).to eq([])
        path = File.join(dir, document)
        File.write(path, "wording lost the count")
        expect(DocumentedCounts.complaints(2, root: dir)).to contain_exactly(a_string_starting_with(document))
      end
    end
  end

  # `024.151`. The tool reports what it *wrote*, not what it found
  # stale: the substitution returns nil when its pattern matched
  # nothing, which is a document whose wording moved out from under it --
  # classed stale, never written to, and until round 1 found it, still
  # counted in the success line and exited 0.
  #
  # Tested through the pure function rather than a document, so the
  # refusal path is reachable without a tracked file being left wrong if
  # this example fails.
  it "reports nothing written when a document's wording moved out from under its pattern" do
    pattern = DocumentedCounts::PATTERNS.fetch("docs/SUPPORT_MATRIX.md")

    expect(DocumentedCounts.substituted("the suite has 1,833 examples", pattern, 2000))
      .to eq("the suite has 2,000 examples")
    expect(DocumentedCounts.substituted("the suite has examples: 1,833 of them", pattern, 2000))
      .to be_nil
  end

  it "compares a census count against the documents rather than a worker's count" do
    expect(DocumentedCounts.complaints(-1)).not_to be_empty
  end
end
