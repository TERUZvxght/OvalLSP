# Measuring

A measurement is a claim, and it needs the same care as a test.
`AGENTS.md`'s "Measuring" lines point here. `026` catalogues the false
results this project has recorded, and each rule below is one of them.

## Measurement discipline

One measurement at a time, in the foreground. Before reading any comparison:

| Invariant | Verification | What a failure produces |
|---|---|---|
| Both sides finished | Check process completion and complete output | Incomplete diff / spurious findings |
| Identical corpus | Verify corpus digest / file list | Spurious findings from corpus divergence |
| Correct revisions | Each side prints its working directory and version *before* running | Comparing baseline against baseline |
| Isolation | Ensure no concurrent or background run writes to same paths | Contaminated numbers / race conditions |
| Control category | Put a category the change cannot move in the diff (e.g. `unresolved-constant`) | Silent measurement failure |

`scripts/corpus_diagnostics.rb` prints its working directory, revision,
dirty count, corpus digest and loaded version, refuses an empty corpus,
and takes `--expect-control` (`046`, C8).

## When a measurement disagrees with a spec

A measurement that disagrees with a spec you have already watched fail is
wrong until proven otherwise.

## A green suite is a measurement too

- **It is not a blast radius.** A one-line change to a name, an encoding
  or a key that every other component reads is measured only for the
  fixtures the suite has; drive a corpus (`033`).
- **It can be green because it did not run.** Suites skip without their
  local dependency while `rspec` exits 0; `docs/DEVELOPMENT.md` says which,
  and how status is verified.
- **A checker that cannot see the thing it checks reports what a working
  checker reports.** Every check carries a control example planting the
  thing it hunts (`024.109`).

## Tool invocations and isolation

- When re-running a check, invoke the exact implementation it invokes
  (`type -a`, or the absolute path) (`028`).
- Sweeps that write into the tree (`scripts/hunk_sweep.rb`,
  `scripts/check_pinned_mutations.rb`) must run in a clean, isolated tree
  with no concurrent writers. Execution instructions live in
  [`docs/DEVELOPMENT.md`](DEVELOPMENT.md).

## Performance measurement contract

- Compare identical workloads before and after on the same machine.
- Report CPU time, wall-clock latency (median and tail), and memory (RSS)
  separately; do not substitute one for another.
- Production LSP latency (save-to-publish, hover) must be measured through
  actual dispatch/LSP channels, not synthetic direct method calls.
- Never use wall-clock thresholds in unit specs without `# perf-guard: <why>`
  (`core/spec/meta/no_wall_clock_thresholds_spec.rb`).
