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
