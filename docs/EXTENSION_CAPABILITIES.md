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

That is what the rows describe. It is not, today, where CI runs them --
see "How these are verified" below, which states exactly what runs where. A
plain Ruby project is explicitly *not* covered by these rows yet: much of
the engine works there, but nothing here has been specified or verified
for it, and half-supporting it would make both stories worse. Giving the
Rails conventions an explicit boundary and specifying the plain-Ruby
experience is roadmap item 024.R1, for 1.0.0.

Untrusted workspaces stay as described at the end of this document: the
Runtime Agent does not start, and every Rails-derived capability degrades
to its static-only answer by design — with one exception, which is a
defect rather than a degradation and is named there.

## How these are verified

Two layers, because they are two different claims:

1. `core/spec/e2e/capabilities_spec.rb` drives a real Core over stdio
   against a real Rails app and checks every row below. Set
   `OVALLSP_E2E_CORE_BIN` to the Core *inside a built VSIX* to verify the
   artifact users install rather than the sources it was built from.
2. `vscode/scripts/verify-installed-extension.sh <vsix> <workspace>`
   installs that VSIX into a throwaway VS Code, opens a Rails folder, and
   confirms VS Code lists it, activates it, spawns Core and the Runtime
   Agent, and leaves nothing behind on exit.

The second layer exists because the first cannot see the failure that
looks most like "the extension does nothing": an extension present on
disk but not registered with VS Code, which never loads and never logs.
This project has been in that state.

**What actually runs where, as of 0.2.0.** Layer 1 runs in CI on
`ubuntu-latest`, against `core/bin/ovallsp` — the sources — because no
workflow sets `OVALLSP_E2E_CORE_BIN`. Layer 2 is run by hand; no workflow
invokes it. The macOS release workflow runs `scripts/vsix_semantic_smoke.rb`
against the built VSIX, which is a narrower check than either layer. So
the rows below are verified continuously on Linux against the sources,
and on darwin-arm64 against the packaged Core only by the smoke check and
by hand. Closing it needs no new infrastructure: `apple-silicon-release.yml`
already runs on GitHub's own `macos-14` Apple Silicon runners, so the gap
is layer 1 against the packaged Core in that job, which is what
`OVALLSP_E2E_CORE_BIN` above is for. Doing it per published target is
024.R4.

`core/spec/e2e/capability_coverage_spec.rb` keeps this document and the
suite in step: every row must have an example, every example a row.

## Status legend

