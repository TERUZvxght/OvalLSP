#!/usr/bin/env ruby
# frozen_string_literal: true

# An Agent that completes the handshake, ignores `agent/shutdown`, and
# ignores SIGTERM -- so the only thing that can end it is the SIGKILL
# escalation in `AgentProcessManager#force_kill`.
#
# `024.268`. `#force_kill` was reached by no example in the manager's own
# spec file, and the example whose comment claims to drive it -- "still
# tears down its pipes, reader thread and pid when the TERM signal itself
# fails to land" -- passed for a different reason: `#stop` sends
# `agent/shutdown` before the teardown, the `rails_minimal` fixture Agent
# obliges and exits, and `#wait_for_exit`'s first `WNOHANG` reaps the
# corpse. `wait_for_exit(2) || force_kill` then short-circuits. Replacing
# `#force_kill`'s first statement with a `raise` left the file green.
#
# `mute_agent` is not enough on its own: it ignores `agent/shutdown` but
# dies on the default SIGTERM handler, so the escalation is still not
# reached. Trapping TERM is the half that makes this fixture
# distinguishing -- if the process is gone at the end of the example,
# SIGKILL is the only thing that can have ended it.
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


Signal.trap("TERM") { nil }

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
