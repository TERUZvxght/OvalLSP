# frozen_string_literal: true

require "json"
require "fileutils"

RSpec.describe Ovallsp::Benchmark::ColdIndexBenchmark do
  # Design targets (docs/design/tasks/021-persistent-cache-and-performance.md):
  # 1k files cold index within 5s, 5k files warm-usable within 3s. This
  # spec runs a *scaled-down* corpus (small enough to stay fast in CI on
  # every run) and reports actual numbers rather than asserting against
  # those absolute targets -- "目標を満たせない場合も数値を隠さず記録す
  # る" / "regression thresholdを少なくともreport-onlyで導入する". A full-
  # scale 1k/5k run is the same class, just called with a larger
  # `file_count:` -- intentionally not run on every CI invocation, since
  # a hard multi-second-per-run cost on every commit isn't worth paying
  # for a number this test already reports at smaller scale.
  REPORT_PATH = File.expand_path("../../../tmp/cold_index_benchmark_report.json", __dir__)

  it "runs the benchmark and writes a report, without asserting a pass/fail threshold" do
    report = described_class.new(logger: instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil)).run(file_count: 50)

    expect(report[:error]).to be_nil
    expect(report[:cold_seconds]).to be_a(Numeric)
    expect(report[:warm_seconds]).to be_a(Numeric)

    FileUtils.mkdir_p(File.dirname(REPORT_PATH))
    File.write(REPORT_PATH, JSON.pretty_generate(report))

    # Report-only: logged for a human/CI-artifact to notice, never fails
    # the suite on a slow machine or a real regression -- see the
    # class-level comment for why a hard assertion here would be the
    # wrong shape for this test.
    warn "[cold_index_benchmark] #{report.inspect}" if ENV["OvalLSP_BENCHMARK_VERBOSE"]
  end

  # Was `expect(report[:warm_seconds]).to be <= (report[:cold_seconds] * 2)`,
  # and it is a wall-clock ratio over roughly a tenth of a second of work,
  # so a single scheduler hiccup during the warm pass fails it. Observed
  # doing exactly that mid-review (round 19), on an otherwise-green full
  # suite run under load, and then passing on the very next run of the same
  # file -- the same flaky-by-construction shape as the mtime race in
  # `spec/ovallsp/cache/store_spec.rb` that this repo's fix-in-place policy
  # was written for.
  #
  # It also contradicted both the class under test and its own sibling
  # example, each of which says in as many words that this benchmark is
  # report-only and must "never fail the suite on a slow machine".
  #
  # Loosening the multiplier would only move the flake further out, so the
  # timing assertion is gone entirely and what it was a *proxy* for is
  # asserted directly: the warm pass must serve the whole corpus from the
  # cache and re-parse nothing. That is a count, not a duration -- it is
  # exactly the property that makes the warm run faster, it cannot be
  # perturbed by machine load, and it fails loudly if the cache stops
  # being consulted at all (a real regression the old ratio would have
  # caught only on a quiet machine).
  it "serves the whole corpus from the cache on the warm pass, re-parsing nothing" do
    file_count = 50
    parses_in_pass = 0
    parses_per_pass = []

    # ColdIndexer#run is single-threaded (it walks and indexes inline), so
    # a plain counter is sound here without synchronization.
    allow_any_instance_of(Ovallsp::ParserService).to receive(:summarize).and_wrap_original do |original, *args|
      parses_in_pass += 1
      original.call(*args)
    end
    allow_any_instance_of(Ovallsp::ColdIndexer).to receive(:run).and_wrap_original do |original|
      original.call
    ensure
      parses_per_pass << parses_in_pass
      parses_in_pass = 0
    end

    described_class.new(logger: instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil))
                   .run(file_count: file_count)

    # The benchmark makes exactly three passes: cold with no cache at all,
    # a second cold pass that populates one, then the warm pass.
    expect(parses_per_pass.size).to eq(3)
    expect(parses_per_pass[0]).to eq(file_count)
    expect(parses_per_pass[1]).to eq(file_count)
    expect(parses_per_pass[2]).to be_zero
  end
end
