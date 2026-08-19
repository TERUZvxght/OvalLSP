# frozen_string_literal: true

require "digest"
require "fileutils"

module Ovallsp
  module Cache
    # Persists one FileSummary per on-disk file, under
    # `<cache_root>/<workspace_digest>/<sha256(path)>.cache` -- never a
    # source of truth on its own ("cacheをsource of truthにすること" is
    # explicitly out of scope): every read is paired with the live file's
    # own current content hash by the caller (ColdIndexer).
    #
    # That pairing used to be described here as making a stale entry cost
    # "a wasted re-parse, never an incorrect result", and that was wrong.
    # A content hash answers whether the *file* changed; it cannot answer
    # whether the code that produced the summary did. 0.2.1 moved the
    # position a call site records its receiver at, and every file already
    # in an upgrading user's cache kept answering with the old one --
    # unchanged bytes, unchanged Ruby, unchanged Prism. What makes the
    # claim true is the *key*: `Cache::Key` carries `Ovallsp::VERSION`, so
    # a build never reads another build's summaries at all.
    #
    # Every failure mode here -- an unwritable cache directory, a
    # corrupted/truncated cache file, a `Marshal.load` of data from an
    # incompatible format -- degrades to "this entry doesn't exist",
    # logged nowhere (this is a pure performance optimization; a cache
    # miss is always correct, just slower), never raised. "corrupt/stale
    # cacheでCoreが落ちない" is enforced structurally: nothing calling
    # #load ever needs its own rescue.
    #
    # #load's `Marshal.load` is an accepted, deliberately-not-hardened
    # trust boundary, flagged by an independent review of Task 022: the
    # `is_a?(Index::FileSummary)` check after it only guards what Core
    # *does* with a malformed entry, not the deserialization itself
    # (Marshal can already run arbitrary code while reconstructing a
    # crafted payload, before that check ever runs). Not fixed in this
    # pass because the cache directory lives under this OS user's own
    # `$XDG_CACHE_HOME`/`~/.cache` (see Server#build_cache_store), never
    # inside the workspace/repo -- planting a hostile entry there already
    # requires the same local file-write access that would let an
    # attacker run arbitrary code directly, so hardening this
    # deserialization step wouldn't close a real privilege boundary, only
    # add defense-in-depth. Worth revisiting if this cache root is ever
    # moved somewhere a lower-privilege or remote actor could write to.
    class Store
      # A soft LRU-ish bound ("memory bounds/LRU"): pruned opportunistically
      # on #save rather than tracked precisely, since exact LRU ordering
      # isn't worth the bookkeeping cost for what's ultimately just a
      # warm-start optimization -- filesystem mtime (already free, no
      # extra state to maintain) is close enough. A 500k-LOC app is
      # comfortably tens of thousands of files, not entries in the
      # hundreds of thousands, so this default has real headroom.
      DEFAULT_MAX_ENTRIES = 20_000

      # How many generation directories to keep for *this workspace*.
      # A generation is abandoned, never migrated, whenever anything in
      # `Cache::Key` changes -- a Ruby upgrade, a `bundle install`, an RBS
      # change, an OvalLSP release -- and until 0.2.1 nothing ever removed
      # one. `DEFAULT_MAX_ENTRIES` bounds the entries *inside* a
      # directory and knows nothing about its siblings, so the root grew
      # for as long as the extension was installed: 28,643 directories and
      # 2.8 GB on one developer machine.
      #
      # Eight is generous for the shapes that actually recur -- two Ruby
      # versions, a `bundle install` or two -- and small enough that the
      # abandoned ones do not outlive their usefulness by months.
      DEFAULT_MAX_GENERATIONS = 8

      # Names the file that says which workspace a scope directory is for.
      # Its presence is also what tells a scope directory apart from a
      # pre-0.2.1 *generation* directory, which sat at the same level.
      WORKSPACE_MARKER = ".workspace"

      # Creates the scope directory if it is not there yet, because this
      # now runs *before* the generation directory is made and there would
      # otherwise be nothing to write into on a first run.
      #
      # Marking first *narrows* the window in which a scope exists with no
      # marker and another process's sweep reads it as a pre-0.2.1 flat
      # generation -- it does not close it, since `mkdir_p` and
      # `File.write` are two syscalls. `UNMARKED_SCOPE_GRACE` is what
      # closes it.
      def self.mark_workspace(scope_dir, workspace_path)
        FileUtils.mkdir_p(scope_dir, mode: 0o700)
        tighten(scope_dir)
        marker = File.join(scope_dir, WORKSPACE_MARKER)
        # The marker records an absolute path from this machine, so it is
        # owner-only for the same reason the entries are.
        File.write(marker, "#{workspace_path}\n")
        tighten(marker, 0o600)
      rescue StandardError
        nil
      end

      # Removes what this machine will never read again, and nothing else.
      #
      # The layout is `<root>/<workspace>/<generation>` for exactly this
      # method's sake. It was flat until 0.2.1, and `Cache::Key` folds the
      # workspace into the same digest as Ruby, Prism, `Gemfile.lock` and
      # the OvalLSP version -- so every *project* was a sibling of every
      # abandoned generation, indistinguishable from one. Keeping the
      # eight most recently written siblings therefore evicted the ninth
      # project's warm cache, possibly a project open in another window,
      # since a directory's mtime advances when an entry is written and
      # not when one is read.
      #
      # Three things are removed, and each is a fact rather than a guess:
      #
      # - generations of *this* workspace beyond `keep`, oldest first;
      # - a workspace whose own directory no longer exists on disk;
      # - a pre-0.2.1 flat generation, which has no marker and which this
      #   build could not read even if it tried, because the version is in
      #   the key.
      #
      # Every failure is swallowed, for the same reason every other
      # failure in this class is: a cache that cannot be tidied is still a
      # correct cache, and a Core that will not start because of one is
      # not. That is also why nothing here may decide *what* to delete on
      # its own: an error that would have announced a wrong target is
      # discarded on the way out, so the target has to be right by
      # construction. #remove_within is where that is enforced, and what
      # it cost to learn.
      #
      # `prune_generations_of` is aimed by `File.dirname(current)`, which
      # is only a directory of this cache's while `current` is one of its
      # generations. It is passed `root` for that reason rather than
      # trusting its caller's arithmetic.
      def self.prune_generations(cache_root:, current:, keep: DEFAULT_MAX_GENERATIONS)
        root = File.expand_path(cache_root)
        current = File.expand_path(current)

        prune_workspaces(root, current)
        prune_generations_of(root, File.dirname(current), current, keep)
      rescue StandardError
        nil
      end

      def self.prune_generations_of(root, scope_dir, current, keep)
        generations = children_of(scope_dir).select { |path| File.directory?(path) }
        return if generations.length <= keep

        # `File.mtime` rather than `seconds_since_write` would raise here
        # when a generation is removed between `children_of` and the sort
        # -- another window's sweep, or `Re-index Workspace` re-entering
        # this one -- and that reaches `prune_generations`' single outer
        # rescue and abandons the removals. Round 38: the argument for
        # `prune_workspaces`' per-entry rescue applies to this half of the
        # same method, and this release is what makes the race ordinary by
        # moving the sweep to a background thread.
        #
        # Sorting an unreadable entry to the *oldest* end is the safe
        # direction: it is a candidate for removal, and `remove_within`
        # then declines a path that is already gone.
        generations.sort_by { |path| -age_for_sort(path) }
                   .reject { |path| File.expand_path(path) == current }
                   .drop(keep - 1)
                   .each { |path| remove_within(root, path) }
      end

      def self.age_for_sort(path)
        File.mtime(path).to_f
      rescue StandardError
        0.0
      end

      def self.prune_workspaces(cache_root, current)
        current_scope = File.dirname(current)
        children_of(cache_root).each do |path|
          next unless File.directory?(path)

          # Every scope, including the one being opened and the ones this
          # sweep decides to keep. `ensure_directory` only tightens the
          # scope currently in use, so before 0.2.5's modes reach a
          # machine's *other* projects they would have to each be opened
          # once -- ten projects, ten launches, and until then their
          # method bodies stay world-readable. This walk is the one place
          # that sees all of them, and it already runs on every launch.
          tighten_tree(path)

          next if File.expand_path(path) == current_scope

          marker = File.join(path, WORKSPACE_MARKER)
          # No marker: a pre-0.2.1 generation, unreadable by this build --
          # *or* a scope another process created moments ago and has not
          # marked yet. `.mark_workspace` is `mkdir_p` then `File.write`,
          # two syscalls, and reordering it ahead of the generation
          # directory narrowed that window rather than closing it, which
          # the comment there claimed. Removing the other window's scope
          # costs it the whole session's cache and a cold index on the
          # next launch.
          #
          # A pre-0.2.1 generation is by definition old -- nothing has
          # written one since 0.2.1 shipped -- so the same grace that
          # protects an absent workspace tells the two apart with no new
          # state and no lock.
          if !File.file?(marker)
            next if seconds_since_write(path) < UNMARKED_SCOPE_GRACE

            next remove_within(cache_root, path)
          end

          # A missing directory is not proof the project is gone: an
          # unmounted volume and a network share that is briefly away both
          # look exactly like a deleted one, and this method's own comment
          # calls every removal it makes "a fact rather than a guess".
          # Held for a grace period instead, so a project only loses its
          # warm cache after being unreachable for longer than any mount
          # is.
          workspace = File.read(marker).strip
          next if workspace.empty? || File.directory?(workspace)
          # The *marker's* mtime, not the scope directory's. A directory's
          # mtime advances when an entry is created or removed inside it,
          # which for a scope directory happens only when a generation is
          # minted -- a Ruby upgrade, a `bundle install`, a release. That
          # is "how long since the cache key changed", and the question
          # here is "how long since anyone opened this project". The
          # marker is rewritten by `.mark_workspace` on every launch that
          # opens this workspace, so its mtime answers the second one.
          next if seconds_since_write(marker) < ABSENT_WORKSPACE_GRACE

          # These two #remove_within calls cannot currently refuse
          # anything: `path` comes from `children_of(cache_root)`, so it is
          # always `cache_root/<name>` and always inside. Reverse-applying
          # either one therefore leaves the whole suite green, and no
          # fixture can pin them -- which by this repository's own rule
          # would make them defects.
          #
          # They are kept, and the rule is answered a level up:
          # `spec/meta/cache_removal_containment_spec.rb` pins that this
          # class removes a directory in exactly one place. That is the
          # property worth holding. What it buys is that the day this loop
          # is changed to enumerate something other than the root's own
          # children -- which is precisely how the sweep escaped last time
          # -- the containment is already here rather than needing to be
          # remembered.
          remove_within(cache_root, path)
        rescue StandardError
          # Per entry, not per sweep. `.prune_generations`' single outer
          # rescue meant anything raised while walking *another
          # workspace's* directory abandoned the rest of the walk --
          # including `prune_generations_of`, which prunes the workspace
          # being opened. One unreadable, half-removed or concurrently
          # removed sibling therefore switched cache tidying off
          # permanently, on exactly the machines the feature exists for.
          #
          # The asymmetry was already visible here: `seconds_since_write`
          # rescues per call while the loop around it did not.
          next
        end
      end

      # Thirty days: long enough that no mount, no external disk and no
      # laptop left closed over a holiday loses a warm cache, short enough
      # that a genuinely deleted project does not keep one for ever.
      ABSENT_WORKSPACE_GRACE = 30 * 24 * 60 * 60

      # An hour: longer than any window between another process's
      # `mkdir_p` and its `File.write` by many orders of magnitude, and
      # short enough that a genuine pre-0.2.1 generation is reclaimed on
      # the first launch after this build has been installed for an hour.
      UNMARKED_SCOPE_GRACE = 60 * 60

      # Wall clock, deliberately. A monotonic clock does not survive the
      # reboot this measures across; the cost is that changing the system
      # clock changes the answer, which is the lesser problem for a
      # thirty-day window.
      def self.seconds_since_write(path)
        Time.now - File.mtime(path)
      rescue StandardError
        0
      end

      # Best-effort: a cache on a filesystem that cannot represent these
      # modes (a mounted share, a Windows volume) is still a working
      # cache, and refusing to run there would trade a real feature for a
      # protection that filesystem cannot offer anyway.
      def self.tighten(path, mode = 0o700)
        File.chmod(mode, path)
      rescue StandardError
        nil
      end

      # Directories to 0700 and files to 0600, across one scope. Bounded
      # by the scope rather than walking the whole root, so the cost is a
      # handful of chmods per launch and not a full tree walk; and
      # best-effort throughout, because a cache on a filesystem that
      # cannot represent these modes is still a working cache.
      def self.tighten_tree(scope_dir)
        tighten(scope_dir)
        Dir.glob(File.join(scope_dir, "**", "*"), File::FNM_DOTMATCH).each do |entry|
          next if entry.end_with?("/.", "/..")

          tighten(entry, File.directory?(entry) ? 0o700 : 0o600)
        end
      rescue StandardError
        nil
      end

      def tighten(path, mode = 0o700) = self.class.tighten(path, mode)

      # The one place this class removes a directory, so that containment
      # is a property of *removal* rather than of each caller's arithmetic.
      #
      # Until 0.2.2 each call site called `FileUtils.remove_entry` directly
      # and the only thing keeping the sweep inside the cache was that
      # every caller happened to hand it a path from inside. One did not:
      # a spec called `.prune_generations(cache_root: "/nonexistent-cache-root",
      # current: "/x")` to check that an unreadable root does not raise.
      # `prune_workspaces` returned immediately, as intended -- and then
      # `prune_generations_of(File.dirname("/x") = "/", ...)` enumerated
      # the machine's root directory, found more entries than `keep`, and
      # removed all but the most recently modified: `/Applications` first,
      # `/Users` next had `remove_entry` not raised on a protected path
      # partway through. #prune_generations swallows every error, so the
      # example asserting `.not_to raise_error` passed on every run while
      # doing it -- for a week, on the maintainer's own machine, until an
      # Endpoint Security trace named `rspec` as the process unlinking
      # `/Applications/*.app`.
      #
      # An entry-point guard alone would have been the symptom's fix: it
      # would stop that one spec and leave the next caller free to compute
      # a target some other way. Checking here means no call site can.
      #
      # One was written as well, rejecting a `current` from outside the
      # root in #prune_generations, and then removed: with containment
      # already enforced here it changed nothing a spec could observe, and
      # an unpinned line is a defect in this repository whichever direction
      # it errs in. What it would have saved is a wasted enumeration of a
      # directory nothing will be removed from.
      # Tolerance lives here for the same reason containment does: one
      # place, so no call site can get it wrong.
      #
      # Rounds 37, 38 and 39 each found a different way for one bad entry
      # to abandon the whole sweep -- an unreadable sibling scope, a
      # generation vanishing between listing and sorting, and now a
      # generation that cannot be removed at all (`EACCES`/`EPERM` from
      # changed ownership, a restored backup, a read-only parent). The
      # first two were fixed where they were found, which is what made a
      # third one possible: `#prune_generations` has a single outer rescue,
      # so anything reaching it discards every removal not yet made, and
      # the sort is newest-first, so a blocker shields the entire older
      # tail. On the machine 024.51 exists for -- 28,643 directories,
      # 2.8 GB -- that is the accumulation resuming silently and for good.
      #
      # `SystemCallError` rather than `StandardError`: a failed *syscall*
      # is the sweep's business to survive, and a `TypeError` or a bug in
      # this class is not something to swallow on the way past. ENOENT is
      # the ordinary member of that family -- two windows sweeping one
      # root, or `Re-index Workspace` starting a second sweep -- and is
      # what makes `Server#build_cache_store`'s "removing what is already
      # removed is a no-op" true rather than merely stated.
      def self.remove_within(root, path)
        return unless inside?(root, path)

        FileUtils.remove_entry(path)
      rescue SystemCallError
        nil
      end

      # Strict containment: `root` itself is never removable, and a sibling
      # whose name merely starts with the root's (`/a/bc` against `/a/b`)
      # is not inside it.
      def self.inside?(root, path)
        File.expand_path(path).start_with?("#{File.expand_path(root)}#{File::SEPARATOR}")
      end

      def self.children_of(dir)
        Dir.children(dir).map { |name| File.join(dir, name) }
      rescue StandardError
        []
      end

      # `cache_dir: nil` explicitly disables the cache (never even tries
      # to create anything) -- used when a caller couldn't determine a
      # cache directory at all (Server#build_cache_store's own rescue).
      def initialize(cache_dir:, max_entries: DEFAULT_MAX_ENTRIES)
        @cache_dir = cache_dir && ensure_directory(cache_dir)
        @max_entries = max_entries
      end

      def enabled?
        !@cache_dir.nil?
      end

      def load(path)
        return nil unless @cache_dir

        file = entry_path(path)
        return nil unless File.file?(file)

        result = Marshal.load(File.binread(file))
        return nil unless result.is_a?(Index::FileSummary)

        result
      rescue StandardError
        nil
      end

      # Atomic: writes to a per-process/per-call-unique temp file in the
      # same directory (so the final #rename is same-filesystem, and
      # therefore atomic) and only ever renames it into place after the
      # write itself succeeded -- a crash or concurrent write mid-write
      # never leaves a half-written file where a real cache entry is
      # expected ("cache writeがatomic").
      def save(path, summary)
        return unless @cache_dir

        file = entry_path(path)
        tmp = "#{file}.tmp.#{Process.pid}.#{Thread.current.object_id}.#{rand(1_000_000)}"
        File.binwrite(tmp, Marshal.dump(summary))
        # Before the rename, so the entry is never briefly world-readable
        # under its real name.
        self.class.tighten(tmp, 0o600)
        File.rename(tmp, file)
        prune_if_over_bound if rand(64).zero?
      rescue StandardError
        nil
      ensure
        # Through the contained removal, like every other deletion in this
        # class. The path is built from `@cache_dir` a few lines up and so
        # is inside it today -- which is the argument the directory
        # removals also had, right up until one of them was not. The
        # `File.exist?` guard and the rescue are gone with it:
        # `.remove_within` tolerates an absent path and swallows a failed
        # syscall itself.
        self.class.remove_within(@cache_dir, tmp) if tmp
      end

      private

      # 0700, not the umask's 0755. `vscode/PRIVACY.md` says what is in
      # here: method bodies from the user's own source, verbatim. On a
      # shared machine the default handed those to every other account.
      # `Observation::Runner` already writes the same kind of evidence
      # through `Tempfile`, which is owner-only, so this is the long-lived
      # copy catching up with the project's own standard for it.
      #
      # `mkdir_p`'s mode applies to directories it creates, not to ones
      # that already exist, so an existing loose directory is tightened
      # explicitly -- the case that matters, since every cache created
      # before 0.2.5 is already on disk at 0755.
      def ensure_directory(cache_dir)
        FileUtils.mkdir_p(cache_dir, mode: 0o700)
        tighten(cache_dir)
        cache_dir
      rescue StandardError
        nil # read-only filesystem, permissions, ... -- cache simply never activates.
      end

      def entry_path(path)
        File.join(@cache_dir, "#{Digest::SHA256.hexdigest(path)}.cache")
      end

      # Called (from #save) only roughly once every 64 saves -- listing
      # the whole directory on every single #save would itself become
      # the performance problem this cache exists to avoid, on a
      # workspace large enough to ever approach the bound in the first
      # place. The sampling itself lives in #save, not here, so this
      # method's own pruning logic stays simple and deterministic.
      def prune_if_over_bound
        entries = Dir.children(@cache_dir).select { |f| f.end_with?(".cache") }
        return if entries.size <= @max_entries

        oldest_first = entries.sort_by { |f| File.mtime(File.join(@cache_dir, f)) }
        excess = entries.size - @max_entries
        oldest_first.first(excess).each { |f| self.class.remove_within(@cache_dir, File.join(@cache_dir, f)) }
      rescue StandardError
        nil
      end
    end
  end
end
