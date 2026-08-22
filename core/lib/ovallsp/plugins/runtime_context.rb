# frozen_string_literal: true

module Ovallsp
  module Plugins
    # A runtime plugin's contribution surface -- deliberately a thinner
    # scaffold than StaticContext: wiring a plugin-contributed section
    # into the Runtime Agent's own JSON-RPC-over-stdio snapshot protocol
    # (a separate child process, not this Core process) is real, further
    # work this task doesn't complete; #register_snapshot_section and
    # #register_reload_hook collect what a runtime plugin *would*
    # contribute, in a form Plugins::Loader keeps isolated the same way
    # static contributions are, but nothing in Server actually forwards
    # these into RailsBootstrap/AgentProcessManager yet
    # (docs/design/tasks/018-plugin-api-and-sdk.md).
    #
    # What *is* real and enforced here: a runtime plugin's entrypoint is
    # never loaded at all for an untrusted workspace -- "Runtime plugin
    # はRailsアプリと同等のコード実行権限を持つため、trusted workspaceのみ"
    # -- checked by Plugins::Loader before this class is even
    # instantiated, not by this class itself.
    class RuntimeContext
      attr_reader :snapshot_sections, :reload_hooks, :reload_hook_count

      def initialize(plugin_name)
        @plugin_name = plugin_name
        @snapshot_sections = {}
        @reload_hooks = []
        @reload_hook_count = 0
      end

      def register_snapshot_section(name, &block)
        @snapshot_sections[name.to_s] = block if block
      end

      def register_reload_hook(&block)
        @reload_hooks << block if block
      end

      # Loader-internal: reconstructs a RuntimeContext in the *parent*
      # process after a runtime plugin's entrypoint ran in an isolated
      # child process (Plugins::Loader#runtime_plugin_summary). A Proc
      # can never cross that process boundary, so `snapshot_sections`
      # here maps each registered name to `nil` (a non-callable
      # placeholder -- present so `.keys` still reports what the plugin
      # declared) rather than the real block, and `reload_hook_count`
      # stands in for the (likewise non-marshalable) `reload_hooks`
      # array.
      def restore_summary(section_names, reload_hook_count)
        @snapshot_sections = Array(section_names).each_with_object({}) { |name, sections| sections[name] = nil }
        @reload_hook_count = reload_hook_count
      end
    end
  end
end
