# frozen_string_literal: true

require "timeout"
require_relative "../unit_spec_helper"
require_relative "../test_hygiene"

RSpec.describe "Ovallsp::Server diagnostics configuration" do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:document_uri) { "file:///workspace/test.rb" }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  # A real server on a real pipe, driven one message at a time.
  #
  # One frame is written and its publish waited for before the next frame
  # is written, because `Server#run` analyses "once nothing else is
  # waiting to be read" (037's C9): every frame written in one go can
  # legitimately be answered by a single analysis, and an example about
  # what a *second* setting produced would then be reading the first
  # one's answer. Waiting on the notification rather than on a duration is
  # also what keeps these examples off the clock -- nothing here sleeps,
  # and no elapsed time is asserted.
  def start_server(init_options, root_uri: "file:///workspace")
    @in_read, @in_write = ::IO.pipe
    @out_read, @out_write = ::IO.pipe
    server = Ovallsp::Server.new(input: @in_read, output: @out_write, logger: logger)
    @server_thread = Thread.new do
      server.run
    ensure
      @out_write.close
    end
    @reader = Ovallsp::IO::FramedReader.new(@out_read)
    @published = []
    send_message(jsonrpc: "2.0", id: 1, method: "initialize",
                 params: { rootUri: root_uri, initializationOptions: init_options })
  end

  def send_message(hash)
    @in_write.write(frame(hash))
  end

  def did_open(source, version: 1, uri: document_uri)
    send_message(jsonrpc: "2.0", method: "textDocument/didOpen",
                 params: { textDocument: { uri: uri, text: source, version: version, languageId: "ruby" } })
  end

  def did_close(uri: document_uri)
    send_message(jsonrpc: "2.0", method: "textDocument/didClose", params: { textDocument: { uri: uri } })
  end

  # The published wire shape: `workspace/didChangeConfiguration` carries a
  # full settings snapshot, and the server reads
  # `settings.ovallsp.diagnostics.severities` out of it.
  def change_severities(severities)
    send_message(jsonrpc: "2.0", method: "workspace/didChangeConfiguration",
                 params: { settings: { ovallsp: { diagnostics: { severities: severities } } } })
  end

  def change_settings(settings)
    send_message(jsonrpc: "2.0", method: "workspace/didChangeConfiguration", params: { settings: settings })
  end

  def await_publish(timeout: 10)
    Timeout.timeout(timeout) do
      loop do
        message = @reader.read_message
        next unless message[:method] == "textDocument/publishDiagnostics"

        @published << message
        return message
      end
    end
  end

  # Ends the session and returns every publish of it, including any that
  # arrived after the last `await_publish` -- so an example that expects a
  # notification to have produced *nothing* can still say so by counting.
  def finish_server
    send_message(jsonrpc: "2.0", method: "exit", params: nil)
    @in_write.close
    Timeout.timeout(10) do
      loop do
        message = @reader.read_message
        @published << message if message[:method] == "textDocument/publishDiagnostics"
      end
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    @server_thread.value
    @published
  end

  def with_server(init_options = {}, root_uri: "file:///workspace")
    start_server(init_options, root_uri: root_uri)
    yield
    finish_server
  end

  after do
    @in_write.close if @in_write && !@in_write.closed?
    @server_thread&.join(5)
    @server_thread&.kill if @server_thread&.alive?
    [@in_read, @out_read, @out_write].compact.each { |io| io.close unless io.closed? }
  end

  def run_server_with_options(init_options, source, did_change_settings: nil)
    with_server(init_options) do
      did_open(source)
      # Establish the initial publish before changing settings; a buffered
      # batch can legitimately coalesce both states into one analysis.
      await_publish
      change_settings(did_change_settings) if did_change_settings
    end
  end

  def codes_of(message)
    message.fetch(:params).fetch(:diagnostics).map { |d| d[:code] }
  end

  def reported(messages)
    messages.map { |m| [m[:params][:version], m[:params][:diagnostics].map { |d| [d[:code], d[:severity]] }] }
  end

  let(:source_with_unresolved_const) do
    <<~RUBY_INNER
      class Foo
        def bar
          MissingConstant.new
        end
      end
    RUBY_INNER
  end

  let(:source_with_unknown_method) do
    <<~RUBY_INNER
      class Bar
        def run
          baz
        end
      end
    RUBY_INNER
  end

  # The same call, in a class body whose final `end` is missing. Ruby
  # cannot parse it, so what a broken tree would say about `baz` is not
  # something this server may report -- switching the syntax diagnostic
  # off does not make the tree parseable.
  let(:source_that_does_not_parse) do
    <<~RUBY_INNER
      class Bar
        def run
          baz
        end
    RUBY_INNER
  end

  it "does not report unresolved-constant in default :safe mode" do
    published = run_server_with_options({}, source_with_unresolved_const)
    diagnostics = published.last.fetch(:params).fetch(:diagnostics)
    codes = diagnostics.map { |d| d[:code] }
    expect(codes).not_to include("unresolved-constant")
  end

  it "reports unresolved-constant when diagnosticsMode is standard" do
    published = run_server_with_options({ diagnosticsMode: "standard" }, source_with_unresolved_const)
    diagnostics = published.last.fetch(:params).fetch(:diagnostics)
    codes = diagnostics.map { |d| d[:code] }
    expect(codes).to include("unresolved-constant")
  end

  it "suppresses a diagnostic when configured severity is none" do
    init_opts = { diagnosticSeverities: { "unknown-method" => "none" } }
    published = run_server_with_options(init_opts, source_with_unknown_method)
    diagnostics = published.last.fetch(:params).fetch(:diagnostics)
    codes = diagnostics.map { |d| d[:code] }
    expect(codes).not_to include("unknown-method")
  end

  it "rejects escalation from warning to error" do
    init_opts = { diagnosticSeverities: { "unknown-method" => "error" } }
    published = run_server_with_options(init_opts, source_with_unknown_method)
    diagnostics = published.last.fetch(:params).fetch(:diagnostics)
    diag = diagnostics.find { |d| d[:code] == "unknown-method" }
    expect(diag).not_to be_nil
    expect(diag[:severity]).to eq(2)
  end

  it "maps severity to hint (4) when configured" do
    init_opts = { diagnosticSeverities: { "unknown-method" => "hint" } }
    published = run_server_with_options(init_opts, source_with_unknown_method)
    diagnostics = published.last.fetch(:params).fetch(:diagnostics)
    diag = diagnostics.find { |d| d[:code] == "unknown-method" }
    expect(diag).not_to be_nil
    expect(diag[:severity]).to eq(4)
  end

  it "updates the same document version from configuration alone" do
    published = run_server_with_options(
      {},
      source_with_unknown_method,
      did_change_settings: {
        ovallsp: {
          diagnostics: {
            severities: { "unknown-method" => "hint" }
          }
        }
      }
    )
    expect(published.map { |m| m[:params][:version] }).to eq([1, 1])
    expect(published.first[:params][:diagnostics].find { |d| d[:code] == "unknown-method" }[:severity]).to eq(2)
    last_diag = published.last[:params][:diagnostics].find { |d| d[:code] == "unknown-method" }
    expect(last_diag).not_to be_nil
    expect(last_diag[:severity]).to eq(4)
  end

  it "refreshes closed-file diagnostics on downgrade, suppression and reset without editing the file" do
    root = example_tmpdir("ovallsp-closed-settings")
    path = File.join(root, "closed.rb")
    File.write(path, source_with_unknown_method)
    uri = Ovallsp::UriUtil.from_path(path)
    with_server({}, root_uri: Ovallsp::UriUtil.from_path(root)) do
      initial = await_publish
      expect(initial.dig(:params, :uri)).to eq(uri)
      expect(initial.dig(:params, :version)).to be_nil
      expect(initial.dig(:params, :diagnostics).map { |d| [d[:code], d[:severity]] }).to eq([["unknown-method", 2]])

      [["hint", 4], ["none", nil], [nil, 2]].each do |severity, expected|
        change_severities(severity ? { "unknown-method" => severity } : {})
        updated = await_publish
        expect(updated.dig(:params, :uri)).to eq(uri)
        expect(updated.dig(:params, :version)).to be_nil
        expect(updated.dig(:params, :diagnostics).map { |d| [d[:code], d[:severity]] })
          .to eq(expected ? [["unknown-method", expected]] : [])
      end
    end
  end
  it "ignores an unresolved-constant opt-in in initialization options" do
    messages = run_server_with_options(
      { diagnosticSeverities: { "unresolved-constant" => "hint" } }, source_with_unresolved_const
    )
    expect(messages.last[:params][:diagnostics].map { |d| d[:code] }).not_to include("unresolved-constant")
  end

  it "resets overrides when severities are removed from a diagnostics snapshot" do
    messages = run_server_with_options(
      { diagnosticSeverities: { "unknown-method" => "hint" } }, source_with_unknown_method,
      did_change_settings: { ovallsp: { diagnostics: {} } }
    )
    expect(messages.map { |m| m[:params][:version] }).to eq([1, 1])
    expect(messages.last[:params][:diagnostics].find { |d| d[:code] == "unknown-method" }[:severity]).to eq(2)
  end

  it "does not change mode or enable unresolved constants through a configuration notification" do
    messages = run_server_with_options(
      {}, source_with_unresolved_const,
      did_change_settings: { ovallsp: { diagnostics: { mode: "standard", severities: { "unresolved-constant" => "hint" } } } }
    )
    expect(messages.flat_map { |m| m[:params][:diagnostics] }.map { |d| d[:code] }).not_to include("unresolved-constant")
  end

  it "ignores unrelated and malformed settings without reanalysis" do
    [{ unrelated: true }, { ovallsp: false }, { ovallsp: { diagnostics: [] } }].each do |settings|
      messages = run_server_with_options({}, source_with_unknown_method, did_change_settings: settings)
      expect(messages.length).to eq(1)
      expect(messages.first[:params][:diagnostics].map { |d| d[:code] }).to include("unknown-method")
    end
  end

  it "ignores the unpublished singular initialization alias" do
    messages = run_server_with_options(
      { diagnosticSeverity: { "unknown-method" => "none" } }, source_with_unknown_method
    )
    expect(messages.last[:params][:diagnostics].map { |d| d[:code] }).to include("unknown-method")
  end

  # Task 064, P2's "動的変更と競合", over the real transport: a setting is
  # a snapshot the client resends in full, so switching a check off and
  # putting it back is two notifications and the server has to answer both
  # without the buffer moving. These examples never send a `didChange`;
  # the document is opened once at version 1 and stays there, so every
  # publish after the first is the configuration's doing and nothing
  # else's.
  describe "a setting that changes while the document does not" do
    it "restores a suppressed diagnostic when the setting is removed" do
      messages = with_server do
        did_open(source_with_unknown_method)
        await_publish
        change_severities({ "unknown-method" => "none" })
        await_publish
        # The published contract for switching a check back on is removing
        # its entry, not naming a severity: `none` is undone by returning
        # to the default, and there is no "on" value to send.
        change_settings({ ovallsp: { diagnostics: {} } })
        await_publish
      end

      expect(reported(messages)).to eq([[1, [["unknown-method", 2]]], [1, []], [1, [["unknown-method", 2]]]])
    end

    # A → B → A with a non-default A, so that returning to it is visible
    # in the payload rather than only in the count: the client ends
    # holding the `hint` it asked for, computed after the `none` in the
    # middle, not the one published before it.
    it "returns to the first value after a change and back again" do
      messages = with_server do
        did_open(source_with_unknown_method)
        await_publish
        change_severities({ "unknown-method" => "hint" })
        await_publish
        change_severities({ "unknown-method" => "none" })
        await_publish
        change_severities({ "unknown-method" => "hint" })
        await_publish
      end

      expect(reported(messages).map(&:last)).to eq([[["unknown-method", 2]], [["unknown-method", 4]], [],
                                                    [["unknown-method", 4]]])
      expect(messages.map { |m| m[:params][:version] }).to eq([1, 1, 1, 1])
    end

    # **Switching the syntax diagnostic off suppresses output; it does not
    # make a broken tree analysable.** The file below is missing its final
    # `end`, and the `baz` inside it is the same call the control example
    # reports as `unknown-method` when the file parses -- so if the
    # semantic checks ran on the broken tree, this would report it.
    it "does not report a semantic diagnostic from a tree that does not parse when syntax-error is none" do
      messages = with_server do
        did_open(source_that_does_not_parse)
        await_publish
        change_severities({ "syntax-error" => "none" })
        await_publish
      end

      expect(codes_of(messages.first)).to eq(%w[syntax-error syntax-error])
      expect(codes_of(messages.last)).to eq([])
    end

    # The control for the example above: the same call, in a file that
    # parses, with the syntax diagnostic switched off in exactly the same
    # way. Without it, an engine that reported nothing at all under
    # `syntax-error: none` would satisfy that example.
    it "still reports a semantic diagnostic in a file that parses when syntax-error is none" do
      messages = with_server({ diagnosticSeverities: { "syntax-error" => "none" } }) do
        did_open(source_with_unknown_method)
        await_publish
      end

      expect(codes_of(messages.last)).to eq(["unknown-method"])
    end

    # A notification the schema would never produce still arrives from
    # anything that is not the shipped client, and the session has to
    # survive it: the malformed one is ignored and the *next* valid one is
    # applied. Counting the publishes is what says the malformed
    # notification produced no analysis of its own.
    it "applies a valid change that follows a malformed one" do
      messages = with_server do
        did_open(source_with_unknown_method)
        await_publish
        change_severities("off")
        change_severities({ "unknown-method" => 4 })
        change_severities({ "unknown-method" => "none" })
        await_publish
      end

      expect(reported(messages)).to eq([[1, [["unknown-method", 2]]], [1, []]])
    end

    # Closing a buffer clears its diagnostics and forgets its version; it
    # does not forget the setting. The reopened buffer -- a new one, at
    # whatever version the editor chooses -- gets the answer the setting
    # in force now asks for, and removing the setting brings the finding
    # back for that new buffer.
    it "clears on close and regenerates the reopened buffer under the setting in force" do
      messages = with_server do
        did_open(source_with_unknown_method)
        await_publish
        change_severities({ "unknown-method" => "none" })
        await_publish
        did_close
        await_publish
        did_open(source_with_unknown_method, version: 5)
        await_publish
        change_settings({ ovallsp: { diagnostics: {} } })
        await_publish
      end

      expect(reported(messages)).to eq([[1, [["unknown-method", 2]]], [1, []], [nil, []], [5, []],
                                        [5, [["unknown-method", 2]]]])
    end
  end
end
