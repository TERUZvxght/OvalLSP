# frozen_string_literal: true

# **The suite used the maintainer's own cache**, which is 2.3 GB and
# 53,509 directories on the machine this was written on. Every
# `Server.new` in an example builds a cache store rooted at
# `$XDG_CACHE_HOME/ovallsp`, and pruning walks it -- one real sweep is
# 8.58 seconds, and the suite triggers it repeatedly.
#
# Two things were wrong with that, and the second is the worse one:
#
# - it is most of the suite's wall time, and none of it is testing
#   anything;
# - a run *mutates* the cache the editor then uses, and two trees
#   measured against it are not measuring the same thing. That is not
#   hypothetical: a corpus comparison in 0.3.0 came out with
#   `gem-index-classes` at 2,077 on one side and 2,220 on the other,
#   and a false report was nearly attributed to a fix that introduced
#   none.
#
# Measured on that machine: 26,397 scopes and 282,805 entries, about
# five seconds per example that starts a server, and most of a
# thirteen-minute run.
#
# Set here rather than in the two spec files that already redirected it,
# so it holds for every example whether or not its author thought about
# the cache -- and because this is the shape `027` is about, where six
# days of `bundle exec rspec` removed installed applications. The lesson
# there was that a test reaching outside its own tmpdir is the hazard,
# whatever it does next.
#
# One directory for the whole run rather than one per example: the cache
# is meant to be reused across launches, and an example that wants a
# fresh one already makes its own.
#
# Per process, so parallel runs cannot share one, and removed at exit.
require "tmpdir"
require "fileutils"

SUITE_CACHE_HOME = File.join(Dir.tmpdir, "ovallsp-suite-cache-#{Process.pid}")
FileUtils.mkdir_p(SUITE_CACHE_HOME)
ENV["XDG_CACHE_HOME"] = SUITE_CACHE_HOME
at_exit { FileUtils.remove_entry(SUITE_CACHE_HOME) if File.directory?(SUITE_CACHE_HOME) }


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

Dir[File.join(__dir__, "support", "*.rb")].sort.each { |f| require f }
