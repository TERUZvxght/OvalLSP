# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../../../scripts/repo_files"

# `024.147`. Every check in this tree enumerated its input with `git
# ls-files`, which lists **tracked** files only — so a file you have just
# written is invisible to all of them until `git add`. And
# `scripts/preflight.rb`, the gate that exists to be run *before* a
# commit, runs in exactly that window.
#
# The consequence, stated plainly: **the suite could be green before a
# commit and red after it**, having examined different sets of files.
# 0.2.14 shipped that. `release_gate_spec.rb`'s planted example passed
# while the file was untracked and failed the moment it was committed,
# and the commit message says "2,374 examples, 0 failures" because that
# is what the run reported.
#
# Demonstrated before it was fixed: an untracked Markdown file carrying a
# duplicated heading *and* a citation of a document that has never
# existed passed both `duplicate_headings_spec` and `check_doc_links`,
# each reporting the tree clean.
#
# `RepoFiles.list` adds `--others --exclude-standard`, so a file git does
# not yet track but would not ignore is included, while anything a
# `.gitignore` really excludes stays out.
RSpec.describe "checks and a file that is not committed yet" do
  UNTRACKED_ROOT = File.expand_path("../../..", __dir__)

  it "RepoFiles sees a file git does not track" do
    Dir.mktmpdir do |dir|
      init_throwaway_repo(dir)
      FileUtils.mkdir_p(File.join(dir, "docs"))
      committed = unspellable("docs", "committed.md")
      brand_new = unspellable("docs", "brand_new.md")
      File.write(File.join(dir, committed), "# One\n")
      commit_throwaway(dir, "one")
      File.write(File.join(dir, brand_new), "# Two\n")

      listed = RepoFiles.list(dir, "docs/*.md")

      expect(listed).to include(committed)
      expect(listed).to include(brand_new),
                        "an uncommitted file is invisible again — the checks are blind in the window " \
                        "preflight runs in"
    end
  end

  it "still excludes what a .gitignore excludes" do
    Dir.mktmpdir do |dir|
      init_throwaway_repo(dir)
      File.write(File.join(dir, ".gitignore"), "ignored.md\n")
      File.write(File.join(dir, "ignored.md"), "# Ignored\n")
      File.write(File.join(dir, "kept.md"), "# Kept\n")

      listed = RepoFiles.list(dir, "*.md")

      expect(listed).to include("kept.md")
      expect(listed).not_to include("ignored.md")
    end
  end

  # The point of the fix is not that one helper behaves well; it is that
  # nothing enumerates the repository any other way. A check reintroduced
  # with `git ls-files` is this defect returning, and it returns looking
  # like ordinary code.
  #
  # The needle is assembled, not spelled: this file is one of the files
  # it scans, so a literal would make it report itself. `024.126`, sixth
  # occurrence, and the sixth time the same repair works — make the
  # example unspellable rather than exempt a file that carries real
  # matches.
  # **Scope.** This read `scripts/*.rb` and `core/spec/meta/*.rb` -- 51
  # files against 559 non-vendored ones -- while its own name said "the
  # only way *this tree* enumerates its own files". An enumeration in
  # `core/spec/support/`, `core/spec/ovallsp/`, `.github/workflows/`,
  # `vscode/` or the `Rakefile` was invisible to it, and moving a helper
  # into `core/spec/support/` is an ordinary refactor. `024.204`.
  #
  # Markdown is excluded, and that is a statement rather than a
  # convenience: a document cannot spawn a subprocess. Six tracked
  # documents discuss this very rule by name, and scanning them would
  # report the rule's own explanation as a violation of it -- which is
  # `024.126` arriving through the scope instead of through a literal.
  # Vendored and generated trees are excluded for the same reason as
  # everywhere else: they are not this project's code.
  UNTRACKED_EXCLUDED_PREFIXES = %w[core/vendor/ vscode/node_modules/ site/].freeze

  # Exactly one path, not a suffix. `end_with?("scripts/repo_files.rb")`
  # exempted `scripts/anything/repo_files.rb` too, when the file that
  # needs exempting has a known exact path -- the same entry.
  UNTRACKED_WRAPPER = "scripts/repo_files.rb"

  # Every file this guard reads: the tree, minus vendored trees, minus
  # prose, minus what it cannot read as text.
  def self.scanned_files
    @scanned_files ||= RepoFiles.list(UNTRACKED_ROOT).reject do |rel|
      rel.start_with?(*UNTRACKED_EXCLUDED_PREFIXES) || rel.end_with?(".md")
    end.select do |rel|
      absolute = File.join(UNTRACKED_ROOT, rel)
      next false unless File.file?(absolute)

      content = File.binread(absolute)
      !content.include?("\0") && content.force_encoding(Encoding::UTF_8).valid_encoding?
    end
  end

  # A line of `scripts/repo_files.rb` quoted as *data* -- the mutation
  # manifest's `from:`/`to:` for the one exempt file -- is not an
  # enumeration; nothing executes a YAML scalar. Taken from the manifest
  # rather than written out here, so the exemption cannot outlive the
  # entry it is about.
  def self.quoted_wrapper_lines
    @quoted_wrapper_lines ||= begin
      manifest = File.join(UNTRACKED_ROOT, "core/spec/meta/pinned_mutations.yml")
      entries = File.exist?(manifest) ? (YAML.safe_load(File.read(manifest, encoding: "UTF-8")) || []) : []
      entries.select { |e| e["file"] == UNTRACKED_WRAPPER }
             .flat_map { |e| [e["from"], e["to"]] }
             .compact.map(&:strip).reject(&:empty?)
    end
  end

  # `needles` are looked for in the line as written; `code_needles` in the
  # line with its string literals blanked out.
  #
  # The second list exists because of a real false positive this guard
  # produced on its first run: three error messages contain a Markdown
  # code span naming a git command, inside a Ruby string, which is prose
  # telling a human what to type and not a subprocess at all. Blanking
  # string literals separates the two, and it has to be a *second* pass
  # rather than the only one, because the quoted spawn forms are made of
  # string literals themselves and blanking would erase them.
  def self.offending_lines(rel, needles, code_needles = [])
    File.read(File.join(UNTRACKED_ROOT, rel), encoding: "UTF-8").each_line.select do |line|
      next false if line.strip.start_with?("#", "//")

      code = line.gsub(/"(?:\\.|[^"\\])*"/, '""').gsub(/'(?:\\.|[^'\\])*'/, "''")
      hit = needles.any? { |n| line.include?(n) } || code_needles.any? { |n| code.include?(n) }
      next false unless hit

      quoted_wrapper_lines.none? { |quoted| line.include?(quoted) }
    end
  end

  it "is the only way this tree enumerates its own files" do
    needle = %w[ls files].join("-")
    offenders = self.class.scanned_files.reject { |rel| rel == UNTRACKED_WRAPPER }
                    .select { |rel| self.class.offending_lines(rel, [needle]).any? }

    expect(offenders).to be_empty,
                         "these enumerate the repository the old way, which cannot see a file " \
                         "until it is committed: #{offenders.join(", ")}. Use RepoFiles.list — " \
                         "or RepoFiles.tracked where the files are evidence that something happens " \
                         "rather than input to inspect (024.194)."
  end

  # **And every git subprocess goes through the same wrapper**, because
  # `RepoFiles` is now where the environment scrub lives.
  #
  # `024.157`: git hands `GIT_DIR` and `GIT_INDEX_FILE` to every hook,
  # absolute in a linked worktree, and neither `chdir:` nor `-C`
  # overrides them. Three specs built a repository in `Dir.mktmpdir` and
  # ran `git add -A && git commit` in it; under a `preflight --install`
  # hook those commands wrote the throwaway tree into the *real*
  # repository's index and committed it -- deleting every tracked file
  # the throwaway did not have -- while the suite reported no failures,
  # because `RepoFiles.list` unions in `--others`, which enumerates the
  # filesystem and so came back with nearly the right answer from the
  # wrong repository.
  #
  # A forbidding text scan, not a proving one: a false negative here is
  # possible and a false positive is loud, which is the right way round
  # for this. What makes it worth having is that the spawn forms are few
  # and the containment is one function.
  # The needles are assembled, never spelled: this file is one of the
  # files it scans, so a literal spawn form written here would make the
  # example report itself. `024.126`, and the same repair as the
  # enumeration needle above.
  it "spawns no git subprocess that has not had its repository scrubbed" do
    quote = 34.chr
    git = "g#{"it"}"
    spawners = %w[system popen popen3 capture2 capture2e capture3 spawn]
    needles = spawners.flat_map { |s| ["#{s}(#{quote}#{git}#{quote}", "#{s}([#{quote}#{git}#{quote}"] }
    code_needles = ["#{96.chr}#{git} "]

    offenders = self.class.scanned_files.reject { |rel| rel == UNTRACKED_WRAPPER }
                    .select { |rel| self.class.offending_lines(rel, needles, code_needles).any? }

    expect(offenders).to be_empty,
                         "these spawn git without unsetting GIT_DIR and its family, so an inherited " \
                         "one aims them at another repository: #{offenders.join(", ")}. Go through " \
                         "RepoFiles.capture / .run / .spawn_args, or ThrowawayRepo for a temporary one."
  end

  # Neither example above can fail on an empty input, and 0.2.14's round 2
  # broke exactly that way: narrow the pathspecs to nothing and a clean
  # tree is indistinguishable from a tree nobody read. A floor well under
  # the current answer, so ordinary churn does not move it.
  it "reads most of this tree, so narrowing its input is a failure" do
    expect(self.class.scanned_files.length).to be >= 250
    expect(self.class.scanned_files).to include(UNTRACKED_WRAPPER, ".github/workflows/ci.yml",
                                                "core/spec/support/unspellable.rb",
                                                "core/spec/spec_helper.rb", "vscode/package.json")
  end

  # And the scrub has to work, not merely be present: git is asked, under
  # a poisoned `GIT_DIR`, which repository it is in.
  #
  # **The decoy has to have a tracked file of its own**, and the first
  # version of this example did not -- which made it pass with the scrub
  # deleted, and `check_pinned_mutations.rb` said so. `list` unions
  # `ls-files` with `ls-files --others`, and `--others` enumerates the
  # *filesystem* under `chdir:`, so the real file is found either way.
  # What only the poisoned index can produce is `decoy.md`: a path listed
  # as tracked that does not exist in the directory git was told to work
  # in. That asymmetry is the whole reason `024.157` stayed invisible --
  # the wrong repository gives nearly the right answer.
  it "answers about the directory it was given, not about an inherited GIT_DIR" do
    Dir.mktmpdir do |decoy|
      Dir.mktmpdir do |real|
        File.write(File.join(decoy, "decoy.md"), "# Decoy\n")
        throwaway_repo(decoy)

        init_throwaway_repo(real)
        File.write(File.join(real, "kept.md"), "# Kept\n")
        commit_throwaway(real, "one")

        listed = with_env("GIT_DIR" => File.join(decoy, ".git"),
                          "GIT_INDEX_FILE" => File.join(decoy, ".git", "index")) do
          RepoFiles.list(real, "*.md")
        end

        expect(listed).to eq(["kept.md"]),
                          "an inherited GIT_DIR was obeyed: git answered #{listed.inspect} about " \
                          "#{decoy} while it was told to work in #{real}"
      end
    end
  end

  def with_env(vars)
    previous = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end
end
