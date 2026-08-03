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

Status legend: **open** — not started. **fixed** / **done** — resolved.

An open, non-roadmap entry should also be cited by number in
`docs/KNOWN_LIMITATIONS.md` **and** `.ja.md`, so a finding recorded here
reaches the people it affects. Nothing checks this today; an attempt to
check it mechanically is recorded as 024.25, along with why the shape it
took was wrong.

A resolved entry is deleted once nothing in the tree cites it. It is
**not** deleted while source or spec comments still name it by number:
those comments say "this is the way it is because of 024.N", and the
number is the only way to reach the reason. Every resolved entry below
was checked against a repo-wide grep and is cited — 024.1 from
`server_views_spec.rb` and `local_inferencer_spec.rb`, 024.6 from
`cold_indexer_spec.rb`, 024.8 from `coreProcess.ts` and its unit test,
024.10 from `extension.ts`, `clientTeardown.ts` and
`clientErrorNotifications.ts`, 024.R5 from fifteen places including
`ancestry_registry.rb`, which says its measurements "are recorded in
024.R5".

The legend previously promised deletion "at the next release" with no
such exception, and four entries — fixed in 0.1.10, so due for deletion
in 0.1.11 — then sat a release past that deadline because deleting them
would have broken live references. Round 5 of the
0.1.12 review reported the entries as stale; the deadline was the part
that was wrong. Run the grep before deleting, not the calendar.

Entries numbered `024.R*` are roadmap items rather than defects: work
that is understood, deliberately not scheduled for the current release,
and too large to fold into one. They live here rather than in a separate
roadmap file for the same reason everything else does — one place.

---

## 024.1 Duplicate, unused implementation of the controller callback chain

**Status:** fixed in 0.1.10 — the unused copy is deleted, along with
`#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node`
and the `MethodLocator` visitor that existed only to serve it. Its specs
were re-anchored rather than dropped: the ones covering pieces the Server
still calls now go through those pieces (`method_nodes` +
`#infer_ivars_for_method_node`, `#static_render_target_for_node`), and the
seven chain behaviours that had no equivalent on the live path — `except:`
on both sides of it, an action overriding a callback's assignment, an
unresolvable `if:` condition, a conditional `skip_before_action`, a
missing callback method, and the multi-name forms of `before_action` and
`skip_before_action` — were ported into `server_views_spec.rb`, where each
fixture was checked to yield a *different* answer under the opposite
behaviour.
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

## 024.6 The `seen_uris` spec's comment overclaims

**Status:** fixed in 0.1.10 — the buffer case is now a spec of its own,
so `@seen_uris << uri` sitting above the open-buffer early return is
pinned rather than merely claimed.
**Area:** `core/spec/ovallsp/cold_indexer_spec.rb`

The comment says the spec covers a file already open in a buffer, but no
`DocumentStore` entry is created, so that branch is never exercised.
`@seen_uris << uri` sits above the open-buffer early return and nothing
pins that ordering. No live consequence: the deletion sweep verifies
absence with `File.file?` rather than trusting `seen_uris`.

**Direction:** add the buffer case, or trim the comment to what the spec
actually asserts.

## 024.8 Ownership retirement on `exited() && known.size === 0` is unpinned

**Status:** fixed in 0.1.10 — the two assignments are deleted; the
`ownedSessionId` one is load-bearing and pinned by a new regression test,
and `ownedGroupId` went with it for symmetry (it is set only from a
validated root row whose `pgid === pid`, and such a row also satisfies the
expansion test against `ownedSessionId`, so `known` cannot be empty in the
same pass — no fixture distinguishes that half). The first attempt at this
entry deleted them as unable to change any answer, reasoning that the
branch is only reached with the root absent and the expansion gate
therefore already closed. Independent review disproved both halves:
`rootObservedAbsent` is assigned at the *end* of the pass, and the root
row can be present but untracked, because `known` only takes the root
while the child has not exited. A Core dying inside the ~57ms pre-`setsid`
window reaches the branch with ownership still meaningful — on Darwin
especially, where `sid` is 0 on every row. Since `terminateOnce` and
`waitForAllExit` both refresh after the interval is cleared, retiring
ownership there permanently lost the survivor those later passes exist to
catch. The `clearInterval` in the same branch stays, pinned by its own
test.
**Area:** `vscode/src/coreProcess.ts`

As originally recorded, and wrong in its premise — kept here because the
reasoning is the point: "Clearing `ownedSessionId`/`ownedGroupId` there is
defence-in-depth: the expansion gate already prevents the failure it
guards against, and no concrete failing scenario could be constructed for
its removal. Recorded because unpinned behavioural lines count as defects
in this project." A scenario *can* be constructed; see the status above.

**Direction (superseded, recorded with the premise above):** a test, not a
code change — or delete the lines if the invariant is genuinely carried
elsewhere. Neither applied: the lines were deleted because keeping them
was actively harmful, not because the invariant was carried elsewhere.

## 024.10 Four `extension.ts` behaviours cannot be unit-tested

**Status:** fixed in 0.1.10 — the four decisions moved into
`vscode/src/clientTeardown.ts`, which imports no `vscode` and takes the
lifecycle manager and the per-folder maps as parameters rather than
reading module state. `extension.ts` now delegates to it and keeps only
the `vscode` wiring. Fifteen unit tests cover them, and each decision was
checked by mutating it and confirming the suite goes red.

The fourth took two attempts, and the first one is worth recording:
exporting the two notification strings for `extension.ts` to choose
between pinned the *wording* while leaving the command-to-message pairing
at the call sites, where an independent reviewer swapped it with the
suite still green. What is pinned now is that there is no choice — each
command is registered through a helper that names its id once and looks
the confirmation up from that same id. What a command *does* is still two
hand-written bodies in `extension.ts` — swapping those would still restart
the wrong thing — so the confirmation is what this pins, not the whole
command.
**Area:** `vscode/src/extension.ts`

`extension.ts` imports `vscode`, which the unit suite cannot load, so
these four are covered only by manual verification: awaiting
`client.stop()` rather than firing it off, `stopClient` draining
retirements for an untracked generation, the shutdown-barrier check when
a workspace folder is added, and the restart notification wording.

**Direction:** extract the testable logic out of the `vscode`-importing
module, or add an integration test host.

## 024.25 A Markdown-parsing spec is the wrong shape for "these two documents must agree"

**Status:** open, and **rolled back** rather than fixed. This entry is the
deliverable; there is no code change to point at.

**Area:** was `core/spec/meta/known_limitations_parity_spec.rb` and
`core/spec/meta/readme_parity_spec.rb`, both deleted.

### What was being solved

A review found that `docs/KNOWN_LIMITATIONS.md` did not mention 024.13,
024.19 or 024.20, while `025-0.2.0-review-loop-handover.md` claimed every
open entry was carried there. The prose promise had gone stale, so the
obvious move was `docs/DOCUMENTATION_MAP.md`'s own principle: where a
fact is restated in several places, have a machine compare the copies.

### Why the shape was wrong

The two specs had to *parse Markdown with regexes* to find out what the
documents said — headings, status lines, an opt-out marker, table rows,
footnote definitions. Every review round then found another input shape
the parser mishandled, and each fix was one more special case:

- **Round 2** found eight decisions in the first guard that no example
  pinned, because the fixtures used `**Status:** Open`, which reads as
  open under *both* branches of the case-sensitivity decision. Rewriting
  them onto the resolved side (`Fixed`, `DONE`) fixed that.
