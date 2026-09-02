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

- **Per-check severity settings**, so a check you disagree with can be a
  hint rather than a warning, or off.
- **Auto-`require` insertion.**
- **Signature help highlights the argument the cursor is in.**

## 1.0.0 — Guarantees, not features

The only release on this page that adds no capability. It removes the two
asterisks in README's matrix instead:

- **Every platform we publish for is verified**, not just Apple Silicon —
  `darwin-x64`, `win32-x64`, `linux-x64` (024.R4).
- **A plain Ruby project is guaranteed**, not only a Rails one. Most of
  the engine almost certainly works there today; nothing specifies or
  verifies it (024.R1).

Until then, every ✅ in README's matrix means "verified on macOS Apple
Silicon, in a Rails project, with the bundled Core" — and nothing else is
promised.
