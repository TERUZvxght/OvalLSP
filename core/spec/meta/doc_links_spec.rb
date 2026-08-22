# frozen_string_literal: true

require "tmpdir"

# `046`'s C1. Every documentation path named in tracked content must
# resolve to a file that exists.
#
# The measured state before this landed, at `6bc31b9`: **19 citations
# across 17 files naming five task filenames that had never existed in
# any commit.** The whole `plugins/` subsystem and the public SDK
# document pointed at one of them. Every one lived in a *source comment*,
# so a checker that read only Markdown would have called this tree clean.
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

  it "all resolve to a file that exists" do
    output, ok = check
    expect(ok).to be(true), output
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
