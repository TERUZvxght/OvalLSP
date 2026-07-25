# frozen_string_literal: true

module Ovallsp
  # The SDK surface a plugin entrypoint file itself calls into --
  # `Ovallsp::Plugins.register_static("my-plugin") { |context| ... }` --
  # rather than a fixed class-name convention Loader would otherwise
  # have to guess at (docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md).
  # A plain module-level Hash, not an instance: entrypoint files are
  # loaded via a bare `Kernel#load` (Plugins::Loader), so there's no
  # object of the plugin's own to hold this on.
  module Plugins
    class << self
      def register_static(name, &block)
        static_registrations[name.to_s] = block if block
      end

      def register_runtime(name, &block)
        runtime_registrations[name.to_s] = block if block
      end

      def static_registration(name)
        static_registrations[name.to_s]
      end

      def runtime_registration(name)
        runtime_registrations[name.to_s]
      end

      # Called by Plugins::Loader immediately after invoking a plugin's
      # registration block, so a *second* #load of the same (or a
      # different) entrypoint never sees a stale registration from a
      # previous load lingering in this shared, module-level Hash.
      def clear_registration(name)
        static_registrations.delete(name.to_s)
        runtime_registrations.delete(name.to_s)
      end

      private

      def static_registrations
        @static_registrations ||= {}
      end

      def runtime_registrations
        @runtime_registrations ||= {}
      end
    end
  end
end
