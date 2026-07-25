# frozen_string_literal: true

require "timeout"
require_relative "../plugins"
require_relative "manifest"
require_relative "static_context"
require_relative "runtime_context"

module Rslsp
  module Plugins
    # Discovers and loads plugins from explicit manifest paths only --
    # never by scanning installed Gems ("自動検出したGemだけを理由に
    # コード実行しない" -- docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md).
    # Every failure mode (invalid manifest, version mismatch, missing
    # entrypoint, an exception or timeout from the plugin's own code)
    # degrades to "this one plugin contributes nothing", logged, never
    # raised -- one broken plugin must never take Core down, and must
    # never prevent every *other* plugin (or Core itself) from working.
    #
    # A plugin's entrypoint runs in a genuinely separate OS process
    # (Process.fork), not merely a Timeout-wrapped Kernel.load in this
    # process -- a follow-up review of this task found that an earlier
    # version ran `Kernel.load` directly here, meaning a plugin file's
    # own top-level code (reopening `Rslsp::WorkspaceIndex` to monkey-
    # patch a method, defining a stray top-level constant, anything at
    # all -- independent of what it does with the StaticContext object
    # it's handed) permanently corrupted this Core process for the rest
    # of its lifetime, surviving even after the "isolated" call
    # returned. Only plain data crosses back across the fork boundary
    # (declarations for a static plugin; snapshot-section/reload-hook
    # *names*, not the Procs themselves, for a runtime one, since Ruby
    # Procs can't be Marshaled across a process boundary) -- whatever
    # damage a plugin's own code does happens in a short-lived child
    # process that's discarded (successfully or not) the moment this
    # method returns, POSIX `Process.fork` semantics.
    class Loader
      DEFAULT_TIMEOUT_SECONDS = 5
      MAX_CONSECUTIVE_FAILURES = 3

      def initialize(logger:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        @logger = logger
        @timeout_seconds = timeout_seconds
        @failure_counts = Hash.new(0)
        @disabled = {}
      end

      # Returns one Plugins::StaticContext per manifest that validated,
      # version-matched, and ran without error/timeout -- a manifest that
      # failed any of those simply contributes no entry to the returned
      # array.
      def load_static(manifest_paths)
        Array(manifest_paths).filter_map { |path| load_static_one(path) }
      end

      # "untrusted workspaceでruntime pluginを実行しない" -- checked here,
      # before a single byte of any runtime entrypoint is read, let alone
      # loaded: an untrusted workspace gets `trusted: false` and this
      # returns [] unconditionally, the same fail-closed posture
      # RailsBootstrap's own Agent gating already uses
      # (docs/02-architecture.md section 11).
      def load_runtime(manifest_paths, trusted:)
        return [] unless trusted

        Array(manifest_paths).filter_map { |path| load_runtime_one(path) }
      end

      private

      def load_static_one(path)
        manifest = safe_load_manifest(path)
        return nil unless manifest && entrypoint_ok?(manifest, manifest.static_entrypoint_path, "static")
        return nil if disabled?(manifest.name)

        declarations = run_isolated(manifest.name) { static_plugin_declarations(manifest) }
        return nil unless declarations

        StaticContext.new(manifest.name).tap { |context| context.restore_declarations(declarations) }
      end

      # Runs *inside the forked child* -- everything this touches
      # (loading the entrypoint file, invoking the plugin's registered
      # block) is thrown away with the child process; only the plain-
      # data `declarations` array returned here is Marshaled back to
      # the parent.
      def static_plugin_declarations(manifest)
        context = StaticContext.new(manifest.name)
        Kernel.load(manifest.static_entrypoint_path)
        Plugins.static_registration(manifest.name)&.call(context)
        context.declarations
      end

      def load_runtime_one(path)
        manifest = safe_load_manifest(path)
        return nil unless manifest && entrypoint_ok?(manifest, manifest.runtime_entrypoint_path, "runtime")
        return nil if disabled?(manifest.name)

        summary = run_isolated(manifest.name) { runtime_plugin_summary(manifest) }
        return nil unless summary

        RuntimeContext.new(manifest.name).tap do |context|
          context.restore_summary(summary[:snapshot_section_names], summary[:reload_hook_count])
        end
      end

      # Same "runs inside the forked child" contract as
      # #static_plugin_declarations -- but a Proc can't be Marshaled
      # across the fork boundary at all, so only the registered
      # sections'/hooks' *names* (not the callables themselves) survive
      # back into the parent. See RuntimeContext#restore_summary.
      def runtime_plugin_summary(manifest)
        context = RuntimeContext.new(manifest.name)
        Kernel.load(manifest.runtime_entrypoint_path)
        Plugins.runtime_registration(manifest.name)&.call(context)
        { snapshot_section_names: context.snapshot_sections.keys, reload_hook_count: context.reload_hooks.size }
      end

      def safe_load_manifest(path)
        manifest = Manifest.load(path)
        return manifest if manifest.compatible_protocol_version?

        @logger.error(
          "plugin #{manifest.name}: protocol_version #{manifest.protocol_version} is incompatible with this " \
          "Core build's #{CURRENT_PROTOCOL_VERSION} -- not loaded"
        )
        nil
      rescue InvalidManifest => e
        @logger.error("plugin manifest invalid at #{path}: #{e.message}")
        nil
      end

      def entrypoint_ok?(manifest, entrypoint_path, kind)
        return false unless entrypoint_path
        return true if File.file?(entrypoint_path)

        @logger.error("plugin #{manifest.name}: #{kind}_entrypoint not found at #{entrypoint_path}")
        false
      end

      def disabled?(name)
        @disabled.key?(name)
      end

      # Forks a child process to run `block`, Marshals whatever it
      # returns back to the parent through a pipe, and returns that
      # value here -- or nil (logged, failure-counted, eventually
      # disabling the plugin after MAX_CONSECUTIVE_FAILURES) for any of:
      # the child raising, the child exceeding @timeout_seconds (killed
      # with SIGKILL), or the child's result failing to Marshal/unMarshal
      # at all.
      def run_isolated(name)
        reader, writer = ::IO.pipe
        pid =
          begin
            fork_plugin_child(writer) { yield }
          rescue StandardError, NotImplementedError => e
            # Process.fork itself failing (no fork(2) on this platform/
            # runtime, ENOMEM, ...) is an environmental failure, not
            # anything the plugin's own code did -- still must degrade
            # to "this plugin contributes nothing" rather than raising
            # out of #load_static/#load_runtime, the same "one broken
            # plugin must never take Core down" invariant every other
            # failure mode here already honors.
            reader.close
            writer.close
            return apply_isolation_result(name, { ok: false, error: "#{e.class}: #{e.message}" })
          end
        writer.close

        payload = read_isolated_result(reader, pid)
        reader.close

        apply_isolation_result(name, payload)
      end

      def fork_plugin_child(writer)
        Process.fork do
          isolate_child_io(writer)
          result = begin
            { ok: true, result: yield }
          rescue Exception => e # rubocop:disable Lint/RescueException -- a plugin's own code, isolated in this child, may raise anything at all; none of it may ever propagate past this process boundary
            { ok: false, error: "#{e.class}: #{e.message}" }
          end
          begin
            writer.write(Marshal.dump(result))
          rescue StandardError => e
            # The result itself couldn't be Marshaled (e.g. a plugin
            # somehow returned an object holding a Proc/IO/etc.) --
            # report that specific failure instead of leaving the parent
            # to time out waiting for output that will never arrive.
            writer.write(Marshal.dump({ ok: false, error: "result could not be serialized: #{e.class}: #{e.message}" }))
          end
        ensure
          writer.close
          Kernel.exit!(0)
        end
      end

      # `Process.fork` duplicates the parent's *entire* fd table, not
      # just fd 1/2 -- reopening only STDOUT/STDERR (an earlier version
      # of this fix) closed the specific leak that had been reported
      # (in `--stdio` mode fd 1 *is* the live LSP JSON-RPC transport,
      # bin/rslsp: `Server.new(..., output: $stdout)`) but left every
      # *other* IO object the parent happens to hold open -- e.g.
      # AgentProcessManager's own `@stdin_write`/`@stdout_read`/
      # `@stderr_read` pipes to a live Rails Runtime Agent
      # (agent_process_manager.rb `#spawn_process`) -- reachable from a
      # plugin with zero `require`s via `ObjectSpace.each_object(::IO)`.
      # Found live by the Task 014-018 independent review's second
      # follow-up pass: a plugin walking every open IO object in
      # ObjectSpace and writing to whichever ones weren't fd 0/1/2 could
      # corrupt or hijack the Agent's own JSON-RPC channel exactly the
      # way the original bug corrupted the editor-facing one. Fixed at
      # the actual architectural root this time: enumerate and close
      # every IO object the child inherited except the ones it legitimately
      # needs (redirected stdin/stdout/stderr, and the result pipe
      # `writer`) -- not just whichever specific fd the last report
      # happened to name. Only ever runs inside the forked child -- must
      # never touch the parent's real IO objects (this is why it takes
      # `writer` as an explicit keep-alive rather than discovering it via
      # ObjectSpace, which would also see it).
      def isolate_child_io(writer)
        devnull_r = File.open(File::NULL, "r")
        devnull_w = File.open(File::NULL, "w")
        STDIN.reopen(devnull_r)
        STDOUT.reopen(devnull_w)
        STDERR.reopen(devnull_w)
        $stdin.reopen(devnull_r) unless $stdin.equal?(STDIN)
        $stdout.reopen(devnull_w) unless $stdout.equal?(STDOUT)
        $stderr.reopen(devnull_w) unless $stderr.equal?(STDERR)

        keep = [STDIN, STDOUT, STDERR, devnull_r, devnull_w, writer]
        ObjectSpace.each_object(::IO) do |io|
          next if keep.any? { |kept| kept.equal?(io) }

          begin
            io.close unless io.closed?
          rescue StandardError
            nil
          end
        end
      rescue StandardError
        nil
      end

      def read_isolated_result(reader, pid)
        raw = nil
        begin
          Timeout.timeout(@timeout_seconds) { raw = reader.read }
        rescue Timeout::Error
          kill_child(pid)
          return { ok: false, error: "Timeout::Error: exceeded #{@timeout_seconds}s" }
        end
        Process.waitpid(pid)

        return { ok: false, error: "plugin process produced no output" } if raw.nil? || raw.empty?

        begin
          Marshal.load(raw)
        rescue StandardError => e
          { ok: false, error: "failed to read plugin process output: #{e.class}: #{e.message}" }
        end
      rescue Errno::ECHILD
        { ok: false, error: "plugin process exited unexpectedly" }
      end

      def kill_child(pid)
        Process.kill("KILL", pid)
        Process.waitpid(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def apply_isolation_result(name, payload)
        if payload[:ok]
          @failure_counts[name] = 0
          payload[:result]
        else
          @failure_counts[name] += 1
          @logger.error("plugin #{name} failed (#{@failure_counts[name]}/#{MAX_CONSECUTIVE_FAILURES}): #{payload[:error]}")
          @disabled[name] = true if @failure_counts[name] >= MAX_CONSECUTIVE_FAILURES
          nil
        end
      end
    end
  end
end
