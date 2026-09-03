# 059 — Ordered procedures become single entry points

**Branch:** `worktree-agent-a5579789c19884cab`, an agent worktree cut
from `main` at the commit that fixed the bodyless-heading check at end
of file, then merged with `main` again once 058's rulebook restructure
landed there. It is not a `release/<version>` branch and claims no
version: the work here is tooling, and whichever release takes it names
it then. `AGENTS.md`'s branch line is the rule the naming answers to,
and `scripts/check_release_pointers.rb` only asks about branches spelled
`release/<x.y.z>`.

## Why

The maintainer asked on 2026-09-03 that a procedure with a fixed order
be guaranteed by a tool rather than by a person holding the order:
*"the version bump completes in one script; if something is unfinished
at that point, refuse and show it."*

The checks already existed. What did not exist was an entry point. The
order in which the four register decisions are made lives in
`docs/ISSUES.md`'s prose; the rule that a review round may not repeat
the previous round's method lives in `docs/REVIEW_LOOP.md`; the fact
that the previous round's method is written in a task document was known
only to whoever had read it. Every one of those is a fact this tree
already holds and nothing read.

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
  `docs/REVIEW_LOOP.md`'s countermeasure section prescribes replacing
  with one both readers use. The cost of disagreeing here would be
  promoting an item other than the one the list showed.
- **An intake item is a bullet plus its indented continuations, and its
  title is the first bolded run however many lines it takes.** The list
  holds two shapes: what `intake add` writes, and what a person writes
  by hand with the title wrapped across lines. The first reader here
  understood only the first shape and read `docs/ISSUES.md`'s own three
  items as none — a reader reporting exactly what a working one reports
  when the list really is empty. Both shapes now read as one list, and
  an example fails if the hand-written ones go missing again.
- **`close`'s state is the register's, and `review_round`'s is a file in
  `core/tmp/`.** That directory is already ignored, for the same reason
  the rspec JSON report is: a fact about this working copy at this
  moment belongs in no commit.
- **The Area is not checked for path existence.** `deferred_findings_spec`
  already asserts that every open entry's Area names a path that exists,
  and a second implementation of that rule in the writer would be a
  second thing to keep right. The cost is that a bad Area is reported by
  preflight rather than by the command.

## The tree moved under this work, and where the documentation went

Package A was written against `main` as it stood before 058's rulebook
restructure merged — a tree with no `docs/DEVELOPMENT.md`,
`docs/CODE_DISCIPLINE.md`, `docs/MEASURING.md` or `docs/REVIEW_LOOP.md`,
where those rules lived in `CLAUDE.md` and the trigger table had a
Japanese twin. The first pass therefore documented the round commands in
`CLAUDE.md`'s review-cadence section and the trigger rows in both
languages.

`origin/main` was then merged in, with the working code committed first
so the merge could not reach it. Three files conflicted and were
resolved as follows, and the content was carried across rather than
re-decided:

- `CLAUDE.md` — taken from `main`, which reduces it to an import of
  `AGENTS.md`. The paragraph about the round commands moved to
  `docs/REVIEW_LOOP.md`'s cadence section, where the rules it belongs to
  now live.
- `docs/DOCUMENTATION_MAP.ja.md` — `main` deletes it, and the deletion <!-- deleted -->
  was accepted. Its two edited rows exist only in the English table now,
  which is where 058 put the whole of it.
- `docs/DOCUMENTATION_MAP.md` — taken from `main`, and the three row
  edits re-applied on top of its rewritten rows.

`docs/DEVELOPMENT.md`'s "The register" section arrived in that merge
saying a register entry is written by hand. It is not, any more, and it
was rewritten here to name the two commands — which is the one place a
reader looking for "how do I open an entry" would land.

Two smaller things the brief assumed and this tree only acquired in that
merge: the intake list has items in it and a count sentence — both now
read and maintained — and `core/spec/meta/agents_card_spec.rb` exists,
replacing the pointer and restates specs the earlier tree had.

## What was watched failing, before it was written

