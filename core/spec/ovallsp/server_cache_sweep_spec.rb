# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The sweep that removes abandoned cache generations does not run on the
# thread that answers requests.
#
# 0.2.1 put the OvalLSP version into the cache key, which is what makes an
# upgrade's fixes reach files whose bytes have not changed -- and which
# abandons every directory the previous build wrote. The sweep that
# reclaims them was called straight from `#start_cold_index`, on the
# `initialize` dispatch, so every request the editor sent afterwards
# queued behind it: 0.9 s per 1,000 directories, and the machine this
# sweep exists for had 28,643 of them (024.51).
#
# Nothing waits on it for an answer. The current generation's directory
# already exists, and removing *other* directories cannot change what
# this one reads.
#
# Asserted by thread identity rather than by elapsed time. The property is
# "the dispatch does not wait for it", and a clock would state that as a
# threshold this suite would then have to defend on a loaded machine.
RSpec.describe "Ovallsp::Server cache generation sweep" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  it "runs somewhere other than the thread that dispatched initialize" do
    sweep_thread = nil
    allow(Ovallsp::Cache::Store).to receive(:prune_generations) { sweep_thread = Thread.current }

    Dir.mktmpdir do |cache_home|
      Dir.mktmpdir do |workspace|
        input =
          frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
          frame(jsonrpc: "2.0", method: "initialized", params: {}) +
          frame(jsonrpc: "2.0", id: 2, method: "shutdown", params: nil) +
          frame(jsonrpc: "2.0", method: "exit", params: nil)

        with_cache_home(cache_home) do
          Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                              workspace_root: workspace).run
        end
      end
    end

    expect(Ovallsp::Cache::Store).to have_received(:prune_generations)
    expect(sweep_thread).not_to be_nil
    expect(sweep_thread).not_to eq(Thread.main)
  end

  # Off the dispatch thread is half of it. The other half is that
  # something reclaims it — an untracked thread deleting directories under
  # the user's cache root goes on running after `#run` returns, which is
  # precisely the leak `BackgroundTasks`' own header was written about
  # ("a leaked Runtime Agent bootstrap thread surviving past the end of
  # the RSpec example that spawned it"). Round 33 removed the
  # `track_thread` call and the whole suite stayed green.
  #
  # The sweep is made slow so that "finished on its own" and "reclaimed"
  # are different observations; without that, a fast sweep is dead either
  # way and the example cannot fail.
  it "is reclaimed rather than left running after the server returns" do
    sweep_thread = nil
    allow(Ovallsp::Cache::Store).to receive(:prune_generations) do
      sweep_thread = Thread.current
      sleep(5)
    end

    Dir.mktmpdir do |cache_home|
      Dir.mktmpdir do |workspace|
        input =
          frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
          frame(jsonrpc: "2.0", method: "initialized", params: {}) +
          frame(jsonrpc: "2.0", method: "exit", params: nil)

        with_cache_home(cache_home) do
          Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                              workspace_root: workspace, background_task_shutdown_timeout: 0.2).run
        end
      end
    end

    expect(sweep_thread).not_to be_nil
    expect(sweep_thread).not_to be_alive
  end

  def with_cache_home(dir)
    previous = ENV.fetch("XDG_CACHE_HOME", nil)
    ENV["XDG_CACHE_HOME"] = dir
    yield
  ensure
    ENV["XDG_CACHE_HOME"] = previous
  end
end
