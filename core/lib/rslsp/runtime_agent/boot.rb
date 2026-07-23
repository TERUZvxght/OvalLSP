#!/usr/bin/env ruby
# frozen_string_literal: true

# Entry point for the Runtime Agent child process. In production this runs
# as `bundle exec bin/rails runner .../boot.rb start <environment_file>`
# inside the target app's own Ruby/Bundler environment; for tests it runs
# directly against a fixture. Real Rails support (Task 006+) will change how
# the environment gets loaded, not this stdout-protection sequence.
#
# The capture-then-reassign order matters: $stdout must be swapped out
# before any application code (Rails boot, initializers) gets a chance to
# run, or a stray `puts` could corrupt the protocol stream
# (docs/design/docs/04-runtime-agent.md section 4).
protocol_stdout = $stdout
$stdout = $stderr

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
