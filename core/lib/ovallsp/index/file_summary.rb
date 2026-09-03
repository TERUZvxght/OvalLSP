# frozen_string_literal: true

module Ovallsp
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
    # - generated_method_facts (Task 017): recognized Rails DSL macros
    #   (`enum`, `scope`, `delegate`) in this file, normalized to
    #   Index::GeneratedMethodFact. Each one is paired with a synthetic
    #   Declaration (also in `declarations`, `origin: :generated`) so
    #   completion/hover-existence/definition already work through the
    #   ordinary WorkspaceIndex/MethodResolver path; this field exists
    #   purely for what a Declaration can't carry -- return type and
    #   DSL-specific metadata.
    # - open_surface_owners (0.2.6): owners whose body contains a
    #   receiverless call this parser does not recognise -- so the set of
    #   methods they define cannot be enumerated from source, and absence
    #   cannot be established for them. `attr_atomic`, `attr_volatile` and
    #   `safe_initialization!` are the measured examples; 31 of the 34
    #   remaining false `unknown-method` reports over the gem corpus are
    #   this shape. Not a Declaration, because the point is precisely that
    #   there is no declaration to record.
    FileSummary = Data.define(:uri, :content_hash, :document_version, :declarations, :diagnostics, :source,
                               :read_sequence, :ancestor_facts, :alias_facts, :reference_candidates,
                               :generated_method_facts, :open_surface_owners, :module_function_names,
                               :buffer_id, :pattern_bound_names) do
      # `module_function_names`: `[owner, name]` pairs this file wrote a
      # `module_function :name` for. A *fact*, not a rewrite, because the
      # method it names may be declared in a different file -- which is
      # what the by-name form exists for, the section form covering the
      # same-file case. The parser rewrote what it happened to have seen,
      # so cross-file never worked and `Reopened.r_a` was reported as
      # missing (`024.114`). `WorkspaceIndex` applies these once every
      # file is in, the way it already does for `open_surface_owners`.
      # `pattern_bound_names`: names this file's patterns bind and the
      # occurrence list deliberately does *not* carry. An `_`-prefixed
      # name inside a pattern is left unrecorded because a pattern may
      # legally bind it twice and rewriting both ranges is a SyntaxError
      # (`024.274`) -- but `Rename` still has to know something binds it,
      # or `024.273`'s refusal is defeated by an ordinary assignment of
      # the same name in the same scope and the rename leaves the pattern
      # behind. Driven: the file still parses and answers 0 where it
      # answered 5 (`024.296`).
      #
      # `buffer_id`: which *buffer* the `document_version` counts within.
      # Nil for a disk read, which has no buffer and is ordered by
      # `read_sequence` instead.
      #
      # Without it `#stale?` compared two buffers' version integers as
      # though they were one sequence, and a reopen at version 1 lost to
      # the closed buffer's version 20 -- so a file reopened without a
      # close stopped updating until its numbering passed where the last
      # one left off (`024.118`). 0.2.10 fixed the same category error in
      # the publish funnel and this layer kept it.
      def initialize(source: :buffer, read_sequence: 0, ancestor_facts: [], alias_facts: [], reference_candidates: [],
                      generated_method_facts: [], open_surface_owners: [], module_function_names: [],
                      buffer_id: nil, pattern_bound_names: [], **rest)
        super(source: source, read_sequence: read_sequence, ancestor_facts: ancestor_facts, alias_facts: alias_facts,
              reference_candidates: reference_candidates, generated_method_facts: generated_method_facts,
              open_surface_owners: open_surface_owners, module_function_names: module_function_names,
              buffer_id: buffer_id, pattern_bound_names: pattern_bound_names, **rest)
      end
    end
  end
end
