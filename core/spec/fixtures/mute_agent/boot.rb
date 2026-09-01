#!/usr/bin/env ruby
# frozen_string_literal: true

# An Agent that completes the handshake and then never answers anything
# else -- a busy application, not a dead one.
#
# The existing unresponsive_agent fixture never answers `agent/hello`, so
# the manager never reaches :ready and no request is ever made. This one
# is what a *request* timing out against a live Agent looks like, which is
# the case that decides whether one slow answer should be treated as proof
# the Agent is gone (024.R5).
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


buffer = +""
while (chunk = $stdin.read(1))
  buffer << chunk
  next unless buffer.end_with?("\r\n\r\n")

  length = buffer[/Content-Length: (\d+)/, 1].to_i
  body = $stdin.read(length)
  buffer = +""
  message = JSON.parse(body)
  next unless message["method"] == "agent/hello"

  result = {
    "protocolVersion" => PROTOCOL_VERSION, "agentVersion" => "0.0.0", "root" => Dir.pwd,
    "railsVersion" => nil, "rubyVersion" => RUBY_VERSION,
    "capabilities" => { "routes" => false, "activeRecord" => false, "reload" => false, "runtimePlugins" => false }
  }
  payload = JSON.generate("jsonrpc" => "2.0", "id" => message["id"], "result" => result)
  $stdout.write("Content-Length: #{payload.bytesize}\r\n\r\n#{payload}")
  $stdout.flush
end
