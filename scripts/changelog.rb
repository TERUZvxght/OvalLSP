# frozen_string_literal: true

require_relative "utf8"

# What a release's changelog entry looks like, in one place.
#
# **The shape was already checked, and could not be checked when it
# mattered.** `core/spec/meta/changelog_parity_spec.rb` reads the two
# real files and asserts the newest section names `Ovallsp::VERSION` —
# true only *after* the version has been bumped. So while a release is
# being prepared, which is the whole window in which the changelog is
# being written, nothing could say the entry was wrong.
#
# This module is that shape as a function of its inputs: two texts and
# the version they should be about. `changelog_parity_spec` reads it for
# the questions it already asked, `check_changelog.rb` asks it about a
# version `vscode/package.json` has not reached yet, and
# `changelog_shape_spec` drives it against deviations the real files do
# not contain. One implementation, three callers.
#
# **The newest section only.** Everything below it was written under
# whatever convention held at the time, and rewriting a published
# release's notes to satisfy a check written afterwards would be
# changing what shipped. `changelog_parity_spec`'s own examples are the
# ones that still range over every release.
module Changelog
  EN = File.join("vscode", "CHANGELOG.md")
  JA = File.join("vscode", "CHANGELOG.ja.md")

  # Where each language puts the reasoning. Checking for the English
  # heading in the Japanese file would pass on a translation that had
  # quietly stopped translating.
  DETAILS = { EN => "### Details", JA => "### 詳細" }.freeze

  # A release heading, and the split between what changed and why. `## `
  # with a version, because both files carry other level-two headings.
  HEADING = /^## (\d+\.\d+\.\d+)/
  SPLIT = /^(?=## \d+\.\d+\.\d+)/

  Section = Struct.new(:version, :heading, :summary, :details, keyword_init: true) do
    # A changelog is read to answer "what changed", so a release leads
    # with that and the reasoning lives below. The natural way to write
    # an entry is to start explaining, and one entry that does drags the
    # whole file back.
    def bullets = summary.lines.count { |line| line.start_with?("- ") }
  end

  module_function

  def sections(markdown)
    markdown.split(SPLIT).drop(1).map do |block|
      summary, details = block.split(/^(?=### )/, 2)
      Section.new(version: block[HEADING, 1], heading: block.lines.first.to_s.strip,
                  summary: summary.to_s, details: details.to_s)
    end
  end

  def versions(markdown) = markdown.scan(HEADING).flatten

  # Every way the newest entry can be wrong, as sentences a person can
  # act on. Empty means it is right.
  #
  # `expected` is the version the entry is about: what
  # `vscode/package.json` says once the bump has happened, and what
  # `--version` says while it is being prepared.
  def complaints(english, japanese, expected)
    newest = { EN => sections(english).first, JA => sections(japanese).first }
    missing = newest.select { |_, section| section.nil? }.keys
    return missing.map { |path| "#{path} carries no release section at all." } if missing.any?

    version_complaints(newest, expected) + shape_complaints(newest) + parity_complaints(newest)
  end

  def version_complaints(newest, expected)
    newest.filter_map do |path, section|
      next if section.version == expected

      "#{path}'s newest section is #{section.version}, and the release is #{expected}. " \
        "Write #{expected}'s section above it, or name the version you meant with --version."
    end
  end

  def shape_complaints(newest)
    newest.flat_map do |path, section|
      complaints = []
      if section.bullets.zero?
        complaints << "#{path}'s #{section.version} section leads with prose. A release leads with " \
                      "what changed, one `- ` bullet each, before any `###` heading."
      end
      unless section.details.start_with?(DETAILS.fetch(path))
        complaints << "#{path}'s #{section.version} section has no #{DETAILS.fetch(path).inspect} " \
                      "subsection. The reasoning, the measurements and the approaches that did not " \
                      "work go under it."
      end
      complaints
    end
  end

  # A dropped bullet is how this pair actually goes wrong -- round 4 of
  # the 0.1.12 review found the Japanese changelog a bullet short, with
  # every other guard green. A count is not a translation check; it is
  # the part a machine can see.
  def parity_complaints(newest)
    english, japanese = newest.values_at(EN, JA)
    return [] unless english.version == japanese.version
    return [] if english.bullets == japanese.bullets

    ["#{EN} leads #{english.version} with #{english.bullets} bullet(s) and #{JA} with " \
     "#{japanese.bullets}. Both languages say the same things about one release."]
  end
end
