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

        context = StaticContext.new(manifest.name)
        succeeded = run_isolated(manifest.name) do
          Kernel.load(manifest.static_entrypoint_path)
          Plugins.static_registration(manifest.name)&.call(context)
        end
        Plugins.clear_registration(manifest.name)
        succeeded ? context : nil
      end

      def load_runtime_one(path)
        manifest = safe_load_manifest(path)
        return nil unless manifest && entrypoint_ok?(manifest, manifest.runtime_entrypoint_path, "runtime")
        return nil if disabled?(manifest.name)

        context = RuntimeContext.new(manifest.name)
        succeeded = run_isolated(manifest.name) do
          Kernel.load(manifest.runtime_entrypoint_path)
          Plugins.runtime_registration(manifest.name)&.call(context)
        end
        Plugins.clear_registration(manifest.name)
        succeeded ? context : nil
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

      # A plugin whose entrypoint raises or times out MAX_CONSECUTIVE_FAILURES
      # times in a row is disabled for the remainder of this Loader's
      # lifetime -- "disable after repeated failure". Returns whether the
      # block completed without error, so callers can tell "ran, but
      # registered nothing" apart from "never ran at all".
      def run_isolated(name)
        Timeout.timeout(@timeout_seconds) { yield }
        @failure_counts[name] = 0
        true
      rescue StandardError, Timeout::Error => e
        @failure_counts[name] += 1
        @logger.error("plugin #{name} failed (#{@failure_counts[name]}/#{MAX_CONSECUTIVE_FAILURES}): #{e.class}: #{e.message}")
        @disabled[name] = true if @failure_counts[name] >= MAX_CONSECUTIVE_FAILURES
        false
      end
    end
  end
end