- **Round 3** found ten unpinned decisions in the *second* guard, written
  in round 2 — including `count("|") == 5`, whose mutation makes the row
  selector return zero rows for both files and leaves every matrix
  assertion vacuously green. It also found two soundness holes in the
  first: a heading with no title (`## 024.25`) is not recognised, so an
  entry can be added and silently skipped, and the documented "and why"
  requirement for the opt-out was never enforced at all.

Three documents had meanwhile been edited to *claim* the guard enforced
things it did not. That is worse than no guard: a maintainer reading
`DOCUMENTATION_MAP.md` would believe an unchecked rule was checked.

The pattern is 024.15's, one layer up. There, each round bolted a sort
onto one more *reader* of an unordered collection. Here, each round
bolted a fixture onto one more *input shape* of a parser that cannot
enumerate its own inputs, because Markdown prose has no schema. A guard
whose correctness depends on a regex surviving every future edit to the
document it reads is a guard that needs the next round to repair it.

### The direction that was actually needed

Two candidates, neither attempted here:

1. **Give the data a schema instead of parsing prose.** If each deferred
   finding carried machine-readable front matter (number, status,
   user-visible yes/no), a check becomes a lookup and has no parser to
   get wrong. The cost is a format change to a document people write by
   hand, which is a decision about how this project keeps notes — not
   something to slip into a documentation fix.
2. **Accept that this pair is checked by a person, and make the person's
   job small.** `DOCUMENTATION_MAP.md` already exists for exactly this,
   and its release checklist is the place to name the pairing. The map's
   own preamble says "a machine check *should* compare the copies" — it
   does not say every pair can be compared by machine, and this pair is
   evidence that some cannot be, cheaply.

The EN/JA README divergence found in round 2 is real and remains
unguarded for the same reason. Prefer 1 if this is taken up; it is the
only one of the two that would also have caught that.

### What was kept

Everything the rounds established about the *product* stayed: 024.21
through 024.24, the corrected measurements, and the user-facing text in
both languages. Those were verified against the source and against corpus
runs, and no round disputed them. Only the enforcement apparatus and the
claims about it were rolled back.

## 024.24 Every `*_path`/`*_url` call is a missing route when no routes are loaded

**Status:** open. Pre-existing — reproduced identically on `main` (0.1.13).

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`
(`unknown_route_helper_findings`)

The check gates on `context.route_registry` being non-nil, and `Server`
always constructs one (`server.rb:55`, `:90`, `:809`). Without a Runtime
Agent the registry is *empty* rather than absent, and an empty registry
answers "no such route" for every helper name. So any receiverless call
matching `/_(path|url)\z/` is reported.

Measured with `scripts/corpus_diagnostics.rb`: **48 reports across Ruby
3.4.7's stdlib and 12 more in prism 1.9.0**, every one of them a false
positive on code that has nothing to do with Rails — `original_path` and
`dsl_path` are ordinary private methods in bundler.

Who sees it: a user who opens a Rails app and declines Workspace Trust
(`vscode/package.json` declares `untrustedWorkspaces: "limited"` and
`extension.ts:209` starts the Core with `workspaceTrusted: false` rather
than refusing), and anyone with a non-Rails project containing a method
whose name ends that way.

Two documents assert the opposite today and have been corrected:
README's legend said `—` means "absent by design, not broken", and
`EXTENSION_CAPABILITIES.md` said an untrusted workspace "degrades to its
static-only answer by design".

**Direction:** an empty registry is not evidence of a missing route. The
check needs to distinguish "routes are loaded and this is not among them"
from "no routes are loaded", and stay silent in the second case — the
same shape as the unknown-method check's refusal to guess without an
Agent. A registry that knows whether it has ever been populated is the
smallest form of it.

## 024.23 The singleton chain does not model `Class`/`Module`, so class-body macros are unknown methods

**Status:** open. Pre-existing — reproduced identically on `main` (0.1.13).

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb` (the
`singleton: true` ancestry), `core/lib/ovallsp/diagnostics/engine.rb`

`HierarchyIndex`'s singleton chain models only `Object`/`Kernel`/
`BasicObject` on the instance side, so `Module`'s own instance methods —
`private`, `attr_reader`, `attr_accessor`, `private_constant`,
`alias_method`, `include` — resolve nowhere when called in a class body
against a closed workspace class. The engine already knows this: its
comment at `engine.rb:100-108` says so and special-cases `new` alone.

Measured with `scripts/corpus_diagnostics.rb` over this repository's own
`core/lib`: **49 of the 62 `unknown-method` findings are this** — 34
`private`, 10 `private_constant`, 5 `attr_reader`. Over
`activesupport-8.1.3/lib`: 776 findings in total, of which about 211 are
this shape — `private` (72), `alias_method` (56), `attr_reader` (40),
`include` (26).

This is the largest single source of wrong reports the engine currently
produces, and it fires on the most ordinary Ruby there is. It is not the
only source: `core/lib`'s remaining 13 are three instances of 024.19's
simple-name fallback (`RBS::Environment#resolve_type_names`), four calls
to readers `attr_reader` itself generated, and a handful of receiverless
calls inside `def self.` and `class << self` bodies — which is the same
missing singleton modelling seen from the other side.

**Direction:** give the singleton chain its real tail — `Class`,
`Module`, `Object`, `Kernel`, `BasicObject` — so RBS's `Module#private`
resolves like any other signature. Special-casing `new` is the same
problem solved once by name; there are dozens more names and the list is
not ours to keep. Note this widens what completion offers on a constant
receiver too, which is correct but is a visible change and wants its own
corpus comparison.

## 024.22 The unassigned-`@ivar` check is silent in an application `rails new` produces

**Status:** open.

**Area:** `core/lib/ovallsp/server.rb` (`MODELLED_CLASS_BODY_CALLS`,
`class_body_is_accounted_for?`)

The check requires every class body in the controller chain to call
nothing beyond `private`/`protected`/`public`/`before_action`/
`skip_before_action`. Railties 7.2, 8.0 and 8.1 all generate an
`ApplicationController` whose body calls `allow_browser versions:
:modern`. That is unmodelled, the rule applies to the whole chain, and so
the check is silenced for **every view in a default Rails application**.

The G16 capability row passes because
`core/spec/fixtures/rails_real/app/controllers/application_controller.rb`
is a hand-written empty class — a shape `rails new` does not produce. The
row is honest about what it exercises; what it exercises is not what a
user has.

`KNOWN_LIMITATIONS.md` stated the rule abstractly ("`ApplicationController`'s
own body decides this for every view beneath it") without saying that the
default application trips it. That has been corrected.

**Direction:** not another name in the list — `allow_browser` today,
something else next Railties. Two shapes are defensible: treat a
class-body call that assigns no ivar and is not a callback as irrelevant
rather than disqualifying (which needs 024.R7's gem index to know what a
macro installs), or narrow the disqualification to the chain's *workspace*
classes and treat gem superclasses as opaque-but-harmless. Until then the
E2E fixture should carry the generated `ApplicationController`, so the
row measures the real shape and fails honestly.

## 024.21 A qualified constant is coloured half one way, half the other

**Status:** open. Pre-existing for `Foo::Bar` reads; 0.2.0 is where
semantic tokens became a user-visible capability (T1).

**Area:** `core/lib/ovallsp/semantic_tokens.rb` (`Collector`)

`Collector` overrides `visit_constant_read_node` but not
`visit_constant_path_node`, so in `Ovallsp::Server` only `Ovallsp`
receives a token and `Server` receives none. A semantic token overrides
the editor's grammar colour, so the two halves of every namespaced
constant render differently — the first half semantic, the second half
whatever TextMate says.

The same module is also `namespace` where it is declared and `class`
where it is read, which is a second inconsistency in the same feature.

**Direction:** visit the path node and emit a token per segment. The
kinds want deciding together with the declaration case rather than
patched one at a time.

## 024.20 `contains?` treats an exclusive end offset as inclusive

**Status:** open, and it blocks a correct answer 0.2.0 had to settle for
approximating.

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`contains?`,
`locate_in_block`), `core/lib/ovallsp/parser_service.rb` (the receiver
position a candidate records)

