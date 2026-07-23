#!/usr/bin/env ruby
# frozen_string_literal: true

# Entry point for the Runtime Agent child process. In production this runs
# as `bundle exec ruby .../boot.rb start /absolute/path/to/config/environment.rb`
# — a plain Ruby process, deliberately NOT `bin/rails runner`. `rails
# runner` boots the whole Rails app, running every initializer, *before*
# handing control to the script it's told to run; by the time this file's
# own code got a chance to protect stdout, initializer output could
# already have corrupted the protocol stream. Requiring
# config/environment.rb ourselves, after the swap below, is what actually
# closes that window (docs/design/tasks/008.5-runtime-and-index-corrections.md).
#
# The capture-then-reassign order matters: stdout must be swapped out
# before any application code (Rails boot, initializers) gets a chance to
# run, or a stray `puts` could corrupt the protocol stream
# (docs/design/docs/04-runtime-agent.md section 4). Both the `$stdout`
# global *and* the `STDOUT` constant are redirected — some gems/frameworks
# write via the constant directly, which a `$stdout` reassignment alone
# wouldn't catch.
protocol_stdout = STDOUT
$stdout = $stderr
original_verbosity = $VERBOSE
$VERBOSE = nil # silence the "already initialized constant" warning below
Object.send(:remove_const, :STDOUT)
Object.const_set(:STDOUT, $stderr)
$VERBOSE = original_verbosity

require_relative "../version"
require_relative "agent"

command = ARGV.shift
unless command == "start"
  warn "runtime_agent boot: usage: boot.rb start [environment_file]"
  exit 1
end

environment_file = ARGV.shift
require environment_file if environment_file && !environment_file.empty?

$stdin.binmode
protocol_stdout.binmode
protocol_stdout.sync = true

agent = Rslsp::RuntimeAgent::Agent.new(
  input: $stdin,
  output: protocol_stdout,
  logger: ->(msg) { warn "[rslsp-agent] #{msg}" }
)

exit(agent.run)
