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
    class Error < StandardError; end

    # Which Core the capability suite drives. The development tree by
    # default; set OVALLSP_E2E_CORE_BIN to the bundled copy inside a built
    # VSIX to verify the artifact users actually install rather than the
    # sources it was built from. Those are not the same thing: the bundled
    # copy carries its own vendored gems and a PLATFORM_MANIFEST, and a
    # release has already shipped without its `core/` at all.
    CORE_BIN = ENV.fetch("OVALLSP_E2E_CORE_BIN", File.expand_path("../../bin/ovallsp", __dir__))

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
      # Drain the child's stderr so it can never block on a full pipe.
      # Deliberately no state: round 5 removed this drain's unused
      # reader and left `@stderr_output` assigned-never-read, which is
      # the debris class this release removes elsewhere -- so the drain
      # now keeps nothing there is to leave behind.
      Thread.new { @stderr.read }
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
    # keystroke can be answered usefully, and returns it -- or, if the
    # timeout expires first, whatever Core was still reporting, so the
    # caller's own expectation names it in the failure message.
    #
    # `agent:` is whether this workspace boots a Runtime Agent, and it has
    # to come from the caller because `ovallsp/status` cannot supply it:
    # **`ready-static` means two different things over the wire.**
    # `Server` assigns `@agent_manager` only once the bootstrap returns
    # (deliberately -- `server_workspace_trust_spec.rb` pins it), so a
    # Rails workspace reads `ready-static` for the whole of its boot,
    # exactly as a plain Ruby workspace that will never have an Agent
    # does.
    #
    # So `agent: true` waits for `ready-rails` and nothing else, and
    # `agent: false` waits only for the cold index to finish, returning
    # whatever settled state Core then reports rather than a name this
    # file hardcodes.
    #
    # **No default, because the omission is the defect** (`024.134`). The
    # accepted set was `ready`/`ready-rails`: `ready` is a state Core does
    # not report at all -- `Server#status_result` answers `indexing`,
    # `ready-rails`, `agent-unavailable` or `ready-static`, and a grep of
    # `core/lib` finds `"ready"` nowhere -- and `ready-rails` is reached
    # only by a workspace with an Agent. The first example pointed at a
    # non-Rails workspace therefore waited out its whole budget in
    # silence. A default of `true` would keep every existing caller green
    # and hand the next one the same wait; `keyreq` raises on that
    # example's first run instead.
    def wait_until_ready(agent:, timeout: 120)
      deadline = monotonic + timeout
      state = nil
      while monotonic < deadline
        state = request("ovallsp/status", {})[:state]
        return state if agent ? state == "ready-rails" : state != "indexing"

        sleep 0.25
      end
      state
    end

    def completion_labels(uri, line, character)
      completion_items(uri, line, character).map { |item| item[:label] }
    end

    def completion_items(uri, line, character)
      result = request("textDocument/completion", { textDocument: { uri: uri }, position: { line: line, character: character } })
      result.is_a?(Array) ? result : (result[:items] || [])
    end

    def completion_item(uri, line, character, label)
      completion_items(uri, line, character).find { |item| item[:label] == label }
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

    # `textDocument/inlayHint` over a whole file. Returns `[line, label]`
    # pairs, sorted, because that is what every example here compares.
    def inlay_hints(uri, last_line: 200)
      Array(request("textDocument/inlayHint",
                    { textDocument: { uri: uri },
                      range: { start: { line: 0, character: 0 },
                               end: { line: last_line, character: 0 } } }))
        # Sorted by position, not by label: two hints on one line are
      # ordered by where they sit, and sorting the pair by its second
      # element put `height:` before `width:`.
      .sort_by { |h| [h[:position][:line], h[:position][:character]] }
      .map { |h| [h[:position][:line], h[:label]] }
    end

    # `textDocument/typeDefinition`. Locations only; the protocol allows a
    # single Location or a list and this client normalises to a list.
    def type_definitions(uri, line, character)
      Array(request("textDocument/typeDefinition",
                    { textDocument: { uri: uri }, position: { line: line, character: character } }))
        .map { |d| { uri: d[:uri], line: d[:range][:start][:line] } }
    end

    # `textDocument/prepareCallHierarchy` and the two follow-ups. The
    # protocol hands the item back verbatim, so the follow-ups take one.
    def prepare_call_hierarchy(uri, line, character)
      Array(request("textDocument/prepareCallHierarchy",
                    { textDocument: { uri: uri }, position: { line: line, character: character } }))
    end

    def incoming_calls(item)
      Array(request("callHierarchy/incomingCalls", { item: item }))
    end

    def outgoing_calls(item)
      Array(request("callHierarchy/outgoingCalls", { item: item }))
    end

    # `textDocument/documentHighlight`. Ranges plus the protocol's kind,
    # which is 1 = Text, 2 = Read, 3 = Write.
    def document_highlights(uri, line, character)
      request("textDocument/documentHighlight",
              { textDocument: { uri: uri }, position: { line: line, character: character } })
        .then { |r| Array(r).map { |h| { range: h[:range], kind: h[:kind] } } }
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

    # Raw request access, for a capability with no purpose-built helper --
    # semantic tokens and completion-item resolve both answer shapes that
    # only one example each looks at.
    def raw_request(method, params, timeout: 60) = request(method, params, timeout: timeout)

    # The pid of the Core process this client owns, so B3 can assert what
    # actually matters after a shutdown: that nothing survives it.
    def core_pid = @wait.pid

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

    private

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def request(method, params, timeout: 60)
      id = (@next_id += 1)
      write({ jsonrpc: "2.0", id: id, method: method, params: params })
      deadline = monotonic + timeout
      while monotonic < deadline
        response = @mutex.synchronize { @responses.delete(id) }
        if response
          # **An error response is not an empty answer.** `result` is absent
          # on an error, so returning it handed every caller `nil` -- and
          # every example asserting "answers nothing" passed just as well when
          # the handler raised. 0.3.0's D5 was written that way and could not
          # tell a deliberate decline from a crash, which is the distinction
          # section 0 is built on. Found by removing a guard and watching the
          # example that exists for it stay green.
          raise Error, "#{method} answered an error: #{response[:error].inspect}" if response[:error]

          return response[:result]
        end

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
