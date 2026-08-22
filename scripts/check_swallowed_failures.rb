#!/usr/bin/env ruby
# frozen_string_literal: true

# `042`'s D10 / `024.122`. A failure caught and turned into a plausible
# value does not produce a wrong answer somebody eventually notices. It
# produces *the answer that would be right if nothing had gone wrong* --
# and this project has been bitten at every layer, including by the
# checker built to prevent a different defect.
#
# Every `rescue` statement in `core/lib` is enumerated here and must
# carry a verdict in `core/spec/meta/rescue_verdicts.yml`. A new rescue
# with no verdict fails, which is the whole mechanism: the decision to
# swallow becomes an edit somebody makes on purpose rather than a default
# nobody notices.
#
# Counting `rescue` *statements*, not the word: the first count of this
# tree said 239 and came from `grep -c rescue`, which counts the keyword
# in the prose of comments explaining a rescue.

require "yaml"

ROOT = File.expand_path("..", __dir__)
LIB = File.join(ROOT, "core", "lib")
VERDICTS = File.join(ROOT, "core", "spec", "meta", "rescue_verdicts.yml")

# - surfaces:   raises, or reports through a channel a person sees
# - contained:  the failure genuinely has no consequence, and the reason
#               is written at the site
# - swallows:   neither. This is the group `024.122` exists to empty.
VERDICT_KINDS = %w[surfaces contained swallows].freeze

def sites
  Dir.glob(File.join(LIB, "**", "*.rb")).sort.flat_map do |path|
    rel = path.delete_prefix("#{ROOT}/")
    lines = File.read(path, encoding: "UTF-8").split("\n")
    # Keyed by the enclosing `def`, not by line number: a line number
    # rots on the next edit above it, and a file plus a repeated
    # `rescue StandardError` is not unique -- 42 of these live in one
    # file. The method name plus an ordinal within it is stable under
    # every edit that does not move the rescue to another method.
    method = nil
    seen_in_method = Hash.new(0)
    lines.each_with_index.filter_map do |line, i|
      if (m = line.strip.match(/\Adef\s+([A-Za-z_][A-Za-z0-9_.?!=\[\]]*)/))
        method = m[1]
        seen_in_method = Hash.new(0)
      end
      next unless line.strip.match?(/\Arescue\b/)

      seen_in_method[method] += 1
      nth = seen_in_method[method]
      { "file" => rel, "line" => i + 1, "source" => line.strip,
        "key" => "#{rel}##{method || "(toplevel)"}#{nth > 1 ? "[#{nth}]" : ""}" }
    end
  end
end

found = sites
recorded = File.exist?(VERDICTS) ? (YAML.safe_load(File.read(VERDICTS, encoding: "UTF-8")) || {}) : {}

problems = []
found.each do |site|
  key = site["key"]
  verdict = recorded[key]
  if verdict.nil?
    problems << "#{site["file"]}:#{site["line"]}  #{site["source"]}\n      has no verdict. Add one to " \
                "core/spec/meta/rescue_verdicts.yml -- surfaces, contained, or swallows."
  elsif !VERDICT_KINDS.include?(verdict.to_s.split(":").first)
    problems << "#{site["file"]}:#{site["line"]}  verdict #{verdict.inspect} is not one of #{VERDICT_KINDS.join(", ")}."
  elsif verdict.to_s.split(":").first == "swallows"
    # **The column is empty, and stays empty.** Every one of the 158
    # sites either surfaces or carries an argument for why the failure
    # cannot become an assertion. `swallows` remains spellable so that
    # this message can name it, not so that a site can sit in it.
    problems << "#{site["file"]}:#{site["line"]}  #{site["source"]}\n      is marked `swallows`. " \
                "Catching a failure and continuing is not allowed by default (CLAUDE.md): make it surface, " \
                "or write the argument for why no caller can assert from the value it returns and mark it " \
                "`contained: <why>`."
  end
end

stale = recorded.keys - found.map { |s| s["key"] }
stale.each { |k| problems << "#{k}\n      has a verdict and no longer exists. Remove it." }

counts = Hash.new(0)
found.each { |s| counts[recorded[s["key"]].to_s.split(":").first] += 1 }

if problems.empty?
  puts "check-swallowed-failures: #{found.length} rescue site(s) -- " \
       "#{counts["surfaces"]} surface, #{counts["contained"]} contained, and none swallowing."
  exit 0
end

warn("check-swallowed-failures: #{problems.length} problem(s):")
problems.first(40).each { |p| warn("  - #{p}") }
warn("  ... and #{problems.length - 40} more") if problems.length > 40
exit 1
