# CLAUDE.md

Project-specific instructions for working on OvalLSP (Ruby Semantic LSP: Core Server + VS Code extension + Rails Runtime Agent).

## Review cadence (mandatory)

After every 5 completed implementation tasks (docs/design/tasks/NNN-*.md, including sub-tasks like 008.5/008.6), before moving on to the next task:

1. Launch an independent subagent to do a full, critical review of the deliverables produced in that batch of 5 tasks.
2. Fix whatever the review finds.
3. Repeat step 1–2 until the independent review comes back clean (no findings).
4. Only then proceed to the next task.

This was established after Task 008.5 shipped without this gate and failed a later review (see Task 008.6, which was a corrective pass). Do not skip this cadence even under time pressure — it is the reason 008.6 was needed at all. Track progress against this cadence explicitly (e.g. via TaskCreate/TaskUpdate) so it isn't silently dropped across a long session or context compaction.

## General implementation discipline (reaffirmed by Task 008.6)

- Fix the underlying design, not the symptom. A local `if` patch that suppresses a symptom without addressing the structural cause is not an acceptable fix in this codebase.
- When a review finding implies "the architecture allows this class of bug," fix the architecture, not just the reported instance.
- Every fix needs a regression test that fails without the fix (verify via git-stash-revert) — this project's established discipline throughout Tasks 001–008.6.
- When you discover a bug, flaky test, or other fixable issue while working on something else in this repo, fix it in place, in the same session, immediately — do not spawn it off as a separate/background/recommended task. Established after a flaky mtime race in `core/spec/ovallsp/cache/store_spec.rb` was found mid-session during Task 022.2's verification loop and initially deferred via a spawned task instead of being fixed directly; the user explicitly redirected that this must not happen going forward. This applies regardless of whether the issue is related to the task currently in progress.
