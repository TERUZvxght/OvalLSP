# frozen_string_literal: true

require "set"
require "digest"
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
require_relative "background_tasks"
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

module Ovallsp
  # LSP transport + request router. Task 001 scope: initialize/initialized,
  # didOpen/didChange/didClose, a fixed hover response, and shutdown/exit.
  # Task 002 adds per-document FileSummary extraction (Prism) and
  # textDocument/documentSymbol. Task 003 adds a workspace-wide index behind
  # textDocument/definition (lexical, name-based — see WorkspaceIndex),
  # workspace/symbol, and workspace/didChangeWatchedFiles. Task 004 adds the
  # custom ovallsp/explainType request, backed by LocalInferencer. Task 006
  # adds route-helper completion/signatureHelp/definition, backed by a
  # Routes::RouteRegistry either injected directly (tests) or populated by
  # RailsBootstrap once the client confirms the workspace is trusted (see
  # #maybe_start_agent — docs/02-architecture.md section 11: untrusted
  # workspaces get static analysis only, never Agent/Bundler code
  # execution). Task 008 makes ovallsp/explainType propagate a conventional
  # controller action's instance variables into its .erb view.
  class Server
    JSONRPC_VERSION = "2.0"

    METHOD_NOT_FOUND = -32601
    INTERNAL_ERROR = -32603

    FILE_CHANGE_DELETED = 3

    def initialize(input:, output:, logger:, route_registry: Routes::RouteRegistry.new,
                   model_registry: Models::ModelRegistry.new, workspace_root: Dir.pwd,
                   ancestry_registry: Runtime::AncestryRegistry.new,
                   agent_bootstrap: RailsBootstrap, background_task_shutdown_timeout: BackgroundTasks::DEFAULT_SHUTDOWN_TIMEOUT)
      @reader = Ovallsp::IO::FramedReader.new(input)
      @writer = Ovallsp::IO::FramedWriter.new(output)
      @logger = logger
      @workspace_root = workspace_root
      @document_store = DocumentStore.new
      @parser_service = ParserService.new
      @workspace_index = WorkspaceIndex.new
      @signatures = load_signatures_environment
      @hierarchy_index = Semantic::HierarchyIndex.new(workspace_index: @workspace_index)
      @method_resolver = Semantic::MethodResolver.new(workspace_index: @workspace_index, hierarchy_index: @hierarchy_index)
      @method_summary_store = Semantic::MethodSummaryStore.new
      @generated_method_index = Semantic::GeneratedMethodIndex.new
      @observation_store = Observation::Store.new
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
      @helper_ivars = {}
      @workspace_pass_mutex = Mutex.new
      @workspace_pass_running = false
      @workspace_pass_requested = false
      @local_inferencer = LocalInferencer.new(
        model_registry: model_registry, method_resolver: @method_resolver, method_analyzer: @method_analyzer,
        signatures: @signatures, observation_store: @observation_store
      )
      @route_registry = route_registry
      @model_registry = model_registry
      @ancestry_registry = ancestry_registry
      @agent_bootstrap = agent_bootstrap
      @agent_manager = nil
      @agent_restart_mutex = Mutex.new
      @agent_refresh_mutex = Mutex.new
      # Serializing agent refreshes fixed out-of-order writes but made
      # every refresh queue behind the previous one, so a wedged Agent
      # (each round trip burning its full timeout) accumulated blocked
      # threads without bound -- a rebase or a long migration can fire
      # didChangeWatchedFiles repeatedly, and every one of those queued
      # refreshes is already stale by the time it runs.
      #
      # Whole-section refreshes are superseded by generation: only the
      # newest queued routes/all-models refresh does the work. Targeted
      # model refreshes cannot be dropped that way -- a later refresh of
      # ["Team"] says nothing about an earlier ["User"] -- so their names
      # are coalesced into one pending set instead, and whichever thread
      # wins the mutex drains and refreshes the whole set at once.
      @refresh_state_mutex = Mutex.new
      @refresh_generations = Hash.new(0)
      @pending_model_names = []
      @model_refresh_waiter = nil
      @ancestry_question_worker = nil
      @file_summaries = {}
      @index_mutation_mutex = Mutex.new
      @shutdown_received = false
      @query_service = Semantic::QueryService.new(
        local_inferencer: @local_inferencer, method_resolver: @method_resolver, model_registry: @model_registry,
        signatures: @signatures, workspace_index: @workspace_index
      )
      @workspace_diagnostics = WorkspaceDiagnostics.new(
        analyze: method(:workspace_findings_for),
        publish: method(:publish_findings),
        open_in_buffer: ->(uri) { !@document_store.fetch(uri: uri).nil? },
        logger: @logger
      )
      @prefix_completion = Semantic::PrefixCompletion.new(
        query_service: @query_service, workspace_index: @workspace_index
      )
      @reference_index = Semantic::ReferenceIndex.new
      @reference_state_mutex = Mutex.new
      @reference_rebuild_mutex = Mutex.new
      @reference_dirty_token = 0
      @reference_built_token = -1
      @reference_built_semantic_generation = nil
      @reference_resolver = Semantic::ReferenceResolver.new(
        workspace_index: @workspace_index, method_resolver: @method_resolver, local_inferencer: @local_inferencer,
        model_registry: @model_registry, route_registry: @route_registry
      )
      @diagnostics_engine = Diagnostics::Engine.new
      @diagnostics_mode = :safe
      @rename_planner = Rename::Planner.new(workspace_index: @workspace_index, reference_index: @reference_index)
      @plugin_loader = Plugins::Loader.new(logger: @logger)
      @observation_runner = Observation::Runner.new(logger: @logger)
      @observation_test_command = nil
      @cold_indexing = false
      # Per-uri memory of the last version published, and the mutex that
      # orders every writer against it. See #publish_findings.
      @last_published_version = {}
      @publish_state_mutex = Mutex.new
      @agent_supervisor = AgentSupervisor.new
      @agent_retry_mutex = Mutex.new
      @agent_retry_generation = 0
      @background_tasks = BackgroundTasks.new(shutdown_timeout: background_task_shutdown_timeout)
    end

    # Runs the read/dispatch loop until `exit` is received or the input
    # stream closes. Returns the process exit code the LSP spec expects:
    # 0 if `shutdown` preceded `exit`, 1 otherwise.
    #
    # `ensure shutdown_background_tasks` runs on every exit path -- EOF
    # (client disconnected without a clean shutdown/exit), a normal
    # `exit`, or an exception escaping the loop -- so a Runtime Agent
    # bootstrap thread (or any other background thread Server owns) never
    # outlives #run itself. Found necessary by a leaked bootstrap thread
    # surviving past the end of the RSpec example that started it and
    # touching that example's already-torn-down RSpec doubles from inside
    # a *later* example (spec/ovallsp/server_workspace_trust_spec.rb).
    def run
      loop do
        message = begin
          @reader.read_message
        rescue Ovallsp::IO::FramedReader::EOF
          break
        rescue Ovallsp::IO::FramedReader::ProtocolError => e
          # A malformed frame carries no id, so there is nobody to answer
          # -- but it is also not a reason to end the session. Until
          # 0.2.6 every one of these (`Content-Length: -5`, a missing
          # header, a body that is not JSON) escaped `run` and the
          # process exited 1 with a raw backtrace, leaving the client's
          # next request unanswered. Only a client can send one, but a
          # reconnect or one stray byte on stdin was enough.
          @logger.error("skipping a malformed message: #{e.message}")
          next
        end

        break if dispatch(message) == :exit
      end

      @shutdown_received ? 0 : 1
    ensure
      shutdown_background_tasks
    end

    private

    # Idempotent (BackgroundTasks#shutdown itself no-ops on a second
    # call), bounded (never an unlimited #join -- see BackgroundTasks),
    # and must never raise out of #run's `ensure` -- a cleanup failure is
    # logged and swallowed, not left to crash the whole process on its way
    # out.
    def shutdown_background_tasks
      # Asked to stop *before* the bounded join, not left for it: a
      # workspace pass checks its token between files, so closing it first
      # lets it finish the file it is on and return. #close rather than
      # #begin_pass: a pass is started from inside another background
      # thread, which could otherwise begin a fresh, valid one after this
      # point and be killed by the join instead of returning (0.2.0).
      @workspace_diagnostics&.close
      @background_tasks.shutdown
    rescue StandardError => e
      begin
        @logger.error("error during background task shutdown: #{e.class}: #{e.message}")
      rescue StandardError
        nil
      end
    end

    # The one place `bootstrap.start`'s return value is trusted: contract
    # is "an object responding to #ready?/#stop, or nil"
    # (docs/design/tasks/022-compatibility-resilience-and-release.md).
    # A test double, or a future bootstrap implementation, that returns
    # something else (a Symbol, an Integer -- `sleep`'s own return value
    # bit a real bug in this codebase's own spec fixtures once) must not
    # crash whatever thread happens to call `#ready?` on it next; it
    # degrades to static-only instead, the same outcome as a genuine
    # bootstrap failure. This check is a boundary safety net, not a
    # substitute for the thread-lifecycle fix above -- it doesn't change
    # when or whether a bootstrap thread gets reclaimed, only what happens
    # to whatever value it happened to produce.
    def coerce_agent_manager(candidate)
      return nil if candidate.nil?
      return candidate if candidate.respond_to?(:stop)

      @logger.error(
        "Runtime Agent bootstrap returned a #{candidate.class} instead of nil or an object responding to " \
        "#stop; treating this as a contract violation and falling back to static-only mode"
      )
      nil
    end

    # A plain `manager&.ready?` isn't safe here: #coerce_agent_manager's
    # minimal contract check only requires #stop, and several existing
    # test doubles across this codebase intentionally model a manager that
    # implements #stop but not #ready? -- and the underlying reported bug
    # was exactly a NoMethodError from calling #ready? on a value that
    # didn't have it (there, an Integer that failed #coerce_agent_manager's
    # check too, but the same guard belongs here as well since a
    # #stop-only manager legitimately passes that check).
    def agent_manager_ready?(manager)
      manager.respond_to?(:ready?) && manager.ready?
    end

    # The editor's `rootUri` is the workspace root, not whatever this
    # process's cwd resolves to.
    #
    # Core never read `rootUri` at all and defaulted to `Dir.pwd`. The
    # extension spawns it with `cwd: folder.uri.fsPath`, and a child
    # started with its cwd on a symlink reports the **resolved** path --
    # so the workspace pass built every uri under the real path while
    # every editor-driven message used the symlink path. The same file
    # then appeared twice in the Problems panel, and the resolved-path
    # copy could never be cleared, because nothing publishes to that uri
    # again (`024.98`). A symlinked checkout is ordinary: `/tmp` on
    # macOS, git worktrees, `~/src` pointing at a volume.
    #
    # `rootUri` wins because it is what the user sees and what every
    # editor-driven message carries. A client that sends none keeps this
    # process's cwd, which is what a direct stdio session and every
    # existing caller rely on.
    #
    # Only before anything has been indexed: this runs from `initialize`,
    # which is the first message, so nothing has been recorded under the
    # old root yet.
    def adopt_client_workspace_root(params)
      root_uri = params.is_a?(Hash) ? params[:rootUri] : nil
      return if root_uri.nil? || root_uri.to_s.empty?

      path = UriUtil.to_path(root_uri.to_s)
      return unless path && File.directory?(path)

      @logger.info("workspace root from the client: #{path}") unless path == @workspace_root
      @workspace_root = path
    end

    def dispatch(message)
      method = message[:method]
      id = message[:id]

      case method
      when "initialize"
        adopt_client_workspace_root(message[:params])
        @diagnostics_mode = diagnostics_mode_from(message[:params])
        @observation_test_command = observation_test_command_from(message[:params])
        # Kept, not merely consulted. Until 0.2.5 trust was read out of
        # these params at `maybe_start_agent` and nowhere else, so every
        # other request that reaches code execution had to be trusted to
        # not need it -- which is a property of the callers, not of the
        # server. `initialize` is the only message that carries it, so
        # this is the only place it can be recorded.
        @workspace_trusted = workspace_trusted?(message[:params])
        respond(id, initialize_result)
        load_static_plugins(message[:params])
        start_cold_index
        maybe_start_agent
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
        respond(id, with_index_snapshot { hover_result(message[:params]) })
      when "textDocument/documentSymbol"
        respond(id, with_index_snapshot { document_symbol_result(message[:params]) })
      when "textDocument/definition"
        respond(id, with_index_snapshot { definition_result(message[:params]) })
      when "workspace/symbol"
        respond(id, with_index_snapshot { workspace_symbol_result(message[:params]) })
      when "workspace/didChangeWatchedFiles"
        handle_did_change_watched_files(message[:params])
      when "ovallsp/explainType"
        respond(id, with_index_snapshot { explain_type_result(message[:params]) })
      when "textDocument/completion"
        respond(id, with_index_snapshot { completion_result(message[:params]) })
      when "textDocument/semanticTokens/full"
        respond(id, semantic_tokens_result(message[:params]))
      when "completionItem/resolve"
        respond(id, with_index_snapshot { completion_resolve_result(message[:params]) })
      when "textDocument/signatureHelp"
        respond(id, with_index_snapshot { signature_help_result(message[:params]) })
      when "textDocument/references"
        respond(id, with_index_snapshot { references_result(message[:params]) })
      when "textDocument/prepareRename"
        respond(id, with_index_snapshot { prepare_rename_result(message[:params]) })
      when "textDocument/rename"
        respond(id, with_index_snapshot { rename_result(message[:params]) })
      when "ovallsp/runObservedTests"
        respond(id, run_observed_tests_result(message[:params]))
      when "ovallsp/clearObservedTypes"
        respond(id, clear_observed_types_result(message[:params]))
      when "ovallsp/showTypeEvidence"
        respond(id, with_index_snapshot { show_type_evidence_result(message[:params]) })
      when "ovallsp/status"
        respond(id, status_result(message[:params]))
      when "ovallsp/restartAgent"
        respond(id, restart_agent_result(message[:params]))
      when "ovallsp/reindexWorkspace"
        respond(id, reindex_workspace_result(message[:params]))
      else
        handle_unknown_method(method, id)
      end

      nil
    rescue StandardError => e
      handle_dispatch_error(method, id, e)
      nil
    end

    def with_index_snapshot(&block)
      @index_mutation_mutex.synchronize(&block)
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
      # `@file_summaries.delete(uri)` used to run here too, outside the
      # index lock -- redundant, since #remove_index_contribution deletes
      # the same key one line below *inside* it, and a lock-discipline
      # exception the rest of this file no longer makes.

      # Unconditional and first: WorkspaceIndex#replace_file now refuses to
      # let any disk-sourced summary overwrite a buffer-sourced one for the
      # same uri (the whole point of Task 008.6's open-buffer-always-wins
      # guarantee) — closing the buffer is the one legitimate transition
      # away from that protection, and it must happen *before*
      # #reindex_from_disk's own replace_file call, or that call would see
      # a still-buffer-sourced existing entry and be silently rejected as
      # stale (docs/design/tasks/008.6-agent-and-index-hardening.md).
      @index_mutation_mutex.synchronize { remove_index_contribution(uri) }
      clear_findings(uri)

      path = UriUtil.to_path(uri)
      publish_workspace_diagnostics_later(uri) if path && File.file?(path) && reindex_from_disk(uri)
    end

    def reindex(document)
      summary = @parser_service.summarize(document)
      if apply_file_summary(summary)
        invalidate_stale_observations
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
    # needing its own generation check.
    #
    # This is the *buffer* path. Until 0.2.0 it was the only one, on the
    # reasoning that an unopened file has no client-side buffer to attach
    # a notification to -- which `WorkspaceDiagnostics`' own header
    # rejects, because LSP does not work that way: a client shows a
    # `publishDiagnostics` for any uri. `#reindex_from_disk` now publishes
    # too, through the workspace pass rather than here, so that the two
    # cannot both claim the last word on one uri.
    def publish_diagnostics(document)
      # Whether there is a running application to ask has to be known
      # *before* the check runs, not after: a receiver it cannot judge
      # statically is one it must defer on rather than guess about, and
      # deferring is only right when an answer can actually arrive.
      @ancestry_registry.activate! if agent_manager_ready?(@agent_manager)
      findings = with_index_snapshot do
        context = diagnostics_semantic_context.with(assigned_ivars: assigned_ivars_for(document.uri, document))
        @diagnostics_engine.analyze(document: document, semantic_context: context, mode: @diagnostics_mode)
      end
      publish_findings(document.uri, findings, version: document.version)
    rescue StandardError => e
      @logger.error("failed to compute diagnostics for #{document.uri}: #{e.class}: #{e.message}")
    ensure
      # Outside the rescue above, which is about computing *this*
      # document's diagnostics: a failure to dispatch the Agent question
      # reported as "failed to compute diagnostics for <uri>" would send
      # anyone reading the log to entirely the wrong place.
      begin
        answer_pending_ancestry_questions
      rescue StandardError => e
        @logger.error("failed to ask the Runtime Agent about pending ancestries: #{e.class}: #{e.message}")
      end
    end

    # The one funnel every publish goes through, and since 0.2.7 the one
    # place that remembers what was last sent for a uri.
    #
    # Four kinds of writer reach here: the dispatch thread, the workspace
    # pass on its own thread, the background republish sites, and the
    # changed-files batch thread. Nothing ordered them, and `024.56`
    # records the reproduced sequence for a closed file -- findings, the
    # clear, the findings again -- present in every shipped build. The
    # same gap the other way round puts stale findings back over newer
    # ones.
    #
    # Four rules, all per-uri and all decided *and written* under one
    # mutex. The lock spans the write on purpose: holding it only over the
    # decision orders admission rather than arrival, so an admitted older
    # publish could still reach the client after a newer one -- observed
    # by parking a thread between the two. It costs nothing, because
    # `FramedWriter` serialises every frame anyway.
    #
    # - **A versioned publish is a buffer's answer**, so that buffer must
    #   still be open. This is `024.56`'s sequence: findings, the clear on
    #   `didClose`, then a background pass already in flight arriving with
    #   the findings again. The version rule alone cannot stop it, because
    #   the clear resets the memory.
    # - **And it must be the same buffer.** The first version of this
    #   funnel checked only that *something* was open, and that introduced
    #   a worse defect than the one it fixed: close a tab mid-republish
    #   and reopen it, the editor hands out a fresh document at version 1,
    #   the stale publish at version 47 finds an open buffer and an empty
    #   memory, and every edit afterwards is refused as older. The panel
    #   then shows the pre-close errors on text already fixed, for as many
    #   edits as the old buffer had accumulated. A buffer never publishes
    #   ahead of itself -- the document came out of the store -- so a
    #   version above what the store holds now belongs to a closed one.
    # - **An older version is dropped**; the *same* version is let
    #   through, because a later pass legitimately knows more about it
    #   (the Agent answering, routes arriving) and refusing it would
    #   switch those off.
    # - **A clear always wins and resets**, because closing a file is not
    #   something a stale computation may overrule.
    #
    # A versionless publish is the workspace pass, which analyses files
    # nobody has open. It is not ordered against a buffer's numbers -- but
    # it is refused for a uri that *is* open, which is the property
    # `WorkspaceDiagnostics` already believes it holds and enforces with a
    # two-statement check a `didOpen` can land inside. The funnel holds
    # the uri, so it can make that true rather than likely.
    #
    # The memory lives here rather than in `FramedWriter`, which also
    # carries responses and must stay a dumb frame mutex. 029's M-3, and
    # it rests on M-2: ordering by a version number is only meaningful
    # once text and version cannot be read torn.
    # Answers whether the publish reached the client, because a caller can
    # need to know: `WorkspaceDiagnostics` counts analysed files by it,
    # and that count bounds the pass and drives its truncation log. It
    # returned `true` unconditionally and so counted files nothing was
    # published for.
    def publish_findings(uri, findings, version: nil)
      @publish_state_mutex.synchronize do
        open_version = @document_store.fetch(uri: uri)&.version
        if version
          return false if open_version.nil? || version > open_version

          last = @last_published_version[uri]
          return false if last && version < last

          @last_published_version[uri] = version
        elsif open_version
          return false
        end

        write_diagnostics(uri, findings, version)
        true
      end
    end

    # Clearing a file's diagnostics, and forgetting what it was at. Called
    # when a buffer closes and when a file leaves the workspace. Under the
    # same lock as a publish, so it cannot be interleaved with one.
    def clear_findings(uri)
      @publish_state_mutex.synchronize do
        @last_published_version.delete(uri)
        write_diagnostics(uri, [], nil)
      end
    end

    def write_diagnostics(uri, findings, version)
      @writer.write_message(
        jsonrpc: JSONRPC_VERSION, method: "textDocument/publishDiagnostics",
        params: { uri: uri, version: version, diagnostics: findings.map { |f| to_lsp_diagnostic(f) } }
      )
    end

    # The same analysis the buffer path runs, minus the notification: the
    # workspace pass owns when and whether to publish, because it also
    # owns the decision to abandon a superseded pass mid-file (0.2.0).
    #
    # `assigned_ivars:` included, for the same reason it is on the buffer
    # path. The pass visits `.erb` as well as `.rb`, and
    # `unassigned_ivar_findings` returns [] when the context does not
    # carry it -- so leaving it out silently switched that check off for
    # every view nobody had open, which is most of them. It is the same
    # call in the same place inside the snapshot, so the two paths cannot
    # answer differently about one view.
    def workspace_findings_for(document)
      @ancestry_registry.activate! if agent_manager_ready?(@agent_manager)
      with_index_snapshot do
        context = diagnostics_semantic_context.with(assigned_ivars: assigned_ivars_for(document.uri, document))
        @diagnostics_engine.analyze(document: document, semantic_context: context, mode: @diagnostics_mode)
      end
    ensure
      # `analyze` *records* the ancestries it had to defer on; something
      # has to ask. The buffer path drains in its own `ensure` and this
      # one did not, so a receiver deferred in an unopened file waited
      # until an open buffer happened to trigger a drain -- which, on a
      # workspace where nothing is open, is never.
      begin
        answer_pending_ancestry_questions
      rescue StandardError => e
        @logger.error("failed to ask the Runtime Agent about pending ancestries: #{e.class}: #{e.message}")
      end
    end

    # One file, analyzed on a background thread. The pass's own generation
    # is not claimed here: this is not a workspace pass and must not
    # supersede one that is running.
    def publish_workspace_diagnostics_later(uri)
      @background_tasks.track_thread(Thread.new do
        @workspace_diagnostics.publish_for(uri)
      rescue StandardError => e
        @logger.error("failed to publish diagnostics for #{uri}: #{e.class}: #{e.message}")
      end)
    end

    # Every reason the whole workspace's answers could have changed at
    # once -- most importantly the Runtime Agent becoming ready, since the
    # unknown-method check defers rather than guesses without one, and a
    # file analyzed before that point is under-reported until something
    # asks again. Supersedes any pass still running.
    # Coalesced, not restarted. A pass drains the ancestry questions each
    # file raises, and an installed answer republishes -- which used to
    # start a fresh pass from file 0 while this one was mid-walk. It
    # terminated, because an answered name is never re-asked, but the
    # redundant work grew with the workspace: five passes over 30 files,
    # twenty-five over 150, each re-taking the index mutex the request
    # path needs. A request arriving while a pass runs now means "run once
    # more when this one is done" (024.14's direction).
    def start_workspace_diagnostics
      should_start = @workspace_pass_mutex.synchronize do
        @workspace_pass_requested = true
        if @workspace_pass_running
          false
        else
          @workspace_pass_running = true
        end
      end
      return unless should_start

      @background_tasks.track_thread(Thread.new { drive_workspace_passes })
    end

    def drive_workspace_passes
      loop do
        keep = @workspace_pass_mutex.synchronize do
          if @workspace_pass_requested
            @workspace_pass_requested = false
            true
          else
            # Cleared inside the same lock the requester tests, so a
            # request arriving as this loop ends cannot be dropped.
            @workspace_pass_running = false
            false
          end
        end
        break unless keep

        run_one_workspace_pass
      end
    rescue StandardError => e
      @logger.error("workspace diagnostics pass failed: #{e.class}: #{e.message}")
      @workspace_pass_mutex.synchronize { @workspace_pass_running = false }
    end

    def run_one_workspace_pass
      generation = @workspace_diagnostics.begin_pass
      # Sorted, because the pass stops at a cap and so *which* files it
      # reaches is part of the answer. `uris_by_source` is the index's
      # own insertion order, and `replace_file` moves a file to the end
      # of it whenever the content changes -- so without an order here,
      # saving one file changes which files past the cap are never
      # reported. The pass's own traversal, not a seventh reader of
      # shared state (024.15).
      uris = @workspace_index.uris_by_source(:disk).sort
      return if uris.empty?

      outcome = @workspace_diagnostics.run(uris, generation)
      # The cap is what stops an unbounded pass on a monorepo, and the
      # files past it get no diagnostics. Saying so in the log is the
      # difference between a bounded answer and a quietly partial one --
      # `WorkspaceDiagnostics` records `truncated` for a caller to
      # report, and until now no caller read the outcome at all.
      if outcome.truncated
        @logger.warn("workspace diagnostics stopped after #{outcome.analyzed} files of #{uris.size}; " \
                     "the rest are not reported")
      end
    end

    # The unknown-method check cannot judge a receiver whose ancestry only
    # the running application knows, so it records the question instead of
    # guessing and the answer is fetched here, off the transport thread
    # (024.R5). Everything open is answered again once it lands, for the
    # same reason routes and models are: the document was diagnosed
    # against an answer that has since arrived, and editing the file
    # should not be what corrects it.
    def answer_pending_ancestry_questions
      return unless @ancestry_registry.pending?
      # Giving up means giving up asking, not just giving up waiting. The
      # failure path re-queues its names, so the queue stays non-empty
      # forever after a give-up -- without this every later publish spawns
      # another worker to block for the full timeout against an Agent
      # already known not to answer, warning each time and holding the
      # Agent's single request lock away from routes and models.
      return unless @ancestry_registry.active?

      manager = @agent_manager
      return unless agent_manager_ready?(manager)

      # Diagnostics are republished for every open document, and each one
      # comes back through here -- without a single-flight guard a batch
      # of questions would spawn one thread per open buffer, all racing
      # for the same drain and all but one finding it empty.
      return unless claim_ancestry_question_slot

      begin
        worker = Thread.new { run_ancestry_questions(manager) }
      rescue StandardError
        # The slot is held by :claiming, which no worker will ever release
        # because no worker exists -- without this every deferred receiver
        # would stay silent for the rest of the session.
        discard_ancestry_question_claim
        raise
      end
      adopt_ancestry_question_worker(worker)
      @background_tasks.track_thread(worker)
    end

    # Drains until the queue is empty rather than once, because this is the
    # only thing that ever asks. Every other caller bows out on the
    # single-flight guard -- including the ones this method's own
    # #republish_open_diagnostics triggers -- so a question raised while a
    # fetch was in flight had nobody left to carry it, and the check stayed
    # silent for that receiver until the user edited the buffer.
    #
    # Found by independent review, and not theoretical: opening two
    # documents back to back (what VS Code does at startup, restoring every
    # editor at once) left the second one's unknown-method check disabled
    # for the session, and made the shipped G2 capability example fail
    # whenever the suite's random order did not happen to leave a gap
    # between the two.
    #
    # Terminates because #install writes an entry for every name it was
    # asked about and #request skips answered names, so each pass answers
    # at least one name that will never be asked again, out of the finite
    # set of receivers in the open documents.
    def run_ancestry_questions(manager)
      epoch = @ancestry_registry.epoch
      drained_everything = false
      loop do
        names = @ancestry_registry.drain_pending
        if names.empty?
          drained_everything = true
          break
        end

        result = manager.fetch_ancestors(names)
        # Put them back rather than dropping them: they have already left
        # the queue, so without this one timeout silences those receivers
        # for the rest of the session. Recording them as absent instead
        # would be a wrong answer that never expires, which is worse.
        # Logged for the same reason a failed routes or models fetch is --
        # a degraded Agent must not look like a working one.
        #
        # `drained_everything` stays false, which is what stops the retry
        # from becoming perpetual: see the ensure below.
        unless result
          @logger.warn("failed to fetch ancestors from Runtime Agent for #{names.join(', ')}; will ask again")
          names.each { |name| @ancestry_registry.request(name) }
          give_up_on_ancestry_questions if @ancestry_registry.note_failure(epoch: epoch)
          break
        end

        # Discarded rather than installed if the Agent was restarted while
        # this was in flight: the answers describe a process that no longer
        # exists, and installing them would both mark the registry active
        # and keep them for the session, since answered names are never
        # re-asked. The epoch is tested inside the registry's own lock,
        # because testing it out here leaves a window for #reset to land
        # between the test and the write.
        @ancestry_registry.install(
          object_ancestors: result[:objectAncestors] || [],
          classes: names.to_h { |name| [name, (result[:classes] || {})[name.to_sym]] },
          epoch: epoch
        )
        republish_open_diagnostics
      end
    rescue StandardError => e
      # Every other Agent-touching background path in this file reports its
      # own failures, and this one has more reason to: the names it drained
      # are already out of the queue, so dying quietly silences those
      # receivers for the session with nothing said about why.
      @logger.error("failed to ask the Runtime Agent for ancestors: #{e.class}: #{e.message}")
    ensure
      release_ancestry_question_slot
      # Only after a pass that ended by emptying the queue. A question
      # raised between that last drain and the release above found the slot
      # still taken and bowed out, so nobody was left to carry it -- this
      # picks it up rather than waiting for whatever the user does next.
      #
      # Deliberately NOT after a failed fetch, which re-queues its names:
      # that pairing is a perpetual motion machine. It became one when the
      # ancestry fetch stopped degrading the Agent on a timeout, which had
      # been the only thing ending the cycle -- measured at ~19,000 worker
      # threads a second against an Agent that answers nothing. A failure
      # now waits for the next real diagnostics run, which is bounded by
      # what the user actually does.
      if drained_everything
        begin
          answer_pending_ancestry_questions
        rescue StandardError => e
          @logger.error("failed to re-ask the Runtime Agent for ancestors: #{e.class}: #{e.message}")
        end
      end
    end

    # Same intent as #claim_model_refresh_slot -- every queued thread would
    # fetch exactly the same thing, since whoever runs drains the whole
    # pending set -- but the claim happens on the transport thread and the
    # work happens on another, so the slot cannot simply hold
    # `Thread.current`. It holds :claiming for the moment between the two,
    # then the worker itself, whose liveness is what lets a thread killed
    # during shutdown release the slot rather than wedge it.
    def claim_ancestry_question_slot
      @refresh_state_mutex.synchronize do
        worker = @ancestry_question_worker
        next false if worker == :claiming || worker&.alive?

        @ancestry_question_worker = :claiming
        true
      end
    end

    def adopt_ancestry_question_worker(worker)
      @refresh_state_mutex.synchronize do
        @ancestry_question_worker = worker if @ancestry_question_worker == :claiming
      end
    end

    def release_ancestry_question_slot
      @refresh_state_mutex.synchronize do
        @ancestry_question_worker = nil if @ancestry_question_worker == Thread.current
      end
    end

    # An Agent that is `ready?` but has stopped answering -- hung, stopped
    # in a debugger, thrashing -- is the one state nothing else notices.
    # The ancestry fetch deliberately does not degrade the manager on a
    # timeout (one slow answer about one class is not worth tearing down
    # routes, models and completion), and the retry is deliberately not
    # automatic, so without this the check would simply defer forever and
    # go silent with nobody concluding anything.
    #
    # The counting itself belongs to the registry, together with the epoch
    # it is about: kept here it survived an Agent restart, so a fresh Agent
    # inherited the previous one's failures. Only the report is Server's.
    # The Agent is left alone either way -- only the ancestry question
    # gives up, falling back to the static reading, which is exactly what
    # "no Agent" already means for this check.
    def give_up_on_ancestry_questions
      @logger.warn(
        "Runtime Agent has not answered #{Runtime::AncestryRegistry::FAILURE_LIMIT} ancestry requests; " \
        "falling back to static analysis for unknown-method checks"
      )
    end

    def discard_ancestry_question_claim
      @refresh_state_mutex.synchronize do
        @ancestry_question_worker = nil if @ancestry_question_worker == :claiming
      end
    end

    DIAGNOSTIC_SEVERITY = { error: 1, warning: 2, information: 3, hint: 4 }.freeze

    def to_lsp_diagnostic(finding)
      {
        range: finding.range, severity: DIAGNOSTIC_SEVERITY.fetch(finding.severity, 2), code: finding.code,
        source: "ovallsp", message: finding.message, relatedInformation: finding.related_information
      }
    end

    # Task 020: `OvalLSP: Show Environment Diagnostics`/status bar. Polled by
    # the client rather than pushed as notifications -- simpler than
    # threading a push-on-every-transition mechanism through Cold Index's
    # and the Agent bootstrap's own background threads, and a request the
    # client can send whenever its own UI needs a fresh read (after
    # startup, on an interval, or right before showing the status bar
    # tooltip) is just as useful for "見える化" purposes as a live push
    # would be. One of: "indexing" (Cold Index still walking the
    # workspace), "ready-rails" (a live, responding Runtime Agent),
    # "agent-unavailable" (an Agent bootstrap was attempted -- the
    # workspace is trusted and looks like a Rails app -- but it's not
    # currently responding), or "ready-static" (no Agent attempt at all:
    # untrusted workspace, or not a Rails app).
    def status_result(_params)
      state =
        if @cold_indexing
          "indexing"
        elsif agent_manager_ready?(@agent_manager)
          "ready-rails"
        elsif @agent_manager
          "agent-unavailable"
        else
          "ready-static"
        end

      { state: state }
    end

    # `OvalLSP: Restart Rails Agent` -- reuses the exact same
    # #restart_agent already wired to Gemfile.lock/initializer file-watch
    # triggers, just invoked on explicit user request instead. Runs on
    # its own background thread (inside #restart_agent), so this request
    # itself returns immediately rather than blocking on however long a
    # full Rails boot takes.
    def restart_agent_result(_params)
      # The Agent executes the workspace's own Rails and Bundler code,
      # which is the thing trust gates. A restart is another way to start
      # it, so it asks the same question -- and it must ask the *stored*
      # answer, because a restart request carries no initializationOptions
      # of its own to inspect.
      return { acknowledged: false, reason: "workspace not trusted" } unless trusted_for_execution?("restarting the Runtime Agent")

      # A user-initiated restart always gets a fresh attempt, regardless
      # of how many *automatic* attempts were already exhausted --
      # "manual restart" is its own capability (Task 022), not gated by
      # the automatic backoff's own crash-loop cap.
      @agent_supervisor.reset
      cancel_scheduled_agent_retries
      restart_agent
      { acknowledged: true }
    end

    # `OvalLSP: Re-index Workspace` -- re-runs Cold Index exactly as it ran
    # at startup. Idempotent: ColdIndexer/WorkspaceIndex#replace_file's
    # own per-uri replace semantics mean re-walking the workspace a
    # second time simply refreshes every file's declarations in place,
    # never duplicates them.
    def reindex_workspace_result(_params)
      start_cold_index
      { acknowledged: true }
    end

    def diagnostics_semantic_context
      Diagnostics::SemanticContext.new(
        workspace_index: @workspace_index, hierarchy_index: @hierarchy_index, method_resolver: @method_resolver,
        local_inferencer: @local_inferencer, model_registry: @model_registry, route_registry: @route_registry,
        signatures: @signatures, generation: @workspace_index.generation, ancestry_registry: @ancestry_registry
      )
    end

    def diagnostics_mode_from(params)
      options = params && params[:initializationOptions]
      mode = options.is_a?(Hash) ? options[:diagnosticsMode] : nil
      Diagnostics::Engine::MODES.include?(mode&.to_sym) ? mode.to_sym : :safe
    end

    DEFAULT_OBSERVATION_TEST_COMMAND = %w[bundle exec rspec].freeze

    def observation_test_command_from(params)
      options = params && params[:initializationOptions]
      command = options.is_a?(Hash) ? options[:observationTestCommand] : nil
      valid_test_command?(command) ? command : DEFAULT_OBSERVATION_TEST_COMMAND
    end

    def valid_test_command?(command)
      command.is_a?(Array) && !command.empty? && command.all? { |part| part.is_a?(String) }
    end

    # Task 019, `OvalLSP: Run Tests with Type Observation` -- explicit
    # opt-in only, never triggered by anything else this Server does on
    # its own ("opt-in時だけ観測runnerが起動する"). Synchronous: a real
    # test suite run can take anywhere from seconds to minutes, and this
    # request's whole point is to run one, so unlike every other request
    # this Server answers, blocking the LSP loop for its duration is the
    # expected, accepted cost of what the user explicitly asked for --
    # the client is expected to show its own "running…" affordance for
    # the request's duration, not to expect a fast reply.
    def run_observed_tests_result(params)
      # This runs a command, and `testCommand` lets the caller choose it.
      # `valid_test_command?` constrains its *shape*, never its meaning --
      # `["curl", "..."]` is a well-shaped command. Trust is what decides
      # whether running the workspace's code is allowed at all.
      return { sampleCount: 0, methodCount: 0 } unless trusted_for_execution?("running observed tests")

      override = params.is_a?(Hash) ? params[:testCommand] : nil
      command = valid_test_command?(override) ? override : @observation_test_command

      results = @observation_runner.run(command: command.first, args: command[1..], workspace_root: @workspace_root)

      # `nil` is Runner's "this run produced no outcome at all" (see its
      # own docs) -- a command that couldn't start, was killed on
      # timeout, or died without observing anything -- as opposed to `[]`,
      # "the suite ran and genuinely observed nothing". Store#replace_run
      # is a full generation swap, so conflating the two would let one
      # broken run silently destroy every signature the user had already
      # accumulated. Report the honest zero counts for *this* run, but
      # leave the last-known-good evidence exactly where it is (the same
      # resolution Task 008.6 applied to RailsBootstrap's own
      # `fetch_all_models || []`).
      return { sampleCount: 0, methodCount: 0 } if results.nil?

      @observation_store.replace_run(results)
      invalidate_stale_observations

      { sampleCount: results.sum(&:samples), methodCount: results.size }
    end

    def clear_observed_types_result(_params)
      @observation_store.clear
      nil
    end

    # Task 019, `OvalLSP: Show Type Evidence` -- deliberately its own
    # request rather than folded into `ovallsp/explainType`'s own response
    # shape: several existing specs assert `explainType`'s result via
    # exact Hash equality (`{type: "..."}`), so adding a field there
    # unconditionally would break every one of them for a feature most
    # callers never opt into.
    def show_type_evidence_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = analyzable_document(@document_store.fetch(uri: uri))
      summary = @file_summaries[uri]
      return nil unless document && summary

      symbol_id = reference_symbol_id_at(document, summary, uri, params.fetch(:position)) ||
                  declaration_symbol_id_at(summary, params.fetch(:position))
      return nil unless symbol_id

      evidence = @observation_store.evidence_for(symbol_id)
      return nil unless evidence

      {
        parameterTypes: evidence.parameter_types.map(&:to_s), returnType: evidence.return_type.to_s,
        samples: evidence.samples, confidence: "low"
      }
    end

    # "code fingerprint変更時に古い観測をstale化する" / "source変更後に
    # 古い観測を使用しない" -- run on every successful #reindex, so an
    # edit to a method that was previously observed drops its (now
    # possibly-inaccurate) evidence immediately, not just the next time
    # someone happens to ask for it. The empty-store check keeps this
    # exactly zero-cost on the overwhelmingly common path (observation
    # is opt-in and off by default -- "observation disabled by default"),
    # not just cheap: no file I/O at all happens unless at least one
    # method has ever actually been observed.
    def invalidate_stale_observations
      symbol_ids = @observation_store.tracked_symbol_ids
      return if symbol_ids.empty?

      fingerprints = symbol_ids.to_h { |symbol_id| [symbol_id, current_observation_fingerprint(symbol_id)] }
      @observation_store.invalidate_changed(fingerprints)
    end

    def current_observation_fingerprint(symbol_id)
      uri, declaration = @workspace_index.declarations_with_uri(symbol_id).first
      return nil unless uri

      line = declaration.location[:start][:line] + 1

      # "Open Buffer優先" (WorkspaceIndex, Task 008.6-3) applies here
      # too: an unsaved edit must invalidate stale evidence immediately,
      # which reading only the on-disk file (below) could never see.
      document = @document_store.fetch(uri: uri)
      return Observation::Fingerprint.for_content_and_line(document.text, line) if document

      path = UriUtil.to_path(uri)
      return nil unless path && File.file?(path)

      Observation::Fingerprint.for_file_and_line(path, line)
    rescue StandardError
      nil
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
      # A plugin executes arbitrary Ruby -- that is what a plugin is. The
      # fork contains it; trust decides whether it runs at all. The paths
      # come from the client's own initializationOptions, so an untrusted
      # workspace persuading a client to name a manifest inside it would
      # otherwise be code execution with no gate in front of it.
      return unless trusted_for_execution?("loading static plugins")

      @plugin_loader.load_static(manifest_paths).each { |context| apply_plugin_context(context) }
    end

    def apply_plugin_context(context)
      return if context.declarations.empty?

      valid_facts, invalid_count = partition_plugin_facts(context.declarations)
      @logger.warn("plugin #{context.plugin_name}: dropped #{invalid_count} malformed declaration(s)") if invalid_count.positive?
      return if valid_facts.empty?

      uri = "plugin://#{context.plugin_name}"
      declarations = valid_facts.map { |fact| plugin_declaration(fact) }
      summary = Index::FileSummary.new(
        uri: uri, content_hash: uri, document_version: nil, declarations: declarations, diagnostics: []
      )

      @workspace_index.replace_file(summary)
      @hierarchy_index.replace_file(summary)
      facts = valid_facts.filter_map { |fact| plugin_generated_fact(fact) }
      @generated_method_index.replace_file(uri: uri, facts: facts) unless facts.empty?
    end

    # `context.declarations` crossed a process boundary as plain JSON,
    # rebuilt here by `Plugins::Wire` from validated fields (024.73) -- everything downstream of this
    # point (WorkspaceIndex, HierarchyIndex, GeneratedMethodIndex) trusts
    # its shape unconditionally and raises on anything else (e.g.
    # WorkspaceIndex#simple_name calling `.name` on a nil symbol_id).
    # A plugin's own file already can't corrupt this process directly
    # (Loader's fork-based isolation), but nothing between "a plugin
    # returned this Hash" and "this Hash reaches WorkspaceIndex" ever
    # re-validates its shape -- a bug in a plugin's own
    # #register_declarations call, or any future gap in Loader's
    # isolation, would otherwise crash the whole Server on an ordinary
    # `NoMethodError`/`TypeError` with no rescue anywhere between here
    # and #run. Filtering here keeps the same "one broken plugin
    # contributes nothing, logged, never brings Core down" contract every
    # other plugin failure mode already gets, instead of trusting
    # cross-process data implicitly.
    def partition_plugin_facts(facts)
      valid = facts.select { |fact| fact.is_a?(Hash) && fact[:symbol_id].is_a?(Index::SymbolId) }
      [valid, facts.size - valid.size]
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

    # Marks the workspace-wide reference index as needing a rebuild. The
    # rebuild itself is #ensure_reference_index_current's job, deferred to
    # the next query that actually needs it rather than run per edit.
    def mark_reference_index_dirty
      @reference_state_mutex.synchronize { @reference_dirty_token += 1 }
    end

    # Reference resolution is workspace-wide, but rebuilding on every
    # keystroke makes ordinary editing O(workspace). Defer it until Find
    # References/Rename needs it. Resolution happens outside the short
    # state lock; a token compare prevents a concurrent Cold Index or
    # didChange from installing an older snapshot after a newer one.
    def ensure_reference_index_current
      @reference_rebuild_mutex.synchronize do
        loop do
          semantic_generation = reference_semantic_generation
          token, current = @reference_state_mutex.synchronize do
            [
              @reference_dirty_token,
              @reference_built_token == @reference_dirty_token &&
                @reference_built_semantic_generation == semantic_generation
            ]
          end
          break if current

          resolved_by_uri = @file_summaries.dup.each_with_object({}) do |(uri, summary), resolved|
            resolved[uri] = []
            document = @document_store.fetch(uri: uri) || load_document_from_disk(uri)
            next unless document

            resolved[uri] = @reference_resolver.resolve(
              document, summary.reference_candidates, uri: uri, generation: @reference_index.generation
            )
          rescue StandardError => e
            @logger.error("failed to resolve references for #{uri}: #{e.class}: #{e.message}")
          end

          latest_semantic_generation = reference_semantic_generation
          installed = @reference_state_mutex.synchronize do
            next false unless @reference_dirty_token == token &&
                              latest_semantic_generation == semantic_generation

            resolved_by_uri.each { |uri, references| @reference_index.replace_file(uri: uri, references: references) }
            @reference_built_token = token
            @reference_built_semantic_generation = semantic_generation
            true
          end
          break if installed
        end
      end
    end

    def reference_semantic_generation
      [
        @workspace_index.generation,
        @signatures.generation,
        @model_registry.generation,
        @route_registry.generation,
        @observation_store.generation,
        @generated_method_index.generation
      ]
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
      return if @cold_indexing

      root = @workspace_root
      parser_service = @parser_service
      workspace_index = @workspace_index
      hierarchy_index = @hierarchy_index
      document_store = @document_store
      logger = @logger
      cache_store = build_cache_store
      existing_disk_uris = workspace_index.uris_by_source(:disk)

      @cold_indexing = true
      @background_tasks.track_thread(Thread.new do
        ColdIndexer.new(root: root, parser_service: parser_service, workspace_index: workspace_index,
                        hierarchy_index: hierarchy_index, document_store: document_store, logger: logger,
                        cache_store: cache_store, on_summary: method(:apply_cold_summary),
                        on_complete: lambda { |result|
                          sweep_deleted_cold_files(existing_disk_uris, result.seen_uris) if result.complete
                          # Bumped under the same lock every other
                          # mutation site uses. Outside it, a dispatch
                          # thread already holding the lock could finish a
                          # full-workspace reference resolution, observe
                          # the token move at install time, and throw the
                          # whole pass away -- a doubled O(workspace)
                          # rebuild on exactly the "just cold-indexed a
                          # large repo" path.
                          @index_mutation_mutex.synchronize { mark_reference_index_dirty }
                          # Now, not earlier: a file analyzed before the
                          # rest of the workspace is indexed resolves
                          # against a half-built index and reports
                          # mistakes that are only missing knowledge.
                          # Not while the Agent's bootstrap is still in
                          # flight: the unknown-method check defers only
                          # once there is an Agent to defer to, and
                          # publishing its static fallback for the whole
                          # project -- then correcting it a boot later --
                          # is a Problems panel full of findings about
                          # working code. The bootstrap starts the pass
                          # itself when it settles, ready or not.
                          start_workspace_diagnostics unless @agent_bootstrap_pending
                        }).run
      rescue StandardError => e
        logger.error("cold index failed: #{e.class}: #{e.message}")
      ensure
        @cold_indexing = false
      end)
    end

    def apply_cold_summary(_uri, _document, summary)
      apply_file_summary(summary)
    end

    def apply_file_summary(summary)
      @index_mutation_mutex.synchronize do
        previous_declarations = @workspace_index.declarations_for_uri(summary.uri)
        return false unless @workspace_index.replace_file(summary)

        @hierarchy_index.replace_file(summary)
        @file_summaries[summary.uri] = summary
        invalidate_method_summaries(previous_declarations)
        @generated_method_index.replace_file(uri: summary.uri, facts: summary.generated_method_facts)
        mark_reference_index_dirty
        true
      end
    end

    # "ColdIndexer did not visit it" is not the same fact as "it was
    # deleted", and treating them as one silently dropped live files out
    # of the index. ColdIndexer only walks its own include/exclude
    # filters (DEFAULT_EXCLUDED_DIRS covers vendor/tmp/log/storage/...),
    # while `reindex_from_disk` indexes whatever the client's watcher
    # reports -- and that glob has no such exclusions. Anything indexed
    # through the wider path but skipped by the narrower one was
    # therefore purged on the next re-index, reappeared when touched, and
    # was purged again: permanently flapping. The symlink-dedup
    # early-return in ColdIndexer never records a `seen` URI either, so
    # it hit the same hole.
    #
    # Absence is now *verified* rather than inferred, which is correct no
    # matter how the two path sets diverge in future. Also one critical
    # section instead of one per URI, so a concurrent request can never
    # observe a half-swept index.
    # Claims the newest generation for a whole-section refresh. The
    # caller compares it again after acquiring @agent_refresh_mutex and
    # bows out if a newer request has since arrived.
    def claim_refresh_generation(kind)
      @refresh_state_mutex.synchronize { @refresh_generations[kind] += 1 }
    end

    def refresh_generation_current?(kind, generation)
      @refresh_state_mutex.synchronize { @refresh_generations[kind] == generation }
    end

    def enqueue_model_names(names)
      @refresh_state_mutex.synchronize { @pending_model_names |= names.to_a }
    end

    def drain_model_names
      @refresh_state_mutex.synchronize { @pending_model_names.tap { @pending_model_names = [] } }
    end

    # At most one thread may *wait* for the model-refresh mutex. Every
    # queued thread would refresh exactly the same thing -- whoever gets
    # the mutex drains the whole pending set -- so the ones behind the
    # first waiter are pure accumulation.
    #
    # The slot is released the moment its holder acquires the mutex and
    # before it drains, which is what makes bowing out safe: a thread that
    # finds the slot taken knows the waiter has not drained yet, so the
    # names it just enqueued are still ahead of that waiter's drain. A
    # dead waiter (killed during shutdown) never wedges the queue, since
    # liveness is rechecked on every claim.
    def claim_model_refresh_slot
      @refresh_state_mutex.synchronize do
        next false if @model_refresh_waiter&.alive?

        @model_refresh_waiter = Thread.current
        true
      end
    end

    def release_model_refresh_slot
      @refresh_state_mutex.synchronize do
        @model_refresh_waiter = nil if @model_refresh_waiter == Thread.current
      end
    end

    def sweep_deleted_cold_files(existing_disk_uris, seen_uris)
      deleted = (existing_disk_uris - seen_uris.to_a).reject do |uri|
        path = UriUtil.to_path(uri)
        # A URI whose path cannot be derived is *unverifiable*, not
        # verified-absent -- keeping it is the direction that matches
        # this method's whole point. Treating nil as "gone" would have
        # reintroduced exactly the inference this check replaced.
        path.nil? || File.file?(path)
      end
      return if deleted.empty?

      @index_mutation_mutex.synchronize do
        deleted.each do |uri|
          next unless @workspace_index.summary_for_uri(uri)&.source == :disk

          remove_index_contribution(uri)
        end
      end
    end

    def remove_index_contribution(uri)
      previous_declarations = @workspace_index.declarations_for_uri(uri)
      @workspace_index.remove_file(uri)
      @hierarchy_index.remove_file(uri)
      @reference_index.remove_file(uri)
      @generated_method_index.remove_file(uri)
      @file_summaries.delete(uri)
      invalidate_method_summaries(previous_declarations)
      mark_reference_index_dirty
    end

    # Task 021: one persistent, on-disk FileSummary cache per distinct
    # (schema, Ruby, Prism, workspace, Gemfile.lock, RBS, settings)
    # combination -- see Cache::Key's own docs for why folding all of
    # that into one directory name is enough to make every one of those
    # dimensions "just work" as an invalidation trigger, with no
    # migration code needed. A user-level cache root (not inside the
    # workspace itself) survives a workspace being deleted and
    # recreated, and never needs its own .gitignore entry.
    def build_cache_store
      root = ENV["XDG_CACHE_HOME"].then { |xdg| xdg && !xdg.empty? ? xdg : File.join(Dir.home, ".cache") }
      digest = Cache::Key.workspace_digest(
        workspace_root: @workspace_root, gemfile_lock_digest: gemfile_lock_digest, rbs_digest: rbs_digest,
        settings_digest: nil
      )
      cache_root = File.join(root, "ovallsp")
      # `<root>/<workspace>/<generation>`: pruning has to be able to tell
      # this project's abandoned generations from *another project's live
      # cache*, and a flat root cannot -- every workspace was a sibling of
      # every generation, so opening a ninth project evicted one of the
      # other eight.
      scope_dir = File.join(cache_root, Cache::Key.workspace_scope(workspace_root: @workspace_root))
      cache_dir = File.join(scope_dir, digest)
      # The marker before the generation, not after. `.prune_workspaces`
      # removes any child of the cache root that has no marker -- a
      # pre-0.2.1 flat generation, which cannot be read again -- and
      # `Store.new` creates the scope directory on its way to the
      # generation. Marking second leaves a window in which the scope
      # exists and the marker does not, and a second window's sweep
      # landing inside it deletes this window's entire scope, after which
      # this process writes cache entries into a removed directory and
      # every `save` silently rescues.
      #
      # It was a narrow window while the sweep ran on the `initialize`
      # dispatch. Moving it to a background thread below lets it overlap
      # another window's cold index, so the reorder narrows it and
      # `Cache::Store::UNMARKED_SCOPE_GRACE` is what closes it.
      Cache::Store.mark_workspace(scope_dir, Cache::Key.canonical_root(@workspace_root))
      store = Cache::Store.new(cache_dir: cache_dir)
      # After the directory exists, so the current generation is never the
      # one swept. A generation is only minted when the key changes -- a
      # Ruby upgrade, a `bundle install`, a release -- so there is
      # normally nothing to sweep after the first start. `Re-index
      # Workspace` reaches this again and starts another sweep; harmless,
      # since removing what is already removed is a no-op and the thread
      # is tracked either way.
      #
      # On a background thread, because this runs on the `initialize`
      # dispatch and every request the editor sends afterwards queues
      # behind it. 0.9 s to remove 1,000 abandoned directories, measured
      # -- and the machine this sweep exists for had 28,643 of them and
      # 2.8 GB -- around 26 seconds of a server that answers nothing. The
      # first launch after an upgrade is exactly when that bill comes
      # due, because putting the build's version in the key is what
      # abandoned them (024.51).
      #
      # Nothing waits on it for an *answer*: the current generation's
      # directory already exists, and removing *other* directories cannot
      # change what this one reads. It is tracked, though, so shutdown
      # joins it for up to the background budget and may kill it
      # mid-`remove_entry`, leaving a directory partly removed -- which
      # the next sweep finishes, because a partial directory is still an
      # abandoned one. Untracked would leak the thread instead -- which is
      # the leak `BackgroundTasks`' own header was written about.
      #
      # Rescued separately from the store. Failing to *start* the sweep is
      # a housekeeping failure and costs nothing this session; letting it
      # reach the method's own rescue would return a disabled cache and
      # make every file cold, which is a far worse answer to a
      # `ThreadError` than skipping a cleanup.
      begin
        @background_tasks.track_thread(
          Thread.new { Cache::Store.prune_generations(cache_root: cache_root, current: cache_dir) }
        )
      rescue StandardError => e
        @logger.error("failed to start the cache sweep; leaving abandoned generations in place: #{e.class}: #{e.message}")
      end
      store
    rescue StandardError => e
      @logger.error("failed to initialize persistent cache; continuing without one: #{e.class}: #{e.message}")
      Cache::Store.new(cache_dir: nil)
    end

    def gemfile_lock_digest
      path = File.join(@workspace_root, "Gemfile.lock")
      return nil unless File.file?(path)

      Digest::SHA256.file(path).hexdigest
    rescue StandardError
      nil
    end

    # No real RBS content-hash source is exposed by Signatures::Environment
    # itself (its own #generation is a load-order counter, not stable
    # across process restarts, so it can't be used as a cache-key
    # component) -- approximated from the mtime+size of every file that
    # could actually change what gets loaded (`sig/**/*.rbs` and project
    # RBI files), cheap enough to compute on every
    # startup without itself becoming a performance problem.
    def rbs_digest
      candidates = [
        File.join(@workspace_root, "sig", "**", "*.{rbs,rbi}"),
        File.join(@workspace_root, "sorbet", "rbi", "**", "*.rbi")
      ].flat_map { |pattern| Dir.glob(pattern) }
      # The collection lockfile decides *which* gem RBS get loaded, so a
      # `rbs collection update` changes every gem signature while nothing
      # under sig/ or sorbet/rbi/ moves. Without it in the fingerprint the
      # cache key is unchanged and the summaries built against the
      # previous signature set stay in use. It also has to count on its
      # own: a project can have a lockfile and no sig/ directory at all,
      # which otherwise fingerprints as "no signatures".
      lockfile = File.join(@workspace_root, "rbs_collection.lock.yaml")
      candidates << lockfile if File.file?(lockfile)
      candidates = candidates.uniq.sort
      return nil if candidates.empty?

      fingerprint = candidates.map { |f| "#{f}:#{File.mtime(f).to_i}:#{File.size(f)}" }.join("|")
      Digest::SHA256.hexdigest(fingerprint)
    rescue StandardError
      nil
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
    # Takes no argument: the trust it needs is the value recorded at
    # `initialize`, not something a caller supplies. It used to take the
    # params and inspect them, which let a caller believe passing
    # `workspaceTrusted: true` was what granted permission.
    def maybe_start_agent
      unless trusted_for_execution?("starting the Runtime Agent")
        return
      end

      @agent_bootstrap_pending = true

      bootstrap = @agent_bootstrap
      root = @workspace_root
      logger = @logger
      route_registry = @route_registry
      model_registry = @model_registry
      mutex = @agent_restart_mutex
      background_tasks = @background_tasks

      thread = Thread.new do
        # Serialized on the same mutex #restart_agent uses: an extremely
        # fast client could in principle fire a file-change restart before
        # this initial bootstrap finishes, and without sharing the lock,
        # both writes to @agent_manager could interleave the same way
        # described in #restart_agent's comment.
        mutex.synchronize do
          manager = start_agent_bootstrap(
            bootstrap,
            root: root, logger: logger, route_registry: route_registry, model_registry: model_registry,
            on_unavailable: method(:handle_agent_unavailable),
            # Registers the manager with BackgroundTasks the moment it
            # exists -- before `bootstrap.start`'s own blocking hello
            # handshake even begins -- so Server#shutdown_background_tasks
            # can reach and cancel it even if this whole method call never
            # returns (a real Rails boot can take tens of seconds; an
            # unresponsive one takes up to hello_timeout). Deliberately
            # does NOT assign @agent_manager here (found by an independent
            # review): doing so made #status_result/#with_ready_agent see
            # a non-nil, not-yet-ready manager for the entire boot and
            # report "agent-unavailable" (defined elsewhere as "attempted
            # but not currently responding") for what's actually just
            # normal, in-progress startup. @agent_manager is only ever
            # assigned its final value below, once #start has actually
            # returned -- exactly the pre-this-fix timing. BackgroundTasks
            # tracks (and can cancel) the manager independently of
            # whatever Server's own @agent_manager ivar currently holds.
            on_manager_created: ->(created) { background_tasks.track_manager(created) }
          )
          # Coerced *before* tracking (not after): #coerce_agent_manager is
          # the one place a return-value-contract violation gets caught,
          # and tracking a value that failed that check (an Integer, say)
          # would just pollute BackgroundTasks' registry with something
          # #shutdown's own `manager.stop` call has to rescue around,
          # never usefully call. #track_manager is idempotent by identity,
          # so re-tracking the same (valid) manager here is a harmless
          # no-op when the bootstrap already called on_manager_created
          # above -- and is the only registration at all for a bootstrap
          # (real or test double) that doesn't call that hook, closing the
          # gap where such a manager would never be reachable from
          # #shutdown_background_tasks (found by an independent review).
          @agent_manager = background_tasks.track_manager(coerce_agent_manager(manager))
        end
        if agent_manager_ready?(@agent_manager)
          @agent_supervisor.record_success
          cancel_scheduled_agent_retries
          # Only now is there an Agent to ask. The snapshot's own republish
          # already ran, from inside the bootstrap call above, while
          # @agent_manager was still unassigned -- so the unknown-method
          # check saw no Agent, did not defer, and reported the very false
          # positives this release removes. Everything open is answered
          # once more, with the Agent in place.
          #
          # This is the ordinary path, not a race: VS Code restores its
          # editors at startup and opens them immediately, while a real
          # Rails boot takes tens of seconds.
          republish_open_diagnostics
        end
      rescue StandardError => e
        logger.error("Runtime Agent bootstrap failed: #{e.class}: #{e.message}")
      ensure
        # Settled, ready or not: a bootstrap that never reaches :ready
        # degrades to static-only with no retry, so this is the only
        # point at which the workspace's answers stop changing.
        @agent_bootstrap_pending = false
        begin
          start_workspace_diagnostics
        rescue StandardError => e
          logger.error("failed to start the workspace pass: #{e.class}: #{e.message}")
        end
      end
      background_tasks.track_thread(thread)
    end

    # Task 022: called (on whichever thread AgentProcessManager's own
    # reader thread or a timed-out request runs on) exactly once each
    # time an Agent that had been :ready unexpectedly becomes
    # unavailable -- never for an explicit #stop, and never for a
    # bootstrap that never reached :ready in the first place (that
    # degrades straight to static-only with no automatic retry, matching
    # the pre-Task-022 behavior for "the Agent never worked" as opposed
    # to "the Agent was working and then crashed").
    def handle_agent_unavailable(reason)
      delay = @agent_supervisor.record_failure_and_next_delay
      if delay.nil?
        @logger.error(
          "runtime agent crash-looped (#{reason}); giving up automatic restarts -- use " \
          "'OvalLSP: Restart Rails Agent' to try again manually"
        )
        # No answer is ever coming now, so the unknown-method check must
        # stop waiting for one. It defers on a receiver only an Agent could
        # judge, which is right while one exists and disables the check
        # outright once none does -- and a crash-looped Agent looks exactly
        # like no Agent to the user. Answers already given are kept: they
        # were true about the application that was running.
        @ancestry_registry.deactivate!
        return
      end

      @logger.warn("runtime agent became unavailable (#{reason}); retrying in #{delay}s")
      retry_generation = @agent_retry_mutex.synchronize do
        @agent_retry_generation += 1
      end
      # Tracked so shutdown can reclaim it -- it owns no subprocess of its
      # own (unlike the bootstrap/restart threads), so BackgroundTasks#shutdown
      # killing it outright once its bounded join expires is safe: no
      # scheduled restart ever fires after Server#run has already exited.
      @background_tasks.track_thread(Thread.new do
        sleep delay
        next unless scheduled_agent_retry_current?(retry_generation)

        restart_agent(retry_generation: retry_generation)
      end)
    end

    def cancel_scheduled_agent_retries
      @agent_retry_mutex.synchronize { @agent_retry_generation += 1 }
    end

    def scheduled_agent_retry_current?(generation)
      @agent_retry_mutex.synchronize { @agent_retry_generation == generation }
    end

    def workspace_trusted?(params)
      options = params && params[:initializationOptions]
      options.is_a?(Hash) && options[:workspaceTrusted] == true
    end

    # The one place that decides whether this server may execute the
    # workspace's code, so that a new entry point cannot be added without
    # meeting it. Fail-closed: `@workspace_trusted` is nil before
    # `initialize` has been handled at all, and nil is not true.
    #
    # Named for what it protects rather than for the flag it reads --
    # `maybe_start_agent`'s own comment already explains why anything but
    # a literal `true` is a refusal.
    def trusted_for_execution?(what)
      return true if @workspace_trusted

      @logger.warn("workspace trust not confirmed; not #{what}")
      false
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

    # The document every position-based query should look at.
    #
    # For an .erb file that is the *extracted* Ruby, not the template:
    # asking the type engine about a position in raw HTML gets whatever
    # Prism made of the markup, which is how a partial's local was read as
    # a String and completion inside a template returned nothing at all.
    # ParserService already extracts before parsing, so every other
    # consumer has to agree with it or the two disagree about what the
    # file contains.
    #
    # Extraction blanks non-Ruby regions in place, preserving every line
    # and column, so a position needs no remapping and neither does a
    # range in the answer.
    #
    # Applied once, where documents are fetched, rather than at each of
    # the ten handlers that take a position -- which is what let hover and
    # explainType be correct while completion, signature help, definition,
    # references and rename were not.
    def analyzable_document(document)
      return document unless document && erb_view?(document.uri)

      TextDocument.new(
        uri: document.uri, text: Erb::RubyRegionExtractor.extract_ruby_source(document.text),
        version: document.version, language_id: "ruby"
      )
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

    # The instance variables this document is *given*, or nil when nobody
    # can say (0.2.0's unassigned-@ivar check).
    #
    # Only a view has an answer: it is handed exactly what its controller
    # action and callback chain assign, which is already computed for
    # type propagation. Everything else -- a controller, a model, a plain
    # Ruby file -- receives its ivars from wherever it likes, and nil is
    # the honest answer rather than the empty set.
    def assigned_ivars_for(uri, view_document = nil)
      return nil unless erb_view?(uri)

      context = view_action_context(uri)
      return nil unless context
      # An `instance_variable_set` anywhere in the chain assigns names
      # this cannot enumerate, so the set stops being a complete answer
      # and there is nothing safe to report against.
      documents = controller_ancestor_documents(context[:owner])
      return nil if controller_sets_ivars_dynamically?(documents)
      return nil unless whole_chain_was_read?(context[:owner], documents)
      return nil unless declared_once_each?(documents)
      return nil unless ivar_sources_fully_enumerable?(context[:owner], documents)
      return nil unless class_body_is_accounted_for?(documents)
      # A view that renders a partial receives whatever the partial
      # assigns, and this walk reads the view's own text only. Resolving
      # the partial and reading it is the precise answer and belongs with
      # the rest of 024.18; until then a render is a contributor that has
      # not been read.
      return nil if renders_something?(uri, view_document)

      method_maps = controller_method_maps(documents)
      actions = contributing_actions(documents, method_maps, context[:action], context[:view_key])
      # No action renders this view, so nothing establishes what it is
      # given. That is a different fact from "the action assigns nothing",
      # and the empty set would say the second while meaning the first.
      return nil if actions.empty?

      # The union of what the inference walk resolved and every ivar the
      # controller chain assigns *syntactically*. The walk's set is the
      # attributed one -- which action assigns what -- but it folds only
      # the statement shapes it models, and a shape it does not fold
      # arrives here as a complete-looking set with a name missing, which
      # is a warning on a view that renders (`@user ||= ...`, an
      # assignment inside `respond_to do |format|`, a `case`, a `rescue`,
      # a multiple assignment).
      #
      # Widening to the whole chain rather than to the contributing
      # action's body alone is deliberate: an ivar assigned in a sibling
      # action silences this check for this view, which is a missed
      # report. The standard here is that a missed report beats a wrong
      # one, and a name the controller never writes at all -- the typo
      # this check exists for -- is still caught.
      (ivars_for_view(uri).keys.map(&:to_s) +
       documents.flat_map { |_, document| @local_inferencer.assigned_ivar_names(document) } +
       helper_assigned_ivar_names).uniq
    rescue StandardError => e
      @logger.error("failed to compute assigned ivars for #{uri}: #{e.class}: #{e.message}")
      nil
    end

    DYNAMIC_IVAR_ASSIGNMENT = /\binstance_variable_set\b/

    # Takes the chain rather than the owner: building it re-reads and
    # re-parses every controller in it from disk, and the caller has
    # already done that.
    def controller_sets_ivars_dynamically?(documents)
      documents.any? do |_ancestor_name, document|
        document.text.match?(DYNAMIC_IVAR_ASSIGNMENT)
      end
    end

    # Whether the instance variables a view receives can be *completely*
    # enumerated (0.2.0).
    #
    # The chain builder was written for type propagation, where missing a
    # source is harmless: the ivar simply infers Unknown. Reused as the
    # input to a diagnostic, every omission becomes a wrong report on code
    # that runs -- and `around_action`, `prepend_before_action`, a
    # block-form callback and a Rails concern are not edge cases. So the
    # answer here is "no" whenever the chain contains anything this cannot
    # follow, and the check above turns that into silence.
    # `controller_ancestor_documents` drops an ancestor whose file it
    # cannot resolve, and says nothing about having done so -- so a class
    # this walk never read looks exactly like a class that assigns
    # nothing. `class UsersController < ApplicationController` analyzed
    # before the cold index reaches the parent reported the parent's
    # `@current_user` as never assigned, on a view that renders; and for a
    # controller whose parent lives outside the workspace it never stops.
    #
    # The chain from the hierarchy index is the authority on what should
    # have been read, and this is where the two are compared, because
    # nowhere else has both.
    def whole_chain_was_read?(owner_name, documents)
      # The *immediate* superclass, whatever its `kind`. One the index has
      # not seen declared arrives with `kind: nil`, which is the case that
      # matters: `controller_ancestor_documents` filters on
      # `kind == :class` and so never even tries to read it.
      #
      # Only the immediate one, because the chain does not end in the
      # workspace -- every Rails controller reaches `ActionController::Base`
      # and beyond, which no document will ever be produced for, so
      # demanding the whole chain switches the check off for every real
      # controller. A framework base does not assign the instance
      # variables a view reads; the class the user wrote `< X` against
      # does, and that is the one worth insisting on.
      # The view's own controller's immediate superclass, and only that
      # one. Applying the same rule to every class that was read is the
      # correct depth -- `UsersController < BaseController <
      # ApplicationController` with the top unread is the same failure one
      # level up, and it is not caught here -- but it cannot be told from
      # the ordinary case: the last class the workspace declares inherits
      # from a gem, which no document will ever exist for, so demanding it
      # silences every real controller. Separating "a workspace class not
      # read yet" from "a base class in a gem" is what 024.R7's index
      # provides, and 024.18 records this as waiting on it.
      parent = @hierarchy_index.ancestors(owner_name).find { |entry| entry.origin == :superclass }
      return true unless parent

      read = documents.map { |name, _| Index::SymbolId.qualify_owner(name) }
      read.include?(Index::SymbolId.qualify_owner(parent.name))
    end

    # Rails mixes every module under `app/helpers` into the view context
    # (`include_all_helpers` is on by default), so an ivar a helper
    # assigns is one the view receives. The controller walk cannot see
    # them, and no other guard notices: the controller's body is clean and
    # its ancestry carries no module.
    #
    # Every helper rather than the ones this view calls, for the same
    # reason the controller chain is taken whole -- a name assigned
    # anywhere a view can reach means "do not warn", and a name no helper
    # writes at all, which is the typo this check exists for, is still
    # caught.
    HELPER_PATH = %r{/app/helpers/}
    def helper_assigned_ivar_names
      uris = (@workspace_index.uris_by_source(:disk) + @document_store.open_documents.map(&:uri))
      uris.uniq.filter_map do |uri|
        next unless uri.match?(HELPER_PATH)

        # The index's own content hash, which costs neither a read nor a
        # parse and tracks an open buffer as well as a file on disk --
        # `didOpen` and `didChange` both re-index. This runs on the
        # dispatch thread once per `didChange`, per keystroke in a view,
        # and once per view in the workspace pass, inside the lock every
        # hover needs: reading and parsing every helper each time measured
        # 17ms on sixty of them, loading and hashing the text 5.8ms, this
        # 0.22ms.
        #
        # A version cannot be the key: it restarts at 1 every time the
        # editor opens the file, so it names a text only within one open
        # session while this cache outlives it, and a helper reopened at
        # version 1 with different content answered from the previous
        # session.
        open_document = @document_store.fetch(uri: uri)
        fingerprint = @workspace_index.summary_for_uri(uri)&.content_hash
        cached = @helper_ivars[uri]
        next cached[1] if fingerprint && cached && cached[0] == fingerprint

        document = open_document || load_document_from_disk(uri)
        next unless document

        names = @local_inferencer.assigned_ivar_names(document)
        @helper_ivars[uri] = [fingerprint, names] if fingerprint
        names
      end.flatten
    end

    # `controller_ancestor_documents` resolves each ancestor to *one* uri,
    # so a second file reopening the class is never read -- and the set
    # the check then compares against looks complete rather than partial.
    # `def show; load_user; end` in one file with `load_user` assigning in
    # another produced a warning on a view that renders.
    def declared_once_each?(documents)
      documents.all? { |name, _| @workspace_index.class_declaration_uris(name).size <= 1 }
    end

    # The class-level declarations this analysis accounts for. Everything
    # else in a controller's class body is a call whose effect it has not
    # read -- and a gem's macro is the ordinary case: CanCanCan's
    # `load_and_authorize_resource`, `expose`, Devise and ActiveAdmin all
    # install a callback that assigns at runtime, none of it visible to a
    # walk over `def` bodies.
    #
    # A whitelist rather than a blacklist, because the failure direction
    # matters: a name nobody thought of has to mean "stay silent", not
    # "assume harmless". `private`/`protected`/`public` and the callback
    # forms the chain builder reads are the ones accounted for by
    # construction.
    #
    # This is the blunt form of the question. 024.R7 lets the index
    # attribute a class-body call to the gem that defines it, at which
    # point this narrows to the calls still unaccounted for -- which
    # *widens* the check rather than changing an answer it gives today.
    MODELLED_CLASS_BODY_CALLS = %w[
      private protected public
      before_action skip_before_action
    ].freeze

    # Any `render` in the template's own Ruby regions. Deliberately not
    # only the partial forms: `render` with a non-literal target is
    # exactly the case that cannot be resolved later either.
    def renders_something?(view_uri, view_document = nil)
      document = view_document || @document_store.fetch(uri: view_uri) || load_document_from_disk(view_uri)
      return false unless document

      Erb::RubyRegionExtractor.extract_ruby_source(document.text).match?(/(?:\A|[^\w.:])render\b/)
    rescue StandardError
      true
    end

    def class_body_is_accounted_for?(documents)
      documents.all? do |ancestor_name, document|
        (@local_inferencer.class_body_call_names(document, owner_name: Index::SymbolId.qualify_owner(ancestor_name)) -
          MODELLED_CLASS_BODY_CALLS).empty?
      end
    end

    def ivar_sources_fully_enumerable?(owner_name, documents)
      # `:default` entries are Object/Kernel/BasicObject, which every
      # class has and none of which assigns a controller's ivars. What
      # matters is a module the workspace mixes in, whose methods
      # `controller_ancestor_documents` does not walk.
      mixed_in = @hierarchy_index.ancestors(owner_name).any? do |entry|
        %i[include extend prepend].include?(entry.origin)
      end
      !mixed_in
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

      documents = controller_ancestor_documents(context[:owner])
      method_maps = controller_method_maps(documents)
      environments = contributing_actions(documents, method_maps, context[:action], context[:view_key]).map do |action_name|
        infer_controller_action_ivars(
          context[:owner], action_name, documents: documents, method_maps: method_maps
        )
      end
      merge_alternative_ivar_environments(environments)
    end

    # Rails inherits callback declarations. Build the effective callback
    # chain from the oldest controller superclass to the concrete
    # controller, applying skip_before_action in declaration order. Each
    # callback method itself follows normal Ruby lookup from child to
    # parent, so an override is evaluated exactly once.
    def infer_controller_action_ivars(owner_name, action_name, documents: controller_ancestor_documents(owner_name),
                                      method_maps: controller_method_maps(documents))
      operations = documents.reverse.flat_map do |ancestor_name, document|
        @local_inferencer.before_action_operations(
          document, owner_name: ancestor_name, action_name: action_name
        )
      end
      callbacks = operations.each_with_object([]) do |(verb, name), names|
        verb == :add ? names << name : names.delete(name)
      end

      @local_inferencer.begin_ivar_inference
      env = callbacks.reduce({}) do |callback_env, callback_name|
        declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(callback_name) }
        next callback_env unless declaration

        ancestor_name, = declaration
        @local_inferencer.infer_ivars_for_method_node(
          method_maps[ancestor_name][callback_name], initial_env: callback_env,
          self_type_name: owner_name, reset_budget: false
        )
      end

      action_declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(action_name) }
      return env unless action_declaration

      ancestor_name, = action_declaration
      @local_inferencer.infer_ivars_for_method_node(
        method_maps[ancestor_name][action_name], initial_env: env, self_type_name: owner_name, reset_budget: false
      )
    end

    def controller_ancestor_documents(owner_name)
      ancestors = @hierarchy_index.ancestors(owner_name).select do |entry|
        entry.kind == :class && %i[self superclass].include?(entry.origin)
      end
      names = ([owner_name] + ancestors.map(&:name)).uniq
      names.filter_map do |name|
        uri = find_controller_uri(name)
        document = uri && (@document_store.fetch(uri: uri) || load_document_from_disk(uri))
        [name, document] if document
      end
    end

    def controller_method_maps(documents)
      documents.to_h do |ancestor_name, document|
        [ancestor_name, @local_inferencer.method_nodes(document, owner_name: ancestor_name)]
      end
    end

    def merge_alternative_ivar_environments(environments)
      return {} if environments.empty?

      environments.reduce do |left, right|
        (left.keys | right.keys).to_h do |name|
          [name, Types.normalize_union([left.fetch(name, Types::NIL), right.fetch(name, Types::NIL)])]
        end
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

      { owner: owner, action: match[:action], view_key: "#{match[:dir]}/#{match[:action]}", controller_uri: controller_uri }
    end

    # Looked up by qualified *name*, never by a reconstructed SymbolId.
    # `owner` is recorded lexically, so one class has as many SymbolIds as
    # there are ways to spell it -- `module Api; module V1; class
    # UsersController`, `class Api::V1::UsersController`, and the partly
    # compact `module Api; class V1::UsersController` are three different
    # keys. Any owner-derived lookup matches some and misses the rest, and
    # a miss silently stops a whole controller's ivars from reaching its
    # views; enumerating candidate owners only moves which spelling
    # breaks. The name is already fully qualified and unique, so asking by
    # it answers every shape at once.
    # The `::` normalisation this used to do by hand now lives in
    # `class_declaration_uris` itself, where every caller gets it and a
    # test can see the difference — measured: both of this method's own
    # callers already pass a qualified name, so the hand-written copy
    # could not change any answer and nothing could ever have pinned it
    # (0.1.12, round 5).
    def find_controller_uri(owner_name)
      @workspace_index.class_declaration_uris(owner_name).first
    end

    # An action contributes its ivars to this view if it either *is* the
    # view's own action, or explicitly `render`s it — propagating e.g. a
    # failed #update's ivars into "edit.html.erb"
    # (docs/design/tasks/008-controller-view-propagation.md "render :edit
    # 先へ伝播").
    def contributing_actions(documents, method_maps, view_action, view_key)
      effective_visibilities = {}
      documents.each do |ancestor_name, document|
        summary = @file_summaries[document.uri] || @parser_service.summarize(document)
        canonical_owner = Index::SymbolId.qualify_owner(ancestor_name)
        owner_visibilities = {}
        summary.declarations.each do |declaration|
          symbol = declaration.symbol_id
          next unless symbol.kind == :instance_method
          next unless symbol.owner == canonical_owner
          next unless method_maps.fetch(ancestor_name).key?(symbol.name)

          owner_visibilities[symbol.name] = declaration.visibility
        end
        # Documents are child-first. The first declaration reached for a
        # name is therefore Ruby's effective override; a private child
        # method must hide a public action inherited from its parent.
        owner_visibilities.each { |name, visibility| effective_visibilities[name] ||= visibility }
      end
      action_names = effective_visibilities.filter_map { |name, visibility| name if visibility == :public }

      action_names.select do |action_name|
        next true if action_name == view_action

        declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(action_name) }
        next false unless declaration

        ancestor_name, = declaration
        target = @local_inferencer.static_render_target_for_node(method_maps[ancestor_name][action_name])
        target && (target.include?("/") ? target.delete_prefix("/") == view_key : target == view_action)
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
      document = analyzable_document(@document_store.fetch(uri: uri))
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

      on_self = receiverless_definitions(document, position, word)
      return on_self unless on_self.empty?

      # The cursor on a declaration's own name answers with that
      # declaration. Jumping there is a no-op, which is the point:
      # answering nothing makes the editor say "No definition found",
      # which reads as a failure rather than as "you are already there".
      # 0.2.1 lost this by tightening the receiverless path, and recorded
      # nothing about it.
      here = declaration_at_cursor(document, position)
      return here unless here.empty?

      lexical = @workspace_index.find_by_simple_name(word).map { |match| { uri: match[:uri], range: match[:range] } }
      (lexical + route_helper_definitions(word)).uniq
    end

    # A call with no receiver is a call on the enclosing `self`, and that
    # is the *only* way most Ruby calls a method of its own class.
    #
    # Without this the fallback below is the whole answer, and it is a
    # name lookup restricted to classes, modules and constants -- so
    # `article_params` in a scaffolded Rails controller resolved to
    # nothing, while find-references on the same pair answered two.
    # `EXTENSION_CAPABILITIES.md`'s D1 row promises the jump for "a call
    # to a workspace method"; its example wrote a receiver, which is why
    # the row read PASS.
    #
    # The same question `PrefixCompletion` answers for "methods callable
    # here", asked the same way -- through the type engine rather than by
    # name, so this cannot jump to an unrelated method that happens to
    # share the word.
    def declaration_at_cursor(document, position)
      summary = @file_summaries[document.uri] || @parser_service.summarize(document)
      declaration = declaration_named_at(summary, position)
      return [] unless declaration

      [{ uri: document.uri, range: declaration.location }]
    rescue StandardError
      []
    end

    def receiverless_definitions(document, position, word)
      return [] unless receiverless_call_at?(document, position)

      self_type = @query_service.scope_at(document, position)&.self_type
      return [] unless self_type

      @query_service.definitions_of(self_type, word)
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
    # recorded at `position` (the same candidate list #ensure_reference_index_current
    # resolves into ReferenceIndex), resolves *that one* candidate again
    # to learn its SymbolId, then returns every location ReferenceIndex
    # has for that SymbolId. Resolving just the one clicked-on candidate
    # rather than looking up a pre-built "SymbolId at position" table
    # keeps this consistent with Hover/Definition/Completion's own "same
    # expression, same resolution path" property from Task 013 -- it's
    # the exact same #resolve a background reindex would have run.
    def references_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = analyzable_document(@document_store.fetch(uri: uri))
      summary = @file_summaries[uri]
      return [] unless document && summary

      position = params.fetch(:position)
      symbol_id = reference_symbol_id_at(document, summary, uri, position) || declaration_symbol_id_at(summary, position)
      return [] unless symbol_id

      ensure_reference_index_current
      @reference_index.references(symbol_id, minimum_confidence: :high).map { |r| { uri: r.uri, range: r.location } }
    end

    # `textDocument/documentHighlight` was implemented during 0.2.1's
    # review loop and is deferred to 0.3.0 with the capability row that
    # named it -- it is on the roadmap, not a correction to something this
    # release already claimed. Note when it returns: it calls
    # `ensure_reference_index_current`, which the comment on that method
    # says to defer until Find References or Rename needs it, because
    # rebuilding is O(workspace) and the editor asks for highlights on
    # every cursor move.
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
      document = analyzable_document(@document_store.fetch(uri: uri))
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
      document = analyzable_document(@document_store.fetch(uri: uri))
      summary = @file_summaries[uri]
      return nil unless document && summary

      symbol_id, = symbol_id_and_range_at(document, summary, uri, params.fetch(:position))
      return nil unless symbol_id

      ensure_reference_index_current
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

      declaration = declaration_named_at(summary, position)
      return [nil, nil] unless declaration

      [declaration.symbol_id, declaration.name_location || declaration.location]
    end

    # The declaration whose *name* the cursor is on, not the innermost one
    # whose range contains it.
    #
    # A `def`'s recorded range spans its whole body, so "contains the
    # position" was true of every position inside the method -- a word in
    # a comment, the contents of a string, a bare number, the `def` and
    # the `end`. Find References and Rename both read it, and both are
    # asked for deliberately, so a wrong answer was rare enough to
    # survive. Occurrence highlighting is asked on every cursor move, and
    # made it continuous: a box on the enclosing method's name almost
    # anywhere the caret went.
    #
    # `name_location` is the name; a declaration without one (a class
    # reopened by a dynamic form) falls back to its whole range, which for
    # those shapes is the name.
    def declaration_named_at(summary, position)
      summary.declarations
             .select { |d| position_within?(d.name_location || d.location, position) }
             .min_by { |d| range_span(d.name_location || d.location) }
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
    COMPLETION_KIND = { source: 2, model_column: 5, model_association: 10, signature: 2, model_api: 2 }.freeze

    # Route helper completion (Task 006) is unconditional-on-nonempty-
    # prefix, unioned with QueryService member completion (Task 013) when
    # the cursor sits right after `receiver.` — the two candidate sources
    # answer genuinely different questions (a bare identifier vs. a
    # receiver's members) and neither should suppress the other.
    def completion_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = analyzable_document(@document_store.fetch(uri: uri))
      return { isIncomplete: false, items: [] } unless document

      position = params.fetch(:position)
      prefix = word_prefix_at_position(document, position)

      # After a receiver dot the question is "what can be called on this
      # exact type", and the bare-prefix sources -- whose whole difficulty
      # is that they match too much -- must not be mixed into it.
      #
      # The test is whether there *is* a dot, not whether the member path
      # found anything. A receiver whose type is Unknown is the ordinary
      # case, and gating on the empty answer offered `thing.art` every
      # local named `article`.
      if receiver_dot_before?(document, position)
        return { isIncomplete: false, items: member_completion_items(document, position, prefix) }
      end
      # Completion after `@` -- the instance variables in scope -- was
      # built during 0.2.1's review loop and is deferred to 0.3.0 with the
      # capability row that named it.
      # A bare identifier is what the workspace and Kernel sources answer
      # about. `$stdout`, `:symbol` and the name in a `def` are not bare
      # identifiers, and each was answered with every constant starting
      # with the same letters.
      return { isIncomplete: false, items: [] } if bound_prefix_before?(document, position)

      route_items =
        if prefix.empty?
          []
        else
          @route_registry.completion_names(prefix).map do |name|
            { label: name, kind: 3,
              sortText: Semantic::PrefixCompletion.sort_text(
                Semantic::PrefixCompletion::GROUP_ROUTE_HELPER, name
              ) }
          end
        end
      bare = @prefix_completion.items(document: document, position: position, prefix: prefix)
      { isIncomplete: bare.incomplete, items: route_items + bare.items }
    end

    def member_completion_items(document, position, prefix)
      receiver_type = receiver_type_before_dot(document, position)
      return [] unless receiver_type

      @query_service.members_of(receiver_type, prefix: prefix).map do |member|
        item = { label: member.name, kind: COMPLETION_KIND.fetch(member.origin, 1), detail: member.detail&.to_s,
                 data: completion_resolve_data(receiver_type, member.name) }
        snippet = completion_snippet(member)
        item.merge(snippet ? { insertText: snippet, insertTextFormat: SNIPPET_INSERT_FORMAT } : {})
      end
    end

    # What `completionItem/resolve` needs to find this member's
    # declaration again, and nothing more: it travels to the editor and
    # back on every item in the list.
    def completion_resolve_data(receiver_type, name)
      base = Types.base_nominal(receiver_type)
      return nil unless base

      { receiver: base.name, name: name }
    end

    # LSP InsertTextFormat.Snippet: `$1`/`${1:name}` become tab stops
    # rather than literal text.
    SNIPPET_INSERT_FORMAT = 2

    # Accepting a completion should leave the cursor where the next thing
    # gets typed, not at the end of a bare name the user then has to add
    # parentheses to. Three cases, because we know three different amounts
    # about a method:
    #
    # - parameter names known (workspace source): each becomes a tab stop,
    #   so `takes_two` completes to `takes_two(first, second)` and Tab
    #   moves between them;
    # - takes arguments but names unknown: Rails' own methods are nearly
    #   all `(*, **, &)`, so there is nothing to name -- open the
    #   parentheses and put the cursor inside, `where($1)`;
    # - takes nothing: insert the bare name. `save()` is not how Ruby is
    #   written, and an editor that produces it is worse than one that
    #   inserts plain text.
    def completion_snippet(member)
      parameters = member.parameters
      return "#{member.name}($1)" if parameters == :unknown_arity
      return nil if parameters.nil? || parameters.empty?

      stops = parameters.each_with_index.map { |name, index| "${#{index + 1}:#{name}}" }
      "#{member.name}(#{stops.join(', ')})"
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
      document = analyzable_document(@document_store.fetch(uri: uri))
      return { signatures: [] } unless document

      position = params.fetch(:position)
      method_name = enclosing_call_name(document, position)
      return { signatures: [] } unless method_name

      # The guard belongs here rather than inside `#method_signature_help`:
      # a route helper answered first and never reached it, so writing
      # `def post_path(record)` -- overriding a route helper is ordinary
      # Rails -- popped the *helper's* signature with `id` bolded.
      name_range = enclosing_call_name_range(document, position)
      return { signatures: [] } if name_range &&
                                   bound_prefix_before?(document, document.char_offset_to_position(name_range.end))

      help = route_signature_help(method_name) || method_signature_help(document, position, method_name)
      return help if help.fetch(:signatures).empty?

      # `activeParameter` -- which parameter the cursor is on -- was built
      # here during 0.2.1's review loop and is deferred to 0.4.0 with the
      # capability row that named it (S4; the roadmap's "Signature help
      # highlights the argument the cursor is in"). It is on the roadmap,
      # not a correction to something this release already claimed.
      help
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
      # `options = {}` is a parameter like the others: it was in the label
      # and not in `parameters`, so a cursor on the last argument indexed
      # past the end and highlighted nothing.
      all_labels = required_labels + optional_labels + ["options = {}"]
      {
        signatures: [
          {
            label: "#{method_name}(#{all_labels.join(', ')})",
            parameters: all_labels.map { |label| { label: label } }
          }
        ]
      }
    end

    def method_signature_help(document, position, method_name)
      name_range = enclosing_call_name_range(document, position)
      return { signatures: [] } unless name_range

      call_start = document.char_offset_to_position(name_range.begin)
      # A `def`'s own parentheses look exactly like a call's to a scan
      # that counts them, so the cursor between them answered with the
      # method being *declared*. Hover and go to definition were taught
      # this in 0.2.1 and signature help was not, while the changelog
      # named all three.
      return { signatures: [] } if bound_prefix_before?(document, document.char_offset_to_position(name_range.end))

      # With no receiver the call is on the enclosing `self`, the same
      # reading go-to-definition and bare-prefix completion take. Without
      # this, `takes(` inside the class that declares `takes` answered
      # nothing -- the third row whose example covered only the
      # receiver-qualified half of what it promises.
      receiver_type = receiver_type_before_dot(document, call_start) ||
                      @query_service.scope_at(document, call_start)&.self_type
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
      # *Unmatched*, which this claimed and did not do: it stopped at the
      # first `(` going back, so a call that had already closed before the
      # cursor won. `takes(compute(1), 2)` answered with `compute`'s
      # signature from the closing paren onward, and on scaffolded Rails
      # `link_to "Edit", edit_article_path(@article), class: "btn"` showed
      # `edit_article_path`'s parameters for the rest of the line.
      #
      # Harmless while the receiverless path did not resolve -- every such
      # position has `(` rather than `.` before the name, so signature help
      # answered nothing. 0.2.0 gave that path a receiver (the enclosing
      # `self`) and turned silence into a wrong answer, which is the trade
      # this project takes the other way round.
      #
      # Over *code* only. Counting raw characters made `takes("smile :(",`
      # walk past the real call and answer nothing, and
      # `takes(label("x("), ` answer with `label` -- silence turned into a
      # wrong answer by the same depth count that was added to remove one.
      tokens = structural_tokens(document)
      cursor = idx + 1
      index = last_token_index_before(tokens, cursor)
      depth = 0
      idx = -1
      while index >= 0
        offset, kind = tokens[index]
        case kind
        # Everything that closes counts, and everything that opens
        # cancels one -- including a bracket or brace, because Prism
        # closes `puts (1)`'s parenthesis with the same token it closes a
        # call's, and an opener this scan ignored would leave that pair
        # unbalanced.
        when :paren_close, :nest_close then depth += 1
        # Never below zero: an *unmatched* opener -- the cursor inside a
        # literal whose call is still open -- drove the count negative,
        # so the scan walked past the real call and out into earlier
        # lines. `alpha([1, |2], 3)` answered nothing where 0.2.0
        # answered, and a cursor in a literal with no enclosing call at
        # all re-balanced against an earlier statement and answered with
        # a call it is nowhere near. There is no being more closed than
        # closed.
        when :nest_open then depth -= 1 unless depth.zero?
        when :paren_open
          if depth.zero?
            idx = offset
            break
          end
          depth -= 1
        end
        index -= 1
      end
      return nil if idx.negative?

      # The same `!`/`?` rule, read the other way: the character before a
      # call's `(` is the last of its *name*, so `refresh!(` has to give
      # up its `!` before the word scan starts or the name comes back
      # empty and signature help answers nothing.
      name_end = idx
      name_end -= 1 if name_end.positive? && METHOD_NAME_SUFFIXES.include?(text[name_end - 1])
      name_start = name_end
      name_start -= 1 while name_start.positive? && word_char?(text[name_start - 1])
      return nil if name_start == name_end

      name_start...(idx)
    end

    def call_name_position(document, position)
      range = enclosing_call_name_range(document, position)
      range && document.char_offset_to_position(range.begin)
    end

    # The character offsets of this document that are *code* — outside any
    # string or character literal and outside any `#` comment.
    #
    # One answer, shared by the two scans signature help runs, because
    # they are two questions about the same text and 0.2.1 shipped them
    # disagreeing: the comma count skipped strings, the scan that finds
    # the call did not, so `takes("a, b(", ` counted right and looked in
    # the wrong place. A single `#` in a string, or a single quote in a
    # comment, is enough to make two scanners diverge, so there is one.
    #
    # Line by line, and each line read forwards, because a quote cannot be
    # classified backwards: whether `"` opens or closes depends on how
    # many came before it. A string that spans lines (a heredoc, a `%w[]`
    # across lines) is therefore read as ending at its line — wrong, but
    # wrong in the direction the old code was already wrong in, and
    # signature help does not reach across one.
    #
    # The structural tokens of this document -- the parentheses, brackets,
    # braces and commas that are *code* -- as a sorted array of
    # `[offset, symbol]`, cached per document version.
    #
    # Both of signature help's scans used to walk the text one character
    # at a time, asking a per-character mask whether each was code. That
    # was correct and unusably slow: with the parens before the cursor
    # balanced there is no early exit, so the loop ran to offset 0, and
    # `text[idx]` on a string Ruby has classed as multibyte is not a
    # constant-time operation. Measured on a 603 KB file with one Japanese
    # comment in it: **8.0 s** to answer that there is no signature at
    # all, on a single-threaded server, with completion and diagnostics
    # queued behind it.
    #
    # Prism already told us which tokens these are while building the
    # mask, so keeping *them* instead of a set of every code offset makes
    # both scans walk parentheses rather than characters -- and the
    # multibyte cost disappears with the character indexing. `%w(`'s
    # parenthesis never appears here because Prism lexes it as a string
    # delimiter, which is the same reason the mask existed.
    #
    # `#{` and `}` are kept as a brace pair: they nest and balance like
    # any other, and what is written between them is real Ruby.
    # Prism gives the *same character* different token types depending on
    # what it opens, and every one of them has to be here or the depth
    # count goes wrong in one direction only: an unmapped opener still
    # meets a mapped closer. An array literal opens `BRACKET_LEFT_ARRAY`,
    # a block's brace is `BRACE_LEFT` but a lambda's is `LAMBDA_BEGIN`,
    # and `puts (1)` opens `PARENTHESIS_LEFT_PARENTHESES` -- so
    # `takes([1, 2, 3], ` counted the literal's commas as this call's and
    # bolded a parameter two along.
    #
    # A parenthesised *expression* is deliberately `:nest_open` rather
    # than `:paren_open`: it is not a call's argument list, so the scan
    # looking for the enclosing call must pass through it rather than
    # stop at it.
    STRUCTURAL_TOKENS = {
      PARENTHESIS_LEFT: :paren_open, PARENTHESIS_RIGHT: :paren_close,
      PARENTHESIS_LEFT_PARENTHESES: :nest_open,
      BRACKET_LEFT: :nest_open, BRACKET_LEFT_ARRAY: :nest_open, BRACKET_RIGHT: :nest_close,
      BRACE_LEFT: :nest_open, LAMBDA_BEGIN: :nest_open, BRACE_RIGHT: :nest_close,
      EMBEXPR_BEGIN: :nest_open, EMBEXPR_END: :nest_close,
      COMMA: :comma
    }.freeze

    def structural_tokens(document)
      key = [document.uri, document.version, document.text.length]
      return @structural_tokens_value if @structural_tokens_key == key

      @structural_tokens_key = key
      @structural_tokens_value = compute_structural_tokens(document.text)
    end

    def compute_structural_tokens(text)
      found = Prism.lex(text).value.filter_map do |token, _state|
        kind = STRUCTURAL_TOKENS[token.type]
        kind && [token.location.start_offset, kind]
      end
      to_character_offsets(text, found)
    rescue StandardError
      []
    end

    # Prism reports byte offsets and every caller here counts characters.
    # They are the same number until the file contains one multibyte
    # character, and converting each offset with `byteslice(0, n).length`
    # is O(offsets x filesize) -- which is why one Japanese comment made a
    # 265 KB file cost 3.4 seconds per keystroke while its ASCII twin cost
    # 150 ms, and why it got four times worse with every doubling. One
    # pass over the string converts all of them.
    def to_character_offsets(text, entries)
      return entries if entries.empty? || text.bytesize == text.length

      mapping = {}
      byte = 0
      character = 0
      text.each_char do |char|
        mapping[byte] = character
        byte += char.bytesize
        character += 1
      end
      mapping[byte] = character
      entries.map { |entry| entry.map { |value| value.is_a?(Integer) ? mapping.fetch(value, value) : value } }
    end
    # The index of the last structural token at or before `offset`.
    def last_token_index_before(tokens, offset)
      (tokens.bsearch_index { |token| token.first >= offset } || tokens.length) - 1
    end

    # Whether `offset` falls inside a string, a regexp, a heredoc or a
    # comment. Only the `@` completion asks this -- a YARD `@param` tag or
    # an `@` inside a string is nobody typing an instance variable -- and
    # it asks about one offset per request, so the spans are kept rather
    # than a per-character mask.
    NON_CODE_TOKEN_PREFIXES = %w[STRING_ REGEXP_ HEREDOC_ EMBDOC_ PERCENT_ SYMBOL_ WORDS_SEP].freeze
    NON_CODE_TOKEN_TYPES = %i[COMMENT CHARACTER_LITERAL].freeze

    def inside_string_or_comment?(document, offset)
      key = [document.uri, document.version, document.text.length]
      unless @non_code_spans_key == key
        @non_code_spans_key = key
        @non_code_spans_value = compute_non_code_spans(document.text)
      end
      @non_code_spans_value.any? { |start, finish| offset >= start && offset < finish }
    end

    def compute_non_code_spans(text)
      found = Prism.lex(text).value.filter_map do |token, _state|
        name = token.type.to_s
        next unless NON_CODE_TOKEN_TYPES.include?(token.type) ||
                    NON_CODE_TOKEN_PREFIXES.any? { |prefix| name.start_with?(prefix) }

        [token.location.start_offset, token.location.end_offset]
      end
      to_character_offsets(text, found)
    rescue StandardError
      []
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
    # Whether the identifier under the cursor is spoken for -- by a sigil
    # that makes it a variable or a symbol rather than a name to resolve,
    # or by a `def` that makes it a name being *declared*.
    BOUND_PREFIX_SIGILS = %w[@ $ :].freeze

    def bound_prefix_before?(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = offset
      # A Ruby method name can end in `!` or `?`, and stopping at one left
      # the scan looking at the sigil rather than at what precedes the
      # name -- so `def save!(a|)` answered with the method being
      # *declared*.
      left -= 1 if left.positive? && METHOD_NAME_SUFFIXES.include?(text[left - 1])
      left -= 1 while left.positive? && word_char?(text[left - 1])
      return false unless left.positive?

      # The character immediately before the word answers all of them,
      # `@@count` included -- its nearest neighbour is still an `@`.
      return true if BOUND_PREFIX_SIGILS.include?(text[left - 1])

      # `undef` names a method the same way `def` does -- a name being
      # declared or removed, not one to resolve. The boundary is `def`
      # the keyword rather than the three letters: `predef use` is an
      # ordinary call and still gets the workspace's answer.
      #
      # `def self.` and `def Foo.` are the same declaration with a
      # receiver written between, which the anchor below cannot see past.
      keyword = text[...left].rindex(/(?:\A|[^\w.])(?:un)?def\s+(?:[A-Za-z_][\w:]*\.)?\z/)
      return false unless keyword

      # Over *code* only. `\s+` spans newlines, so a comment whose last
      # word happens to be `def` -- "# a def", "# undef this later" --
      # silenced signature help and completion on the identifier below it,
      # with nothing to tell the user why. The same mistake the call scan
      # made until it was given this mask.
      !inside_string_or_comment?(document, text[...left].rindex(/(?:un)?def/) || keyword)
    end

    def receiver_dot_before?(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = name_start_offset(text, offset)
      left.positive? && text[left - 1] == "."
    end

    def receiver_type_before_dot(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = name_start_offset(text, offset)
      return nil if left.zero? || text[left - 1] != "."

      dot_position = document.char_offset_to_position(left - 1)
      # An `@ivar` in a template gets its type from the controller action
      # that assigned it, and that arrives as the initial environment --
      # nothing in the template itself assigns it. Hover has always passed
      # it (H3); completion and go-to-definition, which share this helper,
      # did not, so `@article.` in a view completed to nothing while
      # hovering the same `@article` answered `Article`. Task 013 records
      # "hover and completion use the same receiver type" as the rule.
      #
      # Only the environment: `document` here has already been through
      # `#analyzable_document`, so the ERB is extracted. Extracting again
      # -- which is what borrowing `#explain_type_in_view` wholesale does
      # -- breaks the local case this row was written for.
      # The same environment the `@` list is built from, for the same
      # reason: a scaffolded controller assigns `@article` in a
      # `before_action` and uses it in `edit`, `update` and `destroy`, so
      # a walk that only sees the current method body finds nothing. 0.2.1
      # gave the `@` list that environment and left this one behind, which
      # produced the disagreement it had just spent the release removing
      # elsewhere: the `@` popup said `Article` and `@article.` a
      # keystroke later offered nothing.
      initial_env = erb_view?(document.uri) ? ivars_for_view(document.uri) : {}
      type = @query_service.type_at(document, dot_position, initial_env: initial_env)
      type == Types::UNKNOWN ? nil : type
    end

    def word_at_position(document, position)
      text = document.text
      offset = document.position_to_char_offset(position)

      left = name_start_offset(text, offset)
      right = offset
      right += 1 while right < text.length && word_char?(text[right])
      # A Ruby method name can end in `!` or `?`, and stopping at them
      # looked up `destroy` for `destroy!`: hover opened an empty popup
      # and F12 said "No definition found", on the names a Rails
      # controller is mostly made of. Only one, only at the end -- that is
      # all Ruby allows, and `a ? b : c` must not be swallowed, which is
      # why the scan does not start here.
      right += 1 if right > left && METHOD_NAME_SUFFIXES.include?(text[right])

      return nil if left == right

      text[left...right]
    end

    METHOD_NAME_SUFFIXES = ["!", "?"].freeze

    # Where the name containing -- or ending at -- `offset` starts.
    #
    # Every scan in this file that walks left off a name needs the same
    # two rules, and four consecutive rounds of review found them missing
    # from one place at a time: a Ruby name may end in `!` or `?`, and
    # such a character belongs to the name only when a word character
    # precedes it, because the `!` of `!ready` is negation. Written once
    # so that the next caller cannot get a different answer, which is how
    # each of those four rounds happened.
    def name_start_offset(text, offset)
      left = offset
      left -= 1 if left > 1 && METHOD_NAME_SUFFIXES.include?(text[left - 1]) && word_char?(text[left - 2])
      left -= 1 while left.positive? && word_char?(text[left - 1])
      left
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
      reanalyze = []
      changed_models = Set.new
      needs_routes_refresh = false
      needs_restart = false
      needs_full_models_refresh = false
      needs_signature_reload = false

      params.fetch(:changes, []).each do |change|
        uri = change.fetch(:uri)
        if signature_file?(uri)
          needs_signature_reload = true
        elsif change.fetch(:type) == FILE_CHANGE_DELETED && @document_store.fetch(uri: uri).nil?
          @index_mutation_mutex.synchronize { remove_index_contribution(uri) }
          # And retract what the workspace pass published for it. Before
          # 0.2.0 an unopened file had no diagnostics and there was
          # nothing to clear; now the Problems panel would keep a finding
          # about a file that no longer exists, and nothing else ever
          # publishes for that uri again -- `WorkspaceDiagnostics#publish_for`
          # returns early on a path that is gone. A rename arrives here as
          # a delete plus a create, so this is not only the `git checkout`
          # case.
          clear_findings(uri)
        elsif @document_store.fetch(uri: uri).nil?
          # An open buffer is always authoritative over what's on disk; only
          # reindex from disk for files nobody currently has open.
          reanalyze << uri if reindex_from_disk(uri)
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

      # Under @index_mutation_mutex like every other mutation of shared
      # index state: this swaps the whole signature environment out from
      # under readers and empties the summary cache derived from it. Off
      # the lock, a request thread could read a method summary computed
      # from the pre-reload environment and store it *after* the clear,
      # leaving a stale entry that nothing else invalidates.
      if needs_signature_reload
        @index_mutation_mutex.synchronize do
          @signatures.load(workspace_root: @workspace_root)
          @method_summary_store.clear
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

      # One pass over the whole batch, after it is indexed, rather than a
      # thread per file while it is being indexed. `WorkspaceDiagnostics`
      # already checks its token between files, so a newer batch
      # supersedes this one instead of queueing behind it.
      analyze_changed_files_later(reanalyze)
    end

    # A batch of changed files, on one thread. Deliberately *not* through
    # `begin_pass`/`run`: that takes the single generation a workspace
    # pass is identified by, which supersedes the pass in flight -- and
    # unlike every other caller that supersedes one, this has no
    # replacement to start, so a `git pull` landing during the first pass
    # ended it and the rest of the workspace was never analysed.
    #
    # `publish_for` is what a pass does per file anyway: it skips an open
    # buffer and a path that is gone, and reports its own failures. The
    # list is bounded by the notification, so it needs no cap and nothing
    # needs to supersede it.
    def analyze_changed_files_later(uris)
      return if uris.empty?

      @background_tasks.track_thread(Thread.new do
        uris.each { |uri| @workspace_diagnostics.publish_for(uri) }
      rescue StandardError => e
        @logger.error("failed to analyze changed files: #{e.class}: #{e.message}")
      end)
    end

    SCHEMA_FILE_PATTERNS = [%r{db/schema\.rb\z}, %r{db/structure\.sql\z}, %r{db/migrate/}].freeze

    def signature_file?(uri)
      path = UriUtil.to_path(uri) || uri
      path.end_with?(".rbs", ".rbi")
    end

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
    # Returns whether the summary was applied, so a caller handling a
    # batch can collect the uris worth re-analysing and hand them to one
    # pass rather than starting one per file. Analysing here would put the
    # work on the dispatch thread; starting a thread per file put it on
    # the index mutex, which the dispatch thread needs for the *next*
    # file -- measured at 13.5s for a 200-file batch against 1.5s for the
    # indexing alone, with no request served meanwhile.
    def reindex_from_disk(uri)
      path = UriUtil.to_path(uri)
      return unless path && File.file?(path)

      read_sequence = @workspace_index.next_read_sequence
      document = TextDocument.new(uri: uri, text: File.read(path, encoding: Encoding::UTF_8), version: nil,
                                   language_id: "ruby")
      summary = @parser_service.summarize(document).with(source: :disk, read_sequence: read_sequence)
      apply_file_summary(summary)
    rescue StandardError => e
      @logger.error("failed to reindex #{uri} from disk: #{e.class}: #{e.message}")
      # Explicitly, because the rescue's value would otherwise be the
      # logger's -- truthy for a real IO -- and a file that failed to
      # reindex would then be queued for analysis and fail there too.
      false
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
      if agent_manager_ready?(@agent_manager)
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
    # The whole refresh is serialized with every other refresh from this
    # Server. Its final write is guarded by @agent_restart_mutex and an
    # identity check against the *current* @agent_manager: this thread captured a
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
      refresh_mutex = @agent_refresh_mutex

      generation = claim_refresh_generation(:routes)

      @background_tasks.track_thread(Thread.new do
        # Checked *before* blocking on the mutex, not only after
        # acquiring it: a superseded refresh that waits its turn behind a
        # wedged Agent still occupies a thread for the whole timeout, so
        # checking only on the inside skipped the redundant work while
        # leaving the thread pile-up it was supposed to bound.
        next unless refresh_generation_current?(:routes, generation)

        refresh_mutex.synchronize do
          # Re-checked inside: a newer request may have arrived while
          # this thread was waiting for the lock.
          next unless refresh_generation_current?(:routes, generation)
          next unless agent_manager.reload(sections: ["routes"])

          snapshot = agent_manager.fetch_snapshot(sections: ["routes"])
          unless snapshot
            logger.warn("failed to fetch routes snapshot after routes.rb change; keeping last-known-good routes")
            next
          end

          mutex.synchronize do
            next unless agent_manager.equal?(@agent_manager)

            @index_mutation_mutex.synchronize { route_registry.replace(snapshot[:routes] || []) }
            # Same reason as #install_agent_snapshot: a file open right
            # now was diagnosed against the previous route table.
            republish_open_diagnostics
          end
        end
      rescue StandardError => e
        logger.error("failed to refresh routes after routes.rb change: #{e.class}: #{e.message}")
      end)
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
    # Same stale-generation guard as #refresh_routes. All responses are
    # fetched before any are installed, then the whole changed-model batch
    # and its MethodSummaryStore invalidation become visible under one
    # semantic-index lock.
    def refresh_models(names)
      agent_manager = @agent_manager
      model_registry = @model_registry
      method_summary_store = @method_summary_store
      logger = @logger
      mutex = @agent_restart_mutex
      refresh_mutex = @agent_refresh_mutex

      enqueue_model_names(names)

      @background_tasks.track_thread(Thread.new do
        # Bow out *before* blocking on the mutex, the way #refresh_routes
        # and #refresh_all_models check their generation first. Without
        # this, the whole-section refreshes were bounded against a wedged
        # Agent but targeted model refreshes were not: every save under
        # app/models/ parked another thread on the mutex for the Agent's
        # full timeout (measured 10 blocked threads to routes' 1), each
        # holding a @background_tasks entry, all of them queued to redo
        # the identical drain. One waiter is enough; see
        # #claim_model_refresh_slot for why bowing out drops no names.
        next unless claim_model_refresh_slot

        refresh_mutex.synchronize do
          release_model_refresh_slot
          # Whichever thread gets here first refreshes every name queued
          # so far; the ones behind it find an empty set and exit.
          #
          # `outstanding` is the contract that makes "names are never
          # dropped, only batched" actually true: draining removes them
          # from @pending_model_names, so from here until each name has
          # been *successfully* committed this block owns them, and the
          # ensure below puts back whatever it still owns. Re-enqueuing
          # only on individually enumerated failure paths was not enough
          # -- `prepare_replace` raises on a malformed payload (which the
          # all-or-nothing commit is designed around) and a dying Agent
          # can raise mid-round-trip, and either unwound straight past
          # them to the rescue with the whole batch already gone. One bad
          # model then permanently suppressed every unrelated model that
          # happened to be batched with it.
          names = drain_model_names
          next if names.empty?

          outstanding = names.dup
          begin
            unless agent_manager.reload(sections: ["models"])
              # Routes already logged its equivalent failure; a dropped
              # model refresh left no trace at all, so stale model data
              # after a schema change looked like an inference bug.
              logger.warn("failed to reload models after a model change; keeping last-known-good models")
              next
            end

            # A nil response is a failed round trip, not "this model is
            # gone", so those names stay outstanding and get retried.
            responses = []
            unfetched = []
            names.each do |name|
              response = agent_manager.fetch_model(name: name)
              response ? responses << [name, response] : unfetched << name
            end
            unless unfetched.empty?
              logger.warn("failed to fetch #{unfetched.join(", ")} after a model change; will retry on the next change")
            end
            next if responses.empty?

            removals, upserts = responses.partition { |_name, response| response[:error] }
            prepared =
              begin
                model_registry.prepare_replace(upserts.to_h)
              rescue StandardError => e
                # A payload that cannot even be *built* is malformed data,
                # not a transient failure, so retrying it forever cannot
                # help -- and the ensure below would do exactly that,
                # re-enqueuing the whole batch including the bad name.
                # Every later drain then re-included it, raised again, and
                # re-enqueued again: one permanently malformed model
                # wedged every unrelated model for the life of the
                # process (verified: a well-formed `Post` queued after a
                # bad `Team` never landed, and never would).
                #
                # The name is isolated by preparing each payload alone --
                # a pure build with no side effects -- and dropped. The
                # batch still publishes nothing this pass, preserving the
                # all-or-nothing contract; what changes is that the next
                # pass is no longer poisoned. A model dropped this way
                # keeps its last-known-good entry and returns on its next
                # change, by which time the payload may be valid again.
                poisoned = upserts.filter_map do |name, response|
                  model_registry.prepare_replace({ name => response })
                  nil
                rescue StandardError
                  name
                end
                outstanding -= poisoned
                logger.error("dropping malformed model payload for #{poisoned.join(', ')}: #{e.class}: #{e.message}")
                raise
              end

            mutex.synchronize do
              # A restart replaced the Agent mid-flight; this batch is
              # stale, but the names still need refreshing.
              next unless agent_manager.equal?(@agent_manager)

              @index_mutation_mutex.synchronize do
                model_registry.commit_updates(prepared, removals: removals.map(&:first))
                method_summary_store.clear
              end
              # Committed: these names no longer need to go back.
              outstanding -= responses.map(&:first)
              republish_open_diagnostics
            end
          ensure
            enqueue_model_names(outstanding) unless outstanding.empty?
          end
        end
      rescue StandardError => e
        logger.error("failed to refresh models #{names.to_a.join(', ')}: #{e.class}: #{e.message}")
      end)
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
      method_summary_store = @method_summary_store
      logger = @logger
      mutex = @agent_restart_mutex
      refresh_mutex = @agent_refresh_mutex

      generation = claim_refresh_generation(:all_models)

      @background_tasks.track_thread(Thread.new do
        # See #refresh_routes: checked before blocking so a superseded
        # refresh does not sit on a thread for a whole Agent timeout.
        next unless refresh_generation_current?(:all_models, generation)

        refresh_mutex.synchronize do
          next unless refresh_generation_current?(:all_models, generation)

          unless agent_manager.reload(sections: ["models"])
            logger.warn("failed to reload models for a full refresh; keeping last-known-good models")
            next
          end

          models = agent_manager.fetch_all_models
          unless models
            logger.warn("failed to fetch models after a schema change; keeping last-known-good models")
            next
          end

          mutex.synchronize do
            next unless agent_manager.equal?(@agent_manager)

            responses_by_name = models.filter_map { |entry| entry[:name] && [entry[:name], entry] }.to_h
            @index_mutation_mutex.synchronize do
              model_registry.replace(responses_by_name)
              method_summary_store.clear
            end
          end
        end
      rescue StandardError => e
        logger.error("failed to refresh models after a schema change: #{e.class}: #{e.message}")
      end)
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
    def restart_agent(retry_generation: nil)
      bootstrap = @agent_bootstrap
      root = @workspace_root
      route_registry = @route_registry
      model_registry = @model_registry
      logger = @logger
      mutex = @agent_restart_mutex
      background_tasks = @background_tasks

      thread = Thread.new do
        mutex.synchronize do
          next if retry_generation && !scheduled_agent_retry_current?(retry_generation)

          @agent_manager&.stop
          # A class's ancestors cannot change without a restart, which is
          # precisely why they cannot survive one: what comes back may be
          # a different Gemfile, a different environment, and answering
          # from the old process would be answering about an application
          # that no longer exists. #reset also moves the registry's epoch,
          # which is what stops a fetch already in flight against the dying
          # process from landing afterwards and re-populating what was just
          # cleared -- answered names are never re-asked, so a stale answer
          # that got in would have been permanent.
          @ancestry_registry.reset
          manager = start_agent_bootstrap(
            bootstrap,
            root: root, logger: logger, route_registry: route_registry, model_registry: model_registry,
            on_unavailable: method(:handle_agent_unavailable),
            # See #maybe_start_agent's identical hook for why this
            # deliberately does not assign @agent_manager itself -- only
            # registers the manager with BackgroundTasks so it can be
            # reached/cancelled independently of whatever @agent_manager
            # currently holds (still the just-#stop-ped old manager, at
            # this point).
            on_manager_created: ->(created) { background_tasks.track_manager(created) }
          )
          @agent_manager = background_tasks.track_manager(coerce_agent_manager(manager))
        end
        if agent_manager_ready?(@agent_manager)
          @agent_supervisor.record_success
          cancel_scheduled_agent_retries
          # Only now is there an Agent to ask. The snapshot's own republish
          # already ran, from inside the bootstrap call above, while
          # @agent_manager was still unassigned -- so the unknown-method
          # check saw no Agent, did not defer, and reported the very false
          # positives this release removes. Everything open is answered
          # once more, with the Agent in place.
          #
          # This is the ordinary path, not a race: VS Code restores its
          # editors at startup and opens them immediately, while a real
          # Rails boot takes tens of seconds.
          republish_open_diagnostics
        end
      rescue StandardError => e
        logger.error("failed to restart runtime agent: #{e.class}: #{e.message}")
      end
      background_tasks.track_thread(thread)
    end

    # Always passes install_snapshot rather than sniffing whether the
    # bootstrap declares it. The reflection this replaces made a
    # load-bearing atomicity guarantee depend on a signature guess: any
    # bootstrap it guessed wrong about (a wrapper, a decorator, a
    # method_missing-backed object, a future signature change) silently
    # took RailsBootstrap's fallback branch, which commits routes and
    # models as two separate un-locked writes and never clears the method
    # summary store -- precisely the mixed state installing them together
    # exists to prevent. A capability this important is a contract, not
    # something to infer at runtime.
    def start_agent_bootstrap(bootstrap, **kwargs)
      bootstrap.start(install_snapshot: method(:install_agent_snapshot), **kwargs)
    end

    def install_agent_snapshot(routes:, models:)
      prepared_routes = @route_registry.prepare_replace(routes) if routes
      prepared_models = @model_registry.prepare_replace(models) if models
      @index_mutation_mutex.synchronize do
        @route_registry.commit_replace(prepared_routes) if prepared_routes
        if prepared_models
          @model_registry.commit_replace(prepared_models)
          @method_summary_store.clear
        end
      end
      republish_open_diagnostics
    end

    # Diagnostics are computed when a document is opened or changed, and
    # the answer depends on Rails data that arrives later: the extension
    # opens files as soon as it starts, seconds before the Runtime Agent
    # has reported a single route. Every `*_path` in an already-open file
    # was therefore marked unresolved permanently -- the only way to clear
    # it was to edit the file -- while a file opened afterwards was fine.
    #
    # So whenever that data lands, everything currently open is answered
    # again. Failures are per-document: one unparseable buffer must not
    # stop the rest being corrected.
    # Every caller of this is a place where the answers just changed for
    # reasons that have nothing to do with any one file -- the Runtime
    # Agent becoming ready or restarting, routes and models being
    # installed, trust being granted. All of them apply to the workspace
    # exactly as much as to the open buffers, and before 0.2.0 only the
    # buffers were re-asked because only the buffers were ever asked.
    #
    # Wired here rather than at each of the six call sites so a seventh
    # cannot be added that quietly refreshes half the workspace.
    def republish_open_diagnostics
      @document_store.open_documents.each do |document|
        publish_diagnostics(document)
      rescue StandardError => e
        @logger.error("failed to republish diagnostics for #{document.uri}: #{e.class}: #{e.message}")
      end
      start_workspace_diagnostics
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
          completionProvider: { triggerCharacters: ["."], resolveProvider: true },
          semanticTokensProvider: {
            legend: { tokenTypes: SemanticTokens::LEGEND, tokenModifiers: SemanticTokens::MODIFIERS },
            full: true
          },
          signatureHelpProvider: { triggerCharacters: ["("] }
        },
        serverInfo: {
          name: "ovallsp",
          version: Ovallsp::VERSION
        },
        ovallspInfo: ovallsp_info
      }
    end

    # Task 023.2: everything the Extension's own version-compatibility
    # handshake needs to judge whether this Core is safe to keep talking
    # to, beyond the bare `serverInfo` LSP already has a slot for. Always
    # reports protocol/coreVersion/ruby identity (true regardless of
    # whether this is a packaged VSIX or a monorepo dev checkout); `build`
    # is only ever non-nil for a packaged VSIX, since a dev checkout has no
    # `PLATFORM_MANIFEST.json` to read it from (Ovallsp::BuildManifest
    # returns nil the same way VendorCompatibility already treats that
    # case -- "no information", not an error).
    def ovallsp_info
      manifest = Ovallsp::BuildManifest.load
      {
        coreVersion: Ovallsp::VERSION,
        protocol: {
          current: Ovallsp::ProtocolVersion::CURRENT,
          minimumClient: Ovallsp::ProtocolVersion::MINIMUM_CLIENT,
          maximumClient: Ovallsp::ProtocolVersion::MAXIMUM_CLIENT,
          minimumServer: Ovallsp::ProtocolVersion::MINIMUM_SERVER,
          maximumServer: Ovallsp::ProtocolVersion::MAXIMUM_SERVER
        },
        ruby: {
          engine: RUBY_ENGINE,
          version: RUBY_VERSION,
          platform: RUBY_PLATFORM
        },
        build: manifest && {
          commit: manifest["buildCommit"],
          target: manifest["buildTarget"],
          payloadSha256: manifest["payloadSha256"]
        }
      }
    end

    # Semantic highlighting (0.2.0). Answers `{ data: [] }` rather than
    # nil for a document it has nothing to say about: a null result tells
    # the client the request failed, and a client told that stops asking.
    def semantic_tokens_result(params)
      uri = params.fetch(:textDocument).fetch(:uri)
      document = @document_store.fetch(uri: uri)
      return { data: [] } unless document

      { data: SemanticTokens.encode(document) }
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
    # The type of `self` where the cursor is, for a word that is not
    # receiver-qualified. Nil when the position has a receiver in front of
    # it: a receiver whose own type is Unknown must stay unanswered rather
    # than fall back to the enclosing class, or `thing.article_params`
    # would be answered from the file it is written in.
    def enclosing_self_type(document, position)
      return nil unless receiverless_call_at?(document, position)

      @query_service.scope_at(document, position)&.self_type
    end

    # Whether the cursor is on the *message* of a call that was written
    # with no receiver -- `article_params`, not `thing.article_params` and
    # not the word `article_params` occurring in a comment.
    #
    # The question used to be "is there a `.` immediately before this
    # word", which every word in the file answers no to. Hover, go to
    # definition and signature help each took that as licence to look the
    # word up as a method on the enclosing `self`, so resting on prose
    # inside a comment, on the contents of a string, on a parameter name
    # in a `def`, or on a local variable sharing a name with a method
    # opened a popup asserting a call that is not there. Ruby's own rule
    # settles the last of those outright: a local in scope always wins
    # over a same-named method.
    #
    # `ParserService` already records every call site with its message
    # range and whether it had a receiver -- the same records Find
    # References resolves -- so this reads the answer instead of guessing
    # at it. A local read is a `LocalVariableReadNode` and produces no
    # call candidate at all; so do a comment, a string's contents and a
    # parameter name.
    def receiverless_call_at?(document, position)
      summary = @file_summaries[document.uri] || @parser_service.summarize(document)
      summary.reference_candidates.any? do |candidate|
        candidate.kind == :method_call && candidate.receiver.nil? && position_within?(candidate.location, position)
      end
    rescue StandardError
      false
    end

    def hover_lines(document, position, type)
      lines = type == Types::UNKNOWN ? [] : [type.to_s]
      documentation = nil

      word = word_at_position(document, position)
      # Skipped for .erb views: #receiver_type_before_dot queries #type_at
      # directly against `document`, which only works for a plain Ruby
      # buffer -- an .erb view needs the synthetic-source/ivar-seeded path
      # #explain_type_in_view already used just above for `type` itself.
      # With no receiver the call is on the enclosing `self`, which is how
      # most Ruby calls a method of its own class -- `article_params` in a
      # controller. Go to definition and signature help were given this
      # reading in 0.2.0 and hover was not, so hovering such a call
      # answered an empty popup while H5 promises its parameter list with
      # no qualifier about receivers.
      receiver_type = word && !erb_view?(document.uri) &&
                      (receiver_type_before_dot(document, position) || enclosing_self_type(document, position))
      if receiver_type
        # The call's own shape, first: hovering `value.documented(1)` is
        # most often a question about what to pass, and the answer was
        # only reachable by retyping `(` to trigger signature help.
        signature = @query_service.signatures_of(receiver_type, word).first
        lines.unshift(signature[:label]) if signature && signature[:label]

        origin = hover_origin(receiver_type, word)
        lines << "Origin: #{origin}" if origin

        location = @query_service.definitions_of(receiver_type, word).first
        if location
          lines << "Defined: #{location[:uri]}:#{location[:range][:start][:line] + 1}"
          documentation = documentation_at(location)
        end
      end

      # Prose, separated from the type/origin/path lines by a blank line
      # rather than run together with them -- otherwise the comment's
      # first line reads as part of the signature.
      documentation ? lines + ["", documentation] : lines
    end

    # The comment block above a declaration, read from the buffer if the
    # file is open and from disk otherwise (0.2.0). Nothing indexes
    # comments: they live in the source, and this is the only place that
    # wants them.
    def documentation_at(location)
      uri = location[:uri]
      document = @document_store.fetch(uri: uri) || load_document_from_disk(uri)
      return nil unless document

      Documentation.above(document.text, location.dig(:range, :start, :line))
    rescue StandardError => e
      @logger.error("failed to read documentation for #{uri}: #{e.class}: #{e.message}")
      nil
    end

    # Fills in the documentation for the one item the editor is actually
    # showing (0.2.0).
    #
    # Reading the source for every candidate would put a file read per
    # item on the request path, for documentation the user sees for one of
    # them at most -- so the list carries only `data`, the receiver and
    # name this needs to find the declaration again.
    def completion_resolve_result(params)
      item = params.dup
      data = item[:data]
      # Only that there is a `data`. A `data` missing either key cannot
      # produce a definition either -- `definitions_of` answers nothing
      # for a nil name -- so testing the keys here was a condition no
      # input could reach.
      return item unless data

      location = @query_service.definitions_of(Types::Nominal.new(name: data[:receiver]), data[:name]).first
      return item unless location

      documentation = documentation_at(location)
      return item unless documentation

      # `plaintext`, the same kind hover sends. RDoc/YARD is not markdown:
      # under CommonMark two comment lines become one run-on paragraph
      # and `*bold*`/`+code+`/`_italic_` are reinterpreted, so declaring
      # it markdown rendered one source two ways depending on which
      # request asked for it.
      item.merge(documentation: { kind: "plaintext", value: documentation })
    rescue StandardError => e
      @logger.error("failed to resolve completion item: #{e.class}: #{e.message}")
      params
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
