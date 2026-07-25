# frozen_string_literal: true

require "benchmark"
require_relative "../../fixtures/observation/sample_classes"

RSpec.describe "Observation overhead (Task 019)" do
  it "invalidate_stale_observations does zero file I/O when nothing has ever been observed (observation disabled by default)" do
    output = StringIO.new
    logger = instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil)
    server = Rslsp::Server.new(input: StringIO.new(""), output: output, logger: logger)

    allow(Rslsp::Observation::Fingerprint).to receive(:for_file_and_line).and_raise("must not be called")
    allow(Rslsp::Observation::Fingerprint).to receive(:for_content_and_line).and_raise("must not be called")

    expect { server.send(:invalidate_stale_observations) }.not_to raise_error
  end

  it "collecting a large number of calls completes within a generous time bound" do
    workspace_root = File.expand_path("../../fixtures/observation", __dir__)
    collector = Rslsp::Observation::Collector.new(workspace_root: workspace_root)

    collector.start
    elapsed = Benchmark.realtime do
      3000.times { ObservationFixture::Widget.new.combine("a", "b") }
    end
    collector.stop

    # Deliberately generous (not a tight perf assertion, which would be
    # flaky across CI hardware) -- this only guards against a gross
    # regression (e.g. an accidental O(n^2) somewhere), not a specific
    # overhead percentage.
    expect(elapsed).to be < 10
  end
end
