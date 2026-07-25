# frozen_string_literal: true

require "stringio"

RSpec.describe "Rslsp::Server workspace trust gating" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:calls) { Queue.new }

  # Stands in for Rslsp::RailsBootstrap: records that it was asked to
  # start (and with what root), without actually spawning anything.
  let(:fake_bootstrap) do
    queue = calls
    Class.new do
      define_singleton_method(:start) do |root:, logger:, route_registry:, model_registry:, on_unavailable: nil|
        queue << { root: root, route_registry: route_registry, model_registry: model_registry }
      end
    end
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Rslsp::Server.new(
      input: StringIO.new(input_string), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: fake_bootstrap
    )
  end

  def sent_messages
    output.rewind
    reader = Rslsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Rslsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  it "starts the Runtime Agent bootstrap when the workspace is explicitly trusted" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize",
            params: { initializationOptions: { workspaceTrusted: true } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    call = calls.pop(timeout: 2)
    expect(call).not_to be_nil
    expect(call[:root]).to eq("/workspace")
  end

  it "does NOT start the Runtime Agent bootstrap when trust isn't communicated at all (fail-closed)" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(calls.pop(timeout: 0.3)).to be_nil
  end

  it "does NOT start the Runtime Agent bootstrap when the workspace is explicitly untrusted" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize",
            params: { initializationOptions: { workspaceTrusted: false } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(calls.pop(timeout: 0.3)).to be_nil
    expect(logger).to have_received(:warn).with(/workspace trust/)
  end

  it "still answers the initialize handshake immediately even when the bootstrap is slow" do
    slow_bootstrap = Class.new do
      define_singleton_method(:start) do |**|
        sleep 5
      end
    end

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize",
            params: { initializationOptions: { workspaceTrusted: true } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    server = Rslsp::Server.new(
      input: StringIO.new(input), output: output, logger: logger,
      workspace_root: "/workspace", agent_bootstrap: slow_bootstrap
    )

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.run
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    expect(elapsed).to be < 1.0
    expect(sent_messages.first).to include(id: 1)
  end
end