- `core/spec/meta/issues_tool_spec.rb` — ten new examples, all ten
  failing against the tree as it stood (`invalid option: --area`, and
  `promote`/`close` not existing). The seven that were already there
  passed throughout.
- `core/spec/meta/review_round_spec.rb` — the whole file, on a
  `LoadError` for a script that did not exist.
- After the merge, three more in `issues_tool_spec.rb` for the intake
  list itself — the wrapped-title shape read as nothing, the two shapes
  counted as one list, and the count sentence restated. All three failed
  against the reader as it then stood, which is how the wrapped shape
  was found at all.

One of those first ten passed for the wrong reason and was repaired
before the code was: "refuses a position the intake list does not have"
was written with an invocation that was *also* missing
`--user-visible`, so it was the option parser refusing, under this
example's name. It now sends a valid invocation at a position past the
end.

**And each decision inside them is pinned separately**, because
reverse-applying a hunk that adds a whole method only shows the method
exists. Twenty-two entries were added to
`core/spec/meta/pinned_mutations.yml` — one per refusal, plus the
removals and restatements the two commands perform — and each was
applied to the tracked file and run against the example that names it.

**Three of the twenty-two were caught by that run and not by reading**,
and they are three different mistakes:

- the dirty-tree refusal and the published-paragraph refusal were
  mutated as `unless false`, which *inverts* a guard into always-refuse
  rather than removing it, so both examples passed under a mutation that
  pinned nothing;
- the mutation for where a new intake bullet goes passed because
  "above the sentence" was all the example asserted, and inserting *at*
  the sentence is also above it. The example now asserts the bullet
  joined the run and the blank before the sentence survived — which is
  the difference between one list and two.

The second of those is the case the manifest exists for: an example
whose fixture cannot distinguish the two candidate behaviours passes
under both, and no amount of reading finds it.

## The review rounds

### Round 1 — `diff`

An independent reviewer read the change set. Five findings.

| # | Finding | Disposition |
|---|---|---|
| 1 | HIGH — `scripts/review_round.rb` never requires `fileutils`, so every real `start` raised `uninitialized constant ReviewRound::FileUtils` at `record`. Twelve green examples stood over it, because the spec file requires `fileutils` at its own line 1 and so supplied what the script forgot. | Fixed. `require "fileutils"` at the top, and a new example runs the tracked script *as its own process* through `OVALLSP_REVIEW_ROUND_ROOT`, so the subject loads its own dependencies. That example is the countermeasure, not the require. |
| 2 | HIGH — `start` wrote the round heading before recording the state, so a crash between the two left a heading for a round that was never opened — and the next `start` refused that method as already used. | Fixed. State first, heading second, and a failed heading write removes the state. Two examples: `record` raising leaves the document unchanged, `append_round` raising leaves no state. |
| 3 | MEDIUM — `close` on a moved tree returned 1 and *kept* the state, while `start` refuses whenever a state exists. The loop stuck: `start` said "close it first", `close` said "it closes nothing", and the way out was deleting an untracked file nothing mentions. | Fixed. A round the index moved under is over: `close` forgets it, still exits 1, and says the next round starts fresh. |
| 4 | LOW-MEDIUM — the delegated guards ran with `out: File::NULL` and an ignored status, so a refusal's reason was discarded at the moment it was produced; the trailing `check` could then say `FAILED` and not why. | Fixed. One `delegate` runs them, captures the output, and refuses in the script's own words. |
| 5 | LOW — with the last item promoted the count sentence reads "**No items above; …**"; decide whether zero should return to the original "Empty, and emptied deliberately". | Decided: one sentence shape, always. The original wording is outside `INTAKE_COUNT`'s reach, so restoring it at zero would leave the next item to arrive under a sentence nothing could restate, and the count would go stale silently. An example now covers the zero case and asserts the sentence is still findable. |

### Round 2 — `drive`

The same reviewer ran both commands in a scratch copy of the tree turned
into a throwaway git repository. One finding, and the rest confirmed.

