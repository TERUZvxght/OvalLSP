#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "changelog"
require_relative "repo_files"

require "json"
require "optparse"

# The newest changelog entry, checked against the release it is about.
#
#   ruby scripts/check_changelog.rb                  # against vscode/package.json
#   ruby scripts/check_changelog.rb --version 0.4.0  # against the one being prepared
#
# **Why this exists when a spec already reads these files.**
# `changelog_parity_spec` asserts the newest section names
# `Ovallsp::VERSION`, which becomes true only *after* the version has
# been bumped — so during the window in which the entry is actually being
# written, nothing could say it was wrong. `--version` is that window:
# `scripts/release.rb bump` asks this before it moves any version file,
# and refuses if the answer is no.
#
# It is not a second implementation of the shape. `scripts/changelog.rb`
# holds it, the parity spec reads the same module, and
# `changelog_shape_spec` drives it against deviations the real files do
# not contain.
module CheckChangelog
  ROOT = File.expand_path("..", __dir__)

  module_function

  # What `vscode/package.json` says the extension is. Read from the
  # manifest rather than from `version.rb`, because this runs mid-bump
  # and the manifest is the file the VSIX is built from.
  def packaged_version
    JSON.parse(File.read(File.join(ROOT, "vscode", "package.json"), encoding: "UTF-8")).fetch("version")
  end

  def read(relative) = File.read(File.join(ROOT, relative), encoding: "UTF-8")

  def branch
    out = RepoFiles.capture(ROOT, %w[branch --show-current])
    $?.success? ? out.strip : ""
  end

  # **Which version the newest section is measured against.**
  #
  # `--version` when given; otherwise the branch, when the branch names a
  # release; otherwise the manifest. The branch knows before the manifest
  # does — that is the whole gap between `open` and `bump`, and this
  # check, running from preflight, failed every commit in it for writing
  # the entry `open` had just told the writer to write.
  #
  # Pure, so the three cases can be driven without a repository.
  def expected_version(given, branch_name, packaged)
    given || branch_name.to_s[%r{\Arelease/(\d+\.\d+\.\d+)\z}, 1] || packaged
  end

  def run(argv)
    expected = nil
    parser = OptionParser.new do |o|
      o.banner = "usage: ruby scripts/check_changelog.rb [--version VERSION]"
      o.on("--version VERSION", "the release being prepared, if it is not the packaged one") { |v| expected = v }
    end
    parser.parse(argv)
    expected = expected_version(expected, branch, packaged_version)

    complaints = Changelog.complaints(read(Changelog::EN), read(Changelog::JA), expected)
    if complaints.empty?
      puts "check-changelog: #{Changelog::EN} and #{Changelog::JA} lead with #{expected}, " \
           "bullets first and the reasoning below, the same number in each."
      return 0
    end

    warn "check-changelog: #{complaints.length} problem(s) with the newest entry:"
    complaints.each { |complaint| warn "  - #{complaint}" }
    1
  end
end

exit CheckChangelog.run(ARGV) if $PROGRAM_NAME == __FILE__
