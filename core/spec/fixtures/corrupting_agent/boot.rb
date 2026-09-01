#!/usr/bin/env ruby
# frozen_string_literal: true

# Simulates a Runtime Agent that answers agent/hello correctly and then
# emits one syntactically-invalid frame (a Content-Length header whose
# value isn't an integer) instead of a normal response. Used to test that
# AgentProcessManager's reader thread doesn't die silently on a StandardError
# other than EOF/IOError/EBADF -- it must still notify pending/future
# requests and let the Manager degrade to :static_only instead of getting
# stuck at :ready forever (docs/design/tasks/008.5-runtime-and-index-corrections.md).

require "json"
# The Core refuses an Agent whose protocol version differs from its
# own, so a stub that writes the number as a literal is refused the
# moment the protocol moves -- which is what 0.3.0's bump to 2 did
# to all three of these. Read from the Core's own constant, with a
# fallback for a stub run without it on the load path.
PROTOCOL_VERSION =
  begin
    require "ovallsp/runtime_agent/agent"
    Ovallsp::RuntimeAgent::Agent::PROTOCOL_VERSION
  rescue LoadError, NameError
    2
  end


def write_message(payload)
  json = JSON.generate(payload)
  $stdout.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
  $stdout.flush
end

write_message(
  jsonrpc: "2.0", id: 1,
  result: {
    protocolVersion: PROTOCOL_VERSION, agentVersion: "0.0.0", root: Dir.pwd, railsVersion: nil,
    rubyVersion: RUBY_VERSION, capabilities: {}
  }
)

$stdout.write("Content-Length: not-a-number\r\n\r\n")
$stdout.flush

sleep 10