Prism's `end_offset` is one past a node's last character. `contains?`
compares `offset <= end_offset`, so an offset that sits *just past* a
node is answered as being inside it. The consequence is not academic: a
method-call candidate records its receiver's position as one character
inside the receiver, which for a receiver ending in `)` is the `)` -- and
the receiver's own last argument ends exactly there. `wrap(Widget.new).go`
therefore resolves the receiver to `Widget`, and `unknown-method` reports
a call that runs.

Measured: making `contains?` exclusive fixes it and **fails 39 examples**,
because every caller that hands it an LSP range end -- whose end is
likewise exclusive -- depends on the current rule. The fix is the rule
plus every call site, which is a change of its own size.

What 0.2.0 did instead: `locate_in_block` answers `Types::UNKNOWN` for a
position inside a block whose receiver is not a generic. Descending into
the body is the right answer and was tried -- it produced **230
`unknown-method` reports the shipped line never made**, across Ruby
3.4.7's own stdlib, because descending is exactly what stops masking the
mis-resolution above (`s[:dependencies].map { }` reported as "Symbol has
no method named `map`"). Returning the *enclosing call's* type, which is
what the code did before, is equally wrong in the other direction and is
what made `argument-type` report a string literal inside
`opts.on("-x") do` as an `OptionParser`. Unknown is the only one of the
three that no check acts on.

**Direction:** make `contains?` exclusive, then fix each caller that
passes a range end to pass the last character instead. `mismatched_arguments`'s
`infer_at(document, range[:end])` is the clearest of them -- its own
comment already explains that it wants the argument's last character and
relies on the inclusive rule to get it. With that done, `locate_in_block`
can descend and hover becomes right inside every block.

## 024.19 The argument-type check judges against a class the receiver is not

**Status:** open. Reported by an independent review that drove the engine
over 25 installed gems; not reproduced from a fixture here, which is why
it is recorded rather than fixed.

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`sole_declared_overload`)

A receiver whose constant path the workspace does not declare reaches
`WorkspaceIndex`'s documented simple-name fallback -- "名前ヒューリスティック",
the one that answers with whatever class shares the last segment. The
unknown-method check has `closed_nominal?` to stop exactly there; the
argument-type check has no equivalent, so it can resolve
`::Vendor::Gadgets::Widget` to an unrelated `Widget` and type-check
against that class's signature.

There is no second report to notice it by, and an earlier version of this
entry had that backwards. `unresolved_constant_findings` skips a
candidate the index resolves (`engine.rb:579`) — and the resolution that
makes the argument check misfire is the same one — so precisely when the
fallback fires, the full constant is *not* reported unresolvable. Only
its unresolvable prefixes are. Verified against a two-file corpus:
`::Vendor::Gadgets::Widget.make(1)` with a workspace `class Widget`
reports `::Vendor::Gadgets` and `::Vendor`, never
`::Vendor::Gadgets::Widget`.

Reported instance: `prism-1.9.0/lib/prism/translation/parser.rb:320`,
`::Parser::Source::Comment.new(build_range(...))` reported as "`new`
expects Location here, but Parser::Source::Range is given" -- where
`Location` is Prism's own type, not the `Parser` gem's.

**Direction:** the check needs the receiver it was written against, not
the one the index guessed. Either gate on the same closedness the
unknown-method check uses, or require the resolved name to end with the
constant path as written. A fixture has to make the simple-name fallback
fire, which the current spec's RBS shape does not.

## 024.18 The unassigned-`@ivar` check cannot enumerate what it needs to

**Status:** open, and **blocked on 024.R7** for the part that needs it.
Three of the five shapes are closed in 0.2.0 by staying silent rather
than guessing: a class-body call this analysis does not model (which
covers every gem macro), a view that renders anything, and everything
rounds 3 and 4 fixed. What is left is *precision* -- turning those two
silences back into answers -- and one shape that is still wrong rather
than silent, and one that is wrong only at depth two or more:

- a view rendered by *another* controller's action (`render "users/show"`
  from elsewhere) sees only its own controller's ivars;
- `UsersController < BaseController < ApplicationController` with the top
  of the chain not yet read. The depth-1 guard covers
  `UsersController < ApplicationController`; applying the same rule to
  every class read is the correct depth but cannot be told from the
  ordinary case, because the last class a workspace declares inherits
  from a gem that no document will ever exist for. Separating "a
  workspace class not read yet" from "a base class in a gem" is exactly
  what R7's attribution provides.

Recorded under the rule in `CLAUDE.md` about a fix aimed at a symptom: three consecutive review rounds each found a *new*
shape where this check warns on code that renders, and each round's fix
addressed the shape rather than the class.

**Area:** `core/lib/ovallsp/server.rb` (`assigned_ivars_for` and its
guards), `core/lib/ovallsp/diagnostics/engine.rb`
(`unassigned_ivar_findings`)

The check reports an `@ivar` a view reads that the controller never
assigns. To be safe it needs a *complete* enumeration of the assignments
a view can receive, and it guards the cases where it knows it cannot get
one: `instance_variable_set`, a mixed-in module, an unmodelled callback
form, an unread superclass, a shape the walk does not fold.

The shapes found round after round, each a warning on a working page:

| round | shape | fix that round applied |
|---|---|---|
| 3 | `@user \|\|= ...`, an assignment in a block, a `case`, a `rescue`, a multiple assignment | count assignments syntactically instead of by type inference |
| 4 | a superclass the index had not read yet | insist the immediate superclass was read |
| 5 | a gem's class-level macro (`load_and_authorize_resource`, `expose`, Devise, ActiveAdmin) | — |
| 5 | an ivar assigned in a partial the view renders | — |
| 5 | a view rendered by a *different* controller's action | — |

The list does not converge, and the reason is structural: **Ruby has
unboundedly many ways to assign an instance variable that this analysis
cannot see**, and a gem's class-level macro is the ordinary case, not the
exotic one. The same repository already draws this line correctly
elsewhere -- README says the unknown-method check stays silent on classes
inheriting from a gem, "so most controllers and jobs", because reporting
there means guessing. This check reports there.

**Direction: ask the Runtime Agent, rather than adding a sixth static
guard.** This is the answer to the question the static approach cannot
reach, and it closes a whole class rather than a shape.

The Agent has the real application loaded. It cannot say *what* a gem's
macro assigns -- that would mean executing the action -- but it can
report a controller's actual `_process_action_callbacks` chain, which is
exactly where `load_and_authorize_resource`, `expose`, Devise and
ActiveAdmin install themselves. Comparing that chain against the methods
the workspace defines answers the question this check actually needs:

> is every source that contributes to this action one this analysis has
> read?

A callback the workspace cannot account for means stay silent. That
subsumes the gem-macro shape, the concern shape, and every framework
callback at once -- and it is the same shape of question the ancestry
registry already asks the Agent, so the transport, the deferral and the
"answer arrives later" handling all exist.

Two of the five known shapes are *not* covered by it and stay static
work: an ivar assigned in a partial the view renders (collect ivar writes
from the partials a template renders, which is a parse away), and a view
rendered by another controller's action (`render "users/show"` from
`AdminController`; the index already knows every literal render target,
so this is a reverse lookup rather than new information).

