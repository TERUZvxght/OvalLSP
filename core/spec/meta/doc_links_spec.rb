# frozen_string_literal: true

require "tmpdir"

# `046`'s C1. Every documentation path named in tracked content must
# resolve to a file that exists.
#
# The measured state before this landed, at `6bc31b9`: **19 citations
# across 17 files naming five task filenames that had never existed in
# any commit.** The whole `plugins/` subsystem and the public SDK
# document pointed at one of them. Eighteen of the nineteen lived in a
# *source comment* and the nineteenth in that SDK document, so a checker
# that read only Markdown would have found one of them and called the
# rest of this tree clean. (`024.178`: this said "every one", which
# re-running the census does not support. The argument for reading `.rb`
# survives at 18 of 19.)
#
# `scripts/check_site_links.rb` had already bought this countermeasure
# for `site/` alone, and its header makes the argument: nothing else
# would notice a renamed page. This is the same argument for the other
# 101 documents, and by CLAUDE.md's rule the fourth occurrence buys the
# check rather than a fourth fix.
RSpec.describe "documentation links" do
  DOC_LINKS_SCRIPT = File.expand_path("../../../scripts/check_doc_links.rb", __dir__)

  # Every fixture path is assembled from parts, never written whole.
  # This file is tracked, so the checker scans it too: a path spelled
  # the way a real citation is spelled becomes a finding about the spec
  # that tests the checker. `024.126` is the class, and its rule is to
  # make the example unspellable rather than to exempt the file --
  # exempting this one would stop checking a file that does carry real
  # citations, and it carries three.
  DOC_LINKS_DIR = ["docs", "design", "tasks"].join("/")
  DOC_LINKS_NEVER = "#{DOC_LINKS_DIR}/999-never-#{"existed"}.md"
  DOC_LINKS_ONCE = "#{DOC_LINKS_DIR}/999-was-#{"here"}.md"

  def check(root: nil)
    env = root ? { "CHECK_DOC_LINKS_ROOT" => root } : {}
    output = IO.popen(env, ["ruby", DOC_LINKS_SCRIPT], err: %i[child out], &:read)
    [output, $?.success?]
  end

  # A throwaway repository is the only honest fixture for a checker that
  # asks git questions, and every example below needs the same three
  # commands.
  def init_commit(root)
    system("git", "init", "-q", root, out: File::NULL)
    system("git", "-C", root, "add", "-A", out: File::NULL)
    system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
           "commit", "-qm", "one", out: File::NULL)
  end

  it "all resolve to a file that exists" do
    output, ok = check
    expect(ok).to be(true), output
  end

  # Round 2 gutted this check by widening `SKIP`: inspection fell from
  # 537 files to 117, a dangling citation in a `core/lib` source comment
  # went unreported, and all four examples stayed green. `SKIP` was an
  # unpinned constant, and this file's headline claim — *source comments
  # are in scope, deliberately* — was one edit away from false.
  #
  # The floor is stated **per root** rather than as a total, so it is not
  # a number to keep updating: this check is worthless if it stops
  # reading any of these, and none will legitimately fall to zero. It is
  # also not a second copy of `SKIP` — it asserts coverage, which is the
  # property, rather than restating the exclusion, which is the
  # mechanism.
  it "reads every part of the tree it claims to, so narrowing its input is a failure" do
    output, ok = check

    expect(ok).to be(true), output
    %w[core vscode scripts docs site].each do |root|
      count = output[/coverage\.#{root}=(\d+)/, 1]
      expect(count).not_to be_nil, "the checker no longer reports coverage for #{root}:\n#{output}"
      expect(count.to_i).to be > 0,
                            "the checker inspected no file under #{root}/. Source comments are in scope " \
                            "deliberately — 18 of the 19 citations this was built for lived in them."
    end
  end

  # Relative links are the half this check did not have until round 1
  # measured it: 105 of them in tracked Markdown, including ten between
  # task files that cite each other constantly, while the header above
  # claimed "every documentation path named in tracked content".
  it "resolves a relative Markdown link against the citing file's own directory" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, DOC_LINKS_DIR))
      File.write(File.join(root, DOC_LINKS_DIR, "here.md"),
                 "A link to [a sibling](#{["999-absent", "md"].join(".")})\n")
      system("git", "init", "-q", root, out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)

      output, ok = check(root: root)

      expect(ok).to be(false), "a broken relative link was not reported:\n#{output}"
      expect(output).to include("999-absent")
    end
  end

  # `024.174`. The relative pass handed every link beginning `docs/` back
  # to the pass that resolves against the repository root, on the grounds
  # that it was already counted there — so for any document below the
  # root the checker validated a path the reader can never follow.
  #
  # The fixture distinguishes the two readings rather than merely
  # exercising one: the target exists at the root and does not exist
  # beside the citing file, so root-resolution reports green and
  # directory-resolution reports red. A fixture where both readings agree
  # would pass either way.
  it "resolves a relative link written as a docs path against the citing file's directory too" do
    Dir.mktmpdir do |root|
      target = unspellable("docs", "zz-target.md")
      FileUtils.mkdir_p(File.join(root, File.dirname(target)))
      File.write(File.join(root, target), "the one at the root\n")
      FileUtils.mkdir_p(File.join(root, DOC_LINKS_DIR))
      File.write(File.join(root, DOC_LINKS_DIR, "here.md"), "A link to [the target](#{target})\n")
      init_commit(root)

      output, ok = check(root: root)

      expect(ok).to be(false), "a docs-prefixed relative link was resolved against the root:\n#{output}"
      expect(output).to include(target)
    end
  end

  # `024.175`. Resolution asked the working tree, `File.file?`, and the
  # working tree answers for things this repository does not carry. The
  # instance that raised it was macOS: APFS folds case, so a citation
  # differing from the real filename only in case resolved here and was a
  # dead link on Linux and in GitHub's renderer — the local-green/CI-red
  # asymmetry `CLAUDE.md` already records for the real-Rails suites.
  #
  # Pinned by the *rule* rather than by that one instance, because the
  # instance cannot fail on a case-sensitive filesystem and the rule can:
  # a file present on disk but ignored by git is not a file a reader of
  # this repository has. Both are the same repair — resolve against the
  # enumerated list, which is byte-exact and is what git carries.
  #
  # Two targets, because the resolver has two call sites and one fixture
  # would leave the other unpinned. The linked one is a *sibling* link,
  # which the citation pattern cannot name at all, so only the relative
  # pass can report it.
  it "resolves only against files git carries, not whatever the working tree answers for" do
    Dir.mktmpdir do |root|
      cited = unspellable("docs", "zz-cited.md")
      linked = ["zz-linked", "md"].join(".")
      FileUtils.mkdir_p(File.join(root, DOC_LINKS_DIR))
      FileUtils.mkdir_p(File.join(root, File.dirname(cited)))
      File.write(File.join(root, cited), "on this disk, carried by nothing\n")
      File.write(File.join(root, DOC_LINKS_DIR, linked), "likewise\n")
      File.write(File.join(root, ".gitignore"), "zz-*.md\n")
      File.write(File.join(root, "note.md"), "A citation of `#{cited}`\n")
      File.write(File.join(root, DOC_LINKS_DIR, "here.md"), "A link to [a sibling](#{linked})\n")
      init_commit(root)

      output, ok = check(root: root)

      expect(ok).to be(false), "a path git does not carry resolved because the disk answered for it:\n#{output}"
      expect(output).to include(cited)
      expect(output).to include(linked)
    end
  end

  # `024.177`. The pattern could name a path only in an enumerated set of
  # `docs/` subdirectories, so a citation in any other one — including
  # any added tomorrow — was not merely resolved, it was never matched.
  it "names a citation in a docs subdirectory nobody enumerated" do
    Dir.mktmpdir do |root|
      absent = unspellable("docs", "guides", "zz-absent.md")
      File.write(File.join(root, "note.md"), "A citation of `#{absent}`\n")
      init_commit(root)

      output, ok = check(root: root)

      expect(ok).to be(false), "a citation in an unenumerated subdirectory was invisible:\n#{output}"
      expect(output).to include(absent)
    end
  end

  # And the same property stated as coverage rather than as one instance,
  # which is what stops the list growing back. The floor above says how
  # much of the tree the checker *reads*; this says how much of it the
  # checker can *refer to*. A document `CITATION` cannot name is one
  # whose citations from source comments no run will ever test, however
  # much was read looking for them — and under the enumerated pattern
  # that was a silent consequence of which directory a file was put in.
  #
  # Watched failing by planting a document the pattern cannot reach —
  # a lower-case `.md` outside `docs/` — which took it to 1.
  it "can name every document in this tree, so no citation of one goes unchecked" do
    output, ok = check

    expect(ok).to be(true), output
    count = output[/unnameable-documents=(\d+)/, 1]
    expect(count).not_to be_nil, "the checker no longer reports the pattern's reach:\n#{output}"
    expect(count.to_i).to eq(0),
                          "the citation pattern cannot name every document here, so citations of the ones " \
                          "it cannot name are unchecked. Widen it, or move the document:\n#{output}"
  end

  # The `<!-- deleted -->` marker is the one way a citation may resolve
  # to nothing, and its whole design is that it admits only a path some
  # commit in this history actually carried. If it ever degraded into a
  # blanket exemption, this tree would still pass and nothing would say
  # so -- the founding 19 citations were all names no commit had carried,
  # so a blanket marker is precisely the failure mode that reopens them.
  #
  # Built rather than read: a throwaway repository, one commit, and a
  # citation of a file that has never existed in it.
  it "still fails on a path no commit ever carried, even when the line is marked deleted" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "note.md"), "A citation of `#{DOC_LINKS_NEVER}` <!-- deleted -->\n")
      system("git", "init", "-q", root, out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)

      output, ok = check(root: root)
      expect(ok).to be(false), "the marker admitted a path no commit carried:\n#{output}"
      expect(output).to include(DOC_LINKS_NEVER)
    end
  end

  # The other half: the same repository, the same marker, on a path the
  # history *does* carry. Without this the example above would pass if
  # the marker stopped working entirely.
  it "admits a path that a commit carried and a later commit deleted" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, DOC_LINKS_DIR))
      File.write(File.join(root, DOC_LINKS_ONCE), "gone soon\n")
      system("git", "init", "-q", root, out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "one", out: File::NULL)

      FileUtils.rm(File.join(root, DOC_LINKS_ONCE))
      File.write(File.join(root, "note.md"), "Deleted `#{DOC_LINKS_ONCE}` <!-- deleted -->\n")
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@example.invalid", "-c", "user.name=t",
             "commit", "-qm", "two", out: File::NULL)

      output, ok = check(root: root)
      expect(ok).to be(true), output
      expect(output).to include("1 naming a deleted file")
    end
  end
end
