# Task 024: Deferred review findings

Findings from independent review that were deliberately **not** fixed in
the change set they were found in, because fixing them would have widened
that change set beyond what its own goal required.

**This is the single place deferred findings are collected.** Do not open
a second file, and do not scatter `TODO` comments through the source for
them — an item that is worth deferring is worth being findable in one
place. Append new entries here; remove an entry only when it is actually
fixed, and say in the fixing commit which entry it closes.

Each entry states the symptom, who it affects, how to reproduce it, and a
proposed direction. Nothing here is a shipping blocker; every item was
triaged as such by the reviewer that raised it.

Status legend: **open** — not started. **fixed** — resolved; entry kept
until the next release, then deleted.

Entries numbered `024.R*` are roadmap items rather than defects: work
that is understood, deliberately not scheduled for the current release,
and too large to fold into one. They live here rather than in a separate
roadmap file for the same reason everything else does — one place.

---

## 024.1 Duplicate, unused implementation of the controller callback chain

**Status:** open
**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/server.rb`

`LocalInferencer#infer_ivars_for_action` implements the before_action
chain rule (build the effective callback list, evaluate each callback,
then the action, sharing one step budget). `Server#infer_controller_action_ivars`
implements the same rule again, over its own inheritance-aware method
maps. Only the Server copy runs in production; the LocalInferencer copy
has no caller in `lib/`.

Two same-shaped implementations of one rule means a fix to either can
silently miss the other. This was found the expensive way: a regression
spec written against the LocalInferencer copy pinned nothing about the
path that actually runs, and the production budget-sharing decision was
left untested until round 14 caught it.

`#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node`
and the `MethodLocator` visitor exist only to serve that unused copy and
its specs.

**Direction:** delete the unused copy and re-anchor its specs onto the
Server path, or make the Server call the LocalInferencer copy so there is
one implementation. Deleting cascades into `MethodLocator`, so it is not a
one-line change.

## 024.2 `Hash.new` / `Set.new` hover as `Hash[Unknown]` / `Set[Unknown]`

