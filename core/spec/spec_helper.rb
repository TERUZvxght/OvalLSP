# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../lib/ovallsp"

# `Dir.mktmpdir` *with* a block removes the directory when the block
# returns; without one it returns the path and removes nothing, ever.
# Four call sites in this suite used the blockless form because they
# needed the path to outlive an expression rather than a block -- and so
# leaked one directory per example, permanently, on every developer's and
# CI machine (found by an independent review, round 19; measured on this
# project's own machine before the fix: 301 stale `ovallsp-*` directories
# in TMPDIR, growing by ~5 per full suite run, with nothing anywhere that
# would ever remove them).
#
# This is the block form's guarantee restored without the block: the
# directory is registered against the *example*, and RSpec's own `after`
# hook is the `ensure` -- so it is removed even when the example fails or
# raises, which is exactly when a hand-written `ensure` per call site is
# most likely to be the thing that was forgotten.
#
# `spec/meta/tmpdir_hygiene_spec.rb` is what keeps this from decaying: it
# fails on any blockless `Dir.mktmpdir` reintroduced anywhere under spec/.
module ExampleTmpdir
  def example_tmpdir(prefix = "ovallsp-spec")
    dir = Dir.mktmpdir(prefix)
    (@example_tmpdirs ||= []) << dir
    dir
  end

  # Total, for the same reason every cleanup path in lib/ is: this runs
  # from an `after` hook, and one undeletable directory must not stop the
  # rest of the example's directories being reclaimed, nor turn a passing
  # example red.
  def remove_example_tmpdirs
    Array(@example_tmpdirs).each do |dir|
      FileUtils.remove_entry(dir)
    rescue StandardError
      nil
    end
    @example_tmpdirs = nil
  end
end

RSpec.configure do |config|
  config.include ExampleTmpdir
  config.after { remove_example_tmpdirs }

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
