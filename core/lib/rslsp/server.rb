# frozen_string_literal: true

require_relative "io/framed_reader"
require_relative "io/framed_writer"
require_relative "document_store"
require_relative "parser_service"
require_relative "workspace_index"
require_relative "uri_util"
require_relative "local_inferencer"
require_relative "index/document_symbol_builder"
require_relative "routes/route_registry"
require_relative "routes/controller_naming"
require_relative "erb/ruby_region_extractor"

module Rslsp
  # LSP transport + request router. Task 001 scope: initialize/initialized,
  # didOpen/didChange/didClose, a fixed hover response, and shutdown/exit.
  # Task 002 adds per-document FileSummary extraction (Prism) and
  # textDocument/documentSymbol. Task 003 adds a workspace-wide index behind
  # textDocument/definition (lexical, name-based — see WorkspaceIndex),
  # workspace/symbol, and workspace/didChangeWatchedFiles. Task 004 adds the
  # custom rslsp/explainType request, backed by LocalInferencer. Task 006
  # adds route-helper completion/signatureHelp/definition, backed by a
  # Routes::RouteRegistry the caller builds from an agent/snapshot response
  # (Server itself doesn't manage the Runtime Agent process — see
  # AgentProcessManager — keeping this class free of Rails-boot concerns).
  # Task 008 makes rslsp/explainType propagate a conventional controller
  # action's instance variables into its .erb view.
  class Server
    JSONRPC_VERSION = "2.0"

    METHOD_NOT_FOUND = -32601
    INTERNAL_ERROR = -32603

    FILE_CHANGE_DELETED = 3

    def initialize(input:, output:, logger:, route_registry: Routes::RouteRegistry.new,
                   model_registry: Models::ModelRegistry.new)
      @reader = Rslsp::IO::FramedReader.new(input)
      @writer = Rslsp::IO::FramedWriter.new(output)
      @logger = logger
      @document_store = DocumentStore.new
      @parser_service = ParserService.new
      @workspace_index = WorkspaceIndex.new
      @local_inferencer = LocalInferencer.new(model_registry: model_registry)
      @route_registry = route_registry
      @file_summaries = {}
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
      when "textDocument/documentSymbol"
        respond(id, document_symbol_result(message[:params]))
      when "textDocument/definition"
        respond(id, definition_result(message[:params]))
      when "workspace/symbol"
        respond(id, workspace_symbol_result(message[:params]))
      when "workspace/didChangeWatchedFiles"
        handle_did_change_watched_files(message[:params])
      when "rslsp/explainType"
        respond(id, explain_type_result(message[:params]))
      when "textDocument/completion"
        respond(id, completion_result(message[:params]))
      when "textDocument/signatureHelp"
        respond(id, signature_help_result(message[:params]))
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
      document = @document_store.open(
        uri: doc.fetch(:uri),
        text: doc.fetch(:text),
        version: doc.fetch(:version),
        language_id: doc.fetch(:languageId)
      )
      reindex(document)
    end

    def handle_did_change(params)
      doc = params.fetch(:textDocument)
      document = @document_store.change(
        uri: doc.fetch(:uri),
        version: doc.fetch(:version),
        changes: params.fetch(:contentChanges)
      )
      reindex(document)
    end

    def handle_did_close(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      @document_store.close(uri: uri)
      @file_summaries.delete(uri)
    end

    def reindex(document)
      summary = @parser_service.summarize(document)
      @file_summaries[document.uri] = summary
      @workspace_index.replace_file(summary)
    rescue StandardError => e
      # Parsing must never take the server down: keep the previous summary
      # (if any) and let static features degrade gracefully for this file.
      @logger.error("failed to summarize #{document.uri}: #{e.class}: #{e.message}")
    end

    def document_symbol_result(params)
      summary = @file_summaries[params.fetch(:textDocument).fetch(:uri)]
      return [] unless summary

      Index::DocumentSymbolBuilder.build(summary.declarations)
    end

    # Custom (non-LSP-standard) request: infers the type of the expression
    # at a position using local-only inference (docs/design/tasks/004-type-model-and-local-inference.md).
    # For a .erb view (Task 008), the query instead runs against a synthetic
    # Ruby source extracted from the template's <% %> regions, seeded with
    # the conventionally-corresponding controller action's instance
    # variable types.
    def explain_type_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return { type: Types::UNKNOWN.to_s } unless document

      position = params.fetch(:position)
      type = erb_view?(uri) ? explain_type_in_view(document, position) : @local_inferencer.infer_at(document, position)
      { type: type.to_s }
    end

    def erb_view?(uri)
      uri.end_with?(".erb")
    end

    def explain_type_in_view(document, position)
      ruby_source = Erb::RubyRegionExtractor.extract_ruby_source(document.text)
      synthetic = TextDocument.new(uri: document.uri, text: ruby_source, version: document.version, language_id: "ruby")

      @local_inferencer.infer_at(synthetic, position, initial_env: ivars_for_view(document.uri))
    end

    # No caching here by design: recomputed fresh from the controller's
    # *current* text on every call, so an edited action's ivar types are
    # immediately reflected — there's no stale view context to invalidate
    # (docs/design/tasks/008-controller-view-propagation.md "action変更時に
    # view contextをinvalidate"). Returns {} (-> Unknown for every @ivar)
    # when the view doesn't match the app/views/<controller>/<action>.*.erb
    # convention or its controller can't be found.
    def ivars_for_view(view_uri)
      context = view_action_context(view_uri)
      return {} unless context

      controller_document = @document_store.fetch(uri: context[:controller_uri]) ||
                             load_document_from_disk(context[:controller_uri])
      return {} unless controller_document

      contributing_actions(controller_document, context[:owner], context[:action]).reduce({}) do |env, action_name|
        env.merge(@local_inferencer.infer_ivars_for_method(controller_document, owner_name: context[:owner],
                                                                                 method_name: action_name))
      end
    end

    VIEW_PATH_PATTERN = %r{app/views/(?<dir>.+)/(?<action>[^/.]+)\.[^/]*\.erb\z}

    def view_action_context(view_uri)
      path = UriUtil.to_path(view_uri) || view_uri
      match = VIEW_PATH_PATTERN.match(path)
      return nil unless match

      owner = Routes::ControllerNaming.owner_name(match[:dir])
      return nil unless owner

      controller_uri = find_controller_uri(owner)
      return nil unless controller_uri

      { owner: owner, action: match[:action], controller_uri: controller_uri }
    end

    def find_controller_uri(owner_name)
      symbol_id = Index::SymbolId.new(kind: :class, owner: nil, name: owner_name, discriminator: nil)
      @workspace_index.declarations_with_uri(symbol_id).first&.first
    end

    # An action contributes its ivars to this view if it either *is* the
    # view's own action, or explicitly `render`s it — propagating e.g. a
    # failed #update's ivars into "edit.html.erb"
    # (docs/design/tasks/008-controller-view-propagation.md "render :edit
    # 先へ伝播").
    def contributing_actions(controller_document, owner_name, view_action)
      summary = @parser_service.summarize(controller_document)
      action_names = summary.declarations
                            .select { |d| d.symbol_id.kind == :instance_method && d.symbol_id.owner == owner_name }
                            .map { |d| d.symbol_id.name }

      action_names.select do |action_name|
        action_name == view_action ||
          @local_inferencer.find_static_render_target(controller_document, owner_name: owner_name,
                                                                             method_name: action_name) == view_action
      end
    end

    def load_document_from_disk(uri)
      path = UriUtil.to_path(uri)
      return nil unless path && File.file?(path)

      TextDocument.new(uri: uri, text: File.read(path), version: nil, language_id: "ruby")
    rescue StandardError => e
      @logger.error("failed to read #{uri} from disk: #{e.class}: #{e.message}")
      nil
    end

    # Lexical-only "go to definition": resolves the identifier under the
    # cursor by name against the workspace index (docs/03-semantic-engine.md
    # section 6's name-heuristic fallback) and, if it's a route helper,
    # against the route registry too. Real reference tracking arrives with
    # the type engine.
    def definition_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return [] unless document

      word = word_at_position(document, params.fetch(:position))
      return [] unless word

      lexical = @workspace_index.find_by_simple_name(word).map { |match| { uri: match[:uri], range: match[:range] } }
      (lexical + route_helper_definitions(word)).uniq
    end

    # A route helper's primary definition is its routes.rb source line (the
    # RouteRegistry.route_helper's location — absent for a route Task 006's
    # "source location unavailable" case falls back to, so it's simply
    # omitted rather than pointing somewhere meaningless). Its secondary
    # definitions are every controller action it can dispatch to, resolved
    # via the workspace index — GET actions sort first, so a plain resource
    # route's "show" action leads.
    def route_helper_definitions(word)
      helper = @route_registry.find_by_method_name(word)
      return [] unless helper

      locations = []
      if helper.source_location
        line = helper.source_location.fetch(:line)
        locations << {
          uri: UriUtil.from_path(helper.source_location.fetch(:path)),
          range: { start: { line: line, character: 0 }, end: { line: line, character: 0 } }
        }
      end

      helper.action_targets.each do |target|
        owner = Routes::ControllerNaming.owner_name(target.controller)
        next unless owner

        symbol_id = Index::SymbolId.new(kind: :instance_method, owner: owner, name: target.action, discriminator: nil)
        @workspace_index.declarations_with_uri(symbol_id).each do |(decl_uri, decl)|
          locations << { uri: decl_uri, range: decl.location }
        end
      end

      locations
    end

    def completion_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return [] unless document

      prefix = word_prefix_at_position(document, params.fetch(:position))
      return [] if prefix.empty?

      @route_registry.completion_names(prefix).map do |name|
        { label: name, kind: 3 } # LSP CompletionItemKind::Function
      end
    end

    # Finds the call whose argument list the cursor is inside by scanning
    # backward for an unmatched `(`, then reads the identifier immediately
    # before it. Good enough for the common `post_path(|)` shape signature
    # help actually needs to handle; it doesn't try to track nested calls.
    def signature_help_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return { signatures: [] } unless document

      method_name = enclosing_call_name(document, params.fetch(:position))
      helper = method_name && @route_registry.find_by_method_name(method_name)
      return { signatures: [] } unless helper

      params_label = (helper.required_parts + ["options = {}"]).join(", ")
      {
        signatures: [
          {
            label: "#{helper.path_helper}(#{params_label})",
            parameters: helper.required_parts.map { |part| { label: part } }
          }
        ]
      }
    end

    def enclosing_call_name(document, position)
      text = document.text
      idx = document.position_to_char_offset(position) - 1
      idx -= 1 while idx >= 0 && text[idx] != "("
      return nil if idx.negative?

      name_end = idx
      name_start = name_end
      name_start -= 1 while name_start.positive? && word_char?(text[name_start - 1])
      return nil if name_start == name_end

      text[name_start...name_end]
    end

    def word_at_position(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = offset
      left -= 1 while left > 0 && word_char?(text[left - 1])
      right = offset
      right += 1 while right < text.length && word_char?(text[right])

      return nil if left == right

      text[left...right]
    end

    def word_prefix_at_position(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = offset
      left -= 1 while left > 0 && word_char?(text[left - 1])
      text[left...offset]
    end

    def word_char?(char)
      !char.nil? && char.match?(/[A-Za-z0-9_]/)
    end

    def workspace_symbol_result(params)
      query = params.fetch(:query, "")
      @workspace_index.search(query, limit: 100).map do |match|
        {
          name: match[:symbol_id].name.to_s.split("::").last,
          kind: Index::DocumentSymbolBuilder::SYMBOL_KIND.fetch(match[:symbol_id].kind, 13),
          location: { uri: match[:uri], range: match[:location] }
        }
      end
    end

    def handle_did_change_watched_files(params)
      params.fetch(:changes, []).each do |change|
        uri = change.fetch(:uri)
        if change.fetch(:type) == FILE_CHANGE_DELETED
          @workspace_index.remove_file(uri)
          @file_summaries.delete(uri)
        elsif @document_store.fetch(uri: uri).nil?
          # An open buffer is always authoritative over what's on disk; only
          # reindex from disk for files nobody currently has open.
          reindex_from_disk(uri)
        end
      end
    end

    def reindex_from_disk(uri)
      path = UriUtil.to_path(uri)
      return unless path && File.file?(path)

      document = TextDocument.new(uri: uri, text: File.read(path), version: nil, language_id: "ruby")
      @workspace_index.replace_file(@parser_service.summarize(document))
    rescue StandardError => e
      @logger.error("failed to reindex #{uri} from disk: #{e.class}: #{e.message}")
    end

    def initialize_result
      {
        capabilities: {
          textDocumentSync: {
            openClose: true,
            change: 2 # Incremental, per LSP 3.17 TextDocumentSyncKind.
          },
          hoverProvider: true,
          documentSymbolProvider: true,
          definitionProvider: true,
          workspaceSymbolProvider: true,
          completionProvider: { triggerCharacters: [] },
          signatureHelpProvider: { triggerCharacters: ["("] }
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
