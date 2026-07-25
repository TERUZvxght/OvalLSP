# frozen_string_literal: true

module Ovallsp
  module Diagnostics
    # One diagnostic result (docs/design/tasks/015-confidence-aware-diagnostics.md
    # required interface).
    #
    # - code: a stable string identifying the check that produced this
    #   (e.g. "unknown-method", "unresolved-constant", "unknown-route-helper")
    #   -- never the human-readable message, which may change wording
    #   freely; a client (or a future suppress-by-code setting) keys off
    #   this instead.
    # - severity: :error, :warning, :information, or :hint (LSP's own
    #   DiagnosticSeverity vocabulary).
    # - confidence: :high or :low -- distinct from severity: a low-
    #   confidence finding is still worth surfacing in :strict mode, just
    #   never in :safe (see Engine::MODE_RANK).
    # - evidence: a short Hash describing *why* (e.g. `{ receiver: "Widget",
    #   ancestors_closed: true }`) -- "diagnosticにcode・confidence・evidence
    #   が含まれる" acceptance criterion.
    # - related_information: LSP RelatedInformation-shaped hashes pointing
    #   at a generating source (e.g. a route's own routes.rb line) --
    #   "generated methodの不足は生成元情報をrelatedInformationへ付ける".
    # - generation: the WorkspaceIndex/HierarchyIndex generation this
    #   finding was computed against, so a caller can detect staleness
    #   the same way Task 013's QueryContext does.
    Finding = Data.define(:code, :message, :range, :severity, :confidence, :evidence, :related_information, :generation) do
      def initialize(evidence: {}, related_information: [], generation: nil, **rest)
        super(evidence: evidence, related_information: related_information, generation: generation, **rest)
      end
    end
  end
end
