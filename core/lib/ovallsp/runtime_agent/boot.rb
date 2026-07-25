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
# (docs/design/docs/04-runtime-agent.md section 4).
#
# A Ruby-level swap of `$stdout` and the `STDOUT` *constant* (what Task
# 008.5 did) only redirects Ruby code that goes through one of those two
# objects. It does nothing about:
#   - a C extension or native library writing directly to file descriptor
#     1 via write(2), bypassing every Ruby IO object entirely;
#   - a child process the target Rails app spawns (`system`, backticks,
#     `Open3`, `IO.popen`, ...), which inherits fd 1 by default and can
#     write straight into it for as long as it lives.
# Both still land in the real protocol pipe and corrupt Content-Length
# framing (docs/design/tasks/008.6-agent-and-index-hardening.md).
#
# The fix operates at the file-descriptor level instead of the Ruby-object
# level: dup fd 1 into a fresh (close-on-exec) descriptor we keep for our
# own protocol writes, then `reopen` STDOUT's *underlying fd 1* onto
# stderr's destination (a dup2(2, 1) under the hood). After this, fd 1
# itself — not just the `STDOUT` Ruby object — points at stderr, so any
# write to fd 1 from anywhere (Ruby, native code, or a child process that
# inherits it) is redirected, and no child spawned afterward can ever see
# the protocol pipe on fd 1 to begin with.
protocol_stdout = STDOUT.dup
protocol_stdout.close_on_exec = true # a spawned child must never inherit the protocol pipe

STDOUT.reopen(STDERR)
$stdout = STDERR

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

agent = Ovallsp::RuntimeAgent::Agent.new(
  input: $stdin,
  output: protocol_stdout,
  logger: ->(msg) { warn "[ovallsp-agent] #{msg}" }
)

exit(agent.run)