Until that exists the check does not meet its own stated bar -- "a wrong
report is worse than a missed one" -- on gem-backed controllers, which is
most of them. Whether 0.2.0 ships it meanwhile is a decision about the
release, not a defect to patch in the current change set.

## 024.14 Workspace-wide diagnostics do not fire against the real Rails fixture

**Status:** open
**Area:** `core/lib/ovallsp/workspace_diagnostics.rb`, `core/lib/ovallsp/server.rb`

0.2.0's workspace pass is covered by Server-level specs (a mistake in an
unopened file is reported, cleared, re-reported on a disk change, and
refreshed when the answers change workspace-wide) and by unit specs for
the pass itself. It has **no E2E row**, because the example written for
one did not pass: a probe file carrying `UnopenedProbe.new
.definitely_not_here`, present in `spec/fixtures/rails_real` before Core
starts and never opened, produced no diagnostic within 45 seconds.

**A diagnosed cause, not yet fixed.** `republish_open_diagnostics` ends
with `start_workspace_diagnostics`, which calls `begin_pass` --
invalidating whatever pass is running -- and `WorkspaceDiagnostics#run`
restarts from `uris.first` with no resume point. That method is called
from six sites, two of which are *loops*: the ancestry drain (which
drains until the queue is empty) and the model-refresh batch (once per
batch). On a real Rails
app each iteration therefore aborts an O(workspace) pass and starts a new
one from zero, and each new one takes the same global index mutex. That
is a credible mechanism for the 45-second silence above, and it is not
among the three causes guessed at below.

The direction is to coalesce rather than restart: a request arriving
while a pass runs should set "run once more when this one finishes"
instead of spawning a pass of its own. Deliberately *not* done in this
release. It is a concurrency change, the harm is reasoned rather than
measured, and the deterministic test it needs -- one that makes the
overlap real rather than racing it -- is the part that is not cheap. A
half-tested concurrency change made late in a review loop is how a change
set drifts. Its own task, with the 45-second reproduction as the
acceptance test.

What *was* fixed here: `workspace_findings_for` recorded deferred
ancestry questions and never asked them. The buffer path drains in an
`ensure`; this one now does too, so a receiver deferred in an unopened
file is answered rather than waiting for someone to open a buffer.

A second gap in the same pass was found when 0.1.11-0.1.13 were merged
in and the whole branch was reviewed: `workspace_findings_for` built its
semantic context without `assigned_ivars:`, and
`Engine#unassigned_ivar_findings` returns [] without it -- so the
unassigned-`@ivar` check (G16) never ran for any view nobody had open,
which is most of them. The pass does visit `.erb`;
`WorkspaceDiagnostics#language_id_for` exists for that. Fixed on the
merge branch, with a spec that fails without it. It is listed here rather
than as its own entry because it is the same capability's E2E story.

The capability row was withdrawn rather than marked PASS on the strength
of the in-process specs — the document's own rule is that a capability
with no E2E row is not a capability, and marking it anyway is exactly the
failure that rule exists to prevent.

Three causes were guessed at before the one above was found, and they
are kept because none is ruled out and any could compound it: the pass
runs before the Runtime Agent is ready and the later refresh does not
reach it; the receiver is not `closed_nominal?` in a real Rails app the
way it is in the fixture-free specs; the pass never starts at all in that
configuration.

**Direction:** fix the restart-without-resume above, then reproduce
against `spec/fixtures/rails_real` directly to see whether anything is
left, and restore the row with an E2E example behind it.

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

## 024.R2 Argument *type* checking (done, 0.2.0)

**Status:** done — shipped in 0.2.0, as the narrow version this entry
described: the expected type comes from an RBS/RBI declaration, the
signature must have exactly one overload and no `*rest`, and both the
declared and the inferred type must be concrete classes with no ancestor
relation between them. Everything else stays silent.

Two false positives were found while building it, both by mutating the
new code rather than by reading it:

- `Signatures::Environment#ancestors` resolves a *qualified* name, so
  asking with a bare one reported every stdlib subclass as incompatible
  with its parent — an `Integer` passed where `Numeric` is declared.
- RBS's `int`/`string`/`boolish` are aliases meaning "anything that
  converts", not classes, so an object of an unrelated class satisfies
  one. They are excluded by the same rule that tells them apart from Ruby
  constants: capitalisation.

A third, pre-existing, was found on the same lookup: `HierarchyIndex`
reports a class's own entry already qualified, so `rbs_resolves?` asked
for `::::Widget` and found nothing — meaning anything a project declared
in its own `sig/` without also writing it in Ruby was reported as an
unknown method. Both call sites now share one helper.
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

**Status:** open — roadmap. Its three 0.2.0 rows are done; the table
below carries a **shipped in** column so the entry can be read as a
record rather than only as a plan. Two of the three shipped outright;
whole-project diagnostics shipped without a capability row, because the
E2E example written for it did not pass (024.14) -- README marks that row
⚠️ and both changelogs say so.

Pylance is the closest well-known reference point for "what a language
server is expected to do" in a dynamically typed language with optional
type declarations, so it is a useful yardstick — not a target to copy.
Rows Pylance has that make no sense here (Jupyter support, IntelliCode's
ranked completions, Python-specific stub packaging) are deliberately
absent rather than listed and dismissed.

Capabilities were read from the `initialize` response and the code, not
assumed. As of 0.2.0: `hoverProvider`, `documentSymbolProvider`,
`definitionProvider`, `referencesProvider`, `renameProvider`,
`workspaceSymbolProvider`, `completionProvider`, `signatureHelpProvider`
and `semanticTokensProvider`. Everything below without a "shipped in" is
still absent.

| Pylance capability | OvalLSP before it | Planned for | Shipped in | Notes |
|---|---|---|---|---|
| Diagnostics across the whole project | Open files only | **0.2.0** | 0.2.0, no capability row (024.14) | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.0** | 0.2.0 | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.0** | 0.2.0 | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.0** | — | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.0** | — | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.0** | — | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.0** | — | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.0** | — | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
| Auto-import / add `require` | None | **0.4.0** | — | Much weaker payoff than in Python: Rails autoloads, and plain Ruby projects mostly `require` at the entry point. Worth revisiting only after the plain-Ruby story (024.R1) exists. |
| Type checking strictness levels | One fixed set of checks | **0.4.0** (as per-check severity) | — | Pylance's basic/strict switch matters because its checks are numerous and opinionated. With the checks this engine has, a per-check severity setting would cover the same need more simply. |
| Signature help with active parameter tracking | Signature label only | **0.4.0** | — | Already useful; highlighting which argument the cursor is in is a refinement, not a gap. |
| Generating type stubs from source | RBS/RBI are read, never written | not planned | — | Interesting for library authors, irrelevant to the Rails application developer this Preview targets. |

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

## 024.R5 A reopened gem class still looks closed (done, 0.1.7)

**Status:** done — shipped in 0.1.7. Measured against the same real
application that reported it: 2 diagnostics before, 0 after.
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

**Direction (superseded — kept because the disproof is the useful part):**
ask the Runtime Agent for `Object.const_source_location`, and treat a
constant defined outside the workspace root as one whose real method set
is unknown here.

**`const_source_location` cannot answer this.** Measured against the same
application, in the environment the Agent actually boots:

