# frozen_string_literal: true

require "digest"
require "fileutils"

module Rslsp
  module Cache
    # Persists one FileSummary per on-disk file, under
    # `<cache_root>/<workspace_digest>/<sha256(path)>.cache` -- never a
    # source of truth on its own ("cacheをsource of truthにすること" is
    # explicitly out of scope): every read is paired with the live file's
    # own current content hash by the caller (ColdIndexer), so a stale or
    # entirely-wrong cached entry can only ever cost a wasted re-parse,
    # never produce an incorrect result.
    #
    # Every failure mode here -- an unwritable cache directory, a
    # corrupted/truncated cache file, a `Marshal.load` of data from an
    # incompatible format -- degrades to "this entry doesn't exist",
    # logged nowhere (this is a pure performance optimization; a cache
    # miss is always correct, just slower), never raised. "corrupt/stale
    # cacheでCoreが落ちない" is enforced structurally: nothing calling
    # #load ever needs its own rescue.
    class Store
      # A soft LRU-ish bound ("memory bounds/LRU"): pruned opportunistically
      # on #save rather than tracked precisely, since exact LRU ordering
      # isn't worth the bookkeeping cost for what's ultimately just a
      # warm-start optimization -- filesystem mtime (already free, no
      # extra state to maintain) is close enough. A 500k-LOC app is
      # comfortably tens of thousands of files, not entries in the
      # hundreds of thousands, so this default has real headroom.
      DEFAULT_MAX_ENTRIES = 20_000

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
