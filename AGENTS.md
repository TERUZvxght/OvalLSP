# Development Guidelines

- Never implement functionality speculatively or in advance. Apply the YAGNI principle rigorously, and implement only what is explicitly required for the current task.
- Write tests first: a test must be observed failing before the code that makes it pass is written. Behaviour that no test fails on when it is reverted counts as a defect. See `CLAUDE.md` for the full rule and for how to verify it mechanically.
- When asking another agent for an independent review, do not tell it what not to count, where to concentrate, or that finding nothing is fine. Each of those narrows what it can report, and a falling defect count then measures the instructions rather than the code. See `CLAUDE.md` for the rule and 024.36 for the control run that established it.
- **Work in progress lives in `docs/design/tasks/`, not in a transcript.**
  The open findings of the current review loop are in the highest-numbered
  `NNN-*.md` there — 028 for 0.2.3. Anything a reviewer reported and
  nobody has fixed exists only in that file; agent reports are not kept.
  Read it before deciding what to do next, and add to it before a long
  session ends.
- **A measurement that disagrees with a spec you have watched fail is
  wrong until proven otherwise.** Three corpus comparisons in the 0.2.x
  work produced confident false results — a file still being written, two
  different corpora, and a `cd` that persisted so both sides ran the same
  code. Each would have changed a decision. `026-0.2.1-review-loop.md`
  records what each invented and what caught it.
- **A green `rspec` run can be green because the decisive suites did not
  run.** Without `rails ~> 8.1` and `sqlite3` as local gems,
  `spec/e2e/capabilities_spec.rb` and `spec/integration/real_rails_spec.rb`
  skip in full and the run still exits 0. Run those two files and check
  the example count before reporting a suite as passing. See `CLAUDE.md`
  and `CONTRIBUTING.md`.
- Proactively locate and consult Claude-specific source files and instructions, including `CLAUDE.md` and relevant files under `.claude/`, before beginning work, and follow any applicable guidance.
- Context compaction or a task handoff may omit project instructions. After every compaction/handoff, re-read `AGENTS.md`, `CLAUDE.md`, and relevant files under `.claude/` before resuming work.
