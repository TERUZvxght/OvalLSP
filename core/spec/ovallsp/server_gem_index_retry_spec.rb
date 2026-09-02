# frozen_string_literal: true

require "stringio"
require "logger"

# **One failed fetch turned the gem index off for the rest of the
# session.** `#ensure_gem_index` set `@gem_index_loaded = true` *before*
# calling `#load_gem_index`, and `#load_gem_index` returns quietly when
# the payload is nil — which is what a slow or busy Agent gives back. So
# a single timeout at boot left `@gem_index` empty and the guard refusing
# to try again, and 0.3.0's whole gem-backed undefined-method check
# (G18/G19) was off until the editor was restarted.
#
# Found by the 0.3.0 review workflow, which recorded it as "real, cheap
# and in scope" and ran out of pass before fixing it.
#
# The flag means "this session has an index", so it is set when there is
# one. A nil payload is now logged rather than swallowed: the layer above
# is the one that can try again, and it cannot if nothing tells it.
RSpec.describe "Ovallsp::Server and a gem index fetch that comes back empty" do
  let(:logger_output) { StringIO.new }
  let(:logger) { Logger.new(logger_output) }

  # A manager that answers nil the first time and a payload the second,
  # which is exactly a timeout followed by a healthy Agent.
  let(:manager) do
    answers = [nil, { "gems" => { "widget" => { "classes" => [
      { "name" => "Widget::Base", "ancestors" => %w[Widget::Base Object], "instanceMethods" => %w[persist],
        "singletonMethods" => [], "definesMethodMissing" => false }
    ] } } }]
    double = Object.new
    double.define_singleton_method(:fetch_gem_index) { answers.shift }
    double.define_singleton_method(:ready?) { true }
    # `#restart_agent` stops the old manager before it resets anything;
    # a double without this dies on the restart thread and the example
    # below then fails for the wrong reason.
    double.define_singleton_method(:stop) { nil }
    double
  end

  let(:server) do
    Ovallsp::Server.new(input: StringIO.new(""), output: StringIO.new, logger: logger, workspace_root: Dir.pwd)
  end

  before do
    server.instance_variable_set(:@agent_manager, manager)
    allow(server).to receive(:agent_manager_ready?).and_return(true)
  end

# The restart runs on its own thread, so the assertion has to outlive
# the call rather than the statement after it.
def wait_until(timeout: 3)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    return true if yield
    return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep 0.02
  end
end

  def gem_index_size
    server.instance_variable_get(:@gem_index)&.size.to_i
  end

  it "tries again after a fetch that answers nothing" do
    server.send(:ensure_gem_index)
    expect(gem_index_size).to eq(0), "the first fetch answered nil, so there is no index yet"

    server.send(:ensure_gem_index)

    expect(gem_index_size).to eq(1),
                              "a second call must fetch again; one timeout used to disable the check for the session"
  end

  # **The control.** A server that fetched on every call would also pass
  # the example above, and would ask the Agent for its whole object space
  # on every document open. Once there is an index, the question stops
  # being asked.
  it "stops asking once it has one" do
    server.send(:ensure_gem_index)
    server.send(:ensure_gem_index)
    expect(gem_index_size).to eq(1)

    server.send(:ensure_gem_index)

    expect(gem_index_size).to eq(1), "a third call must not re-fetch: `answers` is empty and would give nil"
  end

# **A restart replaces the application, and the gem index is a fact about
# the one that is gone.**
#
# `#restart_agent` resets `@ancestry_registry` under a comment that makes
# the argument in full -- "what comes back may be a different Gemfile, a
# different environment, and answering from the old process would be
# answering about an application that no longer exists". The gem index is
# the same kind of fact from the same process and was not reset, so a
# `bundle install` -- which `#classify_change` routes to a restart --
# left the old gem's method sets answering for the new one.
#
# Driven before the fix, with the fresh index as the control:
#
#     FRESH: ["MyCtl has no method named `definitely_not_a_method_either`"]
#     STALE: ["MyCtl has no method named `performed?`",
#             "MyCtl has no method named `definitely_not_a_method_either`"]
#
# `performed?` exists in the gems that came back; the held index predates
# them. That is a false report on code that runs, which section 0 ranks
# below saying nothing -- and `KNOWN_LIMITATIONS` told users in both
# languages that nothing is reported wrongly while the index is missing.
it "forgets the gem index when the Agent restarts" do
  server.send(:ensure_gem_index)
  server.send(:ensure_gem_index)
  expect(gem_index_size).to eq(1), "the fixture must have an index to forget, or this asserts nothing"

  # Since `024.74` trust is asked in front of the spawn, and a server
  # built here has handled no `initialize` to be told.
  server.instance_variable_set(:@workspace_trusted, true)
  server.send(:restart_agent)

  expect(wait_until { gem_index_size.zero? }).to be(true),
                                                 "the index survived a restart, so it describes an application " \
                                                 "that is gone"
  expect(server.instance_variable_get(:@gem_index_loaded)).to be_falsey,
                                                             "the flag still says this session has an index"
end

  it "says so in the log rather than swallowing the empty answer" do
    server.send(:ensure_gem_index)

    expect(logger_output.string).to include("gem index")
  end
end
