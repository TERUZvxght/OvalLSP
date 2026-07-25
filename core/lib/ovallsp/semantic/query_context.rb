# frozen_string_literal: true

module Ovallsp
  module Semantic
    # Everything a QueryService call needs to know about *when* it's being
    # asked, not just *what* — the "Staleness" section
    # (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md):
    # a caller that captures each subsystem's generation at request time
    # can tell, after a possibly-slow query returns, whether the answer is
    # still current or the workspace/runtime/signature state has since
    # moved on.
    #
    # - budget: max AST-node-visit steps for this one query (threaded into
    #   LocalInferencer#max_steps-style callees); nil means "use the
    #   callee's own default".
    # - cancellation_token: anything responding to #cancelled? — checked
    #   at the few points a query loops over an unbounded candidate set
    #   (e.g. QueryService#members_of enumerating ancestors); nil means
    #   "never cancelled".
    QueryContext = Data.define(
      :uri, :position, :document_version, :workspace_generation, :runtime_generation,
      :signature_generation, :budget, :cancellation_token
    ) do
      def initialize(uri:, position:, document_version: nil, workspace_generation: nil, runtime_generation: nil,
                      signature_generation: nil, budget: nil, cancellation_token: nil)
        super(uri: uri, position: position, document_version: document_version,
              workspace_generation: workspace_generation, runtime_generation: runtime_generation,
              signature_generation: signature_generation, budget: budget, cancellation_token: cancellation_token)
      end

      # True once any generation this context captured has since moved on
      # — a result computed under a stale context should be marked (or
      # discarded) rather than presented as current
      # ("処理中に世代が変わった場合は、古い結果を破棄するかstale metadataを付ける").
      def stale?(workspace_generation: nil, runtime_generation: nil, signature_generation: nil)
        [
          [self.workspace_generation, workspace_generation],
          [self.runtime_generation, runtime_generation],
          [self.signature_generation, signature_generation]
        ].any? { |captured, current| captured && current && captured != current }
      end

      def cancelled?
        cancellation_token.respond_to?(:cancelled?) && cancellation_token.cancelled?
      end
    end
  end
end
