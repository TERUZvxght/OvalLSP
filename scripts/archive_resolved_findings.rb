#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves every resolved entry out of the live register and into the
# archive beside it, in numeric order.
#
# `024.R9` split the register by state: the live file is the open work
# and its legend, the archive is everything `fixed` or `done`. That split
# only stays true if resolving an entry moves it, and doing that by hand
# is the operation this repository has the worst record with -- a scripted
# edit took the register from 11,555 lines to 25,878 twice over
# (`024.225`), and `docs/DEVELOPMENT.md` asks for a form of work that can be
# replayed rather than one that exists only in the tree.
#
# So it is one script, run after closing an entry, and
# `core/spec/meta/register_split_spec.rb` fails if it was not.
#
# `--check` reports without writing, which is what a gate wants.

require_relative "utf8"
require_relative "deferred_findings"
require_relative "reindex_findings"

ROOT = File.expand_path("..", __dir__)
CHECK = ARGV.include?("--check")

live_path = File.join(ROOT, DeferredFindings::LIVE)
archive_path = File.join(ROOT, DeferredFindings::ARCHIVE)

all = DeferredFindings.entries(DeferredFindings.register(ROOT))
resolved = ->(block) do
  fields = all[DeferredFindings.number_of(block)]
  fields && DeferredFindings::RESOLVED.include?(fields["status"])
end

head, *blocks = File.read(live_path, encoding: "UTF-8").split(DeferredFindings::ENTRY_SPLIT)
moving, staying = blocks.partition(&resolved)

if moving.empty?
  puts "archive-resolved: nothing to move."
  exit 0
end

numbers = moving.map { |b| DeferredFindings.number_of(b) }
if CHECK
  warn "archive-resolved: #{numbers.length} resolved entr#{numbers.length == 1 ? 'y is' : 'ies are'} " \
       "still in the live register: #{numbers.join(', ')}.\n" \
       "Run: ruby scripts/archive_resolved_findings.rb"
  exit 1
end

archive_head, *archived = File.read(archive_path, encoding: "UTF-8").split(DeferredFindings::ENTRY_SPLIT)
merged = (archived + moving).sort_by { |b| ReindexFindings.entry_key(DeferredFindings.number_of(b)) }

File.write(archive_path, archive_head + merged.join)
File.write(live_path, head + staying.join)
puts "archive-resolved: moved #{numbers.join(', ')}. Now run: ruby scripts/reindex_findings.rb"
