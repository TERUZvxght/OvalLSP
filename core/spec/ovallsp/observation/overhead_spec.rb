# frozen_string_literal: true

require "benchmark"
require_relative "../../fixtures/observation/sample_classes"

RSpec.describe "Observation overhead (Task 019)" do
  it "invalidate_stale_observations does zero file I/O when nothing has ever been observed (observation disabled by default)" do
    output = StringIO.new
    logger = instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil)
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger)

    allow(Ovallsp::Observation::Fingerprint).to receive(:for_file_and_line).and_raise("must not be called")
    allow(Ovallsp::Observation::Fingerprint).to receive(:for_content_and_line).and_raise("must not be called")

    expect { server.send(:invalidate_stale_observations) }.not_to raise_error
  end

  it "collecting a large number of calls completes within a generous time bound" do
    workspace_root = File.expand_path("../../fixtures/observation", __dir__)
    collector = Ovallsp::Observation::Collector.new(workspace_root: workspace_root)

    collector.start
    elapsed = Benchmark.realtime do
      3000.times { ObservationFixture::Widget.new.combine("a", "b") }
    end
    collector.stop

    # Deliberately generous (not a tight perf assertion, which would be
    # flaky across CI hardware) -- this only guards against a gross
    # regression (e.g. an accidental O(n^2) somewhere), not a specific
    # overhead percentage.
    # perf-guard: gross regression only (an accidental O(n^2)), not an overhead percentage
    expect(elapsed).to be < 10
  end

  # `Collector#@method_cache` used to cite the timing example above as what
  # guards it. Measured in review round 24, it does not and cannot: deleting
  # the cache outright makes this file 12x slower (0.017s -> 0.20s) and still
  # leaves it 50x inside a bound deliberately kept loose enough not to be
  # flaky on CI hardware. So the cache was a mechanism nothing pinned -- the
  # shape round 23 found for `#pop_matching`, in the same class -- and it is
  # not a mere optimization: the whole run's symbol_id/fingerprint
  # attribution is keyed off it (see #symbol_id_for's docs, round 24).
  #
  # Asserted as a *count*, not a duration, so it pins the actual invariant
  # ("one computation per method that exists, never per call") and cannot go
  # flaky on a slow machine.
  it "hashes a traced method's source file once per method, not once per call" do
    workspace_root = File.expand_path("../../fixtures/observation", __dir__)
    collector = Ovallsp::Observation::Collector.new(workspace_root: workspace_root)

    fingerprint_calls = 0
    original = Ovallsp::Observation::Fingerprint.method(:for_file_and_line)
    allow(Ovallsp::Observation::Fingerprint).to receive(:for_file_and_line) do |*args|
      fingerprint_calls += 1
      original.call(*args)
    end

    collector.start
    500.times { ObservationFixture::Widget.new.combine("a", "b") }
    collector.stop

    # `Widget#combine` is the only Ruby-defined workspace method these 500
    # iterations enter (`Widget.new` is C-implemented, so untraced -- table
    # row 6), so one full-file digest total.
    expect(fingerprint_calls).to eq(1)
    expect(collector.results(run_id: "r1").first&.samples).to eq(500)
  end
end