| Constant | `const_source_location` |
|---|---|
| `ActiveSupport::TestCase` | `activesupport-8.1.3/lib/active_support/dependencies/autoload.rb:41` |
| `ActiveRecord::Base` | the same `autoload.rb:41` |
| `ApplicationController` | `zeitwerk-2.8.2/lib/zeitwerk/cref.rb:47` |
| `ApplicationRecord` | the same `cref.rb:47` |
| `Ovaldev::Application` | `config/application.rb:10` |
| `String` | `[]` |

It reports where the constant was *registered*, not where the class was
written. Every `ActiveSupport::Autoload` constant points at one line of
`autoload.rb`, and every Zeitwerk-managed constant — which is every class
in `app/` — points at one line of `cref.rb`. So the rule "defined outside
the workspace root means not ours" would classify `ApplicationController`
and `ApplicationRecord`, the application's own classes, as foreign. That
is the same bug pointed the other way, and worse: it would silence the
check across all of `app/` instead of misfiring twice in one file.

Two further approaches were measured and rejected:

- **Walk every constant and record its origin** (the cheap precursor to
  024.R7). `Module#const_get` on an autoload-registered constant *runs
  the autoload*: the walk raised `Gem::LoadError: listen is not part of
  the bundle` in `active_support/evented_file_update_checker` before
  finishing. Enumerating constants is not a read-only operation, and an
  Agent that loads arbitrary code to answer a diagnostic question is not
  one worth having.
- **Report the runtime's method set for the class**, the way model
  methods already are. It fixes `parallelize` and not `fixtures`: the
  Agent boots `config/environment.rb`, not `rails/test_help`, so
  `ActiveSupport::TestCase.respond_to?(:fixtures)` is genuinely `false`
  in the process being asked. Runtime truth is the wrong instrument when
  the truth differs per environment, and the file in question is the one
  file that only ever loads in a different one.

**Direction (measured, and what 0.1.7 implements):** ask the Agent for
the class's **ancestors**, and compare them against `Object.ancestors`
taken in the same process. The static claim being tested is precisely
"this class's ancestry is complete", so test it against the ancestry:

```
PlainWorkspaceThing      8 ancestors,  0 beyond Object's
ActiveSupport::TestCase 28 ancestors, 20 beyond Object's
```

Using the running process's own `Object.ancestors` as the baseline is
what makes this robust: an application that mixes into `Object` (this one
mixes in four modules, from Active Support and JSON) calibrates the
baseline itself, so no list of "expected" ancestors has to be maintained
or guessed. A class carrying ancestors beyond it that the workspace does
not declare and RBS does not know is one the workspace did not write
alone — so the chain the static index believes is complete is not, and
the check stays silent for that receiver.

The question is asked of **every workspace-declared link in the chain**,
not just the receiver. Reopening `ActiveSupport::TestCase` makes that name
workspace-declared, so every `class FooTest < ActiveSupport::TestCase`
then has a static chain that reaches BasicObject *through* it — while the
subclass itself is a genuine workspace class the Agent rightly cannot
place. Asking only about the receiver left every test file in the project
reporting the gem's whole API as unknown: the same false positive, one
level down. The implicit `Object`/`Kernel`/`BasicObject` tail is skipped,
since those are not links the workspace wrote.

Cache per class; ancestors cannot change without a restart. Ask lazily,
for the names the check is actually about to report on, rather than
enumerating anything — that is a handful of names per session, and it
avoids both the load-everything hazard above and any dependency on the
index being built before the Agent answers.

Modules need no special case: a module's static chain never reaches
BasicObject, so `chain_reaches_root?` already treats every module as
open. Confirmed against the same fixture — `module ActiveSupport` indexes
as the single ancestor `::ActiveSupport`, and nothing is reported for it.

A second, currently latent instance of the same mistake is answerable
from the Agent too, though not by the same request.
`unresolved-constant` reports any constant that is neither in
the workspace nor in RBS, which in a Rails application means every gem
constant: measured against `config/application.rb`, it reports `Rails`
and `Bundler` as unresolvable. It does not reach users today because the
check only runs in `standard` mode and the extension never sends
`diagnosticsMode`, so `safe` is the only mode reachable -- but the check
is unusable as written, and enabling it without this would repeat the
false-positive flood the unknown-method check just came out of.
`Object.const_defined?` from the Agent settles it exactly.

**What shipped**, and the one part the measurement above did not predict:
the ancestor comparison alone does not fix the reported case.
`ActiveSupport::TestCase` is not loaded in the environment the Agent
boots — `config/environment.rb`, not `rails/test_help` — so there are no
ancestors to compare, and the first working version of this still
reported both calls. The autoload registration is what settles it:
Zeitwerk registers the application's own classes by absolute path under
the workspace root, while a gem's `autoload` registers the bare require
path it was written with (`"active_support/test_case"`). So the Agent
answers one of three things per name — the real ancestors, "registered
from outside this workspace", or nothing — and the third leaves the
static reading standing, which is the right answer for a class the
workspace genuinely owns but has not loaded.

**What it still misses**, found by independent review rather than by the
change set's own tests, and worth stating precisely because the ancestor
comparison is the part this entry leads with: a reopened gem class whose
ancestry carries nothing foreign is invisible to it. `class String; def
to_bool; end; end` in an initializer gives `[String, Comparable, Object,
Kernel, BasicObject]` — `Comparable` is RBS-known, so no ancestor
disqualifies it, and a call to an Active Support core extension defined
directly on `String` is still reported. The same holds for any gem class
reopened without mixins (`class Faraday::Connection`). The reported
`ActiveSupport::TestCase` case is fixed by the autoload branch, not by
the ancestor comparison — the comparison covers the loaded-and-mixed
case, which is a different one.

Four further cases the Agent cannot settle, all reported by independent
review and all leaving the check firing where it should be silent:

- **The Agent's process is not the test environment.** It boots
  `config/environment.rb` with no `RAILS_ENV` set, so `development`. A gem
  in `group :test`, or one with `require: false`, is neither loaded nor
  autoload-registered there, so its classes answer `:absent` and the
  static reading stands.
- **A top-level name the workspace and a gem both use.** `resolve_owner`
  starts every walk at `::Object` with no notion of the workspace, so a
  workspace PORO called `Configuration` or `Response` resolves in the
  Agent to whichever gem owns that constant, and *that* class's foreign
  ancestors silence the check for the workspace's own.
- **Engines and monorepos.** `workspace_path?` compares against
  `Rails.root`, so a class autoloaded from `/repo/engines/billing` while
  `Rails.root` is `/repo/backend` reads as defined outside the workspace.
- **Singleton-only provenance.** The Agent reports `Module#ancestors`,
  the instance chain, so a class whose gem origin shows only in its
  singleton class is invisible to the ancestor comparison. Mostly moot in
  practice: a statically visible `extend` already puts the module in the
  singleton chain, where `ancestor_known?` opens the receiver anyway.

A crash-looped Agent is not on this list, and deliberately: once
`AgentSupervisor` gives up, `AncestryRegistry#deactivate!` puts the check
back on the static reading, exactly as if no Agent had ever existed.
Without that the check would defer forever to an answer that cannot come,
which is not degrading gracefully — it is going silent.

Closing all of these needs to know where each *method* came from, not
where the class did, which is 024.R7's territory.

The check remains silent for gem-derived classes reached by superclass
(024.R7 is what lifts that), and behaves exactly as it did in 0.1.6
wherever there is no Runtime Agent to ask.

---

## 024.R6 Reading an instance variable that is never assigned (done, 0.2.0)

**Status:** done — shipped in 0.2.0, scoped to views, which is where the
symptom the entry describes actually appears. A view is handed exactly
what its controller action and callback chain assign, and that set was
already computed for type propagation; everything else receives its ivars
from wherever it likes, so nothing is reported there.

