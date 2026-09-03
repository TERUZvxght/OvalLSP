# Code discipline

What a change has to show before it is believed. `AGENTS.md`'s "Writing
code" lines point here; this is the full rule behind each, with the number
of the record that established it.

## Test first, and know where the expectation came from

1. Write a test that expresses the required behaviour and **watch it fail
   against the current code**. A test never observed failing has not been
   shown to test anything.
2. Implement the change.
3. Confirm the test passes, and that the rest of the suite still does.

Writing the fix first and reverting it to see the test fail verifies that
one test and nothing else, so it is not a substitute for step 1.

**A wrong expectation written first is implemented faithfully.** `038`: a
spec asserted something Ruby does not do, the parser was written to match
it, and a working call was reported as unknown. So before writing an
expected value, establish its source:

- A claim about Ruby's semantics is taken from Ruby: run it, and paste the
  session, not prose about it. `scripts/check_interpreter_sessions.rb`
  re-runs every pasted session in the tree and re-runs no prose
  (`024.220`).
- A claim about anything outside this tree — the client, the editor, the
  LSP specification — is a row in `docs/CLIENT_BEHAVIOUR.md` naming what
  shows it.
- A claim about this tree's own numbers is derived, not typed: a
  `measured:` marker with a deriver, which
  `core/spec/meta/measured_claims_spec.rb` recomputes (`024.181`).

## Unpinned behaviour is a defect

A behavioural line that no test fails on when it is reverted is a defect,
whether or not the behaviour is correct. Verify it mechanically:
`scripts/hunk_sweep.rb` reverse-applies each hunk on its own and runs the
suite. Its blind spot: a hunk that adds a whole method only tests that the
method exists, so the decisions inside such a hunk are pinned separately.

An example whose fixture cannot distinguish the two candidate behaviours
is unpinned even though it passes. Prefer fixtures where each branch of
the decision yields a different observable answer, and name the mutation
in `core/spec/meta/pinned_mutations.yml` so that
`scripts/check_pinned_mutations.rb` can apply it and require the example
to fail (`024.109`).

An assertion that cannot fail is not a test: before writing an example,
ask what would have to happen for it to fail. `.not_to raise_error`
against a method that swallows every error asserts nothing (`027`).

## Code that deletes

- Contain a destructive operation where the deletion happens, not at each
  caller. One function performs every removal and refuses a path outside
  its root; `cache_removal_containment_spec` holds the cache to it.
- Never pass a fabricated absolute path to code that deletes, not even in
  the example asserting it does nothing. Destructive code gets
  `Dir.mktmpdir`, always.

`027` is why: for six days the suite emptied the maintainer's
`/Applications`, from an example that passed `"/x"` to cache pruning.

## Catching a failure and continuing is not the default

A swallowed failure produces the answer that would be right if nothing had
gone wrong. Every `rescue` in `core/lib` carries a verdict in
`core/spec/meta/rescue_verdicts.yml`, and
`scripts/check_swallowed_failures.rb` fails on one that does not:

- `surfaces` — it raises, or reports through a channel a person sees.
- `contained: <why>` — the argument, at the site as well as in the file,
  that **no caller can turn the value into an assertion about the user's
  code**: `Types::UNKNOWN`, a `nil` every reader treats as "cannot say", a
  cache miss that recomputes.

The test is not whether the failure is important but whether the fallback
lets a caller assert something. A failure to enumerate declines
(`024.122`). The arguments for `contained` are one author's, reviewed by
nobody else; a `contained` that turns out to be wrong is an ordinary
finding, and the verdicts file is where to record that it was.

## The simplest thing that could possibly work

The maintainer asked on 2026-08-25 that this be a working principle, so
that excess complexity stops being produced. Generalised: *write the
simplest construction that satisfies the requirement in front of you, and
let the next requirement change the shape.*

- **It governs code being written.** Applied to code that works, a
  simplification is an ordinary change with an ordinary change's
  obligations — a test watched failing, a corpus driven, a control in the
  diff. `048` audited ten subsystems, and every one of its eight
  proposals failed measurement.
- **Simpler means fewer places that must agree**, fewer invariants held by
  convention, fewer rules a reader must remember — not fewer lines.
- **Stop when adding the N-th place that must agree.** The shapes this
  tree has produced: information destroyed upstream and reconstructed
  downstream (`024.224`); N bookkeeping structures where one value would
  do (`038`); a sentinel every reader must remember to check (`024.223`);
  a guard at each caller instead of at the thing guarded (`027`).
- **Centralising is not free.** One implementation only where every
  reader wants the same answer; where they want it *most* of the time,
  they do not (`024.47`). A module function callers invoke is usually the
  cheaper form of "one place that knows the rule".

YAGNI answers *should this exist*; this answers *given it must, is this
its simplest form*. Both are asked.

## The design, not the symptom

- A local `if` that suppresses a symptom is not a fix. When a finding
  implies "the architecture allows this class of bug", the architecture is
  what changes.
- A defect found while working on something else is fixed in place, in
  the same session — the maintainer's explicit direction during `022.2`.
- A design decision with a real trade-off — not an implementation
  detail — is recorded as an ADR under `docs/design/adrs/`.

## A check's example is bait for the other checks

Every check scans tracked content, and a check is tracked content. An
example path, register number or needle spelled the way a real one is
spelled becomes a finding about the file that hunts it — twelve times in
one release (`024.126`). In a spec, build it at runtime with
`core/spec/support/unspellable.rb`; in a comment, describe the shape and
say that you did. Never exempt the file.
