#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"
require_relative "changelog"
require_relative "deferred_findings"

require "digest"
require "fileutils"
require "json"
require "open3"

# The release, one command per step, each refusing when the step before
# it left no evidence.
#
#   ruby scripts/release.rb status
#   ruby scripts/release.rb open 0.4.0
#   ruby scripts/release.rb bump
#   ruby scripts/release.rb gate [--accept 024.N --reason "..."]
#   ruby scripts/release.rb publish
#   ruby scripts/release.rb record
#
# **It implements no check.** Every gate below is a delegation to the
# script or spec that already owns the question — `check_changelog.rb`,
# `documented_counts.rb`, `check_site_links.rb`, `preflight.rb`,
# `gitleaks`, `deferred_findings.rb`, the `changelog_parity_spec` and the
# extension's `versionPairing` test — and what this adds is the *order*,
# and the refusal when a step is reached without the one before it.
# `docs/RELEASE_CHECKLIST.md` was that order, and it was a list a person
# walked.
#
# **Every refusal names what clears it.** A gate that says no and not
# what to do next is a gate somebody works around.
#
# What it deliberately does not do: commit anything except `record`'s own
# row, bypass `release.sh`'s prompt, or decide that a minor or major may
# ship. `docs/PUBLISHING.md` has the standing permission and its limits.
module Release
  ROOT = ENV.fetch("OVALLSP_RELEASE_ROOT", File.expand_path("..", __dir__))

  Refused = Class.new(StandardError)

  module_function

  # --- what the tree says -------------------------------------------

  def packaged_version
    JSON.parse(File.read(File.join(ROOT, "vscode", "package.json"), encoding: "UTF-8")).fetch("version")
  end

  def core_version
    File.read(File.join(ROOT, "core", "lib", "ovallsp", "version.rb"), encoding: "UTF-8")[/VERSION\s*=\s*"([^"]+)"/, 1]
  end

  def branch = git("branch", "--show-current").strip

  # The version this branch is for. `release/<version>` is the
  # convention, and a branch that is not one has no release to be about.
  def branch_version
    branch[%r{\Arelease/(\d+\.\d+\.\d+)\z}, 1]
  end

  def tagged?(version) = git("tag", "--list", "v#{version}").strip != ""

  def dirty = git("status", "--porcelain").rstrip

  def git(*args)
    out = RepoFiles.capture(ROOT, args)
    raise Refused, "git #{args.join(' ')} failed: #{out.strip}" unless $?.success?

    out
  end

  # A delegated command, refused in its own words. The same shape
  # `scripts/issues.rb` uses, and for the same reason: running these with
  # their output discarded throws away the reason at the moment it is
  # produced.
  def delegate(*command, chdir: ROOT, why:)
    out, status = Open3.capture2e(*command, chdir: chdir)
    out = out.dup.force_encoding(Encoding::UTF_8).scrub("?")
    return out if status.success?

    raise Refused, "#{why}\n  #{command.join(' ')} said:\n#{out.rstrip.lines.last(20).map { |l| "    #{l}" }.join}"
  end

  # --- the evidence one step leaves the next ------------------------

  # `core/tmp/` is ignored, for the same reason the rspec report is: this
  # is a fact about one working copy at one moment.
  def state_path(version) = File.join(ROOT, "core", "tmp", "release-#{version}.json")

  def state(version)
    path = state_path(version)
    File.file?(path) ? JSON.parse(File.read(path, encoding: "UTF-8")) : {}
  end

  def remember(version, fields)
    FileUtils.mkdir_p(File.dirname(state_path(version)))
    File.write(state_path(version), "#{JSON.pretty_generate(state(version).merge(fields))}\n")
  end

  # --- open ----------------------------------------------------------

  def open_release(version)
    raise Refused, "v#{version} is already tagged. Pick the next version." if tagged?(version)

    unless dirty.empty?
      raise Refused, "the tree is not clean, and a release branch starts from what has shipped:\n" \
                     "#{dirty}\n  Commit or stash it, then run this again."
    end

    git("checkout", "-q", "-b", "release/#{version}")
    document = write_record(version)
    entries = targeted(version)
    write_changelog_skeletons(version, entries)

    puts "release: on release/#{version}."
    puts "  #{document} records it, and names the branch."
    puts "  both changelogs carry a #{version} section with #{entries.length} bullet(s) to write."
    if entries.empty?
      puts "  no open entry targets #{version} yet. `ruby scripts/issues.rb list --target=#{version}` stays the list."
    else
      entries.each { |number, fields| puts "  #{number}  (#{fields['kind']})" }
    end
    0
  end

  # The next `NNN-` in `docs/design/tasks/`, and the two lines a record
  # must open with: the branch, per `AGENTS.md`, and the findings pointer
  # `task_findings_section_spec` requires of a document that has one.
  def write_record(version)
    numbers = Dir.glob(File.join(ROOT, "docs", "design", "tasks", "*.md"))
                 .filter_map { |path| File.basename(path)[/\A(\d+)/, 1]&.to_i }
    relative = File.join("docs", "design", "tasks", "#{numbers.max.to_i + 1}-#{version}-what-this-release-is-for.md")

    File.write(File.join(ROOT, relative), <<~MD)
      # #{version} — what this release is for

      **Branch:** `release/#{version}`, merging into `main` by pull request.

      ## Why this release exists

      Write it before the work, not after.

      ## 残課題

      未処理の指摘はこの文書ではなく `024` に書く。
    MD
    relative
  end

  def targeted(version)
    markdown = DeferredFindings.register(ROOT)
    DeferredFindings.entries(markdown).select do |_, fields|
      fields["target"] == version && !DeferredFindings::RESOLVED.include?(fields["status"])
    end
  end

  # One bullet per entry the release owes, and an empty reasoning
  # subsection under it. Written into both languages at once, because a
  # section added to one and not the other is how this pair goes wrong.
  def write_changelog_skeletons(version, entries)
    titles = entry_titles(version, entries)
    { Changelog::EN => "what this release is for", Changelog::JA => "このリリースの目的" }.each do |relative, headline|
      path = File.join(ROOT, relative)
      body = File.read(path, encoding: "UTF-8")
      head, rest = body.split(Changelog::SPLIT, 2)
      bullets = titles.map { |number, title| "- **#{title}** `#{number}`\n" }.join
      section = "## #{version} — #{headline}\n\n#{bullets.empty? ? "- **TODO** \n" : bullets}\n" \
                "#{Changelog::DETAILS.fetch(relative)}\n\nTODO\n\n"
      File.write(path, "#{head}#{section}#{rest}")
    end
  end

  def entry_titles(version, entries)
    bodies = DeferredFindings.bodies(DeferredFindings.register(ROOT)).to_h
    entries.keys.map { |number| [number, bodies[number].to_s.lines.first.to_s.strip] }
  rescue StandardError
    entries.keys.map { |number| [number, "TODO"] }
  end

  # --- bump ----------------------------------------------------------

  def bump
    version = require_release_branch
    raise Refused, "v#{version} is already tagged. This branch has nothing left to bump." if tagged?(version)

    delegate("ruby", "scripts/check_changelog.rb", "--version", version,
             why: "the #{version} changelog entry is not ready. Write it, then run this again.")
    delegate("ruby", "scripts/documented_counts.rb", "--check",
             why: "the documented example counts are stale. Run `ruby scripts/documented_counts.rb`.")
    refuse_unshaped_release(version)

    set_versions(version)
    delegate("bundle", "lock", chdir: File.join(ROOT, "core"),
                               why: "core/Gemfile.lock could not be refreshed for #{version}.")
    delegate("ruby", "scripts/check_site_links.rb",
             why: "the site does not agree with vscode/package.json about #{version}.")

    remember(version, "bumped" => true)
    puts "release: every version file now says #{version}."
    puts "  nothing is committed. Read `git diff`, then: ruby scripts/release.rb gate"
    0
  end

  # A **patch** may move no capability row, and a **minor** may not leave
  # a user-visible defect unrouted. Both questions are asked of the
  # documents that own them rather than answered here.
  def refuse_unshaped_release(version)
    return if patch?(version)

    unrouted = DeferredFindings.open_entries(DeferredFindings.register(ROOT)).select do |_, fields|
      fields["kind"] == "defect" && fields["user-visible"] == "yes" && fields["target"].to_s.empty?
    end
    return if unrouted.empty?

    raise Refused, "#{version} adds capability, and #{unrouted.length} user-visible defect(s) name no " \
                   "release:\n  #{unrouted.keys.join(', ')}\n" \
                   "  Route each with `ruby scripts/issues.rb retarget <number> --to=V --why=\"...\"`."
  end

  def patch?(version) = version.split(".").last != "0"

  def set_versions(version)
    core = File.join(ROOT, "core", "lib", "ovallsp", "version.rb")
    File.write(core, File.read(core, encoding: "UTF-8").sub(/VERSION\s*=\s*"[^"]+"/) { %(VERSION = "#{version}") })

    delegate("npm", "version", version, "--no-git-tag-version", "--allow-same-version",
             chdir: File.join(ROOT, "vscode"),
             why: "npm could not set vscode/package.json and its lock file to #{version}.")

    %w[index.html ja/index.html].each do |page|
      path = File.join(ROOT, "site", page)
      next unless File.file?(path)

      File.write(path, File.read(path, encoding: "UTF-8").gsub(/(Preview\s+v?)\d+\.\d+\.\d+/) { "#{$1}#{version}" })
    end
  end

  # --- gate ----------------------------------------------------------

  def gate(accept: nil, reason: nil)
    version = require_release_branch
    record_acceptance(version, accept, reason) if accept

    disagreeing = { "vscode/package.json" => packaged_version, "core/lib/ovallsp/version.rb" => core_version }
                  .reject { |_, said| said == version }
    unless disagreeing.empty?
      raise Refused, "these still say something other than #{version}: " \
                     "#{disagreeing.map { |file, said| "#{file} (#{said})" }.join(', ')}.\n" \
                     "  Run: ruby scripts/release.rb bump"
    end

    refuse_open_entries(version)
    refuse_stale_version_mentions(version)
    delegate("gitleaks", "detect", "--config", ".gitleaks.toml",
             why: "gitleaks found something. Nothing is published from a tree it refuses.")
    delegate("ruby", "scripts/preflight.rb", why: "preflight failed. Its own output says which check.")

    remember(version, "gated" => index_tree)
    puts "release: #{version} is gated."
    puts
    puts quotable_block(version)
    0
  end

  def record_acceptance(version, number, reason)
    raise Refused, "--accept #{number} needs --reason: say why #{version} does not owe it." if reason.to_s.strip.empty?

    remember(version, "accepted" => state(version).fetch("accepted", {}).merge(number => reason))
    puts "release: #{number} accepted as not owed by #{version} — #{reason}"
  end

  def refuse_open_entries(version)
    accepted = state(version).fetch("accepted", {}).keys
    owed = targeted(version).keys - accepted
    return if owed.empty?

    warn "release: #{owed.length} entr#{owed.length == 1 ? 'y' : 'ies'} still open against #{version}:"
    owed.each { |number| warn "  #{number}" }
    raise Refused, "close each with `ruby scripts/issues.rb close <number> --released-in #{version}`, " \
                   "or accept one with `--accept <number> --reason \"...\"`."
  end

  # **Where a past version belongs, and where it is staleness.** A
  # release's own record, the artifact table and the changelogs name
  # every version this project has cut and always will; anywhere else, a
  # version that has shipped is a sentence nobody updated. This was the
  # fourth of the four steps `docs/RELEASE_CHECKLIST.md` asked a person
  # to do by hand.
  HISTORY = ["docs/design/tasks/", "docs/RELEASE_ARTIFACTS.md", Changelog::EN, Changelog::JA].freeze

  def refuse_stale_version_mentions(version)
    previous = previous_version(version) or return

    stale = RepoFiles.list(ROOT).reject { |path| path.start_with?(*HISTORY) }.select do |path|
      full = File.join(ROOT, path)
      File.file?(full) && !File.binread(full).include?("\0") &&
        File.read(full, encoding: "UTF-8").include?(previous)
    end
    return if stale.empty?

    warn "release: #{stale.length} file(s) still name #{previous}, which has shipped:"
    stale.each { |path| warn "  #{path} still names #{previous}" }
    raise Refused, "update each, or move the sentence into the release record where a past version belongs."
  end

  # The highest version below this one that `docs/RELEASE_ARTIFACTS.md`
  # records as published — read through the same function every other
  # reader of that table uses.
  def previous_version(version)
    path = File.join(ROOT, "docs", "RELEASE_ARTIFACTS.md")
    return nil unless File.file?(path)

    key = DeferredFindings.version_key(version)
    DeferredFindings.published_versions(File.read(path, encoding: "UTF-8"))
                    .select { |published| (DeferredFindings.version_key(published) <=> key) == -1 }
                    .max_by { |published| DeferredFindings.version_key(published) }
  end

  def index_tree = git("write-tree").strip

  def quotable_block(version)
    <<~TEXT
      #{version} gated on #{branch}
        versions agree: vscode/package.json, core/lib/ovallsp/version.rb
        changelog: both languages lead with #{version}
        register: nothing open against #{version}
        gitleaks: clean; preflight: all checks passed
    TEXT
  end

  # --- publish -------------------------------------------------------

  def publish
    version = require_release_branch
    gated = state(version)["gated"]
    if gated.nil?
      raise Refused, "#{version} has not been gated. Run: ruby scripts/release.rb gate"
    end
    unless gated == index_tree
      raise Refused, "the index has moved since #{version} was gated, so what was gated is not what would " \
                     "be published.\n  Run: ruby scripts/release.rb gate"
    end

    script = File.join(ROOT, "vscode", "scripts", "release.sh")
    raise Refused, "#{script} does not exist." unless File.file?(script)

    puts "release: handing over to vscode/scripts/release.sh, which asks before it publishes."
    exec(script)
  end

  # --- record --------------------------------------------------------

  def record
    version = require_release_branch
    vsix = Dir.glob(File.join(ROOT, "vscode", "*#{version}*.vsix")).first
    unless vsix
      raise Refused, "no VSIX for #{version} in vscode/. Run: ruby scripts/release.rb publish"
    end

    digest = Digest::SHA256.file(vsix).hexdigest
    append_artifact_row(version, digest)
    git("tag", "v#{version}")
    puts "release: recorded #{File.basename(vsix)} as #{digest}, and tagged v#{version}."
    puts "  Compare it against what the Marketplace serves — docs/RELEASE_ARTIFACTS.md has the command —"
    puts "  then commit the row. Nothing is pushed."
    0
  end

  def append_artifact_row(version, digest)
    path = File.join(ROOT, "docs", "RELEASE_ARTIFACTS.md")
    body = File.read(path, encoding: "UTF-8")
    row = "| #{version} | `#{digest}` | Pre-Release |\n"
    anchor = body[/^\| Version \| SHA-256 \| Channel \|\n\|---\|---\|---\|\n/]
    raise Refused, "docs/RELEASE_ARTIFACTS.md has no published table to add a row to." unless anchor

    File.write(path, body.sub(anchor) { "#{anchor}#{row}" })
  end

  # --- status --------------------------------------------------------

  def status
    version = branch_version || packaged_version
    said = state(version)

    puts "release: #{version}, on #{branch.empty? ? '(detached)' : branch}."
    puts "  vscode/package.json      #{packaged_version}"
    puts "  core/lib/ovallsp/version #{core_version}"
    puts "  branch names a release   #{branch_version ? 'yes' : "no — bump and gate refuse off release/<version>"}"
    puts "  bumped                   #{said['bumped'] ? 'yes' : 'no'}"
    puts "  gated                    #{gated_state(said)}"
    puts "  tagged                   #{tagged?(version) ? "yes — v#{version}" : 'no'}"
    accepted = said.fetch("accepted", {})
    accepted.each { |number, reason| puts "  accepted #{number}: #{reason}" }
    0
  end

  def gated_state(said)
    return "no" unless said["gated"]

    said["gated"] == index_tree ? "yes, on this index" : "yes, but the index has moved since"
  end

  # --- dispatch ------------------------------------------------------

  def require_release_branch
    branch_version or
      raise Refused, "this is `#{branch}`, and a release is prepared on `release/<version>`.\n" \
                     "  Start one with: ruby scripts/release.rb open <version>"
  end

  USAGE = <<~TEXT
    usage: ruby scripts/release.rb <command>

      status                     which steps are done for this branch's version
      open <version>             the branch, the record, and both changelog skeletons
      bump                       every version file, once the changelog and counts are ready
      gate [--accept N --reason] gitleaks and preflight, once nothing is open against it
      publish                    hand over to vscode/scripts/release.sh, once gated
      record                     the artifact's hash and the tag, once published

    Every step refuses when the one before it left no evidence, and every
    refusal names the command that clears it. docs/PUBLISHING.md has the
    permission this operates under; docs/RELEASE_CHECKLIST.md has the order.
  TEXT

  def run(argv)
    command = argv.first
    case command
    when "status" then status
    when "open" then argv[1] ? open_release(argv[1]) : (warn(USAGE) || 2)
    when "bump" then bump
    when "gate" then gate(accept: option(argv, "--accept"), reason: option(argv, "--reason"))
    when "publish" then publish
    when "record" then record
    else
      warn USAGE
      2
    end
  rescue Refused => e
    warn "release: refused. #{e.message}"
    2
  end

  def option(argv, name)
    at = argv.index(name) or return nil

    argv[at + 1]
  end
end

exit Release.run(ARGV) if $PROGRAM_NAME == __FILE__
