# frozen_string_literal: true

require "rspec"
require "tmpdir"
require "fileutils"

# All test entrypoints install this before loading Core. An exec worker
# receives a new directory; activate also handles an explicitly forked
# example without allowing a child to remove its parent's cache at exit.
module SuiteHygiene
  def self.activate
    return if @pid == Process.pid

    @pid = Process.pid
    dir = Dir.mktmpdir("ovallsp-suite-cache-#{@pid}-")
    Object.send(:remove_const, :SUITE_CACHE_HOME) if Object.const_defined?(:SUITE_CACHE_HOME)
    Object.const_set(:SUITE_CACHE_HOME, dir)
    ENV["XDG_CACHE_HOME"] = dir
    owner = @pid
    at_exit { FileUtils.remove_entry(dir) if Process.pid == owner && File.directory?(dir) }
  end
end

SuiteHygiene.activate

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
  config.before { SuiteHygiene.activate }
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

