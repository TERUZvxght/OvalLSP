# 059 — Ordered procedures become single entry points

**Branch:** `worktree-agent-a5579789c19884cab`, an agent worktree cut
from `main` at the commit that fixed the bodyless-heading check at
end of file. It is not a `release/<version>` branch and claims no
version: the work here is tooling, and whichever release takes it names
it then. `CLAUDE.md`'s "Where a release's work lives" is the rule the
naming answers to, and `scripts/check_release_pointers.rb` only asks
about branches spelled `release/<x.y.z>`.

## Why

The maintainer asked on 2026-09-03 that a procedure with a fixed order
be guaranteed by a tool rather than by a person holding the order:
*"the version bump completes in one script; if something is unfinished
at that point, refuse and show it."*

The checks already existed. What did not exist was an entry point. The
order in which the four register decisions are made lives in
`docs/ISSUES.md`'s prose; the rule that a review round may not repeat
the previous round's method lives in `CLAUDE.md`; the fact that the
previous round's method is written in a task document was known only to
whoever had read it. Every one of those is a fact this tree already
holds and nothing read.

## What package A did

Two commands became entry points, and each refuses rather than
defaulting.

### `scripts/issues.rb promote` and `close`

`promote <n>` takes the n-th item out of `docs/ISSUES.md`'s intake list,
allocates a number that has never been used, writes the entry in the
legend's shape, drops the bullet, and re-runs the register's three
guards. Every one of the four decisions `docs/ISSUES.md` names — kind,
release, area, direction — is a required option, and a `defect` or a
`friction` must also say whether a user meets it, with a reason when it
says no. A default for any of them would be an assertion about the
product made by a script, which is what `024.130` cost: a limitation
published in both languages that the product did not have.

`close 024.N --released-in V` sets the status, inserts `released-in:`,
moves the entry to the archive and re-indexes. It **refuses while
either language still publishes a paragraph for the finding**, and
prints both locations with line numbers.

Both go through the existing `Issues.rewrite` primitive, which is told
what the edit should cost and refuses one that costs anything else —
`024.225`'s shape, where a scripted edit pasted the preceding file in at
its anchor and the line count was the only symptom.

### `scripts/review_round.rb`

`start <method>` refuses a method the cadence does not define, refuses
the method the previous round used, refuses a tree that is not clean,
and refuses while a round is already open. It then records the index the
round reads, writes the round's heading and an empty findings table into
the highest-numbered task document on the branch, and prints what it
wrote. `close` refuses when the index moved under the round; `status`
says which round is open and whether it did.

The heading it writes is not spelled anywhere in this document, on
purpose. `latest_document` reads the highest-numbered file in
`docs/design/tasks/`, which is this one — so an illustration of a round
heading written here would be read back as a real previous round, in the
document describing the tool that would read it. `024.126`, arriving
through a record instead of through a spec.

## What was decided, where the brief left a choice

- **`--drop-paragraphs` removes the whole `##` section, not the marker
  line.** The brief's wording allowed either. Removing the marker alone
  leaves the limitation published *and* silences
  `deferred_findings_spec`'s "stops documenting a finding once it is
  fixed", which is this repository's commonest failure shape: the answer
  that would be right if nothing had gone wrong. Removing the paragraph
  but not its heading is the defect `scripts/check_bodyless_headings.rb`
  exists for, three times over. So the section goes — and a section that
  also publishes another finding is refused rather than removed, because
  only one of the two claims is being closed.
- **`promote` requires `--user-visible` on a `friction` as well as on a
  `defect`.** The brief named the defect case. The grammar demands both:
  `DeferredFindings.undocumented` excludes only `roadmap`, so a
  `friction` entry with no user-visible field is one the register
  requires a limitation paragraph for. A `roadmap` entry writes no such
  field, which is what the three open ones do.
