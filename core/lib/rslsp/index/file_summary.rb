# frozen_string_literal: true

module Rslsp
  module Index
    # Per-document extraction result. Never holds AST node objects — only
    # normalized declarations and diagnostics, so it can outlive the parse
    # that produced it (docs/02-architecture.md "Incremental Index").
    #
    # - source: `:buffer` (from an open LSP document — didOpen/didChange)
    #   or `:disk` (read directly from the filesystem — Cold Index,
    #   didChangeWatchedFiles' reindex, didClose falling back to disk).
    #   WorkspaceIndex#replace_file uses this to guarantee an open buffer's
    #   contribution can never be overwritten by a disk read racing
    #   against it, no matter which one's write happens to land second
    #   (docs/design/tasks/008.6-agent-and-index-hardening.md) — a rule
    #   enforced once, structurally, inside WorkspaceIndex itself, so
    #   every present and future disk-reading index path (Cold Index,
    #   Task 009+ background indexers) gets it for free instead of having
    #   to each remember a "skip if open" check of their own.
    # - read_sequence: a monotonic counter from WorkspaceIndex#next_read_sequence,
    #   fetched by the caller *before* reading the file's content from
    #   disk. Only meaningful for `source: :disk`, where it resolves the
    #   remaining race disk sources can have among themselves: two disk
    #   reads of the same file can finish (and call #replace_file) in
    #   either order regardless of which one *started* reading the more
    #   current content, so ordering by "who read the file more recently"
    #   (this) rather than "who finished writing to the index more
    #   recently" (document_version, which disk sources don't have) is
    #   what actually prevents a slow, earlier-started walk (e.g. Cold
    #   Index, mid-way through a large workspace) from clobbering a fast,
    #   later-started targeted reindex with stale content.
    FileSummary = Data.define(:uri, :content_hash, :document_version, :declarations, :diagnostics, :source,
                               :read_sequence) do
      def initialize(source: :buffer, read_sequence: 0, **rest)
        super(source: source, read_sequence: read_sequence, **rest)
      end
    end
  end
end
