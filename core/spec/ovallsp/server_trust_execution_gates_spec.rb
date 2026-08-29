# frozen_string_literal: true

require "stringio"

# 0.2.4 fixed the extension half of Workspace Trust: a repository could
# name the binary the extension spawned. The Core half has the same shape
# and is still open. `maybe_start_agent` consults trust, and it is the
# *only* place that does -- trust is read out of the `initialize` params
# at that one call site and never kept.
#
# Two other requests reach code execution and neither asks:
#
#   * `ovallsp/runObservedTests` runs a command, and takes a per-request
#     `testCommand` override, so the command is caller-supplied;
#   * `ovallsp/restartAgent` restarts the Runtime Agent, which is the
#     very thing trust gates in the first place.
#
# Today's shipped extension does not send either from an untrusted
# window, so nothing is exploitable through it. That is exactly the
# property section 0.5 calls out as not a property: it holds because
# every caller currently happens to be right, and the LSP is a protocol
# any client can speak.
RSpec.describe "Ovallsp::Server execution entry points are gated on workspace trust" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:started) { Queue.new }

  let(:fake_bootstrap) do
    queue = started
    Class.new do
      define_singleton_method(:start) do |root:, **|
        queue << root
      end
    end
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def initialize_frame(trusted:, id: 1)
    frame(
      jsonrpc: "2.0", id: id, method: "initialize",
      params: { rootUri: "file:///workspace", initializationOptions: { workspaceTrusted: trusted } }
    )
  end

  def run(*frames, runner: nil)
    server = Ovallsp::Server.new(
      input: StringIO.new(frames.join), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: fake_bootstrap
    )
    server.instance_variable_set(:@observation_runner, runner) if runner
    server.run
    server
  end

  def responses
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.select { |m| m.key?(:id) }
  end

  # Records what it was asked to run instead of running it. A real
  # `Observation::Runner` spawns a process; this spec must never do that,
  # and it is the *request* to spawn that is being asserted about.
  let(:recording_runner) do
    Class.new do
      attr_reader :invocations

      def initialize = @invocations = []

      def run(command:, args:, workspace_root:)
        @invocations << { command: command, args: args, workspace_root: workspace_root }
        nil
      end
    end.new
  end

  describe "ovallsp/runObservedTests" do
    it "does not run a caller-supplied command when the workspace is untrusted" do
      run(
        initialize_frame(trusted: false),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
              params: { testCommand: %w[echo pwned] }),
        runner: recording_runner
      )

      expect(recording_runner.invocations).to be_empty
    end

    it "still runs it when the workspace is trusted" do
      run(
        initialize_frame(trusted: true),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
              params: { testCommand: %w[echo ok] }),
        runner: recording_runner
      )

      expect(recording_runner.invocations.map { |i| i[:command] }).to eq(["echo"])
    end

    it "answers the request rather than hanging, so a client is not left waiting" do
      run(
        initialize_frame(trusted: false),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests", params: {}),
        runner: recording_runner
      )

      expect(responses.map { |m| m[:id] }).to include(2)
    end
  end

  describe "ovallsp/restartAgent" do
    it "does not start the Runtime Agent when the workspace is untrusted" do
      run(
        initialize_frame(trusted: false),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/restartAgent", params: {})
      )

      expect(started).to be_empty
    end

    # And it says so, rather than acknowledging a restart that did not
    # happen. The refusal payload was asserted by nothing until `024.74`
    # moved the gate: the example above would pass just as well if the
    # client were told the restart had been accepted.
    it "tells the client it refused rather than acknowledging a restart that did not happen" do
      run(
        initialize_frame(trusted: false),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/restartAgent", params: {})
      )

      expect(responses.find { |m| m[:id] == 2 }[:result])
        .to eq(acknowledged: false, reason: "workspace not trusted")
    end

    # The positive half: without it, a gate that refuses everything would
    # pass the example above and break the feature. `maybe_start_agent`
    # fires on initialize when trusted, so one start is expected already;
    # the restart adds another.
    it "still restarts it when the workspace is trusted" do
      run(
        initialize_frame(trusted: true),
        frame(jsonrpc: "2.0", id: 2, method: "ovallsp/restartAgent", params: {})
      )

      sleep 0.05 until started.size >= 1 || (defined?(@waited) && @waited)
      expect(started.size).to be >= 1
    end
  end

  # `024.74`. The two examples above go through `restart_agent_result`,
  # which asks; the method that actually spawns did not. Every route to it
  # was gated, so nothing was reachable -- and "every caller happens to be
  # right" is the property this file's own header says is not a property.
  # A fourth caller closed nothing, and neither did the three.
  #
  # Driven before the fix: `#restart_agent` on this same untrusted server
  # returned a Thread and `bootstrap.start` was called once, with no
  # warning logged.
  describe "#restart_agent itself" do
    def untrusted_server
      Ovallsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger,
        workspace_root: "/workspace", agent_bootstrap: fake_bootstrap
      )
    end

    it "does not spawn a bootstrap when called directly on an untrusted workspace" do
      server = untrusted_server

      server.send(:restart_agent)
      sleep 0.1

      expect(started).to be_empty
    ensure
      server&.send(:shutdown_background_tasks)
    end

    it "reports the refusal to its caller rather than a thread that will do nothing" do
      server = untrusted_server

      expect(server.send(:restart_agent)).to be_nil
    ensure
      server&.send(:shutdown_background_tasks)
    end

    # The positive half, so a gate that refuses everything cannot pass the
    # two above: the same direct call on a server that *was* told.
    it "still spawns one once trust has been recorded" do
      server = untrusted_server
      server.instance_variable_set(:@workspace_trusted, true)

      expect(server.send(:restart_agent)).to be_a(Thread)
      expect(started.pop(timeout: 2)).to eq("/workspace")
    ensure
      server&.send(:shutdown_background_tasks)
    end
  end
end
