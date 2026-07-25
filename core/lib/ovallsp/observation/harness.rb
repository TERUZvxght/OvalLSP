# frozen_string_literal: true

# Loaded into the *target workspace's own* test-command process via
# `RUBYOPT="-r<this file>"` (Observation::Runner) -- never `require`s
# anything from the `ovallsp` gem by name, only by absolute path relative
# to itself, so it works whether or not the target project's own
# Gemfile happens to declare `ovallsp` as a dependency at all. Everything
# it does is opt-in and only active for the one process
# Observation::Runner explicitly spawned for this purpose -- ordinary
# `bundle exec rspec` runs never load this file at all.
require_relative "type_normalizer"
require_relative "fingerprint"
require_relative "observed_signature"
require_relative "collector"
require_relative "../index/symbol_id"
require_relative "../types"

module Ovallsp
  module Observation
    # Wires Collector's start/stop/dump-results lifecycle around the
    # host process' own at_exit -- this file's only side effect at
    # `require` time (besides the requires above) is registering that
    # hook and starting the TracePoint; nothing here overrides Bundler,
    # RSpec, or the target app's own setup, so a workspace's test suite
    # runs exactly as it otherwise would, just with one more TracePoint
    # active for the duration.
    module Harness
      module_function

      def install
        workspace_root = ENV.fetch("OvalLSP_OBSERVATION_WORKSPACE_ROOT", nil)
        output_path = ENV.fetch("OvalLSP_OBSERVATION_OUTPUT_PATH", nil)
        run_id = ENV.fetch("OvalLSP_OBSERVATION_RUN_ID", nil)
        return unless workspace_root && output_path && run_id

        collector = Collector.new(workspace_root: workspace_root)
        collector.start

        at_exit { finish(collector, run_id, output_path) }
      rescue StandardError
        # A broken harness must never break the actual test run it's
        # silently riding along with ("runner障害で通常LSPが影響を受け
        # ない" -- and symmetrically, a broken harness must never affect
        # the workspace's own test run either).
        nil
      end

      # The at_exit half of #install's "must never break the actual test
      # run" contract, and it needs its own rescue rather than relying on
      # #install's: by the time this runs, #install has long since
      # returned, so its `rescue StandardError` is completely out of
      # scope. An exception escaping an at_exit handler is not swallowed
      # by Ruby -- it prints a stack trace to the test process' stderr
      # *and* forces that process' exit status to 1. So any bug in
      # Collector#stop/#results turned a green suite red, blaming a
      # harness the user never asked to think about (found by an
      # independent review, round 9; reproduced by making
      # Collector#results raise: `suite passed` on stdout, a
      # `harness.rb:41` backtrace on stderr, exit status 1).
      #
      # #dump already had exactly this rescue, which is what makes the
      # gap a structural one rather than a typo: of the three calls in
      # the at_exit block, only the last was protected, and only because
      # it happened to live in its own method. Guarding the block itself
      # covers the class of bug (any future work added here), not just
      # today's two unprotected calls.
      def finish(collector, run_id, output_path)
        collector.stop
        dump(collector.results(run_id: run_id), output_path)
      rescue StandardError
        nil
      end

      def dump(results, output_path)
        File.binwrite(output_path, Marshal.dump(results))
      rescue StandardError
        nil
      end
    end
  end
end

Ovallsp::Observation::Harness.install
