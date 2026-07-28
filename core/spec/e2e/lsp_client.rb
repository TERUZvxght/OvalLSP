# frozen_string_literal: true

require "json"
require "open3"

module E2E
  # Drives a real Core process over stdio the way the extension does:
  # stays connected, lets the Runtime Agent boot and the cold index run,
  # and only then asks. Every capability check in this directory goes
  # through here rather than through in-process objects, because the
  # failures this suite exists to catch (nothing is indexed yet, the Agent
  # never became ready, the receiver type is Unknown so completion is
  # empty) are invisible to a test that hands the engine a document
  # directly.
  class LspClient
    class Timeout < StandardError; end

    CORE_BIN = File.expand_path("../../bin/ovallsp", __dir__)

    attr_reader :diagnostics_by_uri

    def initialize(root, env: {})
      @root = root
      @next_id = 0
      @responses = {}
      @diagnostics_by_uri = Hash.new { |h, k| h[k] = [] }
      @mutex = Mutex.new
      @stdin, @stdout, @stderr, @wait = Open3.popen3(env, RbConfig.ruby, CORE_BIN, "--stdio", chdir: root)
      @stdin.binmode
      @stdout.binmode
      @reader = Thread.new { read_loop }
      @stderr_thread = Thread.new { @stderr_output = @stderr.read }
    end

    def initialize!(trusted: true)
      request("initialize", {
                processId: nil, rootUri: "file://#{@root}", capabilities: {},
                initializationOptions: { workspaceTrusted: trusted }
              })
      notify("initialized", {})
    end

    def open(path, text: nil)
      uri = "file://#{path}"
      notify("textDocument/didOpen", {
               textDocument: { uri: uri, text: text || File.read(path), version: 1, languageId: "ruby" }
             })
      uri
    end

    # Waits for the state the extension waits for before a user's first
    # keystroke can be answered usefully. Returns the final state.
    def wait_until_ready(timeout: 120)
      deadline = monotonic + timeout
      state = nil
      while monotonic < deadline
        state = request("ovallsp/status", {})[:state]
        return state if %w[ready ready-rails].include?(state)

        sleep 0.25
      end
      state
    end

    def completion_labels(uri, line, character)
      result = request("textDocument/completion", { textDocument: { uri: uri }, position: { line: line, character: character } })
      items = result.is_a?(Array) ? result : (result[:items] || [])
      items.map { |item| item[:label] }
    end

    def hover_text(uri, line, character)
      result = request("textDocument/hover", { textDocument: { uri: uri }, position: { line: line, character: character } })
      result && result.dig(:contents, :value)
    end

    def definitions(uri, line, character)
      Array(request("textDocument/definition", { textDocument: { uri: uri }, position: { line: line, character: character } }))
    end

    def signature_labels(uri, line, character)
      result = request("textDocument/signatureHelp", { textDocument: { uri: uri }, position: { line: line, character: character } })
      Array(result && result[:signatures]).map { |signature| signature[:label] }
    end

    def references(uri, line, character)
      Array(request("textDocument/references", { textDocument: { uri: uri }, position: { line: line, character: character } }))
    end

    def rename_edits(uri, line, character, new_name)
      result = request("textDocument/rename", {
                         textDocument: { uri: uri }, position: { line: line, character: character }, newName: new_name
                       })
      (result && result[:changes]) || {}
    end

    def workspace_symbols(query)
      Array(request("workspace/symbol", { query: query })).map { |entry| entry[:name] }
    end

    # Diagnostics arrive as notifications, so a caller has to say how long
    # it is willing to wait for the publish that follows an edit.
    def diagnostic_messages(uri, timeout: 15)
      deadline = monotonic + timeout
      while monotonic < deadline
        found = @mutex.synchronize { @diagnostics_by_uri[uri].dup }
        return found.map { |d| d[:message] } unless found.empty?

        sleep 0.1
      end
      []
    end

    def stop
      request("shutdown", nil, timeout: 10)
      notify("exit", nil)
      @wait.join(5)
    rescue StandardError
      nil
    ensure
      @reader&.kill
      [@stdin, @stdout, @stderr].each { |io| io.close rescue nil }
      Process.kill("KILL", @wait.pid) rescue nil
    end

    def stderr_output
      @stderr_output.to_s
    end

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def request(method, params, timeout: 60)
      id = (@next_id += 1)
      write({ jsonrpc: "2.0", id: id, method: method, params: params })
      deadline = monotonic + timeout
      while monotonic < deadline
        response = @mutex.synchronize { @responses.delete(id) }
        return response[:result] if response

        sleep 0.02
      end
      raise Timeout, "no response to #{method} within #{timeout}s"
    end

    def notify(method, params)
      write({ jsonrpc: "2.0", method: method, params: params })
    end

    def write(message)
      body = JSON.generate(message)
      @stdin.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
      @stdin.flush
    end

    def read_loop
      loop do
        header = +""
        header << @stdout.readpartial(1) until header.end_with?("\r\n\r\n")
        length = header[/Content-Length: (\d+)/, 1].to_i
        body = +""
        body << @stdout.read(length - body.bytesize) while body.bytesize < length
        message = JSON.parse(body, symbolize_names: true)
        @mutex.synchronize do
          if message[:method] == "textDocument/publishDiagnostics"
            uri = message[:params][:uri]
            @diagnostics_by_uri[uri] = message[:params][:diagnostics]
          elsif message[:id]
            @responses[message[:id]] = message
          end
        end
      end
    rescue EOFError, IOError
      nil
    end
  end
end
