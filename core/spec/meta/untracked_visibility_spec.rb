# frozen_string_literal: true

require "tmpdir"
require "fileutils"
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
      system("git", "init", "-q", dir, out: File::NULL)
      FileUtils.mkdir_p(File.join(dir, "docs"))
      committed = unspellable("docs", "committed.md")
      brand_new = unspellable("docs", "brand_new.md")
      File.write(File.join(dir, committed), "# One\n")
      system("git", "-C", dir, "add", "-A", out: File::NULL)
      system("git", "-C", dir, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)
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
      system("git", "init", "-q", dir, out: File::NULL)
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
  it "is the only way this tree enumerates its own files" do
    needle = %w[ls files].join("-")
    offenders = RepoFiles.list(UNTRACKED_ROOT, "scripts/*.rb", "core/spec/meta/*.rb").filter_map do |rel|
      next if rel.end_with?("scripts/repo_files.rb")

      File.read(File.join(UNTRACKED_ROOT, rel), encoding: "UTF-8")
          .each_line
          .reject { |line| line.strip.start_with?("#") }
          .any? { |line| line.include?(needle) } ? rel : nil
    end

    expect(offenders).to be_empty,
                         "these enumerate the repository the old way, which cannot see a file " \
                         "until it is committed: #{offenders.join(", ")}. Use RepoFiles.list — " \
                         "or RepoFiles.tracked where the files are evidence that something happens " \
                         "rather than input to inspect (024.194)."
  end
end
