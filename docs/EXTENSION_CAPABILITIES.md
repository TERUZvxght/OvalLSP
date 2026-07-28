# Extension capabilities: what "working" means

[日本語版](EXTENSION_CAPABILITIES.ja.md)

This document exists because the extension shipped several versions in a
row that installed cleanly, started cleanly, reported healthy status, and
did almost nothing a user would notice. Every check we had answered a
question no user asks: does the process start, does the payload hash
match, does the suite pass. None answered *does completion produce items
when I type a dot*.

So this is the list of things that must actually work, phrased as what a
user does and what they must see. Each row is verified end to end against
a real Rails application by `core/spec/e2e/capabilities_spec.rb`, driving
the real Core over stdio the way the extension does — waiting for the
Runtime Agent and the cold index, then asking.

**A capability with no E2E row is not a capability. A capability whose
row is skipped is not shipped.** If a row cannot pass yet, it stays in
this document marked `NOT YET` with the reason, so the gap is visible
rather than merely absent.

## The environment this guarantee covers

Every row below is a promise about one environment, and only that one:

- a **Rails application** (`bin/rails` and `config/environment.rb`
  present), opened as a **trusted** workspace, on **darwin-arm64**, with
  the extension's own bundled Core.

That is what the E2E suite runs against, so it is what is verified. A
plain Ruby project is explicitly *not* covered by these rows yet: much of
the engine works there, but nothing here has been specified or verified
for it, and half-supporting it would make both stories worse. Giving the
Rails conventions an explicit boundary and specifying the plain-Ruby
experience is roadmap item 024.R1, for 0.2.x.

Untrusted workspaces stay as described at the end of this document: the
Runtime Agent does not start, and every Rails-derived capability degrades
to its static-only answer by design.

## Status legend

- **PASS** — verified by an E2E row that fails if the behaviour breaks.
- **NOT YET** — specified, has an E2E row, currently failing or pending.
  The extension is not claimed to do this.

## Baseline: the extension is actually running

| # | What the user does | What must happen | Status |
|---|---|---|---|
| B1 | Opens a Ruby file in a Rails project | Core starts and answers `initialize` | PASS |
| B2 | Waits a moment | `ovallsp/status` reaches `ready-rails` in a Rails app (`ready` elsewhere) | PASS |
| B3 | Closes the window | No Core, Runtime Agent, or runner process survives | PASS |

## Hover: what is this expression?

| # | What the user does | What must happen | Status |
|---|---|---|---|
| H1 | Hovers a local assigned from a constructor (`w = Widget.new`) | `Widget` | PASS |
| H2 | Hovers a local assigned from an Active Record finder (`a = Article.find(id)`) | `Article` | PASS |
| H3 | Hovers an `@ivar` in a view whose controller action assigned it | the action's inferred type | PASS |
| H4 | Hovers a literal (`"s"`, `1`, `[1]`) | `String`, `Integer`, `Array[Integer]` | PASS |

## Completion: the single most-used feature

| # | What the user does | What must happen | Status |
|---|---|---|---|
| C1 | Types `s.` where `s` is a String | stdlib methods (`upcase`, `split`, …) | PASS |
| C2 | Types `w.` where `w` is a workspace class instance | that class's own instance methods | PASS |
| C3 | Types `article.` where `article` is an Active Record instance | the model's columns and associations | PASS |
| C4 | Types `article.` where `article` is an Active Record instance | Active Record's own instance API (`save`, `update`, `destroy`, `valid?`, …) | PASS |
| C5 | Types `Article.` (a constant) | Active Record's class API (`all`, `find`, `where`, `create`, `new`, …) | PASS |
| C6 | Types `Widget.` where Widget is a workspace class | that class's own singleton methods (`def self.build`) | PASS |
| C7 | Types `article_p` in a view | route helpers (`article_path`, `article_url`) | PASS |

C4, C5 and C6 were all broken and are now fixed. C5/C6 shared one cause:
a bare constant inferred as `Unknown`, so nothing downstream ever saw a
class receiver. C4/C5 shared another: a model's ancestors above
`ApplicationRecord` are outside the workspace and have no signatures, so
Active Record's own API was invisible. The Runtime Agent now reports that
API from the really-loaded classes — once for all models, not per model —
which is what it is for.

## Go to definition

| # | What the user does | What must happen | Status |
|---|---|---|---|
| D1 | Go to definition on a call to a workspace method | jumps to its `def` | PASS |
| D2 | Go to definition on an Active Record column/association | jumps to the owning model class | PASS |
| D3 | Go to definition on a stdlib method | jumps into the RBS declaration | PASS |

## Diagnostics

| # | What the user does | What must happen | Status |
|---|---|---|---|
| G1 | Writes a syntax error | a parse diagnostic at that position | PASS |
| G2 | Calls a method that does not exist on a **workspace class** | "has no method named" | PASS |
| G3 | References a route helper that does not exist | "no route named" | PASS |
| G4 | Calls a method that does not exist on an **Active Record model** | a diagnostic | NOT YET |
| G5 | Calls a method with the wrong **number of arguments** | a diagnostic | NOT YET |
| G6 | Passes an argument of the wrong **type** | a diagnostic | NOT YET |

G4 follows from the same missing-ancestor problem as C4: the engine only
reports unknown methods on a *closed* receiver — one whose ancestors are
all known and which declares no `method_missing`. An Active Record model
is never closed today, so the check is silently inert for exactly the
classes a Rails developer writes most.

G5 and G6 are not implemented at all. They are named here so their
absence is a stated gap rather than an assumed feature: the diagnostics
engine has four checks (syntax, unknown method, unresolved constant,
unknown route helper) and none of them inspects arguments.

## Signature help

| # | What the user does | What must happen | Status |
|---|---|---|---|
| S1 | Types `(` after a workspace method | its parameter list | PASS |
| S2 | Types `(` after a stdlib method | the RBS overload label | PASS |
| S3 | Types `(` after a route helper | the helper's required parts | PASS |

## Workspace-wide

| # | What the user does | What must happen | Status |
|---|---|---|---|
| W1 | Find All References on a workspace method | every call site, across files | PASS |
| W2 | Rename a workspace method | every call site is rewritten | PASS |
| W3 | Workspace symbol search | matching classes and methods | PASS |

## What this document deliberately does not promise

- Type checking in the sense a static type checker means it. There is no
  flow-sensitive analysis, no generics beyond the built-in container
  shapes, and no exhaustiveness. G5/G6 above are the nearest thing and
  they are not built.
- Anything about a Ruby file outside a workspace folder.
- Anything while the workspace is untrusted: the Runtime Agent does not
  start, so every Rails-derived capability (C3, C4, C5, D2, G3, G4)
  degrades to its static-only answer by design.