The safety of the check is one distinction: the set is `nil` when nobody
worked out a context and *empty* when an action genuinely assigns
nothing. Collapsing the two would report every `@ivar` in any file no
context could be established for. `nil` is therefore also the answer for
a view outside the naming convention, a view no action renders, a
controller chain containing `instance_variable_set`, and a document whose
Ruby does not parse — each pinned by asserting nothing was logged, since
the rescue above them produces the same silence for the wrong reason.
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

Nothing reports `@usr` where the code meant `@user`. Ruby returns `nil`
for an unassigned instance variable rather than raising, so this is a
mistake the language itself never surfaces: the view renders empty and
nobody is told why.

The information is already here. Controller-to-view propagation infers
the set of instance variables an action assigns, including through the
`before_action` chain (capability H3). A read of an `@ivar` that no
assignment in the effective chain produces is reportable with high
confidence.

**Direction:** report an `@ivar` read when the enclosing method, its
callback chain, and its ancestors contain no assignment to it. Stay
silent where assignments could come from somewhere unmodelled --
`instance_variable_set`, a concern the workspace cannot see -- on the
same standard as every other check here.

## 024.R7 Index what the gems actually define, and keep it fresh (roadmap, 0.3.0)

**Status:** open — roadmap
**Area:** `core/lib/ovallsp/runtime_agent/agent.rb`,
`core/lib/ovallsp/cache/`, `core/lib/ovallsp/diagnostics/engine.rb`

Today the unknown-method check only fires on a *closed* receiver, and a
class is closed only when the workspace can see its whole ancestry. In a
Rails application that is a minority of classes: a controller inherits
from `ApplicationController`, whose parent is in a gem, so the check
stays silent there — correctly, but silently. The result is that the
check works where it is least needed and says nothing where most code is
written.

The running application knows all of it. Measured against a small Rails 8
app: 3027 named modules loaded, 2204 of them attributable to one of 63
gems, contributing 15868 methods defined directly on them. Names only,
that is roughly 365KB — small enough to persist, far too much to send on
every query.

**Direction:**

- the Agent walks loaded modules once, attributing each to a gem through
  `Object.const_source_location` and the `…/gems/<name>-<version>/` path,
  and reports, per class: its own methods, its ancestors, and whether it
  defines `method_missing`;
- Core persists that per gem-version, in the cache store that already
  exists for file summaries. `Gemfile.lock` already contributes to the
  cache key, so the invalidation shape is in place — but it should become
  per gem rather than whole-index, so a single bumped gem re-indexes one
  gem and not sixty-three;
- with that, "closed" stops meaning "declared in this workspace" and
  starts meaning "we know its full method set", which is the honest
  question. Most receivers in a Rails app become closed, and the check
  becomes useful where the code actually is.

**It is also what 024.18 waits for.** The unassigned-`@ivar` check
currently stays silent whenever a controller's class body calls anything
it does not model, because a gem's macro
(`load_and_authorize_resource`, `expose`, Devise, ActiveAdmin) installs a
callback that assigns at runtime and nothing can tell that call apart
from a harmless one. With this index, such a call is attributable: "a
method CanCanCan defines, whose body this analysis has not read" is a
sound reason to stay silent, and a class-body call that resolves to a
*workspace* method that *was* read is a sound reason to report. That
narrows the guard rather than replacing it -- every answer the check
gives today it still gives, and it starts covering controllers it
currently declines. Doing it before this index exists would mean
guessing, which is the thing this check refuses to do. **This is a
required part of R7, not an optional extension of it: 024.18 is not
closed until it lands.**

It also subsumes several entries above: 024.R5's reopened-gem-class case
(the index knows `ActiveSupport::TestCase` is a gem class), and the
latent `unresolved-constant` flood (the index knows `Rails` exists).
024.R5 stays as the narrow, cheap version for 0.1.7 — one question per
constant, no persistence — and is a stepping stone to this rather than a
competing design.

**Risks to settle when building it, not after:**

- what is loaded depends on the environment and on eager loading, so the
  index describes *a* boot, not the gem in the abstract. It must be
  recorded as such and never treated as proof a method is absent unless
  the class was actually seen;
- classes that define methods at runtime (`define_method` in an included
  hook, `method_missing`) are already handled by the existing
  `method_missing` rule, which must apply to gem classes too;
- the walk costs real time on a large app and must not block the first
  query — the same background/degrade-to-static shape the Agent already
  uses.


---

## 024.R8 Completion does nothing until you type a dot (done, 0.2.0)

**Status:** done — shipped in 0.2.0. The entry's own reading was right:
the work was mostly ranking and bounding, not calling the existing pieces.
The order it proposed is the order that shipped (locals, methods on self,
workspace constants, Kernel), with two decisions it left open settled as
it suggested — a hard cap with `isIncomplete`, and a one-character prefix
that returns only the two sources near the cursor.

Two things the entry did not anticipate. The ranking has to be rendered
into `sortText`: an editor re-sorts a completion list itself, so array
order alone pins nothing, and a spec checking array positions passes with
`sortText` deleted. And `WorkspaceIndex#search` matches by substring
because `workspace/symbol` wants that, while a completion prefix means the
start of the name. Filtering `search`'s answer down was the first attempt
and it was wrong: `search` truncates, so on a workspace with more than
`limit` substring matches every prefix match can already be gone -- 250
classes merely containing `art` made typing `art` return nothing at all.
The index gained `#prefix_search`, which applies both the prefix and the
offerable kinds *before* the truncation.
**Area:** `core/lib/ovallsp/server.rb` (`completion_result`),
`core/lib/ovallsp/semantic/query_service.rb`,
`core/lib/ovallsp/semantic/prefix_completion.rb`,
`core/lib/ovallsp/workspace_index.rb` (`#prefix_search`)

`completion_result` matches a bare prefix against the route registry and
nothing else; every other candidate comes from
`member_completion_items`, which returns immediately unless
`receiver_type_before_dot` finds a receiver. So typing `A` offers
`article_path` and stops. The workspace's own classes, the locals in
scope, and the methods callable on self at that position — most of what
anyone types — appear only after the name is already written, at which
point completion has nothing left to do.

This is the most-used completion in any editor, and its absence is the
kind of gap that reads as "the extension does nothing", the same
impression 0.1.6 was written to correct.

**Direction:** a fourth source alongside the route helpers, assembled
from what is already indexed:

- constants the workspace declares (`WorkspaceIndex#search` already
  answers this for `workspace/symbol`, by simple name, case-insensitively);
- locals in scope at the position — `LocalInferencer` already builds the
  environment it would need, but exposes only the type of one expression,
  not the set of names it knows;
- methods callable on self, which is `members_of` against the enclosing
  class's `self` type — the same call `member_completion_items` makes,
  with the receiver taken from lexical scope rather than from before a
  dot;
- RBS-known `Kernel` methods, so `pu` offers `puts`.

**The trap, and why this is not just "call the existing pieces":** a bare
prefix matches far more than a receiver does. `a` in a large workspace
matches thousands of symbols, and an editor that answers with all of them
sorted alphabetically is worse than one that answers with nothing —
VS Code will show them, the right answer will be on page four, and the
user learns to stop pressing the key. So the work is mostly *ranking and
bounding*, which is a different problem from the one the receiver-based
path solves and has no existing answer here:

- locals before methods on self before workspace constants before
  `Kernel`, because that is roughly the order of how close the
  declaration is to the cursor;
- a hard cap, with `isIncomplete: true` so the editor re-asks as the
  prefix narrows;
- and a decision about a one-character prefix, where the honest answer
  may be to return only locals and enclosing-class methods.

