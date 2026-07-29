# Roadmap

[日本語版](ROADMAP.ja.md)

What each planned release lets you do, in the order a user notices it.

A version number here is a promise about *what arrives together*, not a
date. Patch releases are absent by design: they add nothing, so there is
nothing to list — see [`PUBLISHING.md`](PUBLISHING.md) for what each
position means.

Every item below corresponds to a row in README's capability matrix. The
reasoning behind each, and the Pylance features deliberately *not*
planned, are in
[`design/tasks/024-deferred-review-findings.md`](design/tasks/024-deferred-review-findings.md)
(024.R3).

## 0.2.0 — Beyond the file you are looking at

- **Mistakes in files you have not opened are reported.** Today a
  diagnostic only exists for a file currently open in an editor, so an
  error three directories away is invisible until you happen to look at
  it.
- **Passing an argument of the wrong type is reported.** Today only the
  *number* of arguments is checked.
- **Reading an `@ivar` that is never assigned is reported.** Ruby returns
  `nil` rather than raising, so today nothing tells you — the view simply
  renders empty.
- **Hover and completion show the documentation.** Today hover says what
  a thing *is* and never what it is *for*, though the RDoc/YARD comment
  is right above the `def`.
- **Semantic highlighting.** Ruby's `foo` is ambiguous between a local
  variable and a method call on self; the engine already knows which and
  the editor does not. Covers ERB templates' Ruby regions too.

## 0.3.0 — Knowing what the gems define

- **Unknown methods are reported on classes that inherit from a gem** —
  `ApplicationController`, and so most controllers and jobs. Today the
  check is deliberately silent there, because reporting would mean
  guessing (024.R7).
- **Inlay hints.** The inferred types and parameter names appear in the
  code itself, not only when you hover.
- **Quick fixes for each diagnostic.** Define the missing method, correct
  the route helper name, fix the argument count.
- **Go to type definition** — jump to the class an expression evaluates
  to, rather than to the method being called.
- **Highlight the other occurrences** of the symbol under the cursor,
  within the file.
- **Call hierarchy** — callers and callees, navigable, instead of a flat
  list of references.

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
