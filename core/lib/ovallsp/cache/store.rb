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

      def self.mark_workspace(scope_dir, workspace_path)
        File.write(File.join(scope_dir, WORKSPACE_MARKER), "#{workspace_path}\n")
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
      # not.
      def self.prune_generations(cache_root:, current:, keep: DEFAULT_MAX_GENERATIONS)
        prune_workspaces(cache_root, File.expand_path(current))
        prune_generations_of(File.dirname(File.expand_path(current)), File.expand_path(current), keep)
      rescue StandardError
        nil
      end

      def self.prune_generations_of(scope_dir, current, keep)
        generations = children_of(scope_dir).select { |path| File.directory?(path) }
        return if generations.length <= keep

        generations.sort_by { |path| -File.mtime(path).to_f }
                   .reject { |path| File.expand_path(path) == current }
                   .drop(keep - 1)
                   .each { |path| FileUtils.remove_entry(path) }
      end

      def self.prune_workspaces(cache_root, current)
        current_scope = File.dirname(current)
        children_of(cache_root).each do |path|
          next unless File.directory?(path)
          next if File.expand_path(path) == current_scope

          marker = File.join(path, WORKSPACE_MARKER)
          # No marker: a pre-0.2.1 generation, unreadable by this build.
          next FileUtils.remove_entry(path) unless File.file?(marker)

          workspace = File.read(marker).strip
          FileUtils.remove_entry(path) unless workspace.empty? || File.directory?(workspace)
        end
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
        File.rename(tmp, file)
        prune_if_over_bound if rand(64).zero?
      rescue StandardError
        nil
      ensure
        begin
          File.delete(tmp) if tmp && File.exist?(tmp)
        rescue StandardError
          nil
        end
      end

      def clear
        return unless @cache_dir

        FileUtils.rm_rf(@cache_dir)
        FileUtils.mkdir_p(@cache_dir)
      rescue StandardError
        nil
      end

      private

      def ensure_directory(cache_dir)
        FileUtils.mkdir_p(cache_dir)
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
        oldest_first.first(excess).each { |f| File.delete(File.join(@cache_dir, f)) }
      rescue StandardError
        nil
      end
    end
  end
end
