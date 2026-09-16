# frozen_string_literal: true

require_relative "../../../scripts/test_environment"

# Mutable app/DB state is private to each example group and process. The
# suite's one cleanup owner reclaims it even if setup or an example fails.
module RealRailsFixture
  def workspace
    @workspace ||= TestEnvironment.copy_fixture(
      source: File.expand_path("../fixtures/rails_real", __dir__),
      lock: TestEnvironment.fixture_lock,
      destination: File.join(SUITE_CACHE_HOME, "rails-#{object_id}")
    )
  end

  def machine_has_real_rails_gems?
    return @machine_gems if defined?(@machine_gems)
    @machine_gems = TestEnvironment.probe(TestEnvironment.clean_env, RbConfig.ruby, "-e",
      'gem "rails", "~> 8.1"; gem "sqlite3", ">= 2.1"; require "rails"; require "sqlite3"')
  end

  def fixture_bundle_env
    Ovallsp::BundleEnvironment.for_workspace(workspace)
  end

  def available?
    return @available if defined?(@available)
    return false unless machine_has_real_rails_gems?
    # Probe the product's isolation separately, with frozen pre-resolved
    # dependencies. A defect here is a failure, never an unavailable gem.
    unless TestEnvironment.probe(fixture_bundle_env.merge("BUNDLE_FROZEN" => "true"),
                                "bundle", "check", chdir: workspace)
      raise "prepared Rails fixture failed under BundleEnvironment; check bundle isolation"
    end
    @available = true
  end
end

# The minimal fixture has no Gemfile/Bundler graph of its own -- it's a
# hand-written fake_routing.rb/fake_active_record.rb double, not real
# Rails -- so unlike RealRailsFixture it needs no lock/`bundle check` step,
# just a private copy of its handful of files.
#
# Every user gets that private copy, not just the one example that flips
# `config/.disable_archived_route` (Task 006's reload test): the source
# tree is shared across every process running specs, so a writer in one
# process and a reader in another previously raced on the same file.
# `example_tmpdir` (core/spec/test_hygiene.rb) gives a fresh copy per
# example and reclaims it in an `after` hook even on failure, which also
# means a flag one example sets can never leak into a sibling example
# reusing the same process.
module MinimalRailsFixture
  SOURCE = File.expand_path("../fixtures/rails_minimal", __dir__)

  def minimal_rails_fixture
    @minimal_rails_fixture ||= begin
      destination = example_tmpdir("ovallsp-rails-minimal")
      Dir.children(SOURCE).sort.each { |name| FileUtils.cp_r(File.join(SOURCE, name), destination) }
      # Defensive against a stray flag left in the source tree (e.g. by
      # code predating this isolation): every fresh copy starts with the
      # archived route present, regardless of source state.
      FileUtils.rm_f(File.join(destination, "config", ".disable_archived_route"))
      File.realpath(destination)
    end
  end
end
