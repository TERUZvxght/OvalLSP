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

def write_message(payload)
  json = JSON.generate(payload)
  $stdout.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
  $stdout.flush
end

write_message(
  jsonrpc: "2.0", id: 1,
  result: {
    protocolVersion: 1, agentVersion: "0.0.0", root: Dir.pwd, railsVersion: nil,
    rubyVersion: RUBY_VERSION, capabilities: {}
  }
)

$stdout.write("Content-Length: not-a-number\r\n\r\n")
$stdout.flush

sleep 10
