# frozen_string_literal: true

require "json"

module Ovallsp
  module Plugins
    # The current Plugin API version this Core build implements --
    # compared against a manifest's `protocol_version` before loading
    # anything, so an incompatible plugin is refused with a clear reason
    # instead of loaded and failing in some more confusing way later
    # (docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md
    # acceptance: "API version不一致を明確に報告する").
    CURRENT_PROTOCOL_VERSION = 1

    class InvalidManifest < StandardError; end

    # A validated plugin-manifest.json, matching the fields actually
    # defined in docs/design/schemas/plugin-manifest.schema.json (the
    # "既存" schema this task connects to an implementation) --
    # deliberately hand-validated rather than pulling in a JSON-Schema
    # gem dependency for one small, fixed shape.
    Manifest = Data.define(:name, :version, :protocol_version, :static_entrypoint, :runtime_entrypoint, :capabilities,
                            :requires, :dir) do
      def initialize(static_entrypoint: nil, runtime_entrypoint: nil, capabilities: [], requires: {}, **rest)
        super(static_entrypoint: static_entrypoint, runtime_entrypoint: runtime_entrypoint, capabilities: capabilities,
              requires: requires, **rest)
      end

      def self.load(path)
        raw = JSON.parse(File.read(path), symbolize_names: true)
        from_hash(raw, dir: File.dirname(File.expand_path(path)))
      rescue Errno::ENOENT, Errno::EISDIR
        raise InvalidManifest, "no manifest file at #{path}"
      rescue JSON::ParserError => e
        raise InvalidManifest, "#{path} is not valid JSON: #{e.message}"
      end

      def self.from_hash(raw, dir:)
        validate!(raw)
        new(
          name: raw.fetch(:name), version: raw.fetch(:version), protocol_version: raw.fetch(:protocol_version),
          static_entrypoint: raw[:static_entrypoint], runtime_entrypoint: raw[:runtime_entrypoint],
          capabilities: raw[:capabilities] || [], requires: raw[:requires] || {}, dir: dir
        )
      end

      def self.validate!(raw)
        raise InvalidManifest, "manifest must be a JSON object" unless raw.is_a?(Hash)

        %i[name version protocol_version].each do |key|
          raise InvalidManifest, "manifest missing required field: #{key}" unless raw.key?(key)
        end
        unless raw[:name].is_a?(String) && raw[:name].match?(/\A[a-z0-9_-]+\z/)
          raise InvalidManifest, "manifest `name` must match ^[a-z0-9_-]+$, got #{raw[:name].inspect}"
        end
        raise InvalidManifest, "manifest `protocol_version` must be an integer" unless raw[:protocol_version].is_a?(Integer)
      end

      def compatible_protocol_version?
        protocol_version == CURRENT_PROTOCOL_VERSION
      end

      def static_entrypoint_path
        static_entrypoint && File.join(dir, static_entrypoint)
      end

      def runtime_entrypoint_path
        runtime_entrypoint && File.join(dir, runtime_entrypoint)
      end
    end
  end
end
