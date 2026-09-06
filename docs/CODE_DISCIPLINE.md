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

**A wrong expectation written first is implemented faithfully** (`038`).
Before writing an expected value, establish its source:

- A claim about Ruby's semantics is taken from Ruby: run it, and paste the
  session, not prose about it (`scripts/check_interpreter_sessions.rb`, `024.220`).
- A claim about anything outside this tree — the client, the editor, the
  LSP specification — is a row in `docs/CLIENT_BEHAVIOUR.md` naming what
  shows it.
- A claim about this tree's own numbers is derived, not typed: a
  `measured:` marker with a deriver (`core/spec/meta/measured_claims_spec.rb`, `024.181`).

### Proof required by change type

| Change type | Required proof | What not to add |
|---|---|---|
| Diagnostics, types, resolution | Red reproduction on production path, positive control for true diagnostics, unit test, independent expected value | Tests echoing implementation; passing merely because false positive was silenced |
| State, concurrency, cache | Barrier/queue reproducing race order (stale generation, cancel, reopen) | Flaky sleep-based concurrency tests; lock existence string checks |
| Issue/release/meta scripts | Temp repository / fixture CLI I/O; non-mutation on failure; positive control | Raw regex checks asserting nothing |
| Performance | Identical input before/after; deterministic test catching redundant work; `# perf-guard: <why>` | Short wall-clock assertions replacing correctness; fixed sleep |
| Semantics-preserving refactor | Existing specs and diff verification; characteristic tests for missing invariants | Artificial RED solely for refactoring |
| Text, docs, links | Doc triggers / links guards; bilingual semantic parity | Throwaway unit tests for reversible prose |
| Public capabilities | Routed to minor release | Sneaking capability tests into a patch |

## Unpinned behaviour is a defect

A behavioural line that no test fails on when it is reverted is a defect,
whether or not the behaviour is correct. Verify it mechanically:
`scripts/hunk_sweep.rb` reverse-applies each hunk on its own and runs the
suite. A hunk adding a whole method only tests existence, so decisions
inside must be pinned separately.

An example whose fixture cannot distinguish candidate behaviours is
unpinned even though it passes. Prefer fixtures where each branch yields
a different observable answer, and name the mutation in
`core/spec/meta/pinned_mutations.yml` (`scripts/check_pinned_mutations.rb`, `024.109`).

An assertion that cannot fail is not a test: ask what would have to happen
for it to fail. `.not_to raise_error` against a method that swallows every
error asserts nothing (`027`).

## Code that deletes

- Contain destructive operations where deletion happens, not at callers.
  One function performs every removal and refuses paths outside its root;
  `cache_removal_containment_spec` holds the cache to it.
- Never pass a fabricated absolute path to code that deletes, not even in
  an example asserting it does nothing. Destructive code gets
  `Dir.mktmpdir`, always (`027`).

## Catching a failure and continuing is not the default

A swallowed failure produces the answer that would be right if nothing had
gone wrong. Every `rescue` in `core/lib` carries a verdict in
`core/spec/meta/rescue_verdicts.yml` (`scripts/check_swallowed_failures.rb`):

- `surfaces` — it raises, or reports through a channel a person sees.
- `contained: <why>` — the argument, at the site as well as in the file,
  that **no caller can turn the value into an assertion about the user's
  code**: `Types::UNKNOWN`, a `nil` every reader treats as "cannot say", a
  cache miss that recomputes (`024.122`).

## The simplest thing that could possibly work

Write the simplest construction that satisfies the requirement in front of
you, and let the next requirement change the shape:

- **It governs code being written.** Applied to code that works, a
  simplification is an ordinary change with an ordinary change's
  obligations (`048`).
- **Simpler means fewer places that must agree**, fewer invariants held by
  convention, fewer rules a reader must remember — not fewer lines.
- **Stop when adding the N-th place that must agree.** Patterns to avoid:
  information destroyed upstream and reconstructed downstream (`024.224`);
  redundant bookkeeping structures (`038`); a sentinel every reader must
  remember to check; caller-side guards instead of callee-side containment (`027`).
- **Centralising is not free.** One implementation only where every
  reader wants the same answer; where they want it *most* of the time,
  they do not (`024.47`).

## The design, not the symptom

- A local `if` that suppresses a symptom is not a fix. When a finding
  implies architectural deficiency, the architecture changes.
- A defect found while working on something else is fixed in place, in
  the same session (`022.2`).
- A design decision with a real trade-off is recorded as an ADR under
  `docs/design/adrs/`.

## A check's example is bait for the other checks

Every check scans tracked content, and a check is tracked content. In a
spec, build fixture paths and needles at runtime with
`core/spec/support/unspellable.rb`; in a comment, describe the shape and say
that you did (`024.126`). Never exempt the file.
