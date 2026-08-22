# Development Guidelines

## Read this first, every time

**Why this project exists, and what "finished" means:**
[`docs/design/docs/01-product-requirements.md`](docs/design/docs/01-product-requirements.md)
section 0. It is short. Read it at the start of a session and again
whenever a task has run long.

In one paragraph, so that a lost pointer is not a lost purpose: Ruby/Rails
LSP support is markedly weaker than other languages', so every guarantee
falls to hand-written tests. This product takes the basic half back —
**type checking and calls to methods that do not exist** — so that tests
can narrow to what they are actually for, strengthening Ruby's
conventions rather than fighting them. **1.0.0 is where that becomes
usable in practice** and a Ruby/Rails engineer is measurably better off;
its scope is *make the foundation solid, with Pylance as the reference*.
Conveniences that are not load-bearing — completion candidates sorted
most-useful-first, say — are 2.x.x.

**Two things are absolute. Nothing else is.**

- **General safety obligations** — personal data, the extension's own
  data, and the safety of the LSP user's machine. This axis is
  *independent of* the product vision: it is what shipping a product at
  all makes you responsible for. **Anything ordinary decency requires is
  done whether or not section 0 mentions it**; finding no basis in
  section 0 is not a reason to skip it.
- **Section 0 itself** — the vision, the definition of finished, the
  scope, and the accuracy-versus-shipping principle.

**The distance to 1.0.0 is written down**, derived from those two and
nothing else: [`docs/design/tasks/036-road-to-1.0.0.md`](docs/design/tasks/036-road-to-1.0.0.md).
The release being prepared now is **0.3.0, on `feat/0.3.0`** — the first
release that may add capability, and the one every accuracy release so
far has been clearing the way for. Its scope is
[`docs/design/tasks/045-0.3.0-scope.md`](docs/design/tasks/045-0.3.0-scope.md).
0.2.13 shipped 042's D5, D10 and the parser's half of D2, and is recorded
in
[`docs/design/tasks/044-0.2.13-what-a-body-says.md`](docs/design/tasks/044-0.2.13-what-a-body-says.md).
**Read [`042`](docs/design/tasks/042-second-enumeration.md) before
touching anything it names.**
Read it when a session opens, so the path is seen rather than inferred —
an inferred path is what a compaction loses.

**Section 0 is the trusted root.** Everything else in this repository —
this file, CLAUDE.md, the task files, the register, the checklists — is
instruction stacked to fulfil it, *including the maintainer's own past
instructions*, which may have drifted or been dropped. When a rule and
section 0 disagree, section 0 wins and the rule is what changes. Section
0.6 states how to check a rule against it, and how to write one without
manufacturing a false one.

Given those two, the maintainer does not need to be asked about each
decision — that is their own position, and it is why a patch may ship
without them. **It is not a licence to decide freely and run on.** They
have asked explicitly that this not become that; the axes are what
judgement is measured against, not permission to stop reporting. A wrong answer is worse than no
answer, because the foundation's value is that it can be trusted — **but
letting 1.0.0 recede forever in pursuit of accuracy is worse than either**.
Nothing is perfect at first. So a wrong answer on a path people walk daily
blocks the release, one on a path almost nobody walks is recorded as a
known limitation and ships, and when you cannot tell which it is, *measure
the frequency* instead of estimating it. "It is a real bug" and "it is
worth fixing now" are different claims; treating them as one makes
everything top priority and ships nothing.

The maintainer's role in a session is to notice when an agent has gone a
long way in the wrong direction and correct the course toward that goal.
The single largest threat to it is context compaction dropping the goal
while the work continues — which is why it is written here rather than
carried in a conversation.


- Never implement functionality speculatively or in advance. Apply the YAGNI principle rigorously, and implement only what is explicitly required for the current task.
- Write tests first: a test must be observed failing before the code that makes it pass is written. Behaviour that no test fails on when it is reverted counts as a defect. See `CLAUDE.md` for the full rule and for how to verify it mechanically.
- When asking another agent for an independent review, do not tell it what not to count, where to concentrate, or that finding nothing is fine. Each of those narrows what it can report, and a falling defect count then measures the instructions rather than the code. See `CLAUDE.md` for the rule and 024.36 for the control run that established it.
- **Work in progress lives in `docs/design/tasks/`, not in a transcript.**
  The open findings of the current review loop are in the highest-numbered
  `NNN-*.md` there — and **check which branch you are on before trusting
  a number**. On `main` the highest is `031-0.2.4-workspace-trust.md`
  (the shipped security patch); the 0.2.5 foundation work and its
  `030-0.2.4-review-loop.md` live on `feat/0.2.5`. This line pointed at
  `030` from a branch that did not contain it, which is the dangling
  pointer the residency rule below exists to prevent — created, of all
  things, while fixing this same line. Anything a reviewer reported and
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
