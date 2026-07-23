# frozen_string_literal: true

require "set"
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
require_relative "rails_bootstrap"
require_relative "cold_indexer"

module Rslsp
  # LSP transport + request router. Task 001 scope: initialize/initialized,
  # didOpen/didChange/didClose, a fixed hover response, and shutdown/exit.
  # Task 002 adds per-document FileSummary extraction (Prism) and
  # textDocument/documentSymbol. Task 003 adds a workspace-wide index behind
  # textDocument/definition (lexical, name-based — see WorkspaceIndex),
  # workspace/symbol, and workspace/didChangeWatchedFiles. Task 004 adds the
  # custom rslsp/explainType request, backed by LocalInferencer. Task 006
  # adds route-helper completion/signatureHelp/definition, backed by a
  # Routes::RouteRegistry either injected directly (tests) or populated by
  # RailsBootstrap once the client confirms the workspace is trusted (see
  # #maybe_start_agent — docs/02-architecture.md section 11: untrusted
  # workspaces get static analysis only, never Agent/Bundler code
  # execution). Task 008 makes rslsp/explainType propagate a conventional
  # controller action's instance variables into its .erb view.
  class Server
    JSONRPC_VERSION = "2.0"

    METHOD_NOT_FOUND = -32601
    INTERNAL_ERROR = -32603

    FILE_CHANGE_DELETED = 3

    def initialize(input:, output:, logger:, route_registry: Routes::RouteRegistry.new,
                   model_registry: Models::ModelRegistry.new, workspace_root: Dir.pwd,
                   agent_bootstrap: RailsBootstrap)
      @reader = Rslsp::IO::FramedReader.new(input)
      @writer = Rslsp::IO::FramedWriter.new(output)
      @logger = logger
      @document_store = DocumentStore.new
      @parser_service = ParserService.new
      @workspace_index = WorkspaceIndex.new
      @local_inferencer = LocalInferencer.new(model_registry: model_registry)
      @route_registry = route_registry
      @model_registry = model_registry
      @workspace_root = workspace_root
      @agent_bootstrap = agent_bootstrap
      @agent_manager = nil
      @agent_restart_mutex = Mutex.new
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
        start_cold_index
        maybe_start_agent(message[:params])
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

    # Closing a buffer ends its authority over WorkspaceIndex — whatever's
    # on disk becomes the truth again (docs/design/tasks/008.5-runtime-and-index-corrections.md).
    # Without this, closing an unsaved new file (or unsaved edits to an
    # existing one) left its buffer-only declarations in WorkspaceIndex
    # forever, showing up in completion/definition/workspace symbol
    # results for a file nobody has open anymore and whose disk content
    # (if any) says something else entirely.
    def handle_did_close(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      @document_store.close(uri: uri)
      @file_summaries.delete(uri)

      path = UriUtil.to_path(uri)
      if path && File.file?(path)
        reindex_from_disk(uri)
      else
        @workspace_index.remove_file(uri)
      end
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

    # Cold Index (docs/design/tasks/008.5-runtime-and-index-corrections.md):
    # indexes the workspace from disk after initialize, so files nobody
    # has opened yet (a controller behind a view opened first, a model
    # nobody's touched this session) are still resolvable. Unlike the
    # Agent, this needs no trust check — reading and parsing local Ruby
    # source executes none of it, unlike booting the workspace's own Rails
    # app does.
    def start_cold_index
      root = @workspace_root
      parser_service = @parser_service
      workspace_index = @workspace_index
      document_store = @document_store
      logger = @logger

      Thread.new do
        ColdIndexer.new(root: root, parser_service: parser_service, workspace_index: workspace_index,
                        document_store: document_store, logger: logger).run
      rescue StandardError => e
        logger.error("cold index failed: #{e.class}: #{e.message}")
      end
    end

    # Starts the Runtime Agent on a background thread — never the request
    # thread, so a slow or absent Rails boot can't delay any LSP response
    # (docs/02-architecture.md section 8's threading model) — but only
    # once the *client* has explicitly said the workspace is trusted.
    # Workspace Trust is a VS Code (client-side) concept with no standard
    # LSP field for it, so the client passes it through
    # `initializationOptions.workspaceTrusted` (see vscode/src/extension.ts).
    # Fail-closed by design: anything other than a literal `true` — absent,
    # `false`, or a client that doesn't send `initializationOptions` at all
    # — skips starting the Agent, per docs/02-architecture.md section 11
    # ("Workspace Trustがない場合...起動しない") and
    # docs/10-ai-execution-guide.md section 8 ("Workspace Trustを迂回して
    # code executionしていないか"). The VS Code extension always sends this
    # explicitly, so real usage is unaffected; a client that never mentions
    # trust at all gets static-only behavior rather than an implicit grant.
    def maybe_start_agent(params)
      unless workspace_trusted?(params)
        @logger.warn("workspace trust not confirmed; not starting the Runtime Agent")
        return
      end

      bootstrap = @agent_bootstrap
      root = @workspace_root
      logger = @logger
      route_registry = @route_registry
      model_registry = @model_registry
      mutex = @agent_restart_mutex

      Thread.new do
        # Serialized on the same mutex #restart_agent uses: an extremely
        # fast client could in principle fire a file-change restart before
        # this initial bootstrap finishes, and without sharing the lock,
        # both writes to @agent_manager could interleave the same way
        # described in #restart_agent's comment.
        mutex.synchronize do
          @agent_manager = bootstrap.start(root: root, logger: logger, route_registry: route_registry,
                                            model_registry: model_registry)
        end
      rescue StandardError => e
        logger.error("Runtime Agent bootstrap failed: #{e.class}: #{e.message}")
      end
    end

    def workspace_trusted?(params)
      options = params && params[:initializationOptions]
      options.is_a?(Hash) && options[:workspaceTrusted] == true
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

      TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8), version: nil, language_id: "ruby")
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
        column = helper.source_location.fetch(:column, 0)
        locations << {
          uri: UriUtil.from_path(helper.source_location.fetch(:path)),
          range: { start: { line: line, character: column }, end: { line: line, character: column } }
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
      changed_models = Set.new
      needs_routes_refresh = false
      needs_restart = false

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

        case classify_rails_change(uri)
        when :routes then needs_routes_refresh = true
        when :restart then needs_restart = true
        else
          model_name = model_name_for(uri)
          changed_models << model_name if model_name
        end
      end

      # Deduplicated across the whole batch — a git checkout or branch
      # switch can touch dozens of files in one notification, and without
      # this a restart (or the same model) would otherwise be requested
      # once per file instead of once per batch.
      maybe_restart_agent if needs_restart
      return if needs_restart # a restart already refreshes everything

      with_ready_agent("config/routes.rb") { refresh_routes } if needs_routes_refresh
      changed_models.each { |name| with_ready_agent("app/models/#{name}") { refresh_model_named(name) } }
    end

    def classify_rails_change(uri)
      path = UriUtil.to_path(uri) || uri
      return :routes if path.end_with?("config/routes.rb")
      return :restart if path.end_with?("Gemfile.lock") || path.include?("config/initializers/")

      nil
    end

    def model_name_for(uri)
      path = UriUtil.to_path(uri) || uri
      match = MODEL_FILE_PATTERN.match(path)
      return nil unless match

      match[:relative].split("/").map { |segment| Routes::ControllerNaming.camelize(segment) }.join("::")
    end

    def reindex_from_disk(uri)
      path = UriUtil.to_path(uri)
      return unless path && File.file?(path)

      document = TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8), version: nil,
                                   language_id: "ruby")
      @workspace_index.replace_file(@parser_service.summarize(document))
    rescue StandardError => e
      @logger.error("failed to reindex #{uri} from disk: #{e.class}: #{e.message}")
    end

    MODEL_FILE_PATTERN = %r{app/models/(?<relative>.+)\.rb\z}

    # docs/design/docs/04-runtime-agent.md section 9's invalidation rules,
    # scoped down to what actually needs Runtime Agent round-trips: routes
    # and models (a bare re-parse via #reindex_from_disk above already
    # covers everything WorkspaceIndex needs). No-ops entirely when no
    # Agent is running (never started, still starting, or degraded to
    # static-only) — there's nothing to refresh from. Only warns when
    # there's an Agent to begin with (started but not
    # currently :ready — e.g. mid-restart, or degraded to :static_only) so
    # a change is never silently dropped without a trace. A workspace with
    # no Agent at all (not Rails, or trust not yet granted) is the normal
    # case and stays quiet. A change arriving mid-restart is usually
    # harmless in practice — #restart_agent's own bootstrap fetches a full
    # fresh routes+models snapshot on completion, which normally already
    # reflects whatever this change was — but it's still logged since
    # "usually" isn't "always".
    def with_ready_agent(path)
      if @agent_manager&.ready?
        yield
      elsif @agent_manager
        @logger.warn("skipping Runtime Agent refresh for #{path}: agent not ready (status=#{@agent_manager.status})")
      end
    end

    # Unlike routes/model refresh, a restart is exactly the recovery
    # mechanism for an Agent that *isn't* :ready (:starting, or degraded
    # to :static_only after a failed boot) — gating it on #ready? the same
    # way would mean a workspace stuck in :static_only could never recover
    # from a Gemfile.lock fix without a full Core Server restart (reloading
    # the VS Code window). The only real precondition is that some Agent
    # was ever started for this workspace in the first place; a workspace
    # with none (not Rails, or trust not yet granted) has nothing to
    # restart and stays quiet, same as #with_ready_agent's nil case.
    def maybe_restart_agent
      restart_agent if @agent_manager
    end

    # Re-draws routes via agent/reload, then re-fetches the routes section
    # so RouteRegistry reflects whatever changed — added, removed, or
    # edited (docs/design/tasks/006-routes-snapshot.md "reload後に削除route
    # が消える"). Runs on its own thread: both requests block on Agent I/O,
    # and nothing here may delay LSP responses.
    def refresh_routes
      agent_manager = @agent_manager
      route_registry = @route_registry
      logger = @logger

      Thread.new do
        next unless agent_manager.reload(sections: ["routes"])

        snapshot = agent_manager.fetch_snapshot(sections: ["routes"])
        route_registry.replace(snapshot[:routes]) if snapshot
      rescue StandardError => e
        logger.error("failed to refresh routes after routes.rb change: #{e.class}: #{e.message}")
      end
    end

    # Unlike routes, a model's columns/associations are read live on every
    # agent/model call (docs/design/docs/05-protocol.md) — there's no
    # server-side model cache to explicitly reload, so refreshing just
    # means asking again for the one model whose file changed.
    def refresh_model_named(name)
      agent_manager = @agent_manager
      model_registry = @model_registry
      logger = @logger

      Thread.new do
        response = agent_manager.fetch_model(name: name)
        model_registry.register_from_agent_response(name, response) if response && !response[:error]
      rescue StandardError => e
        logger.error("failed to refresh model #{name}: #{e.class}: #{e.message}")
      end
    end

    # Gemfile.lock and initializer changes can alter what's loaded at boot
    # in ways routes/model refresh alone can't recover from, so the whole
    # Agent process restarts (docs/design/docs/04-runtime-agent.md section 9:
    # "Gemfile.lock -> Core/Agent full restart", "config/initializers/** ->
    # Agent restart").
    #
    # Serialized on @agent_restart_mutex: two restart triggers arriving as
    # separate didChangeWatchedFiles notifications in quick succession
    # (e.g. `bundle install` touching Gemfile.lock, then a follow-up save)
    # each spawn their own thread here. Without the mutex, both would
    # capture the same starting @agent_manager, both stop it and start a
    # fresh process, and whichever thread finished last would overwrite
    # @agent_manager — orphaning the other thread's freshly-started Agent
    # process with nothing left to stop it (docs/11-risk-register.md R-08,
    # memory/process growth). Re-reading @agent_manager *inside* the lock
    # (not capturing it beforehand) means a second, serialized restart
    # correctly stops the process the first restart just started, instead
    # of a stale reference to the one from before either ran.
    def restart_agent
      bootstrap = @agent_bootstrap
      root = @workspace_root
      route_registry = @route_registry
      model_registry = @model_registry
      logger = @logger
      mutex = @agent_restart_mutex

      Thread.new do
        mutex.synchronize do
          @agent_manager&.stop
          @agent_manager = bootstrap.start(root: root, logger: logger, route_registry: route_registry,
                                            model_registry: model_registry)
        end
      rescue StandardError => e
        logger.error("failed to restart runtime agent: #{e.class}: #{e.message}")
      end
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
