# Development Guidelines

- Never implement functionality speculatively or in advance. Apply the YAGNI principle rigorously, and implement only what is explicitly required for the current task.
- Write tests first: a test must be observed failing before the code that makes it pass is written. Behaviour that no test fails on when it is reverted counts as a defect. See `CLAUDE.md` for the full rule and for how to verify it mechanically.
- Proactively locate and consult Claude-specific source files and instructions, including `CLAUDE.md` and relevant files under `.claude/`, before beginning work, and follow any applicable guidance.
- Context compaction or a task handoff may omit project instructions. After every compaction/handoff, re-read `AGENTS.md`, `CLAUDE.md`, and relevant files under `.claude/` before resuming work.
