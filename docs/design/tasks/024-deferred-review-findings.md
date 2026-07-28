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
