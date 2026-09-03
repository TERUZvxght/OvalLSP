# Working rules

Section 0 of `docs/design/docs/01-product-requirements.md` is the trusted
root, and this is it in one paragraph so that a lost pointer is not a lost
purpose: Ruby's LSP support is weak enough that every guarantee falls to
hand-written tests, and this product takes the basic half back — type
checking, and calls to methods that do not exist — so tests can narrow to
what they are for. 1.0.0 is where that is usable in practice, with Pylance
as the reference. A wrong answer is worse than no answer, but a 1.0.0 that
recedes forever is worse than either: a wrong answer on a path people walk
daily blocks a release, one on a path almost nobody walks ships as a known
limitation, and when you cannot tell, measure the frequency. None of that
is a licence to decide freely and stop reporting. Every rule here serves
section 0 and changes when they disagree; 0.6 says how to check one.
Absolute: section 0, and ordinary safety obligations — personal data, the
extension's own data, the user's machine — named there or not.

## Where the rules are

This file is the card: the rules to hold in mind, one line each, with what
enforces it — *check*: `preflight` or CI fails; *judgement*: nothing does —
and the number of the record that holds its history. The documents behind
the lines carry the rest of the rules and the how-to; when to open them:

- Setting up, running the suites, committing, branching: `docs/DEVELOPMENT.md`
- Writing code, and what a test has to show: `docs/CODE_DISCIPLINE.md`
- Comparing two runs, driving a corpus, quoting a number: `docs/MEASURING.md`
- Asking for a review round, or running one: `docs/REVIEW_LOOP.md`
- Finishing any change a user could notice: `docs/DOCUMENTATION_MAP.md`
- Recording, triaging or closing an issue: `docs/ISSUES.md`
- Relying on the editor, the client or the LSP spec: `docs/CLIENT_BEHAVIOUR.md`
- Cutting or publishing a release: `docs/PUBLISHING.md`, `docs/RELEASE_CHECKLIST.md`
- What each version is for, and the road to 1.0.0: `docs/ROADMAP.md`, `docs/design/tasks/036-road-to-1.0.0.md`

## When a session starts

- Read section 0. Then `git fetch --all --prune` and read the
  highest-numbered `docs/design/tasks/NNN-*.md` on every branch whose name
  or record claims the release — list the directory; never trust a number
  written elsewhere. The current work, its findings and its decisions
  live there and nowhere else. *judgement*; 024.109, 028
- After a context compaction or handoff, re-read this file and anything
  under `.claude/` that applies. *judgement*
- Read `docs/design/tasks/042-second-enumeration.md` before touching code
  it names. *judgement*

## Writing code

- Test first, and watch the test fail before the implementation exists. A
  line no test fails on when reverted is a defect; `scripts/hunk_sweep.rb`
  finds them. *judgement*; 038, 058
- An expected value has a source: Ruby's behaviour is a pasted session, a
  fact about the editor or client is a row in `docs/CLIENT_BEHAVIOUR.md`,
  a number about this tree is a `measured:` marker with a deriver.
  *check* once written; 024.220, 024.181
- An example that claims to tell two behaviours apart names its mutation
  in `core/spec/meta/pinned_mutations.yml`. *check*; 024.109
- Every `rescue` in `core/lib` has a verdict in
  `core/spec/meta/rescue_verdicts.yml`: it surfaces, or no caller can
  turn the value into an assertion. *check*; 024.122
- Code that deletes is tested under `Dir.mktmpdir` and removes in one
  contained place. *check* for the cache, *judgement* elsewhere; 027
- Write the simplest construction for the requirement in front of you;
  simpler means fewer places that must agree, not fewer lines. Simplifying
  working code is an ordinary change. *judgement*; maintainer 2026-08-25
- Fix the design that allowed a defect, not the instance; fix what you
  find in passing, in the same session; build nothing speculative; a real
  trade-off gets an ADR. *judgement*; maintainer, 022.2

## Measuring

- One measurement at a time, in the foreground: each side prints its
  working directory and version first, both get the identical corpus, and
  the diff carries a control the change cannot move. *judgement*; 026
- A green suite is not a blast radius: a change to a name, encoding or
  key every component reads gets a corpus run. *judgement*; 033

## Documents and the record

- Before finishing a change a user could notice, walk
  `docs/DOCUMENTATION_MAP.md`'s trigger table. User-facing documents are
  bilingual; internal ones are one language. *check*, in part
- A new issue starts in `docs/ISSUES.md`'s intake, is driven, then gets a
  register entry in the legend's shape; the index is generated. *check*,
  in part; 024.130
- Promoting a finding — a target, a user-visible flag, a
  `KNOWN_LIMITATIONS` paragraph — means re-running its reproduction on the
  tree it is promoted into. *judgement*; 024.131
- A review round's findings go into the task file as the round produces
  them. Before reverting anything, grep the tree for it. *judgement*;
  024.109, 024.47
- An incident produces a check or a register entry, never a paragraph
  here; a new line has to fit this file's budget. *check*; 058

## Review loop

- A round closes when a reviewer that has not seen the change set, using
  a method the previous round did not — diff, drive, attack, reproduce —
  reports nothing. *judgement*; 028
- After three rounds that find defects, ship with the open findings
  recorded. During a loop, fix; do not add. *judgement*; section 0.4, 026
- The same place found in two consecutive rounds gets a mechanical
  countermeasure; a third time, roll the thread back and record the root
  cause. *judgement*; 024.15
- Tell a reviewer what a defect is — never what not to count, where to
  look, or that clean is expected. Before believing a falling count, run
  one neutral round. *judgement*; 024.36

## Branches, commits, releases

- One `release/<version>` branch per version, merged into `main` by pull
  request; other work takes a short-lived branch and a pull request too.
  Merged branches are kept. *check*; maintainer 2026-09-01
- `ruby scripts/preflight.rb` before every commit; `--list` says what it
  runs. Nothing personal in the tree or a commit message: no secret, no
  home path, a noreply address. *check*; 024.195, 028
- A patch ships without asking, provided the privacy checks named in
  `docs/PUBLISHING.md` ran and passed; a minor or major asks. *judgement*;
  maintainer 0.2.4, 024.231
