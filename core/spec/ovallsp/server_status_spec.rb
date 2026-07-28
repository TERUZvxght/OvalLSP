# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe "Ovallsp::Server environment status (Task 020)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  # Same polling helper server_cold_index_spec.rb uses -- Cold Index runs
  # on its own background thread, so "not indexing anymore" can't be
  # asserted immediately after #initialize returns.
  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield

      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "reports ready-static once Cold Index finishes with no Runtime Agent ever attempted (untrusted/non-Rails workspace)" do
    Dir.mktmpdir do |root|
      server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: root)
      server.send(:start_cold_index)

      wait_until { server.send(:status_result, nil) != { state: "indexing" } }

      expect(server.send(:status_result, nil)).to eq(state: "ready-static")
    end
  end

  it "reports ready-rails when the Runtime Agent is live and responding" do
    server = build_server(frame(jsonrpc: "2.0", method: "exit", params: nil))
    agent_manager = instance_double(Ovallsp::AgentProcessManager, ready?: true)
    server.instance_variable_set(:@agent_manager, agent_manager)

    expect(server.send(:status_result, nil)).to eq(state: "ready-rails")
  end

  it "reports agent-unavailable when a Runtime Agent bootstrap was attempted but isn't responding" do
    server = build_server(frame(jsonrpc: "2.0", method: "exit", params: nil))
    agent_manager = instance_double(Ovallsp::AgentProcessManager, ready?: false)
    server.instance_variable_set(:@agent_manager, agent_manager)

    expect(server.send(:status_result, nil)).to eq(state: "agent-unavailable")
  end

  it "reports indexing while Cold Index is still running" do
    server = build_server(frame(jsonrpc: "2.0", method: "exit", params: nil))
    server.instance_variable_set(:@cold_indexing, true)

    expect(server.send(:status_result, nil)).to eq(state: "indexing")
  end

  it "acknowledges ovallsp/restartAgent without raising, even with no Agent bootstrap configured" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/restartAgent", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input).run }.not_to raise_error
    expect(sent_messages.find { |m| m[:id] == 2 }[:result]).to eq(acknowledged: true)
  end

  it "cancels a scheduled automatic retry when a manual restart is requested" do
    server = build_server("")
    server.instance_variable_set(
      :@agent_supervisor,
      Ovallsp::AgentSupervisor.new(max_attempts: 2, base_delay_seconds: 0.05, max_delay_seconds: 0.05)
    )
    restart_count = 0
    server.define_singleton_method(:restart_agent) { restart_count += 1 }

    server.send(:handle_agent_unavailable, "test crash")
    server.send(:restart_agent_result, nil)
    sleep 0.1

    expect(restart_count).to eq(1)
  ensure
    server&.instance_variable_get(:@background_tasks)&.shutdown
  end

  it "acknowledges ovallsp/reindexWorkspace" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/reindexWorkspace", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 2 }[:result]).to eq(acknowledged: true)
  end

  it "removes disk-indexed files that disappeared before a manual reindex" do
    Dir.mktmpdir do |root|
      path = File.join(root, "widget.rb")
      File.write(path, "class Widget\nend\n")
      server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, workspace_root: root)
      symbol = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil)

      server.send(:start_cold_index)
      expect(wait_until { !server.instance_variable_get(:@workspace_index).declarations(symbol).empty? }).to be(true)
      expect(wait_until { !server.instance_variable_get(:@cold_indexing) }).to be(true)

      File.delete(path)
      server.send(:start_cold_index)
      expect(wait_until { !server.instance_variable_get(:@cold_indexing) }).to be(true)

      expect(server.instance_variable_get(:@workspace_index).declarations(symbol)).to be_empty
    ensure
      server&.instance_variable_get(:@background_tasks)&.shutdown
    end
  end
end
