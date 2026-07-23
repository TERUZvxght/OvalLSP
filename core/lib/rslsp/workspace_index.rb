# frozen_string_literal: true

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
      @by_symbol = Hash.new { |h, k| h[k] = [] }
      @generation = 0
    end

    def generation
      @mutex.synchronize { @generation }
    end

    # Adds or updates one file's contribution to the index. Returns false
    # (a no-op) when the content hash is unchanged, or when `summary` is
    # older than what's already indexed for this uri — a nil
    # `document_version` on either side skips the ordering check entirely,
    # since disk-sourced summaries (no LSP version) and buffer-sourced
    # summaries (LSP version) are different channels that aren't mutually
    # comparable.
    def replace_file(summary)
      @mutex.synchronize do
        existing = @summaries[summary.uri]
        next false if existing && existing.content_hash == summary.content_hash
        next false if stale?(existing, summary)

        remove_file_locked(summary.uri)
        @summaries[summary.uri] = summary
        summary.declarations.each { |decl| @by_symbol[decl.symbol_id] << [summary.uri, decl] }
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
      @mutex.synchronize { @by_symbol[symbol_id].map { |(_uri, decl)| decl } }
    end

    # Same as #declarations, but paired with the contributing uri. Declaration
    # itself carries no uri (Task 002's contract), and callers building an
    # LSP Location need one, so this is an intentional, documented addition
    # to the task's required interface rather than a change to it.
    def declarations_with_uri(symbol_id)
      @mutex.synchronize { @by_symbol[symbol_id].dup }
    end

    # Lexical (name-only) lookup across class/module/constant declarations,
    # independent of any particular SymbolId#owner. This is the "名前ヒュー
    # リスティック" fallback from docs/03-semantic-engine.md section 6 — the
    # best available strategy before real call-site resolution exists.
    def find_by_simple_name(name)
      @mutex.synchronize do
        results = []
        @by_symbol.each do |symbol_id, entries|
          next unless %i[class module constant].include?(symbol_id.kind)
          next unless simple_name(symbol_id) == name

          entries.each { |(uri, decl)| results << { uri: uri, range: decl.location } }
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

    def stale?(existing, incoming)
      return false unless existing
      return false if incoming.document_version.nil? || existing.document_version.nil?

      incoming.document_version < existing.document_version
    end

    def remove_file_locked(uri)
      summary = @summaries.delete(uri)
      return false unless summary

      summary.declarations.each do |decl|
        entries = @by_symbol[decl.symbol_id]
        entries.reject! { |(entry_uri, _decl)| entry_uri == uri }
        @by_symbol.delete(decl.symbol_id) if entries.empty?
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
