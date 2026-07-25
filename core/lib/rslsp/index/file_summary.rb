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
    # - ancestor_facts / alias_facts (Task 009): raw superclass/include/
    #   prepend/extend and alias/alias_method statements found in this
    #   file, in source order. Semantic::HierarchyIndex aggregates these
    #   across files the same way WorkspaceIndex aggregates declarations —
    #   kept as a separate field (not folded into `declarations`) because
    #   they describe *relationships between* types, not a type's own
    #   declaration site.
    # - reference_candidates (Task 014): raw, unresolved reference sites
    #   (constant reads, local/instance/class variable reads and writes,
    #   method calls) found in this file — Semantic::ReferenceResolver
    #   turns these into confirmed Index::Reference values once every
    #   file's declarations are known. Kept separate from `declarations`
    #   the same way ancestor_facts is: a reference candidate describes a
    #   *usage* site, not a thing being declared.
    FileSummary = Data.define(:uri, :content_hash, :document_version, :declarations, :diagnostics, :source,
                               :read_sequence, :ancestor_facts, :alias_facts, :reference_candidates) do
      def initialize(source: :buffer, read_sequence: 0, ancestor_facts: [], alias_facts: [], reference_candidates: [],
                      **rest)
        super(source: source, read_sequence: read_sequence, ancestor_facts: ancestor_facts, alias_facts: alias_facts,
              reference_candidates: reference_candidates, **rest)
      end
    end
  end
end
