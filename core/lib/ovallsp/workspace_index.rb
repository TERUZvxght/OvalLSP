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
      # `[owner, name]` pairs a `module_function :name` named, counted the
      # same way as `@open_surface_owners` so a file being re-indexed does
      # not lose another file's. Applied at read time rather than written
      # into `@by_symbol`, because the `def` it names may be indexed
      # before or after the `module_function` that names it (`024.114`).
      @module_function_names = Hash.new(0)
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
        summary.module_function_names.each { |key| @module_function_names[key] += 1 }
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
      @mutex.synchronize do
        found = @by_symbol.fetch(symbol_id, [])
        return found.dup unless found.empty?

        # A module method this owner has only through `module_function
        # :name`, whose `def` is in another file. The declaration to show
        # is that `def`'s -- it is the same method, and go-to-definition
        # should land on it.
        return [] unless module_function_named_locked?(symbol_id)

        @by_symbol.fetch(symbol_id.with(kind: :instance_method), []).dup
      end
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
    # declarations" cache could be (docs/design/tasks/013-unified-semantic-queries-and-lsp-features.md
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

    # **The identity, not a projection of it.** `#resolve_type_name` and
    # `#type_kind` each answer with one field of the SymbolId this finds,
    # and a caller that wants the whole thing asks here instead of asking
    # twice and inventing the fields neither returns. There is no owner
    # to invent: a class written inside a `module` body is declared under
    # that module, and the `nil` a rebuilt id had to supply for it named
    # nothing the index holds -- so `#declarations_with_uri` answered
    # zero, and prepareRename, which has only declarations to go on until
    # something has rebuilt the reference index, refused the class while
    # offering the compact spelling of the same thing (`024.244`).
    #
    # `nesting` is asked first, for the reason `#nested_type_name` gives:
    # a bare name written inside a namespace means that namespace's
    # class, and `#resolve_type_symbol_locked` behind it is a
    # workspace-wide pick that cannot know that. Without it, handing back
    # a *declared* id turned an already wrong answer into a confidently
    # wrong one -- renaming one of two same-named classes in different
    # namespaces rewrote both `class` lines. Empty nesting (a use written
    # at the top level, a rooted name) skips straight to the pick,
    # exactly as before.
    def resolve_type_symbol(name, nesting: [])
      @mutex.synchronize { nested_type_symbol_locked(name, nesting) || resolve_type_symbol_locked(name) }
    end

    # The name `nesting` makes this bare name mean, or **nil when the
    # nesting decides nothing** -- which is the whole difference between
    # this and `#resolve_type_name`. A caller rewriting a name it will
    # hand downstream must not fall through to the first-candidate
    # heuristic: doing that turned `Queue.new` inside `module DEBUGGER__`
    # into `ActiveRecord::ConnectionAdapters::ConnectionPool::Queue` and
    # added five false reports over 40 gems, because the bare name it
    # replaced was the one RBS could still answer for. Measured; the fix
    # for `024.103` shipped with this distinction and not without it.
    #
    # Both readers go through `#nested_type_symbol_locked`, and it through
    # `#nesting_match`, so the lookup rule itself is in one place. (This
    # sentence named `#nesting_match` directly while this method inlined
    # the walk; the helper is the layer both readers now share.)
    # `nesting` is Ruby's `Module.nesting` at the point the name was
    # written, innermost first.
    #
    # This is not `024.47`'s rolled-back shape. That moved a *shadowing
    # test* into `#resolve_type_name`, which cannot tell a written name
    # from an inferred one and broke every bare name written from inside
    # its own namespace. This is the lookup rule itself, asked as its own
    # question by the one caller that has a nesting to give -- and 0.2.10
    # shipped a `nesting:` parameter on `#resolve_type_name` as well,
    # which no caller ever passed. An unreachable branch is a defect in
    # its own right (CLAUDE.md), and it was carrying the comment that
    # argued it was not 024.47. Removed; this is where the rule lives.
    def nested_type_name(name, nesting: [])
      @mutex.synchronize { nested_type_symbol_locked(name, nesting)&.name }
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
      @mutex.synchronize do
        declared = @by_owner_kind.fetch([needle, kind], [])
        (declared + module_function_symbol_ids_locked(needle, kind)).uniq.sort_by(&:name)
      end
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
    #
    # Reads `@by_simple_name`, like `#prefix_search` and
    # `#find_by_simple_name` above -- the third reader of the structure to
    # do so, and the last one that was not (`024.137`). Its keys already
    # *are* the downcased simple names, which is precisely the string this
    # query is asked about; walking `@by_symbol` instead meant deriving
    # one per symbol (`split("::")` and a `downcase` allocated per key) to
    # rediscover a value the index was already holding. The register entry
    # said a substring search "cannot use" this index because
    # `#find_by_simple_name` looks a key up exactly. Exact lookup is what
    # *that* method needs; the keys are equally available to scan.
    #
    # Measured on a 14,958-symbol workspace (activerecord, activesupport,
    # actionpack, actionview and activemodel: 1,039 files, 16,688
    # declaration entries, 8,259 distinct simple names), four
    # implementations in one process against one index, every answer
    # identical by digest across nine queries. The table is in `024.137`;
    # the shape of it is that a query of two characters or more falls
    # from 3.6-5.5ms to 0.7-2.1ms, and that is the whole of the gain.
    #
    # **A one-character query improves slightly (13.6ms against 11.4ms)
    # and the empty query not at all (17.9ms against 17.5ms).** The empty
    # query is what the picker sends when it opens, and it matches every
    # symbol in the workspace by definition, so nothing about *which
    # symbols match* can help it: the cost is building and ranking 16,688
    # candidates. That half of `024.137` is unfixed and the entry stays
    # open for it, with a paragraph in `KNOWN_LIMITATIONS` -- the fix
    # narrows the entry rather than closing it.
    #
    # The corpus is installed gems and deliberately excludes this
    # repository's own `core/lib`: the first attempt at this measurement
    # included it, so editing *this file* moved declaration line numbers
    # inside the corpus and the before/after answers differed for that
    # reason alone. The register's own rule about a corpus containing the
    # tree under change, arriving a third time.
    #
    # One critical section, not two. The entry proposed copying
    # `@by_symbol.keys` under the lock, filtering outside it and re-taking
    # the lock for the survivors. Measured in the same run it is slower
    # end to end than this at every one of the nine queries, and it does
    # not even hold the lock for less where it matters most: ranking
    # happens in the second critical section, so the picker's opening
    # state holds the mutex for 16.6ms of a 21.1ms call. It also opens a
    # window in which a copied key can name a symbol removed while the
    # filter ran. And the trade it is offering is not one this program can
    # take: `Server` wraps this whole request in `@index_mutation_mutex`
    # -- `server_spec.rb` has an example per read request pinning that --
    # and commits every index mutation under that same outer lock, so what
    # indexing actually waits behind is the call's total time. Shortening
    # the call is what shortens the wait; moving the inner lock is not.
    #
    # `fetch(symbol_id, [])` because that is this class's read convention,
    # stated in `#initialize` and followed by all six readers of
    # `@by_symbol` -- not a decision taken here. Its default is in fact
    # unreachable from outside: `#replace_file` writes both structures and
    # `#remove_file_locked` prunes both in one critical section, and this
    # method never leaves `@mutex`, so a bucket naming a symbol
    # `@by_symbol` has lost would be an index bug rather than a race.
    # Which also means no test can fail on it -- subscripting instead
    # leaves the whole behavioural file green. `024.137` records that as
    # an unpinned line rather than pretending otherwise.
    def search(query, limit:)
      @mutex.synchronize do
        needle = query.to_s.downcase
        matches = []
        @by_simple_name.each do |simple, symbol_ids|
          next unless simple.include?(needle)

          symbol_ids.each do |symbol_id|
            @by_symbol.fetch(symbol_id, []).each do |(uri, decl)|
              matches << { symbol_id: symbol_id, uri: uri, location: decl.location, simple: simple }
            end
          end
        end
        # `:simple` is `#rank`'s, not a caller's: the answer's shape is the
        # three keys `Server#workspace_symbol_result` reads, and stays so.
        rank(matches, needle, limit)
            .map { |m| { symbol_id: m[:symbol_id], uri: m[:uri], location: m[:location] } }
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
    # ordering apply: document_version for two updates *of one buffer*
    # (see the buffer_id refusal below -- across buffers the two
    # numberings are not comparable at all), or
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
        # **Two buffers of one uri are two documents.** Version 1 of the
        # second is not older than version 20 of the first; the two
        # numberings are not one sequence, and comparing them made a
        # reopen-without-close stop updating until the new buffer's
        # numbering passed where the old one left off. The comment above
        # asserted "an LSP client always sends increasing versions per
        # document" -- which is the premise 0.2.10's publish funnel had
        # already rejected one layer up, leaving two places comparing a
        # version across buffers and one of them fixed (`024.118`).
        return false if incoming.buffer_id != existing.buffer_id

        incoming.document_version < existing.document_version
      else
        incoming.read_sequence < existing.read_sequence
      end
    end

    def owner_kind_key(symbol_id) = [symbol_id.owner, symbol_id.kind]

    def remove_file_locked(uri)
      summary = @summaries.delete(uri)
      return false unless summary

      summary.module_function_names.each do |key|
        @module_function_names[key] -= 1
        @module_function_names.delete(key) unless @module_function_names[key].positive?
      end
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

    # The singleton SymbolIds an owner has only through a
    # `module_function :name` written somewhere. Instance methods it
    # declares *and* a `module_function` names, which is exactly Ruby's
    # rule for the by-name form.
    def module_function_symbol_ids_locked(needle, kind)
      return [] unless kind == :singleton_method

      @by_owner_kind.fetch([needle, :instance_method], []).select do |symbol_id|
        @module_function_names.key?([Index::SymbolId.bare_name(needle), symbol_id.name])
      end.map { |symbol_id| symbol_id.with(kind: :singleton_method) }
    end

    def module_function_named_locked?(symbol_id)
      return false unless symbol_id.kind == :singleton_method

      @module_function_names.key?([Index::SymbolId.bare_name(symbol_id.owner), symbol_id.name])
    end

    # The nesting rule itself, in one place, so the two callers that read
    # it -- `#nested_type_name`, which wants the name, and
    # `#resolve_type_symbol`, which wants the whole identity -- cannot
    # come to disagree about which frame wins.
    #
    # **Both guards are early-outs, not decisions**, and saying so is the
    # point, because the hunk sweep will report the line unpinned and the
    # next reader should know that is expected. `#nesting_match` builds a
    # `<frame>::<raw>` name, so a rooted `raw` produces one with a
    # doubled separator that no declaration can carry, and an empty
    # nesting gives it nothing to iterate. Asked directly, with a
    # top-level `Widget` and an `Api::Widget` both declared:
    #
    #   nesting_match(candidates, "::Widget", ["::Api"])  # => nil
    #   nesting_match(candidates, "Widget",   [])         # => nil
    #   nesting_match(candidates, "Widget",   ["::Api"])  # => ::Api::Widget
    #
    # So what these two save is the `#type_candidates_locked` scan, and
    # what they carry is the rule in the place a reader looks for it. The
    # *rule* is pinned where it is observable, by the example in
    # `reference_resolver_spec.rb` asserting that a rooted name written
    # inside a namespace still names the top-level class.
    def nested_type_symbol_locked(name, nesting)
      raw = name.to_s
      return nil if raw.start_with?("::") || nesting.empty?

      candidates, = type_candidates_locked(raw)
      nesting_match(candidates, raw, nesting)
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
      # inside its own namespace, and was rolled back (024.47). Ruby's
      # actual lookup rule is asked as its own question by
      # `#nested_type_name`, which the caller with a nesting uses.
      exact || candidates.first
    end

    # The innermost nesting frame that declares `raw`, or nil.
    def nesting_match(candidates, raw, nesting)
      Array(nesting).each do |frame|
        wanted = Index::SymbolId.qualify_owner("#{frame}::#{raw}")
        found = candidates.find { |sid| sid.name == wanted }
        return found if found
      end
      nil
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

    # One of three queries that read `@by_simple_name` -- `#prefix_search`
    # since 0.2.0 and `#search` since 0.2.16 read it too, as does
    # `remove_file_locked`, to drop a name whose last declarer is gone.
    # This said "the one place" until 0.2.16; it went stale in 0.2.0 when
    # `#prefix_search` became the second, and the change that added the
    # third is the one that found it.
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
      # bucket was decided by the scanned Hash's insertion order -- and
      # this result is *truncated*, so that changed which symbols survived
      # `limit:` after any edit. (`@by_symbol`'s, when this was written;
      # `@by_simple_name`'s since `024.137`. Which Hash is scanned is the
      # thing this key exists to stop mattering.)
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
      #
      # `m.fetch(:simple)` rather than deriving the simple name again: it
      # is the `@by_simple_name` bucket key `#search` matched on, written
      # by `#replace_file` as `simple_name(sid).downcase`, so re-deriving
      # it here computed the same rule a second time, once per match.
      #
      # It is a trade rather than a free win, and the measurement in
      # `024.137` says which way it goes. Re-deriving is *cheaper* on a
      # typed query, where the match list is short and building a fourth
      # hash entry per match costs more than the `split("::")` it saves
      # (0.4-1.7ms against 0.7-2.1ms). It is dearer where the match list
      # is the whole workspace: the empty query the picker opens with
      # makes all 16,688 declarations a match, and re-deriving answers it
      # in 20.1ms against 17.5ms. The carry is taken because the state it
      # helps is the one that costs the most in absolute terms, and
      # because that state is already the one `024.137` cannot fix.
      #
      # `fetch`, not `[]`: a match assembled without the key would
      # silently rank as inexact -- an ordering defect, not an error --
      # and this is the only caller. Nothing behavioural can hold that
      # choice, so `spec/meta/workspace_index_cost_spec.rb` holds it as a
      # source-text decision, the way this file's other cost decisions
      # are held.
      matches.min_by(limit) do |m|
        [m.fetch(:simple) == needle ? 0 : 1,
         m[:symbol_id].name.to_s, m[:uri],
         m[:location][:start][:line], m[:location][:start][:character],
         m[:symbol_id].kind.to_s, m[:symbol_id].owner.to_s]
      end
    end
  end
end
