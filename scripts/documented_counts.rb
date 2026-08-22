#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Where `core/`'s example count is written down, and how to read it.
#
#   ruby scripts/documented_counts.rb           # rewrite the documents
#   ruby scripts/documented_counts.rb --check   # exit 1 if any is stale
#
# Three documents state the number, and `documented_counts_spec.rb`
# fails when any of them disagrees with the suite it is running in. The
# guard is right to exist -- the figure was 895 for six releases, then
# 1,776 taken mid-branch, then 1,833 with two commits still to come, so
# it went stale three times while a line saying "measure this every
# time" sat next to it.
#
# What the guard could not fix is that re-deriving it was three hand
# edits, every time an example is added, in two languages. That is a
# tax on the commit rather than on the release, and in one 0.2.14
# session it was paid four times. `024.145`.
#
# The patterns live here rather than in the spec because both must read
# the same ones. Two readers of one text with two grammars is the defect
# `046`'s C4 exists for; repeating it inside C4's own release would be
# a poor joke.
module DocumentedCounts
  ROOT = File.expand_path("..", __dir__)

  # `1,833` and `1833` are the same claim; the documents use the first
  # and a future one may use the second.
  PATTERNS = {
    "docs/SUPPORT_MATRIX.md" => /([\d,]+) examples/,
    "docs/SUPPORT_MATRIX.ja.md" => /([\d,]+) examples/,
    "docs/RELEASE_CHECKLIST.md" => %r{`core/`: ([\d,]+) examples}
  }.freeze

  module_function

  def read(document) = File.read(File.join(ROOT, document), encoding: "UTF-8")

  def stated(document) = read(document).scan(PATTERNS.fetch(document)).flatten.map { |n| Integer(n.delete(",")) }

  # `--dry-run` loads every spec file and counts, without running one.
  # 0.4 seconds against the eight minutes a real run takes, and the same
  # number `RSpec.world.example_count` reports from inside it.
  def actual
    out = IO.popen(%w[bundle exec rspec --dry-run], chdir: File.join(ROOT, "core"), err: %i[child out], &:read)
    count = out[/^(\d+) examples?,/, 1]
    raise "could not read an example count from `rspec --dry-run`:\n#{out}" if count.nil?

    Integer(count)
  end

  # Rewrites only inside a match of that document's own pattern, so a
  # number that happens to equal the old count elsewhere in the file is
  # left alone.
  def rewrite(document, count)
    text = read(document)
    updated = text.gsub(PATTERNS.fetch(document)) do |match|
      match.sub(Regexp.last_match(1), count.to_s.reverse.scan(/\d{1,3}/).join(",").reverse)
    end
    return false if updated == text

    File.write(File.join(ROOT, document), updated)
    true
  end
end

if __FILE__ == $PROGRAM_NAME
  check_only = ARGV.include?("--check")
  count = DocumentedCounts.actual
  stale = DocumentedCounts::PATTERNS.keys.reject { |d| DocumentedCounts.stated(d).uniq == [count] }

  if stale.empty?
    puts "documented-counts: all #{DocumentedCounts::PATTERNS.length} documents state #{count}."
    exit 0
  end

  if check_only
    stale.each { |d| warn "documented-counts: #{d} says #{DocumentedCounts.stated(d).uniq.join(', ')}, the suite has #{count}" }
    warn "documented-counts: run `ruby scripts/documented_counts.rb` to re-derive."
    exit 1
  end

  # Report what was *written*, not what was found stale. `rewrite`
  # returns false when its gsub matched nothing, which is a document
  # whose wording moved out from under the pattern -- classed stale,
  # never written to, and until round 1 found it, still counted in the
  # success line and exited 0.
  rewritten = stale.select { |d| DocumentedCounts.rewrite(d, count).tap { |ok| puts "documented-counts: #{d} -> #{count}" if ok } }
  missed = stale - rewritten

  unless missed.empty?
    missed.each do |d|
      warn "documented-counts: #{d} matched #{DocumentedCounts::PATTERNS.fetch(d).inspect} nowhere -- nothing was written."
    end
    warn "documented-counts: the document's wording moved out from under its pattern. " \
         "Fix the pattern here, or the sentence there; do not leave the number unstated."
    exit 1
  end

  puts "documented-counts: re-derived #{count} into #{rewritten.length} document(s)."
end
