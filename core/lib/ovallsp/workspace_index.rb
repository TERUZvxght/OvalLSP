# frozen_string_literal: true

require "set"
require_relative "index/symbol_id"

module Ovallsp
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
        if existing && existing.content_hash == summary.content_hash
          # Identical content is a genuine no-op ONLY when the source
          # agrees too. A disk-sourced entry whose content happens to
          # match an incoming *buffer*-sourced summary (the ordinary case
          # — most files are opened unmodified) must still be promoted to
          # `:buffer`, or the entry stays tagged `:disk` forever despite a
          # live open buffer existing for it, silently reopening exactly
          # the race #stale? below exists to close: a later disk read
          # (different content — the file changed on disk while open)
          # would see `existing.source == :disk` and fall through to
          # read_sequence ordering instead of being unconditionally
          # rejected as it must be against an open buffer
          # (docs/design/tasks/008.6-agent-and-index-hardening.md).
          # Declarations are identical either way (same content_hash), so
          # this only needs to swap the stored FileSummary object, not
          # touch @by_symbol/@by_simple_name at all.
          next promote_source_locked(summary) if existing.source == :disk && summary.source == :buffer

          next false
        end
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

    # Every Declaration currently indexed for `uri` (regardless of which
    # caller last populated it — #replace_file is the single write path
    # every source funnels through: didOpen/didChange, disk re-reads, and
    # Cold Index all end up in the same `@summaries[uri]`), or [] if
    # nothing is indexed for it. A caller that needs "what did this uri
    # declare *before* the replace I'm about to make" (Task 013's
    # MethodSummaryStore invalidation, so an edited method's stale cached
    # return type doesn't survive an edit) must call this *before*
    # #replace_file for the same uri — this deliberately doesn't track
    # that pairing itself, so there is nothing for a new caller to forget
    # to wire in the way a separate caller-maintained "previous
    # declarations" cache could be (docs/design/tasks/013-unified-semantic-query-and-lsp-integration.md
    # review: a Server-side shadow hash for this left Cold Index's
    # first-ever index of a file unable to seed invalidation for it).
    def declarations_for_uri(uri)
      @mutex.synchronize { @summaries[uri]&.declarations&.dup || [] }
    end

    def summary_for_uri(uri)
      @mutex.synchronize { @summaries[uri] }
    end

    def uris_by_source(source)
      @mutex.synchronize do
        @summaries.filter_map { |uri, summary| uri if summary.source == source }
      end
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

    # Every uri declaring the class/module whose *fully-qualified* name is
    # `qualified_name`, regardless of how it was written.
    #
    # SymbolId#owner is recorded lexically, so one class has as many
    # distinct SymbolIds as there are ways to spell it: `module Api;
    # module V1; class UsersController` (owner "::Api::V1"), `class
    # Api::V1::UsersController` (owner nil) and `module Api; class
    # V1::UsersController` (owner "::Api") are three different keys for
    # the same class. Any lookup that reconstructs an owner can only ever
    # match some of them, which is why callers that know the qualified
    # name should ask by name. `name` is always absolute-qualified, so
    # this cannot collide with a same-named class in another namespace.
    def class_declaration_uris(qualified_name)
      class_declarations(qualified_name).map { |entry| entry[:uri] }
    end

    # The same lookup, with each declaration's own range — for callers
    # that want to jump to it rather than merely name its file. One
    # implementation of the matching rule, for the reason this release
    # exists: the alternative is a second place that has to remember that
    # `owner` is lexical.
    #
    # The `::` is normalised here rather than by the caller. Indexed names
    # always carry it, so a bare argument silently matches nothing —
    # and "silently" is the problem: `Server#find_controller_uri` used to
    # prefix by hand, and a caller that forgot would have lost a whole
    # controller's ivars with no error anywhere. The lookup is the one
    # place that knows what shape its own keys are.
    # No nil guard: `qualify_owner(nil)` is nil, `simple_name_of(nil)` is
    # `""`, and nothing is indexed under `""` — so a nil name already
    # returns []. A guard here would be a line no input can reach, which
    # is the same defect as an untested one (0.1.12, round 7).
    def class_declarations(name)
      qualified_name = Index::SymbolId.qualify_owner(name)
      @mutex.synchronize do
        results = []
        @by_simple_name.fetch(simple_name_of(qualified_name).downcase, []).each do |symbol_id|
          next unless %i[class module].include?(symbol_id.kind)
          next unless symbol_id.name == qualified_name

          @by_symbol.fetch(symbol_id, []).each { |(uri, decl)| results << { uri: uri, range: decl.location } }
        end
        # Sorted, because callers take `.first` of this and insertion order
        # is *index* order: `replace_file` removes a uri's entries and then
        # appends the new ones, so editing one file of a class reopened
        # across several moved it to the back -- silently changing which
        # declaration go-to-definition answered with, and which controller
        # file supplied a view's ivars. Ordering by uri makes the answer a
        # property of the workspace rather than of what was typed in last
        # (0.1.12, round 9).
        results.sort_by { |entry| entry[:uri] }
      end
    end

    # Resolves a raw type name as written in source ("User", "::User",
    # "Admin::Manager") to the canonical, fully-qualified name of a
    # declared class/module, or nil if none is known. Real (lexical-scope-
    # aware) constant resolution is out of scope (Task 009's explicit
    # boundary) — this is the same "名前ヒューリスティック" #find_by_simple_name
    # already uses: match by unqualified simple name, then prefer whichever
    # candidate's own full name exactly matches what was written. An
    # ambiguous simple name (two same-named classes in different
    # namespaces) resolves to whichever was indexed first.
    def resolve_type_name(name)
      @mutex.synchronize { resolve_type_symbol_locked(name)&.name }
    end

    # Same resolution as #resolve_type_name, but returns the declared
    # kind (:class or :module) instead of the name — Semantic::HierarchyIndex
    # uses this to decide whether a type implicitly inherits from Object
    # (only classes do).
    def type_kind(name)
      @mutex.synchronize { resolve_type_symbol_locked(name)&.kind }
    end

    # Every SymbolId of `kind` declared directly under `owner` (e.g. every
    # instance method declared in "::User", across however many files
    # reopen it). Semantic::MethodResolver#complete uses this to enumerate
    # a type's own method names rather than checking one name at a time.
    # `owner` arrives qualified or bare depending on where the caller got
    # it: declarations are indexed qualified (`::Object`), while
    # `HierarchyIndex`'s default chain names its entries bare. Comparing
    # the two raw answered "nothing" for half the callers -- and the
    # visible consequence was a workspace reopening `class Object` with
    # `method_missing` still getting a false `unknown-method` on every
    # closed receiver.
    #
    # `SymbolId` now stores every owner qualified, so the stored side needs
    # no work; this only has to put the *argument* through the same rule
    # (0.1.11).
    def method_symbol_ids(owner, kind:)
      needle = Index::SymbolId.qualify_owner(owner)
      @mutex.synchronize { @by_symbol.keys.select { |sid| sid.owner == needle && sid.kind == kind } }
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

    # Swaps in a buffer-sourced summary whose content is byte-for-byte
    # identical to the disk-sourced one already indexed, so `source`
    # (and `document_version`, for future staleness comparisons) update
    # even though nothing about the declarations themselves changed.
    def promote_source_locked(summary)
      @summaries[summary.uri] = summary
      @generation += 1
      true
    end

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
      simple_name_of(symbol_id.name)
    end

    def simple_name_of(name)
      name.to_s.split("::").last.to_s
    end

    def resolve_type_symbol_locked(name)
      raw = name.to_s
      simple = raw.split("::").last
      candidates = @by_simple_name.fetch(simple.to_s.downcase, []).select do |sid|
        %i[class module].include?(sid.kind) && simple_name(sid) == simple
      end
      return nil if candidates.empty?

      # Only `raw` needs normalising: it is a name as written, and may be
      # bare. An indexed class/module name always carries the `::`, so
      # normalising that side too was a branch no input could reach
      # (0.1.12, round 8).
      qualified = Index::SymbolId.qualify_owner(raw)
      candidates.find { |sid| sid.name == qualified } || candidates.first
    end

    def rank(matches, needle)
      matches.sort_by { |m| simple_name(m[:symbol_id]).downcase == needle ? 0 : 1 }
    end
  end
end
