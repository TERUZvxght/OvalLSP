# frozen_string_literal: true

require_relative "io/framed_reader"
require_relative "io/framed_writer"
require_relative "document_store"

module Rslsp
  # LSP transport + request router. Task 001 scope: initialize/initialized,
  # didOpen/didChange/didClose, a fixed hover response, and shutdown/exit.
  # No parsing, indexing, or Rails integration happens here yet.
  class Server
    JSONRPC_VERSION = "2.0"

    METHOD_NOT_FOUND = -32601
    INTERNAL_ERROR = -32603

    def initialize(input:, output:, logger:)
      @reader = Rslsp::IO::FramedReader.new(input)
      @writer = Rslsp::IO::FramedWriter.new(output)
      @logger = logger
      @document_store = DocumentStore.new
      @shutdown_received = false
    end

    # Runs the read/dispatch loop until `exit` is received or the input
    # stream closes. Returns the process exit code the LSP spec expects:
    # 0 if `shutdown` preceded `exit`, 1 otherwise.
    def run
      loop do
        message = begin
          @reader.read_message
        rescue Rslsp::IO::FramedReader::EOF
          break
        end

        break if dispatch(message) == :exit
      end

      @shutdown_received ? 0 : 1
    end

    private

    def dispatch(message)
      method = message[:method]
      id = message[:id]

      case method
      when "initialize"
        respond(id, initialize_result)
      when "initialized"
        # no-op: nothing to do yet at this task's scope.
      when "shutdown"
        @shutdown_received = true
        respond(id, nil)
      when "exit"
        return :exit
      when "textDocument/didOpen"
        handle_did_open(message[:params])
      when "textDocument/didChange"
        handle_did_change(message[:params])
      when "textDocument/didClose"
        handle_did_close(message[:params])
      when "textDocument/hover"
        respond(id, hover_result)
      else
        handle_unknown_method(method, id)
      end

      nil
    rescue StandardError => e
      handle_dispatch_error(method, id, e)
      nil
    end

    def handle_unknown_method(method, id)
      if id
        respond_error(id, code: METHOD_NOT_FOUND, message: "Method not found: #{method}")
      else
        @logger.warn("ignoring unknown notification: #{method}")
      end
    end

    def handle_dispatch_error(method, id, error)
      @logger.error("error handling #{method.inspect}: #{error.class}: #{error.message}")
      respond_error(id, code: INTERNAL_ERROR, message: "internal error") if id
    end

    def handle_did_open(params)
      doc = params.fetch(:textDocument)
      @document_store.open(
        uri: doc.fetch(:uri),
        text: doc.fetch(:text),
        version: doc.fetch(:version),
        language_id: doc.fetch(:languageId)
      )
    end

    def handle_did_change(params)
      doc = params.fetch(:textDocument)
      @document_store.change(
        uri: doc.fetch(:uri),
        version: doc.fetch(:version),
        changes: params.fetch(:contentChanges)
      )
    end

    def handle_did_close(params)
      doc = params.fetch(:textDocument)
      @document_store.close(uri: doc.fetch(:uri))
    end

    def initialize_result
      {
        capabilities: {
          textDocumentSync: {
            openClose: true,
            change: 2 # Incremental, per LSP 3.17 TextDocumentSyncKind.
          },
          hoverProvider: true
        },
        serverInfo: {
          name: "rslsp",
          version: Rslsp::VERSION
        }
      }
    end

    def hover_result
      {
        contents: {
          kind: "plaintext",
          value: "RSLSP connected"
        }
      }
    end

    def respond(id, result)
      @writer.write_message(jsonrpc: JSONRPC_VERSION, id: id, result: result)
    end

    def respond_error(id, code:, message:)
      @writer.write_message(jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message })
    end
  end
end
