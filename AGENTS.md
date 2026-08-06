# Development Guidelines

- Never implement functionality speculatively or in advance. Apply the YAGNI principle rigorously, and implement only what is explicitly required for the current task.
- Write tests first: a test must be observed failing before the code that makes it pass is written. Behaviour that no test fails on when it is reverted counts as a defect. See `CLAUDE.md` for the full rule and for how to verify it mechanically.
- When asking another agent for an independent review, do not tell it what not to count, where to concentrate, or that finding nothing is fine. Each of those narrows what it can report, and a falling defect count then measures the instructions rather than the code. See `CLAUDE.md` for the rule and 024.36 for the control run that established it.
- **Work in progress lives in `docs/design/tasks/`, not in a transcript.**
  The open findings of the current review loop are in the highest-numbered
  `NNN-*.md` there — 027 for 0.2.2, 026 for 0.2.1. Anything a reviewer
  reported and nobody has fixed exists only in that file; agent reports
  are not kept. Read it before deciding what to do next, and add to it
  before a long session ends.
- **A measurement that disagrees with a spec you have watched fail is
  wrong until proven otherwise.** Five corpus comparisons in the 0.2.x
  work produced confident false results — a file still being written, two
  different corpora, a `cd` that persisted so both sides ran the same
  code, two runs writing the same output files at once, and a tool that
  built the engine *without* the configuration the server uses. Each
  would have changed a decision. `CLAUDE.md` carries the rules that
  follow; `026-0.2.1-review-loop.md` records what each invented.
- **During a review loop, fix; do not add.** A capability a reviewer asks
  for is an entry in `024-deferred-review-findings.md`, not work to do
  before the next round. 0.2.1 ran nine rounds and seven found a defect
  in code the previous round had written.
- Proactively locate and consult Claude-specific source files and instructions, including `CLAUDE.md` and relevant files under `.claude/`, before beginning work, and follow any applicable guidance.
- Context compaction or a task handoff may omit project instructions. After every compaction/handoff, re-read `AGENTS.md`, `CLAUDE.md`, and relevant files under `.claude/` before resuming work.
