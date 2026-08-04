# CLAUDE.md

Project-specific instructions for working on OvalLSP (Ruby Semantic LSP: Core Server + VS Code extension + Rails Runtime Agent).

## Review cadence (mandatory)

After every 5 completed implementation tasks (docs/design/tasks/NNN-*.md, including sub-tasks like 008.5/008.6), before moving on to the next task:

1. Launch an independent subagent to do a full, critical review of the deliverables produced in that batch of 5 tasks.
2. Fix whatever the review finds.
3. Repeat step 1–2 until the independent review comes back clean (no findings).
4. Only then proceed to the next task.

This was established after Task 008.5 shipped without this gate and failed a later review (see Task 008.6, which was a corrective pass). Do not skip this cadence even under time pressure — it is the reason 008.6 was needed at all. Track progress against this cadence explicitly (e.g. via TaskCreate/TaskUpdate) so it isn't silently dropped across a long session or context compaction.

The same clean-review gate applies whenever an independent review is explicitly requested, including release preparation and broad defect audits: run one or more independent subagents, fix every actionable finding, and repeat with a fresh independent review until a full round reports no findings. A single review pass is not sufficient when it finds defects.

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

## General implementation discipline (reaffirmed by Task 008.6)

- Fix the underlying design, not the symptom. A local `if` patch that suppresses a symptom without addressing the structural cause is not an acceptable fix in this codebase.
- When a review finding implies "the architecture allows this class of bug," fix the architecture, not just the reported instance.
- Every fix needs a regression test that fails without the fix — see "Test-first discipline" above for the order to write them in and for why passing that check alone is not enough.
- When you discover a bug, flaky test, or other fixable issue while working on something else in this repo, fix it in place, in the same session, immediately — do not spawn it off as a separate/background/recommended task. Established after a flaky mtime race in `core/spec/ovallsp/cache/store_spec.rb` was found mid-session during Task 022.2's verification loop and initially deferred via a spawned task instead of being fixed directly; the user explicitly redirected that this must not happen going forward. This applies regardless of whether the issue is related to the task currently in progress.

## Two rounds in a row on the same code: stop and roll back (mandatory)

If a review round's findings are mostly about **the previous round's own
changes**, and that happens **twice in a row**, stop the loop. Do not run
another round. Instead:

1. **Roll back** the whole thread of changes those rounds produced — not
   the last one, the whole thread back to where it started.
2. **Write down the root cause and the direction that was actually
   needed**, as an entry in `docs/design/tasks/024-deferred-review-findings.md`.
   Name the attempts and say why each was the wrong shape. That entry is
   the deliverable; the code change is not.
3. **Re-scope**: the problem goes to its own release or its own task, and
   the current change set returns to what it was about.
4. Only then resume the loop.

Two consecutive self-referential rounds is the signal that the fix is
aimed at a symptom. A correct fix does not need the next round to repair
it; if it does, the round after that will need repairing too, and the
change set drifts while every individual round looks productive.

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

## Public repository privacy and secret handling

- This repository is public. Never commit or push secrets, credentials, tokens, private keys, private URLs, personal information, or personal email addresses.
- Treat Git author/committer metadata, generated artifacts, logs, fixtures, snapshots, and copied command output as possible disclosure paths, not only source files.
- Use an established public noreply address for commit metadata. Before every push, inspect the complete outgoing diff and commit range and run the repository's secret scan; stop rather than push if any sensitive or personal data may be present.
