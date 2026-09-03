# frozen_string_literal: true

# A wall-clock threshold in a test measures the machine, not the code.
# This suite had two asserting that answering `initialize` is fast, and
# both were wrong in the same three ways:
#
# - they flaked, because the margin was under 2x on the maintainer's own
#   machine and a loaded one crossed it;
# - they could not fail for what they claimed -- indexing 120 two-line
#   files takes ~50ms, so running it *synchronously* also came in under a
#   second, measured;
# - they timed the wrong event, since `server.run` returns after `exit`,
#   which joins the background tasks.
#
# Each was replaced by the property that actually holds: the reply is
# written before the indexing starts, and the workspace pass runs on a
# thread that is not the one serving requests. Both fail when the code is
# mutated; neither can be affected by load.
#
# The second one is why this file exists rather than a third careful
# rewrite. docs/REVIEW_LOOP.md: the first time a place is found twice, put in
# something that makes the class of defect fail a check instead of
# waiting for a reviewer.
#
# **A performance guard is a different thing** and stays allowed, marked
# `# perf-guard: <why>` on the line or the one above it. The point is not
# that duration is unmeasurable -- it is that a duration compared against
# a constant must be *claimed as* a performance bound, so a reader can
# tell it from an assertion about behaviour and knows it may flake on a
# loaded machine. Ratios between two measurements in the same run, and
# timeouts that stop a test hanging, are neither and are not matched.
#
# The marker is a deliberate edit with a reason, the same shape
# `scripts/check_home_paths.rb`'s `SYNTHETIC` list already uses.
RSpec.describe "the suite's own timing assertions" do
  SPEC_ROOT = File.expand_path("..", __dir__)

  # `expect(elapsed).to be < 1.0`, `expect(duration).to be <= 0.5`, and
  # the `be_within` spelling of the same thing. Deliberately narrow: it
  # keys on a variable named for a duration, so an ordinary numeric
  # comparison is not swept up.
  THRESHOLD = /
    expect\s*\(\s*(?<name>[a-z_]*(?:elapsed|duration|took|seconds|ms)[a-z_]*)\s*\)
    \s*\.\s*to\s+
    (?:be\s*[<>]=?\s*[\d_.]+ | be_within\s*\(\s*[\d_.]+)
  /x

  PERF_GUARD = /#\s*perf-guard:/

  def offending_lines(path)
    lines = File.read(path, encoding: "UTF-8").lines
    lines.each_with_index.filter_map do |line, index|
      # A comment may quote one -- the two this file was written for both
      # explain themselves where they used to be.
      next if line.lstrip.start_with?("#")
      next unless line.match?(THRESHOLD)
      next if line.match?(PERF_GUARD) || lines[index - 1].to_s.match?(PERF_GUARD)

      "#{path.delete_prefix("#{SPEC_ROOT}/")}:#{index + 1}: #{line.strip}"
    end
  end

  it "compares no duration against a constant without saying it is a performance bound" do
    # This file's own examples below are written to match, on purpose.
    paths = Dir.glob(File.join(SPEC_ROOT, "**", "*_spec.rb")).sort - [File.expand_path(__FILE__)]

    offenders = paths.flat_map { |path| offending_lines(path) }

    expect(offenders).to be_empty,
                         "a duration compared against a constant measures the machine, not the code:\n" \
                         "#{offenders.join("\n")}\n" \
                         "Assert the property instead -- what ordering, what thread, what was already " \
                         "written -- or mark it `# perf-guard: <why>` if it really is a performance bound."
  end

  # The check is only worth having if it would catch what it was written
  # for, so it is run against those rather than trusted.
  it "matches the two assertions it replaced" do
    [
      "      expect(elapsed).to be < 1.0",
      "      expect(duration_seconds).to be_within(0.2).of(1.0)"
    ].each { |sample| expect(sample).to match(THRESHOLD) }
  end

  # And the shapes that measure something real stay usable.
  it "does not match a ratio between two measurements, or an ordinary comparison" do
    [
      "      expect(large - empty).to be < (empty * 2)",
      "      expect(findings.size).to be < 10"
    ].each { |sample| expect(sample).not_to match(THRESHOLD) }
  end
end
