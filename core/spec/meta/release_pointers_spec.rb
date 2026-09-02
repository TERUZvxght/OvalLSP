# frozen_string_literal: true

require_relative "../../../scripts/check_release_pointers"

# **0.2.3 was prepared twice, in parallel**, because a task document on
# `main` pointed at a file that existed only on a branch nothing on `main`
# named. A session starting from `main` followed the pointer, found nothing,
# and rebuilt the release. `docs/design/tasks/028-0.2.3-review-loop.md`
# records the merge and what each preparation had independently corrected.
#
# `CLAUDE.md`'s "Where a release's work lives" is the rule that came out of
# it, and `docs/DOCUMENTATION_MAP.md` carries the row. Neither was checked:
# that row's "Checked by" column is one of eight reading as nothing at all.
# When this file was written, `release/0.3.1` existed on the remote and no
# document in the tree named it -- the same shape, one release later, with
# the rule in front of whoever created the branch.
RSpec.describe "scripts/check_release_pointers.rb" do
  # The document paths below are assembled at run time. Spelled out,
  # they are citations `check_doc_links.rb` resolves and fails on --
  # which is what happened to the first draft of this file, inside the
  # release that added the checker beside it.
  def doc(name) = unspellable("docs", "design", "tasks", name)

  root = File.expand_path("../../..", __dir__)

  # A version nothing in this repository will ever ship, so no example can
  # pass because the tree happens to contain the name.
  def unshipped = "release/9.9.9"

  it "reports a branch no task document names" do
    found = ReleasePointers.problems(branches: [unshipped], documents: { doc("probe-x.md") => "no mention" })

    expect(found.length).to eq(1)
    expect(found.first).to include(unshipped)
  end

  # The control, and it is what makes the example above mean something: the
  # same branch, named, produces nothing. A check that reported both would
  # be asserting that release branches may not exist.
  it "says nothing about a branch a task document names" do
    documents = { doc("probe-x.md") => "the work continues on #{unshipped} until it ships" }

    expect(ReleasePointers.problems(branches: [unshipped], documents: documents)).to be_empty
  end

  # Any document, not a particular one. The rule is that a session can find
  # the branch from the tree, not that a nominated file carries it.
  it "accepts the name from whichever document carries it" do
    documents = { doc("probe-a.md") => "unrelated", doc("probe-b.md") => unshipped }

    expect(ReleasePointers.problems(branches: [unshipped], documents: documents)).to be_empty
  end

  it "has nothing to say when no release branch is visible" do
    expect(ReleasePointers.problems(branches: [], documents: { doc("probe-x.md") => "" })).to be_empty
  end

  # The tree. A failure here is a release record to open, not a checker to
  # fix -- which is why it is its own example.
  it "finds every release branch in this checkout named by a task document" do
    branches = ReleasePointers.visible_branches(root)
    found = ReleasePointers.problems(branches: branches, documents: ReleasePointers.task_documents(root))

    expect(found).to be_empty, "check-release-pointers:\n  #{found.join("\n  ")}"
  end

  # A checker that can see no documents reports exactly what one seeing
  # agreement reports. This is the example that tells those apart. It does
  # not assert a branch count: a `git archive` extraction has none, and
  # demanding one would fail for a reader doing nothing wrong.
  it "is reading the real task documents, not an empty directory" do
    documents = ReleasePointers.task_documents(root)

    expect(documents.length).to be >= 20
    expect(documents.keys).to all(start_with(unspellable("docs", "design", "tasks") + "/"))
  end

  it "is invoked by preflight" do
    expect(File.read(File.join(root, "scripts", "preflight.rb"), encoding: "UTF-8"))
      .to include("check_release_pointers.rb")
  end
end
