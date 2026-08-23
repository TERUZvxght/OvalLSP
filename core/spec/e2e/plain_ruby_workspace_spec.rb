# frozen_string_literal: true

require_relative "lsp_client"

# `024.134`. The first e2e example pointed at a workspace that is not a
# Rails app.
#
# Every other example in this directory drives `spec/fixtures/rails_real`,
# which is why this sat unnoticed: `LspClient#wait_until_ready` accepted
# only `ready` and `ready-rails`. Core reports four states —
# `indexing`, `ready-rails`, `agent-unavailable`, `ready-static`
# (`Server#status_result`) — and **`ready` is not among them**; a grep of
# `core/lib` finds it nowhere. `ready-rails` is reached only by a
# workspace that boots a Runtime Agent. So a plain Ruby workspace
# settles in milliseconds and the helper waits out its entire 120-second
# budget before returning what it already had.
#
# Needs no Rails and no sqlite3, unlike `capabilities_spec.rb`, so it
# runs wherever the suite runs.
RSpec.describe "a workspace that is not a Rails app", :e2e do
  it "reaches its ready state without waiting out the timeout" do
    root = example_tmpdir("ovallsp-plain-ruby")
    File.write(File.join(root, "greeter.rb"), <<~SOURCE)
      class Greeter
        def greet(name) = "hi \#{name}"
      end
    SOURCE

    client = E2E::LspClient.new(root)
    begin
      # Trusted deliberately: what makes this workspace static is that
      # there is no Rails app in it, not that permission was withheld.
      client.initialize!(trusted: true)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      state = client.wait_until_ready(agent: false, timeout: 30)
      waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(state).to eq("ready-static")
      expect(waited).to be < 15,
                        "wait_until_ready spent #{waited.round(1)}s of a 30s budget on a workspace " \
                        "that was already ready-static"
      # Not an early return *too* soon: the cold index has finished and
      # the workspace answers.
      expect(client.workspace_symbols("Greeter")).to include("Greeter")
    ensure
      client.stop
    end
  end

  # A separate example, because a default would leave this half untested.
  # Every existing caller passes `agent: true`, so defaulting to `true`
  # keeps the whole suite green while handing the next non-Rails caller
  # the timeout this entry is about. `keyreq` is the difference between
  # "the caller may say" and "the caller must".
  it "will not let a caller leave the Runtime Agent question unanswered" do
    expect(E2E::LspClient.instance_method(:wait_until_ready).parameters).to include(%i[keyreq agent])
  end
end
