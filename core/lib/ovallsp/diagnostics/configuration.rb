# frozen_string_literal: true

module Ovallsp
  module Diagnostics
    # Task 064: severity may reduce an existing check, never enable one.
    # No setters or caller-owned maps: a calculation keeps this snapshot
    # even when the server replaces its current configuration.
    class Configuration
      MODES = %i[safe standard strict].freeze
      DEFAULT_SEVERITIES = {
        "syntax-error" => :error,
        "unknown-method" => :warning,
        "unknown-route-helper" => :warning,
        "argument-count" => :warning,
        "argument-type" => :warning,
        "unassigned-ivar" => :warning
      }.freeze
      SEVERITY_NAMES = {
        "error" => :error, "warning" => :warning, "information" => :information,
        "hint" => :hint, "none" => :none
      }.freeze
      SEVERITY_RANK = { error: 0, warning: 1, information: 2, hint: 3, none: 4 }.freeze

      attr_reader :mode, :severities

      def initialize(mode: :safe, severities: {})
        raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)

        normalized = {}
        if severities.is_a?(Hash)
          severities.each do |code, value|
            code = code.to_s
            baseline = DEFAULT_SEVERITIES[code]
            severity = SEVERITY_NAMES[value]
            next unless baseline && severity
            next if SEVERITY_RANK.fetch(severity) < SEVERITY_RANK.fetch(baseline)

            normalized[code] = severity
          end
        end
        @mode = mode
        @severities = normalized.freeze
        freeze
      end

      def ==(other)
        other.is_a?(Configuration) && mode == other.mode && severities == other.severities
      end

      def apply(findings, budget: nil)
        visible = findings.filter_map do |finding|
          severity = severities.fetch(finding.code, finding.severity)
          next if severity == :none

          severity == finding.severity ? finding : finding.with(severity: severity)
        end
        budget ? visible.first(budget) : visible
      end
    end
  end
end
