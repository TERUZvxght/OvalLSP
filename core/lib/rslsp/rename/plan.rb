# frozen_string_literal: true

module Rslsp
  module Rename
    # The result of planning a rename -- a testable internal
    # representation, deliberately separate from the LSP WorkspaceEdit
    # shape Server converts it into
    # (docs/design/tasks/016-guarded-rename-and-preview.md required
    # interface: "rename planをテスト可能な内部表現として持つ").
    #
    # - target: the SymbolId being renamed (nil if nothing renameable
    #   was found at the query position).
    # - confirmed_edits: `[{ uri:, range:, new_text: }]` -- only these
    #   ever become part of an actual WorkspaceEdit. Empty whenever the
    #   rename is refused (a conflict, an invalid new name, or a
    #   generated/DSL-origin symbol) -- refusal is `confirmed_edits: []`
    #   plus a `warnings` entry explaining why, not an exception.
    # - dynamic_candidates: reserved for `send`/`public_send`-style call
    #   sites a future rename-preview might surface (Task 014 doesn't
    #   collect these as reference candidates at all yet) -- always [].
    # - conflicts: `[{ reason: }]` -- a non-empty conflicts list is what
    #   actually causes confirmed_edits to be refused/empty; kept
    #   separate from `warnings` so a caller can distinguish "refused
    #   because of a real conflict" from "succeeded, but here's something
    #   to be aware of".
    # - generation: the WorkspaceIndex generation this plan was computed
    #   against, mirroring Task 013's QueryContext staleness model.
    Plan = Data.define(:target, :confirmed_edits, :dynamic_candidates, :conflicts, :warnings, :generation) do
      def initialize(confirmed_edits: [], dynamic_candidates: [], conflicts: [], warnings: [], generation: nil, **rest)
        super(confirmed_edits: confirmed_edits, dynamic_candidates: dynamic_candidates, conflicts: conflicts,
              warnings: warnings, generation: generation, **rest)
      end

      def refused?
        confirmed_edits.empty? && !warnings.empty?
      end
    end
  end
end
