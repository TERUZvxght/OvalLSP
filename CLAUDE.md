# CLAUDE.md

Project-specific instructions for working on OvalLSP (Ruby Semantic LSP: Core Server + VS Code extension + Rails Runtime Agent).

## What these rules are for

Every rule below is subordinate to two things, and exists to serve them:

1. **General safety obligations** — personal data, the extension's own
   data, the safety of the user's machine. Independent of the product
   vision; what shipping a product at all makes you responsible for.
   Done whether or not anything here or in section 0 mentions it.
2. **[`docs/design/docs/01-product-requirements.md`](docs/design/docs/01-product-requirements.md)
   section 0** — why this product exists, what "finished" means, and the
   principle that a wrong answer is worse than no answer *but letting
   1.0.0 recede forever in pursuit of accuracy is worse than either*.

**Section 0 is the trusted root; this file is not.** These rules were
each written after a real incident, which makes them hard to question and
is exactly why they need a root to be checked against. If following a
rule here starts working against section 0 — most often by making the
release recede — **the rule is what changes**. Section 0.6 says how to
check one, and how to write one without manufacturing a false rule from
a true instruction. An audit on 2026-08-18 found four passages in this
repository stating the project's own inferences in the maintainer's
voice; that is the failure this paragraph exists to prevent.

## Review cadence (mandatory)

