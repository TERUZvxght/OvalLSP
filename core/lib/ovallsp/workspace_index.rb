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
      # Keyed on [owner, kind], because `#method_symbol_ids` is asked once
      # per ancestor and used to scan every key in `@by_symbol` to answer.
      # 0.1.14 grew the singleton chain from one entry to six, so a single
      # `Widget.` completion went from one full scan of the symbol table
      # to six: 31ms -> 200ms on a 126k-symbol workspace, on the path a
      # keystroke runs.
      @by_owner_kind = Hash.new { |h, k| h[k] = [] }
      # [owner bare name, :instance | :singleton] => how many indexed
      # files leave that surface open (Index::FileSummary#open_surface_owners).
      # A count rather than a set, because two files can each run an
      # unreadable macro in the same reopened class and removing one of
      # them must not close the surface the other still opens.
      @open_surface_owners = Hash.new(0)
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
        touched = []
        summary.declarations.each do |decl|
          fresh = !@by_symbol.key?(decl.symbol_id)
          (@by_symbol[decl.symbol_id] ||= []) << [summary.uri, decl]
          @by_simple_name[simple_name(decl.symbol_id).downcase] << decl.symbol_id
          @by_owner_kind[owner_kind_key(decl.symbol_id)] << decl.symbol_id if fresh
          touched << decl.symbol_id
        end
        # The order lives here, not in the readers. `remove_file_locked`
        # deletes this uri's entries and the loop above appends the new
        # ones, so without this a re-index moves a file's declarations to
        # the back of every list they are in -- and the readers take
        # `.first` of such a list, or truncate it. Typing one character in
        # an unrelated file then changed where go-to-definition landed and
        # which symbols survived `workspace/symbol`'s limit.
        #
        # Sorted once per touched symbol per file rather than inserted in
        # place. Cost is quadratic in a symbol's *fan-out* -- Cold Index
        # re-sorts a list of length i on the i-th file that joins it -- and
        # the fan-out that matters is a reopened namespace module, not a
        # class: 78 of this project's own 79 `lib` files declare
        # `module Ovallsp`, so that one list reaches 78. Measured on real
        # trees, `replace_file` totals: `core/lib` 79 files 1.4 -> 3.5ms,
        # `activerecord/lib` 397 files 9.5 -> 32.5ms. Negligible against
        # parsing. It stops being negligible only at a fan-out no real tree
        # has shown -- a synthetic 4,000-file single-namespace workspace
        # measures 80ms -> 3.0s -- which is the shape to re-measure if this
        # ever feels slow (024.15).
        summary.open_surface_owners.each { |key| @open_surface_owners[key] += 1 }
        touched.uniq.each { |symbol_id| @by_symbol[symbol_id].sort_by!(&method(:entry_order)) }
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
        matching = ordered_symbol_ids(name, matching: lambda { |sid|
          %i[class module constant].include?(sid.kind) && simple_name(sid) == name
        })
        matching.each do |symbol_id|
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
        matching = ordered_symbol_ids(simple_name_of(qualified_name), matching: lambda { |sid|
          %i[class module].include?(sid.kind) && sid.name == qualified_name
        })
        matching.each do |symbol_id|
          @by_symbol.fetch(symbol_id, []).each { |(uri, decl)| results << { uri: uri, range: decl.location } }
        end
        results
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
    # namespaces) resolves to the alphabetically first qualified name --
    # arbitrary, but a property of the workspace rather than of which file
    # was edited last, which is what it was until 0.1.13 (024.15).
    def resolve_type_name(name)
      @mutex.synchronize { resolve_type_symbol_locked(name)&.name }
    end

    # Whether a *bare* name is claimed by more than one declared type, so
    # that resolving it is a pick rather than a lookup.
    #
    # `#resolve_type_name` answers anyway, and should: for completion and
    # go-to-definition a plausible class beats none, and 024.15 is why the
    # pick is at least deterministic. But an ancestor edge is different --
    # putting the wrong module in a chain does not merely answer weakly,
    # it makes the chain *look complete while being wrong*, and
    # `closed_nominal?` then reports the class's own methods missing.
    # Measured: 12 of 54 false findings over real gem source, where
    # `Helpers`, `Base`, `Error` and `Node` are claimed many times over.
    #
    # A qualified name is never ambiguous in this sense: the caller wrote
    # the namespace, and `#substitution?` is what covers a written
    # namespace resolving somewhere else.
    def ambiguous_type_name?(name)
      bare = Index::SymbolId.bare_name(name.to_s)
      return false if bare.include?("::")

      @mutex.synchronize do
        candidates, = type_candidates_locked(name)
        candidates.map(&:name).uniq.length > 1
      end
    end

    # Whether anything indexed leaves this owner's instance (or, with
    # `singleton:`, its class-level) method surface open --
    # a class body running a macro the parser cannot read, so the methods
    # it defines are not in the index and never will be.
    #
    # Asked by the undefined-method check, which may assert absence only
    # where the surface is enumerable. Answers about the owner named, not
    # its ancestors; the caller walks the chain because that is where the
    # chain is known.
    def open_surface?(owner, singleton: false)
      return false if owner.nil?

      key = [Index::SymbolId.bare_name(owner.to_s), singleton ? :singleton : :instance]
      @mutex.synchronize { @open_surface_owners[key].positive? }
    end

    # Whether `resolve_type_name` answered about a *different name* than
    # the one it was asked about. It always answers when the last segment
    # matches something, and should -- for completion and go-to-definition
    # a plausible class beats none.
    #
    # A diagnostic is the other case. Reporting "X has no method named y"
    # about a class the engine substituted is an assertion about a
    # receiver it has not identified.
    #
    # Two ways the substitution happens, and the first version of this
    # guard only caught the second:
    #
    # - **the name carries a namespace and no declared type has it.**
    #   `Ripper::Lexer` in prism's `lex_compat.rb` resolved to
    #   `Prism::Translation::Parser::Lexer` and `ripper.lex` was reported
    #   unknown. Counting candidates does not see this: there is only one
    #   `Lexer`, and it is the wrong one. What gives it away is that the
    #   caller wrote a namespace and got a class from a different one.
    # - **the name is bare and several types share it.** Then the pick is
    #   between them, and there is nothing to prefer. This repository grew
    #   a second `Collector` in 0.2.0 and a method the parser records was
    #   reported unknown.
    #
    # A bare name matching exactly one type is *not* a guess: that is the
    # lookup working, and it is how every reference from inside a
    # namespace resolves -- `LocalInferencer` hands over the constant as
    # written, without the lexical qualification `ReceiverResolution`
    # applies to an explicit receiver.
    #
    # 024.19 is this, reaching the argument-type check.
    def guessed_type_name?(name)
      @mutex.synchronize do
        candidates, qualified = type_candidates_locked(name)
        # Nothing matched, so nothing was substituted: `resolve_type_name`
        # answers nil and every caller keeps the name as written. Calling
        # that a guess silenced 2,517 `unknown-method` reports over the
        # standard library and five Rails gems -- every class whose
        # superclass lives outside the corpus stopped being closed, and
        # the check went off for the whole class. Measured, not reasoned:
        # the corpus run is what caught it.
        next false if candidates.empty?
        next false if candidates.any? { |sid| sid.name == qualified }
        next true if Index::SymbolId.bare_name(name.to_s).include?("::")

        candidates.size > 1
      end
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
    # Sorted on read, not stored sorted: the bucket is small (one class's
    # methods) and an unordered collection read by `.first`/a truncation
    # is what 024.15 was spent on.
    def method_symbol_ids(owner, kind:)
      needle = Index::SymbolId.qualify_owner(owner)
      @mutex.synchronize { @by_owner_kind.fetch([needle, kind], []).sort_by(&:name) }
    end

    # Completion's question, which is not `search`'s. A completion prefix
    # means the *start* of the simple name and only certain kinds are
    # offerable, and both predicates have to run before the truncation:
    # filtering `search`'s already-truncated answer filters what is left
    # after `limit` substring matches were kept, and on any workspace with
    # more than `limit` of those, every prefix match can already be gone.
    # Measured before this existed: 250 classes named `Aaa001Artish`... and
    # one named `Artzzz`, typing `art` returned nothing at all.
    #
    # Distinct SymbolIds rather than declarations, because `limit:` should
    # count names a user could pick, and one class reopened in forty files
    # is one name.
    #
    # Reads `@by_simple_name`, whose keys are already the downcased simple
    # names this asks about, rather than scanning `@by_symbol` and
    # deriving one per symbol -- and takes `min_by(limit)` rather than
    # sorting everything to keep the first `limit`. Both are the rules
    # `spec/meta/workspace_index_cost_spec.rb` already states for
    # `#method_symbol_ids` and `#rank`; this method was written after
    # them and carried neither. Measured on a 21.7k-symbol workspace,
    # same prefixes, byte-identical answers: 4.8ms per keystroke against
    # 3.0ms for `wi`/`wid`/`widg`, 2.6ms against 1.4ms for a prefix that
    # narrows. This runs on the request path, per keystroke, holding the
    # lock every hover and every diagnostic needs.
    def prefix_search(prefix, limit:, kinds:)
      needle = prefix.to_s.downcase
      @mutex.synchronize do
        matches = []
        @by_simple_name.each do |name, symbol_ids|
          next unless name.start_with?(needle)

          symbol_ids.each { |sid| matches << sid if kinds.include?(sid.kind) }
        end
        matches.min_by(limit) do |sid|
          [simple_name(sid).downcase == needle ? 0 : 1, sid.name.to_s, sid.kind.to_s, sid.owner.to_s]
        end
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
        rank(matches, needle, limit)
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

    def owner_kind_key(symbol_id) = [symbol_id.owner, symbol_id.kind]

    def remove_file_locked(uri)
      summary = @summaries.delete(uri)
      return false unless summary

      summary.open_surface_owners.each do |key|
        @open_surface_owners[key] -= 1
        @open_surface_owners.delete(key) unless @open_surface_owners[key].positive?
      end
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
        owner_key = owner_kind_key(decl.symbol_id)
        by_owner = @by_owner_kind[owner_key]
        by_owner.delete(decl.symbol_id)
        @by_owner_kind.delete(owner_key) if by_owner.empty?
      end
      true
    end

    def simple_name(symbol_id)
      simple_name_of(symbol_id.name)
    end

    def simple_name_of(name)
      name.to_s.split("::").last.to_s
    end

    # Every declared class or module whose last segment is this name's
    # last segment, in a stable order, paired with the name as written
    # normalised for comparison against them.
    #
    # One place, because `#resolve_type_symbol_locked` picks from this
    # list and `#guessed_type_name?` reports whether the pick was a
    # substitution. Computed twice, the two could disagree about which
    # candidates exist, and the flag would then describe a different pick
    # than the one returned.
    #
    # Only the written name needs normalising: an indexed class/module
    # name always carries the `::`, so normalising that side too was a
    # branch no input could reach (0.1.12, round 8).
    def type_candidates_locked(name)
      raw = name.to_s
      simple = raw.split("::").last
      candidates = ordered_symbol_ids(simple, matching: lambda { |sid|
        %i[class module].include?(sid.kind) && simple_name(sid) == simple
      })
      [candidates, Index::SymbolId.qualify_owner(raw)]
    end

    def resolve_type_symbol_locked(name)
      candidates, qualified = type_candidates_locked(name)
      return nil if candidates.empty?

      raw = name.to_s
      exact = candidates.find { |sid| sid.name == qualified }
      # A leading `::` is not decoration -- it is the whole meaning of the
      # reference, and Ruby gives it exactly one possible referent. The
      # last-segment heuristic below is right for a name the author wrote
      # bare and wrong for one they rooted: `::JSON` inside i18n resolved
      # to that gem's own `I18n::Backend::KeyValue::JSON`, and the
      # undefined-method check then reported `::JSON.parse` missing.
      # Nil is the correct answer when the workspace has no top-level
      # constant of that name, because RBS holds the one that exists.
      return exact if raw.start_with?("::")

      # A written namespace is a constraint too, just a weaker one. It is
      # not an absolute path -- `Inner::Klass` from inside `module Outer`
      # legitimately means `Outer::Inner::Klass` -- so the match is a
      # suffix on segment boundaries rather than equality. That is enough
      # to keep `File::Stat` from resolving to a workspace `Stat` in some
      # unrelated namespace, which is what made completion after
      # `File.stat(path).` offer that class's members while hover and the
      # diagnostics already said `File::Stat` (024.78).
      return exact || candidates.find { |sid| namespace_suffix?(sid.name, raw) } if raw.include?("::")

      # `.first` is safe here because `candidates` came from
      # `ordered_symbol_ids`, not from the Set directly. Until 0.1.13 it
      # was index order, so an ambiguous bare name resolved to a different
      # class whenever either file was re-indexed (024.15).
      #
      # Bare names keep the heuristic deliberately: 0.2.1 applied a
      # shadowing rule to them here and broke every bare name written from
      # inside its own namespace, and was rolled back (024.47).
      exact || candidates.first
    end

    # Whether `candidate` (always fully qualified, leading `::`) names the
    # same constant path `written` does, allowing for an outer namespace
    # the author did not repeat. Compared segment-wise, so `::MyStat` is
    # not a match for `Stat`.
    #
    # `written` needs no `bare_name`: a rooted name returned above before
    # reaching here, so what arrives is always unrooted. A review round
    # found the call reverted with the suite still green, which is what
    # dead code looks like from the outside.
    def namespace_suffix?(candidate, written)
      candidate.to_s.end_with?("::#{written}")
    end

    # One collection is deliberately left in insertion order, and a
    # re-index does move it: `#uris_by_source` reads `@summaries`, whose
    # entry `remove_file_locked` deletes and `replace_file` re-inserts;
    # its one caller sweeps deleted files and does not care in what order.
    # "The order lives in the storage" is a claim about the collections
    # whose order a caller can observe.
    #
    # `#method_symbol_ids` was the second one and is no longer: it reads a
    # `[owner, kind]` bucket and sorts it on the way out (see there).
    #
    # `[uri, line, character]`. Uri first because that is what a caller
    # taking `.first` is choosing between; source position breaks the tie
    # a class reopened twice in one file creates, which `sort_by` alone
    # cannot -- it is not a stable sort and scrambles equal keys from
    # eight entries up.
    def entry_order(entry)
      uri, decl = entry
      [uri, decl.location[:start][:line], decl.location[:start][:character]]
    end

    # The one place a *query* reads `@by_simple_name` -- `remove_file_locked`
    # reads it too, to drop a name whose last declarer is gone.
    # It is a Set, so its order is
    # insertion order -- which moves on re-index for the same reason the
    # entry lists did. Ordered by qualified name: a bare name that matches
    # several classes resolves to the same one whichever file was edited
    # last, and that choice drives the ancestry chain, the unknown-method
    # check, find-references and rename (024.15).
    # A total key, not just the name: one class has as many SymbolIds as
    # there are ways to spell it (`class Api::Widget` has owner nil,
    # `module Api; class Widget` has owner "::Api"), and those share a
    # name. Leaving them tied put the outer walk back on Set insertion
    # order, which is the thing being fixed.
    #
    # The caller's filter is applied *before* the sort, not after, because
    # a bucket is keyed on the downcased simple name and so mixes kinds: a
    # workspace where 1200 service objects each define `call` puts 1200
    # method SymbolIds in the bucket `resolve_type_name("Call")` reads.
    # Timing `resolve_type_name("Call")` on that workspace, sorting the
    # whole bucket to then keep one element measured 3.7ms per call
    # against 51us for the filtered sort (300 objects: 878us against
    # 20us). An independent re-measurement of the bucket operation alone
    # got 1.25ms against 40us -- same direction, same order of magnitude,
    # a third of the absolute. What the two agree on is the ratio, and
    # this is a path `Diagnostics::Engine` runs per constant candidate and
    # `HierarchyIndex` per ancestry lookup. Filtering commutes
    # with sorting here -- the key reads one element -- so the order is
    # identical either way.
    #
    # `matching:` is a required keyword rather than a block so that
    # omitting it is an `ArgumentError` from Ruby. A block would be `nil`
    # when absent, and `select(&nil)` returns an enumerator of everything
    # -- silently unfiltered -- so guarding it would have meant an `if`
    # that all three call sites make unreachable, which this file already
    # calls the same defect as an untested line (0.1.12, round 7).
    def ordered_symbol_ids(simple, matching:)
      @by_simple_name.fetch(simple.to_s.downcase, [])
                     .select(&matching)
                     .sort_by { |sid| [sid.name.to_s, sid.kind.to_s, sid.owner.to_s] }
    end

    def rank(matches, needle, limit)
      # The exact-match bucket was the whole key, so everything inside a
      # bucket was decided by `@by_symbol`'s insertion order -- and this
      # result is *truncated*, so that changed which symbols survived
      # `limit:` after any edit.
      #
      # The tail has to be *total*, not merely longer. A first attempt
      # stopped at `[name, uri, line]` and still scrambled: `sort_by` is
      # not stable from eight tied elements up, and ties survive that key
      # in two shapes that both occur. One class declared several times on
      # one line of one file ties on all three -- `search` then returned
      # the columns in a different order than `class_declarations` did,
      # one method away. And every declaration a plugin registers shares
      # its `plugin://` uri and a frozen line-0/char-0 location
      # (`Server#apply_plugin_context`), so a plugin generating one method
      # name across ten models ties on all of them; which three survived
      # `limit:` depended on registration order.
      #
      # `min_by(limit)`, not `sort_by { }.first(limit)`. The key is total,
      # so the two answer identically for the Integer limit its one
      # caller passes -- but the picker opens with an
      # empty query, so every declaration in the workspace matches, on a
      # keystroke path that holds this mutex. Ranking the 32,000 matches
      # an empty query returns for 2,000 files that each declare a class
      # and fifteen methods measures 68ms sorting all of them on this key,
      # 17ms taking the hundred asked for, and 10ms for the one-element
      # key this replaced. So the key does cost about 7ms more
      # than it used to, not nothing: `min_by` recovers four fifths of
      # what the wider key added, and the rest buys an answer whose
      # membership does not depend on which file was saved last.
      #
      # (An earlier note here claimed parity, from an end-to-end
      # measurement of `search` -- where building the match list dominates
      # and hid the difference. Time the ranking, not the query.)
      #
      # `[kind, owner]` last is what makes it total: two declarations that
      # agree on name, uri and position are the same symbol or differ in
      # identity, and nothing else distinguishes them (024.15). "Nothing
      # else" assumes `SymbolId#discriminator` stays nil, which every
      # construction in this tree does -- but `Server#plugin_declaration`
      # copies a plugin's own SymbolId verbatim, so a plugin that starts
      # populating it would put an index-order tie back.
      matches.min_by(limit) do |m|
        [simple_name(m[:symbol_id]).downcase == needle ? 0 : 1,
         m[:symbol_id].name.to_s, m[:uri],
         m[:location][:start][:line], m[:location][:start][:character],
         m[:symbol_id].kind.to_s, m[:symbol_id].owner.to_s]
      end
    end
  end
end