| # | Finding | Disposition |
|---|---|---|
| 1 | `intake add` did not restate the count, so the sentence `promote` maintains on the way out went stale on the way in — found while recording the `issue_index.rb` observation with the tool, as the round asked. It also appended below that sentence and its table, which is where "N items above" stops being true. | Fixed. `intake add` restates the count and inserts the bullet after the last item, and two mutations pin both halves. |
| — | `issues.rb intake` lists the three hand-written items; `promote 1 …` wrote the entry in the legend's shape, in numeric position before the roadmap entries, dropped the bullet, restated the count, and the three guards passed; `close … --released-in` set `status` and `released-in`, moved the entry to the archive, and `deferred_findings_spec`, `register_split_spec` and `issue_index_spec` passed on the result. | Confirmed, no change. |

The round also asked that the `scripts/issue_index.rb` observation be
recorded with the tool rather than only in this document. It is intake
item 4, added with `ruby scripts/issues.rb intake add` — which is how the
`intake add` defect above was found.

### Round 3 — `drive`

Both commands run end to end on a scratch copy of the round-2 commit,
turned into a throwaway repository. **No findings.**

| # | Finding | Disposition |
|---|---|---|
| — | `start diff` on a copy with no `core/tmp` opened round 3 and wrote the heading; `close` without a commit closed it; `start attack`, a commit under it, `close` refused with exit 1 and forgot the round; `start reproduce` then opened round 5; `status` read the state. | Confirmed, no change. |
| — | `intake` listed four items; `promote 1 …` wrote the entry in numeric position with the guards green and the sentence at "Three items above"; `close … --released-in=0.4.0` moved it to the archive; promoting the rest left the sentence at "No items above" and `intake` at "(nothing in intake)". `deferred_findings_spec`, `register_split_spec` and `issue_index_spec` passed on the result. | Confirmed, no change. |

Round 3 is the one that mattered for the round-4 findings below: it is
the run that emptied the copy's intake list, and the suite was then run
against that copy.

### Round 4 — `reproduce`

The claims of the previous rounds re-derived. `rspec --dry-run` gives
the recorded example count; `review_round_spec` passes; the mutation
manifest verifies. **Two claims did not survive**, both about examples
that depended on the state of a list this task's own tool exists to
empty.

| # | Finding | Disposition |
|---|---|---|
| 1 | MEDIUM — four examples in `core/spec/meta/issues_tool_spec.rb` copied the real `docs/ISSUES.md` and relied on its hand-written items being there. On a tree where `promote` has done its job the list is empty and all four fail, for a reason unrelated to what they test. | Fixed. The `before` block plants the list: one bullet in the shape `intake add` writes, one with the bold title wrapped across lines, and the sentence counting them. A fifth example reads the *real* document and asserts only what stays true whatever it holds — that it parses and no title comes back spanning lines. |
| 2 | MEDIUM — the mutation on `count_word` was reported as pinning nothing: the example asserted only that the sentence matches `INTAKE_COUNT`, whose first group is `\S+`, so a count rendered as a digit satisfies it. | Fixed, and it was worse than reported. On the emptied list the example's loop ran **zero times**, so it asserted a sentence no `promote` had written — an assertion that could not fail, in the example named for a claim. It now refuses to run on a list of fewer than two, promotes them, and asserts the words: `**No items above;`. |

Reproduced before either was touched, by emptying this tree's own intake
list with a script and running the suite against it: the same four
examples failed, at the lines the round named, and the applier reported
that one mutation not caught. Both were then re-run in that same state
after the fix — 24 examples, 0 failures, and

    all 1 new mutation(s) caught by the example that names it

— before the list was restored and the whole set re-run:

    all 22 new mutation(s) caught by the example that names it

**Two expectations were computing themselves from the subject** and were
rewritten in passing: the count examples asked `Issues.count_word` for
the word they then looked for, so a wrong `count_word` agreed with
itself. They spell "Two", "Three" and "One item" out, the singular
included.

## 残課題

未処理の指摘はこの文書ではなく `024` に書く。

## Package B

Not started. The changelog shape and its check, the trigger table as
data, the pre-push hook, and `scripts/release.rb` are the second half of
the brief, and begin in this worktree on the reviewer's go-ahead.