None of that is settled, and settling it needs measurement against a real
workspace rather than reasoning — which is why this is scoped as its own
roadmap entry rather than folded into another release's work.

---

## 024.16 The capability E2E suite can skip in full while CI stays green

**Status:** fixed in 0.1.13 -- `ci.yml`'s skip guard now checks both
`spec/integration/real_rails_spec.rb` and `spec/e2e/capabilities_spec.rb`,
by table rather than by a second copy of the check.

Two things the one-line direction below did not anticipate. First, a
guard that failed on *any* pending example would have made this
document's own `NOT YET` status -- "specified, has an E2E row, currently
failing or pending", which `capability_coverage_spec.rb` accepts --
unexpressible; the guard therefore exempts a pending message that says
`NOT YET`, and `spec/meta/ci_skip_guard_spec.rb` asserts that neither
suite's environment-skip message says it. That exemption is an authoring
rule -- a pending row has to *say* `NOT YET` -- so both language versions
of `EXTENSION_CAPABILITIES.md` state it, and the meta spec asserts they
do: a CI-enforced rule recorded only in a YAML comment is one an author
meets as a red build with no way to find out why. Second, the guard was itself
pinned by nothing: deleting the capability row leaves every check in this
repository green, which is the same shape as the gap it closes. That is
what the meta spec is for, following `versionPairing.test.ts`.
**Area:** `.github/workflows/ci.yml`, `core/spec/e2e/capabilities_spec.rb`,
`core/spec/meta/ci_skip_guard_spec.rb`

`docs/EXTENSION_CAPABILITIES.md` states two rules. "A capability with no
E2E row is not a capability" is enforced by
`core/spec/e2e/capability_coverage_spec.rb`. "A capability whose row is
skipped is not shipped" is enforced by nothing.

`capabilities_spec.rb` skips every example when its real-Rails fixture
cannot be prepared (`before(:all)` → `skip` when `available?` is false).
CI has exactly the right guard — "Fail if the real-Rails integration
suite was skipped instead of run" — but it filters on
`spec/integration/real_rails_spec.rb` and does not cover the e2e path.
Measured: forcing `available?` false gives `45 examples, 0 failures, 41
pending` and **exit status 0**, with `capability_coverage_spec.rb` still
green, because it scans the spec file's source text for `it "C5: …"` and
cannot tell a row that ran from a row that was skipped.

Latent rather than live today: `real_rails_spec.rb`'s own guard
incidentally forces the fixture's gems to exist. But nothing states that
dependency, and the two suites reach the fixture by different code paths.

**Direction:** widen the existing CI step's file filter to both paths.
One line. Recorded rather than fixed in 0.1.12 because it is a CI gap,
not a defect in the release, and 0.1.12 has already been rolled back once
for widening past its own subject.

## 024.17 `vscode/src/extension.ts` is covered by no test that runs anywhere

**Status:** fixed in 0.1.13 for the two decisions a user notices --
`documentSelectorFor` and `statusPresentation` moved into
`vscode/src/clientPresentation.ts`, which imports no `vscode`, with
fifteen unit tests -- thirteen behavioural, plus two that assert
`extension.ts` actually calls them (024.10's first attempt exported the
strings but left the choice between them at the call site, so the tests
described code the extension did not reach). `resolveStatus` was added in a second pass: the
extraction had left the "no client" / "the client did not answer"
decision at the call site, where a mutation reporting a failure as "no
client" passed all 167 tests.

Three of the extracted decisions were then found unpinned, all the same
shape: the specs compared the render against the very table it renders
from, and the constant against itself. Relabelling `indexing`, deleting
`agent-unavailable` and emptying the error text each left the suite
green, and a deleted key falls through to the raw-state branch -- the
status bar would read `OvalLSP: agent-unavailable`. The literals are
asserted now, and a further example -- `labels exactly the states the
Core emits` -- reads the four states out of `Server#status_result` rather
than restating them, so a state added on the Core side without a label
here fails the extension's own suite. The remaining
`vscode` wiring -- command registrations, the client bootstrap, the poll
loop's timer -- is still integration-only; running that suite in CI is
the part not done.
**Area:** `vscode/src/extension.ts`, `.github/workflows/ci.yml`

Nine of the extension's ten modules have unit tests. `extension.ts` — the
largest at 812 lines — has none. What covers it is
`vscode/src/test/integration/`, and `npm run test:integration` appears in
no workflow; `ci.yml` runs `test:unit` only.
`vscode/scripts/verify-installed-extension.sh` is likewise manual.

The uncovered surface is exactly the layer `EXTENSION_CAPABILITIES.md`
says the E2E suite structurally cannot see: the `documentSelector`, all
nine command registrations, the `ovallsp/status` poll loop, and the
client bootstrap. No defect was found in it by reading — the `.erb`
selector, the watcher glob and the version handshake are all correct —
but "the extension's tests are meaningful" is true only of the nine
modules that have them.

**Direction:** either run the integration suite in CI, or extract the
remaining decisions the way 024.10 extracted `clientTeardown.ts`.

---

## 024.15 The index's answers depend on which file was edited last

**Status:** fixed in 0.1.13 by option 1 below, in the half of it that
carries the cost. Option 1 called for both collections to be maintained
sorted at write time; `@by_symbol`'s entry lists are, and
`@by_simple_name` is still an unordered Set sorted per read -- but by one
centralised reader rather than by each of eleven, which is the property
the option was chosen for. Sorting a Set on insert would have cost every
`replace_file` a sort of every bucket its declarations touch, against a
read path that filters first and so sorts a handful of elements.

Entry lists are sorted by `[uri, line, character]` in `replace_file`, and
`ordered_symbol_ids` is the one place a query reads `@by_simple_name`, ordered
by `[name, kind, owner]` because one class has several SymbolIds that
share a name. `search`'s `rank` keeps exact-match-first and gains a tail,
since a truncated result cannot have ties decided by index order.
Measured as the entry asked: 2,000 files with one class reopened in 500
of them goes 7ms -> 61ms in `replace_file`, negligible against Cold
Index. The *read* paths needed measuring too and were not measured at
first: a bucket is keyed on the simple name, so `resolve_type_name`
sorting a whole bucket before its caller filtered it cost 3.7ms per call
in a workspace of 1,200 service objects each defining `call`. Filtering
before sorting -- the two commute here -- restores 51us with the same
order.

`search`'s ranking key grew from one element to seven, which is the
largest cost this change adds to a read: the picker opens with an empty
query, so every declaration in the workspace is a match, and the index
mutex is held throughout. Ranking the 32,000 matches an empty query
returns for 2,000 files that each declare a class and fifteen methods
measures 68ms sorting
all of them, 17ms with `min_by(limit)` -- which answers identically
because the key is total -- against 10ms for the one-element key it
replaced. About 7ms more per query, for an answer whose membership no
longer depends on which file was saved last.

The first version of that paragraph claimed parity, measured end to end
through `search`, where building the 32,000-entry match list dominates
and hid the difference. A cost claim about a sort has to time the sort.

Neither that nor the filter-before-sort above is a *behavioural* line, so
no example in the suite fails when either is reversed -- which is exactly
why they need `spec/meta/workspace_index_cost_spec.rb`. Both read as
tidying: a `select` after a `sort` looks no worse than before it, and
`sort_by { }.first(n)` is the more familiar idiom.

Every spec that could regress on re-index re-indexes, and all
twenty-three decisions are pinned by mutation -- deletions and
*permutations* both, which is a distinction the count did not make until
four keys turned out to survive having their elements reordered.

