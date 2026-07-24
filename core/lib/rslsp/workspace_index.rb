# frozen_string_literal: true

require "set"

module Rslsp
  # Workspace-wide aggregation of FileSummary declarations, keyed by
  # SymbolId so a class reopened across many files resolves to every
  # Declaration that contributes to it (docs/design/tasks/003-workspace-index.md).
  #
  # Mutation is single-writer and each method synchronizes on one mutex, so
  # a query never observes a half-applied replace/remove (constraint from
  # the task spec) even though the current callers are all single-threaded.
  class WorkspaceIndex
    def initialize
      @mutex = Mutex.new
      @summaries = {}
      # Never a default-proc Hash: a default proc that inserts on read
      # (the previous `Hash.new { |h, k| h[k] = [] }`) means a mere
      # existence check for a SymbolId that was never indexed
      # permanently plants an empty array in the Hash -- after Cold Index
      # touches thousands of files' worth of ad-hoc lookups (hover on an
      # unresolved constant, a definition miss, ...), most of `@by_symbol`
      # would be garbage entries nothing ever removes
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md). Reads
      # go through `@by_symbol.fetch(id, [])`; only the write path
      # (#replace_file) actually inserts a key.
      @by_symbol = {}
      # Secondary index: downcased simple (unqualified) name -> Set of
      # SymbolIds sharing it, so #find_by_simple_name doesn't have to scan
      # every distinct symbol in the workspace to answer one name lookup
      # once Cold Index has populated thousands of them.
      @by_simple_name = Hash.new { |h, k| h[k] = Set.new }
      @generation = 0
      @next_read_sequence = 0
    end

    def generation
      @mutex.synchronize { @generation }
    end

    # Monotonic counter callers reading a file from disk (Cold Index,
    # didChangeWatchedFiles' reindex, any future background indexer) must
    # fetch *before* they read the file's content, and stamp onto the
    # resulting FileSummary's `read_sequence`. This is what
    # #replace_file's staleness check for `source: :disk` orders by,
    # instead of write-arrival order — see #stale?'s comment for why that
    # distinction matters (docs/design/tasks/008.6-agent-and-index-hardening.md).
    def next_read_sequence
      @mutex.synchronize { @next_read_sequence += 1 }
    end

    # Adds or updates one file's contribution to the index. Returns false
    # (a no-op) when the content hash is unchanged, or when `summary` loses
    # to what's already indexed for this uri under #stale?'s rules — an
    # open buffer's contribution (`source: :buffer`) can never be
    # overwritten by a disk read (`source: :disk`) for the same uri, no
    # matter which call reaches #replace_file second; this is enforced
    # here, once, rather than relying on every disk-reading caller to
    # separately check DocumentStore before indexing
    # (docs/design/tasks/008.6-agent-and-index-hardening.md — Cold Index's
    # own "skip if open" check at read time left a race window between
    # that check and this call, where a didOpen for the same file landing
    # in between would get silently overwritten by the disk read finishing
    # after it).
    def replace_file(summary)
      @mutex.synchronize do
        existing = @summaries[summary.uri]
        next false if existing && existing.content_hash == summary.content_hash
        next false if stale?(existing, summary)

        remove_file_locked(summary.uri)
        @summaries[summary.uri] = summary
        summary.declarations.each do |decl|
          (@by_symbol[decl.symbol_id] ||= []) << [summary.uri, decl]
          @by_simple_name[simple_name(decl.symbol_id).downcase] << decl.symbol_id
        end
        @generation += 1
        true
      end
    end

    def remove_file(uri)
      @mutex.synchronize do
        removed = remove_file_locked(uri)
        @generation += 1 if removed
        removed
      end
    end

    # All Declarations sharing this SymbolId, across every indexed file.
    def declarations(symbol_id)
      @mutex.synchronize { @by_symbol.fetch(symbol_id, []).map { |(_uri, decl)| decl } }
    end

    # Same as #declarations, but paired with the contributing uri. Declaration
    # itself carries no uri (Task 002's contract), and callers building an
    # LSP Location need one, so this is an intentional, documented addition
    # to the task's required interface rather than a change to it.
    def declarations_with_uri(symbol_id)
      @mutex.synchronize { @by_symbol.fetch(symbol_id, []).dup }
    end

    # Lexical (name-only) lookup across class/module/constant declarations,
    # independent of any particular SymbolId#owner. This is the "名前ヒュー
    # リスティック" fallback from docs/03-semantic-engine.md section 6 — the
    # best available strategy before real call-site resolution exists.
    # Goes through the @by_simple_name secondary index rather than scanning
    # every distinct symbol in the workspace, which matters once Cold Index
    # (docs/design/tasks/008.5-runtime-and-index-corrections.md) has
    # populated thousands of them.
    def find_by_simple_name(name)
      @mutex.synchronize do
        results = []
        @by_simple_name.fetch(name.downcase, []).each do |symbol_id|
          next unless %i[class module constant].include?(symbol_id.kind)
          next unless simple_name(symbol_id) == name

          @by_symbol.fetch(symbol_id, []).each { |(uri, decl)| results << { uri: uri, range: decl.location } }
        end
        results
      end
    end

    # Workspace symbol search: case-insensitive substring match on the
    # symbol's own (unqualified) name, exact matches ranked first.
    def search(query, limit:)
      @mutex.synchronize do
        needle = query.to_s.downcase
        matches = []
        @by_symbol.each do |symbol_id, entries|
          next unless simple_name(symbol_id).downcase.include?(needle)

          entries.each { |(uri, decl)| matches << { symbol_id: symbol_id, uri: uri, location: decl.location } }
        end
        rank(matches, needle).first(limit)
      end
    end

    private

    # Buffer-vs-disk precedence is absolute and one-directional: a buffer
    # can always overwrite a disk-sourced entry (the user started editing,
    # or didOpen simply raced ahead of a Cold Index read already in
    # flight for the same file — either way the buffer is authoritative),
    # but a disk read can never overwrite a buffer, full stop. Only when
    # both sides share the same source does either kind of "staleness"
    # ordering apply: document_version for two buffer updates (an LSP
    # client always sends increasing versions per document), or
    # read_sequence for two disk reads (ordered by when each *started*
    # reading, not when each *finished* writing to the index — a slow
    # walk that began reading stale content before a fast, later-started
    # targeted reindex must lose to it even if the slow walk's
    # #replace_file call happens to arrive second).
    def stale?(existing, incoming)
      return false unless existing
      return true if existing.source == :buffer && incoming.source == :disk # disk never beats an open buffer
      return false if existing.source == :disk && incoming.source == :buffer # a buffer always promotes over disk

      if incoming.source == :buffer
        return false if incoming.document_version.nil? || existing.document_version.nil?

        incoming.document_version < existing.document_version
      else
        incoming.read_sequence < existing.read_sequence
      end
    end

    def remove_file_locked(uri)
      summary = @summaries.delete(uri)
      return false unless summary

      summary.declarations.each do |decl|
        entries = @by_symbol[decl.symbol_id]
        next unless entries

        entries.reject! { |(entry_uri, _decl)| entry_uri == uri }
        next unless entries.empty?

        @by_symbol.delete(decl.symbol_id)
        name_key = simple_name(decl.symbol_id).downcase
        by_name = @by_simple_name[name_key]
        by_name.delete(decl.symbol_id)
        @by_simple_name.delete(name_key) if by_name.empty?
      end
      true
    end

    def simple_name(symbol_id)
      symbol_id.name.to_s.split("::").last.to_s
    end

    def rank(matches, needle)
      matches.sort_by { |m| simple_name(m[:symbol_id]).downcase == needle ? 0 : 1 }
    end
  end
end
