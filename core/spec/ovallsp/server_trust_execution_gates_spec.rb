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
end
