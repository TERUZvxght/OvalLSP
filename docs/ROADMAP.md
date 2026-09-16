# Roadmap

[日本語版](ROADMAP.ja.md)

What each planned release lets you do, in the order a user notices it.

A version number here is a promise about *what arrives together*, not a
date. Patch releases normally have no feature rows: they announce nothing new,
so there is nothing to list here — but they are where a promise already
made gets kept, and a capability row can appear or turn ✅ in one. See
[`PUBLISHING.md`](PUBLISHING.md) for what each position means.

Capability items below correspond to README's matrix; the 0.4.1 repair checkpoint adds no capability row. The
reasoning behind each, and the Pylance features deliberately *not*
planned, are in
[`design/tasks/024-deferred-review-findings.md`](design/tasks/024-deferred-review-findings.md)
(024.R3).

## 0.4.0 — Refinements

- **Per-check severity settings.** `ovallsp.diagnostics.severities` lowers enabled checks to warning, information or hint, or suppresses them with none. Syntax errors can retain error. Removing overrides restores defaults; open and closed files refresh. Safe mode remains the default, with no public mode or unresolved-constant opt-in.
- **Auto-`require` insertion.** Explicit quick fixes for JSON, URI and Pathname in a supported plain Ruby file, including requests with no diagnostics. Rails, bundle/Ruby selector environments, name conflicts and uncertain syntax are declined. Stale CodeAction application is not guaranteed safe; obtain a fresh action after editing.
- **Signature help highlights the matching parameter.** Keywords match by name regardless of order; excess, unknown and ambiguous arguments have no highlighted range. See the [capability table](EXTENSION_CAPABILITIES.md) for S4, G20 and Q4.

## 0.4.1 — Performance, concurrency and test isolation (unreleased)

This patch records partial repairs to existing guarantees, not new capability promises.

- Share parsed trees and receiver types across diagnostic checks; retain index memos for body edits with unchanged inputs.
- Remove the outer-lock wait for workspace symbol search; retain internal synchronization and acknowledge remaining search cost.
- Isolate minimal Rails fixtures per example and permit the real Rails integration file to run in parallel; keep CI at one worker.

The 300ms re-analysis target, fully isolated inference state and cooperative cancellation remain unverified or unimplemented. Residual work on 024.38, 024.39, 024.45, 024.62, 024.71 and 024.137 remains open toward 1.0.0.

## 1.0.0 — Guarantees, not features

This release adds no capability. It removes the two
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

1. **0.4.1 (Performance, Concurrency & Test Isolation)**: Partial improvements described above; the six residual issues remain open toward 1.0.0.
2. **0.4.2 (Permitted Pendings & Core Type Model)**: Resolving the four permitted pendings (024.19 argument type evaluation, 024.47 namespaced core class shadowing, 024.13 reopened core classes, 024.224 RBS-only types) to achieve zero skipped specs.
3. **0.4.3 (Diagnostics Precision & Feature Path Unification)**: Eliminating false positive undefined-method reports over real gem source (024.76, 024.83), unifying internal query paths across hover, completion, and diagnostics (024.100), aligning union member diagnostics (024.88), and wiring gem RBS with stdlib types (024.321, 024.322).
4. **1.0.0 (Platform & Environment Guarantees)**: Automating multi-platform packaging and CI verification across Windows, Linux, and Intel Mac (024.R4), and verifying full workspace guarantees for plain Ruby projects (024.R1).

