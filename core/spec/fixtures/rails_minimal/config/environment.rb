# frozen_string_literal: true

# Stands in for a real Rails app's config/environment.rb. Task 005 only
# needs to prove two things: the Agent can load an "app environment" and
# report facts from it, and stdout pollution from initializer-style code
# doesn't corrupt the protocol stream. A real Rails boot arrives with
# Task 006+; this fixture deliberately stays free of the `rails` gem.

require "open3"

puts "accidental stdout from a noisy initializer"
STDOUT.puts "accidental stdout via the STDOUT constant directly" # rubocop:disable Style/GlobalStdStream
warn "expected: a normal log line on stderr"

# Task 008.6: a Ruby-level `$stdout`/`STDOUT` swap alone (what Task 008.5
# did) doesn't stop a native extension writing straight to file
# descriptor 1, or a child process that inherits fd 1 by default. boot.rb
# now redirects fd 1 itself before requiring this file, so all three of
# the following must land on stderr, not corrupt the protocol pipe.
begin
  raw_fd1 = IO.for_fd(1, autoclose: false)
  raw_fd1.syswrite("accidental raw fd1 write via IO.for_fd(1)\n")
rescue StandardError => e
  warn "IO.for_fd(1) probe failed: #{e.class}: #{e.message}"
end

system("echo", "accidental stdout from a child process via system(...)")
# Open3.capture2 pipes the child's stdout back to us rather than letting
# it inherit fd 1, so it can't corrupt the protocol either way -- this
# only proves boot doesn't crash when the target app happens to use it.
Open3.capture2("echo", "accidental stdout from a child process via Open3")

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

