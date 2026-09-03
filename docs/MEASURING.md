# Measuring

A measurement is a claim, and it needs the same care as a test.
`AGENTS.md`'s "Measuring" lines point here. `026` catalogues the false
results this project has recorded, and each rule below is one of them.

## Before reading any comparison

- Confirm both sides finished. A diff computed from a file still being
  written invented 79 findings.
- Confirm both sides were given the identical corpus. A diff over two
  different corpora, one of which included this repository's own
  `core/lib`, invented 10.
- Confirm each side ran the code you think it ran. A `cd` that persisted
  in a compound command ran both sides from the same worktree and reported
  a fix as doing nothing.
- Confirm no other run of the same kind is alive. Two runs started
  together wrote the same output files, and a rewritten script left both
  sides in the baseline tree — both from backgrounding, both caught before
  the numbers were read: one because the totals were implausibly low, the
  other because the two sides came out identical.

The cheap form: check that no run of the same kind is in progress; have
each side print its own working directory and version *before* it runs;
and put a control in the diff — a category the change cannot affect,
which must come out equal (`unresolved-constant` in 0.2.1). One
measurement at a time, in the foreground.

`scripts/corpus_diagnostics.rb` prints its working directory, revision,
dirty count, corpus digest and loaded version, refuses an empty corpus,
and takes `--expect-control`, so a run reports on itself (`046`, C8).

## When a measurement disagrees with a spec

A measurement that disagrees with a spec you have already watched fail is
wrong until proven otherwise. That is what caught the third case above,
and re-reading the numbers would not have.

## A green suite is a measurement too

- **It is not a blast radius.** A one-line change to a name, an encoding
  or a key that every other component reads is measured only for the
  fixtures the suite has; drive a corpus. `033`: a nested alias
  capitalised, a guard switched off, and ordinary `String` calls reported
  as errors, with the suite green.
- **It can be green because it did not run.** Three suites skip in full
  without their local dependency while `rspec` exits 0;
  `docs/DEVELOPMENT.md` says which, and how the status is read.
- **A checker that cannot see the thing it checks reports what a working
  checker reports.** `scripts/check_pinned_mutations.rb`'s first run said
  every mutation escaped, because it had loaded the unmutated code. So
  every check here carries a control example that plants the thing it
  hunts, and a check that has only ever been seen passing is `024.109`.

## The tool with the right name

When re-running a check to confirm it, invoke the implementation it
invokes — `type -a`, or the absolute path the script calls. `028`: a
gate's `grep` and a shell's `grep` were different programs, and a register
entry was filed against a defect that did not exist.

## Sweeps that write into the tree

`scripts/hunk_sweep.rb` and `scripts/check_pinned_mutations.rb` both write
into tracked files and restore them. Never run either while another
process — another agent, a rebase, a corpus run — mutates the same tree:
a contaminated result reads exactly like a real one.
