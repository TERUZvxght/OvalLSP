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

Two rules follow from that experience:

- Never run this hunk-by-hunk sweep while another agent is mutating the same working tree. Concurrent mutation invalidates both results. Sequence them.
- A spec whose fixture cannot distinguish the two candidate behaviours is unpinned even though it passes. Prefer fixtures where each branch of the decision yields a *different* observable answer (e.g. a block whose return type differs from the seed type, or two same-named classes in different namespaces), and assert the distinguishing value.

## General implementation discipline (reaffirmed by Task 008.6)

- Fix the underlying design, not the symptom. A local `if` patch that suppresses a symptom without addressing the structural cause is not an acceptable fix in this codebase.
- When a review finding implies "the architecture allows this class of bug," fix the architecture, not just the reported instance.
- Every fix needs a regression test that fails without the fix — see "Test-first discipline" above for the order to write them in and for why passing that check alone is not enough.
- When you discover a bug, flaky test, or other fixable issue while working on something else in this repo, fix it in place, in the same session, immediately — do not spawn it off as a separate/background/recommended task. Established after a flaky mtime race in `core/spec/ovallsp/cache/store_spec.rb` was found mid-session during Task 022.2's verification loop and initially deferred via a spawned task instead of being fixed directly; the user explicitly redirected that this must not happen going forward. This applies regardless of whether the issue is related to the task currently in progress.

## Public repository privacy and secret handling

- This repository is public. Never commit or push secrets, credentials, tokens, private keys, private URLs, personal information, or personal email addresses.
- Treat Git author/committer metadata, generated artifacts, logs, fixtures, snapshots, and copied command output as possible disclosure paths, not only source files.
- Use an established public noreply address for commit metadata. Before every push, inspect the complete outgoing diff and commit range and run the repository's secret scan; stop rather than push if any sensitive or personal data may be present.