**Status:** open
**Area:** `core/lib/ovallsp/local_inferencer.rb` (`resolve_call`'s `.new` ladder)

Consulting RBS before the nominal-constructor fallback means `Hash.new`
resolves through `Hash.new: [K, V]() -> Hash[K, V]` with both parameters
unbound, so hover shows `Hash[Unknown]` where it used to show `Hash`.
Same for `Set.new`. (`Array.new` → `Array[Unknown]` is arguably better,
since it lets the container rules dispatch.)

`Types.normalize_union` already encodes the opposite judgement — it
collapses `Hash[Unknown]` into `Hash` on the grounds that the generic
form constrains nothing extra — so the two behaviours disagree about the
same value. Display-only; no wrong type is produced.

**Direction:** decide once whether `X[Unknown]` or `X` is the canonical
rendering of "container with no known element type", and apply it in both
places. Pin whichever is chosen.

## 024.3 An `untyped` RBS singleton signature still shadows source resolution

**Status:** open
**Area:** `core/lib/ovallsp/local_inferencer.rb` (constant-receiver branch)

The `.new` branch treats a `Types::Unknown` from RBS as "no answer" and
falls through to source/nominal resolution. The sibling branch for every
*other* singleton call returns the signature result even when it is
Unknown, so it never reaches `resolve_class_level_finder` or
`resolve_source_method_member`.

Reproduce: declare `def self.build: (...) -> untyped` in a project `sig/`
or Sorbet RBI for a class that also defines `self.build` in source; a
call resolves to Unknown instead of the source return type. Requires a
project-supplied untyped signature, so it does not occur with stdlib
alone.

**Direction:** apply the same Unknown filter to the non-`new` branch.

## 024.4 `BeforeActionFinder#record` mutates the Prism AST in place

**Status:** open
**Area:** `core/lib/ovallsp/local_inferencer.rb`

`arguments.pop` operates on the array Prism owns, not a copy (verified:
the node's own `arguments.arguments` shrinks). Harmless today because the
document is re-parsed on every call and each statement is visited once;
it becomes a live bug as soon as anything caches or re-walks that tree.

**Direction:** `arguments[0...-1]` instead of `pop`.

## 024.5 `Server#index_references` is dead

**Status:** open
**Area:** `core/lib/ovallsp/server.rb`

Both former callers now go through `apply_file_summary` plus
`mark_reference_index_dirty`. The risk is a future change to reference
resolution being made in the dead copy.

**Direction:** delete.

## 024.6 The `seen_uris` spec's comment overclaims

**Status:** open
**Area:** `core/spec/ovallsp/cold_indexer_spec.rb`

The comment says the spec covers a file already open in a buffer, but no
`DocumentStore` entry is created, so that branch is never exercised.
`@seen_uris << uri` sits above the open-buffer early return and nothing
pins that ordering. No live consequence: the deletion sweep verifies
absence with `File.file?` rather than trusting `seen_uris`.

**Direction:** add the buffer case, or trim the comment to what the spec
actually asserts.

## 024.7 `rootIdentity`'s refresh assignment cannot affect any decision

**Status:** open
**Area:** `vscode/src/coreProcess.ts`

`this.rootIdentity = rootRow` in the "still our process" branch is
documented as picking up a post-setsid pgid change, but the only
comparison it feeds (`sameRootProcess`) looks at `pid` and `startedAt`,
both invariant over the process's life. The pgid tolerance the comment
credits it with actually comes from `sameRootProcess` not comparing pgid
at all. The line is unpinnable by construction — no fixture can
distinguish it.

**Direction:** delete the line, or correct the comment to say it is
insurance against `sameRootProcess` tightening later.

## 024.8 Ownership retirement on `exited() && known.size === 0` is unpinned

**Status:** open
**Area:** `vscode/src/coreProcess.ts`

Clearing `ownedSessionId`/`ownedGroupId` there is defence-in-depth: the
expansion gate already prevents the failure it guards against, and no
concrete failing scenario could be constructed for its removal. Recorded
because unpinned behavioural lines count as defects in this project.

**Direction:** a test, not a code change — or delete the lines if the
invariant is genuinely carried elsewhere.

## 024.9 A forced crash popup can still appear for deliberate stops

**Status:** open
**Area:** `vscode/src/extension.ts` (`OvalLspLanguageClient.error`)

The suppression keys off the branded rejection arriving as `data`. That
covers the two paths that carry it, but not vscode-languageclient's
`DoNotRestart` notice, which passes `data === undefined` with `'force'`.

Reproduce: stop the client five times within three minutes while it is
still `starting` (repeated *OvalLSP: Restart Server* during the
compatibility probe). `stopClient` deliberately does not call
`client.stop()` in that state — it terminates Core directly — so the
library sees five connection closures and reports *"The OvalLSP server
crashed 5 times in the last 3 minutes"*, about five deliberate stops.

**Direction:** key the suppression on lifecycle state or the message,
rather than on `data` alone.

## 024.10 Four `extension.ts` behaviours cannot be unit-tested

**Status:** open
**Area:** `vscode/src/extension.ts`

`extension.ts` imports `vscode`, which the unit suite cannot load, so
these four are covered only by manual verification: awaiting
`client.stop()` rather than firing it off, `stopClient` draining
retirements for an untracked generation, the shutdown-barrier check when
a workspace folder is added, and the restart notification wording.

**Direction:** extract the testable logic out of the `vscode`-importing
module, or add an integration test host.

## 024.11 Core reports version 0.0.1 while the extension reports 0.1.5

**Status:** fixed — `Ovallsp::VERSION` now tracks the extension version,
and `copy-core.js` refuses to build a bundled payload where the two
disagree. The rule and its exemptions are in `docs/PUBLISHING.md`.
**Area:** `core/lib/ovallsp/version.rb`, surfaced by `OvalLSP: Show Version Information`

`Ovallsp::VERSION` has been `0.0.1` since the rebrand, so `initialize`
answers `serverInfo.version` / `ovallspInfo.coreVersion` as `0.0.1` while
the extension reports its own `0.1.5`. Compatibility is judged on the
protocol range, not on these strings, so nothing misbehaves — but the
version panel shows a pairing that looks wrong to anyone reading it, and
a bug report quoting "Core 0.0.1" is hard to map to a release.

**Direction:** decide whether the gem version tracks the extension
version or is deliberately independent, and either bump it in step or say
so in the version panel's own wording.

---

## 024.R1 Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/server.rb`, `core/lib/ovallsp/parser_service.rb`,
`core/lib/ovallsp/local_inferencer.rb`

Rails detection gates exactly one thing: whether `RailsBootstrap.start`
spawns the Runtime Agent (`bin/rails` + `config/environment.rb` must both
exist). Everything downstream is not branched on "is this Rails" at all —
the same code runs either way, and in a plain Ruby project the
Rails-derived registries are simply empty, so those features contribute
nothing.

That part is a good property: a wrong Rails guess degrades to static
analysis instead of breaking, and it is the same path an untrusted
workspace takes when the Agent deliberately does not start.

The gap is that several Rails *conventions* are applied on filename and
method-name shape alone, with no Rails gate anywhere:

- controller-to-view ivar propagation matches
  `app/views/<dir>/<action>.*.erb`
- file-change classification matches `app/models/*.rb`, `db/schema.rb`,
  `db/structure.sql`, `db/migrate/`
- `before_action` is recognised by method name
- `enum`/`scope`/`delegate` generated-method facts are recorded by method
  name

So a plain Ruby project that happens to use those names or that directory
layout gets Rails semantics applied to it. No incorrect behaviour has
been observed — the registries those paths feed are empty without an
Agent — but the boundary is implicit, and nothing tests what a non-Rails
project experiences.

**Direction:** give the Rails conventions one explicit boundary (a
capability/profile decided once at initialize, from the same detection
that gates the Agent) rather than re-deriving "this looks like Rails"
from a path pattern at each site. Add a plain-Ruby workspace to the E2E
capability suite so the non-Rails experience is specified and verified
rather than assumed.

Deferred out of 0.1.6 deliberately: it is an architectural change across
three files, and 0.1.6's goal is that the capabilities already claimed to
work actually do.

One of the two things 1.0.0 requires (`docs/PUBLISHING.md`, "0.x, and
what 1.0.0 requires"): a plain Ruby project must be guaranteed, not only
a Rails one. Until then README's capability matrix carries ⚠️ for that
column and this entry is why.

## 024.R2 Argument *type* checking (roadmap, 0.2.x)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

0.1.6 added an argument *count* check (capability G5). Nothing inspects
what the arguments actually are: passing a String where the parameter is
only ever used as an Integer is not reported.

Doing it honestly needs more than the count check did. Parameter types
are not declared in Ruby source, so the expected type has to come from
RBS/RBI where one exists, or from inference over the method body where it
does not — and a wrong "expected Integer, got String" on code that runs
is worse than saying nothing, the same standard G5 was held to.

**Direction:** start where the expected type is stated rather than
inferred (RBS/RBI-declared parameters, and the built-in container rules),
and report only when the argument's own inferred type is a concrete
Nominal that cannot match. Leave everything else silent.

Referenced from README's capability matrix as the version this is planned
for, so the table's promise and this entry stay in step.

---

## 024.R3 Feature parity roadmap, measured against Pylance

**Status:** open — roadmap

Pylance is the closest well-known reference point for "what a language
server is expected to do" in a dynamically typed language with optional
type declarations, so it is a useful yardstick — not a target to copy.
Rows Pylance has that make no sense here (Jupyter support, IntelliCode's
ranked completions, Python-specific stub packaging) are deliberately
absent rather than listed and dismissed.

Current OvalLSP capabilities were read from the `initialize` response and
the code, not assumed: `hoverProvider`, `documentSymbolProvider`,
`definitionProvider`, `referencesProvider`, `renameProvider`,
`workspaceSymbolProvider`, `completionProvider`, `signatureHelpProvider`.
Everything else below is absent.

| Pylance capability | OvalLSP today | Planned for | Notes |
|---|---|---|---|
| Diagnostics across the whole project | Open files only | **0.2.x** | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.x** | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.x** | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.x** | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.x** | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.x** | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.x** | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.x** | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
| Auto-import / add `require` | None | **0.4.x** | Much weaker payoff than in Python: Rails autoloads, and plain Ruby projects mostly `require` at the entry point. Worth revisiting only after the plain-Ruby story (024.R1) exists. |
| Type checking strictness levels | One fixed set of checks | **0.4.x** (as per-check severity) | Pylance's basic/strict switch matters because its checks are numerous and opinionated. With four checks, a per-check severity setting would cover the same need more simply. |
| Signature help with active parameter tracking | Signature label only | **0.4.x** | Already useful; highlighting which argument the cursor is in is a refinement, not a gap. |
| Generating type stubs from source | RBS/RBI are read, never written | not planned | Interesting for library authors, irrelevant to the Rails application developer this Preview targets. |

Not planned, and listed only so their absence is a decision rather than
an oversight: unreachable-code dimming (RuboCop covers the same ground
for Ruby users), refactoring extractions beyond rename, and anything
notebook-shaped.

Ordered by what a user notices soonest rather than by effort:
whole-project diagnostics, then documentation in hover/completion, then
semantic tokens, then inlay hints and code actions. The first two are
noticed in the first ten minutes.

These versions are also carried in README.md and README.ja.md's
capability matrix, which is the user-facing statement of them; this
section is the reasoning behind each. Keep the two in step.

---

## 024.R4 Only one platform is published or verified (roadmap, 1.0.0)

**Status:** open — roadmap
**Area:** `vscode/package.json` (`--target darwin-arm64`),
`.github/workflows/apple-silicon-release.yml`, `vscode/scripts/copy-core.js`

One VSIX is published, for `darwin-arm64`, and it is the only environment
any capability has been verified in. On every other platform the
situation is not "probably fine" but "unpublished": VS Code filters
Marketplace results by target, so there is nothing to install on Windows,
Linux, or an Intel Mac.

The obstacle is the vendored payload rather than the code. `prism` and
`rbs` ship as native extensions built for the packaging machine's Ruby
ABI, OS and CPU, so a VSIX is only valid for the combination
`PLATFORM_MANIFEST.json` records. Sideloading the darwin-arm64 build
elsewhere does not crash — `Ovallsp::VendorCompatibility` and
`platformCompatibility.ts` refuse the payload and explain why (ADR-0005)
— but it then depends on the user's own Ruby having prism/rbs, which is
unverified.

`.github/workflows/apple-silicon-release.yml` deliberately asserts an
arm64 interpreter before building, so it cannot be pointed at another
target as-is.

**Direction:** a per-target build matrix producing one VSIX per platform,
each built on that platform (never cross-compiled or emulated, for the
reason above), each running the capability suite against its own bundled
Core, and each published. `docs/SUPPORT_MATRIX.md`'s tiers then become
statements about verified artifacts rather than about one artifact and
several unknowns.

The other of the two things 1.0.0 requires (`docs/PUBLISHING.md`, "0.x,
and what 1.0.0 requires").

---

## 024.R5 A reopened gem class still looks closed (roadmap, 0.1.7)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/runtime_agent/agent.rb`

0.1.6 stopped the unknown-method check firing on classes whose ancestry
the workspace cannot see: a chain that does not reach BasicObject is
treated as open, which covers a gem superclass named by constant and a
superclass that is an expression (`ActiveRecord::Migration[8.1]`).

One case is left, and it is not a gap in the rule but a limit of static
analysis. Reopening a class the workspace does not define looks identical
to defining it:

```ruby
module ActiveSupport
  class TestCase          # a reopen: the real class lives in a gem
    parallelize(workers: :number_of_processors)
  end
end
```

Ruby keeps the original superclass when a class is reopened, but nothing
in this file says so, so the declaration reads as a plain class with no
parent — Object, Kernel, BasicObject, complete. `parallelize` and
`fixtures` are then reported as undefined. Every Rails application's
`test/test_helper.rb` has exactly this shape, so this is the common case,
not an exotic one.

Distinguishing the two needs to know where the constant was really
defined, which only the running application knows.

**Direction:** ask the Runtime Agent, the same way model methods and the
Active Record API are already answered from runtime truth
(`Object.const_source_location`): a constant defined outside the
workspace root means the class's real method set is unknown here, so the
check stays silent for it. Cache per constant; it cannot change without
a restart.

The same request answers a second, currently latent instance of the same
mistake. `unresolved-constant` reports any constant that is neither in
the workspace nor in RBS, which in a Rails application means every gem
constant: measured against `config/application.rb`, it reports `Rails`
and `Bundler` as unresolvable. It does not reach users today because the
check only runs in `standard` mode and the extension never sends
`diagnosticsMode`, so `safe` is the only mode reachable -- but the check
is unusable as written, and enabling it without this would repeat the
false-positive flood the unknown-method check just came out of.
`Object.const_defined?` from the Agent settles it exactly.

Until then the check is silent for gem-derived classes reached by
superclass, and wrong for gem classes reached by reopening.

