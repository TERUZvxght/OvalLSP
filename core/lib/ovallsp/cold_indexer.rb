# frozen_string_literal: true

require "set"
require "digest"
require_relative "text_document"
require_relative "uri_util"

module Ovallsp
  # Walks the workspace on disk after `initialize` and indexes every
  # matching file, so a controller or model that hasn't been opened in an
  # editor yet is still resolvable — without this, opening a view before
  # its controller made Task 008's instance-variable propagation fail,
  # since WorkspaceIndex only ever learned about files through
  # didOpen/didChange/didChangeWatchedFiles
  # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
  #
  # Runs entirely on the caller's thread — Server is expected to run it on
  # a background thread (see #start_cold_index) so it never delays the
  # `initialize` response. An open document always wins: a file already
  # in DocumentStore is skipped rather than overwritten with (possibly
  # stale) on-disk content, mirroring the same check
  # workspace/didChangeWatchedFiles already makes.
  #
  # URIs are built from the *logical* path (root as given, joined with
  # each directory entry's literal name) — never from a realpath-resolved
  # path. `File.realpath` is used only as an internal dedup/cycle-detection
  # key; if it were also used to build URIs, a workspace root that's
  # itself a symlink (common for OS temp directories, some project setups)
  # would produce URIs that never match what didOpen sends for the same
  # file, silently defeating the "open document wins" rule above.
  class ColdIndexer
    Result = Data.define(:seen_uris, :complete)
    DEFAULT_INCLUDED_EXTENSIONS = %w[.rb .rake .erb].freeze
    DEFAULT_EXCLUDED_DIRS = %w[.git node_modules vendor tmp log coverage storage].freeze
    DEFAULT_EXCLUDED_PATHS = ["vendor/bundle", "public/assets"].freeze

    def initialize(root:, parser_service:, workspace_index:, document_store:, logger:, hierarchy_index: nil,
                   cache_store: nil, excluded_dirs: DEFAULT_EXCLUDED_DIRS, excluded_paths: DEFAULT_EXCLUDED_PATHS,
                   included_extensions: DEFAULT_INCLUDED_EXTENSIONS, on_indexed: nil, on_complete: nil,
                   on_summary: nil)
      @root = File.expand_path(root)
      @root_real = safe_realpath(@root) || @root
      @parser_service = parser_service
      @workspace_index = workspace_index
      @hierarchy_index = hierarchy_index
      @document_store = document_store
      @logger = logger
      @cache_store = cache_store
      @excluded_dirs = excluded_dirs
      @excluded_paths = excluded_paths
      @included_extensions = included_extensions
      @on_indexed = on_indexed
      @on_complete = on_complete
      @on_summary = on_summary
      @seen_uris = Set.new
      @scan_complete = true
    end

    def run
      visited_dirs = Set.new
      visited_files = Set.new
      each_candidate_file(@root, visited_dirs) { |path| index_file(path, visited_files) }
    rescue StandardError => e
      @scan_complete = false
      @logger.error("cold index failed: #{e.class}: #{e.message}")
    ensure
      if @on_complete
        result = Result.new(seen_uris: @seen_uris.dup, complete: @scan_complete)
        @on_complete.arity.zero? ? @on_complete.call : @on_complete.call(result)
      end
    end

    private

    def each_candidate_file(dir, visited_dirs)
      real_dir = safe_realpath(dir)
      unless real_dir
        @scan_complete = false
        return
      end
      return if visited_dirs.include?(real_dir) # already walked (symlink cycle or alias)

      visited_dirs << real_dir

      Dir.each_child(dir) do |entry|
        path = File.join(dir, entry) # logical path — see class comment

        if File.directory?(path)
          next if excluded_dir?(dir, entry)
          next if File.symlink?(path) && !symlinked_path_stays_inside_root?(path)

          each_candidate_file(path, visited_dirs) { |file| yield file }
        elsif @included_extensions.any? { |ext| entry.end_with?(ext) }
          yield path
        end
      end
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      @scan_complete = false
      @logger.error("cold index: skipping #{dir}: #{e.class}: #{e.message}")
    end

    # A symlinked *directory* pointing outside the workspace was already
    # checked here before Task 008.6; a symlinked *file* pointing outside
    # the workspace (e.g. `app/models/evil.rb -> /etc/passwd`, or more
    # realistically a symlink into another project entirely) was not —
    # #index_file only used realpath for dedup, never for a boundary
    # check, so any file-level symlink escaping the root was silently
    # read and indexed regardless of where it actually pointed
    # (docs/design/tasks/008.6-agent-and-index-hardening.md). #index_file
    # applies the same `real_path_stays_inside_root?` check below to
    # every file, not just ones File.symlink? itself flags, since a file
    # reached through an *already-permitted* symlinked directory can
    # still individually be a symlink pointing back out.
    def symlinked_path_stays_inside_root?(path)
      real_path_stays_inside_root?(safe_realpath(path))
    end

    def real_path_stays_inside_root?(real_path)
      return false if real_path.nil?

      real_path == @root_real || real_path.start_with?("#{@root_real}/")
    end

    def excluded_dir?(parent_dir, entry)
      return true if @excluded_dirs.include?(entry)

      relative = relative_path(File.join(parent_dir, entry))
      @excluded_paths.any? { |excluded| relative == excluded || relative.start_with?("#{excluded}/") }
    end

    def relative_path(path)
      full = File.expand_path(path)
      full.start_with?("#{@root}/") ? full.delete_prefix("#{@root}/") : full
    end

    def index_file(path, visited_files)
      real_path = safe_realpath(path)
      return if real_path.nil? # gone since the directory scan
      return if visited_files.include?(real_path) # same file reached via two symlinked paths

      visited_files << real_path
      return unless real_path_stays_inside_root?(real_path)

      uri = UriUtil.from_path(path)
      @seen_uris << uri
      # This check alone is NOT what prevents an open buffer from being
      # overwritten — there's a window between it and the #replace_file
      # call below where a didOpen for this exact uri can land, and this
      # thread's read (already in flight) would otherwise clobber it. The
      # real guarantee is structural, inside WorkspaceIndex#replace_file
      # itself (buffer always beats disk, unconditionally); this check is
      # only a cheap early-out to skip reading+parsing a file we already
      # know is open, not a substitute for that guarantee
      # (docs/design/tasks/008.6-agent-and-index-hardening.md).
      return if @document_store.fetch(uri: uri)

      raw_source = source_for(path)
      parsed = cached_or_parsed_summary(uri, path, raw_source)
      document = TextDocument.new(uri: uri, text: raw_source, version: nil, language_id: "ruby")

      read_sequence = @workspace_index.next_read_sequence
      summary = parsed.with(source: :disk, read_sequence: read_sequence)
      if @on_summary
        @on_summary.call(uri, document, summary)
        return
      end

      previous_declarations = @workspace_index.declarations_for_uri(uri)
      if @workspace_index.replace_file(summary)
        @hierarchy_index&.replace_file(summary)
        @on_indexed&.call(uri, document, summary, previous_declarations)
      end
    rescue StandardError => e
      @scan_complete = false
      @logger.error("cold index: failed to index #{path}: #{e.class}: #{e.message}")
    end

    # "Cache格納結果とcold解析結果が意味的に一致する" (Task 021): a cache
    # hit is only ever used when its *own* stored `content_hash` matches
    # the file's current content exactly -- computed here, once, and
    # reused for both the cache-validity check and (on a miss)
    # ParserService#summarize's own identical hash, rather than reading
    # the file twice. `content_hash` is always keyed on the *raw*
    # (pre-ERB-extraction) source, matching FileSummary's own documented
    # contract, so this comparison is exactly the same check
    # WorkspaceIndex's own no-op-skip logic already relies on elsewhere.
    def cached_or_parsed_summary(uri, path, raw_source)
      content_hash = Digest::SHA256.hexdigest(raw_source)
      cached = @cache_store&.load(path)
      return cached if cached && cached.content_hash == content_hash

      document = TextDocument.new(uri: uri, text: raw_source, version: nil, language_id: "ruby")
      summary = @parser_service.summarize(document)
      @cache_store&.save(path, summary)
      summary
    end

    # ERB extraction itself now happens inside ParserService#summarize,
    # keyed off the document's uri — the one place every declaration-
    # extracting caller (Cold Index here, didOpen/didChange's #reindex,
    # didChangeWatchedFiles' #reindex_from_disk) goes through, so none of
    # them can implement it differently or forget it
    # (docs/design/tasks/008.6-agent-and-index-hardening.md). This method
    # only reads the raw file content.
    def source_for(path)
      # Never rely on Encoding.default_external here: it reflects the
      # *process's* locale, not the file's actual encoding, and reading
      # without pinning UTF-8 explicitly makes any file containing
      # non-ASCII bytes (Japanese comments, em dashes, emoji, ...) raise
      # ArgumentError the moment ParserService tries to String#split it
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      File.read(path, encoding: Encoding::UTF_8)
    end

    def safe_realpath(path)
      File.realpath(path)
    rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR
      nil
    end
  end
end
