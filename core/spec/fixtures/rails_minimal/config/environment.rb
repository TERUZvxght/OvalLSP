# frozen_string_literal: true

# Stands in for a real Rails app's config/environment.rb. Task 005 only
# needs to prove two things: the Agent can load an "app environment" and
# report facts from it, and stdout pollution from initializer-style code
# doesn't corrupt the protocol stream. A real Rails boot arrives with
# Task 006+; this fixture deliberately stays free of the `rails` gem.

puts "accidental stdout from a noisy initializer"
STDOUT.puts "accidental stdout via the STDOUT constant directly" # rubocop:disable Style/GlobalStdStream
warn "expected: a normal log line on stderr"

require_relative "fake_routing"

module Rails
  def self.root
    File.expand_path("..", __dir__)
  end

  def self.version
    "7.1.0-fixture"
  end

  def self.application
    @application ||= FakeApplication.new
  end

  class FakeApplication
    def routes
      @routes ||= FakeRouting::RouteSet.new
    end

    # Simulates Rails.application.reload_routes!: re-draws routes.rb from
    # scratch. Real Rails apps re-evaluate the routes DSL on reload the
    # same way; `load` (not `require`) is what makes that possible here
    # too, since `require` would silently no-op on an already-loaded file.
    def reload_routes!
      routes.routes.clear
      load(File.join(__dir__, "routes.rb"))
    end
  end
end

load(File.join(__dir__, "routes.rb"))

require_relative "fake_active_record"
require_relative "../app/models/user"
require_relative "../app/models/company"
require_relative "../app/models/order"