**A round closes when a reviewer that has not seen this change set,
using a method the previous round did not use, reports nothing.** Method
is one of `diff` (read the change set), `drive` (run the product and
compare answers), `attack` (take one guarantee and try to break it),
`reproduce` (re-derive the round's own claims). Each round records which
it used; a closing round whose method repeats the previous round's closes
nothing.

**After three rounds that find defects, ship with the open findings
recorded** — register entry plus a user-facing paragraph in
`KNOWN_LIMITATIONS`. Section 0.4: letting 1.0.0 recede in pursuit of
accuracy is worse than the defects being pursued, and an unbounded loop
has no other outcome. The bound of three is this project's operational
choice, not a maintainer ruling.

**During a review loop, fix; do not add.** A capability a reviewer asks
for is a finding to record. A round reviews a fixed thing, and every
addition between rounds resets it.

**Departing from this rule is written down**, where the release is
recorded. Shipping under the bound above is the rule, not a departure.

*Why it is this and not "repeat until a round is clean": that form
measured reviewer exhaustion. 028 declares merge round 8 clean and the
next entry is an external reviewer finding two defects; eight rounds
followed, one a rollback. Around sixty rounds are recorded across 0.2.x.
Rewritten in 0.2.5 under section 0.6. The per-five-implementation-tasks
trigger is also gone: the last implementation task was 023.8, so it has
not been able to fire in over two hundred commits.*

## Test-first discipline (mandatory)

Write the test before the implementation, in this order:

1. Write a test that expresses the required behaviour and **watch it fail against the current code**. A test that has never been observed failing has not been shown to test anything.
2. Implement the change.
3. Confirm the test now passes, and that the rest of the suite still does.

Writing the fix first and then reverting it to check the new test still counts as verifying that one test — but it cannot reveal the more common problem below, so it is not a substitute for step 1.

### Unpinned behaviour is a defect in its own right

A behavioural line that no test fails on when it is reverted is a defect, and must be reported and fixed like any other — regardless of whether the behaviour itself is correct. Correct code with no test is one refactor away from being incorrect code with no test.

Verify this mechanically rather than by inspection: take the diff hunk by hunk, reverse-apply each behavioural hunk on its own, and run the full suite. Every hunk that leaves the suite green is unpinned. Do this before declaring a change set ready, and record the result.

Established after rounds 9–12 of independent review on the v0.1.5 change set: of the last six findings, four were not wrong behaviour but behaviour that could be reverted with the entire suite still green — including a one-line qualified-name guard whose removal would have made a view show a different controller's inferred types. Each was found only because a reviewer thought to mutate that specific line by hand.

The sweep has a blind spot worth knowing before trusting its number: reverse-applying a hunk that *adds a whole method* only tests that the method exists at all. It says nothing about the individual decisions inside it, because reverting the hunk removes the call site too. A `reset_budget: false` argument living inside such a hunk survived the sweep untested and was caught only by a later reviewer. Treat "N of M hunks pinned" as a floor, and for any hunk that introduces new code wholesale, pin its internal decisions separately.

Two further rules follow from that experience:

- Never run this hunk-by-hunk sweep while another agent is mutating the same working tree. Concurrent mutation invalidates both results. Sequence them.
- A spec whose fixture cannot distinguish the two candidate behaviours is unpinned even though it passes. Prefer fixtures where each branch of the decision yields a *different* observable answer (e.g. a block whose return type differs from the seed type, or two same-named classes in different namespaces), and assert the distinguishing value.

## A test that deletes things, and an assertion that could not fail (mandatory)

For six days, `bundle exec rspec` deleted the maintainer's installed
applications. `store_spec.rb` called

```ruby
described_class.prune_generations(cache_root: "/nonexistent-cache-root", current: "/x", keep: 2)
```

to check that an unreadable cache root does not raise. The unreadable
root was handled exactly as intended — and then the *second* half of the
same method aimed itself at `File.dirname("/x")`, enumerated `/`, found
more entries than it was told to keep, and removed all but the newest:
`/Applications` first. It stopped only because a protected path made
`remove_entry` raise. Identified by an Endpoint Security trace naming
`rspec` as the process unlinking `/Applications/*.app`; reinstalling
macOS had not helped, because re-cloning restores the cause.

Three rules, each of which alone would have prevented it:

- **An assertion that cannot fail is not a test.** `prune_generations`
  swallows every error by design, so `.not_to raise_error` against it was
  true before the method was written and would be true if it deleted the
  disk. Before writing an example, ask what would have to happen for it
  to fail; if the answer is "nothing", it is asserting nothing. This is
  the same defect as an unpinned behavioural line, arriving from the
  other direction — see "Test-first discipline" above.
- **Contain a destructive operation where the deletion happens, not at
  each caller.** Every call site here computed its own target and was
  individually plausible; containment was an emergent property of all of
  them being right at once, which is not a property. One function now
  performs every removal in that class and refuses a path outside the
  cache root, so no present or future caller can aim it elsewhere. An
  entry-point guard is the symptom's fix; this is the class's.
- **Never pass a fabricated absolute path to code that deletes.** The
  spec's `"/nonexistent-cache-root"` and `"/x"` were chosen to be
  obviously fake, which is what made them dangerous: `/x` does not exist,
  but `File.dirname("/x")` does, and it is the machine. Destructive code
  gets `Dir.mktmpdir`, always, including in the examples that assert it
  does nothing.

The wider lesson is about what "this test is safe" rests on. Nothing in
the example named a directory anyone cared about; the path from it to
`/Applications` ran through a `dirname` in another method. Reading the
test could not reveal that, and reading the method it called could not
either — only the two together.

## General implementation discipline (reaffirmed by Task 008.6)

- Fix the underlying design, not the symptom. A local `if` patch that suppresses a symptom without addressing the structural cause is not an acceptable fix in this codebase.
- When a review finding implies "the architecture allows this class of bug," fix the architecture, not just the reported instance.
- Every fix needs a regression test that fails without the fix — see "Test-first discipline" above for the order to write them in and for why passing that check alone is not enough.
- When you discover a bug, flaky test, or other fixable issue while working on something else in this repo, fix it in place, in the same session, immediately — do not spawn it off as a separate/background/recommended task. Established after a flaky mtime race in `core/spec/ovallsp/cache/store_spec.rb` was found mid-session during Task 022.2's verification loop and initially deferred via a spawned task instead of being fixed directly; the user explicitly redirected that this must not happen going forward. This applies regardless of whether the issue is related to the task currently in progress.

## Two rounds in a row on the same place: mechanise, then roll back (mandatory)

**A finding about the previous round's changes is not a problem.** A
round that repairs what the last one got wrong is the loop working. Keep
going.

What matters is **the same place** twice. Track, per round, *which code*
each finding is about — not merely whether it postdates the last round.
Then:

- **First time a place is found twice in a row:** do not hand-fix it a
  third time. Put in a **mechanical countermeasure** — something that
  makes that class of defect fail a check rather than wait for a
  reviewer. Then continue the loop normally. Examples of the right shape,
  from rounds that needed one:
  - two scanners that had to agree about the same text, replaced by one
    both read (0.2.1's `#structural_tokens`);
  - a literal-type table two inferencers kept diverging on, replaced by
    one table both read, with the spec driven from the table
    (`Types::LiteralTypes`);
  - a guard that could not see a finding parked outside its input, given
    the finding as input (`024.41`'s entry, so `deferred_findings_spec`
    enforces it).
  A countermeasure can also *fail*: 0.2.1 moved the type-name shadowing
  rule into resolution so its readers could not diverge, and that broke
  every bare name written from inside its own namespace — rolled back,
  024.47. Moving a rule to where the value is produced is only the right
  shape when every reader really does want the same answer.
  A regression test for the specific instance is *not* a countermeasure.
  It pins the one case and leaves the next one to a reviewer.

- **If the same place is found again after that**, the countermeasure was
  aimed at the symptom too. Stop the loop and roll back:

  1. **Roll back** the whole thread of changes those rounds produced —
     not the last one, the whole thread back to where it started.
  2. **Write down the root cause and the direction that was actually
     needed**, as an entry in
     `docs/design/tasks/024-deferred-review-findings.md`. Name the
     attempts and say why each was the wrong shape. That entry is the
     deliverable; the code change is not.
  3. **Re-scope**: the problem goes to its own release or its own task,
     and the current change set returns to what it was about.
  4. Only then resume the loop.

A correct fix does not need the next round to repair it; if it does, the
round after that will need repairing too, and the change set drifts while
every individual round looks productive. The counting rule is about
*place* rather than *recency* because a round whose findings are all new
ground is healthy however recently the code was written — 0.2.1's round
24 had four of ten about round 23's changes, and every one was a
different place.

Established after 0.1.12, where the index's ordering instability was
"fixed" in rounds 8, 9, 10 and 11 — each attempt bolting a sort onto one
more *reader* of a collection whose *storage* had no order. Round 8
pinned an accident, round 9 fixed two readers of seven with an unstable
sort, round 10 regressed round 9's fix, round 11 restored it. Four rounds,
zero net progress, and the release grew to 47 files and 2,463 added lines
— larger than 0.1.9, 0.1.10 and 0.1.11 combined. The thread was rolled
back and recorded as 024.15.

Two supporting rules follow from the same episode:

- **Do not tell a reviewer to assume the previous round broke something.**
  Doing that manufactures the self-referential findings this rule exists
  to detect, and hides the signal. Ask for defects; do not name where.
- **Centralising a rule into a type's constructor is not free.** 0.1.12
  moved three naming rules and an invariant into `Index::SymbolId`, and
  one of the rounds' regressions existed *only* because logic had moved
  into `initialize` (reading `kind:`/`name:` there silently made two
  required keywords optional). A module function that callers invoke is
  usually the cheaper form of "one place that knows the rule".

## How to ask for an independent review (mandatory)

The review loop above is only worth what the reviewer is allowed to find.
0.1.15 ran eight rounds whose defect counts fell 6, 3, 3, 2, 1, 1, 2, 0 —
and a control run of the last round, given round one's instructions
instead, found a user-visible regression the narrowed round had missed.
024.36 records the experiment.

**Do not narrow what counts as a finding.** Each of these was added to
0.1.15's prompts for a good local reason, and together they made the
count stop measuring anything:

- *"Re-finding a defect already recorded in `024.*` is not a finding."*
  The exclusion list grew from three entries to nine while the count was
  being read as convergence.
- *"Concentrate on X."* X is where the last round looked, not where the
  next defect is.
- *"A clean report is the expected outcome."* Say what a defect is; do
  not say what the answer should look like.

**Keep the corpus list, and never use it to exclude.** Tell a reviewer
what has been measured and at which revision — that is coverage. Telling
them to *avoid* those corpora is what let `delegate`'s missing parameters
through: the Rails gems were on the already-measured list, and the
release had moved seven commits since they were measured. A corpus is
measured against a revision, not for ever.

**Before believing a falling count, run one round neutral.** Same tree,
round-one instructions, plus: *report anything you consider a defect,
whether or not it looks already known or deliberate; if a decision
recorded as deliberate is the wrong decision, say so.* If the neutral run
finds more than the narrowed one, the decline was the instructions.

**A falling count is not evidence on its own.** It cannot distinguish
"fewer defects remain" from "fewer defects can be reported", and in
0.1.15 both were true at once. What it *can* be read against is user
impact: rounds 1–7 each found something that changed what the engine
answers; round 8 found five things and none of them did. That is the
signal worth acting on, and it is a different question from the count.

## A measurement is a claim, and it needs the same care as a test

Three corpus comparisons during the 0.2.x work produced confident false
results. None was subtle, each would have changed a decision, and the
count of findings each invented is recorded in
`docs/design/tasks/026-0.2.1-review-loop.md`:

- a diff computed from a file **still being written** — 79 invented;
- a diff between two runs over **different corpora**, one of which
  included this repository's own `core/lib` — 10 invented;
- a `cd` in a compound command that **persisted**, so both "before" and
  "after" ran from the same worktree — reported the fix as doing nothing.

Before reading any diff: confirm both sides finished, confirm both sides
were given the identical corpus, and confirm each side ran the code you
think it ran. Print the thing you are asserting rather than assuming it.

**Run one measurement at a time, in the foreground.** 0.2.1's last day
added two more to the list, and both came from backgrounding: a second
run started while the first was still alive, so two processes wrote the
same output files; and a rewritten script left both sides `cd`-ed into
the baseline tree, which is the third entry above happening again. Each
was caught before its numbers were read — the first because the totals
were implausibly low, the second because the two sides came out
*identical*, which contradicts a spec already watched failing. Neither
would have been caught by re-reading the numbers.

The cheap form of all of this: before starting, check no process of the
same kind is running; have each side print its own working directory and
version *before* it runs; and put a control in the diff — a category the
change cannot affect, which must come out equal. 0.2.1's control was
`unresolved-constant`, identical at 9,550 on both sides.

**A tool with the right name is not necessarily the tool under test.**
0.2.3's pre-publish gate reported that the packaged artifact's compiled
extensions embed the build machine's home path. The check was re-run by
hand to confirm, came back clean, and a register entry was filed saying
the gate's warning was blind. Both commands were the same text; the
gate's ran under `#!/usr/bin/env bash` and got `/usr/bin/grep`, while
the hand-run went through a shell where `grep` is a function wrapping
`ugrep`, which does not report matches in binary files without `-a`.
The entry was withdrawn. The general form: when you re-run a check to
confirm it, confirm you invoked the same implementation — `type -a`, or
just call the absolute path the script calls.

**A green suite is not a blast radius.** 0.2.5 changed one line in the
RBS type converter, ran the whole suite, found one failure, and recorded
the blast radius as measured. A corpus run then found a second
consequence immediately: the change made a nested *alias* capitalised,
which switched off a guard that told aliases from classes by their first
letter, and ordinary `"a.b".tr(".", "")` started being reported as an
error. No fixture called a selector-typed method on a known String, so
the suite could not have seen it. When a change alters something every
other component reads — a name, an encoding, a key — the suite measures
the radius it already has fixtures for. Drive a corpus.

**And when a measurement disagrees with a spec you have already watched
fail, the measurement is wrong until proven otherwise.** That is what
caught the third one; nothing about re-reading the numbers would have.

**A green suite is a measurement too, and it can be green because it did
not run.** `spec/e2e/capabilities_spec.rb` and
`spec/integration/real_rails_spec.rb` drive a real Rails application, and
without `rails ~> 8.1` and `sqlite3` installed as **local** gems they
skip in full while `rspec` still exits 0 — so a local run reports success
while the suite that decides whether a capability row is true never
executed. CI catches it ("Fail if the real-Rails or capability suites
were skipped instead of run"), which means it bites locally and nowhere
else. Before believing a green run, print the thing you are asserting:
run those two files and check the example count is non-zero, exactly as
the rule above says to do for a corpus diff. `CONTRIBUTING.md` carries
the install command.

## Documentation is part of the change (mandatory)

Before finishing any change a user could notice, open
[`docs/DOCUMENTATION_MAP.md`](docs/DOCUMENTATION_MAP.md) and walk its
trigger table. It lists every document that a given kind of change makes
stale — including the public site under `site/`, which is *not* generated
from the Markdown docs and therefore propagates nothing on its own.

Do not rely on remembering the list, and do not rely on a review agent to
find what was missed: that was the previous arrangement and it is why the
map exists. Read the file each time. It is short, and it names which
checks already enforce which pairs, so the parts a machine can catch are
marked as such.

Established after 0.2.0 shipped six capabilities without adding a single
row to `docs/EXTENSION_CAPABILITIES.md` — the document `docs/PUBLISHING.md`
defines a "capability" by — leaving the release's own version number
unjustifiable on the project's own terms until a reviewer caught it.

**A revert is the change most likely to leave documentation behind**, and
it is the one least likely to look like it needs a pass: the prose was
correct when it was written, and nothing about undoing a change announces
that it also undid the reason for a paragraph. 0.2.1 reverted its
resolution-side shadowing rule and left an unreferenced method, an inert
constructor parameter, stale comments in six places describing the
reverted arrangement as current, a published changelog bullet claiming
the reverted change as a fix — so the release shipped two bullets under
one heading contradicting each other about one behaviour — and a
`KNOWN_LIMITATIONS` section in both languages describing the rolled-back
arrangement instead of the shipped one, so users were told a limitation
that did not exist while the one that did went unmentioned. All of it was
found by re-measuring rather than by reading, across two releases; the
first inventory itself undercounted ("three comments") until 0.2.3
re-grepped. The cheap check is to **grep the tree for the thing being
reverted before committing the revert**, not after. 024.47 records the
full list.

## Where a release's work lives (mandatory)

A release's work in progress lives on a pushed branch, and the task
file on `main` that names the release also names that branch. A
pointer to a file that exists only on an unnamed branch is a pointer
to nothing for every session that cannot see the branch.

Starting or resuming release work begins with `git fetch --all
--prune`, listing the remote branches, and reading the
highest-numbered `NNN-*.md` on every branch whose name or record
claims the release — not only on `main`. When work moves between
branches, or a branch is renamed or renumbered, the record on `main`
moves in the same change.

Established by 0.2.3, which was prepared twice in parallel: 027 on
`main` said the work "continues in `028-0.2.3-review-loop.md`", that
file existed only on `fix/0.2.3`, nothing on `main` named that branch,
and a session starting from `main` rebuilt the release from the
pointer. The two preparations converged independently on several
identical corrections — worth something as evidence the corrections
were load-bearing, but bought with days of duplicated work. 028's "Two
preparations, one release" section records the merge and the
dispositions.

## Public repository privacy and secret handling

- This repository is public. Never commit or push secrets, credentials, tokens, private keys, private URLs, personal information, or personal email addresses.
- Treat Git author/committer metadata, generated artifacts, logs, fixtures, snapshots, and copied command output as possible disclosure paths, not only source files.
- Use an established public noreply address for commit metadata. Before every push, inspect the complete outgoing diff and commit range and run the repository's secret scan; stop rather than push if any sensitive or personal data may be present.

**One of these is now machine-checked, because the prose alone failed
twice.** 0.2.1's record named a scaffolded application by its absolute
path, and 0.2.3's pre-publish gate quoted the build machine's home
directory into a task document *and* a commit message — the second
channel being one the line above already names, which is the point: a
rule that lists disclosure paths does not make anyone see them. Per the
same-place rule, the third pass is a countermeasure.

`scripts/check_home_paths.rb` is the single detector, read by both places
that must agree about it: `core/spec/meta/home_path_guard_spec.rb` scans
tracked content on every suite run, and ci.yml's secret-scan job runs
`--messages` over commit messages, which no tree scan can see. Adding a
name to its `SYNTHETIC` list is a deliberate edit with a reason; an
unknown name fails. The script refuses a shallow clone rather than
scanning one commit and reporting the history clean.

Note what it does *not* do: it guards content arriving from here on, not
history. The instance already published in `main` stays, because
rewriting that history would orphan the `buildCommit` SHAs baked into the
0.2.1 and 0.2.2 VSIXs the Marketplace still serves — an integrity loss
for no privacy gain, since the name is the published Marketplace
publisher id in `vscode/package.json` regardless. That is a decision, and
`docs/design/tasks/028-0.2.3-review-loop.md` records it.
