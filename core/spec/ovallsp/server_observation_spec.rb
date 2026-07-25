# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server runtime observation (Task 019)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:fixtures_root) { File.expand_path("../fixtures/observation_runner", __dir__) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string, workspace_root: fixtures_root)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger, workspace_root: workspace_root)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  it "runs the configured test command and makes its evidence available via showTypeEvidence" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    run_result = sent_messages.find { |m| m[:id] == 2 }[:result]
    expect(run_result[:methodCount]).to be >= 1

    evidence = sent_messages.find { |m| m[:id] == 3 }[:result]
    expect(evidence).not_to be_nil
    expect(evidence[:parameterTypes]).to eq(%w[Integer Integer])
    expect(evidence[:returnType]).to eq("Integer")
    expect(evidence[:confidence]).to eq("low")
  end

  it "returns nil from showTypeEvidence when nothing has been observed" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 2 }[:result]).to be_nil
  end

  it "clears observed evidence via clearObservedTypes" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/clearObservedTypes", params: nil) +
      frame(jsonrpc: "2.0", id: 4, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 4 }[:result]).to be_nil
  end

  # Found by an independent review (round 7) of Task 022.2. Round 6 made
  # Runner#run honour its "never raises" contract by returning an empty
  # array for a run that couldn't even start -- which Server then fed
  # straight into Store#replace_run, a *full generation swap*. So a
  # workspace renamed while the editor is open, or a test command that
  # simply fails to boot, silently destroyed every signature the user had
  # accumulated, reported as a perfectly ordinary `methodCount: 0`. Runner
  # now distinguishes "no outcome" (nil) from "ran, observed nothing"
  # ([]), and Server only installs the latter.
  it "keeps previously observed evidence when a later run fails outright" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "crash.rb"] }) +
      frame(jsonrpc: "2.0", id: 4, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 2 }[:result][:methodCount]).to be >= 1
    expect(sent_messages.find { |m| m[:id] == 3 }[:result]).to eq(sampleCount: 0, methodCount: 0)

    evidence = sent_messages.find { |m| m[:id] == 4 }[:result]
    expect(evidence).not_to be_nil
    expect(evidence[:parameterTypes]).to eq(%w[Integer Integer])
  end

  # Found by an independent review (round 8) of Task 022.2: the same
  # store-destroying conflation as the test above, through the one door
  # round 7 left open. A test command that exits *zero* without the
  # harness ever writing a result file -- an ordinary non-Ruby test
  # command, a wrapper that re-execs with a sanitized env, a Spring-style
  # preloader (here: a fixture that skips at_exit) -- left a zero-byte
  # result file, which Runner read as a trusted `[]`. The clean exit means
  # no exit-status check could catch it, so Server did a full generation
  # swap and wiped every accumulated signature.
  it "keeps previously observed evidence when a later run exits cleanly without the harness ever running" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "no_harness_output.rb"] }) +
      frame(jsonrpc: "2.0", id: 4, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 2 }[:result][:methodCount]).to be >= 1
    expect(sent_messages.find { |m| m[:id] == 3 }[:result]).to eq(sampleCount: 0, methodCount: 0)

    evidence = sent_messages.find { |m| m[:id] == 4 }[:result]
    expect(evidence).not_to be_nil
    expect(evidence[:parameterTypes]).to eq(%w[Integer Integer])
  end

  # The converse, so the fix above can't be "just never replace on a
  # small result": a run that genuinely completes having observed nothing
  # must still swap the store empty.
  it "clears previously observed evidence when a later run completes having observed nothing" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "no_observations.rb"] }) +
      frame(jsonrpc: "2.0", id: 4, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.find { |m| m[:id] == 2 }[:result][:methodCount]).to be >= 1
    expect(sent_messages.find { |m| m[:id] == 3 }[:result]).to eq(sampleCount: 0, methodCount: 0)
    expect(sent_messages.find { |m| m[:id] == 4 }[:result]).to be_nil
  end

  it "invalidates an observed method's evidence once its own source changes" do
    calculator_uri = Ovallsp::UriUtil.from_path(File.join(fixtures_root, "lib", "calculator.rb"))
    calculator_source = File.read(File.join(fixtures_root, "lib", "calculator.rb"))
    changed_source = calculator_source.sub("a + b", "a + b # comment, still 'add', still returns an Integer")

    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      did_open(calculator_uri, calculator_source) +
      frame(jsonrpc: "2.0", id: 2, method: "ovallsp/runObservedTests",
            params: { testCommand: ["ruby", "run_tests.rb"] }) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: calculator_uri, version: 2 },
          contentChanges: [{ text: changed_source }]
        }
      ) +
      frame(jsonrpc: "2.0", id: 3, method: "ovallsp/showTypeEvidence",
            params: { textDocument: { uri: calculator_uri }, position: { line: 3, character: 6 } }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    run_result = sent_messages.find { |m| m[:id] == 2 }[:result]
    expect(run_result[:methodCount]).to be >= 1

    evidence = sent_messages.find { |m| m[:id] == 3 }[:result]
    expect(evidence).to be_nil
  end
end