Reaching that took several passes, and
the misses are the instructive part: the `search` tail first shipped
behind a fixture whose eight files shared a single SymbolId; the ranking
key's `uri` and `line` elements were satisfied by fixtures that ordered
files and lines the same way; `find_by_simple_name`'s spec used one name
in two files, which is one SymbolId, so it never walked the collection it
was written for; the ambiguous-name spec asserted only an absolute answer
while re-indexing the first-inserted file, which lands on that answer by
accident -- and correcting it went one step too far, gaining a
before/after assertion *and* moving to the second-inserted file, which
leaves the collection in the order it already had, so the new assertion
could not fail either. Which file to re-index depends on the assertion
shape, and an example carrying both needs the first-inserted one. And
the `line`/`character` pair went the same way as the `uri`/`line` pair
had, each fixture holding one of the two at zero while varying the other,
which any order of the pair satisfies. Then the same again one level up:
deleting an element of a key is not the only way to break it, and
`[kind, name, owner]`, `[name, owner, kind]`, `rank` with uri before the
name and `rank` with owner before kind each passed the whole suite while
changing where go-to-definition lands. Every element of a sort key is two
decisions -- that it is there, and where. The
last of those was then made twice: the fixture written for the ordering
key's `kind` element re-indexed the second-inserted file, so it could not
fail either, and the round that added it published "all fifteen decisions
are pinned" on its strength. A fixture that passes has not shown that
anything is tested.
**Area:** `core/lib/ovallsp/workspace_index.rb`

`@by_symbol` maps a SymbolId to a list of `[uri, declaration]`, and
`@by_simple_name` maps a name to a Set of SymbolIds. Both are in
*insertion* order, and `replace_file` removes a uri's entries and then
appends the new ones — so re-indexing a file moves its entries to the
back of every list they are in. Editing a file, without changing a single
declaration, changes the order.

These readers then take `.first` of such a list, or truncate it. The list
was miscounted twice before it was written one reader per row, and a
later review found four more (`Server#current_observation_fingerprint`,
`MethodResolver#names_for_type`'s visibility lookup,
`Server#route_helper_definitions`, `Rename::Planner#locations_for`) — so
it is a sample, not an inventory. That is an argument *for* the storage
fix rather than against it: ordering the storage covers readers nobody
enumerated, which is exactly what converting a subset does not.

| reader | what changes |
|---|---|
| `Server#find_controller_uri` | which controller file supplies a view's instance variables |
| `QueryService#model_definition_locations` | where go-to-definition on a column or association lands |
| `find_by_simple_name` | where go-to-definition on a bare constant lands |
| `resolve_type_symbol_locked` | which class an ambiguous bare name resolves to — and with it the ancestry chain, the unknown-method check, find references and rename |
| `QueryService#source_signatures` | whose parameters signature help shows |
| `MethodResolver#build_candidate` | whose visibility gates the private-method check |
| `search` | which symbols survive `workspace/symbol`'s result limit |

All measured, all reproducible by adding one comment line to a file. This
predates 0.1.12 and has shipped in every published version.

### Why it is deferred rather than fixed

0.1.12 tried to fix it four times and produced three incomplete fixes and
two regressions:

- round 8 pinned `.first` with a spec asserting the current answer, which
  turned out to be an accident rather than a behaviour;
- round 9 sorted `class_declarations` by uri — which backs two of the
  seven rows above and leaves five, and
  `sort_by` is not a stable sort, so entries sharing a uri were still
  arbitrary, and the *source* order that insertion had at least preserved
  within a file was lost;
- round 10 replaced that with a per-SymbolId `ordered_entries`, which
  dropped the cross-SymbolId ordering round 9 had added — a straight
  regression of the same bug, in the same method;
- round 11 added a second sort on top to restore it.

Each attempt bolted an ordering onto a *reader*. That is fixing the
symptom: the readers are not wrong to want a stable answer, the storage
is wrong to have an unstable one. Every reader added is a new place to
forget, which is the same structural mistake 0.1.11 was spent on for
qualification.

### The fix this actually needs

One of these two, decided before any code is written:

1. **Make the storage ordered.** `@by_symbol`'s per-SymbolId list and
   `@by_simple_name`'s Set are maintained sorted by `[uri, line,
   character]` at write time in `replace_file`. Every reader then
   inherits the order without knowing about it, and there is exactly one
   place that knows what the order is. Cost: `replace_file` does an
   insertion sort per declaration; measure it against Cold Index on the
   real Rails fixture before committing to it.
2. **Stop taking `.first` of a collection with no order.** Go-to-definition
   and find-references are `Location[]` in LSP — a class reopened across
   four files genuinely has four definitions, and answering with all of
   them is a better answer than answering with an arbitrary one. This is
   a larger behavioural change and needs the `.first` callers examined
   one at a time; `find_controller_uri` cannot return several, so it
   would still need a stated rule.

Option 1 is the smaller change and the one that matches this codebase's
own habit of putting a rule in the one place that owns the data. Option 2
is the better answer for the three readers that are LSP list responses.
They are not exclusive.

Whichever is chosen, the spec has to exercise **re-indexing** — every
0.1.12 attempt was pinned by a spec that built the index once, which is
exactly the state in which the bug is invisible.

---

## 024.13 A reopened core class looks closed, in both directions (0.3.x)

**Status:** open
**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

`closed_nominal?` calls a receiver closed when every ancestor is
workspace-declared or RBS-known. A workspace that reopens a core class —
`lib/core_ext/array.rb`, idiomatic in Rails — satisfies that: `Array`'s
chain is `Array, Object, Kernel, BasicObject`, all known. But the
workspace does not own `Array`, and gems keep adding to it, so the check
is wrong in both directions on such a receiver:

```ruby
class Array
  def to_sentence_ish = "x"     # any reopening closes the chain
end

a = [1, 2, 3]
a.second                        # ActiveSupport's; reported as unknown
a.totally_bogus_method          # genuinely unknown; correctly reported
```

This is 024.R5's problem one level out — the class is *partly* the
workspace's — and 024.R5's machinery already solves it when a Runtime
Agent is connected: the Agent reports `Array`'s real ancestors, the check
sees ancestors it cannot account for, and stays silent. Without an Agent
(an untrusted workspace, a plain Ruby project) there is nothing to ask.

0.1.9 made this concrete. Array literals already inferred as `Generic`
and so were never in either check; **hash literals were `Nominal("Hash")`
and were**. Rendering them as `Hash[Unknown]` (024.12) takes them out,
because the engine's gates ask for a plain class name.

Teaching the gates to read a container receiver — correct everywhere
else, and what `Types.base_nominal` exists for — would have put both
literals in, array ones for the first time. Independent review measured
what that costs: `[1,2,3].second` reported as unknown against a workspace
that reopens `Array`, because ActiveSupport defines it and stdlib RBS does
not. So the gates keep asking for a plain class name.

What 0.1.9 therefore changes, and it is a change rather than a
preservation: a hash-literal receiver is no longer checked. On a workspace
that reopens `Hash`, `h = {}; h.totally_bogus_method` was reported and now
is not, and so is an argument-count mismatch on such a receiver. The same
gate previously reported `{}.deep_symbolize_keys` — ActiveSupport's —
as unknown, which is the false positive this direction avoids. Fewer
reports either way, which is the direction this check is meant to err in,
but the true positives are lost with the false ones.

**Direction:** treat "the workspace declares part of this class" as
distinct from "the workspace owns this class", which is what the Agent
already answers for 024.R5. Scheduled with 024.R7, since a gem index is
what makes the answer available without an Agent too.
