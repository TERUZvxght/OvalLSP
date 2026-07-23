# frozen_string_literal: true

require "set"
require_relative "text_document"
require_relative "uri_util"
require_relative "erb/ruby_region_extractor"

module Rslsp
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
    DEFAULT_INCLUDED_EXTENSIONS = %w[.rb .rake .erb].freeze
    DEFAULT_EXCLUDED_DIRS = %w[.git node_modules vendor tmp log coverage storage].freeze
    DEFAULT_EXCLUDED_PATHS = ["vendor/bundle", "public/assets"].freeze

    def initialize(root:, parser_service:, workspace_index:, document_store:, logger:,
                   excluded_dirs: DEFAULT_EXCLUDED_DIRS, excluded_paths: DEFAULT_EXCLUDED_PATHS,
                   included_extensions: DEFAULT_INCLUDED_EXTENSIONS)
      @root = File.expand_path(root)
      @root_real = safe_realpath(@root) || @root
      @parser_service = parser_service
      @workspace_index = workspace_index
      @document_store = document_store
      @logger = logger
      @excluded_dirs = excluded_dirs
      @excluded_paths = excluded_paths
      @included_extensions = included_extensions
    end

    def run
      visited_dirs = Set.new
      visited_files = Set.new
      each_candidate_file(@root, visited_dirs) { |path| index_file(path, visited_files) }
    rescue StandardError => e
      @logger.error("cold index failed: #{e.class}: #{e.message}")
    end

    private

    def each_candidate_file(dir, visited_dirs)
      real_dir = safe_realpath(dir)
      return if real_dir.nil? # gone, or a broken symlink
      return if visited_dirs.include?(real_dir) # already walked (symlink cycle or alias)

      visited_dirs << real_dir

      Dir.each_child(dir) do |entry|
        path = File.join(dir, entry) # logical path — see class comment

        if File.directory?(path)
          next if excluded_dir?(dir, entry)
          next if File.symlink?(path) && !symlinked_dir_stays_inside_root?(path)

          each_candidate_file(path, visited_dirs) { |file| yield file }
        elsif @included_extensions.any? { |ext| entry.end_with?(ext) }
          yield path
        end
      end
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
      @logger.error("cold index: skipping #{dir}: #{e.class}: #{e.message}")
    end

    def symlinked_dir_stays_inside_root?(path)
      target_real = safe_realpath(path)
      return false if target_real.nil?

      target_real == @root_real || target_real.start_with?("#{@root_real}/")
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

      uri = UriUtil.from_path(path)
      return if @document_store.fetch(uri: uri) # an open buffer's content is authoritative; leave it alone

      document = TextDocument.new(uri: uri, text: source_for(path), version: nil, language_id: "ruby")
      @workspace_index.replace_file(@parser_service.summarize(document))
    rescue StandardError => e
      @logger.error("cold index: failed to index #{path}: #{e.class}: #{e.message}")
    end

    # .erb isn't Ruby — Prism can't parse the surrounding HTML — so its Ruby
    # regions are extracted the same way Server does for Task 008's view
    # queries before this ever reaches ParserService.
    def source_for(path)
      # Never rely on Encoding.default_external here: it reflects the
      # *process's* locale, not the file's actual encoding, and reading
      # without pinning UTF-8 explicitly makes any file containing
      # non-ASCII bytes (Japanese comments, em dashes, emoji, ...) raise
      # ArgumentError the moment ParserService tries to String#split it
      # (docs/design/tasks/008.5-runtime-and-index-corrections.md).
      text = File.read(path, encoding: Encoding::UTF_8)
      path.end_with?(".erb") ? Erb::RubyRegionExtractor.extract_ruby_source(text) : text
    end

    def safe_realpath(path)
      File.realpath(path)
    rescue Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR
      nil
    end
  end
end