- **PASS** — verified by an E2E row that fails if the behaviour breaks.
- **NOT YET** — specified, has an E2E row, currently failing or pending.
  The extension is not claimed to do this. If the row is *pending* rather
  than failing, its `pending`/`skip` message must contain the words
  `NOT YET`: CI fails the build on any skipped example in this suite that
  does not say so,
  because a suite that skips itself for want of rails/sqlite3 would
  otherwise report every capability as shipped, and that string is what
  tells a deliberate gap apart from a broken environment
  (`.github/workflows/ci.yml`, `core/spec/meta/ci_skip_guard_spec.rb`).

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
| H5 | Hovers a method call | its parameter list (`documented(first, second)`) | PASS |
| H6 | Hovers an expression nested in a keyword argument, array, hash, `case`, `while` or `return` | that expression's own type, not the enclosing structure's | PASS |
| H7 | Hovers a *call written with a receiver* to a method declared with an RDoc/YARD comment above it | the comment appears in the hover, below the type | PASS |

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
| C8 | Accepts a completion for a method whose parameters are known | the call is written out with each parameter as a tab stop (`takes_two(first, second)`) | PASS |
| C9 | Accepts a completion for a method that takes nothing | the bare name, no parentheses | PASS |
| C10 | Accepts a completion for a method that takes arguments of unknown shape | `where($1)` — parentheses opened, cursor inside | PASS |
| C11 | Types `post.` inside an ERB template | the model's members, resolved from the template's Ruby regions rather than its HTML | PASS |
| C12 | Types `Art` with no receiver in front of it | workspace classes, the locals in scope, and the methods callable at that position | PASS |
| C13 | Highlights a completion candidate declared with an RDoc/YARD comment, *in the list a receiver produced* | the comment appears as the item's documentation | PASS |

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
| G4 | Calls a method that does not exist on an **Active Record model** | "has no method named" | PASS |
| G5 | Calls a method with the wrong **number of arguments** | "takes N arguments, but M given" | PASS |
| G6 | Calls a Rails DSL in a class whose superclass is a gem constant (`< Rails::Application`) | nothing — the class's real method set is unknown here | PASS |
| G7 | Calls a DSL in a class whose superclass is an expression (`< ActiveRecord::Migration[8.1]`) | nothing | PASS |
| G9 | Writes an ERB template that calls a method on a local | nothing about HTML — the Ruby regions are analysed, not the template text | PASS |
| G10 | Writes `<%= yield %>` in a layout | nothing — legal in a template, even though the extracted Ruby is top level | PASS |
| G11 | Calls a method on an argument (`User.find(params[:id])`) | nothing — the inner call belongs to its own receiver | PASS |
| G12 | Has a file open from before the Runtime Agent reported routes | the route diagnostic clears once routes arrive, without touching the file | PASS |
| G13 | Reopens a class that lives in a gem (`test/test_helper.rb`'s `ActiveSupport::TestCase`) | nothing — the workspace does not own that class, whatever the static chain says | PASS |
| G14 | Writes a test that inherits from a reopened gem class (`class FooTest < ActiveSupport::TestCase`) | nothing — the reopen is in the chain, not just at the receiver | PASS |
| G15 | Passes an argument whose type cannot be the one an RBS/RBI signature declares | it is reported, on the argument rather than on the whole call | PASS |
| G16 | Reads an `@ivar` in a view that no controller action or callback assigns | it is reported | PASS |

G4 used to follow from the same missing-ancestor problem as C4 and is now
closed: the Runtime Agent reports what each model actually responds to,
so a model counts as a closed receiver — unless it defines
`method_missing`, or its columns could not be read, in which cases the
check stays silent rather than guessing.

G5 is deliberately narrow. It reports only when the receiver resolves to
exactly one source declaration, the call passes no splat or `...`, and
the declaration takes no `*rest`. Everything else says nothing: a false
"wrong number of arguments" on code that runs would be worse than no
arity checking.

Argument *type* checking became a row in 0.2.0 (G15), on the same terms:
it says nothing unless the declared type comes from an RBS/RBI
declaration, the signature has exactly one overload, both types are plain
classes, and the argument is not an expression whose own type this cannot
settle. Everything it declines is listed under the non-goals below.

## Signature help

| # | What the user does | What must happen | Status |
|---|---|---|---|
| S1 | Types `(` after a workspace method | its parameter list | PASS |
| S2 | Types `(` after a stdlib method | the RBS overload label | PASS |
| S3 | Types `(` after a route helper | the helper's required parts | PASS |

## Semantic highlighting

| # | What the user does | What must happen | Status |
|---|---|---|---|
| T1 | Reads `foo` where it is a local variable, and `foo` where it is a call on self | the two are coloured differently, in `.rb` and in an ERB template's Ruby regions alike | PASS |

## Workspace-wide

| # | What the user does | What must happen | Status |
|---|---|---|---|
| W1 | Find All References on a workspace method | every call site, across files | PASS |
| W2 | Rename a workspace method declared with `def` | every call site is rewritten | PASS |
| W3 | Workspace symbol search | matching classes and methods | PASS |
| W4 | Renames a method a macro declared (`attr_accessor`, `delegate`, …) | nothing is edited — there is no identifier token to rewrite, and editing only the call sites would leave the declaration behind. The editor shows its own refusal; the reason is logged, not surfaced (024.28) | PASS |

## What this document deliberately does not promise

- Type checking in the sense a static type checker means it. There is no
  flow-sensitive analysis, no generics beyond the built-in container
  shapes, and no exhaustiveness. Argument *types* are checked as of 0.2.0
  (G15), but only where a signature declares one and the argument's type
  is known — G5 still counts arguments, and a call neither can judge is
  left alone rather than guessed at.
- Syntax colouring. A TextMate grammar decides how a file is tokenised
  for display, which is a presentation concern and not what this engine
  knows anything about; VS Code's bundled Ruby extension already
  associates `.erb`, and other Ruby extensions ship grammars of their
  own. Registering another would collide with them for no gain.
  *Semantic* highlighting is a different thing and ships as of 0.2.0
  (T1 above): it layers meaning this engine actually has — whether `foo`
  is a local variable or a call on self — over whatever grammar is in
  use, in `.rb` files and in an ERB template's Ruby regions alike.
- Anything about a Ruby file outside a workspace folder.
- Anything while the workspace is untrusted: the Runtime Agent does not
  start, so every Rails-derived capability (H2, C3, C4, C5, C7, C11, D2,
  G3, G4, G12, S3) degrades to its static-only answer by design. That
  included one defect rather than a degradation until 0.2.0: G3's check
  reported *every* `*_path`/`*_url` call as a missing route, because an
  empty route table answered "no such route" rather than "I do not know".
  It now says nothing until a route table has been loaded (024.24).
