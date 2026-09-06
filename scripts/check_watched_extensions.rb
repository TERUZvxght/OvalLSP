#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# **What the first index reads, and what the watcher then watches, are one
# contract written in two languages.**
#
# `ColdIndexer::DEFAULT_INCLUDED_EXTENSIONS` is `%w[.rb .rake .erb]`;
# `WATCHED_FILES_GLOB` in `vscode/src/watchedFiles.ts` listed `.rb`,
# `.rbs`, `.rbi`, `.erb` and two named files. `.rake` was in one and not
# the other for three releases, so a `.rake` file was read once at startup
# and never again: edit, add or delete it outside the editor with the file
# unopened, and the index went on answering from the first read. Nothing
# could notice, because no check knew the two lists were about the same
# thing. Found by the 2026-09-05 critical review, R12.
#
# **Both directions.** An extension Core indexes and the watcher misses is
# the defect above. An extension the watcher reports and Core does not
# index is a notification Core has nothing to do with -- cheap, but it
# means one of the two lists was edited without the other, which is the
# state this exists to refuse.
#
# `EXTRA_WATCHED` is the deliberate difference: signatures and schema are
# watched because a change to them invalidates answers, not because they
# are indexed as source. Listed here rather than inferred, so adding one
# is a decision somebody writes down.
#
# Usage: ruby scripts/check_watched_extensions.rb
module WatchedExtensions
  ROOT = File.expand_path("..", __dir__)
  COLD_INDEXER = "core/lib/ovallsp/cold_indexer.rb"
  WATCHED_FILES = "vscode/src/watchedFiles.ts"

  EXTRA_WATCHED = %w[.rbs .rbi].freeze

  module_function

  def indexed_extensions
    source = File.read(File.join(ROOT, COLD_INDEXER), encoding: "UTF-8")
    match = /DEFAULT_INCLUDED_EXTENSIONS\s*=\s*%w\[([^\]]*)\]/.match(source)
    raise "#{COLD_INDEXER}: DEFAULT_INCLUDED_EXTENSIONS is not written as a %w[] literal any more" unless match

    match[1].split.map(&:strip).reject(&:empty?)
  end

  def watched_extensions
    source = File.read(File.join(ROOT, WATCHED_FILES), encoding: "UTF-8")
    match = /WATCHED_FILES_GLOB\s*=\s*'([^']*)'/.match(source)
    raise "#{WATCHED_FILES}: WATCHED_FILES_GLOB is not written as a single-quoted literal any more" unless match

    match[1].scan(/\*(\.[A-Za-z0-9]+)/).flatten
  end

  def problems
    indexed = indexed_extensions
    watched = watched_extensions
    # The census before the verdict (`024.148`): two empty lists agree
    # with each other and say nothing.
    return ["neither list could be read as a list of extensions"] if indexed.empty? || watched.empty?

    (indexed - watched).map { |ext| "#{ext} is indexed by ColdIndexer and not watched by the extension" } +
      (watched - indexed - EXTRA_WATCHED).map { |ext| "#{ext} is watched by the extension and not indexed by Core" }
  end

  def run
    found = problems
    puts "check-watched-extensions: indexed #{indexed_extensions.join(' ')}; watched #{watched_extensions.join(' ')}"

    if found.empty?
      puts "check-watched-extensions: the two lists agree."
      0
    else
      found.each { |problem| warn "  #{problem}" }
      warn "A file kind the first index reads must be one the watcher reports, or its answers freeze at startup."
      1
    end
  end
end

exit(WatchedExtensions.run) if __FILE__ == $PROGRAM_NAME
