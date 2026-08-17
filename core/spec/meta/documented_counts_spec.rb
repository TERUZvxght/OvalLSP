# frozen_string_literal: true

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
# Counted from `RSpec.world` rather than by shelling out to a second
# `rspec`: this *is* the run, and asking it how many examples it loaded is
# free. That only means the full total when the whole suite is being run,
# so a filtered run skips rather than failing on its own filter.
#
# Deliberately not a lint over every integer in the docs — only the places
# that state *this suite's* size. The corpus figures next to them are
# measurements of other things and belong to their own runs.
RSpec.describe "documented example counts" do
  def read(name) = File.read(File.expand_path("../../../#{name}", __dir__), encoding: "UTF-8")

  # Every spec file this suite owns. Rooted at `spec/` itself, not at
  # `core/`: `bundle config path vendor/bundle` -- which is what CI's own
  # `bundler-cache: true` sets -- puts `diff-lcs`' twenty spec files
  # inside `core/`, and counting those made the comparison below never
  # match. The guard then skipped on every full run, in CI included, and
  # the number it exists to hold went stale exactly as before: it said
  # 1,934 while the suite had grown past it, which is the third time this
  # figure has drifted and the first time with a guard watching.
  def spec_files_on_disk = Dir.glob(File.expand_path("../**/*_spec.rb", __dir__))

  # Only when the runner was given no files and no filters -- `rspec` with
  # nothing after it. Anything narrower is a subset, and `example_count`
  # would be the subset's size, which is not what the documents claim.
  def whole_suite?
    return false unless RSpec.configuration.filter_manager.inclusions.empty?

    spec_files_on_disk.length == RSpec.configuration.files_to_run.length
  end

  # Why this is a `skip` and not another in-suite predicate.
  #
  # Two rounds running put a defect in this file's own body (the
  # 0.2.4-bound branch's rounds): round 37
  # replaced a check that compared a glob's results against the glob's own
  # root, and round 38 found the replacement comparing "everything under
  # core/ that is not under spec/" against a `files_to_run` that `.rspec`
  # confines to `spec/`. Both were empty by construction. A third
  # predicate over the same two sets would be the same mistake a third
  # time -- and asserting the two file counts match, which was tried, is
  # *legitimately* false whenever anyone runs a single file, so it turns a
  # correct subset run red.
  #
  # The property worth holding cannot be stated from inside a run that may
  # legitimately be a subset. It is that **the run CI performs did not
  # skip**, and it is enforced where the whole suite is guaranteed:
  # `.github/workflows/ci.yml`'s "Fail if a documented-count check
  # skipped" step reads the JSON formatter's output and fails on a pending
  # from this file. `skip` rather than an early return so that step has
  # something to see.

  # `1,833` and `1833` are the same claim; the documents use the first and
  # a future one may use the second.
  def counts_in(text, pattern)
    text.scan(pattern).flatten.map { |number| Integer(number.delete(",")) }
  end

  {
    "docs/SUPPORT_MATRIX.md" => /([\d,]+) examples/,
    "docs/SUPPORT_MATRIX.ja.md" => /([\d,]+) examples/,
    "docs/RELEASE_CHECKLIST.md" => /`core\/`: ([\d,]+) examples/
  }.each do |document, pattern|
    it "states this suite's size correctly in #{document}" do
      skip "run the whole suite for this check" unless whole_suite?

      actual = RSpec.world.example_count
      stated = counts_in(read(document), pattern)

      expect(stated).not_to be_empty,
                            "#{document} no longer states a Core example count -- update this guard or the document"
      expect(stated.uniq).to eq([actual]),
                             "#{document} says #{stated.uniq.join(', ')} and the suite has #{actual}"
    end
  end
end
