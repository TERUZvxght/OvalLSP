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
require "tmpdir"

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

  # How to get each tool this shells out to. Named rather than left to
  # the reader, because the refusal that sends somebody to a search
  # engine is the one they work around.
  INSTALL = {
    "gitleaks" => "Install it: brew install gitleaks",
    "npm" => "Install Node, which brings npm",
    "bundle" => "Install Bundler: gem install bundler",
    "curl" => "Install curl, or pass --served <sha256> instead"
  }.freeze

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

  def branch_exists?(name) = git("branch", "--list", name).strip != ""

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
  # **A tool that is not installed is a refusal, not a stack trace.**
  # `Open3.capture2e` raises `Errno::ENOENT` when the binary is not on
  # PATH, and nothing turned that into one -- so `gate` on a machine
  # without `gitleaks` died mid-run, naming neither the tool nor what to
  # do about it. The pre-push hook already states the rule this follows:
  # a scan that cannot run is not a clean scan, so it refuses rather than
  # passing.
  def delegate(*command, chdir: ROOT, why:)
    begin
      out, status = Open3.capture2e(*command, chdir: chdir)
    rescue Errno::ENOENT
      raise Refused, "`#{command.first}` is not installed, so this step cannot run #{command.join(' ')}.\n" \
                     "  #{INSTALL.fetch(command.first, "Install #{command.first}")}, then run this again.\n" \
                     "  A step that could not run is not a step that passed."
    end
    out = out.dup.force_encoding(Encoding::UTF_8).scrub("?")
    return out if status.success?

    raise Refused, "#{why}\n  #{command.join(' ')} said:\n#{relay(out)}"
  end

  # **The lines that name a failure, and then the tail.**
  #
  # This relayed the last twenty lines and nothing else, so a preflight
  # that failed three checks showed the tail of the third and named
  # neither of the others -- and the refusal's own "its own output says
  # which check" was not true of what it had shown. The only way left to
  # learn which checks failed was to run preflight again, which is
  # fifteen minutes.
  #
  # The tail is kept because a command with no summary of its own says
  # why at the end; the named lines are added in front of it because a
  # command that does summarise puts that summary out of the tail's
  # reach.
  SUMMARY = /FAILED|\A=== |\A\s*\d+ (?:of|examples?)\b|refused|not caught/i

  def relay(output, tail: 20)
    lines = output.rstrip.lines
    named = lines.grep(SUMMARY)
    shown = (named + lines.last(tail)).uniq

    shown.map { |line| "    #{line.rstrip}\n" }.join
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
    refuse_off_main
    if branch_exists?("release/#{version}")
      raise Refused, "`release/#{version}` already exists, so #{version} has been opened.\n" \
                     "  Run: git checkout release/#{version}  — and `ruby scripts/release.rb status` " \
                     "says how far it got."
    end

    git("checkout", "-q", "-b", "release/#{version}")
    document = write_record(version)
    entries = targeted(version)
    write_changelog_skeletons(version, entries)

    puts "release: on release/#{version}."
    puts "  #{document} records it, and names the branch."
    puts "  both changelogs carry a #{version} section with #{entries.length} bullet(s) to write."
    # Said here rather than by `bump`'s failure: `check_site_links.rb`
    # requires a roadmap section per shipped version, and `bump` runs it
    # *after* rewriting eight files. The requirement belongs with the
    # other things to write, not after the edit.
    puts "  site/roadmap.html and site/ja/roadmap.html each need a #{version} section before `bump`,"
    puts "  and docs/ROADMAP.md + .ja.md are what they are counted against."
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
    # `%03d`: the width is what `agents_card_spec`'s task-file pattern,
    # the map's "highest-numbered NNN-*.md" and
    # `check_release_pointers.rb`'s lexical sort all rest on. An
    # unpadded `60-` sorts after `061-` for ever.
    next_number = format("%03d", numbers.max.to_i + 1)
    relative = File.join("docs", "design", "tasks", "#{next_number}-#{version}-what-this-release-is-for.md")

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

  # A release is cut from what has shipped, and **that is a statement
  # about a commit, not a branch name.**
  #
  # This asked the name first and returned on `main` without comparing
  # anything, so a local `main` nobody had pulled cut -- and would have
  # published -- a release missing whatever had merged. The other half
  # was unreachable: `git` already turns a failed `rev-parse` into
  # `Refused`, and the `rescue Refused; raise` in front of the catch-all
  # re-raised it, so the remedy that branch existed to print was never
  # printed. One rule now, and both ends of it say what to run.
  def refuse_off_main
    here = branch
    shipped = origin_main
    return if git("rev-parse", "HEAD").strip == shipped

    raise Refused, "`#{here}` is not what has shipped, and a release is cut from that.\n" \
                   "  #{remedy_for(here, shipped)}"
  end

  # **Which way it is wrong decides what clears it.** The refusal named
  # `git pull` in both directions, and a pull cannot clear a branch that
  # is *ahead* of `origin/main` -- there the commits have to land on
  # `main` first, by the pull request every other change goes through, or
  # be given up deliberately.
  def remedy_for(here, shipped)
    if ancestor?(git("rev-parse", "HEAD").strip, shipped)
      "Run: git checkout main && git pull"
    elsif ancestor?(shipped, git("rev-parse", "HEAD").strip)
      "`#{here}` has commits origin/main does not. Merge them into main by pull request first, or " \
        "give them up with `git reset --hard origin/main` if they are not wanted."
    else
      "`#{here}` and origin/main have each moved. Reconcile them on main before cutting a release."
    end
  end

  def ancestor?(earlier, later)
    RepoFiles.run(ROOT, "merge-base", "--is-ancestor", earlier, later, out: File::NULL, err: File::NULL)
  end

  def origin_main
    out = RepoFiles.capture(ROOT, %w[rev-parse origin/main])
    unless $?.success?
      raise Refused, "this clone has no `origin/main`, so what has shipped is not something it can " \
                     "point at.\n  Run: git fetch origin"
    end

    out.strip
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

  # No rescue. `targeted` has just parsed the same register, so a failure
  # here is a failure there too -- the branch could only have turned
  # every title into "TODO" and let the release carry on, which is the
  # swallowed failure `docs/DEVELOPMENT.md` refuses.
  def entry_titles(version, entries)
    bodies = DeferredFindings.bodies(DeferredFindings.register(ROOT)).to_h
    entries.keys.map { |number| [number, bodies[number].to_s.lines.first.to_s.strip] }
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
    puts "  nothing is committed. Read `git diff`, commit the bump, then: ruby scripts/release.rb gate"
    puts "  (gate refuses a dirty tree, so that what it gates is what publish sends.)"
    0
  end

  # A **patch** may move no capability row, and a **minor** may not leave
  # a user-visible defect unrouted. Both questions are asked of the
  # documents that own them rather than answered here.
  def refuse_unshaped_release(version)
    return refuse_moved_capabilities(version) if patch?(version)

    unrouted = DeferredFindings.open_entries(DeferredFindings.register(ROOT)).select do |_, fields|
      fields["kind"] == "defect" && fields["user-visible"] == "yes" && fields["target"].to_s.empty?
    end
    return if unrouted.empty?

    raise Refused, "#{version} adds capability, and #{unrouted.length} user-visible defect(s) name no " \
                   "release:\n  #{unrouted.keys.join(', ')}\n" \
                   "  Route each with `ruby scripts/issues.rb retarget <number> --to=V --why=\"...\"`."
  end

  def patch?(version) = version.split(".").last != "0"

  # **What makes a patch a patch.** `docs/PUBLISHING.md` grants a patch
  # the standing permission to ship without asking, and defines one as a
  # release where no capability row moves. Nothing checked that, so the
  # permission covered a release nobody had compared.
  #
  # Compared against the previous tag's copy of the document, which is
  # what "moved" means: added rows, removed rows, and changed statuses.
  def refuse_moved_capabilities(version)
    previous = previous_version(version) or return
    moved = moved_capability_rows(version, previous)
    return if moved.empty?

    raise Refused, "#{version} is a patch, and a patch moves no capability row. Against v#{previous}:\n" \
                   "#{moved.map { |line| "  #{line}" }.join("\n")}\n" \
                   "  Cut a minor instead, or put the row back."
  end

  def moved_capability_rows(version, previous)
    unless tagged?(previous)
      raise Refused, "v#{previous} is not in this clone, so what #{version} would be compared against " \
                     "is not here.\n  Run: git fetch --tags"
    end

    was = capability_rows(show("v#{previous}", CAPABILITY_DOC))
    now = capability_rows(File.read(File.join(ROOT, CAPABILITY_DOC), encoding: "UTF-8"))

    (was.keys | now.keys).filter_map do |id|
      next if was[id] == now[id]

      "#{id}: #{was.fetch(id, '(not there)')} -> #{now.fetch(id, '(gone)')}"
    end
  end

  CAPABILITY_DOC = File.join("docs", "EXTENSION_CAPABILITIES.md")

  # `| id | what the user does | what must happen | status |`, as
  # `{id => status}`. The same two fields `capability_coverage_spec`
  # reads, from one pattern rather than that file's two -- a third
  # grammar for this table is what `024.216` counted six of.
  CAPABILITY_ROW = /^\| ([A-Z]+\d+) \|[^|]*\|[^|]*\| ([^|]+) \|/

  def capability_rows(markdown) = markdown.scan(CAPABILITY_ROW).to_h { |id, status| [id, status.strip] }

  def show(ref, path)
    out = RepoFiles.capture(ROOT, ["show", "#{ref}:#{path}"])
    raise Refused, "cannot read #{path} at #{ref}: #{out.strip}" unless $?.success?

    out
  end

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

    unless dirty.empty?
      raise Refused, "the tree is not clean, and what is gated must be what is published:\n" \
                     "#{dirty}\n  Commit the bump, then run this again."
    end

    refuse_open_entries(version)
    report_stale_version_mentions(version)
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
    write_acceptance_into_record(version, number, reason)
    puts "release: #{number} accepted as not owed by #{version} — #{reason}"
  end

  # **And into the release's own record**, because `core/tmp/` is
  # untracked and goes with the machine. "This release does not owe
  # 024.N, because ..." is a decision, and a decision that survives only
  # in a scratch file reaches neither the record nor the next reader —
  # which is what the register exists to stop happening to findings.
  #
  # Above `## 残課題`, so it sits with the other outstanding-work prose
  # rather than after it.
  def write_acceptance_into_record(version, number, reason)
    path = release_record(version) or return

    body = File.read(path, encoding: "UTF-8")
    line = "- `#{number}` — accepted as not owed by #{version}: #{reason}\n"
    return if body.include?(line)

    # Under the heading if it is there, and only otherwise does the
    # heading get written. Inserting one per acceptance left a record
    # with two sections of one line each, which reads as two decisions
    # taken at two times rather than one list.
    File.write(path, body.include?(ACCEPTED_HEADING) ? add_to_accepted(body, line) : open_accepted(body, line))
  end

  ACCEPTED_HEADING = "## Accepted, and why"

  def add_to_accepted(body, line)
    body.sub(/^#{Regexp.escape(ACCEPTED_HEADING)}\n\n/) { "#{ACCEPTED_HEADING}\n\n#{line}" }
  end

  def open_accepted(body, line)
    owed = "## 残課題"
    return "#{body}\n#{ACCEPTED_HEADING}\n\n#{line}" unless body.include?(owed)

    body.sub(owed) { "#{ACCEPTED_HEADING}\n\n#{line}\n#{owed}" }
  end

  def release_record(version)
    Dir.glob(File.join(ROOT, "docs", "design", "tasks", "*-#{version}-*.md")).min
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

  # **It lists; it does not refuse**, and that is the whole of what this
  # check can honestly be.
  #
  # "Not history" was a judgement in the manual step. As "anywhere but
  # these four paths" it is wrong on this tree: the roadmap pages must
  # carry a section per shipped version, and `check_site_links.rb` --
  # which `bump` itself runs -- requires it, so refusing here made `bump`
  # demand what `gate` forbade. Driven on 0.3.4 it named five files and
  # every one was history. A refusal with that error rate is the check
  # `024.150` records being switched off; the same shape as preflight's
  # non-gating `ci:` line is what is left, and it is worth having.
  def report_stale_version_mentions(version)
    previous = previous_version(version) or return

    stale = stale_version_mentions(version)
    return if stale.empty?

    puts "release: #{stale.length} file(s) name #{previous}, which has shipped. Each is either history"
    puts "  or a sentence nobody updated — read them; this does not decide which:"
    stale.each { |path| puts "  #{path}" }
  end

  def stale_version_mentions(version)
    previous = previous_version(version) or return []

    RepoFiles.list(ROOT).reject { |path| path.start_with?(*HISTORY) }.select do |path|
      full = File.join(ROOT, path)
      File.file?(full) && !File.binread(full).include?("\0") &&
        File.read(full, encoding: "UTF-8").include?(previous)
    end
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
    accepted = state(version).fetch("accepted", {})
    owed = accepted.empty? ? "nothing open against #{version}" : "nothing open against #{version}, and:"

    [<<~TEXT.rstrip, *accepted.map { |number, reason| "      #{number} accepted — #{reason}" }].join("\n")
      #{version} gated on #{branch}
        versions agree: vscode/package.json, core/lib/ovallsp/version.rb
        changelog: both languages lead with #{version}
        register: #{owed}
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

  # **The comparison happens before the tag exists.** This tagged and
  # wrote the row first, so a disagreement between what was built and
  # what the Marketplace serves was found after the release had been
  # recorded as good — and a tag is the one thing here that must not be
  # rewritten, because the Marketplace artifacts reference its SHA.
  def record(served: nil)
    version = require_release_branch
    # **Before anything is written.** A second run appended a second
    # identical row and then failed on git's own "tag already exists" --
    # a side effect in front of a failure that named no remedy, in the
    # one step whose outputs must not be duplicated: the Marketplace
    # artifacts reference the tag's SHA, so republishing a tag breaks
    # them.
    if tagged?(version)
      raise Refused, "v#{version} is already tagged, so #{version} has been recorded. Its row is in " \
                     "docs/RELEASE_ARTIFACTS.md.\n  If it is wrong, fix the row and the tag by hand — " \
                     "this will not rewrite either."
    end

    vsix = Dir.glob(File.join(ROOT, "vscode", "*#{version}*.vsix")).first
    unless vsix
      raise Refused, "no VSIX for #{version} in vscode/. Run: ruby scripts/release.rb publish"
    end

    digest = Digest::SHA256.file(vsix).hexdigest
    published = served || fetch_published_digest(version)
    unless published == digest
      raise Refused, "what was built and what is served do not match:\n" \
                     "  built  #{digest}  (#{File.basename(vsix)})\n  served #{published}\n" \
                     # True because the guard above refuses a version already tagged, so this
                     # branch is only reachable while nothing has been recorded.
                     "  Nothing is tagged. docs/RELEASE_ARTIFACTS.md has the command that fetches it by hand."
    end

    append_artifact_row(version, digest)
    git("tag", "v#{version}")
    puts "release: #{File.basename(vsix)} is #{digest}, and that is what the Marketplace serves."
    puts "  The row is in docs/RELEASE_ARTIFACTS.md and v#{version} is tagged. Commit the row."
    puts "  Nothing is pushed."
    0
  end

  # The Marketplace serves the VSIX **gzipped**, which is the one step
  # that makes a naive `curl | shasum` disagree; `--compressed` is what
  # `docs/RELEASE_ARTIFACTS.md` records. `--served` is the same answer
  # obtained by hand, for a machine with no network.
  MARKETPLACE = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/teruz/" \
                "vsextensions/ovallsp/%<version>s/vspackage?targetPlatform=darwin-arm64"

  def fetch_published_digest(version)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "published.vsix")
      delegate("curl", "-sSL", "--compressed", "-o", path, format(MARKETPLACE, version: version),
               why: "the published artifact could not be fetched. Pass --served <sha256> instead, " \
                    "using the command in docs/RELEASE_ARTIFACTS.md.")
      Digest::SHA256.file(path).hexdigest
    end
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
      record [--served <sha256>] the artifact's hash and the tag, once it matches

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
    when "record" then record(served: option(argv, "--served"))
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
