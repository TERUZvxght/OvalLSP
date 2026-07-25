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
require_relative "semantic/hierarchy_index"
require_relative "semantic/method_resolver"
require_relative "semantic/method_summary_store"
require_relative "semantic/method_analyzer"
require_relative "semantic/query_context"
require_relative "semantic/query_service"
require_relative "semantic/reference_index"
require_relative "semantic/reference_resolver"
require_relative "diagnostics/engine"
require_relative "rename/planner"
require_relative "plugins/loader"
require_relative "signatures/environment"

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
      @hierarchy_index = Semantic::HierarchyIndex.new(workspace_index: @workspace_index)
      @method_resolver = Semantic::MethodResolver.new(workspace_index: @workspace_index, hierarchy_index: @hierarchy_index)
      @method_summary_store = Semantic::MethodSummaryStore.new
      @generated_method_index = Semantic::GeneratedMethodIndex.new
      @method_analyzer = Semantic::MethodAnalyzer.new(
        workspace_index: @workspace_index, method_resolver: @method_resolver, summary_store: @method_summary_store,
        model_registry: model_registry, generated_method_index: @generated_method_index
      )
      # method_resolver/method_analyzer let a plain (non-Active-Record)
      # method call chain keep resolving past its first hop instead of
      # widening to Unknown immediately -- see LocalInferencer#resolve_source_method_member
      # (docs/design/tasks/010-method-summaries-and-call-chains.md; wired
      # in as part of Task 013 after an independent review found Task 010
      # had shipped as a fully isolated, never-called engine).
      @local_inferencer = LocalInferencer.new(
        model_registry: model_registry, method_resolver: @method_resolver, method_analyzer: @method_analyzer
      )
      @route_registry = route_registry
      @model_registry = model_registry
      @workspace_root = workspace_root
      @agent_bootstrap = agent_bootstrap
      @agent_manager = nil
      @agent_restart_mutex = Mutex.new
      @file_summaries = {}
      @shutdown_received = false
      @signatures = load_signatures_environment
      @query_service = Semantic::QueryService.new(
        local_inferencer: @local_inferencer, method_resolver: @method_resolver, model_registry: @model_registry,
        signatures: @signatures, workspace_index: @workspace_index
      )
      @reference_index = Semantic::ReferenceIndex.new
      @reference_resolver = Semantic::ReferenceResolver.new(
        workspace_index: @workspace_index, method_resolver: @method_resolver, local_inferencer: @local_inferencer,
        model_registry: @model_registry, route_registry: @route_registry
      )
      @diagnostics_engine = Diagnostics::Engine.new
      @diagnostics_mode = :safe
      @rename_planner = Rename::Planner.new(workspace_index: @workspace_index, reference_index: @reference_index)
      @plugin_loader = Plugins::Loader.new(logger: @logger)
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
        @diagnostics_mode = diagnostics_mode_from(message[:params])
        respond(id, initialize_result)
        load_static_plugins(message[:params])
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
        respond(id, hover_result(message[:params]))
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
      when "textDocument/references"
        respond(id, references_result(message[:params]))
      when "textDocument/prepareRename"
        respond(id, prepare_rename_result(message[:params]))
      when "textDocument/rename"
        respond(id, rename_result(message[:params]))
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

      # Unconditional and first: WorkspaceIndex#replace_file now refuses to
      # let any disk-sourced summary overwrite a buffer-sourced one for the
      # same uri (the whole point of Task 008.6's open-buffer-always-wins
      # guarantee) — closing the buffer is the one legitimate transition
      # away from that protection, and it must happen *before*
      # #reindex_from_disk's own replace_file call, or that call would see
      # a still-buffer-sourced existing entry and be silently rejected as
      # stale (docs/design/tasks/008.6-agent-and-index-hardening.md).
      previous_declarations = @workspace_index.declarations_for_uri(uri)
      @workspace_index.remove_file(uri)
      @hierarchy_index.remove_file(uri)
      @reference_index.remove_file(uri)
      @generated_method_index.remove_file(uri)
      invalidate_method_summaries(previous_declarations)
      clear_diagnostics(uri)

      path = UriUtil.to_path(uri)
      reindex_from_disk(uri) if path && File.file?(path)
    end

    def reindex(document)
      summary = @parser_service.summarize(document)
      @file_summaries[document.uri] = summary
      previous_declarations = @workspace_index.declarations_for_uri(document.uri)
      if @workspace_index.replace_file(summary)
        @hierarchy_index.replace_file(summary)
        invalidate_method_summaries(previous_declarations)
        index_references(document.uri, document, summary)
        @generated_method_index.replace_file(uri: document.uri, facts: summary.generated_method_facts)
        publish_diagnostics(document)
      end
    rescue StandardError => e
      # Parsing must never take the server down: keep the previous summary
      # (if any) and let static features degrade gracefully for this file.
      @logger.error("failed to summarize #{document.uri}: #{e.class}: #{e.message}")
    end

    # Task 015: computed and published synchronously, in the same dispatch
    # turn that already owns `document`'s current version -- there's no
    # background/async gap for a result to go stale in, so "stale document
    # versionのdiagnosticをpublishしない" holds by construction rather than
    # needing its own generation check. Only wired into the didOpen/
    # didChange path (buffer content the client can actually see) --
    # #reindex_from_disk (files nobody has open) doesn't publish, since
    # there's no LSP client-side buffer to attach the notification to
    # meaningfully.
    def publish_diagnostics(document)
      context = diagnostics_semantic_context
      findings = @diagnostics_engine.analyze(document: document, semantic_context: context, mode: @diagnostics_mode)
      @writer.write_message(
        jsonrpc: JSONRPC_VERSION, method: "textDocument/publishDiagnostics",
        params: { uri: document.uri, version: document.version, diagnostics: findings.map { |f| to_lsp_diagnostic(f) } }
      )
    rescue StandardError => e
      @logger.error("failed to compute diagnostics for #{document.uri}: #{e.class}: #{e.message}")
    end

    def clear_diagnostics(uri)
      @writer.write_message(
        jsonrpc: JSONRPC_VERSION, method: "textDocument/publishDiagnostics", params: { uri: uri, diagnostics: [] }
      )
    end

    DIAGNOSTIC_SEVERITY = { error: 1, warning: 2, information: 3, hint: 4 }.freeze

    def to_lsp_diagnostic(finding)
      {
        range: finding.range, severity: DIAGNOSTIC_SEVERITY.fetch(finding.severity, 2), code: finding.code,
        source: "rslsp", message: finding.message, relatedInformation: finding.related_information
      }
    end

    def diagnostics_semantic_context
      Diagnostics::SemanticContext.new(
        workspace_index: @workspace_index, hierarchy_index: @hierarchy_index, method_resolver: @method_resolver,
        local_inferencer: @local_inferencer, model_registry: @model_registry, route_registry: @route_registry,
        signatures: @signatures, generation: @workspace_index.generation
      )
    end

    def diagnostics_mode_from(params)
      options = params && params[:initializationOptions]
      mode = options.is_a?(Hash) ? options[:diagnosticsMode] : nil
      Diagnostics::Engine::MODES.include?(mode&.to_sym) ? mode.to_sym : :safe
    end

    # Task 018: loads only manifests the client explicitly lists in
    # `initializationOptions.pluginManifests` -- never auto-discovered
    # from installed Gems ("自動検出したGemだけを理由にコード実行しない").
    # Each plugin's declarations (and generated-method facts, for ones
    # that gave a return_type) are merged in under a synthetic
    # `plugin://<name>` uri, exactly the same replace/remove-by-uri
    # contract every other per-file contribution to WorkspaceIndex/
    # HierarchyIndex/GeneratedMethodIndex already has -- a plugin's
    # contribution can be swapped wholesale on the next `initialize`
    # (there's no live reload endpoint yet) without leaving anything
    # behind. Runtime plugin loading (Plugins::Loader#load_runtime) is
    # implemented and tested but not called here -- forwarding a
    # runtime plugin's contributions into the actual Rails Runtime
    # Agent process is further work this task doesn't complete (see
    # Plugins::RuntimeContext's own docs).
    def load_static_plugins(params)
      options = params && params[:initializationOptions]
      manifest_paths = options.is_a?(Hash) ? options[:pluginManifests] : nil
      return unless manifest_paths.is_a?(Array) && !manifest_paths.empty?

      @plugin_loader.load_static(manifest_paths).each { |context| apply_plugin_context(context) }
    end

    def apply_plugin_context(context)
      return if context.declarations.empty?

      uri = "plugin://#{context.plugin_name}"
      declarations = context.declarations.map { |fact| plugin_declaration(fact) }
      summary = Index::FileSummary.new(
        uri: uri, content_hash: uri, document_version: nil, declarations: declarations, diagnostics: []
      )

      @workspace_index.replace_file(summary)
      @hierarchy_index.replace_file(summary)
      facts = context.declarations.filter_map { |fact| plugin_generated_fact(fact) }
      @generated_method_index.replace_file(uri: uri, facts: facts) unless facts.empty?
    end

    def plugin_declaration(fact)
      Index::Declaration.new(symbol_id: fact[:symbol_id], location: PLUGIN_LOCATION, visibility: :public,
                              parameters: [], origin: :plugin)
    end

    def plugin_generated_fact(fact)
      return nil unless fact[:return_type]

      symbol_id = fact[:symbol_id]
      Index::GeneratedMethodFact.new(
        owner: symbol_id.owner, name: symbol_id.name, kind: symbol_id.kind, return_type: fact[:return_type],
        source_location: PLUGIN_LOCATION, origin: :plugin, confidence: :high
      )
    end

    PLUGIN_LOCATION = { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }.freeze

    # Task 014: resolves this file's raw reference candidates (Prism-level
    # constant/local/ivar/cvar/method-call sites -- ParserService already
    # collected them into `summary.reference_candidates`) against the
    # *current* whole-workspace state, and replaces this uri's
    # contribution to ReferenceIndex. Errors degrade the same way
    # #reindex itself does: Find References for this file just stays
    # stale/empty rather than taking the server down.
    def index_references(uri, document, summary)
      references = @reference_resolver.resolve(document, summary.reference_candidates, uri: uri,
                                                          generation: @reference_index.generation)
      @reference_index.replace_file(uri: uri, references: references)
    rescue StandardError => e
      @logger.error("failed to resolve references for #{uri}: #{e.class}: #{e.message}")
    end

    # MethodSummaryStore's cache (Task 010, wired into resolution by Task
    # 013) is keyed by SymbolId, not by file, so it needs its own
    # invalidation trigger independent of WorkspaceIndex/HierarchyIndex —
    # every method a uri declared *before* this replace must be
    # invalidated (and, transitively, everything that depended on it),
    # or an edited method body would keep returning its stale cached
    # return type indefinitely.
    #
    # `previous_declarations` always comes from
    # WorkspaceIndex#declarations_for_uri, called by the caller *before*
    # its own #replace_file/#remove_file for the same uri — WorkspaceIndex
    # is the single write path every source (didOpen/didChange, disk
    # re-reads, Cold Index) already funnels through, so this needs no
    # Server-side bookkeeping of its own to stay in sync. An earlier
    # version of this fix kept a separate `@method_symbol_ids_by_uri`
    # shadow hash that only #reindex/#reindex_from_disk updated — Cold
    # Index populated WorkspaceIndex directly without touching it, so a
    # file only ever cold-indexed (never opened) whose *first* Server-side
    # touch was an external disk edit invalidated nothing, leaving a
    # stale cached return type for any method already summarized through
    # some other open file's call chain (found by an independent review;
    # deriving "previous" from WorkspaceIndex itself instead closes this
    # for every caller, present and future, rather than patching Cold
    # Index specifically). Deliberately invalidates on every replace
    # rather than diffing old/new declarations for real changes: matching
    # HierarchyIndex's own "always a full swap" policy, correctness over
    # cache-hit-rate here.
    def invalidate_method_summaries(declarations)
      symbol_ids = declarations.select { |d| %i[instance_method singleton_method].include?(d.symbol_id.kind) }
                               .map(&:symbol_id)
      @method_summary_store.invalidate(symbol_ids) unless symbol_ids.empty?
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
      hierarchy_index = @hierarchy_index
      document_store = @document_store
      logger = @logger

      Thread.new do
        ColdIndexer.new(root: root, parser_service: parser_service, workspace_index: workspace_index,
                        hierarchy_index: hierarchy_index, document_store: document_store, logger: logger).run
      rescue StandardError => e
        logger.error("cold index failed: #{e.class}: #{e.message}")
      end
    end

    # Best-effort: an RBS/Gem load failure must never block server startup
    # (docs/design/tasks/012-rbs-rbi-and-external-signatures.md "RBS/RBIロード
    # 失敗でRuby source解析を停止しない") — every downstream consumer already
    # treats a nil/empty Signatures::Environment as "no signature results",
    # never as an error.
    def load_signatures_environment
      env = Signatures::Environment.new
      env.load(workspace_root: @workspace_root)
      env
    rescue StandardError => e
      @logger.error("failed to load RBS signatures: #{e.class}: #{e.message}")
      env
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
      query_context = build_query_context(uri, position)
      type = erb_view?(uri) ? explain_type_in_view(document, position, query_context) : @query_service.type_at(document, position, budget: query_context.budget)
      warn_if_stale(query_context)
      { type: type.to_s }
    end

    def erb_view?(uri)
      uri.end_with?(".erb")
    end

    def explain_type_in_view(document, position, query_context = nil)
      ruby_source = Erb::RubyRegionExtractor.extract_ruby_source(document.text)
      synthetic = TextDocument.new(uri: document.uri, text: ruby_source, version: document.version, language_id: "ruby")

      @query_service.type_at(synthetic, position, initial_env: ivars_for_view(document.uri), budget: query_context&.budget)
    end

    # Task 013's QueryContext, actually constructed and consulted (a
    # follow-up review of Tasks 009-013 found it defined to match the
    # design doc's interface but never instantiated anywhere) — captures
    # each generation-bearing index's state *before* a query runs, so
    # #warn_if_stale can tell afterward whether a concurrent background
    # thread (ColdIndexer, the Runtime Agent) mutated it mid-computation.
    # `budget` stays nil (LocalInferencer's own default) for now; the
    # field exists so a future caller with an actual timeout need can set
    # it per-request without changing this plumbing.
    def build_query_context(uri, position)
      Semantic::QueryContext.new(
        uri: uri, position: position,
        workspace_generation: @workspace_index.generation, signature_generation: @signatures.generation
      )
    end

    # Only logged, not surfaced to the client -- LSP's hover/explainType
    # responses have no standard "this result may be stale" field, and a
    # result computed from an index that changed mid-query is still very
    # likely useful (usually, the change was unrelated to what was being
    # queried). This is observability, not a correctness guarantee.
    def warn_if_stale(query_context)
      return unless query_context.stale?(workspace_generation: @workspace_index.generation,
                                          signature_generation: @signatures.generation)

      @logger.warn("query for #{query_context.uri} at #{query_context.position} became stale mid-computation")
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

      position = params.fetch(:position)
      word = word_at_position(document, position)
      return [] unless word

      # A receiver-qualified call (Task 013) resolves through the type
      # engine first — it's a real answer, not a name-heuristic guess —
      # falling through to the lexical/route-helper heuristics either
      # when there's no receiver at all (a bare class/constant reference)
      # or the type engine found nothing for it.
      receiver_type = receiver_type_before_dot(document, position)
      typed = receiver_type ? @query_service.definitions_of(receiver_type, word) : []
      return typed unless typed.empty?

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

    # Task 014: finds the reference candidate ParserService already
    # recorded at `position` (the same candidate list #index_references
    # resolved into ReferenceIndex), resolves *that one* candidate again
    # to learn its SymbolId, then returns every location ReferenceIndex
    # has for that SymbolId. Resolving just the one clicked-on candidate
    # rather than looking up a pre-built "SymbolId at position" table
    # keeps this consistent with Hover/Definition/Completion's own "same
    # expression, same resolution path" property from Task 013 -- it's
    # the exact same #resolve a background reindex would have run.
    def references_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      summary = @file_summaries[uri]
      return [] unless document && summary

      position = params.fetch(:position)
      symbol_id = reference_symbol_id_at(document, summary, uri, position) || declaration_symbol_id_at(summary, position)
      return [] unless symbol_id

      @reference_index.references(symbol_id, minimum_confidence: :high).map { |r| { uri: r.uri, range: r.location } }
    end

    def reference_symbol_id_at(document, summary, uri, position)
      candidate = summary.reference_candidates.find { |c| position_within?(c.location, position) }
      return nil unless candidate

      @reference_resolver.resolve(document, [candidate], uri: uri, generation: @reference_index.generation).first&.symbol_id
    end

    # A click on the declaration site itself (`def build`, `class Widget`)
    # has no ReferenceCandidate of its own -- ParserService only records
    # *usage* sites -- so Find References triggered from a declaration
    # falls back to WorkspaceIndex's own per-file declarations instead.
    # Picks the *smallest* enclosing declaration among matches (not just
    # the first): a class's own range spans its entire body, so clicking
    # on a nested `def build`'s line would otherwise resolve to the
    # class itself, since `declarations` lists the class before its
    # methods.
    def declaration_symbol_id_at(summary, position)
      candidates = summary.declarations.select { |d| position_within?(d.location, position) }
      candidates.min_by { |d| range_span(d.location) }&.symbol_id
    end

    def range_span(range)
      [range[:end][:line] - range[:start][:line], range[:end][:character] - range[:start][:character]]
    end

    # Task 016: LSP `textDocument/prepareRename` -- answers whether the
    # symbol under the cursor can be renamed at all, and what range/
    # placeholder the editor should show while the user types the new
    # name. Returning nil (a null LSP result) tells the client to refuse
    # the rename UI outright, before the user even gets to type anything
    # -- used for generated Rails methods and positions with nothing
    # renameable under the cursor.
    def prepare_rename_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      summary = @file_summaries[uri]
      return nil unless document && summary

      symbol_id, range = symbol_id_and_range_at(document, summary, uri, params.fetch(:position))
      return nil unless symbol_id

      result = @rename_planner.prepare(symbol_id)
      return nil unless result

      { range: range, placeholder: result[:placeholder] }
    end

    # Task 016: LSP `textDocument/rename`. A refused Rename::Plan
    # (`confirmed_edits: []`) responds with a null WorkspaceEdit -- the
    # client shows nothing happened -- rather than an error response;
    # the refusal reason still goes to the log for anyone debugging why.
    def rename_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      summary = @file_summaries[uri]
      return nil unless document && summary

      symbol_id, = symbol_id_and_range_at(document, summary, uri, params.fetch(:position))
      return nil unless symbol_id

      plan = @rename_planner.plan(symbol_id, new_name: params.fetch(:newName), generation: @workspace_index.generation)
      if plan.confirmed_edits.empty?
        @logger.warn("rename refused for #{symbol_id.inspect}: #{plan.warnings.join('; ')}") unless plan.warnings.empty?
        return nil
      end

      { changes: plan.confirmed_edits.group_by { |e| e[:uri] }
                      .transform_values { |edits| edits.map { |e| { range: e[:range], newText: e[:new_text] } } } }
    end

    # Shared by prepareRename/rename: the same candidate-or-declaration
    # lookup #references_result uses (Task 014), but also returning the
    # exact range the resolved symbol was found at -- prepareRename needs
    # it to tell the client what to highlight/select.
    def symbol_id_and_range_at(document, summary, uri, position)
      candidate = summary.reference_candidates.find { |c| position_within?(c.location, position) }
      if candidate
        resolved = @reference_resolver.resolve(document, [candidate], uri: uri, generation: @reference_index.generation).first
        return [resolved.symbol_id, candidate.location] if resolved
      end

      declaration = summary.declarations.select { |d| position_within?(d.location, position) }.min_by { |d| range_span(d.location) }
      return [nil, nil] unless declaration

      [declaration.symbol_id, declaration.name_location || declaration.location]
    end

    def position_within?(range, position)
      start = range[:start]
      finish = range[:end]
      return false if position[:line] < start[:line] || position[:line] > finish[:line]
      return false if position[:line] == start[:line] && position[:character] < start[:character]
      return false if position[:line] == finish[:line] && position[:character] > finish[:character]

      true
    end

    # LSP CompletionItemKind values used below: Function=3, Method=2,
    # Field=5, Property=10.
    COMPLETION_KIND = { source: 2, model_column: 5, model_association: 10, signature: 2 }.freeze

    # Route helper completion (Task 006) is unconditional-on-nonempty-
    # prefix, unioned with QueryService member completion (Task 013) when
    # the cursor sits right after `receiver.` — the two candidate sources
    # answer genuinely different questions (a bare identifier vs. a
    # receiver's members) and neither should suppress the other.
    def completion_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return [] unless document

      position = params.fetch(:position)
      prefix = word_prefix_at_position(document, position)

      route_items = prefix.empty? ? [] : @route_registry.completion_names(prefix).map { |name| { label: name, kind: 3 } }
      route_items + member_completion_items(document, position, prefix)
    end

    def member_completion_items(document, position, prefix)
      receiver_type = receiver_type_before_dot(document, position)
      return [] unless receiver_type

      @query_service.members_of(receiver_type, prefix: prefix).map do |member|
        { label: member.name, kind: COMPLETION_KIND.fetch(member.origin, 1), detail: member.detail&.to_s }
      end
    end

    # Finds the call whose argument list the cursor is inside by scanning
    # backward for an unmatched `(`, then reads the identifier immediately
    # before it, and (Task 013) the receiver just before *that*, if any —
    # "route/通常method/RBSでSignature Helpが統一的に動く": a route helper
    # call is tried first (it has no Types receiver at all to look up
    # through QueryService), then an ordinary/RBS method call through
    # QueryService#signatures_of.
    def signature_help_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return { signatures: [] } unless document

      position = params.fetch(:position)
      method_name = enclosing_call_name(document, position)
      return { signatures: [] } unless method_name

      route_signature = route_signature_help(method_name)
      return route_signature if route_signature

      method_signature_help(document, position, method_name)
    end

    def route_signature_help(method_name)
      helper = @route_registry.find_by_method_name(method_name)
      return nil unless helper

      # `method_name` is exactly what the user typed (`post_path` or
      # `post_url` -- #find_by_method_name resolves both back to the same
      # helper), so the signature echoes that, not always path_helper
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      required_labels = helper.required_parts
      optional_labels = helper.optional_parts.map { |part| "#{part} = nil" }
      params_label = (required_labels + optional_labels + ["options = {}"]).join(", ")
      {
        signatures: [
          {
            label: "#{method_name}(#{params_label})",
            parameters: required_labels.map { |part| { label: part } } +
              optional_labels.map { |label| { label: label } }
          }
        ]
      }
    end

    def method_signature_help(document, position, method_name)
      call_start = call_name_position(document, position)
      receiver_type = call_start && receiver_type_before_dot(document, call_start)
      return { signatures: [] } unless receiver_type

      signatures = @query_service.signatures_of(receiver_type, method_name)
      { signatures: signatures }
    end

    def enclosing_call_name(document, position)
      range = enclosing_call_name_range(document, position)
      return nil unless range

      document.text[range]
    end

    # The char-offset Range of the identifier immediately before the
    # unmatched `(` enclosing `position`, or nil if there isn't one —
    # shared by #enclosing_call_name (which just wants the text) and
    # #call_name_position (Task 013, which needs the *position* to look
    # up a receiver before it).
    def enclosing_call_name_range(document, position)
      text = document.text
      idx = document.position_to_char_offset(position) - 1
      idx -= 1 while idx >= 0 && text[idx] != "("
      return nil if idx.negative?

      name_end = idx
      name_start = name_end
      name_start -= 1 while name_start.positive? && word_char?(text[name_start - 1])
      return nil if name_start == name_end

      name_start...name_end
    end

    def call_name_position(document, position)
      range = enclosing_call_name_range(document, position)
      range && document.char_offset_to_position(range.begin)
    end

    # If `position` sits on an identifier immediately preceded by `.`
    # (`receiver.|method`, cursor anywhere in "method"), returns the
    # receiver expression's own type — computed by querying #type_at
    # exactly at the `.`'s position, which #infer_at resolves to whatever
    # node the `.` falls inside (the receiver, never the call itself).
    # This is the one piece of position math Hover/Completion/Signature
    # Help all share, which is what actually makes Task 013's "同一式に
    # ついてHoverとCompletionが同じreceiver型を利用する" true rather than
    # just documented.
    def receiver_type_before_dot(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = offset
      left -= 1 while left > 0 && word_char?(text[left - 1])
      return nil if left.zero? || text[left - 1] != "."

      dot_position = document.char_offset_to_position(left - 1)
      type = @query_service.type_at(document, dot_position)
      type == Types::UNKNOWN ? nil : type
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
      needs_full_models_refresh = false

      params.fetch(:changes, []).each do |change|
        uri = change.fetch(:uri)
        if change.fetch(:type) == FILE_CHANGE_DELETED
          previous_declarations = @workspace_index.declarations_for_uri(uri)
          @workspace_index.remove_file(uri)
          @hierarchy_index.remove_file(uri)
          @reference_index.remove_file(uri)
          @generated_method_index.remove_file(uri)
          invalidate_method_summaries(previous_declarations)
          @file_summaries.delete(uri)
        elsif @document_store.fetch(uri: uri).nil?
          # An open buffer is always authoritative over what's on disk; only
          # reindex from disk for files nobody currently has open.
          reindex_from_disk(uri)
        end

        case classify_rails_change(uri)
        when :routes then needs_routes_refresh = true
        when :restart then needs_restart = true
        when :schema then needs_full_models_refresh = true
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
      # A schema-wide change (a migration, `db/schema.rb`/`structure.sql`
      # regenerated) can alter any model's columns, not just one whose own
      # file changed — a full model-table refresh subsumes any individual
      # #refresh_models call this same batch would otherwise also trigger,
      # so it takes priority and the per-file path is skipped
      # (docs/design/tasks/008.6-agent-and-index-hardening.md).
      if needs_full_models_refresh
        with_ready_agent("db/schema.rb") { refresh_all_models }
      elsif !changed_models.empty?
        with_ready_agent("app/models/*") { refresh_models(changed_models) }
      end
    end

    SCHEMA_FILE_PATTERNS = [%r{db/schema\.rb\z}, %r{db/structure\.sql\z}, %r{db/migrate/}].freeze

    def classify_rails_change(uri)
      path = UriUtil.to_path(uri) || uri
      return :routes if path.end_with?("config/routes.rb")
      return :restart if path.end_with?("Gemfile.lock") || path.include?("config/initializers/")
      return :schema if SCHEMA_FILE_PATTERNS.any? { |pattern| pattern.match?(path) }

      nil
    end

    def model_name_for(uri)
      path = UriUtil.to_path(uri) || uri
      match = MODEL_FILE_PATTERN.match(path)
      return nil unless match

      match[:relative].split("/").map { |segment| Routes::ControllerNaming.camelize(segment) }.join("::")
    end

    # The read_sequence is fetched *before* reading the file, not after,
    # so ordering reflects when each disk read actually observed the
    # file's content, not when its #replace_file call happened to arrive
    # — see WorkspaceIndex#stale?'s comment
    # (docs/design/tasks/008.6-agent-and-index-hardening.md).
    def reindex_from_disk(uri)
      path = UriUtil.to_path(uri)
      return unless path && File.file?(path)

      read_sequence = @workspace_index.next_read_sequence
      document = TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8), version: nil,
                                   language_id: "ruby")
      summary = @parser_service.summarize(document).with(source: :disk, read_sequence: read_sequence)
      previous_declarations = @workspace_index.declarations_for_uri(uri)
      if @workspace_index.replace_file(summary)
        @hierarchy_index.replace_file(summary)
        @file_summaries[uri] = summary
        invalidate_method_summaries(previous_declarations)
        index_references(uri, document, summary)
        @generated_method_index.replace_file(uri: uri, facts: summary.generated_method_facts)
      end
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
    #
    # The final write is guarded by @agent_restart_mutex and an identity
    # check against the *current* @agent_manager: this thread captured a
    # specific manager instance at call time, and if a restart (Gemfile.lock,
    # an initializer change) swaps in a fresh one — and fully repopulates
    # both registries — while this thread's own round trip was still in
    # flight, its (now stale, from the old Agent generation) result must
    # not land on top of the new Agent's already-current data
    # (docs/design/tasks/008.6-agent-and-index-hardening.md). `snapshot`
    # itself is also checked for nil separately from an empty routes list,
    # so a communication failure (timeout, degraded Agent) never gets
    # treated as "the app genuinely has zero routes" and wipes the
    # registry — it leaves the last-known-good routes in place instead.
    def refresh_routes
      agent_manager = @agent_manager
      route_registry = @route_registry
      logger = @logger
      mutex = @agent_restart_mutex

      Thread.new do
        next unless agent_manager.reload(sections: ["routes"])

        snapshot = agent_manager.fetch_snapshot(sections: ["routes"])
        unless snapshot
          logger.warn("failed to fetch routes snapshot after routes.rb change; keeping last-known-good routes")
          next
        end

        mutex.synchronize do
          next unless agent_manager.equal?(@agent_manager)

          route_registry.replace(snapshot[:routes] || [])
        end
      rescue StandardError => e
        logger.error("failed to refresh routes after routes.rb change: #{e.class}: #{e.message}")
      end
    end

    # Asks the Agent to reload models first (Rails' own autoloader
    # unload/reload for app/models -- docs/design/tasks/008.5-runtime-and-index-corrections.md)
    # before re-fetching each changed name, so a deleted or renamed
    # model's class is actually gone by the time #fetch_model asks about
    # it, instead of an agent/model NOT_FOUND response never coming
    # because the old class is still defined. A NOT_FOUND after that
    # reload removes the entry from ModelRegistry rather than leaving its
    # last-known columns/associations behind. One reload per batch (not
    # per model) -- a Rails reload is whole-app regardless of which
    # specific file triggered it.
    # Same stale-generation guard as #refresh_routes: each per-model write
    # is checked against the *current* @agent_manager (not just once
    # before the loop), since a restart can land partway through a batch
    # of models just as easily as between #refresh_models calls
    # (docs/design/tasks/008.6-agent-and-index-hardening.md).
    def refresh_models(names)
      agent_manager = @agent_manager
      model_registry = @model_registry
      logger = @logger
      mutex = @agent_restart_mutex

      Thread.new do
        agent_manager.reload(sections: ["models"])

        names.each do |name|
          response = agent_manager.fetch_model(name: name)
          next unless response

          mutex.synchronize do
            next unless agent_manager.equal?(@agent_manager)

            if response[:error]
              model_registry.remove(name)
            else
              model_registry.register_from_agent_response(name, response)
            end
          end
        end
      rescue StandardError => e
        logger.error("failed to refresh models #{names.to_a.join(', ')}: #{e.class}: #{e.message}")
      end
    end

    # A migration, `db/schema.rb`, or `db/structure.sql` change can alter
    # any model's columns/associations, not just one whose own file
    # changed, so this re-fetches every model in one bulk agent/models
    # round trip and installs it as a full generation-replace (mirroring
    # RailsBootstrap#populate_registries at startup) rather than looping
    # over a specific name list (docs/design/tasks/008.6-agent-and-index-hardening.md).
    # Same failure-preserves-last-known-good and stale-Agent-generation
    # guards as #refresh_routes/#refresh_models: a nil fetch (communication
    # failure) leaves the registry untouched instead of wiping it, and the
    # write is dropped if a restart has already replaced @agent_manager by
    # the time this round trip completes.
    def refresh_all_models
      agent_manager = @agent_manager
      model_registry = @model_registry
      logger = @logger
      mutex = @agent_restart_mutex

      Thread.new do
        agent_manager.reload(sections: ["models"])

        models = agent_manager.fetch_all_models
        unless models
          logger.warn("failed to fetch models after a schema change; keeping last-known-good models")
          next
        end

        mutex.synchronize do
          next unless agent_manager.equal?(@agent_manager)

          responses_by_name = models.filter_map { |entry| entry[:name] && [entry[:name], entry] }.to_h
          model_registry.replace(responses_by_name)
        end
      rescue StandardError => e
        logger.error("failed to refresh models after a schema change: #{e.class}: #{e.message}")
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
          referencesProvider: true,
          renameProvider: { prepareProvider: true },
          workspaceSymbolProvider: true,
          completionProvider: { triggerCharacters: ["."] },
          signatureHelpProvider: { triggerCharacters: ["("] }
        },
        serverInfo: {
          name: "rslsp",
          version: Rslsp::VERSION
        }
      }
    end

    # Task 013: a real, type-engine-backed hover. Deliberately conservative
    # about what it shows — "情報不足時は断定的な表示を避ける"
    # (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md):
    # an unresolved expression gets an empty hover, never a guessed one.
    def hover_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return empty_hover unless document

      position = params.fetch(:position)
      query_context = build_query_context(uri, position)
      type = erb_view?(uri) ? explain_type_in_view(document, position, query_context) : @query_service.type_at(document, position, budget: query_context.budget)
      warn_if_stale(query_context)
      lines = hover_lines(document, position, type)
      return empty_hover if lines.empty?

      { contents: { kind: "plaintext", value: lines.join("\n") } }
    end

    def empty_hover
      { contents: { kind: "plaintext", value: "" } }
    end

    # Same #receiver_type_before_dot Completion/Definition already use
    # (Task 013's "同一式についてHoverとCompletionが同じreceiver型を利用す
    # る"): when the cursor sits on a receiver-qualified method call, the
    # extra Origin/Defined lines come from the exact same #members_of /
    # #definitions_of a completion or go-to-definition request for the
    # identical position would use. The overall expression type may still
    # be Unknown even when its origin/definition are known (LocalInferencer
    # doesn't chase a source method's own body to infer its return type),
    # so this only omits the "-> Type" line for Unknown, rather than
    # discarding a hover that otherwise has real content to show.
    def hover_lines(document, position, type)
      lines = type == Types::UNKNOWN ? [] : [type.to_s]

      word = word_at_position(document, position)
      # Skipped for .erb views: #receiver_type_before_dot queries #type_at
      # directly against `document`, which only works for a plain Ruby
      # buffer -- an .erb view needs the synthetic-source/ivar-seeded path
      # #explain_type_in_view already used just above for `type` itself.
      receiver_type = word && !erb_view?(document.uri) && receiver_type_before_dot(document, position)
      if receiver_type
        origin = hover_origin(receiver_type, word)
        lines << "Origin: #{origin}" if origin

        location = @query_service.definitions_of(receiver_type, word).first
        lines << "Defined: #{location[:uri]}:#{location[:range][:start][:line] + 1}" if location
      end

      lines
    end

    HOVER_ORIGIN_LABEL = {
      source: "source declaration", model_column: "Active Record column",
      model_association: "Active Record association", signature: "RBS/Gem signature"
    }.freeze

    def hover_origin(receiver_type, word)
      member = @query_service.members_of(receiver_type, prefix: word).find { |m| m.name == word }
      member && HOVER_ORIGIN_LABEL[member.origin]
    end

    def respond(id, result)
      @writer.write_message(jsonrpc: JSONRPC_VERSION, id: id, result: result)
    end

    def respond_error(id, code:, message:)
      @writer.write_message(jsonrpc: JSONRPC_VERSION, id: id, error: { code: code, message: message })
    end
  end
end
