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
- **And it lives on a named, pushed branch.** Before starting or
  resuming release work: `git fetch --all --prune`, list the remote
  branches, and read the highest-numbered task file on every branch
  whose name or record claims the release — not only on `main`. 0.2.3
  was prepared twice in parallel because a pointer on `main` named a
  file that existed only on a branch nothing named. `CLAUDE.md` has the
  rule; 028's "Two preparations, one release" records the episode.
- **Never write a real absolute home path into the tree or a commit
  message.** Write `$HOME`, `~`, or a description. This is machine-checked
  now, in both channels — `core/spec/meta/home_path_guard_spec.rb` for
  tracked content and ci.yml's secret-scan job for commit messages, both
  reading the one detector in `scripts/check_home_paths.rb`. The prose
  rule alone missed it twice, which is why the check exists; `CLAUDE.md`
  has the rule and what it deliberately does not cover.
- **Run the tool the thing under test runs.** 0.2.3 read a release
  gate's `grep` result in a shell where the name resolves to a `ugrep`
  wrapper that skips binary files, contradicted the gate, and filed a
  register entry against a defect that did not exist. `CLAUDE.md`'s
  measurement section carries this with the others.
- **A measurement that disagrees with a spec you have watched fail is
  wrong until proven otherwise.** The corpus comparisons that went wrong
  are catalogued in `CLAUDE.md`'s measurement section — read them before
  comparing anything. That copy is the one to keep current: this bullet
  used to carry its own list, which drifted out of agreement with it.
  `026-0.2.1-review-loop.md` records what each invented and what caught
  it.
- **During a review loop, fix; do not add.** A capability a reviewer asks
  for is an entry in `024-deferred-review-findings.md`, not work to do
  before the next round. 0.2.1 ran nine rounds and seven found a defect
  in code the previous round had written.
- **Two review rounds on the same place buys a mechanical countermeasure;
  a third buys a rollback.** Not a third hand fix, and not a regression
  test for the one instance — something that makes the class of defect
  fail a check. And when the countermeasure turns out to have been aimed
  at the symptom too, roll back the whole thread and write down the root
  cause; the entry is the deliverable, not the code. `CLAUDE.md` has the
  rule; 024.15 records the first time it fired.
- **A green `rspec` run can be green because the decisive suites did not
  run.** Without `rails ~> 8.1` and `sqlite3` as local gems,
  `spec/e2e/capabilities_spec.rb` and `spec/integration/real_rails_spec.rb`
  skip in full and the run still exits 0. Run those two files and check
  the example count before reporting a suite as passing. See `CLAUDE.md`
  and `CONTRIBUTING.md`.
- **A test that deletes must be given a temporary directory, never a
  fabricated absolute path.** `bundle exec rspec` emptied
  `/Applications` for six days because one example passed `current: "/x"`
  to cache pruning and `File.dirname("/x")` is `/`. The assertion was
  `.not_to raise_error` against a method that swallows every error, so it
  could not have failed. `CLAUDE.md` has the three rules; 027 records the
  incident.
- Proactively locate and consult Claude-specific source files and instructions, including `CLAUDE.md` and relevant files under `.claude/`, before beginning work, and follow any applicable guidance.
- Context compaction or a task handoff may omit project instructions. After every compaction/handoff, re-read `AGENTS.md`, `CLAUDE.md`, and relevant files under `.claude/` before resuming work.
