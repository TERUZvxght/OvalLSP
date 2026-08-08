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

## 0.3.0 — Knowing what the gems define

- **Unknown methods are reported on classes that inherit from a gem** —
  `ApplicationController`, and so most controllers and jobs. Today the
  check is deliberately silent there, because reporting would mean
  guessing (024.R7).
- **`Article.all.` completes.** A `Relation` answers what it holds —
  `where`, `order`, `limit`, and the chain they build. Today hover names
  the type (`Relation[Article]`) and completion offers nothing, because
  nothing tells the engine what a Relation's own API is; the gem index
  above is what supplies it.
- **`self.` completes.** The methods callable on the object you are
  writing in. The same list a bare prefix already offers, after a dot.
- **Inlay hints.** The inferred types and parameter names appear in the
  code itself, not only when you hover.
- **Quick fixes for each diagnostic.** Define the missing method, correct
  the route helper name, fix the argument count.
- **Go to type definition** — jump to the class an expression evaluates
  to, rather than to the method being called.
- **Call hierarchy** — callers and callees, navigable, instead of a flat
  list of references.
- **Highlight the other occurrences** of the symbol under the cursor,
  within the file.
- **Completion of `@ivar` names** the moment you type the sigil.

## 0.4.0 — Refinements

- **Per-check severity settings**, so a check you disagree with can be a
  hint rather than a warning, or off.
- **Auto-`require` insertion.**
- **Signature help highlights the argument the cursor is in.**
- **No diagnostics about the line you are still typing on.** Typing `a.`
  above a line like `b = "str"` makes a program that *means*
  `a.b = "str"` — Ruby agrees, `ruby -c` says `Syntax OK` and running it
  raises `undefined method 'b='` — so the report is correct about text
  you have not finished writing. Removing it needs the edit position,
  and costs hiding a genuine error on the line under the cursor until you
  move away (024.41).

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
