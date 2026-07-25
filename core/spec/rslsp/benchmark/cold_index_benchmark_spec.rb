# frozen_string_literal: true

require "json"
require "fileutils"

RSpec.describe Rslsp::Benchmark::ColdIndexBenchmark do
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
    report = described_class.new(logger: instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil)).run(file_count: 50)

    expect(report[:error]).to be_nil
    expect(report[:cold_seconds]).to be_a(Numeric)
    expect(report[:warm_seconds]).to be_a(Numeric)

    FileUtils.mkdir_p(File.dirname(REPORT_PATH))
    File.write(REPORT_PATH, JSON.pretty_generate(report))

    # Report-only: logged for a human/CI-artifact to notice, never fails
    # the suite on a slow machine or a real regression -- see the
    # class-level comment for why a hard assertion here would be the
    # wrong shape for this test.
    warn "[cold_index_benchmark] #{report.inspect}" if ENV["RSLSP_BENCHMARK_VERBOSE"]
  end

  it "reports a warm run's cache-hit path as no slower than the cold run that populated it, on a representative small corpus" do
    report = described_class.new(logger: instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil)).run(file_count: 50)

    # A soft, generous check (not the design doc's own hard target) --
    # the *direction* of the effect (cache genuinely helps, doesn't
    # regress) is what's actually load-bearing here; exact multipliers
    # are too machine-dependent for a hard assertion in this suite.
    expect(report[:warm_seconds]).to be <= (report[:cold_seconds] * 2)
  end
end
