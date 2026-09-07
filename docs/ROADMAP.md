# Roadmap

[日本語版](ROADMAP.ja.md)

What each planned release lets you do, in the order a user notices it.

A version number here is a promise about *what arrives together*, not a
date. Patch releases are absent by design: they announce nothing new,
so there is nothing to list here — but they are where a promise already
made gets kept, and a capability row can appear or turn ✅ in one. See
[`PUBLISHING.md`](PUBLISHING.md) for what each position means.

Every item below corresponds to a row in README's capability matrix. The
reasoning behind each, and the Pylance features deliberately *not*
planned, are in
[`design/tasks/024-deferred-review-findings.md`](design/tasks/024-deferred-review-findings.md)
(024.R3).

## 0.4.0 — Refinements

- **Per-check severity settings.** `ovallsp.diagnostics.severities` lowers enabled checks to warning, information or hint, or suppresses them with none. Syntax errors can retain error. Removing overrides restores defaults; open and closed files refresh. Safe mode remains the default, with no public mode or unresolved-constant opt-in.
- **Auto-`require` insertion.** Explicit quick fixes for JSON, URI and Pathname in a supported plain Ruby file, including requests with no diagnostics. Rails, bundle/Ruby selector environments, name conflicts and uncertain syntax are declined. Stale CodeAction application is not guaranteed safe; obtain a fresh action after editing.
- **Signature help highlights the matching parameter.** Keywords match by name regardless of order; excess, unknown and ambiguous arguments have no highlighted range. See the [capability table](EXTENSION_CAPABILITIES.md) for S4, G20 and Q4.

## 1.0.0 — Guarantees, not features

The only release on this page that adds no capability. It removes the two
asterisks in README's matrix instead:

- **Every platform we publish for is verified**, not just Apple Silicon —
  `darwin-x64`, `win32-x64`, `linux-x64` (024.R4).
- **A plain Ruby project is guaranteed**, not only a Rails one. Individual fixtures, including finite auto-require, verify parts of
  it; complete plain Ruby workspace coverage is still unverified (024.R1).

Until then, every ✅ in README's matrix means "verified on macOS Apple
Silicon, in a Rails project, with the bundled Core" — and nothing else is
promised.

### Intermediate trajectory toward 1.0.0 (the 0.4.x patch line)

Per [`PUBLISHING.md`](PUBLISHING.md), enhancements to performance, concurrency, and existing correctness guarantees do not introduce new capabilities and are delivered incrementally as patch releases rather than accumulated on an unreleased omnibus branch. The path to 1.0.0 proceeds in four focused steps:

1. **0.4.1 (Performance, Concurrency & Test Isolation)**: Resolving keystroke re-analysis latency on large files (024.45), eliminating environment deep copying in `scope_at` (024.38), narrowing index search lock contention (024.137), and isolating the mutable Rails test fixture to unblock suite parallelization (024.71).
2. **0.4.2 (Permitted Pendings & Core Type Model)**: Resolving the four permitted pendings (024.19 argument type evaluation, 024.47 namespaced core class shadowing, 024.13 reopened core classes, 024.224 RBS-only types) to achieve zero skipped specs.
3. **0.4.3 (Diagnostics Precision & Feature Path Unification)**: Eliminating false positive undefined-method reports over real gem source (024.76, 024.83), unifying internal query paths across hover, completion, and diagnostics (024.100), aligning union member diagnostics (024.88), and wiring gem RBS with stdlib types (024.321, 024.322).
4. **1.0.0 (Platform & Environment Guarantees)**: Automating multi-platform packaging and CI verification across Windows, Linux, and Intel Mac (024.R4), and verifying full workspace guarantees for plain Ruby projects (024.R1).