- **`intake` now prints positions, and one enumeration answers both
  questions.** Listing the items and finding the n-th are the same
  question asked twice, and two scans of one text is the shape
  `CLAUDE.md`'s countermeasure section prescribes replacing with one
  both readers use. The cost of disagreeing here would be promoting an
  item other than the one the list showed.
- **`close`'s state is the register's, and `review_round`'s is a file in
  `core/tmp/`.** That directory is already ignored, for the same reason
  the rspec JSON report is: a fact about this working copy at this
  moment belongs in no commit.
- **The Area is not checked for path existence.** `deferred_findings_spec`
  already asserts that every open entry's Area names a path that exists,
  and a second implementation of that rule in the writer would be a
  second thing to keep right. The cost is that a bad Area is reported by
  preflight rather than by the command.

## What the brief said about this tree that is not true of it

Recorded rather than worked around, because the next reader of the brief
needs it.

- **The three rule documents the brief expects under `docs/` do not
  exist on this branch.** It names a development guide, a
  code-discipline document and a review-loop document. All three are new
  on `worktree-057-rulebook-cleanup`, which has not merged — so they are
  described here rather than named, because a citation of them would
  resolve to nothing on this branch and
  `scripts/check_doc_links.rb` is right to refuse one. (It said so on
  the first draft of this paragraph, which named them.) The rules the
  brief expected to find in them are in `CLAUDE.md` and `AGENTS.md`
  here, so package A's documentation went to the files that do exist:
  `docs/ISSUES.md` for the register commands, `CLAUDE.md`'s
  review-cadence section for the round commands, and
  `docs/DOCUMENTATION_MAP.md` + `.ja.md` for the trigger rows. When 057
  lands, those two passages move with the sections they sit in.
- **The intake list is empty, and carries no count sentence.** The brief
  describes keeping "N items above" current; this tree says "Empty, and
  emptied deliberately" and has no count to keep. Nothing was written to
  maintain a sentence that does not exist.
- **`core/spec/meta/agents_card_spec.rb` does not exist** either. It is
  named in package B's document list; `agents_pointer_spec.rb` and
  `agents_restates_spec.rb` are what guard `AGENTS.md` here.

## What was watched failing, before it was written

- `core/spec/meta/issues_tool_spec.rb` — ten new examples, all ten
  failing against the tree as it stood (`invalid option: --area`, and
  `promote`/`close` not existing). The seven that were already there
  passed throughout.
- `core/spec/meta/review_round_spec.rb` — the whole file, on a
  `LoadError` for a script that did not exist.

**And each decision inside them is pinned separately**, because
reverse-applying a hunk that adds a whole method only shows the method
exists. Twelve entries were added to `core/spec/meta/pinned_mutations.yml`
— one per refusal, plus the two removals `close` and `promote` perform —
and each was applied to the tracked file and run against the example that
names it. **Two of the twelve were caught by that run and not by
reading**: the mutation for the dirty-tree refusal and the one for the
published-paragraph refusal were written as `unless false`, which inverts
the guard into *always refuse* rather than removing it, so both examples
passed under a mutation that pinned nothing. Corrected to `unless true`
and re-run; all twelve are caught now.

## Noticed here, not fixed here

`scripts/issue_index.rb` scans the `<!-- documents: -->` marker with its
own pattern rather than through `DeferredFindings`, and that pattern
cannot express a sub-numbered entry. It is a third grammar for a marker
whose other two readers now share one — `#anchors` and the
`#anchored_numbers` added here. Nothing has gone wrong from it: no
sub-numbered entry is published today. It is not repaired in this change
set because unifying it would change what the generated index counts,
which is a measurement to make on its own rather than inside a tooling
change.

## 残課題

未処理の指摘はこの文書ではなく `024` に書く。

## Package B

Not started. The changelog shape and its check, the trigger table as
data, the pre-push hook, and `scripts/release.rb` are the second half of
the brief, and begin in this worktree on the reviewer's go-ahead.
