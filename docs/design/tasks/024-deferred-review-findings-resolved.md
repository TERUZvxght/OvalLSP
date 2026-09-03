# Task 024: Deferred review findings — resolved

**The other half of [`024-deferred-review-findings.md`](024-deferred-review-findings.md),
and not a second register.** Everything that governs an entry — the
`yaml` grammar, the numbering, the rule that an entry is deleted only
once nothing in the tree cites it — is stated there and applies here
unchanged. This file holds the entries whose `status` is `fixed` or
`done`; that file holds the open ones and **indexes both**, so a reader
holding `024.N` opens the file they have always opened and finds the
row wherever the entry lives.

Split in 0.3.0 under `024.R9`, on a measurement: 239 of 287 entries
were resolved — 15,670 lines of a 20,703-line file, 75.7% — so the file
every session read, and every scripted edit risked, was three-quarters
archive. `024.225` records a scripted edit that took it from 11,555
lines to 25,878 twice over, with the diff too large to read.

**Numbers did not change and the path of the live file did not move.**
`024.R9` proposed relocating the register to the top of `docs/`; 26
tracked files name it by path, and none of them had to change. Entries
keep their `024.` prefix because it is quoted throughout the tree — 278
files cite one — so this is a move plus an index, never a renumber.

Nothing appends here. An entry arrives when it is resolved, by being
moved out of the live file.

## 024.1 Duplicate, unused implementation of the controller callback chain

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the unused copy is deleted, along with `#infer_ivars_for_method`, `#find_static_render_target`, `#find_method_node` and the `MethodLocator` visitor that existed only to serve it. Its specs were re-anchored rather than dropped: the ones covering pieces the Server still calls now go through those pieces (`method_nodes` + `#infer_ivars_for_method_node`, `#static_render_target_for_node`), and the seven chain behaviours that had no equivalent on the live path — `except:` on both sides of it, an action overriding a callback's assignment, an unresolvable `if:` condition, a conditional `skip_before_action`, a missing callback method, and the multi-name forms of `before_action` and `skip_before_action` — were ported into `server_views_spec.rb`, where each fixture was checked to yield a *different* answer under the opposite behaviour.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the buffer case is now a spec of its own, so `@seen_uris << uri` sitting above the open-buffer early return is pinned rather than merely claimed.

**Area:** `core/spec/ovallsp/cold_indexer_spec.rb`

The comment says the spec covers a file already open in a buffer, but no
`DocumentStore` entry is created, so that branch is never exercised.
`@seen_uris << uri` sits above the open-buffer early return and nothing
pins that ordering. No live consequence: the deletion sweep verifies
absence with `File.file?` rather than trusting `seen_uris`.

**Direction:** add the buffer case, or trim the comment to what the spec
actually asserts.


## 024.8 Ownership retirement on `exited() && known.size === 0` is unpinned

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the two assignments are deleted; the `ownedSessionId` one is load-bearing and pinned by a new regression test, and `ownedGroupId` went with it for symmetry (it is set only from a validated root row whose `pgid === pid`, and such a row also satisfies the expansion test against `ownedSessionId`, so `known` cannot be empty in the same pass — no fixture distinguishes that half). The first attempt at this entry deleted them as unable to change any answer, reasoning that the branch is only reached with the root absent and the expansion gate therefore already closed. Independent review disproved both halves: `rootObservedAbsent` is assigned at the *end* of the pass, and the root row can be present but untracked, because `known` only takes the root while the child has not exited. A Core dying inside the ~57ms pre-`setsid` window reaches the branch with ownership still meaningful — on Darwin especially, where `sid` is 0 on every row. Since `terminateOnce` and `waitForAllExit` both refresh after the interval is cleared, retiring ownership there permanently lost the survivor those later passes exist to catch. The `clearInterval` in the same branch stays, pinned by its own test.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.10
```

the four decisions moved into `vscode/src/clientTeardown.ts`, which imports no `vscode` and takes the lifecycle manager and the per-folder maps as parameters rather than reading module state. `extension.ts` now delegates to it and keeps only the `vscode` wiring. Fifteen unit tests cover them, and each decision was checked by mutating it and confirming the suite goes red.

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


## 024.14 Workspace-wide diagnostics do not fire against the real Rails fixture

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: yes
```

**It does not reproduce, and did not need fixing.** A reviewer ran the
procedure this entry describes and got the diagnostic; so did I, on a
real Rails 8.1.3 application: a never-opened file is answered **1.35 s
from process start**, with 42 URIs published. `EXTENSION_CAPABILITIES`'s
**G17** row and its example exist now, and the example fails when the
workspace pass is removed.

What the original measurement most likely hit is a path, not a defect.
`Dir.tmpdir` is `/var/folders/…` on macOS and the server publishes
`/private/var/folders/…`; a test that builds the expected uri from the
un-resolved path waits forever for a notification that has already
arrived under another name. The G17 example calls `File.realpath` and
gives the property its own Core, because the file has to be on disk
*before* the server starts -- which the shared client, started in
`before(:all)`, cannot be given. A first draft of the example wrote the
file afterwards and failed, which is a different property.

Five documents carried consequences of the non-reproducing claim and are
corrected: the missing capability row, README's ⚠️ and its `[^ws]`
footnote, `KNOWN_LIMITATIONS` in both languages, and both changelogs.

**The lesson is not "close entries faster".** It is that an entry
recording a *measurement* should record how the measurement was taken
precisely enough to re-run, and this one did not -- so for two releases
nobody could tell the defect from the harness.

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


## 024.15 The index's answers depend on which file was edited last

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

by option 1 below, in the half of it that carries the cost. Option 1 called for both collections to be maintained sorted at write time; `@by_symbol`'s entry lists are, and `@by_simple_name` is still an unordered Set sorted per read -- but by one centralised reader rather than by each of eleven, which is the property the option was chosen for. Sorting a Set on insert would have cost every `replace_file` a sort of every bucket its declarations touch, against a read path that filters first and so sorts a handful of elements.

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


## 024.16 The capability E2E suite can skip in full while CI stays green

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

`ci.yml`'s skip guard now checks both `spec/integration/real_rails_spec.rb` and `spec/e2e/capabilities_spec.rb`, by table rather than by a second copy of the check.

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

```yaml
status: fixed
kind: defect
released-in: 0.1.13
```

for the two decisions a user notices -- `documentSelectorFor` and `statusPresentation` moved into `vscode/src/clientPresentation.ts`, which imports no `vscode`, with fifteen unit tests -- thirteen behavioural, plus two that assert `extension.ts` actually calls them (024.10's first attempt exported the strings but left the choice between them at the call site, so the tests described code the extension did not reach). `resolveStatus` was added in a second pass: the extraction had left the "no client" / "the client did not answer" decision at the call site, where a mutation reporting a failure as "no client" passed all 167 tests.

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


## 024.21 A qualified constant is coloured half one way, half the other

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. Every segment of a qualified constant is coloured.
target: 0.2.15
released-in: 0.2.15
```

Pre-existing for `Foo::Bar` reads; 0.2.0 is where semantic tokens became a user-visible capability (T1).

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

### Fixed in 0.2.15

Measured before the change, driving `collect` over `x = Ovallsp::Server`:
**one token** — `Ovallsp`, char 4, length 7 — and nothing at all for
`Server`.

`#visit_constant_path_node` records the final segment as `:class` and
walks the parents, recording each as `:namespace`.

**A segment with something after it is a namespace syntactically** — it
is being qualified through, whatever it was declared as — so that half
is decidable here without resolution, and it settles the second
inconsistency the entry names: `module Ovallsp` and the `Ovallsp` of
`Ovallsp::Server` now agree.

**The final segment stays `:class`**, which is what a bare constant read
already gets. Telling a class from a module there needs resolution the
collector does not have, and guessing would be the wrong-answer half of
section 0. That limitation is unchanged and is not what this entry was
about.

**Four examples, and two are the distinguishing ones.** A bare constant
must stay `:class`, or "always namespace" would pass the first two and
be wrong. And the head of a path is reachable twice — the recursion
records it and `super` walks into the same `ConstantReadNode` — so a
duplicate is the obvious way this goes wrong; the encoding is a delta
stream and a zero-delta entry is a token drawn on top of itself.
`A::B::C` gives three tokens and fifteen integers.


## 024.23 The singleton chain did not model `Class`/`Module`

```yaml
status: fixed
kind: defect
released-in: 0.1.14
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`,
`core/lib/ovallsp/parser_service.rb`

Found by driving the engine over real corpora during the 0.2.0 review and
fixed ahead of it, because it was the largest single source of wrong
reports the engine produced and it fired on the most ordinary Ruby there
is: `private`, `attr_reader`, `private_constant`, `alias_method`,
`include` and their neighbours, reported as unknown methods whenever
written in the body of a workspace class whose ancestry was otherwise
fully known.

Two independent causes, either of which alone still produced the report:

1. `HierarchyIndex#ancestors(singleton: true)` walked the superclass
   chain and appended no tail, so `Class`, `Module`, `Object`, `Kernel`
   and `BasicObject` were not in the chain and `Module#private` could not
   be found. The instance side has always had `DEFAULT_OBJECT_CHAIN`.
2. `ParserService` used one flag for two questions — "does an unqualified
   `def` here declare a singleton method" (true only inside
   `class << self`) and "is `self` here a Class/Module object" (also true
   in a class body and inside `def self.x`). Receiverless calls took the
   first, so they were resolved against the instance chain.

A third cause had to be closed in the same release rather than recorded.
Reading a `define_method` body as an instance -- which cause 2's fix
makes correct -- surfaced that `attr_reader`/`attr_writer`/`attr_accessor`
were never recorded as declarations at all, so Thor's
`attr_accessor :options` became a *new* wrong report. A fix that hands a
user a report they did not have before is not a fix, so the parser now
records what those DSLs define (`ATTRIBUTE_DSLS`), with a dynamic
argument recording nothing.

Measured with `scripts/corpus_diagnostics.rb`, each revision against one
fixed corpus: `core/lib` 60 → 4 `unknown-method` findings, ActiveSupport
8.1.3 785 → 265, Ruby 3.4.7's standard library 15,982 → 3,848, **and no
report introduced anywhere in it**. (0.1.14's own entry quoted 62 and 776
for the "before" side, from a different tree; 0.1.15 corrected both.)

0.1.14's fix was itself wrong in five ways, each found by independent
review of the released code and fixed in 0.1.15: the tail was looked up
for singleton methods rather than instance ones, it was keyed on the
terminating ancestor rather than the receiver, `define_method` inside
`class << self` was read as instance-self, and `instance_eval`/
`instance_exec` were listed with it for no stated reason. A fifth --
`attr_*` recorded from inside method bodies and blocks -- was attempted
three times and withdrawn; 024.31 records why the shipped parser
attributes `attr_*` lexically, exactly as 0.1.14 did. Wrong `argument-count` fell 36 → 13 and `unknown-route-helper`
48 → 8, the latter because a `*_path` name that resolves to a declaration
is no longer guessed at -- which reduces 024.24 without fixing it.


## 024.24 Every `*_path`/`*_url` call is a missing route when no routes are loaded

```yaml
status: fixed
kind: defect
released-in: 0.2.0
user-visible: yes
```

Pre-existing — reproduced identically on `main` (0.1.13).

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

**Fixed in 0.2.0**, as the direction recorded here said: `RouteRegistry`
answers `#loaded?`, meaning a snapshot has been applied, and the check
returns nothing until one has. `@generation` already counted
applications rather than routes, so a Rails application whose `routes.rb`
declares nothing still loads and the check is still on there — which is
the distinction the old gate could not make.

What made it worth doing now rather than deferring again: 0.2.0 publishes
diagnostics for files nobody opened, so the same false report went from
the open buffer to every file in the project. A reviewer reproduced that
against a two-file plain-Ruby workspace with trust declined.

Three examples: a loaded table that lacks the name still reports, a table
that loaded empty still reports, and a registry no snapshot ever reached
says nothing.


## 024.25 A Markdown-parsing spec is the wrong shape for "these two documents must agree"

```yaml
status: fixed
kind: defect
user-visible: no
target: 0.2.12
released-in: 0.2.12
user-visible-note: >
  A rolled-back internal guard. Nothing about the product changed, so
  there is nothing to tell a user; what is open is a decision about how
  this project keeps its own notes.
```

**Rolled back** rather than fixed. This entry is the deliverable; there
is no code change to point at.

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

### The direction that was actually needed, and taken

Two candidates were named. The first was chosen, and this file's format
is the result:

1. **Give the data a schema instead of parsing prose.** ✅ Every entry
   carries a fenced `yaml` block, and `core/spec/meta/deferred_findings_spec.rb`
   reads that rather than hunting for `**Status:**` in running text. The
   parser did not disappear — the grammar did the work: one delimited
   shape instead of however many prose can take. Nine of its decisions
   were pinned by reverse-applying each and re-running against a green
   baseline; two survived the first sweep and gained fixtures. It fails
   on an entry whose heading carries no block, which is precisely the
   failure mode that let the old guard skip entries in silence.
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


**Closed in 0.2.12.** The direction this entry chose — give the data a
schema instead of parsing prose — was already shipped; 0.2.12 finished
it in two places.

`deferred_findings_spec.rb` stopped hand-rolling the `key: value` grammar
and parses the fenced block as yaml with a key whitelist (`024.68`),
which is the same move one level deeper: the schema was there and the
reader was still improvising.

And **the EN/JA README divergence this entry left unguarded is guarded**,
in the shape `check_site_links.rb` already uses for the site's Japanese
pages. It does not compare prose — the two READMEs were written
independently and say the same things differently, and demanding
identical wording buys a stricter check by making the prose worse. It
compares the *shape* of the matrix: how many rows carry a verdict, and
which marks each carries, in order. That is the half a translation cannot
legitimately change, and a row saying ✅ in one language and ⚠️ in the
other is a promise made to half the users.

Two examples: the pair as it stands, and one that mutates a copy in
memory and requires the comparison to fail — because reading a guard
cannot tell you whether it would notice.

## 024.26 A workspace `def Object.foo` is reachable from every class in Ruby and from none here

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`

Ruby's real singleton chain for a class `W` is
`[#<Class:W>, #<Class:Object>, #<Class:BasicObject>, Class, Module, Object, Kernel, BasicObject]`.
0.1.15 models the tail from `Class` onward, which is what class-body
macros need. It does not model `#<Class:Object>` or `#<Class:BasicObject>`
— the singleton classes of the root classes — because an `AncestorEntry`
names a type and has no way to say "the singleton class of that type".

A workspace that writes `def Object.foo` declares something every class
can call, and the check does not know it, so `Widget.foo` is reported.
That is a **false positive**, not a missed report — for an unknown-method
check a missing ancestor is the unsafe direction, and an earlier draft of
this entry had that backwards.

The fixture has to be `class Object; def self.foo; end; end`, not
`def Object.foo` -- the latter is recorded as an *instance* method
(024.32), which the new tail then resolves, so it is not reported at all
and demonstrates nothing about this entry.

It is not a 0.1.15 regression. Measured on the `def self.` form across
three revisions: 0.1.13 reports it, 0.1.14 does not, 0.1.15 reports it
again.
0.1.14's silence was an accident of the same mis-kinded lookup that made
it report `class Object; def blank?; end` — idiomatic Rails — on code
that runs. 0.1.15 trades the accident back for the fix. Nothing in the
standard library or the gems measured for it hits this shape.

**Direction:** the entry type needs a singleton flag before this can be
expressed at all. Worth doing with 024.13 rather than alone, since both
are about what a chain says when the workspace has reopened a core class.


**Fixed in 0.2.12.** The chain a class's singleton side ends in now
carries the two links Ruby puts before `Class` — the singleton classes of
`Object` and `BasicObject`, as `origin: :singleton_of`, which keeps them
on the singleton side rather than the `:class_object` tail's instance
one. A workspace `class Object; def self.foo` is reachable from every
class, as Ruby makes it.

`Object` appears twice in a singleton chain now, once as its singleton
class and once as the class the class object is an instance of. They are
two different links and the index tells them apart by which side each
contributes, which `#dedupe_named` already keys on — the name alone was
never enough, and 0.2.11 learned that from `extend self`.

Corpus, four gems, control `unresolved-constant` identical at 1,099:
`unknown-method` 84 → 84, **0 added and 0 removed**. The rule fires only
where a workspace declares a class method on `Object` itself, which none
of these gems do.

## 024.27 `documentSymbol` lists one outline entry per name a macro declares

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#add_generated_method`,
and the five recorders that call it),
`core/lib/ovallsp/index/document_symbol_builder.rb` (`#build_children`)

`attr_accessor :a, :b, :c` declares six methods, all at the same source
range, so the outline shows six children with byte-identical `range` and
`selectionRange` on one line.

**It was more than noise, and 0.2.15's own closing note — replaced by
what follows — was wrong about which half was left.** It read: "each of
the six now selects its own name, so the remaining symptom is duplicate
`range`s in a list whose entries are correctly labelled — noise". Both
halves of that sentence are false, and each is checked below.

Two features read "the smallest declaration whose
range contains the caret" — `Server#declaration_symbol_id_at` for Find
References from a declaration site, and `#declaration_named_at` for go
to definition. With every name at one range those N candidates *tie*,
`min_by` returns the first, and asking about the second name answered
about the first.

Driven through the real server on a class whose `attr_accessor :alpha,
:beta` is called once per name, `textDocument/references` with the caret
on `beta` answered `alpha`'s call site:

    expected: [6]      # the line `beta` is called on
         got: [5]      # the line `alpha` is called on

That is a wrong answer, not a cosmetic one, and it is pinned now by
`core/spec/ovallsp/macro_declaration_ranges_spec.rb` — through the
server, not by a copy of `declaration_symbol_id_at`'s arithmetic, which
would have pinned the copy.

**And `024.227` did not reach these symbols at all**, which is the other
half. `#build_children` falls back to `decl.location` when
`name_location` is nil, and a macro-declared declaration had none, so
none of the six selected its own name.
`DocumentSymbolBuilder.build` over `ParserService#summarize`, on

```ruby
class Widget
  attr_accessor :a, :b
  enum status: { active: 0, archived: 1 }
  scope :recent, -> { where(x: 1) }
  delegate :name, :age, to: :company
  define_method(:calc) { |v| v }
  def plain = 1
end
```

against the tree that shipped 0.2.15:

    Widget         range=(0,0)-(7,3) sel=(0,6)-(0,12)
      a              range=(1,2)-(1,22) sel=(1,2)-(1,22)
      a=             range=(1,2)-(1,22) sel=(1,2)-(1,22)
      b              range=(1,2)-(1,22) sel=(1,2)-(1,22)
      b=             range=(1,2)-(1,22) sel=(1,2)-(1,22)
      active?        range=(2,2)-(2,41) sel=(2,2)-(2,41)
      archived?      range=(2,2)-(2,41) sel=(2,2)-(2,41)
      recent         range=(3,2)-(3,35) sel=(3,2)-(3,35)
      name           range=(4,2)-(4,36) sel=(4,2)-(4,36)
      age            range=(4,2)-(4,36) sel=(4,2)-(4,36)
      calc           range=(5,2)-(5,32) sel=(5,2)-(5,32)
      plain          range=(6,2)-(6,15) sel=(6,6)-(6,11)

`plain` is a `def` and shows the 0.2.15 fix working. Every macro row
above it has `sel` equal to `range`, which is what the fix replaced —
including `recent` and `calc`, which declare one name each and were
never part of the duplicate-range symptom, but lost their
`selectionRange` all the same.
This is the shape `CLAUDE.md`'s "promoting a finding is making a claim"
warns about: a note written while splitting an entry, restating in the
present tense something nobody re-drove.

**Fixed by giving each generated declaration the token it is named
after.** `#add_generated_method` gained a `name_node:` keyword with **no
default**, for the reason `parameters:` has none: three recorders once
took that default while meaning "not stated here". From it comes
`name_location` — Prism's `value_loc`/`content_loc`, the bare name
without the `:` or the quotes, so a `selectionRange` selects `title` and
not `:title`.

`node:` and `name_node:` then differ deliberately, and the rule is
**`node:` is the region this one declaration owns**:

- a macro taking a *list* of names owns, per name, its own token — the
  rest of `attr_accessor :a, :b` is the other name. `attr_*`, `enum` and
  `delegate` pass the token.
- a macro whose call declares exactly one method owns the whole call,
  because the rest of it is that method's body. `scope` passes the call
  (its lambda), `define_method` passes the call (its block). Narrowing
  these would have *lost* the body, and `Declaration#location`'s own
  contract is the whole declaration — a `def`'s body is inside its
  `location`, so a `define_method`'s block belongs inside its own.

The builder needed nothing: `decl.name_location || decl.location` was
already there from `024.227`.

The same run afterwards:

    Widget         range=(0,0)-(7,3) sel=(0,6)-(0,12)
      a              range=(1,16)-(1,18) sel=(1,17)-(1,18)
      a=             range=(1,16)-(1,18) sel=(1,17)-(1,18)
      b              range=(1,20)-(1,22) sel=(1,21)-(1,22)
      b=             range=(1,20)-(1,22) sel=(1,21)-(1,22)
      active?        range=(2,17)-(2,24) sel=(2,17)-(2,23)
      archived?      range=(2,28)-(2,37) sel=(2,28)-(2,36)
      recent         range=(3,2)-(3,35) sel=(3,9)-(3,15)
      name           range=(4,11)-(4,16) sel=(4,12)-(4,16)
      age            range=(4,18)-(4,22) sel=(4,19)-(4,22)
      calc           range=(5,2)-(5,32) sel=(5,17)-(5,21)
      plain          range=(6,2)-(6,15) sel=(6,6)-(6,11)

`a` and `a=` still share a range, and should: one token declares both.
`recent` and `calc` keep the whole call, and now select their names.

**Narrowing has a second side, and the first version of this entry did
not state it.** A name now owns only its own token, so the rest of the
macro call — the keyword, the commas, `to: :company` — lies inside no
method's range at all. Driven through the real server on a `Widget`
whose `attr_accessor :alpha, :beta` and `delegate :title, :author, to:
:company` are each called once in a `def use` that also names `Widget`,
with the caret on the `attr_accessor` keyword itself,
`textDocument/references`:

    before: [(5,4)]           # alpha's call site
    after:  [(0,6), (8,4)]    # Widget's

and `textDocument/definition` there answered the declaration before and
answers nothing now. That reads as a regression until the same two runs
are given a control: a caret on the class's own `end`, and on a blank
line in its body, answered `[(0,6), (8,4)]` on **both** sides. So the
"after" column is the answer this engine has always given for a
position in a class body that no narrower declaration covers, and the
"before" column was the anomaly — a caret on `attr_accessor` reporting
about `alpha`, a name it is not on, because the call's range covered
the keyword and `min_by` broke the tie by returning the first.

Pinned in `macro_declaration_ranges_spec.rb` against the class's own
`end` rather than against a line number, so the example asserts the
rule rather than repeating the measurement. `#declaration_named_at`
reads `name_location || location`, and `scope` — which keeps the whole
call as its `location` — is the fixture that can tell those two apart;
a caret on its `scope` keyword is inside `location` and outside
`name_location`, and only a reader preferring the second declines
there.

**One shape had to be refused: a name span can lie outside its own
node.** `docs/CLIENT_BEHAVIOUR.md` records, checked against the
installed types, that `selectionRange` must be contained by `range`.
While `range` was the whole call that came free; once it is the name
token it does not, because Prism keeps a heredoc's text separately
from the `<<~` marker that is the node:

    $ ruby -rprism -e '
    src = "attr_reader <<~NAME\n  quoted\nNAME\n"
    a = Prism.parse(src).value.statements.body.first.arguments.arguments.first
    p [a.location.start_offset, a.location.end_offset, a.location.slice]
    p [a.content_loc.start_offset, a.content_loc.end_offset]'
    [12, 19, "<<~NAME"]
    [20, 29]
    # prism 1.9.0, ruby 3.4.10

On the first version of this change that shape produced a child with
`range=(1,14)-(1,21)` and `sel=(2,0)-(3,0)` — a selection entirely
outside the range it belongs to. `#name_token_location` now takes the
region as an argument and refuses a span outside it, at the one place
the span is produced rather than at its caller, so that shape falls
back to `location` in both fields.

**Not to the answer it gave before this change**, and the sentence here
said it was until a review round drove it. `location` narrowed for this
shape as well, because `node:` for `attr_*` is the argument now rather
than the whole call: through a real server the row's `range` went from
`(1,2)-(1,21)`, the whole `attr_reader <<~NAME` call, to `(1,14)-(1,21)`,
the marker alone. What is unchanged is that the two fields are *equal*,
which is what the protocol's containment rule allows. The value moved 12
columns, and a reader of the old sentence would have concluded the shape
was untouched.

The shape is pathological on purpose, and Ruby says so — the name the
heredoc produces carries the newline, and `attr_reader` refuses it:

    $ ruby -e 'class W
                 attr_reader <<~NAME
                   quoted
                 NAME
               end'
    NameError: invalid attribute name 'quoted
    '
    # ruby 3.4.10

Nothing here is about supporting that spelling. What the example pins
is the containment invariant, and this was the first shape probed for
it.

**Left unpinned, and recorded rather than papered over.**
`#name_token_location`'s class dispatch has a nil arm for a node that
is neither literal class. Nothing reaches it: each of the five
recorders returns early unless `attribute_name`/`symbol_name`
recognised the argument, and those two admit exactly those classes. It
declines rather than raising so that a sixth recorder handing over
another literal shape loses a `selectionRange` instead of raising out
of `#summarize` and dropping the file's whole index — an argument, not
a measurement. No example can reach it without that sixth recorder, so
none was written.

**Corpus control.** `corpus_diagnostics.rb` over ActiveRecord 8.1.3.1's
`lib` — 397 files, `corpus-sha256` identical on both sides — produces
**byte-identical output**: 1,702 findings before and after, with
`unresolved-constant` at 1,609 and `unknown-method` at 93 on both. That
is the intended result rather than a null one: the engine reads *which*
declarations exist, never where they are, so the whole diagnostics
output is a category this change cannot affect.

**What says the two sides really ran different code** is the outline
pair above, driven in the same two tree states, with
`shasum lib/ovallsp/parser_service.rb` printed before each. The header's
own `dirty-tracked-files` cannot say it here — it counts the index, and
the docs and specs are dirty on both sides, so it read 15 either way.
Worth knowing before trusting that field to tell an A from a B: it
answers "does this tree differ from its revision", not "did these two
runs differ from each other".


## 024.29 Two features were written for 0.1.15 and cut from it

```yaml
status: done
kind: defect
user-visible: no
user-visible-note: >
  Nothing shipped either way. What is open is whether these are worth
  building at all, which is a question about a future release rather than
  about anything a user can see today.
target: 0.2.16
released-in: 0.2.16
```

**Area:** was `core/lib/ovallsp/parser_service.rb` (`module_function`) and
`core/lib/ovallsp/server.rb` (`setter_suffix`, the writer completion
snippet), both removed before 0.1.15 shipped.

0.1.15 exists to correct 0.1.14. These two were written during it and are
not corrections of anything — they are new scope that rode along, and
each shipped a defect of its own that a review round then had to repair.
That pattern, not a wrong fix, is what made the release unstable. An
independent analysis of the thread recommended cutting them rather than
invoking CLAUDE.md's two-rounds rollback, on the grounds that the
corrections themselves had survived two review rounds untouched — the
rounds repaired only what had been *added*, never what had been
*corrected*, which is the opposite of 024.15's shape.

**`module_function` modelling.** Measured before cutting, over the 47
standard-library files that actually call it: this release and 0.1.14
produce **byte-identical output, 1,564 findings**, `comm` empty in both
directions. It changed nothing on real code. What it did do was introduce
a report neither 0.1.13 nor 0.1.14 makes:

```ruby
module Sample
  module_function
  def helper(a, b); [a, b]; end
end
Sample.helper(1, 2, 3)   # reported only with module_function modelling
```

It also leaked out of every construct it was written in — a later
`private` did not close the section, `class << self` pushed no frame, and
neither a method body nor a block was guarded — and recorded the instance
copy public where Ruby makes it private.

The one real report it removed, `::JSON.load(source, proc, opts)`, was
never `module_function`'s to fix: that report comes from the *ancestry
tail* 0.1.15 models, and it is fixed at that end instead, by declining to
judge arity against a declaration reached through a synthesised ancestor.
`module_function` was covering a symptom whose cause is elsewhere — which
is the clearest evidence it was the wrong shape.

**Hover and completion for writer methods.** `w.name = "y"` hovering as
the reader, and the writer completing as `w.name=(value)`. Small, real,
and it shipped `setter_suffix`, whose `rstrip` crossed newlines so that a
comment ending in a period made the next line's assignment look
receiver-qualified: go-to-definition on `LIMIT = 10` under
`# The maximum row count.` found nothing.

**Direction:** whichever release takes either up must justify it on a
corpus first. `module_function` in particular needs a measurement showing
it changes an answer a user sees; the one taken here says it does not.

### Answered by events, and closed in 0.2.16

Driven at HEAD: both features this entry says were cut are in the shipped
tree, having arrived by other routes.

- `module_function` modelling is back under `024.106`/`024.114`.
  `WorkspaceIndex` carries `@module_function_names`, `FileSummary`
  carries `module_function_names`, and the cache schema was bumped for
  it, so it survives a restart.
- The writer half arrived through the parser recording `attr_*`
  generated methods with a `value` parameter, which the general
  completion-snippet path then renders. There is no `setter_suffix` left
  in `core/lib` or `core/spec`, and the rstrip-across-newlines defect
  this entry records did not come back with it.

So the open question the entry ends on — whether these were worth
building at all — has been answered by both of them being built anyway,
for other reasons, and staying. Nothing here is a limitation, so nothing
is published.


## 024.30 0.1.15's hunk sweep: three hunks that cannot be pinned, and why

```yaml
status: fixed
kind: defect
user-visible: no
target: 0.2.12
released-in: 0.2.12
user-visible-note: >
  A record of which lines no test holds, and the reasoning for leaving
  each. Nothing here changes what the engine answers.
```

**Area:** `core/lib` (0.1.15's whole change set — this entry is the
sweep's record rather than a defect in one place)

Reverse-applying each of 0.1.15's 24 `core/lib` hunks against a green
baseline: **21 caught, 3 survived**, the tree verified byte-identical
after every one. The survivors, and what was done about each:

- **The deleted `new` special case** (`diagnostics/engine.rb`). Restoring
  it changes no answer, because the `Class` tail now resolves `new` for
  every class. It only ever suppressed reports, and no receiver exists
  for which `new` *should* be reported, so there is nothing to assert.
  Deleted rather than tested, which is what CLAUDE.md prescribes for a
  decision that cannot be pinned. The corpus runs are the evidence: zero
  reports introduced over the standard library, ActiveSupport and this
  repository's own `core/lib`. A later round measured a wider Rails set
  and found three reports from a different cause (024.31), so "three
  Rails gems" as this entry first put it was not a claim those runs
  supported.
- **`rbs_resolves?` delegating to `AncestorEntry#declaration_kind`**
  (`diagnostics/engine.rb`). Not a behavioural decision — it is the
  removal of a second, hand-written copy of a rule. The rule itself *is*
  pinned: reverting `declaration_kind` at its source fails three
  examples. The kind only differs for a `:class_object` or `:extend`
  ancestor, and for those the reference resolver answers before this path
  is reached, so no fixture can distinguish the call site. Left as is,
  because deleting the delegation would restore the duplication that made
  both copies wrong.
- **`@anonymous_class_depth = 0` in the visitor's constructor**
  (`parser_service.rb`). Defensive initialisation, not a decision.

That sweep was of a change set that no longer ships -- it ran before
024.31 withdrew the `attr_*` block rule -- and two unpinned decisions
inside `add_generated_method` were invisible to it, because reverse-
applying a hunk that adds a whole method only asks whether the method
exists. Both are pinned now.

**The shipped diff was swept at `3dc0011`: 25 hunks, 20 caught, 5
survived**, baseline green before and after, every file verified
byte-identical between hunks. The five:

- Two are **comment-only** (`MethodCandidate`'s origin list, and
  `WorkspaceIndex`'s note about which collections keep insertion order).
  A comment hunk changes the file, so the script scores it; it holds no
  behaviour to pin.
- Two are the ones above and unchanged in character: the **deleted `new`
  special case**, which is redundant-code removal, and **`rbs_resolves?`
  delegating to `declaration_kind`**, which removes a duplicated rule
  that is pinned at its source.
- One is **`@inline_attribute_visibility = nil` in the constructor**.
  Defensive: the ivar is read as `@inline_attribute_visibility ||
  @visibility_stack.last`, so an unset ivar and an explicit `nil` answer
  the same. Kept for the same reason as any other constructor default.

The diff has grown since: rounds six and seven each added a hunk to
`argument_count_findings` and `extract_parameters`, neither covered by
that run. Those were swept at the decision level instead -- each entry of
`declares_keywords`, the forwarding-parameter branch, and the
double-splat branch -- and each is pinned by an example that fails when
it is reverted. A hunk count is only true of the commit it was measured
at; this one is `3dc0011`'s.

One decision was unpinned, and is not any more. `block_self_is_module`'s
`node.receiver.nil?` term survived an 18-mutation sweep a later round
ran, because the example written for it put the explicit receiver inside
a `def` -- where `!@in_method_body` already answers, so the receiver term
never ran. The fixture writes it directly in `class << self` now, and
fails when the term is removed. Two sweeps missed it: the hunk-level one
because the term lives inside a method the diff adds wholesale, and the
decision-level one because its own fixture could not distinguish the
branches. Both blind spots are named in CLAUDE.md; meeting them together
is what let this line through twice.

**A fourth sweep guard, learned here.** A sweep that is *killed* mid-hunk
leaves the tree mutated. One run hit a timeout, left `engine.rb` missing
nine lines, and the next run's baseline check refused to score -- which
is guard 2 working, but only after the damage. The three guards detect a
broken tree; none of them stops a run from leaving one. The script traps
`EXIT INT TERM` and restores now. Budget for it too: 25 hunks at a
4.5-minute suite is nearly two hours, which is worth knowing before
starting rather than after.


**Closed in 0.2.12, and one of its two claims was checked rather than
believed.** The fourth sweep guard this entry describes is in the tree:
`scripts/hunk_sweep.rb`'s `at_exit` restores `core/` and `vscode/` when
an interrupted run leaves the working tree mutated.

The other claim — "the fixture writes it directly in `class << self` now,
and fails when the term is removed" — is prose about a test, which is
exactly what `042`'s D7 says not to trust. It is now an entry in
`core/spec/meta/pinned_mutations.yml`: replacing
`node.receiver.nil? ? nil : false` with `nil` must fail
`class_body_macro_spec.rb`'s "reads an instance_eval block on an explicit
receiver as an instance", and CI applies it.

Worth noting how the entry was written into the manifest: the first
attempt named an example in `parser_cref_spec.rb` that reads well and is
about a *different* decision, and the checker reported it uncaught. A
prose claim about which example pins what is a claim about this tree,
and this one was wrong in a way no reader would have questioned.

## 024.31 A declaration written inside a block has no owner this parser can name

```yaml
status: fixed
released-in: 0.2.13
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`record_attribute_methods`,
`visit_def_node`)

A block can change the receiver its body runs against — `Class.new do`,
`Struct.new do`, `included do`, `class_eval do`, `concerning do`,
`instance_eval do` all answer differently, and `builder.call do` answers
something this file cannot see at all. The visitor attributes everything
it finds to the lexically enclosing owner, which is right for some of
those and wrong for others.

**This entry exists because three attempts to be cleverer than that each
made things worse, and each was found by the review round after it.** All
three were confined to `attr_*` while `def` kept the lexical answer, and
a block holds both:

1. **Skip every block.** Turned every ActiveSupport::Concern's
   `included do attr_accessor :tracked_at end` into
   `Order has no method named tracked_at` — a false report on the most
   ordinary Rails code there is.
2. **Skip only anonymous-class builders** (`Class.new`, `Struct.new`,
   `Data.define`, `Module.new`). ActiveRecord builds its
   habtm association class as
   `Class.new(Base) { class << self; attr_accessor :left_model; end; def self.compute_type; left_model; end }`.
   Dropping the `attr_accessor` while `def self.compute_type` kept the
   enclosing owner produced three reports on `activerecord-8.1.3`.
3. **Skip method bodies.** The same shape, written inside a `def`, has
   the same asymmetry for the same reason.

The rule now is the one `def` has always had: **attribute to the
lexically enclosing owner, everywhere, with no exceptions.** Consistency
is what avoids the false reports; the residual cost is a declaration
recorded against an owner that may not be its real one, which offers a
member in completion that is not there and silences a report rather than
inventing one. That is the direction this engine chooses everywhere else,
and it is what shipped in 0.1.14 and every release before it.

Two consequences a user can see, both pre-existing and both now
deliberate:

- `Struct.new(:x) do attr_reader :label end` inside `class Outer` offers
  `label` on an `Outer`, and go-to-definition on it lands in the block.
- `def setup; attr_accessor :never_real; end` records `never_real`, so a
  call to it is not reported. Ruby cannot define it by any path here --
  `attr_accessor` is `Module`'s and `self` inside an instance method is
  not a module, so `setup` raises `NoMethodError` when called. This is
  the one example where the parallel with `def` does *not* hold: a nested
  `def` in the same position really does define the method once `setup`
  runs. The parallel the decision rests on is the block case above, not
  this one.

**Direction:** the fix is not a longer allowlist — that is what these
three attempts were, and the fourth would be too. It needs the visitor to
carry a *receiver* for a block rather than a boolean, so that
`Class.new do` opens an anonymous owner, `included do` opens the
includer, and an unrecognised builder opens an unknown owner whose
declarations are recorded against nothing. That is a change to what an
owner *is*, which is why it belongs to its own task rather than to a
patch release correcting something else.

Until then, do not add a name to any block allowlist without a corpus run
in both directions across ActiveRecord and ActiveSupport, and without
asking what `def` in the same position does.


**Fixed in 0.2.13, in two halves and by the same mechanism.** The entry
asks for a block to carry a *receiver* rather than a boolean, and that is
what `Cref#in_eval_block(owner)` is.

`024.33` closed the eval-on-an-expression half: `other.instance_eval {
attr_accessor :o_x }` was recording accessors on the *enclosing* class.

This closes the class-creating half. `Class.new`, `Struct.new`,
`Module.new` and `Data.define` with a block define on the new class,
which has no name until the assignment completes and may never get one:

    $ ruby -e '
    class Outer
      Seed = Struct.new(:x) do
        attr_reader :label
      end
    end
    p [Outer.new.respond_to?(:label), Outer::Seed.new(1).respond_to?(:label)]
    '
    # => [false, true]
    # ruby 3.4.10

The accessor belongs to the Struct and was being recorded on `Outer` —
the direction that *invents* a member, which this engine refuses
everywhere else.

The control is in the same file and is what "drop every block" would
break: `included do attr_accessor :tracked_at end` really does define on
the concern, and an ordinary class-body `attr_accessor` is untouched.

**Corpus, 16 gems, control identical at 4,600: 119 removed and 2 added.**
The two are worth naming rather than netting off. Both are
`ActionDispatch::Routing::RouteSet` calling `Kernel#URI`, one of the four
`Kernel` names `024.91` records as an RBS signature-set gap — a
pre-existing false positive that had been *masked* by this class's
surface being spuriously opened by a `Class.new` block inside it.
Removing a wrong silencer shows what it was silencing, and the finding
underneath belongs to `024.91`.

## 024.32 `def Foo.bar` is recorded as an instance method, so both answers are inverted

```yaml
status: fixed
released-in: 0.2.13
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`visit_def_node`)

`visit_def_node` treats a `def` as singleton only when its receiver is a
`Prism::SelfNode`. `def Foo.bar` names a constant instead, so it is
recorded as `Foo#bar` — an instance method. Both consequences are wrong,
in opposite directions:

```ruby
class Foo; end
def Foo.bar; end

Foo.bar        # reported: "Foo has no method named `bar`" -- Ruby runs it
Foo.new.bar    # accepted    -- Ruby raises NoMethodError
```

Pre-existing and identical on 0.1.13, 0.1.14 and 0.1.15. **106**
occurrences of `def Const.method` in Ruby 3.4.7's standard library,
counted with Prism. Matching every stdlib `unknown-method` report's
receiver and method name against those declarations, **56** of them are
this -- on 0.1.15 and 0.1.14 alike, 59 on 0.1.13. An earlier draft of
this entry said six, which was a hand count of one file rather than a
measurement, and it understated the case for fixing this by roughly nine
times. Among them `PP.mcall`, `Ripper.lex`, `IRB::Frame.top`,
`IO.console_size`, `Net::HTTP::Proxy`, and `Bundler::Deprecate.skip`
(`bundler/shared_helpers.rb:391`), `CGI::Session.callback`
(`cgi/session.rb:345`) and three in `fiddle/struct.rb`.

**The owner is wrong too, and this entry said it was not.** An earlier
Direction here read: "the owner is already computed correctly a few
lines below (`constant_full_name(owner_receiver)`); it is only the
`kind`". Round 22 of the 0.2.0 loop disproved it.
`constant_full_name` ends in `qualify`, which nests the name under the
current owner unconditionally — so `def Fetcher.start` written *inside*
`class Fetcher` is recorded on `::Fetcher::Fetcher`, a class that does
not exist. Ruby resolves the constant `Fetcher` there to the class
itself. Anyone following the old Direction would have produced correctly
kinded singleton methods on a namespace nothing resolves to.

**And the consequence is not only `unknown-method`.** The arity check
reads the same declarations, so a call to a `def Const.method` is judged
against whatever *instance* method shares its name. On the 0.2.0
measurement corpus, **9 of the 17 remaining `argument-count` reports**
are this shape: `net/http.rb`'s `def HTTP.get_response` four times, its
vendored copy under `rubygems/vendor/net-http` four times, and
`minitest.rb:472`'s `def Runnable.run_suite`. Neither this entry nor
`KNOWN_LIMITATIONS.md` said so before round 22 measured it.

**Direction:** both the `kind` and the `owner` have to change, and
neither is a one-line edit.

- `kind`: any explicit constant receiver means a singleton method, not
  only `self`. Check what else keys on that predicate first —
  `visit_def_node` also uses it for the declaration's visibility, which
  is `nil` for singleton methods.
- `owner`: the parser cannot know at parse time whether `Foo::Bar`
  exists, so it cannot resolve the constant properly. What it *can* do
  is stop nesting a name that names an enclosing frame: if the written
  name matches the last segment of an enclosing owner, that frame is the
  owner. That covers `def Foo.bar` inside `class Foo`, which is the
  whole measured population.

Still its own task rather than a ride on another release, for the reason
this entry gave before and round 22 agreed with: it changes declaration
kinds, which is what 0.1.14 and 0.1.15 were both spent on, and it wants
a corpus run in both directions.


**Fixed in 0.2.13.** Both halves. A written receiver makes the definition
a singleton one whatever it names — the test was
`node.receiver.is_a?(Prism::SelfNode)`, so `def Foo.bar` fell through to
*instance*, inverting both answers. And the owner is resolved through the
nesting before falling back to qualifying: `def Fetcher.start` inside
`class Fetcher` named `::Fetcher::Fetcher`, a class that does not exist,
and every later lookup failed against it.

Only nesting frames this parser has seen declared are matched, which is
the honest limit of doing it in the parser; a constant declared elsewhere
still falls back to the previous behaviour.

**And it surfaced a second decision that had to move with it.** The
16-gem corpus came back +3, all in
`activerecord/associations/builder/has_and_belongs_to_many.rb`, where
`Class.new(Base) { class << self; attr_accessor :left_model; end }` is
written inside a `def`. `024.34`'s new `Cref#surface_for` reads
"in a method body" as the instance side, which is right for
`def setup; attr_accessor :x; end` and wrong once a `class << self`
intervenes — that opens a definition context of its own. `#in_singleton_class`
resets `in_method_body` now, and the corpus returns to 0 added.

The entry the residue belongs to is `024.31`: those accessors are really
the *anonymous* class's, and attributing them to the lexically enclosing
owner at all is that entry's subject.

## 024.33 `K.instance_eval { attr_accessor :x }` is reported; `K.class_eval` is not

```yaml
status: fixed
released-in: 0.2.13
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`block_self_is_module`)

Both define `x` and `x=` on `K`. The first is reported as
`... has no method named attr_accessor`, the second is not, because
`instance_eval` takes the "explicit receiver means an instance" path and
`class_eval` takes the inherit path.

Not a regression -- 0.1.14 reported it too -- and the receiver rule it
comes from is right for the case it was written for: `o.instance_eval do
helper end` on an object must not resolve against the class's singleton
side.

A three-way split was written and dropped. The visitor tracks *whether*
self is a module, never *which* module, so the "constant receiver means
the class" branch would still resolve against the lexically enclosing
owner rather than the receiver -- and no fixture could tell the two
apart, which is its own reason not to ship it.

**Direction:** the same one 024.31 needs. A block wants a receiver, not a
boolean; with that, `K.instance_eval` opens `K` and this answers itself.
Worth doing with 024.31 rather than separately.


**Fixed in 0.2.13.** The entry says the two spellings were split and the
split was dropped, because "this visitor cannot say *which* module self
is". A **written constant says which**, and that is the whole fix.

Ruby treats the two the same, because `attr_accessor` is a call on self
and self is the receiver either way:

    $ ruby -e '
    class K; end
    K.instance_eval { attr_accessor :k_x }
    p [K.respond_to?(:k_x), K.new.respond_to?(:k_x)]
    class L; end
    L.class_eval { attr_accessor :l_x }
    p [L.respond_to?(:l_x), L.new.respond_to?(:l_x)]
    '
    # => [false, true]
    # => [false, true]
    # ruby 3.4.10

Both define an *instance* accessor on the named class, and both are
recorded that way now. `Cref#in_eval_block(owner)` carries the receiver,
which is `042`'s D5 in its smallest useful form: a block was given a
boolean and needed a receiver.

**And the control found `024.31` in the same place.** An eval block on an
*expression* — `other.instance_eval { attr_accessor :o_x }` — was
recording accessors on the *enclosing* class, inventing an owner for a
receiver nothing can name. `in_eval_block(nil)` makes `#surface_for`
answer nil there, so nothing is recorded. That is one shape of `024.31`
closed; the anonymous-class one (`Class.new { ... }`) is not, and stays.

Corpus, 16 gems, control identical at 4,600: **0 added, 113 removed**
against main — two more than before this fix.

## 024.34 `attr_*` inside a `def` inside `class << self` is kinded singleton

```yaml
status: fixed
kind: defect
target: 0.2.13
released-in: 0.2.13
user-visible: yes
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`record_attribute_methods`)

`singleton = @singleton_context_stack.last` asks "would an unqualified
`def` here declare a singleton method". Inside a `def` nested in
`class << self` that is still true, but the `attr_accessor` runs when the
method is *called*, with the class object as self — so Ruby defines
**instance** methods:

```ruby
class S
  class << self
    def build
      attr_accessor :attr_x     # Ruby defines S#attr_x, not S.attr_x
    end
  end

  def use = attr_x              # reported: "S has no method named `attr_x`"
end
```

Confirmed against the interpreter: after `S.build`,
`S.new.respond_to?(:attr_x)` is true and `S.respond_to?(:attr_x)` is
false. Reported on 0.1.13, 0.1.14 and 0.1.15 alike — a false positive,
which is the unsafe direction.

This is the same reasoning 0.1.15 applied to `block_self_is_module`, and
the sibling decision two hundred lines away did not get it. It is
recorded rather than fixed because 0.1.15 exists to correct 0.1.14, and
this predates both — 024.29 is the entry about what happens when a
release takes on scope beyond its own purpose.

Real code has the shape:
`activerecord/associations/builder/has_and_belongs_to_many.rb:16-20`,
`csv/parser.rb`, `cgi/core.rb:522`, `devise/models.rb:32`.

**Direction:** the same predicate `block_self_is_module` now uses —
`!@in_method_body && @singleton_context_stack.last`. Cheap, but it is a
behaviour change on its own, so it wants its own corpus run in both
directions rather than a ride on a correction release.


**Fixed in 0.2.13, and it is the entry the 0.2.11 stocktake called the
most informative of C1's five.** `Cref#defines_surface?` already answered
the question this needs and was read at *one* site in the parser, while
`#declares_singleton?` was read at *seven* — and
`#record_attribute_methods` read the second. The stocktake's verdict on
C1 was that collecting six flags into one value collected the *storage*
and not the *question*, and this is that sentence made concrete.

`Cref#surface_for` is the question a recorder actually has: `[owner,
side]` for a definition written here, or nil where there is nothing to
attribute it to. The two answers differ in exactly one place, which is
this one — inside a `def` written in `class << self` the cref is still
the singleton class, but self at run time is the class object, so
`attr_accessor` there is `Module#attr_accessor` and defines an *instance*
accessor.

The control is in the same file: written *directly* in `class << self`,
`attr_accessor` still records a singleton accessor, which is what Ruby
does and what an implementation that simply stopped answering singleton
would break.

## 024.35 A class that includes a module the workspace cannot resolve still reads as closed

```yaml
status: done
kind: defect
user-visible: yes
released-in: 0.2.18
```

### Closed in 0.2.18: does not reproduce, confirmed with a control that distinguishes

0.2.15's assessment reached this conclusion and was refused because its
fixture could not tell *"the defect is gone"* from *"nothing of this kind
is reported at all"*. **That refusal was right, and finding out why took
building the control it asked for.**

Driven again, a receiverless macro in a class body — the entry's own
`validate :ensure_ok` — is reported in **no** arrangement: not with an
unread include, not with a readable one, not with no include at all. So
any fixture built from that shape proves nothing in either direction,
which is exactly what 0.2.15 hit.

An explicit receiver *is* reported, and with it the four cases separate:

```
  includes an unread module         Configish.validate(:ensure_ok)          []
  includes nothing                  Plain.validate(:ensure_ok)              reported
  includes a readable module        Known.validate(:ensure_ok)              reported
  unread module, a real typo        Configish.definitely_not_a_member       []
```

The defect is gone and the check is awake, which the middle two prove.

**And the cost this entry predicted is real**, which the fourth line
shows: "it will silence genuine class-level reports on every class that
includes anything unread". It does. That is the trade the rule makes
rather than a second defect, and it is now an assertion in
`unread_include_spec.rb` rather than a sentence, so it cannot be
undone by accident and called an improvement.

**The published limitation was stale in the other direction** and said
the macro *is* reported. Corrected in both languages, and it now states
the cost as well — which is the half a user actually meets, because it
is the half that is silent.

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`closed_nominal?`)

`closed_nominal?` asks `chain_reaches_root?` of the *instance* chain --
deliberately, and correctly -- but asks `ancestor_known?` only of the
chain it is about to search. For a class-level call that is the singleton
chain, which `include` never touches. So a class that includes an
`ActiveSupport::Concern` living in a gem the workspace has not read is
judged closed, though its real class-level method set is whatever that
Concern's `class_methods do` block installs.

```ruby
class Configish
  include SomeGem::Model
  validate :ensure_ok      # reported; `include ActiveModel::Model` makes it run
end
```

Reported on 0.1.14 and 0.1.15, silent on 0.1.13 -- 0.1.14 introduced it
by giving the singleton chain a tail that reaches the root, which is what
`chain_reaches_root?` was the only guard against. Four instances in
`solid_queue-1.5.0/lib/solid_queue/configuration.rb` alone.

**Direction:** ask `ancestor_known?` of both chains when the lookup is a
singleton one. The instance chain is where `include` records itself, and
an unknown module there means the class-level set is unbounded too. Worth
measuring in both directions first: it will silence genuine class-level
reports on every class that includes anything unread, which is most of a
Rails app before the Agent is ready.



### 0.2.15 assessment: claimed not to reproduce — **not yet confirmed**

An assessment run drove this against HEAD and reported that it does not
reproduce. The evidence is real and is quoted below. **It has not been
independently confirmed, and the entry therefore stays open.**

The second attempt at confirmation failed on its own control: a fixture
that cannot tell *"the defect is gone"* from *"nothing of this kind is
reported at all"* proves neither. That is the same defect the assessment
would be closing, one level up.

*This matters here specifically. `024.130` was published to users as a
limitation the product does not have, because a bullet was promoted to a
numbered entry without its reproduction being re-run. Closing an entry
on an unconfirmed claim is the same act in the other direction.*

**What 0.2.15 must do:** re-run this with a control that distinguishes
the two outcomes, and close it or keep it on that basis.

<details><summary>The assessment's evidence, verbatim</summary>

```
DOES NOT REPRODUCE — already fixed and pinned; the register entry is stale.

Scratch spec (<scratch>), stack built with build_analysis_stack, run from core at HEAD 5d20fe7 (v0.2.13):

  B => []            # class Configish2; include SomeGem::Model; end  ->  Configish2.some_class_method
  D => []            # SolidQueue::Configuration includes ActiveModel::Model -> .validates_presence_of
  A => []            # the entry's own `class Configish; include SomeGem::Model; validate :ensure_ok; end`
  C => ["tpyo"]      # control: a class including nothing still reports a class-level typo
  4 examples, 0 failures

The entry's named area no longer exists in that form. `Engine#closed_nominal?` now delegates to `MethodResolver#availability(...).absent?`, and the Direction the entry asked for ("ask ancestor_known? of both chains when the lookup is a singleton one") is implemented in core/lib/ovallsp/semantic/method_resolver.rb#unenumerable_reason, lines 183 and 200:

  return :ancestor_not_identified if singleton && instance_entries.any? { |e| !e.identified? }
  return :ancestor_not_declared_anywhere if singleton && !instance_entries.all? { |e| accounted_for?(e, signatures) }

Direct probe of the reason (scratchpad/e35b_spec.rb):
  Configish2 singleton: absent=false reason=:ancestor_not_declared_anywhere
  Plain35    singleton: absent=true  reason=nil
  Configish2 instance ancestors: [["::Configish2",true,:class],["SomeGem::Model",true,nil],["Object",true,:class],...]

PINNED. Reverse-applying both lines via a monkeypatch (scratchpad/unpatch35.rb — no repo edit) reproduces the entry verbatim and fails an existing spec:
  B => ["some_class_method"]
  D => ["validates_presence_of"]
  spec/ovallsp/semantic/method_resolver_availability_spec.rb  15 examples, 1 failure
(spec/ovallsp/diag
```

</details>

### Reported fixed in 0.2.16, and the refutation was overturned

A triage pass concluded this entry's Direction was implemented — and it
is: `MethodResolver#unenumerable_reason` carries both halves,
`:ancestor_not_identified` and `:ancestor_not_declared_anywhere`, dated
to 0.2.6 and citing the `include Singleton` and `include Sidekiq::Worker`
reports by name.

An adversarial verifier then made it reproduce anyway, which is why the
pass had one. The shape that still fires is a module the workspace *can*
partly see:

    module Other
      module SomeGem
        module Model
          def only_in_other_module; end
        end
        class Base; end
      end
    end

    class ViaInclude
      include SomeGem::Model
    end

The include resolves to something — the nested `Other::SomeGem::Model` —
by the last-segment path, so neither refusal fires, and the class reads
as enumerable while the module the author meant is a gem's. The two
triage agents drove the *unresolvable* spelling, which the Direction does
cover, and not this one.

Stays open. Note that this is the same failure of method as `024.19`'s
entry records: a refutation checked against the fixture it was refuting
rather than against the entry's own claim.

**Re-triaged in 0.2.17** (`024.276`). A class reads as closed when the module it includes is a gem's, so the product asserts a method is missing from code that runs — a repair, not a capability. Its own body records that the two triage agents drove the *unresolvable* spelling, which the Direction already covers, and not this one; that is the same failure of method it notes `024.19` recording. Not re-driven since.

## 024.36 Instructing a reviewer narrowed what it could find, and a control run proved it

```yaml
status: fixed
kind: defect
released-in: 0.1.15
```

**Area:** how this project asks for an independent review. The finding is
about the process, not the engine; `CLAUDE.md`'s "How to ask for an
independent review" section is what came out of it.

### What happened

0.1.15 ran eight review rounds. The count of defects fell steadily, and
that decline was read as convergence:

| round | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| code defects | 6 | 3 | 3 | 2 | 1 | 1 | 2 | 0 |

It was not only convergence. Over those eight rounds the instructions
given to the reviewer had been quietly narrowed, every one of the changes
reducing what could be reported:

| | rounds 1–4 | 5 | 6–7 | 8 |
|---|---|---|---|---|
| "re-finding a recorded defect is not a finding" | — | — | 3 entries excluded | **9 entries excluded** |
| "a clean report is a useful result" | — | yes | emphasised | emphasised twice |
| list of already-measured corpora to avoid | — | partial | 14 sets | **16 sets** |
| "concentrate on X" | — | — | — | **yes** |

Each is defensible on its own. Together they mean the same underlying
defect density produces a smaller number every round, and the number was
being used as the stopping signal.

### The control

The last round was run twice on the same tree: once with the narrowed
instructions (round 8), and once with **round one's instructions
verbatim** — no exclusion list, no corpus list, no "concentrate", no
"clean is fine", plus one addition: *report anything you consider a
defect, whether or not it looks already known or deliberate; if a
decision recorded as deliberate is the wrong decision, say so.*

Round 8 found five things, none of which changed what the engine answers.

The neutral run found a **user-visible regression 0.1.15 itself
introduced**: `delegate` and `scope` recorded their generated methods as
taking no parameters, so once this release taught the argument-count
check to count a brace-less trailing hash, every call to a delegated
method was reported — including in ActiveRecord's own
`database_statements.rb`.

The mechanism of the miss is specific and worth naming: round 8 had been
told to avoid the sixteen already-measured corpora, and the Rails gems
were on that list. **The instruction that sounded like efficiency is what
kept anyone from looking where the regression was.** A corpus is only
"already measured" against the revision it was measured at; the release
had moved seven times since.

### What this changes

`CLAUDE.md` now carries the rules this produced. In short: do not tell a
reviewer what not to count, where to concentrate, or that finding nothing
is fine; keep a list of measured corpora as a record of coverage rather
than as an exclusion; and when a review loop's findings are used to decide
that a change set is ready, run one round with neutral instructions before
believing the count.

### What it does not change

The decline was not *only* instruction drift. Rounds 2–5 each found
defects in code the previous round had written, and less new code was
written each round, so some of the fall is real. The point is that the
number could not distinguish the two, and nothing had been done to make
it able to.


## 024.40 Every `argument-count` report on the measurement corpus is false

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`argument_count_findings`,
`sole_source_declaration`)

G5 has been a ✅ row since 0.1.6. A reviewer read all 17 reports it
produced at `6f5e86a`; after round 22's fixes there were 15, and all 15
were read again. At 0.2.1 the count is **14**, re-measured over Ruby
3.4.7's standard library, five Rails 8.1.3 gems and minitest 6.0.6, and
**10** of them are the `def Const.method` shape. The table below is the
0.1.6 reading and is kept for the shapes rather than the counts:

| shape | count | cause |
|---|---|---|
| `def HTTP.get_response` calling `start(...)`, judged against the instance `def start` | 8 | 024.32 |
| `def CStructEntity.malloc(types, func = nil, size = size(types))` | 1 | 024.32 |
| `def Runnable.run_suite` | 1 | 024.32 |
| `create(name, nil, arg)` where `create` is `alias_method :create, :new` in `class << self` | 2 | the alias is resolved, the singleton `new` is not |
| `run Rails.application` inside `Rack::Builder.new do` | 1 | block self is the enclosing class (024.31) |
| `readline(@prompt, false)`, `Configuration.instance(:must_exist).load do` | 2 | receiver resolved by substitution |

**What this is not.** It is not "the check is wrong". Every one of these
is a case where the *declaration* the check found is not the one the call
reaches, and each has its own recorded cause. Nor is it a 0.2.0
regression: `main` produces 22 on the same corpus.

**What it is.** A corpus of gems is close to the worst case for this
check — dependencies absent, so names resolve by substitution; heavy use
of `def Const.method`, which the parser mis-files. A user's own workspace
is the opposite: their classes are declared, their names are theirs. The
honest statement is that the check's precision is unmeasured on the code
it is actually for, and measured at zero on the code we have.

**What 0.2.0 changes** is the blast radius, exactly as 024.24 argued for
the route check: diagnostics now publish for files nobody opened, so
these reach the Problems panel rather than waiting to be found.

**Direction:** the three causes are already recorded — 024.32 (`def
Const.method`'s kind and owner), 024.31 (a block's self), and the
index's substitution, which round 22 refused for the *receiver* and for
a *superclass* but not for an aliased singleton. Fixing 024.32 alone
removes 10 of the 15. Then re-measure, on a real application rather than
on gems.

### Re-measured at 0.2.13: the tabled shapes were gone, and the count was 109

The direction above was followed and it worked: 024.32, 024.31 and
024.33 all shipped in 0.2.13, and **not one** of the shapes tabled above
is still reported. The count is nevertheless **109**, over Ruby 3.4.10's
standard library, five Rails 8.1.3.1 gems and minitest 5.25.4 — 2,095
files, at `57e98da` — and all 109 are a *new* cause the same release
introduced:

| shape | count | cause |
|---|---|---|
| `warn("a", "b")` anywhere in the corpus | 94 | `rubygems/core_ext/kernel_warn.rb`'s `module_function define_method(:warn) {\|*messages, **kw\| … }` |
| `p :list_start => margin` anywhere in the corpus | 15 | `objspace/trace.rb`'s `define_method(:p) do \|*objs\|` |

**Two declarations produced all 109.** 024.116 taught the parser to
record the *name* a `define_method` writes — which is what made hover,
go-to-definition and completion answer for one — and recorded
`parameters: []` alongside it. An empty parameter list is not "unknown";
it is the assertion that the method takes no arguments, and the arity
check reads it as one. Both files above define a method that takes
`*args`, so every `warn` and every `p` in the corpus was told it takes
none.

This is the third time this exact mistake has been made in this file:
`delegate` and `scope` recorded nothing in 0.1.15 and made the check
judge every call to what they declared, which is what `UNSTATED_PARAMETERS`
(then `FORWARDED_PARAMETERS`) was introduced for.

**Fixed.** A method defined from a block takes what the block takes —
Ruby arity-checks it like a `def`, not like a proc — so
`define_method(:pair) { |a, b| }` declares two required parameters and
`{ |*objs| }` declares a rest parameter the check bails out on. Where
there is no block *literal* (`define_method(:x, &blk)`,
`define_method(:x, instance_method(:y))`) or the block uses numbered
parameters, nothing states a list here and `UNSTATED_PARAMETERS` says so.
And `add_generated_method`'s `parameters:` keyword lost its default, so
the next macro recorder cannot assert an empty list by omission — the
countermeasure the third repetition calls for, rather than a fourth hand
fix.

Measured both sides over the identical corpus (`corpus-sha256`
`acefc6b0798a9c9886a9704dbc86c58bac578bb436d716dbdfc091bb10fe64c4`,
2,095 files), one run at a time, each printing its own tree and revision:

| | `57e98da` | `57e98da` + the fix |
|---|---|---|
| `unresolved-constant` (control) | 10,406 | 10,406 — identical line for line |
| `unknown-method` (control) | 583 | 583 — identical line for line |
| `argument-count` | **109** | **0** |
| removed / added | — | **109 / 0** |

`scripts/hunk_sweep.rb` over the change set: **6 hunks, 6 pinned, 0
unpinned**, and the spec file it adds pins something the rest of the
suite does not. The countermeasure needed one round to get there — the
first sweep reported the required keyword unpinned, because nothing
expressed it as behaviour; `:keyreq` against `:key` on the recorder's own
`Method#parameters` is what pins it now.

### The measurement, run in 0.2.15, and what it could not be

**Precision has nothing to measure.** The check reports **zero** times on
2,095 files of stdlib and gems and **zero** times on the 90 files of this
project's own `core/lib` — where the classes *are* the author's own,
declared, and resolvable, which is the condition the paragraph above
asked for. That is not a precision of zero; it is a precision that is
undefined for want of a single positive.

And on reflection that is the expected answer, not a surprising one.
Committed Ruby that runs does not call its own methods with the wrong
number of arguments — the mistake is made in an editor and fixed seconds
later, and no corpus of committed code can hold one. **A corpus can
never measure this check's precision.** The 0.2.1 entry asked for a
measurement that does not exist, which is why it sat open for six
releases; saying so is the answer to it.

**So recall was measured instead**, by `scripts/measure_arity_recall.rb`:
every `def self.name(a, b)` in a tree whose parameter list is entirely
required positionals — the shape where a wrong count is unambiguously an
error — called once with one argument too many and once with one too
few, in a probe written to a `Dir.mktmpdir` and never into the tree being
measured.

Over `core/lib`, 26 methods and 47 deliberately wrong calls:

| receiver | caught |
|---|---|
| a **class**'s singleton method | **31 / 31** |
| a **module**'s singleton method | **0 / 16** |
| total | 31 / 47 |

**The split is exact, and every miss has one cause**: `024.106`, which
declines on a module because a module's ancestor chain is itself, so this
engine cannot tell "I have seen everything it declares" from "I have seen
one file that reopens it". `Ovallsp::Index`, `Ovallsp::Plugins` and
`Ovallsp::Semantic` are modules; every other owner in the sample is a
class. There is no second cause and no partial credit anywhere in the
table.

So G5 does catch a real mistake, on every receiver it is willing to
answer about, and its one blind spot is a limitation already recorded and
already published in `KNOWN_LIMITATIONS`.

**What was not measured, stated plainly.** Not a Rails application. The
`rails_real` fixture has one method with a parameter and no `def self.`
at all, so it cannot support this measurement; running it there would
have produced a number with an N of one. What that measurement would add
is how often macro-generated methods make the check bail out — a recall
figure, not a precision one, and `UNSTATED_PARAMETERS` already declines
by construction there. It is not expected to change whether G5 earns its
row, and it is not being carried as an open item on that basis.

**The entry's title is retained though it is no longer true.** Every
report it named is gone — 109 to 0 in the table above — and the entry is
closed on that plus the measurement. Retitling it would lose the thread
from the 0.1.6 reading to here.


## 024.41 Typing a `.` reports a method on the *next* line

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.18
```

**Fixed in 0.2.18, and not by the debounce this entry asked for.**

Driven first, because the entry's own table had already moved twice
without anyone noticing. At `6dfd63c` all six rows reproduce exactly as
re-measured, and the control — the same text with the trailing `.`
removed — is silent.

**The Direction was written when `didChange` published synchronously,
and that stopped being true in 0.2.10.** Analysis already waits for the
input queue to settle (`#drain_settled_analyses`, 037's C9), so a
debounce cannot reach this shape: **a pause is what settles the queue,
and pausing to read the completion popup is the scenario.** Deferring
harder would defer this report to exactly the moment it is published.

What distinguishes a half-typed call from a deliberate one is not in the
text — the entry is right about that, and right that a rule about
receivers and lines would silence trailing-dot chain style. It is in the
client's *edit*, which `didChange` carries, this server takes
incrementally, and `TextDocument` was throwing away.

`Diagnostics::MidEditCall` suppresses an `unknown-method` report whose
message is the first token after a `.` that both ends its line and sits
exactly where the last edit finished. Three conditions, each pinned by a
control that fails without it, and the filter lives at the Server rather
than in the engine: the caret is a fact about the *buffer*, and the same
text opened from disk must still say what Ruby says.

**It is a decline and it expires.** The next edit moves the caret and
the report returns, which is right — at that point it is code the user
left rather than code being typed.

**Deliberately not widened.** The obvious generalisation also suppresses
`a.tit` while someone is halfway through `title`, and that shape does
reach the user — measured, typing it and pausing publishes one report
naming `tit`. The two differ in the one way that decides it: `a.` can
never be a finished expression and `a.titel` can, so suppressing a
half-typed *name* would silence a genuine typo for as long as the caret
rests on it, which is the whole time somebody types one and looks.

Eight examples, four of them controls, and two mutation entries. The
first draft of the spec passed for the wrong reason twice — a uri
compared as a Symbol against a String, then an unqualified constant
raising inside a `rescue` that swallowed the publish — and both times
only the controls said so.

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`analyze`'s parse
gate), `core/lib/ovallsp/server.rb` (`did_change`, which publishes with
no debounce)

Half of this is fixed and half is not, and the half that is not is the
commonest editing action there is: `.` is the completion trigger.

```ruby
a = Article.new
a.
b = "str"
```

→ ``Article has no method named `b=` ``.

**Re-run against 0.2.13**, with a control that removes the trailing `.`
and reports nothing for any of the six:

| next line | reported |
|---|---|
| `b = "str"` | ``no method named `b=` `` |
| `value` | ``no method named `value` `` |
| `return 1` | ``no method named `return` `` |
| `other_thing(1)` | ``no method named `other_thing` `` |
| `if true … end` | `syntax-error`, not a method report |
| `puts 1` | nothing |

**Two of the six moved since this entry was written**, in opposite
directions, and neither move was noticed because nobody re-ran it.
`if true` now trips the clean-parse gate instead — `a.if` is not
parseable — so that case is `024.41`-shaped no longer. And
`other_thing(1)` was recorded as *not* reported and now is: the false
report reaches an ordinary method call on the next line, which is a
wider surface than the entry claimed. `puts 1` stays silent because
`Kernel#puts` really is a method `Article` has.

The `end` half -- `a.` at the end of a method, where recovery invents
`a.end` -- was fixed in 0.2.1 by gating semantic checks on a clean parse.
This shape defeats that gate because **there is no syntax error at all**:
`a.\nb = "str"` is valid Ruby that means `a.b = "str"`, and it is
reported correctly. Nothing in the text says the user is mid-edit.

**Direction:** not another check. The engine cannot tell this apart from
the same code written deliberately, so the answer is to stop publishing
*while the user is still typing* -- a debounce on `didChange`, and
ideally the edit position, which the notification already carries and the
Server discards. Recorded rather than patched, because a heuristic that
suppresses "a call whose message is on a different line from its
receiver" would also suppress the leading-dot chain style, which is
ordinary Ruby.

**The debounce was built, and rolled back.** 0.2.2 shipped it, rounds
32--35 each found a defect in it — discarded edits, a publish that could
outlive its document, and a measured 140x cost on the correction it
forced — and `CLAUDE.md`'s same-place rule rolled the thread back.
`024.57` is that record, and its Area is "whatever replaces the
deferral", which is this entry's Direction. They are one piece of work
and now carry one target.

*Until 0.2.14 this paragraph said the reclassification to 0.4.0 "lands
with that branch's release". 0.2.4 shipped fifteen releases ago, the
ROADMAP's 0.4.0 section never gained the item, and the entry kept its
`kind: defect` throughout — so the sentence described a future that had
already not happened. Deciding it here instead: it stays a defect,
because what a user sees is a false report on code they are in the
middle of typing, and it targets 0.3.0 beside `024.57` rather than
adding scope of its own.*

Round 23 found it, round 24 found it again and widened it, and it existed
only in `026-0.2.1-review-loop.md` until now -- which is why it is an
entry: a finding parked in a round's handover is invisible to
`deferred_findings_spec.rb`, and `DOCUMENTATION_MAP`'s "A known
limitation" row was therefore unenforced for it.

**Re-triaged in 0.2.17** (`024.276`). The engine reports a method on the line *below* the cursor while the user is mid-keystroke, which is a false report on code that is simply unfinished — the worst-ranked shape in section 0.4, and a repair rather than a capability. It travels with `024.57` because both want the same debounce, and both move to the patch line together. Found by round 23, widened by round 24, and it lived only in a round's handover until it became an entry.

## 024.43 Signature help answers nothing for a receiverless stdlib call

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.16 for a call inside a *class* body, and for a workspace
  class inheriting a stdlib one. What is still open has entries of its
  own: `024.240` (inside a module body, where the workspace's own
  instance chain never reaches Object/Kernel), `024.229` (the top level
  of a file) and `024.230` (the index-side blocker under it). The
  class-object part was `024.228`, fixed in 0.2.15.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`#signatures_of`,
and the RBS bands under it -- `#rbs_own_signatures` and
`#ancestor_signatures` today, one `#rbs_signatures` called twice with
`direct: true`/`direct: false` when this entry was written)

`puts(` answers `{signatures: []}` while bare-prefix completion offers
`puts` from its own Kernel source.

Round 22 found S1's receiverless half, round 23 fixed it, and this is
S2's: the same row shape, one release later, for the stdlib source
instead of the workspace one.

### Re-driven in 0.2.15: the mechanism recorded here is false

**`lookup_owners` does return Kernel.** Measured:

    lookup_owners(Nominal("Report"))
    # => [["::Report", false], ["Object", false], ["Kernel", false], ["BasicObject", false]]

So "Kernel is not in it" is wrong, and so is the **Area**:
`#signature_owners` (query_service.rb:337) is reached only from
`#add_signature_members` (:304), which is the *completion* path — and
completion answers `puts` correctly, which is what the entry itself
observes. Signature help goes `#signatures_of` → `#rbs_signatures`,
which uses `each_nominal(receiver_type)` and **never walks ancestors at
all**. Instrumented, `#signature_owners` fires zero times across five
signature-help requests and once on the completion request, which is the
control proving the instrumentation was live.

**The Direction is therefore aimed at a method signature help does not
call.** Following it would have produced a `kernel_methods`-shaped
change in the completion path, shipped green, and left every case below
exactly as it was. This entry is the reason `CLAUDE.md` says a stale
entry that reads plausibly is harder to catch than one that is obviously
wrong.

**And the title is one instance of three.** `MyErr.new.full_message(`
fails identically with an *explicit* receiver and no Kernel involved — a
workspace class inheriting a stdlib one — and so do
`MyErr.new.message(` and `MyStr < String; MyStr.new.sub(`. Receiverless
is not the shape; not reaching RBS-declared ancestors is.

### What this entry now is, and what left it

- **`024.228`, fixed in 0.2.15** — a class-object receiver reaching RBS
  un-normalised, so every `String.new(` answered nothing in three
  features at once.
- **`024.229`** — the top-level case, where both obvious fixes are
  wrong: one regresses completion ordering, the other turns silence into
  a wrong answer on a file in this repository.
- **`024.230`** — a top-level `def` indexed with `owner: nil`, which is
  what blocks `024.229`.
- **What stays here**: `#rbs_signatures` maps the receiver straight to
  an RBS type name and never asks the ancestor chain, so a method
  declared only on an RBS ancestor of a nominal RBS does not know is
  unreachable. `#signature_owners` already made this move for
  completion; routing the RBS lookup through
  `@method_resolver.lookup_owners` resolves the in-class receiverless
  case and the workspace-subclass case together, because they are one
  code path.

**Retargeted to 0.2.16.** `#signatures_of` walks Union members and calls
`#rbs_signatures` twice with `direct: true`/`false`, and the ordering
between direct RBS, workspace source and inherited RBS has to be
preserved or an override starts answering with an ancestor's signature.
No spec asserts the current empty result for any of these, so the
behaviour is unpinned in both directions — that wants establishing
before the change, not after.

### Fixed in 0.2.16

`#signatures_of`'s two RBS bands become **three bands and a constructor
rule**, and the band that used to ask about the receiver's own name and
stop now walks the chain `MethodResolver#lookup_owners` gives:

| band | asks | why there |
|---|---|---|
| 1 | RBS, declared **directly** on the receiver's own type | a `sig/` for the class the workspace also declares, or a reopened core class, outranks the workspace's own line |
| 2 | the workspace's declaration | an override is nearer than what it overrides |
| 3 | RBS on the receiver's own type however the method got there, then on an **ancestor** the workspace's chain reaches | the reach this entry is about; its head is the same call the old `direct: false` band made |

Band 1 is the old `direct: true` half, unmoved. The old `direct: false`
half is *inside* band 3 now, as its head, and this is the correction
round 2 of review made: the first version of this change kept it as a
fourth band, justified in two comments that contradicted each other,
and the reviewer showed the code agreed with neither. For every name
but `new`, asking the receiver's own name with no `direct:` filter and
walking a chain whose head is that same name with that same filter are
the identical call. `new` was the only thing the extra band decided,
and it decided it by *where the guard sat* rather than by what it
asked, so it is written as a rule now — `#constructor_signatures` asks
the receiver's own type first and refuses the chain below it, which is
what `#definitions_of` already did in the same order.

Only the reach past the head is new, and it sits below the source band
— which is the ordering the retargeting note above asked to have
established first. `#signature_definition_locations` reads the same
chain, and `#add_signature_members` — the reader that already had it
right — now reads the same builder, so the three cannot drift apart
again.

**Three things the measurement found that reasoning did not.**

- **`#lookup_owners` does not open the chain with the receiver.** The
  comment on `#signature_owners` says it does. Driven over the stdlib,
  `Nominal("EOFError")` opens at a nested `EOFError` a gem declares,
  `Nominal("Encoding")` at one RDoc declares, `Nominal("Marshal")` at
  one OpenSSL declares — `HierarchyIndex` resolves a bare name against
  whatever the workspace declares with that last segment. Handing the
  bare chain to the RBS readers **lost two signatures and eight
  definition jumps they had been answering.** The receiver's own name
  is now prepended, so each walk is a superset of the lookup it
  replaces and cannot answer less. `inherited_rbs_signatures_spec.rb`
  reproduces the shadowing in a fixture.
- **Prepending it in the reader completion uses would undo `024.47`.**
  `query_service_spec.rb`'s "answers an inferred String with the
  workspace class alone" went green — that entry's live half, pinned
  in *both* directions until it is settled. A single call asking "what
  could this reach" and a completion list asking "what should I offer"
  are different questions; `#rbs_lookup_chains` and `#rbs_owner_chains`
  are where they differ, and the second is what completion reads.
- **`new` is the one name an ancestor cannot answer for.** `Class#new`
  forwards to the receiver's own `initialize`, so walking the singleton
  chain reported `new() -> Object` — RBS's rendering of
  `Object#initialize`, which takes nothing — on **31 of 253** newly
  answered call sites, and sent go to definition into
  `basic_object.rbs`. A constructor reported as taking no arguments
  when it takes two is the wrong answer this walk had to not introduce,
  and `Diagnostics::Engine` already declines there, so signature help
  asserting was the asymmetry section 0 forbids. `X.new(` is answered
  from `X#initialize` as the workspace declares it, and otherwise not
  at all — RBS's `Object#initialize` is `() -> void`, and rendering
  that as `new()` would restate the same false claim one layer down.

**Measured, both sides at this revision, on the identical corpus** (Ruby
3.4.10's `lib/ruby/3.4.0`, 976 files, `corpus-sha256` printed and equal
on both runs; each run printed the `query_service.rb` it *loaded* rather
than the one it was handed, after the first attempt found Bundler
putting the worktree's own `lib` on the path first):

| driven through the engine's own inference, 5,898 receiverless call sites | before | after |
|---|---|---|
| answering, unchanged | 3,721 | 3,721 |
| silent, unchanged | 1,928 | 1,928 |
| silent → answering | — | 249 |
| answering → silent | — | **0** |
| answer changed | — | **0** |

The comparison asserts the inferred receiver is identical on both sides
before comparing anything, so inference is not a free variable. A second
pass over 12,609 `(receiver, method)` pairs taken from the same corpus
agrees: 1,266 gained, 0 lost, 0 changed, and 11,343 unchanged.

`scripts/corpus_diagnostics.rb` over 241 files is **byte-identical on
both sides** — 1,293 `unresolved-constant`, 7 `unknown-method`, same
findings. That is the expected result rather than evidence about the
fix: diagnostics never reach `QueryService`, exactly as `024.228`
recorded.

The `.new(` answers are the real constructors —
`new(original_path, &block)`, `new(env, keys)`,
`new(base = nil, name = nil)` — checked against the declaring files.

**Twenty-one behavioural decisions were mutated one at a time, and all
twenty-one fail a spec** — each mutation applied to the real file, the
suite run against it, the file restored from a snapshot afterwards and
the restore verified by sha256. `spec/ovallsp/semantic` alone (225
examples) catches every one; the sweep needed nothing wider.

This is a fresh sweep against the shape as repaired; the eleven the
author counted were against the previous one. **Four decisions did not
fail a spec on their first pass**, and each was dealt with rather than
argued away:

- band 1's `direct:` restriction — now pinned by a workspace reopening
  `String` to override `tap`, which RBS carries on `::String`
  *inherited*;
- `#constructor_candidate`'s instance-side override, which no example
  could reach because no spec passed a `context:` to either reader at
  all;
- the constructor rule's placement below the source band, in *both*
  readers, which no fixture could see because none declared a
  `def self.new` beside an `initialize` — the fixture now does, and
  the two orderings give different answers;
- the same rule sitting above the band's `@signatures` guard, which no
  example reached because none built the service without an RBS
  environment.

Two lines turned out to be unreachable rather than unpinned and were
deleted: a `.drop(1)`, and a `.uniq` on the lookup chain. The `.uniq`
was put back as mutation 22 to check the claim rather than assert it —
the suite stays **green**, because every reader either takes the chain's
head or stops at the first owner that answers, so a repeated owner is
only ever reached after the first copy failed to answer.

**Still open, and not touched here:** `024.240` (inside a module body),
`024.229` (the top level, where `#scope_at` gives no `self_type` at
all) and `024.230` (a top-level `def` indexed with `owner: nil`). A
changelog line for this must say "inside a class body", not "for
Kernel calls" and not "for a receiverless call".

### Found by review round 2, and not fixed here

Round 2 read the change set (`diff`) and reported eight findings, plus
four decisions no example distinguished. Repaired above: all four
unpinned decisions, the band shape, `types.rb`'s comment naming a method
this change deletes, and the limitation paragraph that was deleted while
half of what it described is still true. The rest are recorded rather
than built, because a review round reviews a fixed thing:

- **A module body is still silent, and it is not the asymmetry the
  limitation described.** `024.240`, split out and driven before it was
  written down.
- **`#member_available_on?` is the fourth copy of this walk and still
  asks the receiver's own name.** It reads
  `@signatures.member_names(qualify(nominal.name), …)` with no chain,
  so for a **Union** receiver a Kernel or Object name that
  `#add_signature_members` legitimately offers through the chain comes
  back absent, `#normalize_union_conditionals` marks it
  `conditional: true`, and `#members_of`'s sort puts it below
  everything unconditional. Nothing the user reads is false — the
  item is offered, with its own label and detail — so this changes an
  order, not an answer. Left alone deliberately: changing it moves
  completion ranking, which is what `024.229` records as a regression
  this project will not accept blind, and it wants its own
  measurement. The countermeasure this entry installed therefore
  covers three readers of four, and that is worth knowing before
  trusting it.
- **`Types::INTERNAL_GENERIC_NAMES` is not consulted by the shared
  chain builder.** `#each_nominal` reads a `Generic` as a class of the
  same name, so a `Relation[Article]` receiver becomes
  `Nominal("Relation")` and `#lookup_owners` resolves that bare name
  against whatever the workspace declares with that last segment —
  which `types.rb` says in as many words is the thing to exclude.
  Measured in a fixture declaring `class Relation < String`, both
  sides at this revision: `signatures_of(Relation[Company], "sub")`
  was `[]` before this change and is `String#sub`'s two overloads
  after, and go to definition gains a jump into `string.rbs`.
  Completion was already doing this (`members_of` is identical on both
  sides), so the defect is in `#each_nominal` and this change extends
  its reach to two more readers rather than introducing it. Not fixed
  here because every containment that would work changes completion
  too, or re-splits the readers this entry just joined.
- **The cost reasoning recorded for the walk was wrong**, though the
  cost is not a problem. `Environment#method_signatures` is
  `@rbi_methods[id] || (@method_cache[id] ||= build_signature_method(id))`
  and a miss stores `nil`, so the `||` short-circuit fails on the next
  read and the build is re-entered every request rather than once per
  process. Each unknown owner also appends one warning diagnostic,
  deduplicated by a linear scan. Measured: 1,000 misses cost 6–9 ms in
  total, because RBS's own definition cache absorbs the rebuild. What
  band 3 changes is the *number* of unknown-owner lookups per request,
  not the price of one.
- **One reported finding did not reproduce.** Round 2 reported that
  `#definitions_of`'s constructor branch returns `[]` before
  `#model_definition_locations`, so a model with a column named `new`
  would lose its jump. It cannot: `#model_definition_locations` reads
  `#each_nominal`, which yields `Nominal("ClassOf")` for a class-object
  receiver, and `#constructor_call?` is true only for one of those. So
  that path answered nothing before this change either. Driven in a
  fixture registering a `Company` model with a column literally named
  `new`: `definitions_of(ClassOf[Company], "new")` is `[]` on both
  sides, and `definitions_of(Company, "new")` is unchanged. Recorded
  because a finding that does not reproduce is worth as much as one
  that does, and only if it is written down.
- **Round 2 also withdrew one of the author's own stated risks.**
  The report said hover would show a signature line for a local
  variable whose name collides with an Object/Kernel method.
  `Server#hover_lines` reaches `#signatures_of` for an unqualified word
  only through `#enclosing_self_type`, which needs a
  `reference_candidate` with `kind == :method_call` and a nil receiver
  at that position; a local read is summarised as `local_variable`.
  Publishing it would have been `024.130` again — a limitation the
  product does not have.


## 024.46 Typing `self` cost 55 false diagnostics and was rolled back

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: yes
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#eval_type`)

0.2.1's round-30 countermeasure spec surfaced that `self.target(1)`
resolved to nothing -- `LocalInferencer` had no `SelfNode` case while
`MethodAnalyzer` did -- so one was added: `self` is the enclosing class,
which the descent already tracks.

Round 31 measured it. Over Ruby 3.4.7's standard library, three runs one
at a time with `unresolved-constant` identical at 7,561 as the control:

| side | `unknown-method` | `argument-type` |
|---|---|---|
| before | 1,034 | 0 |
| with the `SelfNode` case | **1,086** | **3** |
| with that one line reverted | 1,034 | 0 -- byte-identical to before |

**55 new false reports, none removed.** Three families:

- `self.class.foo` -- `self` becomes a Nominal, `.class` resolves through
  RBS to `Class`, and every call on it is reported unknown.
  `unless self.class.correct?(v)` is everyday Ruby.
- `def Const.method` and `class << self` bodies type `self` as an
  *instance* rather than the class object, because `#locate_def` only
  pushes `ClassOf` when the receiver is literally `self`.
  `Class.new(self)` inside `def HTTP.Proxy` was reported as a wrong
  argument type.
- `self.foo` where `foo` is C-defined or declared by a singleton
  `attr_accessor`.

Reverted. Answering nothing for `self.foo` is the trade this project
takes; answering wrongly on `self.class` is not.

**What this cost, and the rule it belongs to.** The case was added
*during a review round*, to satisfy a spec written as a countermeasure
for something else. The loop widened the change set instead of closing
it, which is what `CLAUDE.md`'s same-place rule exists to catch -- and
what caught it here was a measurement, not a reviewer's reading. Giving
`self` a type is a real improvement and belongs in a release that can
measure it properly, with `ClassOf` handled for singleton bodies and
`.class` resolving to the class object rather than to `Class`.

**That release is 0.2.16**, and both conditions in the sentence above are
what it did. `024.85` carries the work and the measurement; this entry
stays as the record of the attempt that was reverted, and of the fact
that the sentence naming what was missing turned out to name all of it.


## 024.48 The measurement tool ran an engine the server never runs

```yaml
status: fixed
kind: defect
released-in: 0.2.1
user-visible: no
user-visible-note: >
  A tooling defect. Its consequence reached users only through the
  regressions it failed to catch, which have their own entries
  (024.46, 024.47).
```

**Area:** `scripts/corpus_diagnostics.rb`

(The constructions below are the mid-0.2.1-loop arrangement this entry
was written against. The resolution-side shadow rule they describe was
rolled back before 0.2.1 shipped, and 0.2.3 removed the then-inert
`signatures:` parameter from `HierarchyIndex` everywhere -- so on
today's tree the "defective" construction and the correct one read the
same, the rule lives in the diagnostics engine, and the script matches
the server again by *not* passing what no longer exists. 024.47 records
that rollback; the lesson here is unchanged.)

It built `HierarchyIndex.new(workspace_index:)` while `Server#initialize`
built `HierarchyIndex.new(workspace_index:, signatures:)`. The shadow
rule of the day lived in `#canonical_name` and read `@signatures`, so it
did nothing in any corpus run -- and every figure this release quoted
came from those runs. A measurement of a configuration no user gets is
not a smaller measurement; it is a measurement of something else.

Fixed by building it the way the server did. The lesson is the one
`CLAUDE.md` already carries, one level up: *confirm each side ran the
code you think it ran* has to include "and in the configuration a user
would run it in".


## 024.49 A release record kept asserting durations it could not witness ending

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: no
user-visible-note: >
  Release-record prose (028's guard narrative and the workflow/spec
  comments that copied it); nothing an editor user sees. Entered
  because the same place failed three consecutive review rounds, which
  is the roll-back rule's threshold, and the rule says the entry is
  the deliverable.
```

**Area:** `docs/design/tasks/028-0.2.3-review-loop.md` ("A guard that
could not see its input"), and the ci.yml/pages.yml/guard-spec comments
that carried copies of it

Three consecutive rounds of 0.2.3's review loop found the same
narrative wrong, each time about its relationship to time:

1. **Round 1**: "the check now runs on every push" — false of the
   trigger (`push: branches: [main]` plus pull requests). Hand-fixed,
   in four places at once.
2. **Round 2**: "the check was red on `main` for five days" — a
   duration attached to the wrong fact. The redness began with 0.2.2's
   push (2026-08-16); five days is the publish-before-push gap
   (Marketplace 2026-08-11, repository 2026-08-16), which no in-repo
   check can see. The round's countermeasure — deduplicate the dated
   narrative into 028 and leave only ageless mechanism sentences in
   shipped files — was real and held. But its own restatement
   introduced "lasted under 21 hours".
3. **Round 3**: "lasted under 21 hours" asserts a *completed* duration
   for a condition that had not ended — `main` stays red until the
   release lands on it, and a fixed record cannot date that. (It was
   also arithmetically stale by commit time: the fix existed on the
   branch twenty hours in, but a fix on an unmerged branch bounds
   nothing about `main`.)

**Root cause:** the narrative kept asserting facts whose truth depends
on time and on systems outside the tree — trigger shorthand, deploy
state, the Marketplace, wall clocks. Such claims can silently stop
being true after the commit that states them. Each round fixed the
number; none changed the claim's *shape*, so the next round inherited
a fresh instance of the same class.

**Direction actually needed, applied in 0.2.3:** a fixed record states
witnessed, timestamped events — never durations or completions of
conditions it cannot watch end. An interval may be stated only when
both endpoints are witnessed (publish 2026-08-11 → push 2026-08-16).
Dated narrative does not go into shipped files at all; mechanisms,
which do not age, do — with a pointer to the record that holds the
dates.


## 024.50 The Marketplace description promises the behaviour 0.2.1 removed

```yaml
status: fixed
released-in: 0.2.3
kind: defect
user-visible: yes
```

**Area:** `vscode/README.md` and `vscode/README.ja.md` -- the paragraphs
about unsupported platform/Ruby combinations

They say OvalLSP "does not silently degrade or guess -- it refuses to
load its bundled native dependencies and shows a clear diagnostic
instead" and "does not silently degrade or half-start". As of 0.2.1 a
mismatched Ruby carrying `prism`/`rbs` starts and runs an unverified
combination, which is exactly degrading. `vscode/README.md` is the
Marketplace description, so this is a published claim the build does not
honour.

The same file's environment table still reads "Ruby 3.3.x, 3.5.x | Not
verified" with no 4.0 row, while `docs/SUPPORT_MATRIX.md` carries 4.0 as
best effort.

**Direction:** fix the prose, and add `vscode/README.md` +
`vscode/README.ja.md` to `docs/DOCUMENTATION_MAP.md`'s Ruby/platform
trigger row -- which is why it was missed: the row names
`docs/SUPPORT_MATRIX`, `docs/KNOWN_LIMITATIONS` and the two
getting-started pages, and not these two.


## 024.51 The first launch after an upgrade blocks while it sweeps the old cache

```yaml
status: fixed
released-in: 0.2.2
kind: defect
user-visible: yes
```

**Area:** `core/lib/ovallsp/cache/store.rb` (`.prune_generations`,
`.prune_workspaces`), called from `Server#build_cache_store`, which runs
synchronously on the `initialize` dispatch

Measured: 0.9 s to remove 1,000 legacy generation directories of 20 files
each. The comment in that file cites a real machine at 28,643 directories
and 2.8 GB, which extrapolates to roughly half a minute of a server that
answers nothing -- once, on the first start after upgrading to 0.2.1,
because that is the release that put the version in the cache key. Every
request VS Code sends after `initialize` queues behind it.

**Direction:** do the sweep on a background thread, or after the first
cold-index batch. The current generation directory already exists before
pruning runs, so nothing depends on it finishing first.

**Secondary, same file:** `prune_workspaces` removes a scope directory
whenever `File.directory?` of the recorded workspace path is false, so a
project on an unmounted volume or a temporarily unavailable network share
loses its warm cache. The method's comment calls each removal "a fact
rather than a guess", and this one is a guess.


## 024.52 A publish could outlive the document it was about — folded into `024.56`

```yaml
status: fixed
released-in: reverted
kind: defect
user-visible: no
user-visible-note: >
  Folded into 024.56, which is the same race on the path that shipped.
  This entry's own path -- the debounce waiter -- was rolled back before
  release (024.57), so nothing a user runs has ever had this half.
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (`024.56`)

Kept as a tombstone so the number resolves. `024.56` carries the defect,
the fix, and the two lessons this entry contributed about writing the
example.

## 024.53 The absent-workspace grace measured the wrong clock

```yaml
status: fixed
released-in: 0.2.2
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in the same release that introduced it. Recorded for the mistake
  rather than the outcome: a plausible mtime that answers a different
  question than the one being asked.
```

**Area:** `core/lib/ovallsp/cache/store.rb` (`.prune_workspaces`)

024.51's fix held an absent workspace's cache for thirty days rather than
removing it the moment its directory could not be found. The age it read
was the *scope directory's* mtime -- and a directory's mtime advances
when an entry is created or removed inside it, which for a scope
directory happens only when a generation is minted: a Ruby upgrade, a
`bundle install`, a release. That is "how long since the cache key
changed". The question is "how long since anyone opened this project".

Measured by round 32, driving the real `Cache::Store`:

```
workspace unreachable for: 0 seconds
scope directory mtime age: 90.0 days
cache survived the sweep:  false
```

So the retention was inverted against its own purpose. A project on an
external drive, opened daily on a stable toolchain, still lost its cache
the first time the volume was away -- the exact scenario the grace was
written for -- while a project deleted the day after a `bundle install`
kept a verbatim copy of its source for thirty days.

**Fixed** by reading the `.workspace` marker's mtime instead.
`.mark_workspace` rewrites it on every launch that opens the workspace,
so it is already the answer; nothing new had to be recorded.

**The spec could not have caught it.** It created the scope directory
inside the example, so its mtime was *now* -- the one configuration in
which the wrong clock gives the right answer. The replacement ages the
two in opposite directions: a scope directory 90 days old, a marker
written today. That is the general form worth keeping — a fixture where
both candidate readings are present and disagree, rather than one where
they happen to coincide.

`.monotonic_age` was renamed `.seconds_since_write` in the same change.
It was `Time.now - File.mtime(path)`, which is not monotonic, and a name
asserting a property the code does not have is how the next reader gets
it wrong.


## 024.54 An edit that changed nothing discarded the edit before it

```yaml
status: fixed
released-in: reverted
kind: defect
user-visible: yes
user-visible-note: >
  Both the defect and the correction it produced were rolled back. The
  correction was kept at first, on the reasoning that it fixed the
  synchronous path too; round 36 measured what it cost there -- 0.015 s
  to 2.098 s on a byte-identical `didChange` -- and it went with the
  rest. See the note at the end of this entry.
```

**Area:** `core/lib/ovallsp/server.rb` (`#reindex`, `#schedule_diagnostics`)

`#reindex` reached `#schedule_diagnostics` only from inside
`if apply_file_summary(summary)`, and `WorkspaceIndex#replace_file`
returns false for content it already holds. So a `didChange` whose text is
byte-identical to the indexed text did not refresh
`@pending_publish[uri]`, which went on carrying the *previous* edit's
version. The waiter fired, found `document.version` no longer matched,
and published nothing. Nothing rescheduled.

Round 33 measured it over a real pipe, against 0.2.1 as a control:

| | publishes `(version, count)` |
|---|---|
| 0.2.2, no no-op edit | `[[1, 0], [2, 2]]` |
| 0.2.2, with a no-op edit 50 ms later | `[[1, 0]]` |
| 0.2.1, same script | `[[1, 0], [2, 2]]` |

**What a user saw:** a file with a syntax error and an empty Problems
panel, indefinitely — there is no `didSave` handler, so saving does not
republish and it recovers only on the next edit that changes bytes.
Reachable whenever an edit whose result is byte-identical lands within
300 ms of a real one: a formatter or code action applying a full-range
replace, another extension writing the buffer, a client re-sending.

**Fixed** by moving the publish out of that `if`. The index is right to do
nothing for content it already has; the publish is not, because the client
asked for this version. Republishing an unchanged document costs one
analysis.

**The countermeasure matters more than the fix.** This is the second
round in a row to find a defect in the debounce, and both were the same
three pieces of state disagreeing: `@pending_publish`'s captured version,
`@document_store`'s current one, and whether a waiter is alive to
reconcile them. 024.52 was the first. `CLAUDE.md`'s same-place rule asks
for something mechanical at that point, and
`spec/ovallsp/server_publish_invariant_spec.rb` is it: one property --
*an open document's last published diagnostics are for its current
version, and a closed document's are empty* -- over a table of
notification sequences. Three of its rows failed when it was written. A
regression test pins the sequence someone thought of; this pins the
property, and whoever finds the next one adds a row.

**Round 36: the correction was rolled back too.** Publishing outside
`if apply_file_summary(...)` was kept when the debounce went, on the
reasoning that it is a fix to the synchronous path. Measured, it is not:

| | control (text changed) | byte-identical edit |
|---|---|---|
| 0.2.1, `net/http.rb` 2,574 lines | 2.049 s | **0.015 s** |
| with the correction | 2.031 s | **2.098 s** |

The control agrees to 1% and the measured category moves 140x, under
`@index_mutation_mutex` -- the lock hover, completion and the next
`didChange` all need. On the synchronous path there was nothing to fix:
with no publish, the panel keeps the previous version's diagnostics,
which are correct for byte-identical text. The only difference is the
`version` field, and VS Code does not discard diagnostics on version. So
it bought a field nobody reads and cost up to 5.3 s of a frozen server
per format-on-save of an already-formatted large file.

`server_publish_invariant_spec` was restated about the *text* rather than
the version at the same time, which is the claim the server actually
needs to make -- and still fails on round 33's defect, because that left
the panel showing a clean file whose text had a syntax error.


## 024.55 A version mismatch is reported and then ignored

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Target slipped.** Written for 0.2.4 and still open five releases later; retargeted to 0.2.10 rather than left naming a release that has shipped.

**Half of this shipped in 0.2.10: the pre-start path now refuses.**
`decidePreStart` (`vscode/src/startupGate.ts`) is a named function with
its own tests, and `extension.ts` returns instead of calling
`client.start()` when the probe fails. It is a named function rather than
an `if` in the start callback for the reason this entry gives for the
delay: a refusal that is wrong locks the user out of the extension
entirely, and nothing in `extension.ts` can be unit-tested. The
notification says the Core Server *did not start*, which is both the true
thing and the actionable one.

**The post-start half is what remains open** -- `compareVersionInfo`
still reports and keeps running, which is what the four documents now
describe, split into two paragraphs so each half says what actually
happens.

**Area:** `vscode/src/extension.ts` (`runVersionHandshake`, and the
pre-start branch on `checkBundledCoreCompatibility`)

Four documents said OvalLSP "stops before sending any feature request" on
a version, protocol, build or platform mismatch and shows a diagnostic
"instead of a degraded session". It does not stop. Both deciders log to
the Output channel, raise an error notification, and fall through:
`.stop(` appears once in `extension.ts` and it is inside a comment.

So a Core whose **payload hash does not match** -- a corrupted or
tampered build -- serves hover, completion and go to definition while the
user is told they were protected from exactly that. Same for a protocol
mismatch, where the two sides disagree about the wire.

**0.2.3 corrected the documents only.** `site/getting-started.html` and
`site/ja/`, `vscode/README.md` and `.ja.md` now say what happens: it is
reported, it keeps running, and the answers should be treated as
unreliable until the mismatch is resolved. That is honest and it is not a
fix.

**Why not fixed here.** Stopping is a behaviour change with a real
failure mode of its own -- a false positive locks the user out of the
extension entirely, and this project has shipped a version check that was
wrong about a working combination twice (the 0.2.4-bound branch's
register records the toast half and its round 34). It wants its own
change, with the two paths separated:

1. **Pre-start** (`checkBundledCoreCompatibility` returning
   `compatible: false`) genuinely can refuse before any request, and by
   that point it has already established the Ruby can load neither the
   bundled payload nor its own `prism`/`rbs` -- the Core will fail on
   `require` anyway. Refusing there costs nothing and is what ADR-0005
   describes.
2. **Post-start** (`compareVersionInfo`) cannot honestly claim "before any
   feature request" -- the client has started. It would have to stop the
   client, and the reasons differ in severity: a payload hash mismatch is
   an integrity failure, a core-version mismatch after a Marketplace update
   is usually a stale process that a restart fixes.


**Closed in 0.2.12, and the post-start half is closed by a decision
rather than by code.**

The defect this entry names is that four documents said OvalLSP "stops
before sending any feature request" and it did not. Both halves of that
are now settled: 0.2.10 made the *pre-start* verdict fatal, and 0.2.11
corrected every document to describe the two checks separately, since
they have different failure modes.

**What was left was a question, not a bug: should a post-start version
mismatch stop the session too?** The answer is no, and the reason is
reachability. The Core ships *inside the VSIX* and
`ServerConfig#defaultServerPath` uses it unless `ovallsp.serverPath` is
set. After 0.2.10's pre-start gate, the remaining way to reach a
post-start mismatch is an explicit override — a user who deliberately
pointed the extension at a Core of their own. Refusing to serve a session
somebody deliberately configured is worse than telling them what does not
match and letting them judge, and it is not the shape §0 is about: the
answers are not wrong, they are answers from a build the extension did
not expect.

So it reports and continues, which is what the documents now say. The
split between the two deciders remains real and is `024.65`'s question,
which is about which decider owns the *notification* — not about which
owns the verdict.

## 024.56 A publish can land after the panel has been cleared, and after a newer one

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.7
released-in: 0.2.7
```

**Area:** `core/lib/ovallsp/server.rb` (`#republish_open_diagnostics`,
`#handle_did_close`, `#publish_findings`)

`#republish_open_diagnostics` snapshots `@document_store.open_documents`
and then computes and publishes for each, on a background thread, from
six call sites -- without re-reading the store. `#handle_did_close`
clears the panel on the dispatch thread. Nothing orders the two.

Reproduced identically by the 0.2.4-bound branch's rounds 35 and 36:
publishes for the closed file came out `[2, 0, 2]` -- findings, the
clear, the findings again. **Every build has this**, 0.2.1 included; it
is not a regression of any release. That branch's debounce work gave its
own waiter path the same race, fixed it there, and the fix did not reach
here -- which is how the shape came to be understood at all.

`#republish_open_diagnostics` publishes on a background thread when
routes or models land or the Agent becomes ready. If the dispatch thread
computed findings for version V before routes arrived, and the republish
for the same V lands during its 2--5 s analysis, the dispatch publish
writes last and puts the pre-routes findings back.
`docs/EXTENSION_CAPABILITIES.md`'s G12 row promises "the route diagnostic
clears once routes arrive, without touching the file"; in that
interleaving it clears and comes back.

**What a user sees:** close a tab a second or two after routes or models
land, or after the Runtime Agent becomes ready, and the Problems panel
keeps that file's errors for the rest of the session. Nothing republishes
an unsaved buffer or a deleted file.

### Fixed in 0.2.7, and it needed two rules rather than one

`#publish_findings` keeps a per-uri record of the last version published,
under one small mutex, and every writer is ordered by it without knowing
about the others. An older version is dropped; the *same* version is let
through, because a later pass legitimately knows more about it — the
Agent answering, routes arriving — and refusing it would switch those
off. A clear always wins and resets the memory, so a reopened file
publishes again at any version.

**That alone does not close this entry's own sequence.** The clear resets
the memory, so the background publish already in flight is accepted right
after it — findings, clear, findings, exactly as recorded. What separates
a stale buffer answer from a legitimate one is whether anyone has the
file open *now*: a versioned publish is a buffer's answer and requires
that buffer to still be open, while a versionless publish is the
workspace pass, which analyses files nobody has open by definition and is
subject to neither rule.

And a second clear path had to go: `#clear_diagnostics` wrote straight to
the writer, bypassing the funnel, so the memory was not the funnel's. It
is the "four writer kinds, no state" shape surviving inside the fix for
it. Pinned by an example that fails without it — a reopened file would
show nothing until edited nine times.

Rests on `029`'s M-2, landed in the same release: ordering by a version
number is only meaningful once text and version cannot be read torn.

### The Direction this was recorded with, and what it cost to follow

Recorded open, the entry said the fix was "one writer, not another
comparison" — a per-uri memory in `#publish_findings` refusing a write
older than the last, with a clear always winning. That is what shipped,
and it was **not sufficient on its own**: the open-buffer requirement
is a second rule the Direction did not foresee, and the bypassing
`#clear_diagnostics` is a third. A Direction that reads as one small
piece of state is worth keeping as a Direction; it is not worth reading
back as an estimate of the work.

**`024.52` is folded in here.** It was the same race on the debounce
waiter path, fixed on the 0.2.4-bound branch and rolled back with the
debounce (`024.57`), so its defect is this one and its code is not in
the tree. What survives it is how to write the example, both learned
from a version that passed without exercising anything:

- **A rendezvous, not two sleeps.** The background writer has to have
  reached the point under test before the dispatch thread runs.
  Started near each other, the dispatch thread wins every time.
  `server_publish_ordering_spec.rb:147` is a `Queue` pair for exactly
  this.
- **A finding that survives the close.** `didClose` removes the file's
  index contribution, so a *semantic* finding computed after it comes
  back empty — the stale publish still happens, carrying nothing, and an
  assertion about counts passes. A syntax error needs no index.


## 024.57 The debounce, and why it was rolled back

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.18
```

**Closed in 0.2.18, and the deliverable really was the record.** Driven
against HEAD, the direction this entry wrote down has been built —
partly by later releases that did not know they were answering it, and
partly here.

**"One writer that remembers what it last published" exists.**
`#publish_findings` carries `@last_published_version[uri]`, keyed *per
buffer* rather than per uri, ordered by generation, with a clear that
wins and resets. That is this entry's direction, item for item, arrived
at through `024.56`, `024.97` and `024.113` rather than through this
entry.

**The deferral no longer has the shape the entry argued about.** 0.2.10
replaced the synchronous publish with `#drain_settled_analyses`, which
analyses when the input queue settles. So round 35's second finding — the
debounce cannot bound concurrent analyses — is moot: there is no waiter
to start a second one, and the analysis runs on the dispatch thread.

**What was actually left was the invariant spec's table**, and this
entry named it: "the invariant spec written as the countermeasure has no
row containing a republish — a property is only as wide as its table."
It has three now. The one that matters reproduces the ordering the
defect was, deterministically and without a thread: the close lands
*while the republish is computing*, so findings computed against an open
buffer arrive after it is gone. It passes, and a mutation that lets the
funnel treat the closed buffer as open makes it fail.

**And the report this was all in aid of is fixed elsewhere.** `024.41`'s
false report on a half-typed call is gone as of 0.2.18, by reading the
client's edit position rather than by deferring — see that entry for why
deferring could not have reached it.

`024.45` stays open and no longer travels with this one: it is a latency
number, not an ordering property, and its cost is inside `analyze` where
no publish discipline can reach it.

**Area:** `core/lib/ovallsp/server.rb` (`#publish_diagnostics`,
`#republish_open_diagnostics`, `#publish_findings`), and whatever
replaces the deferral.

0.2.2 made `didChange` publish diagnostics from a waiter thread after a
300 ms pause, to answer 024.45. **Rounds 32, 33, 34 and 35 each found a
defect in it**, and `CLAUDE.md`'s same-place rule fired: the whole thread
was rolled back on 2026-08-07, at the maintainer's direction, and this
entry is the deliverable rather than the code.

The measurements are worth keeping, because the change did work at what
it was for. Round 35, on this machine:

| what | result |
|---|---|
| the per-keystroke half it did *not* defer (summarize + index apply), `net/http.rb` | 0.017 s |
| the per-analysis half it did | 1.72 s |
| 32 edits 0.15 s apart (faster than the debounce) | **1 analysis** |
| 12 edits 0.4 s apart, 1.72 s analysis | **12 analyses, 5 concurrent** |
| 32 edits 0.4 s apart, 5.25 s analysis | **32 analyses, 13 concurrent** |

### Re-measured for 0.2.10, twice, and the first re-measurement was wrong

The table above is this entry's own measurement of the *rolled-back
debounce*, and it stands.

A first attempt to re-derive `024.101`'s "22 wrong intermediate
publishes" typed by appending a comment, found ten correct publishes, and
concluded the claim did not reproduce. **That conclusion was withdrawn.**
The scenario was not `024.101`'s: typing a method name one character at a
time makes every intermediate state a call to a prefix that really is
undefined, and appending a comment makes none of them anything at all.

In the right scenario, 12 keystrokes 0.03 s apart on a 3,907-line file:
**12 publishes, all 12 reporting the unfinished name**, a hover asked
during the burst answered in 1.430 s median, and the client's own writes
taking 15.93 s to send 12 edits because the server was not reading. After
C9: one publish, 0.042 s, 0.52 s. `040` records both measurements and why
the first was wrong.

### What went wrong, in the order it was found

- **Round 32.** `didClose` clears the panel on the dispatch thread; a
  waiter already computing wrote its findings after the clear. Errors in
  the Problems panel for a file nobody has open, permanently for an
  unsaved buffer. Fixed by taking a mutex across the store re-read and
  the write, and taking the same mutex in `#handle_did_close`.
- **Round 33.** A `didChange` whose text is byte-identical to the indexed
  text did not refresh the pending entry, because `#reindex` reached the
  scheduler only inside `if apply_file_summary(...)` and
  `WorkspaceIndex#replace_file` returns false for identical content. The
  waiter woke, found a version mismatch, published nothing, and nothing
  rescheduled (024.54). Countermeasure:
  `spec/ovallsp/server_publish_invariant_spec.rb`.
- **Round 34.** `@publish_threads` written in four places and read in
  none; the 50 ms sleep cap -- the entire mechanism by which a waiter
  notices a close -- unpinned.
- **Round 35.** Two findings, and they are the ones that ended it.

### The two that ended it

1. **`#republish_open_diagnostics` has the same race, and the fix did not
   reach it.** It snapshots the open documents, then computes and
   publishes for each without re-reading the store, on a background
   thread, from six call sites. Close one file while another is being
   analysed and the clear lands first, the findings second. Reproduced
   three times identically: publishes for the closed file came out
   `[2, 0, 2]`. Round 32 fixed this symptom on the waiter path and left
   the older path alone, and the invariant spec written as the
   countermeasure has no row containing a republish -- **a property is
   only as wide as its table.**
2. **The debounce cannot bound concurrent analyses.**
   `#await_and_publish` releases `@pending_publish[uri]` at the moment it
   decides to publish, *before* the 2--5 s analysis. The next `didChange`
   therefore finds the slot empty and starts a second waiter while the
   first is still computing. Every one but the last is discarded by the
   version re-check, and each holds `@index_mutation_mutex` for its whole
   duration -- the lock hover, completion and `didChange` itself need. The
   coalescing window is 0.3 s against a 1.7--5.3 s cycle, so it coalesces
   edits arriving while a waiter *waits* and never while one *analyses*.
   Pausing just over 300 ms -- which is 024.41's own scenario, reading the
   completion popup -- is the common case, not the corner.

### The root cause

**Four publishers write to one stream and nothing owns the order.** The
dispatch thread, the workspace pass, the debounce waiters and
`#republish_open_diagnostics` all reach `#publish_findings`, and ordering
was added pairwise, at call sites, one round at a time: a mutex between
the waiter and `didClose`, a version re-check inside the waiter, nothing
at all between the republish and either. Each fix was correct about the
pair it named and silent about the rest, which is why every round found
another pair.

That is the same shape `CLAUDE.md` records from 0.1.12 -- bolting a sort
onto one more *reader* of a collection whose storage has no order. The
sort belongs where the value is produced.

### The direction that was actually needed

**One writer that remembers what it last published.**
`#publish_findings` is already the single funnel; it just has no memory.
Give it `@published_version[uri]`, and:

- refuse a write whose version is older than the last written for that
  uri;
- let a clear (`#clear_diagnostics`) always win and reset the record;
- delete the record on `didClose`.

That subsumes the version re-check the waiter does by hand, covers the
republish and the workspace pass without either knowing about the other,
and is the one place a future publisher would have to be wrong on
purpose to bypass. It is the same move as `Index::TypeNameResolution` and
`#code_offsets`: put the rule where the value is produced so there is
nothing to copy.

**And the deferral itself needs a different shape.** Keep the pending
slot until the publish *completes*, and re-loop rather than return if a
newer version arrived while computing. That is one analysis in flight per
uri, the last version always published, and it is what makes the
coalescing claim true rather than true-only-between-analyses.

### What was kept

Not everything from those rounds was part of the thread:

- `server_publish_invariant_spec.rb`, which holds for the synchronous
  path unchanged -- the argument for writing a property rather than a
  regression test.
- The `#reindex` correction that publishes outside
  `if apply_file_summary(...)`. It is a fix to the synchronous path and
  stands on its own; the debounce only made it visible.
- Everything from rounds 32--35 about the cache, the version checks, the
  documents and the other five countermeasures.

**Re-triaged in 0.2.17** (`024.276`). This is the rollback's own record: what was reverted, what was kept, and why. It stays open because the debounce is still wanted — by `024.41` for a false report and by `024.45` for a missed requirement — and it moves to the patch line with both of them. Nothing here waits on what a gem defines.

## 024.58 `bin/ovallsp` loaded every ABI's vendored gems, not the running one's

```yaml
status: fixed
kind: defect
released-in: 0.2.2
user-visible: no
user-visible-note: >
  A packaged VSIX vendors for one Ruby, so it has one ABI directory and
  the glob was right by accident. What it broke is the development
  configuration `docs/SUPPORT_MATRIX.md` asks for by name.
```

**Area:** `core/bin/ovallsp`, `core/lib/ovallsp/vendor_bootstrap.rb`

The bootstrap globbed `vendor/bundle/**/gems/*/lib` and unshifted every
match. Bundler lays a payload out one directory per ABI --
`vendor/bundle/ruby/3.4.0`, `vendor/bundle/ruby/4.0.0` -- so a checkout
that has run `bundle install` under two Rubies has both, and a 3.4
interpreter loaded 4.0's native `prism`:

```
LoadError: linked to incompatible /opt/homebrew/Cellar/ruby/4.0.6/lib/libruby.4.0.dylib
  - core/vendor/bundle/ruby/4.0.0/gems/prism-1.9.0/lib/prism/prism.bundle
```

`spec/integration/stdio_spec.rb` caught it the first time the suite ran
under 3.4 with 4.0 also bundled. That is precisely the configuration the
4.0 row of `SUPPORT_MATRIX` describes a contributor creating, and the
second `bundle install` is what creates it.

**ADR-0005's own words were stronger than its code.** `VendorCompatibility`
exists so the bootstrap "can refuse to add an incompatible vendor
directory to `$LOAD_PATH` at all" -- and it answers *whether* a payload
may be loaded, while nothing answered *which directories that permission
covers*. The manifest check cannot help: a dev checkout has no manifest,
which the module deliberately treats as permitted.

Fixed by scoping the glob to `Gem.ruby_engine`/`RbConfig ruby_version`,
in a new `Ovallsp::VendorBootstrap` so the decision has a unit spec at
all -- `bin/ovallsp` runs only as a subprocess, and the one integration
spec that drives it cannot construct the layouts that matter. A payload
with no ABI-matching directory now contributes nothing, which is the same
answer as no payload; falling back to the unscoped glob would reinstate
the crash for exactly the case the manifest cannot catch.


## 024.59 The guard against a stale example count could not run

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: no
user-visible-note: >
  A guard defect. Its consequence is that `SUPPORT_MATRIX` and
  `RELEASE_CHECKLIST` shipped a suite size that was wrong again, which is
  the thing the guard was written to stop.
```

**Area:** `core/spec/meta/documented_counts_spec.rb`

Added in 0.2.1's round 26 because the figure had gone stale three times
(895 for six releases, then 1,776, then 1,833). It skips unless the run
is the whole suite, and decided that by comparing a glob of spec files on
disk against `files_to_run`. The glob was rooted one level too high:

```ruby
File.expand_path("../**/*_spec.rb", __dir__.sub(%r{/meta\z}, ""))  # => core/**/*_spec.rb
```

`core/**` includes `core/vendor/bundle`, so once gems are vendored there
the glob matched the vendored gems' own spec files — ten, all
`diff-lcs`', measured by a real vendored install at 0.2.3; this entry
arrived saying "twenty", which no measurement of the layout it
describes reproduces — and the counts never agreed. **CI vendors them**: `ruby/setup-ruby`'s `bundler-cache: true`
sets `BUNDLE_PATH` to `vendor/bundle`. So the guard skipped on every
full run in that layout — CI's included, and the 0.2.4-bound branch's
machine, whose documents drifted to 1,934 against a suite of 1,941
with nothing to say so. A checkout with nothing vendored under `core/`
— the layout the unified 0.2.3 was prepared in — still compared, which
is why this branch's own audited figures stayed true while CI's guard
was blind.

Fixed by rooting the glob at `spec/`. The countermeasure is separate and
matters more: **a check that decides it is not applicable reports the
same green as one that passed.** The spec keeps its `skip` for a subset
run -- a filtered run is legitimate, and the property cannot be stated
from inside a run that may be one -- so it is enforced where the whole
suite is guaranteed: ci.yml's core job gained a "Fail if a
documented-count check skipped" step that reads the JSON formatter's
output (`core/tmp/rspec.json`) and fails a full run in which these
examples skipped.


## 024.60 Four test fixtures raced macOS' first-execution scan

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: no
user-visible-note: >
  A test-suite defect. It cost confidence rather than behaviour: four of
  six consecutive local runs of the extension's unit suite failed, in
  three different combinations, on code that was correct.
```

**Area:** `vscode/src/test/unit/coreProcess.test.ts`,
`vscode/src/test/unit/platformCompatibility.test.ts`,
`vscode/src/test/support/executableFixture.ts`

Three `ps` tests and one Ruby-query test write a stand-in executable into
a fresh temporary directory and immediately run it. macOS charges the
first execution of a newly written executable a one-off scan: measured on
this repository's own fixture, **2.62 s the first time and 0.04 s on
every run after**. `SystemProcessTreeInspector`'s snapshot timeout is 1 s
and mocha's default is 2 s, so the cold file was killed mid-query and the
assertion reported a product defect that was not there.

Load-dependent, so it flaked rather than failed, and each of the three
`ps` tests failed with a *different* message -- one timeout, one "command
failed", one "expected unparseable output to be rejected" -- which reads
as three unrelated defects rather than one cold file.

Fixed by running each fixture once before the measurement, in a single
shared `installExecutableFixture` rather than copied into both suites.
Ten consecutive runs green afterwards, and faster, because the failing
paths had been spending their time in timeouts.


## 024.63 The dispatch layer owns view inference, and it has broken the query layer's one guarantee twice

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A third occurrence was live while this note said none was, which is why
  that sentence is gone. Hover and explainType built a second extracted
  document of their own instead of reading the one the other seven
  position handlers share, so a template's hover answered nothing at a
  character where completion and go to definition both answered. That
  symptom is fixed and the two call sites that caused it are now one.
  What stays recorded is the structure: the guarantee is upheld by three
  call sites each remembering to do the same thing, rather than by
  construction.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/server.rb` (the view-inference cluster and
`#receiver_type_before_dot`), `core/lib/ovallsp/semantic/query_service.rb`.
Line numbers deliberately not given: this entry carried five of them and
every one had drifted by the release that next read it.

Around 425 lines of `Server` answer a semantic question: *which instance
variables does this view receive.* It walks the controller's ancestors,
builds the effective callback chain, evaluates each callback and then the
action, and merges the alternatives when several actions can render the
same template. Nothing about that is dispatch; it is the same kind of
work `MethodAnalyzer` and `LocalInferencer` do, in the layer that is
supposed to route requests to them.

Placement alone would be a tidiness argument. What makes it a finding is
what the placement costs.

**The guarantee.** Task 013 states it: hover and completion use the same
receiver type for the same expression. `QueryService` delivers it by
construction — every reader calls `#type_at`, so no reader can invent its
own answer.

**Where it leaks.** `#type_at` takes an `initial_env`, and for a template
that environment *is* the answer: nothing in the ERB assigns `@article`,
so the type comes entirely from what the caller passes in. That value is
assembled by `Server` and fetched independently at three places —
`#view_initial_env`, which hover, explainType and
`#receiver_type_before_dot` now share, the `@`-name list inside
`#assigned_ivars_for`, and the diagnostics context. The resolution is
unified; its input is not.

**It was four, and the fourth is how the structure finally produced a
symptom nobody had noticed.** `#explain_type_in_view` extracted the
template a second time and seeded *that* document, while
`#receiver_type_before_dot` seeded the document `#analyzable_document`
had already extracted. Hover's type therefore came out of one document
and its receiver lookup out of the other — so `#hover_lines` switched
the receiver lookup off for every `.erb` to compensate, and a model
method called on a controller-assigned `@ivar` in a template hovered
nothing while completion at the same character offered it and go to
definition found it. The fourth call site is gone; the compensation with
it.

**It broke twice, and the code says so.** `#receiver_type_before_dot`
carries the record, in its own comment:

> 0.2.1 gave the `@` list that environment and left this one behind,
> which produced the disagreement it had just spent the release removing
> elsewhere: the `@` popup said `Article` and `@article.` a keystroke
> later offered nothing.

So the release that fixed a hover/completion disagreement introduced
another one, in a second reader of the same value, and shipped both
halves. The earlier occurrence is the one the comment says the release
"spent" itself removing.

There is precedent immediately next to it. 024.1 — now fixed — was a
second copy of the controller callback-chain rule, and the cost was not
the duplication itself but that the regression spec written against one
copy pinned nothing about the copy that runs. Same layer, same subject,
same shape.

**Direction.** `CLAUDE.md`'s rule applies literally here: a place found
twice does not get hand-fixed a third time, it gets a mechanical
countermeasure. Two candidates, and they are not equivalent:

1. **Move the environment to where it is produced.** `#type_at` obtains
   the view environment itself from the uri, so no caller can forget to
   pass it. This is the real fix and it is large: it means the 425-line
   cluster moves into the semantic layer, because that is what would have
   to compute the environment. Bigger than the disagreement it prevents,
   and correspondingly its own task.
2. **Pin the property rather than the instance**, as an interim. Until
   0.2.3 no spec asserted that two readers *agree*; every existing
   example asked one reader one question. 0.2.3 added that spec —
   `server_views_spec.rb` asks hover and completion for the same
   position in a template and requires the same type, watched failing by
   dropping `initial_env` from one call site — and it would have failed
   on 0.2.1's intermediate state. It is weaker than (1) — it catches a
   divergence rather than preventing one — but it is not an instance
   test, and it is in the tree.

**What the view-hover fix took, and what it did not.** It took (1) as far
as it goes without moving the cluster: the environment is obtained once,
in `#view_initial_env`, keyed on the uri, and the three readers that
query a position all call it instead of each spelling the ternary. That
removes the reader that had already drifted and makes a fourth spelling
something you have to write on purpose. It is *not* (1): `#type_at`
still takes the environment from its caller, so a future handler can
still forget to pass one. The remaining two producers —
`#assigned_ivars_for`'s `@`-name list and the diagnostics context — ask a
different question of the same value and were left alone, per the
counter-rule that unifying readers who want the same answer *most of the
time* is how 0.2.1 lost a release.

Deliberately not attempted while the 0.2.4-bound branch's release was in
flight: (1) is an architectural move, and `CLAUDE.md`'s "during a review
loop, fix; do not add" covers exactly this — a change set that grows an
architecture while being reviewed resets the round reviewing it.

**How it was found:** while describing the layering in conversation, not
by a review round, and it was the fourth reader that gave it away — the
architecture as described has one path, and the code has four.



### Moved out in 0.2.16

Measured before the move, which is what settled it: the region touched
the LSP protocol **zero** times — no `@writer`, no `send_response`, no
`message[:...]`; the single `respond` match was the string
`respond_to do |format|` inside a comment — and every collaborator it
named was an analysis one (`@local_inferencer` 9 references,
`@document_store` 5, `@workspace_index` 4, `@hierarchy_index` 3), with
three call sites.

395 lines and 17 methods are now `Views::ControllerIvars`, handed its
collaborators rather than reaching for them. `server.rb` goes 3,936 to
3,557.

**Two mistakes made during the move, both caught by measurement:**

- `@file_summaries` is written by `Server` on every index and *read* by
  this code. The first version of the extraction gave the new class its
  own empty hash — the "two representations of one value" shape `048`
  is about, created by the change fixing it. Seven examples caught it;
  the hash is now owned there and passed by reference.
- `#load_document_from_disk` was taken along as "the last method in the
  region". It is not view inference: hover documentation and the cold
  index read it too. It is `DocumentFromDisk`, one module function the
  three share.

Three `rescue` verdicts followed their methods to the new files, with
their arguments unchanged — the failure handling did not change, only
where it lives.
## 024.64 Three rounds on `extension.ts`'s wiring, and the countermeasure was aimed at the symptom

```yaml
status: fixed
kind: defect
user-visible: no
target: 0.2.12
released-in: 0.2.12
user-visible-note: >
  Never reached a user; round 37 confirmed the behaviour, not a
  regression. What it recorded was that two countermeasures in a row
  failed to pin the call site, which 0.2.12 closed.
```

**Area:** `vscode/src/extension.ts` (the handshake note call site),
`vscode/src/versionInfo.ts` (`writeHandshakeLines`),
`vscode/src/test/`, `.github/workflows/ci.yml`

Three rounds, same place:

| round | finding | what was done |
|---|---|---|
| 33 | Both `extension.ts` note loops unpinned — nothing in `vscode/src/test` reaches that file | formatting moved into `versionInfo.ts`, five tests added |
| 36 | The note loops *still* unpinned — round 33's finding one level out | the *condition* moved into `writeHandshakeLines`, so "the mutation cannot be expressed at the call site" |
| 37 | It can. Moving the call inside `if (!diagnostic.compatible)` leaves `npm run test:unit` at 186 passing | — |

Round 37 restored 024.49's symptom exactly — a Ruby the payload was not
built for gets no Output-channel note at start-up — and no test noticed.

`CLAUDE.md`'s rule is explicit about what a third hit buys: not a fourth
fix. This entry is the deliverable.

**The root cause, which neither countermeasure addressed.** Both moved
code *out of* `extension.ts`. That pins the code and never the wiring,
because the thing being got wrong is which line calls what, and no test
in `vscode/src/test/unit` executes `extension.ts` at all — 024.17 records
that, and it is still true. `activate()` runs only under
`test:integration`, and CI runs `test:unit`. So every countermeasure of
the "extract it somewhere testable" shape will pass while the call site
stays free.

**The direction that was actually needed.** Something that runs
`activate()` in CI. That is one of:

1. `test:integration` in the CI workflow, which needs a VS Code download
   and a display. **This is what shipped**, in 0.2.12, as `024.69`.
2. A seam that lets the wiring be driven without `vscode` — `activate()`
   split so the per-folder start path is a pure function of injected
   collaborators, with `extension.ts` reduced to the part that only wires
   VS Code objects together. That is a refactor of the file, not another
   extraction from it.

Neither belongs in a review loop. **Re-scoped: this is its own task**, and
the change set returns to what it was about.

**What this entry does not ask for.** Reverting rounds 33 and 36. Their
output — `writeHandshakeLines`, its five tests, the note named by folder
— is correct and tested; what failed is the claim that it made the call
site unmutable. The claim is what is being rolled back, and the comment
in `versionInfo.ts` asserting it should be corrected rather than left to
mislead the next reader.

### Fixed in 0.2.12

Direction 1 shipped as `024.69`: `ci.yml` runs
`xvfb-run -a npm run test:integration`, with a gate that fails the job
when the suite reports no examples. `activate()` returns an `OvallspApi`
carrying the handshakes it recorded, and
`vscode/src/test/integration/handshake.spec.ts` asserts one happened for
a folder whose Core *is* compatible — **the assertion the three
countermeasures could not make**, because the notes are written on the
compatible path too, so round 37's mutation makes that fixture silent.

Not the full `activate()` split direction 2 describes. What is bought is
that the wiring is observable at all from a suite that executes it.

**A "Round 40" section stood here until 0.2.14 and was stale when it was
written.** It said `core/bin/ovallsp`'s call into `VendorBootstrap` was
unpinned by the same absence; `core/spec/ovallsp/bin_vendor_bootstrap_wiring_spec.rb`
parses the script and asserts the `VendorBootstrap.activate!` call, and
has since before that section was added. Deleted rather than corrected —
the claim had no surviving half. `046`'s C3 is the check that would have
caught it.

## 024.65 A different Ruby engine produces two error toasts where it produced one

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: no
user-visible-note: >
  It never reached a user. The duplicate was created by an engine gate
  added during 0.2.3's own review loop and reverted inside the same loop
  after round 38, so no released build has it.
```

**Reverted rather than resolved, and the distinction matters.** Round 38
established that the two toasts did not exist on 0.2.1 or 0.2.2 -- the
change set under review created them, by gating the engine dimension in
`checkBundledCoreCompatibility` so that it agreed with
`compareVersionInfo`. The agreement is real and the split it closed is
real; what it cost was a second red notification whose text advises
`gem install prism rbs` without having asked, on a Core that has them.

The gate is reverted. **The underlying split is not fixed**: two deciders
still reach the engine verdict independently, and the open question is
which of them owns the *notification*. That question is worth answering
and is not worth answering inside a review loop -- see 024.64, three
rounds of exactly that.

**Area:** `vscode/src/platformCompatibility.ts` (the engine branch),
`vscode/src/extension.ts` (the start-time notification and the handshake
notification)

On JRuby or TruffleRuby — reachable only by setting
`ovallsp.rubyExecutablePath` — the start-time compatibility check
*briefly* returned `compatible: false` for an engine mismatch, raising an
error toast, and the handshake then reported the same mismatch and raised
a second. Neither call site returned, so the client started either way,
and the user got two stacked red notifications per window for one fact.

The reason text on the first was `incompatibilityReason`, which advised
`gem install prism rbs` — produced without probing, and wrong for a JRuby
user who already has them.

**Past tense throughout: this describes code that no longer exists.**
Round 39 found the paragraphs above written in the present, inside an
entry whose own opening says the gate is reverted — 024.47's failure mode
recurring in the entry that records a revert, which is the one CLAUDE.md
keeps as a standing lesson.

**Why it is recorded rather than fixed in this loop.** The obvious
one-line fixes are both wrong. Suppressing the start-time toast loses the
only notification in the case where the Core never starts, so there is no
handshake to report anything. Suppressing the handshake toast makes the
authority that actually talked to the Core silent. Deciding which of two
deciders owns the notification is a design question, and the neighbouring
code (024.64) is a three-round record of what happens when a call-site
condition is added to settle one.

**Direction:** one decider for the *notification*, not just for the
verdict — most likely the handshake, with the start-time path escalating
only when it can establish that no handshake will follow.


## 024.66 A marketing card kept carrying claims about what an error's text says

```yaml
status: fixed
kind: defect
released-in: 0.2.3
user-visible: yes
```

**Area:** `site/index.html` and `site/ja/index.html` (the startup
handshake cards, then the platform callout), with the same claim-shape
in `docs/KNOWN_LIMITATIONS.md`/`.ja.md`, `docs/SUPPORT_MATRIX.md`/
`.ja.md` and `vscode/README.md`/`.ja.md`

Entered under the roll-back rule — the same place failed three
consecutive rounds of 0.2.3's unification loop, and the rule says the
entry is the deliverable. Three attempts, each the wrong shape:

1. **Merge round 1** fixed the index pages' platform callout, which
   claimed refusal of a combination the 0.2.1 probe path runs.
   Hand-fixed, card by card.
2. **Merge round 2** found the handshake card claiming the extension
   "stops and explains" on a version mismatch — the build reports and
   keeps running. Fixed, with a countermeasure: a verb-level sweep
   (`reject|refus|stop|拒否|停止|縮退`) across every published page,
   classifying every hit as true or false of the build.
3. **Merge round 3** found round 2's own replacement text claiming the
   mismatch error "names both versions" — the notification names
   neither; the versions are Output-channel reason lines. No refusal
   verb in it, so the sweep could not see it: the countermeasure was
   aimed at the symptom's vocabulary, not the class.

**Root cause:** a published card carried micro-claims about what error
text *says*, and such a claim must be re-verified against the build on
every edit — including the edits made to fix the previous claim. Three
rounds each produced a new false sentence while correcting the old one.

**The rollback (merge round 3):** the cards now state only what does
not need per-edit verification — the exchange happens, a mismatch is
reported, the session keeps running, the specifics are in the Output
channel, 024.55 tracks the follow-through. No error-text claims remain
on either card.

**Merge round 4 extended the same adjudication to the survivors.** Ten
published sentences — the platform callout in both languages, and
`gem install prism rbs` sentences in `KNOWN_LIMITATIONS`,
`SUPPORT_MATRIX` and the READMEs, both languages — attributed that
line to "the error", meaning the notification. The build's
notification names no gems; it points at the Output channel, whose
detail does name them (`platformCompatibility.ts`, the half
`platformCompatibility.test.ts` pins). Four of the ten predate 0.2.3
on `main` (both `KNOWN_LIMITATIONS` Ruby-scope instances, both
`SUPPORT_MATRIX` rows); six were introduced by 0.2.3's own honesty
pass and caught before release. The fix follows the split the
rollback drew: marketing cards carry no error-content claims at all,
and documentation states the notification → Output-channel split,
whose Output-channel half is the test-pinned part. The READMEs'
no-Ruby sentence — "explains what's wrong and what to do rather than
half-starting", published since before 0.2.3 — fell in the same pass:
that path's reason carries no remedy, and the session still attempts
to start (024.55).


## 024.67 Seven register numbers are cited from the tree and resolve to nothing

```yaml
status: fixed
kind: defect
user-visible: no
released-in: 0.2.7
user-visible-note: >
  The dangling pointers live in source comments, spec comments and
  changelog entries -- developer-facing routes to reasons, not
  anything an editor user sees or a behaviour the extension has.
target: 0.3.0
```

**Fixed in 0.2.7, and there were 23, not seven.** Counted mechanically
rather than by reading: `core/spec/meta/measured_claims_spec.rb` scans
every `024.N` cited in `core/lib`, `core/spec`, `vscode/src` and `docs`,
and found sixteen more than this entry recorded — including two in a task
record and seven in the extension's own source and unit tests.

The numbers resolve again: the register's head now carries a **Retired
numbers** table naming what each deleted entry recorded, recovered from
git history, and the same spec accepts a citation that resolves to a row
there. So a deletion cannot leave a dangling pointer whether or not
anyone remembers the legend's grep — which is the arrangement that failed
here, three times over.

`024.70` is in that table for a different reason: it was **withdrawn**
rather than fixed, and the table says so.

**Area:** this file's legend (the deletion rule),
`core/lib/ovallsp/types.rb:122`,
`core/lib/ovallsp/local_inferencer.rb` (607, 741, 878, 1043),
`core/lib/ovallsp/semantic/method_analyzer.rb:255`,
`vscode/src/coreProcess.ts:413`, `vscode/src/extension.ts:50`,
`vscode/src/clientLifecycle.ts:245`,
`vscode/src/clientErrorNotifications.ts:32` and its unit test, and
both changelogs

`024.2`, `024.3`, `024.7`, `024.9` and `024.12` are cited from live
source and spec comments as the route to the reason a piece of code is
the way it is, and `024.4`/`024.5` are cited from both changelogs. None
has a `## 024.N` entry. The entries were deleted around 0.1.9–0.1.10 —
before the legend learned its lesson about exactly this ("run the grep
before deleting, not the calendar"), and nothing ever re-checked the
earlier deletions against the rule once it existed. For the five cited
from source and specs this violates the legend's letter; the changelog
pair is the same class through a document the legend does not name.

Found by merge round 5 of 0.2.3's loop, by full cross-reference at
626d652: 58 entries against 74 distinct number-shaped citations, two
of which are *sub-numbered* synthetic fixture strings inside
`deferred_findings_spec.rb`'s own format examples — not citations of
entries, and excluded as such. (Described rather than spelled: `024.182`
widened the citation guard to read a sub-number as itself, so writing
those two out here makes this paragraph two dangling pointers.
`024.126`'s repair for prose, applied where the helper cannot reach.) Of the remaining 72, the other
unmatched citations (`024.51`, `024.54`, `024.57`, `024.58`, `024.61`,
`024.64`, `024.65`) are the legend's own documented cross-branch
reservations and gap, not defects. (Re-run the cross-reference rather
than trusting these figures; they were measured at one revision, and
merge round 6 caught this paragraph's first draft omitting the
exclusion it was measured under.) Pre-existing at 0.2.3's base.

Recorded rather than fixed because the fix is not small and the loop
runs under fix-don't-add: seven entries would need resurrecting from
history accurately, and the durable form wants the project's own
countermeasure shape — a `deferred_findings_spec` example that every
`024.N` cited from source or spec resolves to an entry, plus a
tombstone convention (a stub entry pointing into history) so historical
citations can stay without forbidding deletion forever. That guard
belongs with 024.R9's register move, which re-points the guard spec
anyway; hence the target.


## 024.68 Three rounds of guards on a hand-rolled grammar, each blind one assumption deeper

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Register hygiene: a typo'd or mis-indented metadata key silently
  un-routes an entry, and nothing an editor user sees is involved.
  Closed in 0.2.12 by deleting the grammar the three rolled-back guards
  were guarding.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/spec/meta/deferred_findings_spec.rb` (the
`entries`/`headings` readers and every guard bolted onto them), this
file's legend

The original defect, found by round 10 of 0.2.3's unification loop:
`target:` routes entries to releases, and a typo'd key was silently
ignored by every guard — the value-typo class `status` defends against
("Anything else reads as open") had no key-side counterpart. Three
consecutive rounds then shipped a guard and had it broken by the next
round, each break one assumption deeper:

1. **Round 10** filtered the *parsed* fields against a `KNOWN_KEYS`
   list — blind outside the field parser's own `[a-z-]` class:
   `Target:` and `user_visible:` never parsed as fields at all
   (round 11 planted `Target: 0.2.4`; 24/0, silent).
2. **Round 11** flagged stray lines instead — but skipped every
   indented line as "the folded note's continuation", so one leading
   space (` target: 0.2.4`) was invisible again (round 12; 25/0).
3. **Round 12** made the walk stateful (indentation legitimate only
   inside an open folded `>` value) and added a loose heading
   pre-scan — and round 13 found both halves blind one state deeper:
   an indented typo *after a folded note* reads as continuation, and
   a heading indented 1–3 spaces renders as a real `h2` under
   CommonMark while all three column-0-anchored readers miss it
   symmetrically (28/0 both, no live instance).

**Root cause:** the metadata grammar is a hand-rolled parser
("deliberately not a YAML parser"), and every guard re-derives "what
is a field / a heading" from it with a fresh subset of its
assumptions — character class, indentation, anchoring. Round 13
measured the end state: the guard was *more permissive than YAML
itself* (Psych raises "did not find expected key" on the exact text
the guard accepted). Patching one assumption manufactures the next
round's finding one assumption deeper; the supply of assumptions is
the hand-rolled parser, not any single patch.

**Direction actually needed:** stop hand-parsing. Parse the blocks
with the real YAML parser and fail on `Psych::SyntaxError` — the
round-13 probe shows Psych already rejects the class outright — with
one loose anything-heading-shaped scan owned beside the strict
reader. That is grammar-formalisation work and belongs with 024.R9's
register move, which re-points this spec anyway; hence the target.

**The rollback, per the counting rule** (rounds 10 → 12 came out as
one thread): `KNOWN_KEYS`, `unknown_keys`, `unreadable_headings` and
their six examples are removed. **What survived:** the legend's
`target:` documentation line — it fixes the *undocumented* half of
round 10's finding, never failed a round, and removing it would
recreate a recorded defect. Until the direction above lands, key
typos in this file are once again caught by nothing; a reviewer
reading the register should know that, which is this note's job.

**Fixed in 0.2.12, by deleting the grammar rather than guarding it a
fourth time.** The block is fenced ` ```yaml `, and it was being scanned
with `/^([a-z-]+): *(.*)$/` under a comment saying "deliberately not a
YAML parser". Every one of the three guards was an attempt to
re-implement, in that scanner, something a yaml parser does for free —
which is why each was blind one assumption deeper than the last.

`DeferredFindings.entries` now calls `YAML.safe_load` and checks the keys
against `KNOWN_KEYS`, the set the legend defines. `Target:` and
`user_visible:` are keys like any other and fail as unknown; a key
indented under another is a nested mapping and fails the same way; a
block that is not valid yaml raises rather than parsing to nothing.
Four examples pin it, including the control that the real register still
parses.

The one shape that needed care: yaml turns an unquoted `yes` into `true`,
and every caller compares against the string `"no"`. Values are
stringified back, which is a real behaviour and is why the control
example exists.

**This paragraph was filed under `024.69` until 0.2.14**, so an entry
read on its own said the register was "deliberately unguarded again"
while its fix had shipped two releases earlier. `046`'s RC-4 is the
class: nothing re-reads an entry after it is written.

## 024.69 The two suites that drive a real editor are run by nobody but the maintainer

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing an editor user sees. The gap is in verification coverage:
  the suites still pass once run, and 0.2.3's gate ran them. What is
  missing is anything that runs them between releases.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `.github/workflows/ci.yml` (the `vscode` job),
`vscode/package.json`'s `test:integration` / `test:integration:packaged`

CI runs `npm run test:unit` for the extension and nothing else. Both
integration suites — the only tests that launch a real VS Code and
drive the extension against a real Core, and the ones
`RELEASE_CHECKLIST`'s Task 023 gate items #4 and #5 are about — run
only when a maintainer runs `make-final-review-bundle.sh` on an Apple
Silicon Mac. Between releases they are executed by nothing.

**How it surfaced.** 0.2.3's pre-publish gate aborted at
`test:integration` with `spawn .../Contents/MacOS/Electron ENOENT`.
VS Code renamed the macOS bundle's main executable from `Electron` to
`Code` in 1.110, `runTest.ts` pins no version so it always downloads
current stable (1.133.0 on the day), and the pinned
`@vscode/test-electron@2.5.2` still computed the old path. The
harness had been broken for every VS Code release since 1.110 and the
tree recorded gate #4/#5 as green throughout, because the only thing
that could have contradicted that was the gate itself. Fixed here by
the bump to `@vscode/test-electron@^3.1.0`, which resolves the
executable by product name with a "sole regular file in
`Contents/MacOS/`" fallback — but the bump is the instance, not the
class.

**Why this is the same shape as a green suite that did not run.**
CLAUDE.md already carries that rule for the real-Rails and capability
suites, whose failure mode is skipping to zero examples while `rspec`
exits 0. This is the same failure with the reporting removed
entirely: not a suite that reports nothing, a suite that no automated
run ever reaches. The asymmetry is what made it durable — CI is green
on every PR, so nothing prompts anyone to doubt the row.

**Direction:** run both suites in CI on a schedule at minimum, and on
release PRs at best. `test:integration` needs a display on
`ubuntu-latest` (`xvfb-run`, the usual arrangement for
`@vscode/test-electron`); `test:integration:packaged` additionally
needs the vendoring step, whose native gems are built per platform,
so the packaged variant is honest only on macOS and wants a
`macos-14` runner. Deferred rather than done here because adding two
CI jobs during a release gate is an addition, not a fix, and the
`macos-14` half costs paid runner minutes on every run, which is a
trade-off this entry does not get to make on its own.

**Fixed in 0.2.12** by a `vscode-integration` job that runs
`npm run test:integration` on every pull request and push --
`xvfb-run` for the display, and Ruby with the bundle installed because
the extension spawns the real Core Server, which is the half a unit test
cannot reach.

The measurement this entry is really about is not the suites passing; it
is **who runs them**. Twice a month, by one person, on one machine, is
how a harness stays broken across four VS Code releases while the tree
records the gate items about it as green.

**And the job asserts the count, not just the exit code.** `runTest.js`
exits 0 when the extension host reports no failures, and no failures is
also what zero examples looks like -- so a harness that stops discovering
tests, or an activation that quietly never happens, would read as a pass.
Adding the job without that check would have replaced "nobody runs them"
with "CI runs them and would not notice if it stopped", which is the same
defect wearing a green tick. The core job has carried the equivalent
guard since 0.2.5. First run: **5 passing**, against a real VS Code
1.134.0 driving a real Core.

**And the first guarded run reported green with `1 failing` in its log**,
which is worth recording rather than quietly fixing. `xvfb-run … | tee`
takes its exit status from `tee`, so the job added to stop a suite going
unrun spent one commit being a suite that ran and was not listened to --
the same defect the entry is about, one layer out. `set -o pipefail`.

The failing example was a real flake and is fixed in the same change:
`createFileSystemWatcher` registers asynchronously, so a file written
immediately afterwards can be created before anything is listening, and a
create event for a file that already exists never arrives however long
the test waits. It now rewrites each still-unseen file each time round
the loop, which turns the race into a retry. It had passed on the run
before, and locally -- **two runs of a new job found a flake that no
amount of reading would have.**

## 024.72 The red toast 0.2.1 removed is still shown, from the other code path

```yaml
status: fixed
released-in: 0.2.2
kind: defect
user-visible: yes
```

**Area:** `vscode/src/versionInfo.ts` (`compareVersionInfo`, the Ruby
mismatch branch), `vscode/src/extension.ts` (the `showErrorMessage` for a
version-incompatible Core)

0.2.1 changed `platformCompatibility.ts` so that a Ruby the bundled
payload was not built for is checked rather than refused: if it carries
`prism` and `rbs`, OvalLSP runs against those and says so in the Output
channel. `versionInfo.ts` still compares the manifest's
`rubyVersionMajorMinor` against the running Core's Ruby and reports
incompatible, and `extension.ts` shows an error toast for that
unconditionally.

Measured against the compiled `out/versionInfo.js` with a 3.4 manifest:
`3.4.7` compatible, `4.0.6` and `3.3.9` incompatible with "Ruby version
mismatch".

**What a user sees:** on Ruby 3.3 or 4.0 with the gems present, a red
error toast on every window -- the thing 0.2.1's change was for --
worded differently. `docs/SUPPORT_MATRIX.md`'s 3.3 and 4.0 rows and both
getting-started pages say it is an Output-channel line.

**Direction:** one function decides whether a Ruby is usable, and both
call sites read it. Today two functions decide and only one was changed.


## 024.73 The fork boundary is undone by `Marshal.load` in the parent

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Reachable only by a client that sends `pluginManifests`, and the
  shipped extension sends none, so no user of the published build was
  exposed. It is recorded as a defect rather than a hazard because the
  containment it breaks is the entire reason the fork exists.
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/plugins/loader.rb:446` (`Marshal.load`),
`:340` (`deliver_result`), `docs/SECURITY_CHECKLIST.md:42`

`Loader` forks a plugin so that a broken or hostile one cannot take Core
down, and reads the result back over a pipe with `Marshal.load`. Those
bytes are produced by the plugin's own code. `Marshal.load` instantiates
whatever classes the stream names, **in the parent, before any of this
file's validation runs** — so a plugin that wants to cross the boundary
the fork exists to create can, through an ordinary deserialisation
gadget. `partition_plugin_facts` validates the data afterwards, which is
too late to matter.

`docs/SECURITY_CHECKLIST.md:42` already claims this channel carries
「Marshal可能なプレーンデータのみ」. Nothing enforces it. That line should
be read as the requirement it was meant to be, not as a description of
what happens.

This file already records two rounds of hardening against a plugin
reaching the pipe by other means (`:360-375`: a forged payload written
through an `ObjectSpace`-discovered `writer`, reproduced live). Both
narrowed *who can write to the channel*. Neither addressed what the
parent does with what arrives.

**The obvious fix does not fit, and that is the finding's substance.**
Switching the channel to JSON was the first direction, and it breaks the
plugin contract: declarations legitimately carry real objects —
`core/spec/fixtures/plugins/state_machine_example/lib/plugin.rb`
returns `Ovallsp::Types::Nominal.new(name: "Boolean")` inside a
declaration, and the SDK's contract is written around that. `Marshal`
was chosen *because* the payload is objects.

**Direction:** send plain data across the boundary and reconstruct the
typed objects in the parent from validated fields — the parent already
knows how to build a `Declaration`, and `partition_plugin_facts` already
decides what is well-formed. That makes validation precede construction
instead of following it, which is the actual invariant wanted. It is a
protocol change (`Plugins::CURRENT_PROTOCOL_VERSION`) and a change to the
SDK's documented contract, so it is a task rather than a patch. A
`Marshal.load` allowlist proc is **not** an alternative: the proc runs
after each object is constructed, which is after a gadget has fired.

**Gated meanwhile.** `Server#load_static_plugins` had no trust check at
all until 0.2.5; it has one now, so an untrusted workspace cannot reach
this path even via a client that would otherwise pass manifests. That
narrows exposure; it does not close the class.

**Shipped open in 0.2.5**, retargeted to 0.2.6. The gate is what made
that defensible rather than the size of the remaining work: reaching this
code needs a client that sends `pluginManifests` *and* a trusted
workspace, and the shipped extension sends none.

### Fixed in 0.2.6, and the predicted protocol change was not needed

`Plugins::Wire` is the boundary's format: the child encodes to JSON, the
parent decodes from fields it has checked. Nothing in a payload can name
a class, so there is no object to construct before validation — the
invariant this entry asked for, reached the way the direction above said
(plain data out, typed values rebuilt in the parent).

**`CURRENT_PROTOCOL_VERSION` stays at 1, which the direction above did
not anticipate.** It predicted a protocol change and a change to the
SDK's documented contract, on the reasoning that declarations carry real
objects. They do — and both ends of the encoding are Core, so the
plugin-facing API is untouched: a plugin still writes
`return_type: Types::Nominal.new(name: "Boolean")` and still gets a
`GeneratedMethodFact`. Nothing a plugin author reads or writes changed,
so bumping the version would have refused every existing manifest for no
compatibility reason.

The one behavioural narrowing, recorded in `plugin-sdk.md`: a
`return_type` outside the `Types` lattice used to cross as whatever
object it was and now becomes nothing. That was already outside the
documented contract (`StaticContext#register_declarations` says "optional
Types value"), and carrying it was the defect.

Pinned by two examples that fail against the old boundary: the loader
never calls `Marshal.load` on this path, and a Marshal payload arriving
on the result pipe is rejected rather than decoded. Asserted as "never
calls it" rather than by demonstrating a gadget, because a gadget is a
property of whichever classes happen to be loaded — a passing gadget test
would be evidence about this Gemfile, not about the boundary.

## 024.74 The trust gate stands in front of callers, not in front of what executes

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user sees, and nothing reachable today: every existing caller
  is gated. It is recorded because "every caller happens to be right" is
  the exact property 0.2.5 spent its trust work removing, and this is the
  same shape one level down.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/server.rb` — `#restart_agent`,
`#trusted_for_execution?` and their call sites

0.2.5 routed every path to code execution through one predicate. Found by
that release's own attack round: the predicate guards the *callers*.
`#restart_agent` spawns, and is itself ungated; what is gated is
`restart_agent_result`, `maybe_start_agent`, and `maybe_restart_agent`
(reachable only when `@agent_manager` is set, which trust already
decided). That closes today. A fourth caller closes nothing, and nothing
would fail when one is added.

The release record for 0.2.5 names this shape as the bug it was fixing,
one level up — which is the argument for finishing it rather than an
argument that it is fine.

**Direction:** the check belongs at the point of execution, not in front
of each route to it — `#restart_agent` asks, and the call sites stop
asking on its behalf. The cost is that the refusal then has to be
reported by a method whose callers expect it to have started something,
so the return contract changes; that is why this is a task rather than a
line. `Plugins::Loader` and `Observation::Runner` want the same treatment
for the same reason.

### Fixed in 0.2.16

Reproduced first, on a server that never handled an `initialize`:
`restart_agent_result` answered `{acknowledged: false, reason:
"workspace not trusted"}` with zero `bootstrap.start` calls and a logged
warning, while `#restart_agent` on the *same* server returned a Thread,
called `bootstrap.start` once, and logged nothing.

`#restart_agent` now asks `#trusted_for_execution?` in front of the
`Thread.new` and answers `nil` for a refusal; `restart_agent_result`
reads that nil instead of asking on its behalf. The return contract is
`Thread | nil`, as the Direction predicted, and `maybe_restart_agent`'s
`if @agent_manager` is now only "nothing to restart" — its comment says
so.

**What the change surfaced is the more interesting half.** Ten examples
across `server_rails_invalidation_spec` and `server_ancestry_spec` broke,
every one of them a fixture that injects `@agent_manager` directly and
never tells the server it was trusted. That is the entry's own claim
measured: those servers were reaching the spawn on a workspace nothing
had granted, and only the *shape of the fixture* — not any gate — decided
it. They now say `@workspace_trusted = true`, which is what a server
holding a live Agent means, in the same form `server_status_spec.rb`
already used for `restart_agent_result`.

`Plugins::Loader` is gone with the plugin subsystem. `Observation::Runner`
still wants the same treatment and is not part of this.


## 024.75 A documented field selects nothing

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Documentation-only. The behaviour it describes -- picking an
  interpreter from a workspace file -- does not exist, so no user is
  affected by it working differently than described.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `vscode/src/rubyResolver.ts` — `RubyResolverEnv.workspaceRoot`

The field is documented as being used for `.tool-versions` and
`.ruby-version`, and is never read; its declaration is its only
occurrence. Found by 0.2.5's attack round while establishing that
`resolveRuby` reads no workspace-controlled file — which it does not, and
that is a security property worth keeping.

So the comment describes a feature that does not exist, in the file
someone would read to check whether interpreter selection can be
influenced by the workspace. **Fixed in 0.2.12 by deleting it** -- the field was added in
anticipation and never wired, and implementing the lookup instead would
be a real feature that has to be gated on trust like everything else that
lets a workspace choose what runs.

**And the property it obscured is now stated where it can be checked.**
`resolveRuby and the workspace` asserts that `RubyResolverEnv` has
exactly four fields -- `platform`, `home`, `pathEnv`, `existsSync` -- so
a fifth arriving is a change someone has to argue for rather than one a
reader has to notice.

The check deliberately does *not* forbid the string `.ruby-version`,
which the first draft did and which failed: chruby reads
`~/.ruby-version`, under `env.home`, and a file in the user's own home
directory is not something a cloned repository can write. The invariant
is about the resolver's **inputs**, not about which filenames it knows,
and writing the first version taught the difference.
## 024.77 A call to a method that does not exist is missed through a relation

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Withdrawn rather than fixed: re-driven in 0.2.15 with a control that reverts the fix and watches the defect return, and it does not reproduce.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/local_inferencer.rb`

`Billing::Order.recent.first.tracking_label` — a method that does not
exist on that model — is reported by nothing, on either branch. The same
wrong call written as `Billing::Order.find(id).tracking_label` **is**
reported.

Completion knows the answer: at that position it offers 329 labels and
`tracking_label` is not among them. So the type is available and the
diagnostic path does not use it. Found by 0.2.5's round 2 while
confirming the scope fix.

`Model.scope.first.method` is an everyday Rails idiom, and undefined-call
detection is half of what section 0 says 1.0.0 is, so this is the
headline capability missing on the headline path.

**Direction:** find where the diagnostic path's receiver typing diverges
from completion's — the two disagree at the same position, which means
one of them is asking a question the other is not. That divergence is the
defect; the missing report is its symptom.


### 0.2.15 assessment: claimed not to reproduce — **not yet confirmed**

An assessment run drove this against HEAD and reported that it does not
reproduce. The evidence is real and is quoted below. **It has not been
independently confirmed, and the entry therefore stays open.**

The second attempt at confirmation failed on its own control: a fixture
that cannot tell *"the defect is gone"* from *"nothing of this kind is
reported at all"* proves neither. That is the same defect the assessment
would be closing, one level up.

*This matters here specifically. `024.130` was published to users as a
limitation the product does not have, because a bullet was promoted to a
numbered entry without its reproduction being re-run. Closing an entry
on an unconfirmed claim is the same act in the other direction.*

**What 0.2.15 must do:** re-run this with a control that distinguishes
the two outcomes, and close it or keep it on that basis.

<details><summary>The assessment's evidence, verbatim</summary>

```
Driven at HEAD 5d20fe7 with a full AnalysisStack (workspace_index + hierarchy_index + generated_method_index all fed from the parse summary, which matters — see note 1). Fixture: `module Billing; class Order < ApplicationRecord; scope :recent, -> { where("created_at > ?", 1) }; end; end`, model registered in ModelRegistry.

  type Billing::Order.recent                    => Relation[Billing::Order]
  type Billing::Order.recent.first              => Billing::Order | nil
  type Billing::Order.find(1)                   => Billing::Order
  diag Billing::Order.find(1).tracking_label         => ["Billing::Order has no method named `tracking_label`"]
  diag Billing::Order.recent.first.tracking_label    => ["Billing::Order has no method named `tracking_label`"]
  diag Billing::Order.first.tracking_label           => ["Billing::Order has no method named `tracking_label`"]

The entry's headline example IS reported. It was closed in 0.2.6 and the tree already says so in three places the register did not get updated from: core/lib/ovallsp/diagnostics/engine.rb:120-131 names `024.77` as the reason `#reportable_branches` exists; core/spec/ovallsp/diagnostics/union_receiver_spec.rb pins it by name; docs/design/tasks/035-0.2.6-honest-diagnostics.md:93 states "`Model.scope.first.missing` is reported (`024.77`)". docs/design/tasks/042-second-enumeration.md:128 had already re-scoped what remains to "a receiver's *type* after a relation hop", i.e. 024.87.

I then tested the entry's stated Direction ("find where the diagnostic path's receiver typing diverges from completion's") directly, comparing QueryService#members_of against the unknown-method finding at the same position:

  Billing::Order.find(1)                    type=Billing::Order           members=9    reported=true
  Billing::Or
```

</details>

## 024.78 Completion did not get the fix hover and diagnostics did

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/semantic/prefix_completion.rb`,
`core/lib/ovallsp/semantic/query_service.rb`

0.2.5 stopped RBS type names losing their namespace, which fixed hover
(`File.stat(path)` says `File::Stat`) and removed a false positive. Round
2 found completion unchanged: with a workspace class named `Stat`
present, `File.stat(path).` returns that class's 121 labels — byte for
byte what completing `Stat.new(x).` returns.

**Round 3 corrected the mechanism, and the correction changes the fix.**
The two features do *not* get different types: `type_at` answers
`File::Stat` at that position either way. The divergence is inside
`QueryService#members_of`, which resolves the type it was given to a
member list and picks the workspace class. So this is not two readers
inferring differently — it is one reader losing the qualification while
looking members up.

That matters because the first diagnosis pointed at `024.47`'s subject
(where a type's answer is produced) and this one points somewhere much
narrower and cheaper. The original wording — "one expression answers as
two different types depending on which feature is asked" — named a cause
that does not exist.

### Fixed in 0.2.6, one level below where round 3 put it

Round 3 was right that member lookup is where the qualification is lost,
and wrong about which component loses it. `QueryService#members_of` asks
`MethodResolver`, which asks `WorkspaceIndex#resolve_type_name` — and
that matched on the **last segment alone**, then fell back to the
alphabetically first candidate. `File::Stat` therefore resolved to a
top-level workspace `Stat`, and every member of that class came back.

`Index::TypeNameResolution.substitution?` could not see it: that rule
returns false for any name containing `::`, on the stated reasoning that
"a receiver written or inferred as `Foo::Logger` carries its namespace
and is nobody else's answer". `File::Stat` is the counterexample — it
carried its namespace and was answered by somebody else anyway.

So the fix is in resolution, not in a second reader applying a guard: a
written namespace constrains the answer. Not to equality, because
`Inner::Klass` from inside `module Outer` legitimately means
`Outer::Inner::Klass`, so the test is a **suffix on segment boundaries**.
`::Stat` does not end with `::File::Stat`; `::Outer::Inner::Klass` does
end with `::Inner::Klass`.

**Bare names are untouched**, deliberately: applying a shadowing rule to
them in resolution is what 0.2.1 rolled back (`024.47`), and that
rollback was about a name written bare from inside its own namespace.
This change cannot reach that case.

Measured on the 213-file corpus: `unknown-method` unchanged, so no
precision was traded. Re-driven directly: `File::Stat` now answers 167
members and no longer leaks the workspace class's, while `Stat` still
answers its own 121.

**Two corrections to the paragraph that stood here**, both from a review
round that re-measured it:

- "every one of the nine is `Concurrent::Error`-shaped" — one is. The
  nine are `TruffleRuby::AtomicReference` ×2, `Truffle::AtomicReference`,
  `URI::Parser`, `Racc::Parser`, `ActiveSupport::JSON`,
  `Concurrent::Error`, and `Rack::Utils::{ParameterTypeError,
  InvalidParameterError}`. Most name a gem outside the indexed corpus,
  which had been answered by an unrelated class of the same basename. Two
  are a *constant alias* (`ParameterTypeError = QueryParser::ParameterTypeError`),
  which is `024.82`'s neighbour rather than `024.82`.
- **`unresolved-constant` was not a valid control for this change.**
  CLAUDE.md defines a control as a category the change cannot affect, and
  this one reads `resolve_type_name`, which the change rewrites. It did
  not come out equal, and it could not have. `unknown-method` staying put
  is the real evidence here; the control belongs to the changes that do
  not touch resolution.



Remove the shadowing class and completion returns 167 correct labels
where 0.2.4 returned 0 — so the release *is* an improvement here, just an
incomplete one.

**Direction:** in `QueryService#members_of`, where the qualified name is
being dropped during member lookup. Not with `024.47` — that was the
first diagnosis and round 3 disproved it.

## 024.79 `Model.first` completes to nothing

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/models/*`, `core/lib/ovallsp/local_inferencer.rb`

`Billing::Order.first.` offers no completions at all, while
`Billing::Order.recent.first.` offers 329. Found by 0.2.5's round 2.

`Model.first` is more common than `Model.scope.first`, so the working
path is the rarer one. The relation from a `scope` is generated with a
declared return type; the one from `first` on the model class evidently
is not, or is not carrying the element type through.

**Direction:** whatever gives `scope` its `Relation[Model]` should give
the finder methods their `Model | nil`. Cheap to check, and it is a
daily path answering nothing.

### Fixed in 0.2.6

`Model.first` was simply absent from `#resolve_class_level_finder`'s
list, which knew `find`, `find_by`, `where` and `all`. Adding a name
would have fixed the symptom and left the next one; instead the method
falls through to `#resolve_relation_member`, asked as if the call had
been written `Model.all.<name>` — which is what Rails does, since
`ActiveRecord::Querying` delegates every one of these to `all`. One place
decides what a relation method returns and it stays one place.

That immediately showed the same hole one level down: `#first` was the
*only* record-returning finder modelled, so `orders.last` and
`User.last` both answered nothing. `RELATION_RECORD_FINDERS` now names
`first`/`last`/`take`, their bang forms, and `find`, split by whether the
call can return nil.

Verified end to end, not only in the unit: with a `User` model
registered, `User.first` now infers `User | nil` and completes to the
same member list as `User.all.first` and `User.find(1)`, where before it
inferred `Unknown` and completed to nothing.
## 024.80 An unresolved hierarchy edge is expressible as a method owner

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  The live instance it caused -- completion offering the workspace's
  top-level methods on a class with an unidentifiable parent -- is fixed
  in 0.2.5. What is open is the representation that made it possible,
  and there is no second live instance known today.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb` (`AncestorEntry`),
`core/lib/ovallsp/semantic/method_resolver.rb`,
`core/lib/ovallsp/index/symbol_id.rb`

`HierarchyIndex` records a parent it cannot identify — `class Foo <
(expression)` — as an `AncestorEntry` with `name: nil`. That preserves
the uncertainty, which is right. But `nil` is *also* the owner a
top-level `def` is indexed under, so a nameless entry passed to a method
lookup answers with every top-level method in the workspace.

`MethodResolver#build_candidate` guards against it, with a comment
recording the bug it caused. `#names_for_type` — what completion asks —
did not, and offered exactly that. Reproduced and fixed in 0.2.5.

**Found by an external review** (GPT-5.6 Sol, recorded in
`034-diagnostics-precision-review-gpt-5.6-sol.md`) reading the two
consumers against each other. It is the shape that review was asked to
look for, and stated in its own words: *one consumer locally sealed an
ambiguous representation, while a second consumer of the same
representation did not.*

**Why the guard is not the fix.** Two readers now each remember to
refuse. A third will be written. The representation is what permits the
mistake: `nil` means "no owner" in one index and "the top-level owner" in
another, and nothing stops the first being passed where the second is
expected.

**Direction (the review's, and it is the right shape):** an unresolved
edge must not be expressible as a real declaration owner. Either a
distinct unresolved-link type that no method-lookup API accepts, or an
`AncestorChain` result carrying `entries` plus `complete?` and its
reasons, so a consumer must decide what to do about incompleteness rather
than being handed a `nil` that looks like data.

The second form is worth more than this entry alone: it is also what
`024.76` needs — `closed_nominal?` cannot currently tell "no ancestor"
from "an ancestor I could not name", and that is the same conflation one
level up.
**Fixed in 0.2.12, and the fix found three readers rather than the two
the entry named.** The member is `identified_name` and the accessor is
`#name`, which raises `Semantic::UnidentifiedAncestor` on an edge nobody
resolved — so "the owner of an unresolved edge" is not a thing that can
be spelled. `AncestorEntry.unidentified(origin:, location:)` is the only
way to make one, and `#name_or_nil` is there for the readers that
legitimately want a dedupe key or a log line, named so that reaching for
it is a decision.

The two guards the entry describes were `MethodResolver#build_candidate`
and `#names_for_type`. Making the value refuse turned up three more the
same run: `#rooted_instance_chain?`, which would have compared `nil`
against `::BasicObject`; `Engine#declared_signature_for`, which asked RBS
for a signature under the `nil` owner — the owner a *top-level* `def` is
indexed under, so it took whatever the top level happened to declare;
and one in the singleton tail. Each had been waiting for the bug to be
found a third time.

## 024.81 An ancestor reference carries no lexical context, so an ambiguous name is picked rather than resolved

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/index/ancestor_fact.rb` (its shape),
`core/lib/ovallsp/parser_service.rb` (`#record_ancestor_call`),
`core/lib/ovallsp/workspace_index.rb` (`#resolve_type_name`)

**Corrected in 0.2.6's review loop: this *is* user-visible, and the
`user-visible: no` it carried was wrong.** The note claimed only the
diagnostic changed. The refusal was placed in `HierarchyIndex`, which is
what completion and go-to-definition read, so a class whose ancestor name
is ambiguous loses that module's members everywhere. Measured with the
entry's own fixture, asking `MethodResolver` rather than the engine:

| | completion candidates for `Rackish::Request` | `resolve("request_method")` |
|---|---|---|
| `Rackish::Request::Helpers` alone | 1 | 1 candidate |
| plus an unrelated `Aaa::Helpers` | **0** | **[]** |

The nested `Helpers` is inside the includer, so Ruby's lexical lookup
makes it unambiguously right, and it is refused because some other
namespace has a `Helpers` — one of the four names this entry itself calls
common. The `no` also satisfied `deferred_findings_spec`, so no
`KNOWN_LIMITATIONS` paragraph was written for a capability loss; that is
now written, and it is why the guard's two directions are worth having.

Found by an independent review round; the yaml and the prose two
paragraphs below it had been disagreeing since the entry was written.

`AncestorFact` carries `owner / relation / target / location`. The target
is the constant **as written**, and Ruby's constant lookup is lexical —
so the one thing needed to identify the ancestor is not recorded.
`resolve_type_name` then resolves a bare name by picking the first
ordered candidate, deterministically since `024.15` but with nothing to
prefer between them.

Reproduced: an unrelated `Aaa::Helpers` anywhere in the workspace
captures `Rackish::Request`'s `include Helpers`. The chain still reaches
`BasicObject` and every entry resolves, so `closed_nominal?` calls it
closed and reports the class's own methods missing.

**Named by an external review** (`034-…-review-gpt-5.6-sol.md`) from the
shape of the fact alone, against a briefing whose own reproduction of the
same phenomenon was wrong.

**Measured.** Over 213 files of real gem source: 262 ancestor facts, **8
ambiguous**. Refusing those eight took `unknown-method` from **54 to 34**
findings — same harness, one variable, and the unfixed side reproduced
the independently recorded 54 exactly.

**What 0.2.6 did, and why it is not the fix.** An ambiguous ancestor
target becomes a nameless entry: the chain says it is incomplete instead
of containing a stranger. That is a refusal, not a resolution — the
correct module is still not found, and a legitimate `include Helpers` in
a workspace that happens to contain another `Helpers` now contributes
nothing.

**Direction:** record the lexical nesting with the reference — the
enclosing module path at the point the constant was written — and resolve
against it, which is what Ruby does. The review notes the alternative
worth weighing first: if an authoritative constant-reference
representation already exists elsewhere in the index, `AncestorFact`
should reference it rather than growing a second lexical model.
**Fixed in 0.2.12.** `AncestorFact` carries `nesting` — `Module.nesting`
at the point the constant was written, innermost first — and
`#ancestor_entries_for` asks `WorkspaceIndex#nested_type_name` before it
considers refusing. That is the same rule and the same reader
`024.103` uses for a bare constant in ordinary code, which is the point:
one lookup rule, two callers, rather than a second implementation.

So `include Helpers` inside `Rackish::Request` names
`Rackish::Request::Helpers` whatever other namespace has a `Helpers`,
and the module's members are back in completion, hover and go to
definition. The refusal stays for the case nesting genuinely cannot
decide — a bare name no enclosing frame declares, claimed by two
strangers — and `ambiguous_ancestor_spec.rb` now pins both directions.

`nesting` is defaulted, so a fact rebuilt from a cache written before
0.2.12 behaves exactly as it did.

Corpus, four gems, control `unresolved-constant` identical at 1,099:
`unknown-method` 84 → 84, **0 added and 0 removed** — these gems do not
contain the shape, so the number is a control and the evidence is the
examples run against the interpreter.

## 024.82 `Foo = Class.new(Bar)` is not a type the index knows

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. A class made by assignment resolves like one made
  with the keyword.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#visit_constant_write_node`),
`core/lib/ovallsp/workspace_index.rb` (`#type_candidates_locked`)

A class created by assignment rather than by the `class` keyword is
recorded as a constant, not as a class, so `#type_candidates_locked` —
which matches `kind` of `:class` or `:module` — never sees it. Nothing
resolves to it: not hover, not go-to-definition, not the member list.

`Concurrent::Error`, `Concurrent::ConfigurationError`,
`Concurrent::LifecycleError` and the rest of `concurrent/errors.rb` are
all written this way, as is `Rack::Utils::ParameterTypeError` (an alias
of `QueryParser::ParameterTypeError`). It is an ordinary Ruby idiom for
exception hierarchies, so a Rails application's `app/errors.rb` is
likely to be entirely invisible.

**Uncovered rather than caused by `024.78`'s fix.** Before it, resolution
matched on a name's last segment alone, so `Concurrent::Error` "resolved"
to whatever unrelated class named `Error` sorted first — an answer, and
the wrong one, which is worse than none by section 0.4. Nine such
constants over the 213-file corpus went from silently mis-resolved to
correctly reported as unresolvable. That is the honest state, not a
regression, and `unresolved-constant` does not run in the Server's
default `:safe` mode.

**Direction:** treat `CONST = Class.new(...)` / `Module.new` as a class
or module declaration at parse time, with the superclass taken from the
argument when it is a written constant. `CONST = SomeOther` is an alias
and is a different question — it names an existing type rather than
declaring one, and answering it needs the alias resolved first.

### Fixed in 0.2.15

`#visit_constant_write_node` records a `Class.new` / `Module.new` /
`Struct.new` / `Data.define` assignment as a **class**, with its
superclass from the first argument. The four receivers are the same
`CLASS_CREATING_BLOCK_RECEIVERS` the block form already reads, so the
two cannot disagree about what creates a class.

**Reproduced with a control**, which is what made it a defect rather
than a preference — the two forms given the same two calls:

```
class Keyworded < Base   ->  reports `definitely_absent`
Assigned = Class.new(Base) -> reports nothing at all
```

The engine declined rather than answering wrongly, so this was a missed
report and not a false one.

### The corpus taught the design, twice

**A form that generates members must not be enumerated.** Naming these
classes and stopping there added a *false* report immediately —
``HeredocData has no method named `common_whitespace=` `` on a
`Struct.new` accessor that plainly exists. Asked of Ruby:

```
Class.new(B).instance_methods(false)        # => []
Module.new.instance_methods(false)          # => []
Struct.new(:a, :b).instance_methods(false)  # => [:a, :a=, :b, :b=]
Data.define(:x).instance_methods(false)     # => [:x]
Class.new(B) { def own_m; end }             # => [:own_m]
```

So `Struct.new`, `Data.define` and **any** of them given a block open
the surface — `024.110`'s rule one level out, an enumeration carrying
its own completeness. A plain `Class.new(Base)` generates nothing and
stays enumerable, which keeps the half worth having.

**The name has to be qualified.** It was recorded as `::HeredocData`
where the keyword form records `::M::L::HeredocData`, so the open
surface — keyed on the qualified name — was never found. **A top-level
fixture cannot tell**: with no enclosing namespace the two are the same
string, and the spec passed. The corpus caught it, and there is a nested
example now.

**Measured**: 269 files of real gem source, both sides on corpus digest
`8143600c…` at different revisions — **13 `unresolved-constant` removed,
0 added**, `unknown-method` unchanged at 22.

*And one measurement error worth recording: the first baseline was
captured with `2>&1` while the after-run used `2>file`, so stderr
concatenated onto the last stdout line and `comm` reported a phantom
addition. `026`'s class exactly — both sides must be captured the same
way, not merely run the same way.*


## 024.84 A constant is typed as a class object whatever it holds

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.18
```

**Fixed in 0.2.18**, and the case that was supposed to be right was
wrong too: `KLASS = Widget` answered `ClassOf[KLASS]` — the constant's
own name rather than the class it holds — so even the intended behaviour
named the wrong thing.

Two halves. `ParserService` records what a constant was assigned, as
source text, in the `body_source` a method declaration has carried since
0.1.x; inference needs a workspace and the parser has none to ask.
`LocalInferencer#eval_constant` then answers in three steps: a class or
module by that name is a class object, which is what `ClassOf` exists
for; a constant whose assignment the workspace recorded takes that
value's type; anything else keeps the guess it always had, because an
unread gem's `SomeGem::Thing.new` depends on it.

**Measured over activesupport's 289 files, 2,655 constant reads:**

| | before | after |
|---|---|---|
| `ClassOf[...]` | 1,551 | 1,354 |
| a concrete type | **0** | **219** |
| unknown | 1,104 | 1,082 |

No constant lost an answer — `unknown` went *down*. And a corpus
diagnostics run over 997 files of activesupport, activerecord, actionpack
and railties came out **byte-identical**, control `unresolved-constant`
held at 2,987: nothing started or stopped being reported, so the gain is
in hover and completion rather than in the checks.

**Three attempts to reach the index, and each failed silently**, which is
worth recording because they all looked the same from outside — every
constant answering exactly as before:

- looked up by the qualified name whole, where the index keys a constant
  by owner plus bare name;
- destructured `[uri, declaration]` the wrong way round, and the
  `NoMethodError` was swallowed by `#eval_constant`'s `rescue` — which is
  there for `full_name` raising on a dynamic path and caught this
  instead;
- qualified through `#constant_type_name`, which resolves *type* names
  only, so `MAX` inside `class C` stayed `MAX` and missed.

A lookup that silently finds nothing is indistinguishable from a
constant the workspace has not seen, which is the answer the third step
gives on purpose. Only the spec's five literal cases told the three
apart.

Depth-bounded at three: `A = B` beside `B = A` is a program somebody can
write, and one level of indirection is what `KLASS = Widget` needs.

`024.82` is the same seam from the other side and stays open.

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#constant_path_type`)

`MAX_RETRIES = 3` then `r = MAX_RETRIES` hovers **`ClassOf[MAX_RETRIES]`**.
Every constant reads as a class object regardless of what was assigned —
`%w[]`, `{}.freeze`, `1.5`, `"str"` all the same. Measured through the
real server by a review round of 0.2.6, in both a plain and a Rails
workspace.

It is an assertion rather than a decline: hover tells the reader the
constant is a class. It propagates to anything assigned from it, and it
silences completion (`DEFAULT_NAME.` offers nothing) and the
undefined-method check at every use of a constant. Literal constants are
as ordinary as Ruby gets.

`ClassOf[X]` exists so that `Widget.new` knows `Widget` is a class
object, which is right for a constant that *names a class*. The rule
should follow the assigned value where the workspace can see it, and
`024.82` is the same seam from the other side.

**Re-triaged in 0.2.17** (`024.276`). A constant holding a String is typed as a class object, so completion offers nothing after `DEFAULT_NAME.` and the undefined-method check is silent at every use — a wrong type, asserted, about the most ordinary thing in Ruby. `ClassOf[X]` is right for a constant that *names* a class and wrong for one that holds a value; the rule should follow the assigned value where the workspace can see it. `024.82` is the same seam from the other side.

## 024.85 `self.` completes nothing

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.16. `self.` offers the members of whatever `self` is at
  that point, and a typo behind it is reported.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/semantic/prefix_completion.rb`,
`core/lib/ovallsp/local_inferencer.rb`

Completion after `self.` returns **0 items** — plain Ruby class or Rails
model, instance or class context alike. `me = self` hovers `""`, and
`self.nope` is not reported while the receiverless `nope` on the line
above is. Bare-prefix completion at the same position works, so this is
`self` specifically. Measured through the real server by a review round
of 0.2.6.

`self.` is mandatory for a setter and ubiquitous in `self.class` /
`self.name`, so the empty list is on a path everyone walks.

### Fixed in 0.2.16, and what `024.46` had got wrong

`024.46` is the 0.2.1 attempt: a `SelfNode` case reading the enclosing
class, reverted after it cost 55 new false diagnostics over Ruby's
standard library and removed none. Its own closing sentence names the
condition for trying again — "with `ClassOf` handled for singleton
bodies and `.class` resolving to the class object rather than to
`Class`" — and all three families it recorded turn out to be *the value
being wrong*, not the case existing:

- **`self.class.foo` reported on `Class`.** `#class` went through RBS,
  which answers `Class` — true, and useless. `Types.class_of` answers the
  receiver's class *object* now, and a `ClassOf` receiver is not
  something `Engine#reportable_branches` asserts about.
- **`def Const.method` bodies typed `self` as an instance**, because the
  push looked for a literal `self` receiver and nothing else.
  `#def_self_type` reads the constant.
- **`class << self` bodies did the same one `def` down.**
  `@in_singleton_class` decides it, because after this change a class
  body and a `class << self` body both hold a class object and the type
  alone cannot tell them apart.

**The root cause is one conflation.** `@self_type_stack` was documented
as "self", and held *an instance of the enclosing class* — right for an
instance method body, which is the reader it was written for, and wrong
for the class body it was pushed in. `#locate_in_def` compensated by
wrapping in `ClassOf` for the one shape it recognised. So the stack now
holds `self` at the point being visited, and `#locate_in_def` derives
the instance type through `Types.class_object_lookup` instead. Every
answer this entry is about falls out of that; the `SelfNode` case is one
line.

**The stack has four readers, not one**, and the class-body change is
visible in three of them. `#eval_type`'s new `SelfNode` case is what the
entry is about. `#eval_call`'s receiverless branch resolves a bare call
written in a class body as the singleton call Ruby makes it, instead of
looking it up on an instance. And `#capture_scope` is what `scope_at`
hands `Semantic::PrefixCompletion`, so receiverless completion in a
class body offers the singleton surface — a change no corpus can see,
because a corpus measures diagnostics and not completion, and one the
suite could not see either: both existing `self_type` examples are `def`
bodies. `local_inferencer_spec.rb` has a class-body one now.

Ruby was asked for each shape rather than reasoned about, and the
sessions are in the spec — including the two a reader gets wrong: a
`def` nested inside `class << self` is still a singleton method (its
`self` is the class), and a `def` nested inside `def self.x` is an
ordinary instance method (its `self` is an instance).

One thing fell out that nothing had asked about: `def self.x` and
`class << self` written at the *top level* of a file used to push
`ClassOf[nil]` — a class object over nothing, which no reader has a case
for and which `#to_s` renders as `ClassOf[]`. They push nil now, which is
what every reader already treats as "cannot say".

**Two things it deliberately does not answer.** The top level of a file:
`self` there is `main`, and a top-level `def` is a private method of
`Object` that this engine does not attribute to `Object` at all, so
offering `Object`'s members would be answering a question nobody asked.
And `class << obj` on anything that is not `self` — the parser's `Cref`
makes the same approximation on the declaration side, and this is the
place to record that neither models a singleton class of an object it
cannot name.

**`Types.class_of` is shared, not duplicated.** `MethodAnalyzer` is the
second evaluator and reads the same function, for the reason
`Types::LiteralTypes` exists: a rule either evaluator owns is a rule the
other drifts from, and the symptom both times was an expression typing
correctly on its own line and losing its type as a method's return.
`Types.class_object` is the wrap that goes with `class_object_lookup`'s
unwrap; `core/lib` held five `Generic.new(name: "ClassOf", …)` of its
own (three in `LocalInferencer`, one in `MethodAnalyzer`, one in
`Observation::TypeNormalizer`) and now holds exactly one, inside
`class_object` itself.

**Where the new reports can and cannot appear.** `self` in an instance
method body is a `Nominal`, so the unknown-method check runs on it —
that is the point, and `self.labell` beside a real `self.label` is
reported. `self` in a class body, a `def self.x` body or a
`class << self` body is a `ClassOf`, which `#reportable_branches`
answers `[]` for, so the check declines there exactly as it already
declines for a local holding a class object. The new population is
therefore `self.foo` written in instance method bodies, which is the
same receiver shape as `widget.foo` and has shipped for releases.

Twelve decisions inside the new methods are in
`core/spec/meta/pinned_mutations.yml`, because the hunk sweep cannot
reach the inside of a method it can only delete whole. It was six until
a review round listed the other six, which is the blind spot working
exactly as `CLAUDE.md` describes it: "N of M hunks pinned" is a floor,
and a method that arrives whole proves only that it exists.

### The measurement

Stated **before** either side ran, per `CLAUDE.md`: the control is
`unresolved-constant`, which must come out identical, because nothing
here touches the constant candidates the parser records or the two
lookups that check reads.

Ruby 3.4.10's own standard library, 976 files, one run at a time in the
foreground, both sides given the identical corpus
(`corpus-sha256` equal, file count equal, same working directory; the
two sides differ by `dirty-tracked-files` 16 against 20, because the
comparison is a dirty tree against itself with `core/lib` stashed rather
than two revisions). The baseline run was given
`--expect-control=unresolved-constant:7204` on the command line, so the
control was asserted by the script rather than read afterwards.

| side | `unresolved-constant` (control) | `unknown-method` |
|---|---|---|
| before | 7,204 | 231 |
| after | **7,204 — as expected** | 270 |

**Re-run after round 2, because the repair could have moved it.**
Scoping `@in_singleton_class` to a nested class changes the answer for
a class or module opened inside a `class << ...` body, and this corpus
contains six of those, in four files (`irb/debug.rb`,
`irb/easter-egg.rb`, `psych.rb`, `tempfile.rb`) — so "rare shape" was
not an argument for leaving the table alone. The after side was
measured again on the repaired tree, same corpus
(`corpus-sha256=2decf77…`, 976 files, the value the first pair printed),
control asserted on the command line again: **`unresolved-constant`
7,204, `unknown-method` 270 — both identical.** What that shows is the
totals, not the sets: the run's own stdout was lost to a concurrent
process writing the same path, which is `026`'s list happening again
and is why this paragraph says totals. The introduced-set analysis
below is the original pair's, and its settling example was re-checked
against the file and the interpreter — `openssl/hmac.rb:17`'s
`base64digest` calls a bare `digest`, `:6`'s `==` calls `self.digest`
twice, and `OpenSSL::HMAC.instance_method(:digest).source_location` is
`nil`.

*One line of `core/lib` changed after that run started and before this
entry was written: `#enclosing_instance`'s nil guard, deleted because
`Types.class_object_lookup` already hands a nil straight back. Checked
rather than assumed, over every shape the stack can hold — nil, Unknown,
nil-type, Nominal, `ClassOf[…]`, `Array[Unknown]` — the guarded and
unguarded forms return the same object for all six.*

**39 introduced, 0 removed**, and every one of the 39 is on five
receivers: `Addrinfo`, `OpenSSL::HMAC`, `OpenSSL::SSL::SSLContext`,
`OpenSSL::X509::Extension`, `Socket`.

**All 39 are `024.13`, not this change.** Each is a `self.<method>` where
the method is C-defined and the class is reopened in a `.rb` file, which
is the exact shape `024.13` records: the reopening makes the chain look
closed while the real method set lives somewhere this engine does not
index. Asked of the interpreter rather than assumed — all eighteen
distinct methods exist, and every one answers `nil` for
`source_location`, which is what "defined in C" looks like from Ruby.

The pair that settles it is ten lines apart in one file. In
`openssl/hmac.rb`, `def base64digest` calls a bare `digest` and **the
baseline already reports it**; `def ==` calls `self.digest` twice and the
baseline is silent. Same method, same class, same file. The product was
reporting one spelling of a call and not the other, and this change makes
the two agree — it does not create the wrong side of the disagreement,
which shipped already. The same corpus's baseline carries 57 reports
naming those five receivers before the change.

**They ship, and no release is scheduled to remove them.** The first
version of this paragraph said the 39 go when `024.13` is fixed,
"which is open, user-visible, and already carries `target: 0.2.16`".
That was read off the register and not off the tree, which is the
promotion rule's own failure mode. The commit this change set is built
on is *`024.13`'s fix declined*: it was attempted in 0.2.16, removed 11
false reports on a gem corpus and took four real typo reports with
them, and was reverted. `024.13`'s own body now says the real fix is
`024.R7`, a 0.3.0 roadmap item — so the yaml's `target: 0.2.16` was
stale the moment that commit landed, and this change set corrects it to
`0.3.0` rather than resting on it. **The 39 are visible to a user of
0.2.16 and stay until 0.3.0.**

**Argued on that, the trade still comes out this way, and here is the
alternative it was weighed against.** `engine.rb` has a house pattern
for exactly "receiver identified, assertion withheld" —
`#shadowed_declared_type?` and `#rooted_receiver_answered_elsewhere?`,
both declining inside `#receiver_type_for` with comments saying
resolution keeps answering and only the assertion is withheld, citing
`024.47` for why the rule belongs there rather than in resolution. A
third such guard, on a `self` receiver, would take the 39 out. It would
also take out the one report this entry exists to add: `self.labell`
beside a real `self.label` is the same `self` receiver, so the guard
cannot tell the capability from its cost. That is `024.13`'s own
attempt in miniature — a fix that buys false positives by spending true
ones — and this release already reverted one of those.

Two facts the size of the number should be read against. `024.46` was
reverted at 55 of these and this is 39, which is the same order; what
differs is that `024.46`'s were three distinct families of *wrong
value*, all three now gone, while these are one family with one cause
that is somebody else's entry. And the baseline already carries 57
reports naming those same five receivers, so the release is not opening
a category — it is making one spelling of a call agree with another,
ten lines apart in `openssl/hmac.rb`.

The direction `024.46` was reverted for is repaired: its first two
families are gone (a `ClassOf` receiver is not asserted about, and
`#class` answers a class object), and its third turns out never to have
been about `self`.

### Round 2: what an independent read found, and what changed

Method `diff`, on the change set above. Five defects and two notes; the
dispositions, because a round that repairs the last one is the loop
working and the next reader needs to know which is which.

- **The justification for shipping the 39 rested on a stale
  `target:`** — the largest of the five, and it is answered in "They
  ship, and no release is scheduled to remove them" above, together
  with the alternative `engine.rb`'s existing decline guards offer.
  `024.13`'s own `target:` moved to 0.3.0 in the same change.
- **`@in_singleton_class` outlived a nested class.** `#locate_in_namespace`
  restored `@lexical_nesting` and not the flag, so `class W; class << self;
  class Inner; def a` answered `ClassOf[Inner]` where Ruby has an `Inner`.
  Before this change set the flag's only reader made a stale `true`
  *decline*; `#def_self_type` made it assert. Scoped, and pinned by an
  example that fails with `ClassOf[Inner]` without it.
- **"Its only reader was `#locate_in_def`" was wrong** — the stack has
  four readers, and two more of them see the class-body change:
  `#eval_call`'s receiverless branch (a bare call in a class body
  resolves as the singleton call it is) and `#capture_scope`, which is
  what `scope_at` hands prefix completion. The second was pinned by
  nothing: both existing `self_type` examples are `def` bodies. There is
  a class-body one now, and the comment says four.
- **Six decisions inside the new methods were unpinned**, in the
  wholly-new-method blind spot the manifest exists for: `#def_self_type`'s
  absent `else`, `#enclosing_class_object`'s missing-enclosure decline,
  and four inside `Types.class_of`/`class_call?`. Each now has an example
  whose two candidate answers differ, and a manifest entry that inverts
  it. Six entries became twelve.
- **The manifest's own text was HTML-escaped.** `class &lt;&lt; self`
  where the example says `class << self`; `rspec -e` is a substring
  match, so it selected nothing and `spec/meta` could not have been
  green. Unescaped. Worth recording as its own class of mistake: the
  escaping was invisible in a rendered diff.
- **`MethodAnalyzer#eval_call` walked the receiver twice** whenever
  `Types.class_of` declined. The walk is carried into the ordinary
  branch now; the dispatch is unchanged.
- **One line was deleted rather than pinned.**
  `#enclosing_instance`'s nil guard could not change an answer:
  `class_object_lookup` hands a nil straight back, so the guard was
  unpinned *and* unpinnable. The rule says pin it or delete it, and
  deleting is what an unobservable line earns.
- **One note did not reproduce.** It said every `self.class.X` /
  `x.class.X` typo becomes unreportable because `s.class` used to be
  `Nominal("Class")` and is now a `ClassOf`. Driven against this tree
  with `core/lib` stashed and again with it applied, both sides answer
  the same: `w.class.bogus_thing`, `self.class.bogus_thing` and
  `s.class.bogus_thing` are reported by neither, because nothing is
  reported on a core-library receiver at all — which is `024.129`. The
  control, `W.bogus_thing`, is reported on both sides. So the change
  does not buy that false negative; it was already there.
- **`Types.class_call?`'s block guard was described wrongly.** The
  comment said `x.class { }` is "somebody's own method"; Ruby ignores
  the block and answers `String`. The guard is kept — declining gives up
  an answer rather than inventing one — but the comment now says what
  Ruby does, with the session.

Two more the round did not raise and the trigger-table walk did. The
three documents that state the suite's size were stale: this change set
adds 31 examples and none of them had been re-derived, which
`scripts/documented_counts.rb` fixes and `preflight` would have refused
the commit over. And `045`, the 0.3.0 scope file, named `024.85` as
0.3.0's first capability task and counted the public roadmap's 0.3.0
section as nine items; it is eight now, and the file carries a dated
amendment saying so rather than being rewritten.

### What shipping this cost, measured, and what it did not

Two review rounds. The second drove a corpus and found the shape that
decides the whole entry.

**Typing `self` also let the undefined-method check assert about it, and
that assertion is wrong.** A type read off the enclosing class body is an
**upper bound**: every instance reaching the body may be a subclass that
supplies the method. Measured over activesupport-8.1.3.1/lib, 289 files,
`corpus-sha256` identical on both sides and `unresolved-constant` held at
827 as the control:

    unknown-method  21 -> 30      9 introduced, 0 removed

and all nine are ``Numeric has no method named `*` `` on that gem's own
`self * KILOBYTE`. Taken from Ruby:

    $ ruby -e '
    p [Numeric.method_defined?(:*), Integer.method_defined?(:*)]
    '
    # => [false, true]
    # ruby 3.4.10

`*` lives on Integer and Float. Every instance that reaches
`Numeric#kilobytes` has it; a bare `Numeric` never exists.

**So the check declines on a written `self`**, recorded by the parser at
the call site because that is where the node is — looking it up again
downstream is the shape `049` counts eleven of. Re-measured after: the
same corpus, both directions of the diff **empty**. The entry's change
moves no diagnostic at all, and what it delivers is the completion and
hover it was filed for.

**What that costs, stated plainly.** `self.labell` is a typo and is not
reported. It was not reported before this entry either — `self` had no
type — so nothing regresses, but the round-one version of this change
did report it and two of its examples asserted so. Section 0 settles the
trade in favour of the missed report. The direction that would get both
is to ask the receiver's *subclasses* rather than its class, which is a
new query and not a thing to add inside a review round.

**And one wrong answer was removed rather than shipped.** `Types.class_of`
answered `ClassOf[Class]` for any class object, which is right for a class
and wrong for a module:

    $ ruby -e '
    module M; end
    class C; end
    p [M.class, C.class, Comparable.class]
    '
    # => [Module, Class, Module]
    # ruby 3.4.10

`Types` holds no index and cannot tell which it has, so that branch
declines. The session pasted with the original branch showed only
`class W; end; p W.class`, so the module case was never asked of the
interpreter — which is the expected-value rule failing in the narrow way
`CLAUDE.md` describes: the claim was checked, but not against the case
that breaks it.

## 024.86 An ivar assigned in another method has no type, except in the view

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/local_inferencer.rb`,
`core/lib/ovallsp/semantic/method_analyzer.rb`

`@article` assigned by a `before_action` and read in the action hovers
`Post` **in the ERB template** and `""` **in the controller itself**,
where completion after `@article.` offers 0 items against the view's 408.
The same shape reproduces in a plain class: `@post` set in one method and
read in another has no type. Measured through the real server by a review
round of 0.2.6.

So the machinery to walk a filter exists and is applied to views but not
to the file the developer is actually editing. `@user`/`@post` set in a
filter and used in the action is the canonical controller shape.

Separately and in the same family: diagnostics never act on an ivar
receiver even where hover and completion do know it — in the ERB,
`@article.no_such_method` is silent while `Post.no_such_class_method` two
lines below is reported.

**Re-triaged in 0.2.17** (`024.276`). Stays, and `045` says why: `@ivar` completion is one of 0.3.0's eight promises and this is what it rests on. The machinery to walk a filter exists and is applied to views but not to the file being edited, so the work is extending an inference path rather than correcting one. The second half its body names — diagnostics never acting on an ivar receiver even where hover and completion do — is a silence too.
### Fixed in 0.3.0: one missing seed, both halves

Reproduced first, in the plain class this entry names:

```
type of @thing read in another method: Unknown
type of @thing where it is assigned  : Nominal["Widget"]
```

**`#locate` gives each `def` a fresh environment.** Right for locals,
wrong for instance variables — so an ivar assigned in another method of
the same class was invisible to the one being edited. It works in an
ERB view for one reason only: a view has no `def` for the descent to
reset at, which is why this looked like Rails machinery that had not
been generalised and was in fact a seam one level down.

`#locate_in_def` now seeds from the enclosing class's other methods,
memoised per parse. **Where two methods assign one name types that
disagree, the answer is nothing** — picking one is a wrong answer at a
position where the code has no single one.

### And the same seed is the `@ivar` completion promise

The roadmap's "completion of `@ivar` names the moment you type the
sigil" was three things, not one, and each was found by running it:

- `#capture_scope` **dropped every `@`-prefixed name** on the way out,
  so the scope had no ivars to offer even once the environment held
  them. `Scope` carries them separately now — a different namespace,
  labelled differently, and merging would have made every existing
  reader of `locals` start answering `@name`.
- `#word_prefix_at_position` treated `@` as a boundary, so the prefix
  at the sigil was the empty string — which matches every name and
  therefore selects none of the ivars.
- `@` was in `BOUND_PREFIX_SIGILS`, the list of prefixes this engine
  answers nothing for. It is out; `$`, `:` and `@@` stay, because a
  global, a symbol and a class variable are still names nothing here
  tracks.

### One regression, caught by an existing example

`#infer_ivars_for_method_node` **replaces `@self_type_stack`
wholesale**, and the sibling walk runs in the middle of a descent that
owns it — so `def self.b` calling `a` started answering `Unknown`. The
stack, the step count and the budget are saved and restored around the
walk. Nothing new was written to find this; a Task 017 example did.

Rows `C15` and `H8`, both languages, three pinned mutations.

**The second half of this entry's body stays open** — diagnostics still
do not act on an ivar receiver even where hover and completion now do.
It is filed as its own entry rather than left inside a resolved one.


## 024.87 A relation stops being a relation after one hop

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  The type half is fixed in 0.2.15: a chain stays Relation[T]. The
  diagnostic half was recorded as unconfirmed until 0.3.0, which
  confirmed it: G19 measures the chain through the real server and the
  answer is that silence is correct, because a relation reaches
  ActiveRecord::AttributeMethods.
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/semantic/generic_rule_registry.rb`,
`core/lib/ovallsp/local_inferencer.rb`

`Post.where(published: true)` infers `Relation[Post]`;
`Post.where(published: true).where(user_id: 1)` infers nothing. So do
`.order`, `.limit`, `.includes`, `.count`, and a second scope. `#first`
and `#to_a` survive because they are modelled; the relation-returning
methods are not.

The cost is not only hover: `Post.published.where(user_id: 1).titel`
produced **no** diagnostic in a run where `post.titel` did — the
undefined-method check switches off at the second link of the most common
Rails expression there is. `@articles = Post.where(...).order(:id)` in a
controller hovers `""`.

Measured through the real server by a review round of 0.2.6.

**Not fixed in 0.2.6**: a review round is for fixing what the change set
got wrong, and this is a capability the round asked for. `024.79`'s
delegation already puts `Model.<name>` and `Relation#<name>` on one rule,
so the table is the one place to add them.

### The type half, fixed in 0.2.15

Reproduced exactly as written, with a registered model:

```
Post.all                       => Relation[Post]
Post.where(a: 1)               => Relation[Post]
Post.where(a: 1).where(b: 2)   => Unknown      <-
Post.where(a: 1).order(:id)    => Unknown      <-
Post.where(a: 1).limit(3)      => Unknown      <-
Post.where(a: 1).first         => Post | nil
```

Sixteen relation-returning methods now carry `return_template: :receiver`
on a `Relation` or `CollectionProxy`. **Probed against real Rails**, the
way the rules beside them were: ActiveRecord 8.1.3.1, in-memory sqlite3,
`rel = Post.where(title: "x")` — `where order limit offset includes joins
distinct group having preload eager_load references reorder readonly none
unscope` all answered `Post::ActiveRecord_Relation`.

**`select` is deliberately absent.** On a Relation it returns a Relation
without a block and an Array with one, and the `ENUMERABLE_LIKE` rule
already covers the block form; adding a relation rule would make the
answer depend on which matched first.

**The distinguishing example is that a terminal method must not become a
relation** — `.first` stays `Post | nil`, `.to_a` stays `Array[Post]` —
because "everything on a Relation is a Relation" would pass every other
example and be wrong exactly where it matters.

Measured over 269 files of real gem source, both sides on corpus digest
`8143600c…` at different revisions: byte-identical.

### The diagnostic half is not confirmed, and the entry stays open

The sharper complaint is that `Post.published.where(user_id: 1).titel`
produced no report where `post.titel` did. **That was not reproduced.**
In a unit fixture the ActiveRecord class-method API is not known to the
diagnostic path, so the *first* hop already reports ``Post has no method
named `where` `` — the fixture cannot tell the second link from the
first, and an example built on it would assert nothing.

What is fixed is the type the diagnostic consumes: a chain that ended in
`Unknown` now ends in `Relation[Post]`, and a check that declines on
`Unknown` no longer has cause to. Confirming the report itself needs the
e2e path with a real Agent. Retargeted to 0.2.16 for that.
### Fixed in 0.3.0, and the unconfirmed half was two different things

The entry's note says the type half was fixed in 0.2.15 and the
diagnostic half is unconfirmed. Measured through the real server, both
are now confirmed and they are not the same answer.

**The members were the missing half, not the type.** Hover on
`Post.where(x: 1).order(:id).` says `Relation[Post]`; completion at the
same caret answered **nothing**. `#receiver_members` handed a `Generic`
to a walk that asks a `Nominal`, so the type survived the chain and its
members had nowhere to come from. **228 items** come back now.

Three things had to move together, and each was found by measuring:

- `#receiver_members` unwraps a `Generic` — but **not `ClassOf`**,
  which is a Generic too and is the one that must stay whole. Routing
  through `#each_nominal`, which unwraps both, asked every class object
  for its *instance* members and failed 21 examples.
- `HierarchyIndex#gem_ancestry` refused a receiver that is itself a gem
  class, because `kind_of` reads the workspace index. So
  `ActiveRecord::Relation`'s own chain was one link.
- `GemIndex` resolves a **unique** simple name, because the type model
  says `Relation[Post]` and the running application says
  `ActiveRecord::Relation`. Only where exactly one class claims the
  simple name: two gems with a `Client` are two classes.

**The diagnostic half is a silence, and it is correct.** A relation is
an Active Record object and its chain reaches
`ActiveRecord::AttributeMethods`, which defines `method_missing` — so
`Post.where(x: 1).order(:id).titel` is *not* reported, and reporting it
would be a wrong answer. `G19` asserts the silence rather than leaving
the entry's "unconfirmed" standing.

### And one regression the corpus caught

Giving a gem class its singleton tail turned `Foo.new` into 37 false
reports over activerecord — `Class#new` is on the singleton chain, and
the gem index reports `singleton_methods(false)`. The tail is now taken
from the workspace's answer first and the index's only for a name the
index knows. Back to **0 introduced, 13 removed**, control
`unresolved-constant` identical at 1,609.


## 024.89 Signature help strips the parameter kinds and never advances

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`#signatures_of`),
`core/lib/ovallsp/server.rb` (the `textDocument/signatureHelp` handler)

`def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)` presents as
`simple(a, b, rest, key, opt, others, blk)` — every default, `*`, `:`,
`**` and `&` removed, so the popup tells the reader `key` is the fourth
positional argument when it is a required keyword. Hover shows the same
stripped label.

And the response carries no `activeParameter` (nor `activeSignature`) at
any position, so the client has nothing to advance the highlight with and
the popup stays on parameter 0 for the whole call. Measured through the
real server by a review round of 0.2.6.

### Two halves, and only one of them was a defect

**The second half is not a defect and should never have been filed as
one.** `activeParameter` is a capability this product has not claimed.
`Server#method_signature_help` says so at the site — built during 0.2.1's
review loop and deferred with the row that names it — and `ROADMAP.md`
carries it under **0.4.0**: "Signature help highlights the argument the
cursor is in". One heading held a live defect and a roadmap item under
one `kind: defect` and one `target: 0.2.15`, which are the two kinds this
register's own legend says are triaged differently and by different
people. The same shape as `024.219`. It stays on the roadmap; nothing
here is owed for it.

### The first half, fixed in 0.2.15

`#signature_label` joined `parameters.map(&:name)`. Everything it needed
was already recorded — asked of both, for one `def`:

    $ ruby -e 'def simple(a, b = 2, *rest, key:, opt: 1, **others, &blk); end
               p method(:simple).parameters'
    # => [[:req, :a], [:opt, :b], [:rest, :rest], [:keyreq, :key],
    #     [:key, :opt], [:keyrest, :others], [:block, :blk]]
    # ruby 3.4.10

    the engine's own list for the same def:
      "a" :required  nil / "b" :optional "2" / "rest" :rest nil /
      "key" :keyword nil / "opt" :keyword_optional "1" /
      "others" :keyrest nil / "blk" :block nil

Seven kinds and both defaults, recorded faithfully and thrown away by the
rendering. `Index::Parameter#label` now spells each one the way the
source does, and the label reads
`simple(a, b = 2, *rest, key:, opt: 1, **others, &blk)`.

It lives on the value because two readers need it — the label and the
per-parameter array, which is what `activeParameter` would one day point
into, so they must be cut the same way. A third reader,
`#completion_snippet`, keeps the bare name deliberately: a snippet's tab
stops want a name, not a spelling.

**Deliberately not shared with `#rbs_signature_parts`.** That renders RBS
*types* (`?Integer`, `name:`); this renders source *names and defaults*.
Two renderings of two different things, and merging them because they
look alike is the move `024.47` had to roll back.

**Hover is fixed by the same change and pinned as such** — it reads
`signatures_of(...).first`. Reverting the one-word change fails the
signature-help example and the hover example together, which is what
makes "one cause, two symptoms" a measurement rather than a claim.

### A latent defect the rendering exposed

`def half(a = )` — an ordinary buffer mid-edit — parses to a
`Prism::MissingNode` whose `slice` is the `=` itself, so `default_source`
had been recorded as `"="` since Task 016. Nothing rendered it, so
nothing saw it; the new label would have read `a = =`.

Fixed where the value is produced: a `MissingNode` records no default,
and the label says `a = ...` rather than inventing one. Pinned on both
halves — the recorded value *and* what it renders as — because asserting
only the label would pass on a parser that still recorded `"="` and a
renderer that happened to hide it.

*The example for this was written against the server first and moved.
`def half(a = )` does not index far enough for signature help to answer
at all, so the server-level example asserted something that position
cannot show — an assertion that fails for the wrong reason is no better
than one that cannot fail.*

## 024.90 Smaller answers a review round measured

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Split rather than fixed. The nine defects it held are now nine entries,
  each with its own Area and its own user-visible half; this number
  survives only so the citations to it resolve.
target: 0.2.14
released-in: 0.2.14
```

**Area:** superseded — see `024.127` through `024.135`

**Split in 0.2.14.** This held **nine unrelated defects under one
number**, with one `user-visible: yes` and one `KNOWN_LIMITATIONS`
anchor. That anchor documents **seven** of them — so two live defects,
`core/spec/e2e/lsp_client.rb#wait_until_ready`'s hang and
`observation/runner.rb`'s `Marshal.load`, were documented **nowhere**
while the guard read green.

That is the failure mode of a grab-bag entry: the guard checks that the
*number* is cited, and a number cited once covers everything filed under
it. Nine numbers cannot hide behind one anchor.

| now | was |
|---|---|
| `024.127` | hover answers `""` where LSP expects `null` |
| `024.128` | integer arithmetic answers a four-way union |
| `024.129` | no undefined-method report on a core-library receiver |
| `024.130` | a hover label drops the namespace |
| `024.131` | `b = nil; b ||= "x"` hovers nothing |
| `024.132` | a scope in a concern's `included do` has no type |
| `024.133` | a positional argument to a keyword-only method |
| `024.134` | `wait_until_ready` hangs on a non-Rails workspace |
| `024.135` | `Marshal.load` in `Observation::Runner` |

The legend gained the rule this cost: **one entry states one defect, with
one Area and one reproduction.** Not machine-checked — a rule counting
bullets would guess at intent — and `046` records why.

## 024.91 The undefined-method check reports on ordinary Ruby it cannot read — split, and re-measured

```yaml
status: done
kind: defect
user-visible: no
user-visible-note: >
  Split into 024.237, 024.238 and 024.239, which carry the user-visible
  halves. This entry is now the measurement that decided the split, and
  the record that two of its four shapes had stopped happening some
  releases before it was read.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/parser_service.rb`,
`core/lib/ovallsp/diagnostics/engine.rb`

Four shapes an attack round found over 177 files of rspec-core / i18n /
psych / reline, recorded together as **41 reports**, about one per four
files.

**Driven again in 0.2.16 before splitting, per the promotion rule, and
the entry had gone stale in both directions.** The same corpus at the
same file count now gives **18**, and the shape the entry says is
"roughly 19 of the 41" — `Const = Struct.new(...)` reopened — produces
nothing at all. What the entry describes has not been true for several
releases.

More usefully, each shape was re-run in a fixture **with a typo written
into the same body as a control**, which the original measurement did
not have. That control is what separates two very different reasons a
report can be gone:

| shape | the entry's report | now | typo control in the same body |
|---|---|---|---|
| A `Struct.new` const, then `class Const` | reported | silent | **also silent** |
| A2 `Data.define` | reported | silent | **also silent** |
| B `define_method`/`attr_reader` in `Class.new do` | reported | silent | **also silent** |
| C `alias` to an included module's method | reported | **reports** | reports |
| D `trap`, `URI` on the user's own class | reported | **reports** | reports |
| E literal `define_method` in a loop block | reported | silent | **also silent** |

A, A2, B and E are silent because the check declines on those bodies
*wholesale* — it has not learned the members, it has stopped answering
there, and a real typo goes with it. That is the right direction for
this check's policy and it is not the same thing as being fixed, so
recording them as fixed would have been a false claim. They are
`024.237`.

C and D survive with their edge intact, and are `024.238` and `024.239`.

The entry's closing correction — that a **literal** name inside a block
reports too, contradicting a `KNOWN_LIMITATIONS` bullet — is shape E,
and is silent now for the same wholesale reason.

## 024.92 A plugin chooses how much memory the parent allocates

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Reachable only by a client that sends `pluginManifests`, and the
  shipped extension sends none. Recorded as a defect because "one broken
  plugin never takes Core down" is the guarantee the fork exists for.
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/plugins/loader.rb` (`#read_isolated_result`)

`Timeout.timeout(5) { reader.read }` bounds wall-clock, not bytes, and
`IO#read` returns only at EOF. Measured by an attack round: a plugin
registering 300,000 declarations took the parent from 44 MB to 380 MB in
1.22s; a plugin whose one method name was 50 MB of `"z"` took it to
144 MB in 0.14s. Five seconds of pipe throughput is multiple GB.

Fixed by reading one byte past a 16 MB cap and refusing anything larger,
so the excess is never allocated.

## 024.93 `Process.kill(sig, 0)` signals the caller's own process group

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing in the product can produce a pid of 0 -- fork(2) either yields
  >= 1 or raises. It is recorded because a *spec* produced one and killed
  the test process, which is the same failure mode as the fabricated path
  that deleted `/Applications`.
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/child_process.rb` (`#signal`, `#reap`)

An example written while capping the plugin payload passed `0` as a
plausible-looking fake pid. `kill_child(0)` called
`Process.kill("KILL", 0)`, which signals **every process in the caller's
own process group** — so `bundle exec rspec` killed itself, with no
output and an exit code that read like an ordinary failure.

`ChildProcess`' own comment already argued that a pid of 0 "never reaches
here" because fork returns >= 1. True of production, and it is exactly
the reasoning the `/Applications` incident disproved: every call site was
individually right, and containment was an emergent property of all of
them being right at once, which is not a property. `#signal` and `#reap`
now refuse a zero target. A negative one stays allowed, because
`#signal_group` names a group deliberately.

## 024.94 A Windows workspace could have its own `ruby.exe` run before it is trusted

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Windows is `unsupported` in `SUPPORT_MATRIX.md` and the published VSIX
  carries a darwin-arm64 payload only, so no shipped configuration
  reaches it. Recorded and fixed anyway: executing a binary an untrusted
  workspace supplied is the class 0.2.4 was about, and the axis that
  covers it does not depend on which platforms are supported.
target: 0.2.6
released-in: 0.2.6
```

**Area:** `vscode/src/platformCompatibility.ts`,
`vscode/src/rubyResolver.ts` (`#pickExecutable`'s fallback)

`resolveRuby` falls back to the bare string `'ruby'` when it finds no
version manager, and `queryRubyIdentity` / `queryRubyConfigPaths` /
`probeRuntimeDependencies` pass `cwd: folder.uri.fsPath` — deliberately,
so a shim reports the version that folder pins. libuv's Windows path
search checks the **cwd before PATH**, so on a machine with no
discoverable Ruby, a workspace containing `ruby.exe` would be executed
during the compatibility probe, which runs before trust is granted.
POSIX is unaffected: `execvp` does not search the cwd.

Found by an attack round. Fixed by `spawnCwd`, which keeps the cwd for an
absolute interpreter path and drops it for a bare or relative one — the
two cases separate cleanly, because the bare fallback means no version
manager was found and so there is no shim for the cwd to influence.
Applied on every platform rather than behind a `win32` check: a rule that
only runs where nobody tests it is not a rule.

## 024.95 A deep enough file ended the session, and three rescues did not catch it

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#summarize`),
`core/lib/ovallsp/server.rb`, `core/lib/ovallsp/background_tasks.rb`

`SystemStackError` is an `Exception`, not a `StandardError`, so the
visitor's recursion escaped every rescue between itself and `Server#run`.
Measured by an attack round: `x` followed by 5,000 `.succ` calls, opened
over `didOpen`, exits the process **rc=1** with a raw backtrace on
stderr; the `documentSymbol` sent immediately after is never answered.

Three more places, same cause: the cold-index thread died with no log
line at all — silently skipping the deleted-file sweep, the
reference-index bump and the workspace diagnostics pass for the rest of
the session, and printing through Ruby's own `report_on_exception`, which
**bypasses `Logger`'s `Redactor`** and so the `$HOME`→`~` substitution
`SECURITY_CHECKLIST` §3 claims for that channel. `BackgroundTasks#shutdown`,
documented "never raises", raised — `Thread#join` re-raises what killed
the thread — leaving the threads after it in the batch unjoined. And
`scripts/corpus_diagnostics.rb` aborts a whole measurement on one such
file.

Thresholds measured: a `.succ` chain fails at depth 2104, nested arrays
at 1923, nested hashes at 1147, nested `if` at 1145. **0 of 4582 `.rb`
files** across every installed gem and the Ruby 3.4 stdlib reach any of
them, so this is generated or hostile input — and a file arrives from
anywhere.

Fixed where the recursion is rather than at each caller, per CLAUDE.md's
containment rule: `ParserService#summarize` answers an empty reading of
the file. Empty rather than partial, because a half-finished walk holds
the declarations from the top of the file and none from the bottom, and
the undefined-method check would assert absence on the strength of it.

## 024.96 Every malformed LSP frame ended the process

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.6
released-in: 0.2.6
```

**Area:** `core/lib/ovallsp/io/framed_reader.rb`,
`core/lib/ovallsp/server.rb` (`#run`)

`Server#run` rescued only `FramedReader::EOF`. Ten inputs measured by an
attack round, each after a valid `initialize` and followed by a valid
`shutdown`: `Content-Length: 0`, `-5`, `abc`, `5.5`, a missing header, a
malformed body, a truncated frame. All exited **rc=1** with an uncaught
`JSON::ParserError`, `ArgumentError`, `NoMethodError` or `ProtocolError`;
none reached `shutdown`.

`Integer()` also accepted `0x10` as 16 and `1_0` as 10, neither of which
the LSP framing grammar allows, and `-5` reached `byteslice(0, -5)`.

Only a client can send these, so a hostile workspace cannot reach it —
but a reconnect, a proxy, or one stray byte on stdin ended the session,
and what the user saw was a backtrace rather than a diagnosable message.

Fixed: the reader raises `ProtocolError` for everything that is not a
well-formed frame and `EOF` only for a stream that ended, the length must
match `\A\d+\z`, and `run` logs a malformed message and reads the next
one.

## 024.97 A later pass at the same version overwrites a corrected answer

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/server.rb` (`#publish_findings`)

0.2.7's funnel orders publishes by version and lets the *same* version
through twice, deliberately: a later pass usually knows more, not less —
the Agent answering, routes arriving — and refusing a repeat would switch
those off. So two answers about one version of one file are ordered only
by arrival, and the slower one wins.

The user-visible instance is the one `024.56` names alongside its own:
pause on a file large enough to take seconds to analyse, and the
`*_path` reports made *before* routes arrived can land after the
corrected ones. Measured across 0.2.7 by a review round: `main` and HEAD
both publish `[[4, 0], [4, 1]]` — identical, the stale report last.

**Recorded here because 0.2.7 briefly claimed to have fixed it.** The
`KNOWN_LIMITATIONS` paragraph for `024.56` was rewritten to say the
release "stops a slower analysis writing its older answers back over
newer ones", which is not true and was not measured; a review round
caught it. The sentence the rewrite deleted — "the next edit clears
that" — was the correct one and is restored.

**Direction:** the version is the wrong key for this. What distinguishes
the two answers is what was *known* when each was computed — routes
loaded or not, the Agent ready or not — which the engine already tracks
as `generation` on every `Finding`. Ordering a repeat of the same
document version by generation would let the corrected answer win without
refusing the repeats that make correction possible. Needs its own change
set and its own measurement: it can silence a publish, which is the
direction that does not announce itself.

## 024.98 A workspace opened through a symlink shows every file twice, and one copy can never be cleared

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.8
released-in: 0.2.8
```

**Area:** `core/lib/ovallsp/server.rb` (`workspace_root:` default),
`vscode/src/extension.ts` (the `cwd` it spawns Core with)

Core never reads `rootUri` — `grep -rn "rootUri" core/lib` finds nothing
— and defaults `workspace_root:` to `Dir.pwd`. The extension spawns Core
with `cwd: folder.uri.fsPath`, and a child started with its cwd on a
symlink reports the **resolved** path from `Dir.pwd`. So the workspace
pass builds every uri under the real path while every editor-driven
publish uses the symlink path.

Driven end to end by 0.2.7's `drive` round, workspace root
`ws30_link → ws30_real`:

| step | the real-path uri | the symlink uri |
|---|---|---|
| cold start | two findings | nothing |
| opened via the symlink, both errors fixed, saved | **the same two findings** | clean |
| tab closed | **the same two findings** | clean |

Nothing publishes to the real-path uri again, so nothing can clear it.
The developer sees the file listed twice, one copy showing errors on
lines that no longer exist, for the whole session — and go-to-definition
returns the real path, so following it opens a second tab of the same
file under a different path.

A symlinked checkout is ordinary: `/tmp` on macOS, git worktrees,
dotfile setups, `~/src` pointing at a volume.

**Direction:** one function turns a path or uri into the workspace's
canonical uri and nothing else constructs one. Which root wins is a
deliberate decision — `rootUri` is what the user sees and what every
editor-driven message carries, so Core should read it rather than
inferring the root from its own cwd.

### Fixed in 0.2.8, and the suite had been encoding the defect

Core reads `rootUri` from `initialize` and takes it as the workspace
root; a client that sends none keeps this process's cwd, which is what a
direct stdio session relies on. It runs from the first message, before
anything has been indexed under the other root.

**One E2E example broke, and how it broke is the finding from the other
side.** `capabilities_spec.rb`'s G17 built its expected uri with
`File.realpath(path)` and had passed for four releases — because the
workspace sits under a symlinked `/tmp` on macOS, Core resolved its root
through `Dir.pwd`, and the example had to resolve the path to find the
diagnostics. It now agrees with the client's own uri and needs no
`realpath` at all. That call was the single one in the whole E2E suite,
and nobody read it as a symptom.

## 024.99 Completion offers members that cannot be called from where it was asked

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`#members_of`),
`core/lib/ovallsp/semantic/method_resolver.rb`

Measured by 0.2.7's `drive` round by asking the *running application*
`respond_to?` for every label returned, rather than by inspection:

| receiver | labels | not callable |
|---|---|---|
| `Post.` (Rails, Agent connected) | 816 | **91** — `abort`, `exec`, `fork`, `exit!`, `eval`, `append_features`, `` ` `` |
| `p.` where `p = Post.new` | 338 | 0 |
| a user's own class, plain Ruby | 121 | **69 (57%)**, `initialize` among them |
| `Circle.` (plain Ruby) | 196 | 86 |
| `"text".` (plain Ruby) | 251 | 69 |

Every one of those raises `NoMethodError` if accepted. The instance path
with a live Agent is clean, so this is the static and singleton paths.

`docs/EXTENSION_CAPABILITIES.md` heads this section "the single most-used
feature" and marks C1/C5 PASS. Section 0.3 sends completion *ordering* to
2.x; this is not ordering.

**Direction:** the member query answers visibility along with existence,
and completion filters on where it was asked from — an explicit receiver
sees public methods only. Same query as `024.78`'s and `024.88`'s
subject; see the availability item in `037`.

### 0.2.15 reassessment: this is not a small fix

An implementation attempt classified it `small` and produced a change
touching **seven files under `core/lib`** — `query_service.rb`,
`method_resolver.rb`, `prefix_completion.rb`, `call_site_visibility.rb`,
`signatures/environment.rb`, `parser_service.rb` and `server.rb` — plus
two specs and a mutation entry.

That is a cross-cutting change to how visibility reaches the completion
path, not a bounded one, and calling it small is how a fix gets made in
seven places instead of one. **Reclassified `large`** and left for a
release that can carry it.

*The rule it needs is already known and stated in `024.151`'s Direction:
the answer belongs where the value is produced, not at each reader. What
is not yet decided is which layer that is here — `MethodResolver`
already owns "can this be called from there" for diagnostics, and the
question is whether completion should be asking it rather than
assembling its own answer.*

**Re-triaged in 0.2.17** (`024.276`). Reclassified `large` in its own body, for a reason that has nothing to do with gems: the rule belongs where the value is produced, and which layer that is here is undecided — `MethodResolver` already owns "can this be called from there" for diagnostics, and whether completion should ask it rather than assemble its own answer is the open question. Not re-driven since the reclassification.

**Fixed in 0.3.0.** Completion after a dot offers no private method.
RBS already carried the answer -- `accessibility` is `:private` for
`fork`, `exec`, `abort`, `exit!`, `eval`, `initialize` and `puts` on
`Object` -- and `Signatures::Environment#member_names` was dropping it.

**The filter is opt-in, and that is the load-bearing half.** Making it
the default in `QueryService#members_of` silently changed every caller
that omits a context, and dropped `puts` from the bare prefix at the
top level of every file -- which is the one place Ruby lets a private
method be called. `Server#member_completion_items` asks for it; the
receiverless groups do not.

What this does not cover is a *workspace* method whose recorded
visibility is wrong, which is `024.221`.

## 024.101 Analysis runs per keystroke, so the answers fall behind the cursor and every wrong one is published

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.10
released-in: 0.2.10
```

**Area:** `core/lib/ovallsp/server.rb` (`#handle_did_change`),
`024.45`, `024.57`

Nothing coalesces changes and nothing cancels a superseded analysis: one
full re-analysis and one publish per `didChange`. Measured by 0.2.7's
`drive` round through the real server:

- per keystroke, median of 5: **53 ms at 1006 lines, 155 ms at 2006,
  368 ms at 4006**;
- 22 keystrokes 60 ms apart on a 4006-line file, typing a method name
  that **does exist**: 22 publishes arrive, each reporting a prefix as an
  unknown method, and the panel is clean **6.55 s after the developer
  stopped typing**;
- requests queue behind the backlog: hover after 1 queued keystroke
  365 ms, after 10 keystrokes **3394 ms**, linear. On a 20 000-line file
  one hover took **25.44 s**, and a second, small file opened in the same
  window got no diagnostics for those 25 s either.

At 2000 lines the per-keystroke cost already exceeds a typing interval,
so the backlog grows rather than drains.

`024.45` recorded the per-file cost and `024.57` the rolled-back
debounce. What is new here is the queueing measurement and the count of
wrong intermediate publishes — which is also the argument the rollback
was missing, since a debounce trades latency for correctness only if the
intermediate answers were wrong, and 22 of 22 were.

**Direction:** analyse the state the buffer settled into rather than each
event on the way to it. `029`'s M-3 was named as the precondition the
rolled-back attempt lacked; it exists as of 0.2.7.

## 024.102 Eight classes, and the logic each one could not have happened under

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Not a defect a user meets. It is the index of the ones they do, sorted
  by how each came about rather than by where it surfaced, so a reader
  looking at any single entry below can see which class it belongs to and
  what is being built to make that class impossible.
target: 0.2.16
released-in: 0.2.16
```

**Area:** the register as a whole; `037`'s "Preventing the classes"
section carries the same table with sizes and reasoning

**Superseded by [`042-second-enumeration.md`](042-second-enumeration.md).**
The stocktake below is why. The second enumeration assigns every open
defect by *where the wrong decision is made* rather than by what the
symptom looks like -- the specific move that let C1 claim two entries
decided in `HierarchyIndex` and in a Prism node-class test -- and it
holds a class open until its entries stop reproducing, measured, rather
than until its mechanism ships.

## The rule working, 0.2.13: a class shed five entries before it built anything

`042`'s first rule is that an entry belongs to a class only if the wrong
value is produced *inside that class's mechanism*. 0.2.13 applied it to
D2, which claimed eleven entries, and **five of them are somewhere else**:
`024.18` and `024.22` need a different source of knowledge entirely (the
Runtime Agent, which is their own Direction), `024.27` and `024.28` are
`selectionRange`/`name_location` on a generated declaration, and `024.77`
is a receiver's type after a relation hop, which is D3's.

That is the difference from `024.102`, stated as plainly as it can be:
**C1 discovered its two miscategorised entries by building the mechanism
and finding they had not moved.** D2 discovered its five by asking where
the value is produced, before spending the release on them. The cost of
the first was a release; the cost of the second was an afternoon's
reading.

## The stocktake, 0.2.11: the mechanisms are built and the instances are not gone

Asked for by the maintainer, after this entry had been read for two
releases as though building a class's preventing logic discharged the
entries under it. It does not, and the difference is measurable. Twenty
entries, each reproduction re-run against the tree at `0449007` by three
independent audits, every claim about Ruby taken from the interpreter.

| class | mechanism | entries fixed |
|---|---|---|
| C1 | shipped 0.2.8 | **0 of 5** |
| C2 | shipped 0.2.9 | **1 of 9** (`024.35`), plus `024.83` reduced 74 → 20 |
| C3 | shipped 0.2.10 | **0 of 3** (`024.19` narrowed, by rules that are not C3) |
| C4 | shipped 0.2.7 | 1 of 1 |
| C5 | shipped 0.2.7 | instances gone; **the instrument works and found 3 unpinned hunks on this branch** |
| C6 | shipped 0.2.7 | — |
| C8 | shipped 0.2.8 | 1 of 1 |
| C9 | shipped 0.2.10 | `024.57`'s behaviour **gone**; `024.45` reproduces |

**Four of the five entries under C1 were never within its reach.** Two
are decided in `HierarchyIndex` and in a Prism node-class test, not from
parser bookkeeping; two need a block *receiver*, and `Cref#in_block` is a
counter. The fifth is the informative one: `Cref#defines_surface?`
answers exactly the question `024.34` needs, and `record_attribute_methods`
asks `declares_singleton?` instead. `defines_surface?` is read at **one**
site in the parser; `declares_singleton?` at **seven**. So `cref.rb`'s
claim — "There is no subset to read wrongly because there is no subset" —
is false. Collecting six flags into one value collected the *storage*,
not the *question*.

**C2's charter had two halves and one was never built.** "One query per
position answering present / absent / unknown" shipped; "read by all four
features" did not. `members_of`, `signatures_of` and hover never call
`availability` — only `Engine#closed_nominal?` does. That accounts for
`024.88`, `024.99` and half of `024.100` directly. Two more failures:
`unenumerable_reason` enumerates *ancestors*, while every surviving false
positive in `024.13`, `024.83` and `024.91` is a failure to enumerate a
class's **own members**; and `MemberAvailability` has no visibility field
although `024.99`'s stated direction requires one.

`024.100`'s root cause was located during the audit and is the sharpest
statement of the gap: hover and completion pass
`initial_env: ivars_for_view(uri)`; the diagnostics path passes only a
set of *names*, and `initial_env` appears nowhere in `engine.rb`. **One
query per position was built as one query about a *type*, not about a
*position*.**

**What the stocktake does not say** is that the mechanisms were a
mistake. C5's instrument found three unpinned lines on the branch it was
run against, one of them a collaborator wired into `Server#initialize`
that no test touched — the same failure `040` records for `024.103`, and
found by a machine rather than a reviewer. C9's rolled-back debounce
findings are structurally impossible now. C2 turned 74 false reports into
20 on one corpus. What it says is that **a class's mechanism and a
class's entries are two different pieces of work**, and this register
recorded the first as though it were both.

Every entry's `status` is unchanged by the stocktake, because every
verdict agreed with what the register already said. What changes is
`036`, which described 0.2.8 and 0.2.10 as *carrying* these entries.

Asked for by the maintainer after 0.2.7's second review round: enumerate
what is open, decide for each the logic under which it could not have
happened, build those, and only then go on reviewing. The instruction
behind it is that fixing instances one at a time had stopped paying — six
entries in this register share one cause, and each 0.2.6 fix was one more
caller learning one more question.

| | class | preventing logic | entries |
|---|---|---|---|
| C1 | a declaration's owner and kind are decided by whichever subset of the parser's six parallel mutable stacks each recorder's author remembered | one immutable cref, pushed in one place, taken as an argument by every recorder | `024.26`, `024.31`, `024.32`, `024.33`, `024.34` |
| C2 | a check asserts absence from an enumeration it could not finish; the four features answer from different paths and disagree at one position | one query per position: present / absent / unknown, plus visibility, with `unknown` produced by whatever failed to enumerate | `024.13`, `024.18`, `024.35`, `024.78`, `024.82`, `024.83`, `024.88`, `024.91`, `024.99`, `024.100` |
| C3 | an answer is computed about one thing and attributed to another | the publish path takes the document object, compared by identity | `024.19`, `024.44`, `024.97` |
| C4 | a number in a document describing the tree is typed rather than derived | marked claims, recomputed by a spec | `024.67` |
| C5 | an assertion that cannot fail, through the setup | a setup that must take effect asserts it did | `024.30` |
| C6 | a fact about something outside this tree, asserted from memory | one document, each row naming the line that shows it | — |
| C8 | a uri is used as an identity without being canonicalised | one function makes the canonical uri; read `rootUri` | `024.98` |
| C9 | analysis runs per event rather than per settled state | coalesce per uri, cancel a superseded analysis | `024.45`, `024.57`, `024.101` |

C4, C5 and C6 shipped in 0.2.7 — the three that protect measurement
itself, which is the right order when every class above is to be judged
by a before-and-after and three of this project's own numbers have failed
re-derivation. C1 and C8 are 0.2.8; C2, C3 and C9 are 0.2.9.

**What this entry is not.** It is not permission to restructure. `024.15`
(0.1.12: 47 files, four rounds, zero net progress, rolled back whole) and
`024.47` (0.2.1: a rule centralised into resolution, rolled back) are
what that costs here, and C2 in particular is the shape both had. Each
class ships with its own corpus measurement, and one that does not move a
measurement is one to abandon rather than defend.

### Closed in 0.2.16 — the counts, and one credit withdrawn

`042` supersedes the classification; what was left open here was the
record, and a stocktake is exactly the kind of document whose numbers go
stale where nothing recomputes them.

**The count that had drifted is now derived.** `cref.rb`'s argument for
`#surface_for` rested on the asymmetry between one read site and seven,
typed out of the 0.2.11 stocktake. The tree has **ten** — the argument is
stronger than it was written, which is precisely why nobody noticed it
was wrong. Both numbers now carry `<!-- measured: -->` markers and
`measured_claims_spec` recomputes them from `parser_service.rb`; drifting
one back to seven fails the suite with *"cref-declares-singleton-parser-sites
says 7, the tree has 10"*.

**The `1 of 9 (024.35)` credit is withdrawn.** `024.35` is open, and has
been through 0.2.15, which added a section saying its "does not
reproduce" claim was never independently confirmed. C2 shipped its
mechanism and closed none of its nine.

**The stocktake table itself is left as written.** It is dated and
attributed — "re-run against the tree at `0449007`" — and correcting a
dated finding to today's tree is the opposite of what a record is for.
What a reader needs is that it *is* dated, which its own heading says.

## 024.103 A bare class name inside a namespace answers with an arbitrary same-named class

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.10
released-in: 0.2.10
```

**Retargeted to 0.2.10.** Recorded as 0.2.9 when 0.2.8's drive round
found it, and 0.2.9 shipped C2 without it — the record said one thing and
the release did another, which is the discrepancy this register exists to
make visible rather than to contain. Kept at the front of 0.2.10 because
it is the sharpest of the three: a false report on working code, on a
layout as ordinary as `Billing::Comment` beside an ActiveRecord
`Comment`.

**Area:** `core/lib/ovallsp/workspace_index.rb` (`#resolve_type_name`),
`core/lib/ovallsp/semantic/receiver_resolution.rb`

Two classes of your own sharing a short name, in different namespaces,
and a bare reference to one of them from inside its own namespace answers
with the other. Driven end to end by 0.2.8's `drive` round, A/B'd against
`main` and identical there — **not a regression, and not covered by any
existing entry.**

Plain Ruby, three files, `::Config#top_only` and `App::Config#app_only`:

```ruby
module App
  class Runner
    def go
      Config.new.app_only   # ordinary, correct Ruby
```

- `unknown-method: Config has no method named 'app_only'` — a **false
  positive on working code**
- `Config.new.top_only`, which is the call that really raises, is
  **silent**
- completion inside `module App` after `Config.new.` offers `top_only`

Exactly inverted, both directions. The Rails shape is the same:
`Billing::Comment` alongside an ActiveRecord `Comment`, which is an
ordinary layout.

**And the winner is not the lexically nearest class.** With only
`Alpha::Config` and `Beta::Config` and no top-level one, completion
inside `module Beta` offers `alpha_only` — first-indexed or alphabetical,
never `Module.nesting`.

`024.47` covers a class of yours named after a *core* class, where the
engine goes silent; `024.81` covers a shared *module* name in an
`include`, where it refuses. Here it neither goes silent nor refuses: it
answers, and the answer is wrong. Section 0.4's own example.

**Direction:** `ReferenceCandidate` already carries `lexical_nesting`,
and `#resolve_explicit_receiver_name` already walks it — for a receiver
written bare. What is missing is the same walk for the *type* a bare
reference denotes, and a refusal when nothing in the nesting matches
rather than a fall back to the alphabetically first candidate. Part of
`037`'s C2: the answer is `unknown`, not a pick.

## 024.104 `class_methods do` in a concern is attributed to the instance side

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.10
released-in: 0.2.10
```

**Area:** `core/lib/ovallsp/parser_service.rb` (the `included`/
`class_methods` block forms), `core/lib/ovallsp/semantic/hierarchy_index.rb`

`ActiveSupport::Concern`'s `class_methods do ... end` declares methods on
the *class*. Ground truth from the booted fixture app:
`Article.respond_to?(:cm_public)` is true, `Article.new.respond_to?` is
false, and calling it on an instance raises.

What 0.2.8's `drive` round measured at `ready-rails`, for
`a = Article.new; a.cm_public`:

| feature | answer |
|---|---|
| completion after `Article.new.` | offers `cm_public` |
| hover | `cm_public()`, defined at the concern |
| go-to-definition | jumps to the concern |
| undefined-method check | silent |

**Four features agreeing, all four wrong.** Statically it is offered only
on the instance and not on the class at all, so the attribution is
backwards; the Runtime Agent later adds the correct class-side entry
without removing the wrong instance-side one.

The control that isolates it: the same app's `module ClassMethods` form
is handled **correctly**, including reporting `a.tag_all` as unknown. So
it is the `class_methods do` block specifically.

This also contradicts the sentence `024.99` put in `KNOWN_LIMITATIONS` —
"the instance-level list in a Rails project with the Runtime Agent
connected is clean".

## 024.105 Visibility is not recorded for singleton methods at all

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.9
released-in: 0.2.9
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#visit_def_node`'s
`visibility: singleton ? nil : ...`)

`private` written inside `class << self`, and `private_class_method`,
change nothing: the method is offered by completion and accepted by the
check. Verified against the booted app — `Article.sing_priv` raises
`NoMethodError: private method 'sing_priv' called for class Article`.

A `def` recorded as a singleton method is given `visibility: nil`
outright, so there is nothing downstream to filter on. A/B'd against
`main` in 0.2.8: identical, so this predates the Cref work.

**Everything around it is right**, which is what makes it a hole rather
than "visibility is not modelled": `private`/`public`/`protected` in a
class body, `private def x`, `private :x`, `private` inside a concern's
`included do`, `private` before a nested `class`, and `private` before
`def self.x` (correctly *not* applied, matching Ruby) all behave.

Neighbour of `024.99`; both are the visibility half of `037`'s C2.

## 024.107 An alias never appears in completion, though every other feature knows it

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.9
released-in: 0.2.9
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb` (`#complete`
against `#resolve`)

```ruby
class Aliased
  def original; end
  alias aka original
  alias_method :aka2, :original
end
```

Hover on `a.aka` answers with its signature and its definition site,
go-to-definition jumps there, and the undefined-method check accepts it.
Completion after `a.` offers 121 items containing `original` and neither
alias.

A developer who aliases a method and then types `a.` concludes the alias
does not exist. `#resolve` follows an alias and `#complete` does not,
which is `024.100`'s shape again: one question, two code paths.

## 024.108 Protected methods are offered on an explicit external receiver

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.9
released-in: 0.2.9
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`#members_of`)

`Prot.new.` completes `prot_only`; the call raises. **Private** instance
methods are correctly excluded at the same position, so the protected
half of the same rule is simply missing.

And at the same position class: `c.secret_helper(1)` — private, explicit
receiver — is excluded from completion while hover answers it and the
check accepts it. `024.99`'s sibling, and the same `037` C2 seam.

## 024.109 Specs whose fixture cannot distinguish the behaviour they pin

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A spec that pins less than it claims changes nothing a user can
  observe today; what it removes is the guarantee that the next refactor
  cannot silently change the behaviour underneath it.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/spec/` (0.2.9's change set)

0.2.9's `attack` round reported four examples that pass under either
candidate behaviour — the failure `CLAUDE.md` names as "a spec whose
fixture cannot distinguish the two candidate behaviours is unpinned even
though it passes".

**One is identified and fixed.** The override-signature example built
`class Shape; def area(x)` and `class Circle < Shape; def area(x)`, so
the override and the method it overrides rendered the *same* label. A
dedup-on-label passed it without ever choosing the callable one, and an
override that renames its parameter — the ordinary case — still showed
the phantom choice. The fixture now names the parameters differently and
the implementation picks the lowest-ranked candidate per receiver member.

**A second is now named.**
`method_resolver_availability_spec.rb`'s "cannot account for a
class-level lookup when the instance chain has an unaccounted link" built
its query by hand and left `signatures:` at its `nil` default, so it was
passing on "unknown because there is no signature environment" and would
have gone on passing with the instance-chain rule removed. Fixed in
0.2.10, with the control it was missing: the same lookup with the chain
accounted for is `absent`, not `unknown`.

**The remaining two are not named here, because the round's list was held
in a session and not written down before it was lost.** That is the
defect this entry mostly records: a review round's findings are a
measurement, and a measurement kept only in a conversation is gone at the
next compaction. Round 11's table now lives in
`docs/design/tasks/039-0.2.9-one-question.md`, which is where the next
round's should go from the start.

Re-deriving them is mechanical rather than archaeological, which is why
this is a 0.2.10 item and not a lost cause: for each example added by
this change set, ask what the *other* branch of the decision would render,
and reject any fixture where the two answers are equal. The spec-deletion
pass of `scripts/hunk_sweep.rb` finds files that pin nothing; this is the
narrower question of an example that pins less than it claims, and the
two are worth running together.

**The remaining two are named, and the way they were found is the
point.** 0.2.12 built the mechanism this entry has always wanted — a
spec names the mutation it claims to catch, and
`scripts/check_pinned_mutations.rb` applies it and requires the failure
— and then pointed it at 0.2.9's own decisions.

**Third:** `member_availability_spec.rb`'s "is frozen, so a reader cannot
be handed one that changes under it" asserted
`described_class.absent` is frozen. A `Data` is frozen whatever this
class does, so the example passed with every `freeze` in the file
removed. It now asserts the *candidates array* — the thing a caller is
handed and could push onto — for all three states.

**Fourth:** the alias-visibility rule the round had designed **was never
in the tree at all.** The mutation could not be written because the
method it was supposed to invert did not exist, and the register carried
`024.105`, `024.107` and `024.108` as fixed while completion offered a
name that raises. Recorded and fixed as `024.123`.

So the count is four of four, and the two nobody could name were found
by a machine rather than by re-reading. That is what this entry was
really about.

## 024.110 The macro is reported, and what it might define is not

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.13
released-in: 0.2.13
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/parser_service.rb` (`#record_open_surface`)

```ruby
class HostC
  attr_atomic :thing        # `unknown-method: HostC has no method named `attr_atomic``
end
```

An unrecognised class-body macro correctly opens the owner's surface, so
nothing it *might* define is reported. The call that opened it is
reported anyway — a false positive on ordinary code whenever a macro
comes from a gem, a `Concern`, or an `extend` this parser cannot read.

The two answers contradict each other about the same fact: the engine
says "I cannot enumerate this class's members because something
unreadable ran here", and then asserts that the unreadable thing does not
exist.

Found while fixing `024.106`'s second half. It is **not new** — the class
spelling has always behaved this way — but it became visible on modules
too once a module's class-level calls started being checked at all. An
existing example in `open_surface_spec.rb` was asserting `be_empty` over
a document containing one, and was narrowed to the call it is actually
about rather than left pinning an accident.

**0.2.11 tried exactly that direction and rolled it back inside the same
release.** "A receiverless call that opens the surface is evidence about
that owner's class side as well" is one line, and it is right for the
class in front of you. It is catastrophic for `class Module`,
`class Object` or `class Kernel`, which are in *every* class's singleton
chain: one bare `alias_method` in a `core_ext` file switched off
`Foo.bar` checking for the whole workspace.

Measured by a `drive` round over 1,659 files of 16 installed gems, with
`unresolved-constant` identical at 4,556 as the control: `unknown-method`
497 → 349, **and constant-receiver findings 117 → 0**. Among the 148
removals was a real latent `NoMethodError` —
`ActiveRecord::Promise.wrap` at `statement_cache.rb:158`, where the only
`def self.wrap` in the tree belongs to `FutureResult`.

**The measurement that justified the try had the same contamination.**
It ran over four gems including activesupport, whose
`core_ext/module/attr_internal.rb` contains a bare `alias_method` in
`class Module` — so its headline `84 → 25` was the class-level check
dying rather than a precision gain, and the sampling that called every
removal a false report missed `Promise.wrap`. A four-line reproduction is
in `unreadable_macro_spec.rb`.

**What a real fix has to distinguish:** "I could not read *this class's*
body" from "I could not read `Module`'s". An open surface on a universal
ancestor is not evidence about a specific class, and the current
representation — a flat `[owner, side]` set consulted through the whole
chain — cannot express the difference. That is the change, and it is
bigger than one line.

**Fixed in 0.2.13, and what made it fixable is `042`'s D2.** The
one-line version — a bare class-body call opens the owner's *class*
surface as well as its instance one — is right, and 0.2.11 shipped it and
rolled it back the same release. What was wrong was the *reader*:
`MethodResolver#open_surface?` consulted every link in the chain, and
`Class`, `Module`, `Object`, `Kernel` and `BasicObject` are in every
class's. One bare `alias_method` in a `core_ext` file then said "I cannot
enumerate" about the whole workspace.

`#open_surface?` ignores a **synthesised** link now — one the workspace
did not write. A reopening of `Module` *is* real, and a method it defines
really would be reachable from `Widget`; what the exclusion trades is
that truth for a check that can run at all in a workspace with a
`core_ext` directory, which is most Rails applications. The narrower
claim it leaves standing is the one this entry was always about: **the
owner whose own body could not be read is declined about, and only that
owner.**

Measured over the 16-gem corpus, 1,659 files, with `unresolved-constant`
identical at 4,600 and both argument checks identical as controls:

| | main `9033ed2` | branch |
|---|---|---|
| `unknown-method` | 506 | **395** |
| added / removed | — | **0 / 111** |

Three of the removals checked against the interpreter —
`ActionCable::Server::Base.config`,
`ActionController::Parameters.permit_all_parameters=`,
`ActionDispatch::Request::Utils.perform_deep_munge` — all real methods,
all false reports. And **`ActiveRecord::Promise.wrap`, the real latent
`NoMethodError` 0.2.11's version silenced, is still reported on both
sides.** That is the difference between this fix and that one, in one
line.

## 024.111 A visibility section written inside a block does not reach the body it runs in

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#visit_block_node`)

```ruby
module BMF
  1.times { module_function }
  def y; end
end
```

Ruby (3.4.10) gives `BMF.respond_to?(:y) == true` and
`BMF.private_instance_methods(false) == [:y]`; the engine records `y` as
a public instance method and no module method, and reports `BMF.y` as
unknown. The same for a plain `private`:
`class BV; [1].each { private }; def x; end; end` leaves
`private_instance_methods(false) == [:x]` in Ruby and `[["x", :public]]`
here.

`#visit_block_node` gives a block its own cref frame, and the reason is
sound for the case it was written for: `included do ... end` and
`class_eval do ... end` run their `private` against a different module,
and without the frame it leaked into the enclosing class and silently
made every later method private — which dropped real controller actions.

But an *ordinary* iterator block shares self with its body, so the frame
is wrong there. Distinguishing the two needs to know what the call does
with the block, which is `#block_self_is_module`'s question, and
extending it is a change to a rule three releases have adjusted.

**Not fixed in 0.2.10** because the release was already in a review loop
and this is the shape `CLAUDE.md` says to record rather than add to a
change set under review. Found by the `attack` round.

**Said to be narrowed in 0.2.13, and it was not.** `024.117` recorded
that "`[1].each { private }` and `1.times { module_function }` reach the
enclosing body now". They did not, on that day or since.
`Cref#in_block(shares_self: true)` returns the same cref and opens no
frame — but `#visit_block_node` restored `@cref` from a local in an
`ensure`, **unconditionally**, and `Cref` is an immutable value. The
section a `private` opens *is* a new cref; the restore threw it away. An
`attr_accessor` in the same block records its declaration while the
shared cref is installed, so that half worked, and its working was read
as evidence for the other two. `024.219` records the claim.

**Fixed in 0.2.15.** `#visit_block_node` asks the value whether a frame
was opened — `!block_cref.equal?(@cref)` — and restores only then. Asking
the returned cref rather than re-deriving `iterates_a_literal?` at the
restore keeps the rule in one place, which is where 0.2.13 left it.

Two constructs neither entry had ever mentioned were broken by the same
line and fixed by it: `[1].each { protected }` and a `[1].each { public }`
cancelling an open `private`. They were found by enumerating what a
self-sharing block carries out instead of fixing the two cases reported —
`CARRIED_OUT` in `spec/ovallsp/visibility_through_block_spec.rb`, which
generates its examples from the table and is the countermeasure this
place earned by being found in two releases running.

**The receiver this parser cannot vouch for stays contained, as it must.**
`SOME_CONST.each { private }`, `included do ... end`, `class_eval` and
`concerning ... do` run their `private` against a different module, and
without the frame every method written after such a block was recorded
private — which silently dropped real controller actions and their ivars
vanished from the corresponding views. All four are rows in `CONTAINED`.
Telling a *nameable* receiver apart from that is still `024.31` and
`024.33`'s question — a block wants a receiver, not a boolean.

Corpus, 4 Rails gems, 997 files, control `unresolved-constant` identical
at 2,987: **0 added, 0 removed.** A Prism probe over the stdlib and every
installed gem — 4,582 files — finds **no instance of the shape at all**,
so that run bounds the regression risk and says nothing about the fix.
The mutation check does: reverting the guard fails 5 of 14 examples,
never restoring fails 4, and forcing `iterates_a_literal?` false fails 5.

## 024.112 A bare constant is not looked up through the enclosing class's ancestors

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.11
released-in: 0.2.11
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#qualify_constant`),
`core/lib/ovallsp/workspace_index.rb` (`#nested_type_name`)

Ruby resolves a bare constant by `Module.nesting`, **then the ancestors
of the innermost cref**, then Object. 0.2.10 implemented the first step
and stops:

```ruby
class Config; def top_only; end; end
class Zbase; class Config; def zbase_only; end; end; end
module App
  class Runner < Zbase
    def go  = Config.new.zbase_only   # Ruby: Zbase::Config, works
    def bad = Config.new.top_only     # Ruby: NoMethodError
  end
end
```

Both directions inverted, exactly as `024.103` describes: the working
call is reported, the raising call is silent. Pre-existing — the same on
`main` — and not a regression from `024.103`'s fix, which correctly
answers nil when the nesting decides nothing and leaves the old heuristic
to answer.

Also here: `#push_nesting` concatenates written paths, so
`module App; class ::Other::Runner` records the frame
`App::Other::Runner` where Ruby's is `Other::Runner`. The compact
`class App::Runner` form is handled correctly.

## 024.113 The publish funnel's memory is keyed by uri, not by buffer

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.11
released-in: 0.2.11
```

**Area:** `core/lib/ovallsp/server.rb` (`@last_published_version`)

0.2.10 made `#publish_findings` take the document and compare its
`buffer_id`, and left the memory it compares against keyed by uri. A
client that reopens a file **without closing it** — `didOpen v10`, then
`didOpen v1` for a new buffer, then `didChange v2` — publishes `[10]` and
refuses every edit until the new buffer's numbering passes 10.

Pre-existing and unchanged by this release (`#clear_findings` covers the
close path, which is what a conforming client sends), but it is the same
category error the release says carrying the buffer eliminates, and it is
the last place a version integer is compared across buffers.

## 024.114 `module_function :name` cannot see a module reopened in another file

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.11
released-in: 0.2.11
```

**Area:** `core/lib/ovallsp/parser_service.rb`
(`#apply_module_function_arguments`)

```ruby
# a.rb
module Reopened; def r_a; :a; end; end
# b.rb
module Reopened; module_function :r_a; end
Reopened.r_a          # Ruby: :a. Reported as missing.
```

The recorder scans `@declarations`, the per-file visitor accumulator, so
the same-file form works and the cross-file form never does — and
cross-file is what the by-name form exists for. 112 `module_function :`
sites in one 40-gem corpus.

The fix is not in the parser: it has to be a fact the index applies after
both files are indexed, the way `AncestorFact` already is. Found by
0.2.10's `drive` round.

## 024.115 `include M` reaches `M::ClassMethods` whether or not M is a Concern

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.11
released-in: 0.2.11
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`
(`#concern_class_method_entries`)

0.2.10 keys the class-level edge on `M::ClassMethods` existing, not on
`M` being an `ActiveSupport::Concern`. A plain module with a nested
`ClassMethods`, included into a class, then makes completion offer a
method that does not exist — `NoMethodError` if the developer picks it.

The recorded reason was that requiring `extend ActiveSupport::Concern`
would miss every concern written before Rails 4. **0.2.11 narrowed it on
a restatement of that reason which turned out to be false**: the
pre-Rails-4 shape is `def self.included(base); base.extend(ClassMethods); end`,
and the receiver is a method *parameter* — there is no `extend` in a class
body for this index to follow, and a generation of real concerns became
false reports for one round. The parser records that hook as its own
relation now, and it is the second marker.

Recorded rather than changed because it arrived in the round that closed
the loop, and because narrowing a rule wants its own corpus measurement.

## 024.116 `def self.method_missing` and `define_singleton_method` do not open a surface

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.13
released-in: 0.2.13
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`
(`#declares_method_missing?`)

`declares_method_missing?` asks the index for `kind: :instance_method`
only, so a class answering through `def self.method_missing` is judged
closed and every call it handles is reported. The same for a class whose
methods are made by `define_singleton_method` in a loop.

Pre-existing on classes, on `main` and every release before it, and
`KNOWN_LIMITATIONS`' four-shape list does not mention either. Found by
0.2.10's `drive` round while checking whether that release had widened
them to modules; it had, and the widening was reverted with `024.106`.
**The half that shipped in 0.2.11**: `#declares_method_missing?` asks the
side the lookup is on, so `def self.method_missing` closes a class-level
lookup and an instance-side one no longer does. Three review rounds in a
row found that one side computation wrong, and it is mechanised now --
`AncestorEntry#declaration_kind` owns the rule and this reader calls it.

**What is left open**: `define_singleton_method` opens the surface, so
the calls it answers are no longer reported, and hover, go-to-definition
and completion still answer nothing for them because the names are not
in the index. Silence instead of an answer, which is the safe direction
and not the right one. Recording those names is the fix, and it is a
parser change with its own measurement.


**The residue is closed in 0.2.13.** `define_method(:x)` and
`define_singleton_method(:x)` name their method as plainly as a `def`
does, and only the open surface was being recorded — so calls stopped
being reported while hover, go-to-definition and completion all answered
nothing. Silence instead of an answer, which is the safe direction and
not the right one.

A literal symbol or string argument is recorded as a generated
declaration on the side `Cref#surface_kind` gives. **The surface still
opens either way**, and the control example says why: a *computed* name
is exactly what this parser cannot read, and one such call in a body
makes the whole owner unenumerable however many literal ones sit beside
it.

Corpus unchanged at 0 added / 119 removed — these gems name their
`define_method` calls dynamically, which is the shape the surface exists
for.

## 024.117 The two spellings of a class-body macro get opposite answers

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.13
released-in: 0.2.13
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#record_open_surface`)

```ruby
class B1; the_macro; end                       # silent
class B2; %w[a b].each { |n| the_macro(n) }; end
# unknown-method: B2 has no method named `the_macro`
```

`024.110` decided that a bare call this parser cannot read is evidence it
could not read the body, and stopped reporting it. The implementation
returns early at `@cref.defines_surface?`, which is false inside a block
— so `%i[title body].each { |f| validates f }`, a mainstream spelling of
exactly the construct `024.110` is about, still reports.

Neither report is *wrong* in a bare-Ruby fixture: both raise. What is
wrong is that one construct written two ways gets opposite answers, which
is the shape `024.100` names.

Not fixed in 0.2.11 because the block guard is `024.111`'s territory —
the frame exists so `included do ... end` cannot leak a `private` into
the enclosing class — and the two want deciding together. Found by
0.2.11's `attack` round.

**Fixed in 0.2.13, by asking Ruby what a block actually does.** The
entry says the two want deciding with `024.111`, and running them settled
both halves at once:

    $ ruby -e '
    module BMF; 1.times { module_function }; def y; end; end
    p [BMF.respond_to?(:y), BMF.private_instance_methods(false)]
    class BV; [1].each { private }; def x; end; end
    p BV.private_instance_methods(false)
    class BS; [1].each { attr_accessor :bs_x }; end
    p [BS.new.respond_to?(:bs_x), BS.respond_to?(:bs_x)]
    '
    # => [true, [:y]]
    # => [:x]
    # => [true, false]
    # ruby 3.4.10

A visibility section, a `module_function` and an `attr_accessor` written
in an ordinary iterator block **all reach the enclosing body**, and the
frame was containing all three.

> **This sentence was one third true, and stayed in the register for two
> releases.** The interpreter session above is right. The `attr_accessor`
> half really was fixed here. Both visibility halves were **inert on the
> day they were declared fixed**: `#in_block(shares_self: true)` opens no
> frame, but `#visit_block_node` restored `@cref` unconditionally in an
> `ensure`, and `Cref` is an immutable value — so the new cref a
> `private` produced was thrown away with the restore. An `attr_accessor`
> records its declaration *while* the shared cref is installed, which is
> why that one worked and looked like evidence for the other two.
> Corrected in 0.2.15 with `024.111`; `024.219` records how a three-part
> claim shipped with one part pinned.

`Cref#in_block(shares_self:)` opens no frame when the owning call's
receiver is a **literal** — `%w[a b].each`, `[1].each`, `(1..3).map`.
That is a shape rather than a list of method names, for the reason
`#record_open_surface` already gives about setters: a list can only ever
hold the calls somebody has already seen. Nobody's DSL rebinds self on a
core object.

Everything else still gets a frame, which is what keeps `included do ...
end` and `concerning ... do` from leaking a `private` into the class
body — the regression that frame exists for, and the half of `024.111`
that stays open: a constant receiver could be anything, and this parser
cannot say what its `each` does with self.

Corpus, 16 gems, 1,659 files, control `unresolved-constant` identical at
4,600: **0 added, 111 removed** — unchanged from before this fix, which
is what it should be, since these gems iterate literals in class bodies
without calling anything unreadable in them.

One example was **deleted rather than adjusted**:
`class_body_macro_spec.rb`'s "still reads an ordinary block in a class
body as the class" turned on an unreadable call, so once the block shared
the cref, `024.110` declined about the owner and the example could no
longer distinguish anything. That is `024.110`'s recorded cost arriving
in a spec instead of a corpus, and the comment left in its place says so.

## 024.118 `WorkspaceIndex#stale?` compares versions across buffers

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/workspace_index.rb` (`#stale?`),
`core/lib/ovallsp/index/file_summary.rb`

`024.113` made the publish funnel remember `[buffer_id, version]`, and
the scenario its own commit message names still fails at the LSP
boundary. Driven as `didOpen v20` → `didChange v21` → `didOpen v1`
without a close → `didChange v2`, nothing at all is published for the new
buffer.

The reopen is dropped one layer earlier: `#stale?` compares
`document_version` against what it already holds, `FileSummary` carries
no `buffer_id`, and the comment there still asserts "an LSP client always
sends increasing versions per document" — the premise `024.113` rejected
one layer down.

**Two places compared a version across buffers and one of them was
fixed.** Found by 0.2.11's `drive` round, driving the real server, after
the `attack` round had reported the funnel unbreakable — which it is, in
isolation. The lesson is the one `024.100` keeps making: a fix belongs
where the *question* is answered, and "which buffer is this" is answered
in two places.

## 024.119 Twenty-eight spec files assemble their own analysis stack

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Not a defect a user meets. It is the reason an example can pass while
  the shipped server answers differently, which is how several defects a
  user does meet reached a release -- so it is recorded as a defect
  rather than as a chore.
target: 0.2.12
released-in: 0.2.12
```

**Area:** the twenty-eight files named in
`core/spec/meta/analysis_stack_spec.rb`'s `NOT_YET_MIGRATED`

0.2.12 made `Ovallsp::AnalysisStack` the one place the analysis
collaborators are wired together, and `Server#initialize` and
`scripts/corpus_diagnostics.rb` now assemble nothing — those are the two
places where measuring against the wrong program actually happened
(`024.103`, `024.112`).

The spec files still write the constructors out, and most are missing
one. `open_surface_spec.rb`'s `LocalInferencer` has no `signatures:`, no
`workspace_index:` and no `hierarchy_index:`; the server's has all three.
An example there is therefore green against a program that is not the one
that ships, which is `024.109`'s category arriving through the wiring
instead of through a fixture — and invisible, because nothing compared
the two lists until the check existed.

**Migrated in one commit rather than twenty-eight**, because a
half-migrated suite runs two programs, which is the condition being
removed. The named list the check carried while that was in flight is
gone with it: a list that can only shrink is still a list, and keeping an
empty one invites the next file to be added to it.

Two of the twenty-eight needed more than a mechanical rewrite and are
worth naming, because both were the defect in miniature:
`visibility_spec.rb` built a `QueryService` around a `MethodResolver`
that no `LocalInferencer` in the file shared, and `literal_types_spec.rb`
called `LocalInferencer.new` with no collaborators at all to answer a
question about literal types — which is the one shape where that happens
to be right, and indistinguishable from the shapes where it is not.

## 024.120 The integration watcher example could not retry, and it looked like a Linux defect

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A test defect, not a product one. It is recorded because it produced a
  confident and wrong diagnosis of the product for two CI runs, and the
  wrong diagnosis was written into KNOWN_LIMITATIONS in both languages
  before the next run disproved it.
target: 0.2.12
released-in: 0.2.12
```

**Area:** `vscode/src/test/integration/watcher.spec.ts`

When `024.69` first put the integration suite on CI, this example failed
on Linux -- and failed on a **different file each run**. The first
diagnosis was that `db/migrate/*.rb` alone produced no event, which was
written up as a possible product gap on Linux and documented as a known
limitation in both languages. The next run failed on the `.rbs` instead,
which disproved it.

The real cause is in the example. `createFileSystemWatcher` registers
asynchronously, so whichever file is written before registration
completes misses its event -- *which* file varying with runner load. The
retry loop added to handle exactly that could not work, because it
rewrites a file that now exists and VS Code reports a rewrite as a
**change**, while the subscription was `onDidCreate` alone.

Fixed by subscribing to both. That is faithful to what the example is
for: the question is whether `WATCHED_FILES_GLOB` reaches these paths at
all, not which kind of event it reaches them with.

**The lesson is about the diagnosis, not the fix.** Two runs of a new job
produced a plausible, specific, user-visible-sounding defect
("migrations do not refresh on Linux") that did not exist. What
distinguished it was the *third* run failing somewhere else. A single
observation of a nondeterministic failure describes the run, not the
system -- the same rule `026` records for measurements, arriving through
a test.

## 024.122 A failure is turned into a plausible value, in 72 measured places

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.13
released-in: 0.2.13
```

**Area:** `core/lib` (159 `rescue` sites), `vscode/src` (21 `catch`
sites), and `CLAUDE.md`, which does not say what the rule is

Raised by the maintainer, who had noticed the pattern across the
codebase rather than in one place. Counted rather than estimated —
every `rescue` in `core/lib`, classified by what the first statement of
its handler does:

| what the handler does | sites |
|---|---|
| **returns a plausible value, silently** | **72** |
| logs, then usually returns a value | 44 |
| other (sets a flag, retries, cleans up) | 39 |
| re-raises as a typed error | 4 |

**The count was first written down as 239 and that was wrong.** It came
from `grep -c rescue`, which counts the word wherever it appears —
including in the prose of comments explaining a rescue, of which this
tree has many. Counting `rescue` *statements* gives **159**, and the
breakdown above was computed that way and is unchanged. Corrected here
rather than quietly, because a measured claim that nobody re-derives is
the thing `026` is about, and this one lasted one release.

**133 of the 159 are `rescue StandardError`** — the widest catch there is —
and the remaining 26 name a type. There are no bare `rescue` statements; the 13 that grep found were the keyword inside comments and one-line modifier prose. `vscode/src` has 21 `catch` blocks outside
its tests, uncounted here.

**Why this is a defect and not a style preference.** A swallowed failure
does not produce a wrong answer that someone eventually notices. It
produces *the answer that would be right if nothing had gone wrong*, and
this project has now been bitten by that at every layer:

- `Cache::Store#load` rescued a "struct size differs" into a silent
  whole-cache miss, so a schema bump that was never made looked exactly
  like a cache that was working. `SCHEMA_VERSION`'s own comment records
  it.
- `Signatures::Environment#ancestors` answering `[]` on failure is
  indistinguishable from a type with no ancestors, which is `024.35`'s
  whole shape and half of what `042`'s D2 is about.
- 0.2.12's own `check_pinned_mutations.rb` reported all four mutations
  uncaught on its first run — because it could not load the code it was
  mutating. **A checker that cannot see the thing it checks reports
  exactly what a working checker reports when nothing is pinned.** That
  is this defect happening to the thing built to prevent a different one.
- `prune_generations` swallowing every error by design is what made
  `.not_to raise_error` an assertion that could not fail, in the spec
  that deleted the maintainer's applications. `CLAUDE.md` records the
  incident and does not draw this conclusion from it.

**The task, in the order it has to happen:**

1. **Enumerate.** Every `rescue` in `core/lib` and every `catch` in
   `vscode/src`, one at a time, with the count above as the control —
   an enumeration that comes out at a different total has missed
   something or double-counted. Each site gets one of three verdicts:
   *surfaces* (raises, or reports through a channel a user or a log
   reader sees), *deliberate and argued* (the failure genuinely has no
   consequence, and the reason is written at the site), or *swallows*.
2. **Fix every site in the third group.** Not by adding a log line —
   44 sites already log and still return a plausible value, and a log
   nobody reads is a swallow with extra steps. The value returned has to
   be one a caller cannot mistake for a real answer: `unknown` where
   there is a three-state answer, a raise where there is not.
3. **Then write the policy**, in `CLAUDE.md`, as a mandatory section:
   catching an exception and continuing is not allowed by default; a
   site that does it names, in place, what the failure cannot affect and
   how a reader would find out it happened. And a check that a new
   `rescue StandardError` without such a note fails the build, because
   this register's whole history says a prose rule alone does not hold.

**Order matters and step 3 is last.** Declaring the policy before the
tree obeys it makes a rule with 72 exceptions on the day it is written,
which is the arrangement `CLAUDE.md`'s own preamble warns about.

**Why 0.2.13 rather than later.** A swallowed failure makes a
*measurement* silently measure nothing, and `042`'s sequencing already
puts the apparatus classes first for exactly that reason. This belongs
with them; it did not go into 0.2.12 only because that release was
already scoped and under review when the maintainer raised it.

### Step 1 shipped in 0.2.13: the enumeration is a checked artefact

`core/spec/meta/rescue_verdicts.yml` names every `rescue` statement in
`core/lib` and what it does with the failure — `surfaces`, `contained`,
or `swallows`. `scripts/check_swallowed_failures.rb` fails on a rescue
with no verdict and on a verdict whose rescue is gone; it runs in the
suite and gates in CI.

Keyed by the enclosing `def` and an ordinal within it, not by line
number — a line number rots on the next edit above it, and 42 of these
live in one file where `rescue StandardError` is not a distinguishing
string.

First-pass verdicts, assigned mechanically: **48 surface** and **111
swallow**, with nothing `contained` — deliberately, because `contained`
means *somebody argued it* and nobody had.

**The first pass was wrong about nine of them, and the second pass is
part of the record.** It looked for a logger and missed
`diagnostics << { severity: :error, … }` — the channel the server
*publishes* to the editor, which is a person seeing it more reliably than
a log line. Counting that as surfacing: **57 surface, 102 swallow**.

**Six are now `contained`, argued in place**, all in
`Signatures::Environment`. What makes them safe is not that the failure
is unimportant: it is that every one produces *less knowledge* and no
consumer can turn it into an assertion about the user's code. An empty
ancestor chain is what a type RBS does not declare gives, and
`TypeNameResolution` then declines to call a name shadowed while
`MethodResolver` reaches `:ancestor_not_declared_anywhere`. That is the
shape of argument `contained` is for, and it is written at each site
rather than only here.

**Then a first real fix, and it is the shape the whole entry is about.**
`LocalInferencer#assigned_ivar_names` answered `[]` when its parse
raised, and both callers build a *union* the unassigned-ivar check
compares a view's reads against. An empty list from a failed parse is
indistinguishable from a document that assigns none — so one unreadable
ancestor file silently removed its ivars from the union and every read of
one became a **false report**.

`Server#assigned_ivars_for` already refuses in that situation, answering
`nil` and switching the check off for that view. **The failure was being
caught one layer below the layer that knows what to do with it**, which
is the commonest form this defect takes: not "nobody handles it" but
"somebody handles it too early". The rescue is gone and the two examples
that pin it include the distinguishing one — a failure must not look like
"this document assigns nothing".

Eleven more are `contained` with their arguments: `Types::UNKNOWN` from
the inferencer is the engine's own three-valued not-knowing, and the
cache's failures all prune rather than keep, which is the direction that
class was rewritten to prefer after it deleted the maintainer's
applications.

**Two more fixes, both of the same shape as the first**: a check asked a
question, could not get an answer, and used the *reporting* value as the
fallback.

- `Engine#ivar_names_tested_for_existence` answered `[]`, which reads as
  "this file is defensive about nothing" — so a failure turned every
  `defined?(@x)` into an unassigned-ivar report. It answers `nil` now,
  which is not the value a file that tests nothing gives, and the caller
  declines on it.
- `Engine#rbs_known_constant?` answered `false`, which reads as "RBS does
  not know this name" — an assertion about the user's code made from a
  question that could not be asked. It answers `true`, so the check
  declines.

**Enumerating is what decides whether to assert, so a failure to
enumerate has to decline.** That sentence is the whole of §0 applied to
this class, and it is the test to run each remaining site against: not
"is this failure important" but "does the fallback value let a caller
assert something".

Thirteen more are `contained` with their arguments — the cache's, which
all leave files rather than remove them, and two more of the engine's
that already fail towards silence.

**71 remain**, and `unresolved-constant` is unmoved at 4,600 over the
16-gem corpus, which is the control these two changes had to keep.

**The mechanism is deliberately not "no rescue may swallow".** That rule
would have had 111 exceptions on the day it was written, which is the
arrangement `CLAUDE.md`'s preamble warns about, and it is why step 3 is
last. What gates now is that the *decision is made*: writing a rescue
means writing down what happens to the failure, in a file a reviewer
reads, and `swallows` is something somebody types rather than a default
nobody notices. Emptying the column is the work; this is what stops it
refilling behind the work's back.

### Step 3, and the column is empty

All 158 sites carry a verdict: **60 surface, 98 contained, none
swallowing.** `scripts/check_swallowed_failures.rb` now *fails* on a
`swallows` verdict as well as on a missing one, so the column that would
hold an unargued site stays empty — and `swallows` remains spellable only
so the failure message can name it.

`CLAUDE.md` carries the policy, written after the tree obeyed it rather
than before. That order was the entry's own condition and it was the
right one: writing it first would have produced a rule with 111
exceptions on the day it appeared.

**What the argument has to be.** Not "this failure is unimportant" — that
sentence is true of most of them and proves nothing. It is that **no
caller can turn the value into an assertion about the user's code**:
`Types::UNKNOWN`, a `nil` every reader already treats as "cannot say", a
cache miss that recomputes, a prune that leaves the file. Three sites
failed that test and were changed rather than argued, and all three had
the same shape — the fallback *was* the reporting value.

**An honest limit.** Ninety-eight arguments were written by one author in
one pass. A `contained` that turns out to be wrong is an ordinary
finding, and the file is where to record that it was; the mechanism this
entry is really about is that such a finding now has somewhere to land
and a check that will not let a new site avoid the question.

## 024.123 A private alias was offered, and the register said it was not

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.12
released-in: 0.2.12
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`,
`core/lib/ovallsp/parser_service.rb`,
`core/lib/ovallsp/index/alias_fact.rb`

```ruby
class A
  def build; end
  alias_method :aka, :build
  private :aka
end
```

`A.new.aka` raises; completion offered `aka`. `024.107` put aliases into
completion and `024.108` filtered private and protected, both released in
0.2.9 — and **neither made the two meet**, because an alias has no
declaration of its own and the visibility rule reads declarations. So the
lookup found `nil` for it and let it through.

**How it was found is the part worth recording.** 0.2.9's review round
identified this and a fix was written for it; the fix never reached a
commit, and the register carried `024.105`, `024.107` and `024.108` as
`fixed` while the tree offered a name that raises. Reading the register
could not reveal that, and neither could reading the specs — the
`visibility_spec.rb` examples all passed.

It surfaced while writing a `pinned_mutations.yml` entry for the alias
rule: the mutation could not be written, because the method it was
supposed to invert did not exist. **A checker built to ask "does this
example catch this change" found a fix that was not there at all.** That
is `042`'s D7 doing something its own charter did not claim.

**Fixed**, with the shape 0.2.9's round had designed:
`MethodResolver#visibility_of` is the one place that answers what a
name's visibility is, so the filter cannot be right about declarations
and wrong about aliases; `AliasFact` carries the alias's *own*
visibility; and `private :aka` writes it — including inside
`class << self`, which the instance-side guard used to return before
reaching, and which is safe for an alias because an `AliasFact` carries
`singleton` itself.

## 024.124 Four entries named a release that had already shipped, for the third time

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Register hygiene. Nothing an editor user meets; what it costs is that
  "what is left for this release" stops being answerable from the file
  that is supposed to answer it.
target: 0.3.0
released-in: 0.2.14
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (the
`target:` values), `core/spec/meta/deferred_findings_spec.rb`

Found by the maintainer asking what 0.2.x had done and what had carried
over. `024.39` and `024.64` still named 0.2.12; `024.106` and `024.111`
still named 0.2.13. Both had shipped.

**This is the third time**, which is what makes it an entry rather than a
correction. 0.2.9's preparation found three entries targeting a release
that had not been built; 0.2.12's found four naming releases that had
shipped; this is four more. Each time the fix was to retarget them by
hand, and each time the next release re-created the situation.

**The mechanical countermeasure, and why it is not simply "fail on a
shipped target".** An entry legitimately names a shipped release for the
whole time that release is being prepared — the value only becomes wrong
once the tag exists. So the check compares `target:` against
`docs/RELEASE_ARTIFACTS.md`, which lists what has actually been
published, and fails on an **open** entry whose target is in that table.
A fixed entry keeps its target as history, which is what
`released-in:` is beside it for.

`deferred_findings_spec.rb` enforces it, so the next release cannot
inherit the situation the way three have.

## 024.125 The packaged Core is never driven end to end, and two gates say it is

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.17
```

**Fixed in 0.2.17 by running it, not by withdrawing the claim.** The
`vscode-integration` job now runs `test:integration:packaged` after the
unpackaged run, with the same "fail if it reported no examples" guard —
without which this would have replaced "nobody runs it" with "CI runs it
and would not notice if it stopped".

**The Direction's cost was wrong, which is why this was cheap.** It said
the job "needs the same `xvfb-run` and VS Code download the unpackaged
integration job already pays for, plus a `vsce package` step". There is
no `vsce package` step: `test:integration:packaged` is `copy-core` plus
`compile` plus the same runner, and `copy-core` is the only thing that
differs from the step already there. The job already installs Ruby 3.4,
Node 20 and xvfb for the run above it.

**And running it found a failing test rather than a green one.** Driven
locally at HEAD, both variants failed the same example — `.erb` hover —
so it was not a packaged-only regression. CI had been failing on it
since 2026-08-24. `024.281` is the test; `024.282` is the week of red CI
that nothing in the tree recorded.

**What this does and does not cover**, stated because the ✅ it restores
is otherwise easy to over-read: the runner is `ubuntu-latest`, so
`copy-core` vendors *Linux* native extensions. The bundled-core load
path — what broke in `023.5` and `024.64`'s round 40 — is now verified
on every push. darwin-arm64 packaging is not, and remains covered by
`vsix_semantic_smoke.rb` at publish time and by hand, which
`docs/EXTENSION_CAPABILITIES.md` already discloses in both languages.

Rows 1 and 5 of `docs/RELEASE_CHECKLIST.md` now say which job runs them
and what the Linux runner does not reach.

**Area:** `vscode/package.json` (`test:integration:packaged`),
`.github/workflows/ci.yml`, `docs/RELEASE_CHECKLIST.md` rows 1 and 5

`vscode/package.json` defines `test:integration:packaged`, which drives a
VS Code host against the **packaged** Core — the one in the VSIX, with
its vendored native extensions — rather than the repository copy. No CI
job invokes it. `git grep test:integration:packaged` finds it named in
six documents and run by nothing.

`docs/RELEASE_CHECKLIST.md` marks rows 1 and 5 ✅ against it.

**Why this is user-visible and not merely a gap.** The packaged Core is
what a user installs, and it differs from the repository copy in exactly
the way that has broken before: `023.5` is a packaged-only update
regression, and `024.64`'s Round 40 was about a packaged-only load path.
`vsix_semantic_smoke.rb` does drive the packaged artifact at publish
time, which is why this is a gap rather than an absence — but it runs at
publish, not on a pull request, so a change that breaks the packaged path
is found after the decision to ship rather than before it.

**This is the half of `024.64` that survived.** That entry's other
direction shipped as `024.69`; this one is a different subject and gets
its own number rather than keeping an entry open for it, which is what
`024.90` did nine times over.

**Direction:** either run it in CI — it needs the same `xvfb-run` and VS
Code download the unpackaged integration job already pays for, plus a
`vsce package` step — or stop marking rows 1 and 5 ✅ and say what really
covers them. `046`'s C6 makes the second impossible to leave implicit.

**Re-triaged in 0.2.17** (`024.276`). Two capability rows are marked as verified and the thing that would verify them is never run: the packaged Core is not driven end to end anywhere. That is a claim about what is guaranteed, which is precisely what the patch line is for — either the job runs in CI, or the rows stop saying they are covered. `046`'s C6 makes leaving it implicit impossible.

## 024.126 A text scanner matches its own prose, exempts itself, and stops checking a file that can hold the real thing

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it costs is that a check quietly stops
  covering one file -- and the file it stops covering is the one whose
  author was thinking about that exact defect.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/check_doc_links.rb`,
`core/spec/meta/tmpdir_hygiene_spec.rb`,
`core/spec/meta/client_behaviour_spec.rb`

Found while building `046`'s A0, and then swept across every scanner in
the tree, which is what the maintainer's instruction for this pass asks
for: *if you find a problem from another angle, inspect the whole scope
from that angle.*

**The shape.** A check that scans tracked content scans **itself**. Its
own failure message, example, or `it` description spells the thing it
hunts — so it reports itself. The obvious repair is to exempt the file,
and that is the trap: the exemption removes coverage from the one file
whose author was demonstrably thinking about this defect, so a *real*
violation added there is invisible.

`check_doc_links.rb` hit it twice in five minutes. The comment written to
*explain* the first hit became the second, by quoting the bad form in
order to name it.

**The sweep, over all six scanners in the tree:**

| scanner | state |
|---|---|
| `check_doc_links.rb` | had it. Fixed by making the example unspellable as a path — `docs/<NN>-<name>.md` — rather than exempting a file that carries four real citations |
| `tmpdir_hygiene_spec.rb` | had it, as a blanket `__FILE__` exemption. Fixed by **parsing instead of grepping**: a call inside a string or a comment is not a call, so the exemption's reason disappears. A planted `Dir.mktmpdir` in the same example proves the matcher still fires |
| `client_behaviour_spec.rb` | had it, and a regex is not spellable another way. Exemption kept, with the reason at the site, and **paid for** by a new example that runs the matcher against a planted restatement |
| `no_wall_clock_thresholds_spec.rb` | **already right** — exemption stated with its reason, and a second example runs the matcher against the two assertions it replaced |
| `analysis_stack_spec.rb` | **already right** — no exemption, and a "would catch a harness that assembled its own" example |
| `check_home_paths.rb` | **already right** — a `SYNTHETIC` allowlist that is a deliberate edit with a reason, not a file exemption |

**The rule that came out of it.** A scanner may exempt itself only if a
second example runs its matcher against a planted instance. Two of the
six already did this; the sweep brought the other four to it. Where the
scan is for *code*, parse rather than grep and the question does not
arise.

**Not machine-checked, deliberately.** A rule that counted `__FILE__`
exemptions would be guessing at intent, and this project has rolled back
one countermeasure aimed at the wrong level (`024.47`). Six scanners is a
set a reviewer can hold; what makes it durable is that each now says at
its own site why it is exempt and where the compensating example is.

### A third instance, in the spec written to test the fix

`doc_links_spec.rb` grew two examples that plant citations in a
throwaway repository, and the fixture paths were spelled out in the
source. The scanner read the spec, found two paths that resolve to
nothing, and failed on the file whose entire subject is paths that
resolve to nothing.

Repaired the same way rather than a new way — `DIR`, `NEVER` and `ONCE`
are assembled from parts, so no contiguous path string exists in the
file — which is the point worth recording: **the rule above held on a
case its author did not anticipate.** Three instances, one repair
shape, no exemption added. That is the evidence that the rule is at the
right level; a fourth instance needing a fourth *different* repair is
what would say otherwise.

**The fourth arrived, and took the same repair.** `046`'s C4 needed a
synthetic register entry, and writing that entry's number out in the
spec made `measured_claims_spec`'s pointer guard report a dangling
register citation — in the file that tests the register. Assembled from
parts instead. (The number is described rather than spelled here for
the same reason, now that the guard reads this file too — `024.183`.)

### Seven times in one release, and what that finally bought

Instances five, six and seven all arrived in the checks written for
`024.147`:

| # | where | what it matched |
|---|---|---|
| 5 | `release_gate_spec.rb` | its own planted script name, once the file was tracked |
| 6 | `untracked_visibility_spec.rb` | its own needle, `ls-files`, in the line that searches for it |
| 7 | `untracked_visibility_spec.rb` | its fixture paths, read by `check_doc_links` |

**The rule was right every time and it kept not being applied.** Seven
occurrences, seven identical repairs, no exemption ever needed — the
level is correct. What failed was *remembering to apply it while writing
an example*, and a rule you must remember at the moment of writing is
the weakest kind.

So it stops being something to remember. `core/spec/support/unspellable.rb`
gives every spec `unspellable("docs", "brand_new.md")` and
`unspellable_number(999)`, which return the string at runtime and leave
nothing in the source for another check to match. It refuses a single
argument, because one part is a literal.

*This is the countermeasure the entry declined to build at three
instances, on the grounds that a rule counting `__FILE__` exemptions
would be guessing at intent. That reasoning still holds — this does not
count exemptions or guess at anything. It removes the occasion.*

### Twelve, and the rule moves to `CLAUDE.md`

Instances nine through twelve all arrived during round 2's fixes:
`AGENTS.md`'s prose naming the two branches it was explaining, and three
separate comments in `check_doc_links.rb` — one quoting a shorthand
path, one quoting a `.gitignore` glob, one naming a deleted document
while explaining how deleted documents are matched.

**Twelve occurrences, nine files, one release, one author who had the
rule in front of them.** That is no longer a series of accidents, and it
is not fixed by being more careful: the moment of writing an
illustration is the moment the rule is furthest from mind. So it is in
`CLAUDE.md` now, as its own section, with the two repairs separated —
`Unspellable` for a spec, *describe rather than quote* for a comment,
and never an exemption.

**Instance eight was the helper's own doc comment**, which showed what
`unspellable_number(999)` returns and thereby wrote a dangling register
citation into the file whose subject is that exact failure. It is the
residue the helper cannot reach: *a call can be assembled, an
illustration has to be legible.* The comment now describes the result
rather than spelling it, and says why — which is the only defence a
prose example has.

## 024.127 Hover answers an empty string where LSP expects null

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. Hover returns null where it has nothing to say.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/server.rb` (`#hover_result`)

For a position it knows nothing about — inside a comment, on
whitespace — hover answers `""` rather than `null`. The LSP specification
says `null`, and a client is entitled to treat an empty-string hover as a
hover that exists.

Measured through the real server by a 0.2.6 review round.

**Was one of nine bullets under `024.90` until 0.2.14.**

### Fixed in 0.2.15, and a spec was holding it in place

`#empty_hover` returns `nil`. The protocol declares the result
`Hover | null`, which `docs/CLIENT_BEHAVIOUR.md` now carries as a row
derived from the client's own `protocol.d.ts` rather than from memory —
`CLAUDE.md` requires a claim about the LSP specification to go through
that document, and this one had not.

**`server_spec.rb` had asserted the defect since Task 013**, under a
comment calling `{contents: {value: ""}}` "an empty, non-committal
result rather than a guess". It is not non-committal: it is a `Hover`
that exists and is blank, and a client may render a frame for it. That
assertion is why this entry survived from 0.2.6 to 0.2.15 — the
behaviour was pinned, so nothing could drift it back and nothing could
notice it was wrong.

*A test can hold a defect in place as firmly as it holds a guarantee,
and reading it does not distinguish the two: the comment explaining why
the empty string was correct is what made it look settled.*


## 024.128 Integer arithmetic answers a four-way union

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. Integer arithmetic hovers Integer.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`, `core/lib/ovallsp/local_inferencer.rb`

`price * qty` hovers `Complex | Float | Integer | Rational`: the RBS
overloads are collected without narrowing on the argument type.

**Nothing false is asserted** — the union contains the truth — but it is
not an answer a reader can use, and completion after it offers 209
members drawn from all four.

**Was one of nine bullets under `024.90` until 0.2.14.**

### Fixed in 0.2.15

Both authorities were read rather than remembered:

```
$ ruby -e 'p [(10 * 3).class, (10 * 1.5).class, (2 ** 3).class, (2 ** -1).class]'
[Integer, Float, Integer, Rational]

Integer#*  : (::Float) -> ::Float
Integer#*  : (::Rational) -> ::Rational
Integer#*  : (::Complex) -> ::Complex
Integer#*  : (::Integer) -> ::Integer
Integer#** : (::Integer) -> ::Numeric
```

RBS keys those overloads on the argument's type. The resolver matched on
**shape only** — arity and block presence — so all four fitted a
one-argument call and every return type joined the union, with the
argument sitting right there. `OverloadResolver#narrow_by_argument_types`
reads that key, and `LocalInferencer` threads `env:` through
`#resolve_signature_call` so the argument *types* are available and not
only their count.

**Three restrictions, each of which is the fix being honest:**

- **Only on the exact-shape path.** The fall-back to every overload is
  already an admission that nothing is known about the call, and
  narrowing an admission is inventing.
- **Only where every argument's type is known.** One `Unknown` and the
  whole set stands.
- **It picks the overload; it never touches the return type.** RBS
  declares `Integer#**(Integer) -> Numeric` deliberately, because the
  answer depends on the value — `2 ** 3` is an Integer and `2 ** -1` a
  Rational — and that `Numeric` survives.

**An expectation was written wrong first and the tree corrected it.** The
guard example asserted that an unknown argument leaves every overload
contributing a union; the engine answers `Unknown` for the whole
expression instead, which is a different and more honest thing. Recorded
in the spec, because `CLAUDE.md` asks where an expected value came from
and the answer was "a belief, until it was run".

**Measured**: 269 files of real gem source, both sides on corpus digest
`8143600c…` at different revisions — output **byte-identical**,
`unresolved-constant` 1,485 and `unknown-method` 22 on both.


## 024.130 A hover label drops the namespace when the name was written bare — withdrawn, it does not reproduce

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Withdrawn rather than fixed: the defect is not there. It was
  published to users as a limitation in both languages between the
  0.2.14 split and this correction, which is the only user-visible
  half and it was a false one.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md`

The claim was: in `Billing::Invoice`, `Order.new` hovers `Order` while
`Shipping::Order.new` hovers `Shipping::Order`.

**Driven at 0.2.14 and it does not happen.** `QueryService#type_at` — the
call `#hover_result` makes — returns `Billing::Order` for the bare name,
across four shapes of the scenario: the two classes in separate files,
both nested in one file, the compact `class Billing::Order` form, and
hovering the constant itself. `#hover_lines` renders `type.to_s`, so the
qualified name is what a user sees. Probably fixed by 0.2.5, whose entry
records that it "stopped RBS type names losing their namespace".

### How a claim nobody had checked came to be published

It was one of nine bullets in `024.90`, a grab-bag written several
releases earlier. **0.2.14 split that entry into nine numbered ones and
re-verified none of them** — the split gave each bullet a number, a
`target:`, a `user-visible: yes`, and a paragraph in
`docs/KNOWN_LIMITATIONS.md` and `.ja.md`.

*Splitting a stale grab-bag does not make its contents true. It gives
nine unverified claims the authority of numbered entries, and publishes
the user-visible ones.* Round 3 caught this one; the other eight were
then driven too — **seven reproduce exactly as written**, and `024.131`
was wrong in a different and worse direction.

**The rule this buys:** an entry may not be promoted — split out, given
a target, or marked user-visible — without its reproduction being run
against the tree it is promoted into. Promotion is a claim.

## 024.131 After `||=` on a nil local, hover answers `nil` — a wrong answer, not an absent one

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. Hover now answers the right-hand side's type.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#eval_type`)

```ruby
b = nil
b ||= "x"
b            # hovers `nil`
```

At that third line `b` is a `String`. The engine answers `nil`.

**This entry said "hovers nothing" until 0.2.14 round 3 drove it.** The
difference is the whole of section 0: *a wrong answer is worse than no
answer.* An empty hover is the product declining; `nil` for a local that
is definitely a `String` is the product asserting something false, and
the entry's own wording argued for the lower of the two triages.

**The stated mechanism was wrong too.** It said the `||=` write "is not
joined with the preceding `nil` assignment, so the local has no type at
the position after it". The local *does* have a type — `Types::NilType`
— and nothing is joined or attempted: `#eval_type` has cases for
`Prism::LocalVariableWriteNode` and `InstanceVariableWriteNode` and **no
case at all** for `LocalVariableOrWriteNode`, so the `||=` is not seen
and the earlier `nil` stands unchallenged.

**Direction:** `a ||= b` is `a || (a = b)`, so the type after it is the
union of the non-nil part of `a` and the type of `b` — here `String`.
The missing `eval_type` case is the whole of it; the union rule already
exists for branches.

**Was one of nine bullets under `024.90` until 0.2.14**, and was
published to users as an absent answer for as long as that entry stood.
`024.130` records what the split did and the rule it bought.

### Fixed in 0.2.15

`#eval_type` gained a case for `Prism::LocalVariableOrWriteNode` and
`InstanceVariableOrWriteNode`, and `#or_write_type` implements what Ruby
does — verified against the interpreter before the expectation was
written:

```ruby
b = nil;  b ||= "x";  b.class   # => String   (the write runs)
c = 1;    c ||= "x";  c.class   # => Integer  (it does not)
```

Three cases, and the middle one is why it is a union rather than a
replacement: a local that *may* be nil keeps what it had and gains the
right-hand side. `Unknown` in, `Unknown` out — if the prior type is not
known then whether the write runs is not known either, and a union built
on that guess would be an assertion made from a question that could not
be asked.

**Measured**: 269 files of real gem source (prism, bundler), both sides
over an identical corpus digest with different revisions — output
**byte-identical**, `unresolved-constant` 1,485 and `unknown-method` 22
on both. No regression. The improvement is in hover, which a corpus does
not measure; four examples do.


## 024.133 A positional argument to a keyword-only method reads as nonsense

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.15. The report now says `positional`.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`#argument_count_findings`)

`kwargs("positional")` against `def kwargs(name:, size: 1, **rest)`
reports *takes 0 arguments, but 1 given*, which reads as nonsense beside a
method that plainly takes several. The count is arithmetically right —
zero *positional* parameters — and the sentence does not say so.

**Was one of nine bullets under `024.90` until 0.2.14.**

### Fixed in 0.2.15

`#expected_arity` takes `positional:`, and `#argument_count_findings`
passes the `declares_keywords` flag it already computes. The message
becomes ``takes 0 positional arguments, but 1 given``.

**The number was right and the noun was wrong**, which is why the fix is
one word. Ruby makes the same count and disambiguates it with a clause —
taken from the interpreter rather than from memory:

```
$ ruby -e 'begin; def kwargs(name:, size: 1, **rest) = 1; kwargs("positional"); rescue ArgumentError => e; puts e.message; end'
wrong number of arguments (given 1, expected 0; required keyword: name)
```

Pinned by two examples, and the second is the one that matters: an
ordinary method must *not* gain the word, because "always say positional"
is a different and equally wrong message.


## 024.134 `wait_until_ready` never returns for a non-Rails workspace

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A spec helper, not shipped code. What it costs is that the next e2e example pointed at a non-Rails fixture hangs to its timeout instead of failing with a reason.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/spec/e2e/lsp_client.rb` (`#wait_until_ready`)

It accepts only `ready` and `ready-rails`. A plain Ruby project settles
on `ready-static`, so the helper waits forever.

No example hits it today because every e2e fixture is a Rails one — which
is exactly why it will be found by whoever writes the first that is not.
**Documented nowhere until 0.2.14**: it was one of nine bullets under
`024.90`, whose single `KNOWN_LIMITATIONS` anchor documents the seven
user-visible ones.

**Was one of nine bullets under `024.90` until 0.2.14.**

### Fixed in 0.2.15

`#wait_until_ready` takes a **required** `agent:` keyword. `true` waits
for `ready-rails`; `false` waits only for the cold index to finish and
returns whatever settled state Core then reports.

**Why the caller has to say, rather than the helper working it out:**
`ready-static` means two different things over the wire. `Server`
assigns `@agent_manager` only once the bootstrap returns — deliberately,
and `server_workspace_trust_spec.rb` pins it — so a Rails workspace
reads `ready-static` for the whole of its boot, exactly as a workspace
that will never have an Agent does.

**Verified independently rather than taken from the entry.**
`Server#status_result` answers `indexing`, `ready-rails`,
`agent-unavailable` or `ready-static`; a grep of `core/lib` finds
`"ready"` nowhere. The helper accepted `ready` — impossible — and
`ready-rails` — Rails only.

**Required, not defaulted, and that is the load-bearing half.** Every
existing caller passes `agent: true`, so a default of `true` keeps the
whole suite green and hands the next non-Rails caller the same silent
two-minute wait. `keyreq` raises on that example's first run instead,
and a second example asserts the parameter is `keyreq` for exactly that
reason.

`spec/e2e/plain_ruby_workspace_spec.rb` is the first e2e example pointed
at a workspace that is not a Rails app — which is why this went
unnoticed: every other one drives `spec/fixtures/rails_real`. It needs
neither Rails nor sqlite3, so it runs wherever the suite runs.


## 024.135 `Observation::Runner` deserialises a subprocess's output with `Marshal.load`

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  The subprocess is one this extension spawned, running code from the user's own workspace, so there is no boundary crossed that the workspace itself does not already cross. What it costs is that the shape `024.73` removed elsewhere survives here.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/observation/runner.rb`

`Marshal.load` on a subprocess's output. Adjacent to `024.73` and not
covered by it; the same reasoning applies and the same fix shape would —
`Plugins::Wire`'s JSON envelope.

**Documented nowhere until 0.2.14**, for the same reason as `024.134`.

**Was one of nine bullets under `024.90` until 0.2.14.**

### Fixed in 0.2.16

Reproduced first, because the entry names the call and not the harm: a
result file holding one object with a `marshal_load` hook made
`#read_results` answer **`nil`** — its shape check working exactly as
written — with the hook already having run inside Core. The check runs
after `Marshal.load` has constructed every object the stream named, which
is `024.73` verbatim.

`Observation::Wire` now carries the payload as JSON and rebuilds
`ObservedSignature` from fields it has checked, so validation precedes
construction. Both ends changed in the same commit, as `046` warned they
must: `Harness#dump` writes the envelope, `#read_results` reads it, and a
format skew between them would otherwise be silent.

Two things the entry did not anticipate:

- **`Plugins::Wire` is gone**, deleted with the plugin subsystem, so the
  "same fix shape" had to be written here rather than reused. Both closed
  lists are therefore **narrower** than the ones that boundary used, and
  narrower than `Types`/`SymbolId` can express: `Collector` records two
  method kinds, and `TypeNormalizer` produces four type shapes. A payload
  naming `constant`, a `ProcType` or a `TypeParameter` is a payload this
  Core did not write.
- **A malformed entry rejects the whole payload**, which is the opposite
  of what the plugin boundary did with a malformed declaration.
  `Store#replace_run` is a generation swap, so a partially decoded run
  would install itself as everything the suite observed;
  `#read_results` turns the rejection into its own `nil`, which is the
  outcome that leaves the user's evidence alone.

Pinned two ways: `runner_spec` asserts `Marshal.load` is never called on
this path *and* that a Marshal result file produces no run — both driven
red against the old code — and `pinned_mutations.yml` carries the
all-or-nothing decode, since `filter_map` there would pass every other
example in the file.

## 024.136 A route's optional segments are detected by matching the literal `(.:format)`

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/runtime_agent/agent.rb` (`optionalParts`)

The Agent has Rails' own route object in hand and reads its optional
parts with a substring test:

```ruby
optionalParts: route.path.spec.to_s.include?("(.:format)") ? ["format"] : []
```

Any other optional segment is reported as having none. `get
"/posts(/:page)"` has an optional `page`, and Signature Help for
`posts_path` offers no parameter for it; a route whose format segment is
constrained (`(.:format)` written any other way) loses `format` too.

**What a user sees:** Signature Help understating a path helper's
parameters — a wrong answer, not an absent one, since the helper is
shown with a complete-looking signature.

**Direction:** `route.path.spec` is a `Journey::Nodes::Node` tree and
Rails walks it itself; `route.required_parts` is already read from the
route object rather than pattern-matched, and the optional parts should
come from the same place. The two halves of one question are being
answered by two different methods, which is `042`'s D5 shape.

**Where this came from:** `008.5`'s `## 残課題`, written during Task
008.5 and never converted into an entry, so no release ever considered
it. See `024.139`.

### Fixed in 0.2.16

`parts` minus `required_parts`, both duck-typed the way `requiredParts`
one line above already was. Rails carries both lists and the difference
is the answer, asked of a real 8.1.3.1 route set rather than reasoned
about:

    get "/posts(/:page)", to: "posts#index", as: :paged_posts
    r.parts           # => [:page, :format]
    r.required_parts  # => []

so the answer is `[:page, :format]` where the substring test said
`["format"]`.

A route object that answers neither degrades to no optional parts rather
than raising, which is what an empty list already meant.

**The example is pinned in both directions**: reverting to the substring
test fails it, and it drives the real agent over framed stdio rather than
calling the private method, so it exercises the payload a Core actually
receives. `rails_minimal`'s fake route gained `parts` too — the fixture
exists to mimic Rails' route interface, and the duck-typing would
otherwise have silently taken it to `[]`, losing the `format` the
substring test used to find.

## 024.138 No test mixes a schema change and a model-file change in one batch

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A coverage gap, not a reproduced defect: the code path was read and
  judged correct when this was written, and nothing has exercised the
  combination since.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/ovallsp/server_rails_invalidation_spec.rb`
(`describe "schema changes"`), `core/lib/ovallsp/server.rb`
(`#refresh_all_models` and the per-model path)

A schema change refreshes every model in one bulk round trip; a model
file change refreshes that model. `server_rails_invalidation_spec.rb`
covers each alone and the coalescing of several model changes. Nothing
covers a batch holding both, where a bulk refresh and a targeted one are
queued for the same generation.

**Direction:** one example, and it is cheap. The value of writing it is
that the two paths reach the same registry through different call sites,
and `024.138` is exactly the shape the mutation manifest exists for —
whichever ordering rule the code relies on is currently pinned by
nothing.

**Where this came from:** `008.6`'s `## 残っているKnown Issue`. See
`024.139`.

### Fixed in 0.2.16

Confirmed first that nothing covered it: of the thirteen examples in the
file that name one path or the other, not one names both, and every
schema example passes a single-element batch.

Two examples, one per ordering of the two changes within the batch, and
the decision they pin is the `elsif` in
`#handle_did_change_watched_files` — the bulk refresh subsumes the
targeted one. The fixture's two payloads deliberately disagree (the bulk
one reports a column the targeted one does not), so the registry's final
state says which path installed the model; a fixture where both answered
the same would have passed under either decision.

Watched failing with the `elsif` split into a second `if`: both examples
report `expected: nil, got: "User"` — the targeted refresh running as
well. `pinned_mutations.yml` carries that mutation, which is the layer-2
half `024.121` asks for.

## 024.139 Task documents grew their own findings sections, outside the register

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Purely a record-keeping defect. Its cost is that three real findings
  sat unregistered for the whole of 0.1.x and 0.2.x -- no release
  considered them, because nothing that decides a release's scope reads
  a task document's own trailing section.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `docs/design/tasks/008.5-runtime-and-index-corrections.md`,
`docs/design/tasks/008.6-agent-and-index-hardening.md`

`008.5` ended with `## 残課題` and `008.6` with
`## 残っているKnown Issue` — six items between them, written when this
register did not yet exist and left there after it did. They are a
second collection point for exactly what `024` holds, and
`deferred_findings_spec.rb` cannot see them.

**What the six turned out to be**, checked against the tree in 0.2.14
rather than assumed:

| item | verdict |
|---|---|
| `optionalParts` matches `(.:format)` literally | **live** → `024.136` |
| `WorkspaceIndex#search` scans linearly | **live** → `024.137` |
| no schema-plus-model batch test | **live** → `024.138` |
| `AgentProcessManager` `#stop`/`#mark_unavailable` TOCTOU | resolved — the final write goes through `@status_mutex` and wins unconditionally, argued at `agent_process_manager.rb:318` |
| Runtime Plugin mechanism 未着手 (twice) | **false** — Task 018 shipped it; `server_plugins_spec.rb` and `Plugins::CURRENT_PROTOCOL_VERSION` |

Three of six were real and unregistered; two restated a "not started"
that has since been done. Both sections' **items** are gone, replaced by a pointer to this entry
and a sentence saying where findings go. The headings themselves remain,
and that is the right outcome rather than a shortfall — a reader who
opens 008.5 looking for its residual issues finds out where they are.

*This sentence said "Both sections are deleted" until 0.2.18, and
`## 残課題` is still at 008.5:104 and `## 残っているKnown Issue` at
008.6:89 (`024.171`). The countermeasure it named — "a check can assert
that `docs/design/tasks/*.md` other than 024 carry no findings section
of their own" — was never built by the work it pointed at, and is now
`core/spec/meta/task_findings_section_spec.rb`, asserting the thing that
actually matters: a findings section has to say where findings go.*

**The general form:** a document that records work has no reason not to
end with what is left over, which is why this happened twice in adjacent
files and why it would happen again. `046`'s C4 is the countermeasure —
the register's parser moving to `scripts/` so a check can assert that
`docs/design/tasks/*.md` other than `024` carry no findings section of
their own.

## 024.140 A scripted edit doubled a register entry, and every check stayed green

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that the register -- the
  document this project uses to decide what is still broken -- was
  committed in a corrupted state and the whole meta suite called it
  clean.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `core/spec/meta/deferred_findings_spec.rb`

Moving a paragraph from `024.69` into `024.68` was done with a python
slice whose end boundary came from `str.find`, which returns `-1` rather
than raising when its terminator is absent. `b[lo:-1]` is not the
paragraph, it is everything to the end of the entry; and the "removal"
that followed pasted the block back. **`024.69`'s entire body ended up
in the file twice**, with a stray heading and yaml block in the middle
of it.

It was committed. Everything passed:

| check | why it saw nothing |
|---|---|
| heading count / index order | the duplicate carried `#` rather than `##`, so the heading count did not change and `reindex_findings` had nothing to reorder |
| yaml key validation | the entry's own metadata block was untouched |
| `register-entries` measured claim | derived from heading count, which was right |
| `KNOWN_LIMITATIONS` coverage | keyed on entry number, and the number still existed once |
| full suite, 2,341 examples | none of them reads an entry's prose |

Every check was about an entry's **metadata**. Nothing was about its
**body**, so a body could be pasted twice and the file remained
well-formed by every definition the tree had. Found by an unrelated
grep printing the same sentence at two line numbers.

**The first countermeasure** was one line of the body that must appear
exactly once: an entry states one `**Area:**`. Checked by planting the
actual defect rather than a synthetic one.

### It happened again the same day, and that moved the countermeasure

Rewriting `07-vscode-extension.md`'s §12, the end boundary passed to the
same helper was `"\n"` — which matches at the top of the file. The
result was **the entire document pasted twice**. Same failure, different
file, an hour apart.

So the `**Area:**` rule was aimed at the symptom: it guards one file, and
the class is "a scripted edit whose boundary silently misses". The
countermeasure is now `core/spec/meta/duplicate_headings_spec.rb`, which
is the check both instances would have failed and which needs no rule
about how edits are performed.

**What exactly it guarantees is stated there, and deliberately not
restated here.** This paragraph used to carry a one-line version of it,
and `024.206` is that line claiming more than the check did — a
guarantee written in two places goes wrong in one of them.

Two things it had to get right, and both were found by running it:

- **Fenced blocks are not headings.** `10-ai-execution-guide.md` quotes a
  task template and a report template that each contain `## Tests`. A
  line-based scan reports that file, and the natural response would be to
  exempt it — `024.126`'s trap exactly. It tracks fences instead.
- **It found a real one immediately.**
  `040-0.2.10-what-an-answer-was-computed-from.md` ended with a second
  `## Review` heading and its opening paragraph, and nothing after it —
  an orphaned stub of the section that already exists 100 lines above.
  Removed.

*Two rounds, one place, then a mechanical countermeasure at the level of
the class rather than the instance — `CLAUDE.md`'s rule, applied to a
defect in the documents rather than in the engine.*

**Why not "be careful with slices".** Because the failure mode is
silent: `find` returning `-1` produces a *plausible* result, and the
plausible result went through a full suite and a commit message that
truthfully said 0 failures. `CLAUDE.md`'s rule about a green suite not
being a blast radius is the same observation from the other side — here
the suite was green because nothing it contained could have been
otherwise.

## 024.141 `PUBLISHING.md` documented the publish command that shipped a corrupt v0.1.2

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Not something an editor user meets, but the closest thing to it a
  document can be: following this document by hand would have published
  an artifact whose own payload hash did not match, which users of
  v0.1.2 did see as a "may be corrupted" warning.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `docs/PUBLISHING.md`, `docs/PUBLISHING.ja.md`

Both languages said `release.sh` "runs `vsce publish --target
darwin-arm64 --pre-release`". It does not, and `release.sh`'s own
comment at the call site says that form must **never** be used:

```
vsce publish --packagePath "$VSIX_PATH" --pre-release
```

`vsce publish --target ...` runs `vscode:prepublish` (`copy-core` →
`tsc`) again on top of the run `npm run package` already did, rebuilding
the vendored native extensions from scratch. That compilation is not
byte-reproducible, so the upload is a different binary from the one just
smoke-tested and hashed — which is how v0.1.2 shipped a
`PLATFORM_MANIFEST.json` that did not match its own payload. The bug was
found by downloading the published VSIX and rehashing its `core/`.

**What makes this its own entry rather than a typo.** The fix for
v0.1.2 went into the script *and its comment*, and stopped there. The
document describing the script kept the pre-fix command for twenty-five
releases. A fix applied at the place that runs and not at the place that
*tells a person what to run* leaves the failure reachable by anyone who
reads instead of executing — and `PUBLISHING.md`'s whole audience is
someone doing this by hand.

`DOCUMENTATION_MAP` has no row for "the release procedure changed",
which is why nothing pointed at it. `046`'s C6 is where that goes.


## 024.142 A corpus run did not say what it had run

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets, and everything the maintainer's decisions rest
  on: five recorded false corpus results, three of which produced
  confident findings that did not exist.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/corpus_diagnostics.rb`

`026-0.2.1-review-loop.md` records five false results, and the shape is
the same every time — **the run was not what the reader thought it
was**:

| what happened | what it produced |
|---|---|
| diff computed from a file still being written | 79 invented findings |
| diff between two *different* corpora, one holding this repo's `core/lib` | 10 invented |
| a `cd` that persisted, so both sides ran from the baseline worktree | reported a real fix as doing nothing |
| two runs started concurrently, writing the same output files | implausibly low totals |
| a rewritten script leaving both sides in the baseline tree | the two sides came out *identical* |

**None would have been caught by re-reading the numbers.** Two were
caught because a number was implausible and one because it contradicted
a spec already watched failing. That is not a method.

**Fixed** by making the run state what it is, on stderr — stdout is the
stream being diffed and is byte-for-byte unchanged:

- `cwd`, `revision`, `dirty-tracked-files` (with a warning when
  non-zero, because a dirty tree means `revision` does not describe the
  code about to run), `ovallsp-version`, `signature-root`;
- `corpus-files` and **`corpus-sha256`, a digest of the file list** —
  which is what makes "both sides were given the identical corpus"
  checkable rather than asserted;
- a per-code count, so a control needs no separate pass.

**And two refusals**, both of which produce an empty or near-empty diff
that reads as *"this change altered nothing"* — the most expensive wrong
answer this script can give:

- a corpus matching no `.rb` files;
- a path that does not exist. This one was live: anything not a
  directory was taken as a file, so a typo'd path became a corpus of
  one, and the run looked like a run.

**`--expect-control=CODE:N`** states before the run what a category the
change cannot affect must come out at, and fails the run if it does not.
0.2.1's control was `unresolved-constant`, identical at 9,550 on both
sides. Given on the command line rather than checked afterwards, because
a control read after the fact is a control chosen to agree.

Pinned by `core/spec/meta/corpus_diagnostics_spec.rb` over a throwaway
corpus — including that two runs over *different* corpora produce
different digests, which is the one guarantee a single run cannot
demonstrate.

## 024.143 "Did I run everything?" was answered from memory

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A working-practice defect. Its cost is commits made on partial
  evidence -- twice in one session, both already pushed.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/preflight.rb`, `CONTRIBUTING.md` + `.ja.md`

Seven things must be true before a commit here: the full suite, the two
real-Rails-backed suites having actually *run*, the home-path scan, the
documentation-link resolver, the register index, the rescue verdicts and
the site links. They live in seven places and nothing but a person held
the list together.

Twice in the 0.2.13 session that person was wrong the same way: the
suite had been run for the directory being worked in, it was green, and
the full run afterwards was not. Both times the tree was already pushed.

**Neither was carelessness in a form more care would fix.** The list is
longer than the working memory of whoever is mid-task, and the failure
mode is not "forgot to run tests" — it is "ran tests, and the thing that
ran was not the thing that decides".

`scripts/preflight.rb` runs all seven, prints what each one ran, and
installs as a pre-commit hook with `--install`. Two properties it needed:

- **A skipped check is reported, never assumed passed.** The real-Rails
  and capability suites skip in full without local `rails` and `sqlite3`
  while `rspec` still exits 0. It reads **each example's status**
  rather than a non-zero example count — `CLAUDE.md` already said to do
  this by hand, which is exactly the kind of instruction that gets
  skipped.
- **Its own output must survive a locale-less shell.** The first version
  crashed with `invalid byte sequence in US-ASCII` on a failure message
  containing Japanese — so the gate that exists to catch a failure died
  on one. `scripts/generate_sbom.rb` carries the same fix, found the
  same way in Task 023.8. Verified under `LC_ALL=C`.


## 024.144 A design document restating a manifest is two copies with nothing between them

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. What it cost is that the document describing the extension
  described an extension that does not exist, and was read and cited
  for a year without anyone noticing.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `core/spec/meta/design_doc_drift_spec.rb`,
`docs/design/docs/07-vscode-extension.md`

Measured at 0.2.14, against `vscode/package.json` and
`clientPresentation.ts`:

| `07` restated | how many were real |
|---|---|
| 8 command ids | **0** |
| 10 settings | 2 |
| 7 status-bar strings | **0** — the extension produces five, none of them these |
| 2 activation events | 2 of the 3 that exist |

**Nothing could have noticed.** A design document listing command ids is
a second copy of `package.json`, and there was no relationship between
the copies — no generation, no check, not even a comment on either side
saying the other existed. `CLAUDE.md`'s countermeasure rule names this
exact shape: *two scanners that had to agree about the same text,
replaced by one both read.* Here the two cannot be collapsed into one —
a design document is not generated from a manifest and should not be —
so the relationship is made instead.

`design_doc_drift_spec.rb` compares four lists against the code that
owns them, and `plugin-sdk.md`'s registration methods against
`core/lib/ovallsp/plugins`. Each example is set equality both ways, so
an id added to the manifest and not to the document fails as loudly as
the reverse.

**Checked by restoring the pre-0.2.14 command list** and watching it
fail, rather than by trusting that a passing check means anything.

**A sixth example exists because the other five compare two lists**, and
two empty lists are equal. A renamed heading or a reformatted fenced
block would make every extractor return nothing and every comparison
pass — which is the failure this whole release is about, arriving inside
the check written to prevent it.


## 024.145 Re-deriving the example count was three hand edits per commit

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that a correct guard made every
  commit that adds an example more expensive than it needed to be, and
  the cost was paid at the end of an eight-minute suite run.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/documented_counts.rb`, `scripts/preflight.rb`,
`core/spec/meta/documented_counts_spec.rb`

Three documents state `core/`'s example count, and
`documented_counts_spec` fails when any disagrees with the running
suite. **The guard is right.** The figure was 895 for six releases, then
1,776 taken mid-branch, then 1,833 with two commits still to come; a
line saying "measure this every time" sat beside it through all three.

What it left in place was the work: adding one example means editing
three documents, in two languages, by hand — and finding out you had to
**at the end of an eight-minute run**, since the check needs the whole
suite to know the number. In one 0.2.14 session that happened four
times.

**Fixed** by `rspec --dry-run`, which loads every spec file and counts
without running one: **0.4 seconds** against the suite's eight minutes,
and the same number `RSpec.world.example_count` reports from inside a
real run — which is asserted rather than assumed.

- `ruby scripts/documented_counts.rb` re-derives it into all three.
- `--check` is the first check `preflight.rb` runs, so a stale count is
  a second-long failure at the start rather than an eight-minute one at
  the end.
- The document list and its patterns live in the script, and the spec
  reads them from there. Writing that table twice — inside the release
  whose C4 is *"two readers, one text, two grammars"* — would have been
  a poor joke.

**Why this is `kind: friction` and not a defect.** Nothing was ever
wrong in the tree; the numbers were true at every commit. What was wrong
is that keeping them true was a tax on the wrong activity, paid at the
worst moment. The maintainer's standing instruction for this pass is
that *this* counts as a problem, and that raising one without recording
it is not allowed.

## 024.146 A script crashes under a locale-less shell, on the input a check exists to report

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal, and sharp: the failure mode is not a wrong answer but a
  crash, and it happens precisely when a check has something to say.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/utf8.rb`, `core/spec/meta/script_encoding_spec.rb`

Ruby returns a String in `Encoding.default_external`, which is whatever
the invoking shell's locale says. Under `LC_ALL=C`, a cron job, or a CI
step with no locale, that is **US-ASCII** — and the first `String#[]`,
`#scan` or `#include?` against a byte above 127 raises `invalid byte
sequence in US-ASCII`.

This tree is substantially non-ASCII: the Japanese documents, the
Japanese halves of `KNOWN_LIMITATIONS`, `SUPPORT_MATRIX` and
`CONTRIBUTING`, and the Japanese failure messages the suite prints.

**The shape is what makes it worth a countermeasure.** The script does
not read the file wrongly. It *crashes* — on exactly the input the check
exists to report. `preflight.rb`'s first version died this way while
printing a suite failure whose message contained Japanese: the gate
built to catch a failure, killed by one.

**Found four separate times, fixed four separate times, each fix
correct and local and no help to the next:**

| where | how it was found |
|---|---|
| `generate_sbom.rb` | Task 023.8, running the release gate under a locale-less shell |
| `preflight.rb` | its first real run |
| `documented_counts.rb` | its first real run, twenty minutes later |
| a hand-run probe | the same session, again |

`CLAUDE.md` says the third occurrence buys a countermeasure rather than
a third fix. `scripts/utf8.rb` is one line — `Encoding.default_external
= Encoding::UTF_8` — which fixes every `File.read` and every `IO.popen`
in the process at once, rather than each call site remembering.
`script_encoding_spec.rb` requires it of every script in `scripts/`, and
requires it to come *before* anything that reads or shells out.

**Two things learned writing the check itself:**

- A `.rb` file's source encoding is UTF-8 whatever the locale says;
  `ruby -e` source is read in the locale's encoding. The first version of
  the probe used `-e` with a Japanese literal in it and failed for a
  reason unrelated to what it was testing.
- The example that proves the fix works is paired with one that proves
  the same probe **fails without it**. Otherwise it demonstrates only
  that Ruby works.


## 024.147 Every check was blind to a file until it was committed, and the commit gate runs before that

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal, and it is how 0.2.14 shipped a red suite under a commit
  message stating 2,374 examples and 0 failures. Nothing a user runs is
  affected; everything this project uses to decide whether a change is
  sound was.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/repo_files.rb`,
`core/spec/meta/untracked_visibility_spec.rb`

Ten call sites across nine files — two scripts and seven specs, one of
which has two — enumerated their input with
`git ls-files`, which lists **tracked** files only. A file you have just
written is untracked until `git add`. And `scripts/preflight.rb`, the
gate whose entire purpose is to run *before* a commit, runs in exactly
that window.

**So the suite could be green before a commit and red after it**, having
examined different sets of files. Not hypothetically:

- `release_gate_spec.rb`'s planted example asserted that a fabricated
  script name is absent from the haystack it builds. The haystack is
  built from `git ls-files core/spec scripts`. While the spec file was
  untracked it was not in its own haystack and the example passed;
  `git commit` put it there and the example began failing.
- `preflight` ran, reported **2,374 examples, 0 failures**, and the
  commit was made on that. The commit message says so. It was false the
  instant it was written.
- Five independent reviewers in round 1 opened with it.

**Demonstrated as a class, not inferred from the one case.** An
untracked Markdown file carrying a duplicated heading *and* a citation
of a document that has never existed passes `duplicate_headings_spec`
and `check_doc_links` both, each reporting the tree clean:

```
3 examples, 0 failures
check-doc-links: every documentation path resolves.
```

**Fixed** by `RepoFiles.list`, which adds `--others --exclude-standard`
— files git does not yet track and would not ignore — and by converting
all ten sites to it. `untracked_visibility_spec.rb` pins three things:
that a brand-new file is listed, that a `.gitignore`d one still is not,
and that **nothing enumerates the repository the old way**, because the
defect returns looking like ordinary code.

**What this says about the other checks in this release.** Every one of
the nine was verified by planting the defect it hunts — and every one of
those plants was written into a file that was untracked at the time. The
verification was real, but it was performed in the blind window. Each
was re-run after this fix.

### Two commits shipped red, not one

This entry originally named `release_gate_spec` as "the one that had
actually been affected". **Round 3 checked out every commit on the
branch and ran the meta suite at each.** Two are red, from the same
cause:

| commit | red because |
|---|---|
| `26243e0` (`046 A0`) | `check_doc_links.rb` reports its own two comment lines as citations resolving to nothing. It was untracked when preflight ran, so it did not scan itself; `git commit` put it into its own input. `doc_links_spec` shells out to it — **1 example, 1 failure**. Repaired at `1bf897b` |
| `7c92b05` (`046 B`) | `release_gate_spec`'s planted name inside its own haystack. Repaired at `23196a8`, the commit this entry documents |

`26243e0`'s message also states "inspects 527 tracked files and 661
citations" — numbers taken inside the same blind window. A clean
checkout of that commit prints 529 and 663, and exits 1.

**Neither the commit that repaired the first nor this entry said HEAD
had been red.** The first was noticed because a spec failed under it;
the second only because round 3 was asked to *re-derive rather than
read*, and ran the suite at every commit instead of trusting the record.
That is the difference between a claim and a measurement, arriving
inside the entry written about exactly that.

*The general form is worth more than the fix: a check's answer must not
depend on git state that changes between running it and committing. If
it does, the run that gates the commit and the run that CI performs are
answering different questions.*


## 024.148 The check for "did the suite actually run" could not fail in the case it existed for

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. Its cost is that the local gate for "a capability row is
  true because its E2E example ran" would have passed on a machine
  where that example never ran.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `scripts/check_suites_ran.rb`,
`core/spec/meta/suites_ran_spec.rb`, `scripts/preflight.rb`,
`.github/workflows/ci.yml`

Three spec files skip themselves when their environment is absent, and
`rspec` still exits 0:

| file | needs |
|---|---|
| `spec/integration/real_rails_spec.rb` | local `rails` + `sqlite3` |
| `spec/e2e/capabilities_spec.rb` | the same fixture |
| `spec/meta/client_behaviour_spec.rb` | `vscode/node_modules` |

`preflight.rb` guarded this by asserting a **non-zero example count**.
That cannot work, and the reason is one sentence: **a skipped example is
still an example.** Measured — a fully skipped file reports:

```
2 examples, 0 failures, 2 pending
```

exit status 0. So the count is 2, the guard passes, and the check whose
entire purpose is to catch this case cannot fail in it. It is
`CLAUDE.md`'s "an assertion that cannot fail is not a test", written by
someone who had just quoted that rule in the same file's header.

**The working logic already existed** — forty lines of Ruby embedded in
`ci.yml`, reading the JSON formatter's per-example status and treating a
pending example as a skip unless its message says `NOT YET`. Embedded in
YAML, it was tested by nothing and callable by nothing else, so the
second caller wrote a weaker rule rather than reusing it. `042`'s D8
shape: a thing assembled twice diverges.

**Fixed** by extracting it to `scripts/check_suites_ran.rb`, which
`ci.yml` and `preflight.rb` both run, and `suites_ran_spec.rb` tests
against the exact all-skipped shape. Verified against a real report with
all 16 `real_rails` examples marked pending, which the old rule accepted
and the new one refuses.

**The `NOT YET` exemption is kept and is not a weakening.**
`docs/EXTENSION_CAPABILITIES.md` defines a `NOT YET` row as specified,
carrying an E2E row, and currently failing or pending — a state the
document tells authors to use. Failing on those would make a documented
state unexpressible. The environment skip is what this is about, and its
message does not say `NOT YET`.

*Found by review round 1. Two of five reviewers reached it
independently, and neither was looking at the same thing.*


## 024.149 A review harness that reports "nothing found" when its own post-processing crashed

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that a review round which had
  found 84 defects returned the number 0, and the only thing between
  that number and being believed was reading the diagnostics.
target: 0.2.14
released-in: 0.2.14
```

**Area:** the review harness for 0.2.14's rounds (a `Workflow` script,
not tracked here), `docs/design/tasks/046-0.2.14-making-the-record-true.md`

Round 1's harness passed **promises** where the API wanted **thunks**,
so all thirty verification calls failed. The round's return value was:

```json
{"method":"diff","raised":0,"survived":[],"refuted":[]}
```

**`raised: 0` meant "the post-processing crashed", and it is indistinguishable
from "five reviewers read the change set and found nothing".** The
findings existed the whole time and were recoverable only from the run's
journal. Had the summary been taken at face value, the round would have
been recorded as clean — and round 1 had found a red suite at HEAD under
a commit message claiming 2,374 examples and 0 failures.

**This is the release's own subject, arriving in the tooling that
measures the release.** `CLAUDE.md` already carries it three times over:
*a checker that cannot see the thing it checks reports exactly what a
working checker reports when nothing is pinned*; *a green suite can be
green because it did not run*; *catching a failure and continuing is not
the default*. None of those is about a review harness, and that is the
gap — the rules are written about the product's code and the harness is
not the product's code.

**Two things follow, and only the second is worth much:**

- The immediate fix is a corrected script, which is nothing.
- The durable one: **a round's result is read from its journal, not from
  its summary.** The journal records each agent's actual return value;
  the summary is a computation over them and can fail on its own. The
  same distinction as a corpus run's stdout versus the script that
  diffs it, and `026` is four recorded instances of trusting the second.

**Two more process failures from the same round, recorded because the
standing instruction for this pass is that raising without recording is
not allowed:**

- **The tree was mutated mid-round — twice, and the second time after
  this entry was written.** Round 1: `046` was edited while five
  reviewers read the tree. Round 2: **this entry itself** was being
  written into the register for the whole of it — the round ran
  02:02–05:26 and the edit was committed at 05:45. `CLAUDE.md` says
  never to run the hunk sweep while another agent is mutating the tree;
  it does not say the same about reviewers, and it should.

  What was verified after round 2 was `git status --porcelain`, which
  was empty — and that was then written up as "the tree was verified
  clean and at the same HEAD afterwards", which reads as a statement
  about the *run*. It is a statement about one moment after it. Three
  round-3 agents and one round-2 finding recorded the dirty tree
  independently, and one of them put it exactly right: *"Working tree
  was NOT clean when I finished, and none of it is mine."*

  The cost is bounded but real: the attackers' subject was code, so the
  findings stand, but **any count of tracked content taken during the
  round is unreliable** — `check_doc_links` and `check_home_paths` read
  the file that was changing. Round 2's numbers are re-derived before
  being acted on.

  *Writing the entry did not prevent the recurrence, and the reason is
  worth stating: the rule lives in a document about reviewing, and the
  moment of violation is the moment of writing something else down.
  This is the same shape as `024.126` — a rule that is correct and
  arrives after the act.*
- **Five reviewers each ran the full suite concurrently** — six `rspec`
  processes, load average 9.6, and a foreground `preflight` starved into
  a timeout. Nothing told them the suite costs eight minutes or that
  four others were doing the same. Rounds 2 and 3 tell each agent the
  cost, ask for single spec files, and state the full run already
  recorded at that revision — which is `CLAUDE.md`'s corpus-list rule
  (*say what has been measured and at which revision*), not an
  exclusion.


## 024.150 `AGENTS.md` paraphrases `CLAUDE.md`, and the paraphrase drifts

```yaml
status: fixed
released-in: 0.2.18
kind: defect
user-visible: no
user-visible-note: >
  Internal. What it costs is that the file a session reads first can
  state something the file it paraphrases has since corrected, and
  nothing compares them.
```

**Area:** `AGENTS.md`, `CLAUDE.md`

`AGENTS.md` is a condensed operational restatement of `CLAUDE.md`'s
rules — twelve bullets, each a shortened form of a section. Two copies
of one set of rules, with no relationship between them, which is the
shape this release's C4 and C5 are both about.

**One measurement, from round 1 of 0.2.14's review:** `AGENTS.md`'s goal
paragraph named the release being prepared and its branch, and named the
*next* release while HEAD was on the current one — in the paragraph the
file itself designates as the defence against a compaction losing the
path. Fixed by making it derivable (`git branch --show-current` and the
highest-numbered task file), and pinned by `agents_pointer_spec.rb`.

**That is one drift, found by accident.** Nothing looked for others, and
nothing would.

**Why it is open rather than done.** `046` asserted that the paraphrase
would shrink in 0.2.14. It grew — by 15 words at `8f1d4f4^`, to 1,562
in the very commit that wrote the claim, and to 1,856 by 0.2.18
(`024.172`; dated, because an undated one is what that entry is
about). The assertion sat in
the plan as if it were a disposition until round 1 measured it — which
is the same defect as the ones this release exists to fix, so it is
recorded rather than quietly executed. Restructuring the file a session
reads first is also an **add**, and `CLAUDE.md` says *during a review
loop, fix; do not add*.

**Direction, and it is not "shrink it".** The question to answer first is
whether the paraphrase carries anything `CLAUDE.md` does not, because
that decides between two different jobs:

- If it is purely a restatement, it should become pointers, and the
  drift class disappears with it.
- If it carries operational sequencing a full read would bury — which is
  the argument for having it at all — then it stays and needs a
  *relationship*: a check that every rule it names still exists in
  `CLAUDE.md`, in the shape `client_behaviour_spec.rb` already uses for
  a claim stated in one document and pointed at from everywhere else.

Measure the overlap before choosing. Deciding without that is what
produced the assertion this entry replaces.

**Measured in 0.2.16, and the answer is the second branch.** `AGENTS.md`
is 1,769 words against `CLAUDE.md`'s 5,833, in 16 top-level bullets, 11
of which cite `CLAUDE.md`. Three rules have **no counterpart anywhere in
`CLAUDE.md`** — YAGNI/no speculative implementation, re-read the
instruction files after a compaction or handoff, and consult `.claude/`
— and neither does the opening section (the one-paragraph product
purpose, the standing patch-publish permission, the `042` pointer, the
maintainer's role). So it is not a pure restatement: it stays, and what
it needs is a relationship.

**Left open because the obvious relationship does not hold.** The cheap
form — for each bullet claiming `CLAUDE.md` carries the rule, require
one distinctive token shared with it — was tried against the tree and
gives three false positives of eleven: two bullets cite `CLAUDE.md` as a
file to *read* rather than as the rule's home, and the test-first bullet
is a genuine paraphrase carrying no identifier at all. A check with that
error rate is one somebody switches off, which is the shape `024.192`
records. What is wanted is a relationship the paraphrase itself
declares, and that is a design question rather than a missing check.

**Re-triaged in 0.2.17** (`024.276`). Two copies of one set of rules with no relationship between them. A citation check was tried and gives three false positives in eleven, which is the error rate that gets a check switched off — so what is wanted is a relationship the paraphrase itself declares. A design question about this repository's own documents; nothing a user meets, and nothing a capability release should be carrying.
### Fixed in 0.2.18: the relationship is declared, not inferred

Each bullet that restates a `CLAUDE.md` rule now ends with an HTML
comment naming the section it restates, and
`core/spec/meta/agents_restates_spec.rb` fails when `CLAUDE.md` no
longer has one. Twelve bullets carry one; the spec also requires at
least ten, because a check whose subject is its own input passes
trivially once the input is deleted.

**Watched failing both ways.** Renaming one `CLAUDE.md` heading in a
scratch copy produced:

```
AGENTS.md restates sections CLAUDE.md no longer has: ["Review cadence (mandatory)"]
```

**Declared rather than inferred, which is what this entry was waiting
on.** The inferred form measured three false positives in eleven: two
bullets cite `CLAUDE.md` as a file to *read*, and the test-first bullet
is a genuine paraphrase carrying no shared identifier. Under a
declaration all three disappear without an exception list — the two
pointer bullets simply carry no marker, and the paraphrase says what it
paraphrases instead of a scanner guessing from wording. Zero false
positives is what stops it being switched off (`024.192`).

**What it does and does not catch.** It catches a renamed or deleted
section, which is the drift that has a mechanism. It does not catch a
section whose *content* changes while its heading stands — that is
still a reader's job, and this entry does not claim otherwise.


## 024.152 A leak check counted every descriptor in the process, and flaked under load

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  A test defect. Nothing a user meets, and the guarantee it pins --
  that a failed plugin load leaks no pipe -- was never in doubt.
target: 0.2.14
released-in: 0.2.14
```

**Area:** `core/spec/ovallsp/plugins/loader_spec.rb`
(`#load_static kills and reaps the plugin child …`)

Found by a full-suite run failing while eight verification agents were
saturating the machine. It passed alone five times, passed under the
whole plugins directory, and passed under **its own failing seed** —
so it is not order-dependent, it is load-dependent.

The measurement was:

```ruby
before_fds = Dir.children("/dev/fd").size
...
leaked = Dir.children("/dev/fd").size - before_fds
```

`/dev/fd` is the **whole process's** descriptor table. Anything else
opening or closing one between the two reads moves the delta —
rspec's own output, a lazily-opened file, a finalized IO. On an idle
machine nothing does; under load something does.

**Fixed by asking the question the example is about.** What
`#run_isolated` can leak is a *pipe pair*, so it now takes the set of
open **pipe** descriptors before and after and requires the difference
to be empty. Other activity in the process stops mattering, and a
failure names the descriptors instead of only counting them.

Still catches the real thing: deleting the two
`ChildProcess.close_quietly` calls from the `ensure` gives
*"#run_isolated leaked 1 pipe descriptor(s) (6)"*.

*`CLAUDE.md` says a flake found while working on something else is
fixed in the same session rather than deferred. This one is also worth
its own entry because the defect is a measurement whose scope was wider
than its question — the same shape as several of round 2's findings,
arriving in a spec rather than a check.*


## 024.153 A quarter of the open work is in no release, and 0.3.0 has become where the rest goes

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Withdrawn rather than fixed: re-driven in 0.2.15 and it does not
  reproduce. What it said when filed, and what the parser read until
  0.2.18 because this key was written twice: 18 of the untargeted
  entries are open, user-visible defects, published to users as
  limitations with no release undertaking to fix them.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (the
`target:` key), `docs/design/tasks/045-0.3.0-scope.md`,
`docs/ROADMAP.md`

Measured at 0.2.14, from the register itself:

| | count |
|---|---|
| open entries targeting **0.3.0** | **35** |
| open entries with **no target at all** | **26** |
| of those, open *and* user-visible | **18** |

And that is before `024.151`'s 55 confirmed findings, round 3's
untriaged remainder, and 37 incidental findings — none of which is yet
an entry.

**Two failures, and the second is the one that matters.**

*`target:` is optional, so "nobody has decided" and "deliberately
unscheduled" are the same value.* 26 entries are in no release. Nothing
distinguishes an entry waiting on a decision from one waiting on work,
and no check can, because the absence of a key carries no argument.

*`0.3.0` has become the default.* `045` calls it "the first release that
may add capability" and lists nine promises. It also carries 35 open
defects. **A release cannot be the one that adds capability and the one
that absorbs everything unscheduled**, and the roadmap promises the
first while the register assigns the second.

**How this connects to the rest of 0.2.14.** The maintainer's diagnosis,
recorded in `046`: the version boundaries became hard to reason about
*because* things that should already have been true were not. This is
that, measured. Every release since 0.2.6 has been an accuracy release
that also had to decide, entry by entry and without a rule, what
belonged to it — and the residue went to 0.3.0 or nowhere.

**Direction, and it is a decision before it is work:**

1. **Every open entry gets a `target:`, and the key stops being
   optional** — `deferred_findings_spec` can require it once every entry
   has one. An entry deliberately unscheduled says so in a value
   (`target: unscheduled`) with the reason in its body, which is an
   argument a reader can disagree with; an absent key is not.
2. **Then decide what 0.3.0 is.** Either the accuracy work moves to a
   0.2.15 and 0.3.0 becomes genuinely capability-only, or 0.3.0 accepts
   being an accuracy release and the nine promises move to 0.4.0.
   *Choosing is the maintainer's; what this entry establishes is that
   the present arrangement is not a third option — it is the absence of
   a decision, and `045` and `ROADMAP` currently disagree about which
   release 0.3.0 is.*

*Raised by the maintainer during 0.2.14's close, from the observation
that the version boundaries had become awkward to handle. The numbers
above are what that turned out to be.*


## 024.154 Findings recorded in 046 are truncated mid-sentence in rounds 1 and 3, in the same commit that untruncated round 2

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Corrected in 0.2.18 by making the record say what it is**, which is
the only repair available: the bodies were cut when they were written,
and the journal they came from is gone.

Re-run against HEAD, and **half of this entry no longer reproduces**.
Round 1: all 18 items still end mid-token, at 574–643 characters —
confirmed. Round 3: its findings are prose bullets, not the `^ \``
shape the entry's own reproduce command assumes, and none of them is
truncated. The command was written against a layout the file no longer
has.

Three sentences were false and are now true:

- the note under round 2 said "Recorded in full and untruncated" of a
  list that is round 2's alone, in the same commit that wrote round 1's
  eighteen with the same cut. It says which list it means now.
- round 3's own summary said round 1's list was "Now written, in full,
  including the refutations". It was written truncated.
- the round-1 list carried no note at all. It now says it is cut, where
  the cut lands, and that commit `8f1d4f4`'s message records the round
  in prose — 84 raised, 30 deduplicated, 18 survived, 12 refuted — which
  is where a reader can get the substance the bullets stop short of.

**Not reconstructed**, deliberately: a bullet completed from memory
reads exactly like one that was never cut, and this register already
carries what that costs.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md (lines 526-671, 1042-1380)

024.151 defers 55 open findings with the sentence "The individual breaks are recorded in `docs/design/tasks/046-0.2.14-making-the-record-true.md`", so 046 is the only place 0.2.15 can read them from. Round 3 found that round 2's 70 findings had been cut at ~400 characters mid-sentence and fixed them; commit 577704b did that and, in the same commit, wrote round 1's 18 findings and round 3's 65 finding bodies with the same cut. All 18 round-1 items are 574-643 characters and every one ends mid-token; 26 of round 3's 65 bodies do the same. The cut lands on the consequence clause and on the reproduction, which is the part a reader needs. 046:686-689 states "Recorded in full and untruncated" — true of round 2 only, and the sentence reads as a claim about the list.

**Reproduce:** awk 'NR>=526 && NR<=671' docs/design/tasks/046-0.2.14-making-the-record-true.md | grep '^- \*\*\[' | wc -l -> 18; the same piped through `sed 's/ *$//' | grep -cvE '[.!?)"`]$'` -> 18. awk 'NR>=1014' <same file> | grep -E '^ `' | sed 's/ *$//' | grep -cvE '[.!?)"`]$' -> 26 of 65. Tails: `sed 's/.*\(.\{35\}\)$/... \1/'` shows `Plugins::CURRENT_PROTOCOL_VERSIO`, `STATUS_LABELS\|STA`, `is not true of thr`. git log -S'Recorded in full and untruncated' --oneline -- <same file> -> 577704b, the same commit that added round 1's list.

**Re-triaged in 0.2.17** (`024.276`). Rounds 1 and 3 of `046` are cut mid-token — all 18 round-1 items and 26 of round 3's 65 — in the same commit that untruncated round 2, and the cut lands on the consequence clause and the reproduction. `024.151` defers 55 findings by pointing here, so this is the difference between a deferral that can be picked up and one that cannot. A record repair, on the patch line.

## 024.155 A register heading the entry grammar does not match is skipped rather than failed, so an entry can exist and be checked by nothing

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/deferred_findings.rb` (`ENTRY_HEADING`, `METADATA_BLOCK`, `#headings`, `#entries`), `core/spec/meta/deferred_findings_spec.rb` ("parses every entry", "indexes every entry"), `scripts/reindex_findings.rb` (`#number_of`)

`DeferredFindings`' header comment states the rule the whole guard was rebuilt for: "An entry with no block is a failure, not a skip. The old guard silently dropped a heading it did not recognise, so an entry could be added and never checked. `parses every entry` compares the block count to the heading count for exactly that reason." It cannot do that. `parses every entry` computes `headings(deferred) - entries(deferred).keys`, and both sides are derived from the *same* pattern — `ENTRY_HEADING` and `METADATA_BLOCK` each require `024.N` followed by a literal space. A heading outside that shape is absent from both sets, so the subtraction is empty for it and the comparison is vacuous exactly where it was meant to bite. Three checks that could have caught it independently do not: `reindex_findings.rb` uses a looser pattern (`/\A## (024\.[0-9R]+)/`, no trailing space), so it happily renders an index row for the malformed entry with `?` for status and an empty title, which then makes `indexes every entry` and `is in numeric order with its index current` both pass. The result is a heading that reads as an entry to every human and to the generated index, and to no check. Note this is not 024.151's class: no check was edited or narrowed, and a coverage floor would not help, because the two readers agree with each other while both being too narrow. The fix has the shape `CLAUDE.md` calls for — the two ends must not share the assumption they are supposed to cross-check. `headings` should recognise deliberately more than `entries` does (any `^## 024\.` line), so that anything the strict grammar cannot parse shows up in the difference.

**Reproduce:** In a clone at aa1185f: `printf '\n## 024.<n>: A finding written with a colon after its number\n\nBody prose, no yaml block.\n' >> docs/design/tasks/024-deferred-review-findings.md`. Then `ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); puts (DeferredFindings.headings(md) - DeferredFindings.entries(md).keys).inspect'` → `[]`. Then `ruby scripts/reindex_findings.rb` (rewrites, adding `| [`024.<n>`](#024200-) | ? | — | |`) and `ruby scripts/reindex_findings.rb --check` → `current`, exit 0. Then from `core/`: `bundle exec rspec spec/meta/deferred_findings_spec.rb` → 37 examples, 0 failures, and `bundle exec rspec spec/meta` → 192 examples, 0 failures, 6 pending — byte-identical to the clean HEAD run. Control: the same body written as `## 024.<n> A finding` (space, no colon) fails `parses every entry`.

### Fixed in 0.2.16

Reproduced first: the colon form gave an empty difference, the space
form gave the heading, exactly as written.

`headings` reads `HEADING_LINE` now — any heading line beginning with
the number's prefix — while `entries` still reads the strict
`METADATA_BLOCK`. The two sides of `parses every entry` no longer share
the assumption they exist to cross-check, and the colon form is named in
the failure.

The index was the other half. `reindex_findings.rb` read the number with
a pattern *looser* than the checks', so it rendered a row for a heading
they could not parse, and that row is what made `indexes every entry`
and `is in numeric order with its index current` both pass about an
entry nothing had looked at. It refuses now:
`ReindexFindings.blocks_of` raises `Unparsable`, split out of `rebuild`
so an example can hand it a register-shaped string instead of the one
file on disk.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.156 The evidence extractor recognises only .rb/.sh/.js and test:, so TypeScript tests and CI job names — the sole evidence for eight gates — are never checked

```yaml
status: fixed
released-in: 0.2.16
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
```

**Area:** core/spec/meta/release_gate_spec.rb (`RELEASE_GATE_EXECUTABLE`, line 38; the dead `.test.ts` branch, line 116), docs/RELEASE_CHECKLIST.md

The Task 023 gate table's evidence column holds, by its own header, CI job names, specs, or release.sh steps. The extractor matches only a backticked path ending .rb/.sh/.js, or a backticked `test:` npm script. A citation of any other shape is not reported as unrecognised — it is silently treated as absent, and the row is reported clean. Gates 8, 9, 10 and 19.1 cite TypeScript test files as their sole evidence (versionInfo.test.ts, clientLifecycle.test.ts, workspaceTrust.test.ts), and gates 2, 3, 14 and 15 cite CI job names (`core`, `secret-scan`, `package-contents-inspection`); none is checked. So the delayed-start race test, the E1/C1→E2/C2 update test, the payload-hash test and the Workspace Trust manifest test can each be deleted or renamed with the gate that names them still green. The spec contains the evidence that this was believed covered: line 116's `next if base.end_with?("_spec.rb", ".test.ts")` can never fire, because the regex cannot produce a capture ending in `.test.ts`. This is distinct from 024.151's disable-ability class: nothing is switched off, the check runs and asserts a clean result over rows it never looked at.

**Reproduce:** ruby -e 'RE=/`([A-Za-z0-9_.\/-]+\.(?:rb|sh|js))`|`(test:[a-z:]+)`/; p "`clientLifecycle.test.ts`".scan(RE).flatten.compact' => []. Scan the whole of docs/RELEASE_CHECKLIST.md with the same regex: 15 captures, none ending .test.ts (the dead branch). Then in docs/RELEASE_CHECKLIST.md rewrite clientLifecycle.test.ts -> neverExisted.test.ts, versionInfo.test.ts -> ghost.test.ts, vscode/src/test/unit/workspaceTrust.test.ts -> vscode/src/test/unit/deletedLastYear.test.ts, and secret-scan / package-contents-inspection -> no-such-job; `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 3 examples, 0 failures. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The extractor recognises all four shapes the
column's header allows -- a script path, a TypeScript test, an npm
script and a CI job name -- and each is checked against a real list
rather than a glob: the tracked file list, `vscode/package.json`'s
`scripts` keys, and the job names parsed out of `.github/workflows/`.
A CI job is matched by its *citation form* (the table's "CI の `x`
ジョブ") rather than by intersecting backticked words with the job
list, because an intersection would make a renamed job stop being a
citation, which is this defect one level in.

The half that stops the class coming back is a **floor per shape**
rather than one total: this entry's own instance was a branch for a
shape the pattern could not produce, and a single count cannot see
that while three other shapes keep it healthy. Watched failing: the
entry's reproduction (renaming the two TypeScript tests, the
workspace-trust path and the two CI jobs) now names all five rows,
and killing the TypeScript pattern fails the shape floor by name.

## 024.157 A git subprocess in a throwaway repository obeys the inherited GIT_DIR, so the suite commits to the real repository

```yaml
status: fixed
released-in: 0.2.16
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
```

**Area:** `scripts/repo_files.rb`, `core/spec/meta/untracked_visibility_spec.rb`, `core/spec/meta/doc_links_spec.rb`, `core/spec/meta/release_script_guard_spec.rb`, `scripts/check_home_paths.rb`, `scripts/preflight.rb` (the `--install` hook)

Git exports `GIT_DIR` and `GIT_INDEX_FILE` to every hook. In a **linked worktree** they are absolute paths to that worktree's gitdir and index (measured, git 2.55.0); in an ordinary repository `GIT_DIR` is unset and `GIT_INDEX_FILE` is the relative `.git/index`, which is why this is invisible until someone works in a worktree. Nothing in this tree scrubs them: `grep -rn 'GIT_DIR|GIT_INDEX_FILE|GIT_WORK_TREE' scripts core/spec .github` returns nothing. `RepoFiles.git` spawns `IO.popen(["git", ...], chdir: root)`, and the three spec files that build throwaway repositories use `system("git", "-C", dir, ...)`. **`chdir:` and `-C` change the working directory; they do not override `GIT_DIR`.** So `git add -A` writes the throwaway repository's contents into the real worktree's index, and `git commit` lands a commit on the branch that worktree has checked out -- a commit that *deletes* every tracked file the throwaway repository does not have. Three things make it worse than a red suite: (1) **the suite stays green while it does this** -- `RepoFiles.list` unions `ls-files` with `ls-files --others`, and `--others` enumerates the filesystem, so it returns nearly the right answer from the wrong repository and the assertions still pass; (2) `scripts/check_home_paths.rb` enumerates through the same helper for `--tree` and runs `git log --all` in `ROOT` for `--messages`, so the public-repository privacy guard reads whichever repository `GIT_DIR` names and reports clean about it; (3) the vector is documented -- `ruby scripts/preflight.rb --install` installs exactly such a hook and `CONTRIBUTING.md` tells contributors to run it. This is `CLAUDE.md`'s "a test that deletes things, and an assertion that could not fail" returning by a different route: the path from a harmless-looking `Dir.mktmpdir` to a real repository runs through an environment variable no call site mentions, and reading either the spec or the helper alone cannot reveal it. Fix shape is the one that section already prescribes -- contain it where the spawn happens: one helper that every `git` invocation in `scripts/` and `core/spec/` goes through, unsetting `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_COMMON_DIR` and `GIT_NAMESPACE`, plus the same unset in `HOOK`.

**Reproduce:** ``` cd "$SCRATCH" && git init -q main0 && cd main0 git config user.email t@e.com && git config user.name T mkdir src && echo precious > src/important.rb && git add -A && git commit -qm init git worktree add -q -b featurex ../wt G="$PWD/.git/worktrees/wt" cd /path/to/OvalLSP/core GIT_DIR="$G" GIT_INDEX_FILE="$G/index" bundle exec rspec spec/meta/untracked_visibility_spec.rb # => 3 examples, 0 failures git --git-dir="$G" log --oneline featurex # => a second commit "one" git --git-dir="$G" show --stat HEAD # => `<probe>.md` | 1 + # src/important.rb | 1 - ``` Those two variables are exactly what git sets for a pre-commit hook in a linked worktree -- confirm with a hook that prints them (absolute in a worktree, `GIT_DIR` empty and `GIT_INDEX_FILE=.git/index` in a normal repository). Under the same environment `bundle exec rspec spec/meta/doc_links_spec.rb` fails 3 of its examples, so the hook also rejects the commit for a reason that is not about the commit. `git worktree list` on this repository currently shows seven linked worktrees under the scratch directory, so the precondition is this project's ordinary working practice, not a hypothetical.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16, and it reproduced exactly as written.** Run under
the two variables git hands a hook in a linked worktree,
`untracked_visibility_spec.rb` reported "3 examples, 0 failures" and
left a commit on the other repository's branch deleting its tracked
source.

Contained where the spawn happens: `RepoFiles` unsets `GIT_DIR`,
`GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_OBJECT_DIRECTORY`,
`GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_COMMON_DIR` and
`GIT_NAMESPACE` at every `git` invocation, and every call site in
`scripts/` and `core/spec/` goes through it -- including
`check_home_paths`' two backticks, `hunk_sweep`'s `git apply -R` and
`git checkout`, `measure_typing_publishes`' provenance lines and
`measured_claims_spec`'s `git show`. The three specs that built
throwaway repositories share one `core/spec/support/throwaway_repo.rb`
instead of three hand-written sequences. `preflight --install`'s hook
and `release.sh` unset the same list in shell, as a second layer.

Three checks, each watched failing: `untracked_visibility_spec` now
fails on a git spawn anywhere in `scripts/` or `core/spec/` that does
not go through the wrapper (planted, red, removed); an example asks
git, under a poisoned `GIT_DIR`, which repository it is in, and
`pinned_mutations.yml` pins it -- deleting the scrub makes that
example fail. The first version of that example did **not** fail
under the mutation, and `check_pinned_mutations.rb` said so: `list`
unions in `--others`, which enumerates the filesystem, so the wrong
repository gives nearly the right answer. The fixture now plants a
tracked file in the decoy, which only the poisoned index can produce.

Re-run afterwards under the same two variables, the whole `spec/meta`
suite passes and the other repository is byte-for-byte untouched.

## 024.158 The executed PAT-mode example passes on a release.sh that only warns, because its exit status comes from a later check misreporting a non-repository as dirty

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/release_script_guard_spec.rb` lines 158-182, `vscode/scripts/release.sh` lines 51-56 and 78-84

The PAT-mode example exists because "semantic mutations are invisible to any text match", and it asserts only `status.success? == false` plus `output.include?("readable beyond its owner")`. Neither is tied to the PAT check. Demote the refusal to `if [ "${OVALLSP_STRICT_PAT_MODE:-0}" = "1" ]; then exit 1; fi` and soften the echo to a warning, and the example still passes: the message is still printed, and the non-zero status comes from the clean-tree check further down. The mechanism is a second defect in its own right — the fixture's REPO_ROOT is the tmpdir's parent, not a git repository, so `git diff --quiet` fails with "not a git repository", `if ! …` reads that failure as truth, and release.sh announces "the tracked tree has uncommitted changes" about a tree it could not read. A failure to *ask* is turned into an assertion about the user's tree, which is CLAUDE.md's swallowed-failure rule arriving from the other side. The text half is no protection either: `block_containing(/8#077/)` stops at the first `^\s*fi\s*$`, which after the demotion is the nested one, so the unreachable `exit 1` is still inside the window. Fix: assert the refusal happens *at* that check (exit before any git call, or `expect(out).not_to include("uncommitted changes")`), and make the clean-tree condition distinguish "git says dirty" from "git could not answer".

**Reproduce:** Scratch mirror as above. Replace release.sh's `exit 1` on line 55 with ` if [ "${OVALLSP_STRICT_PAT_MODE:-0}" = "1" ]; then` / ` exit 1` / ` fi`, and change line 52's message to `warning -- $PAT_FILE is mode $PAT_MODE -- readable beyond its owner.` → 10 examples, 0 failures. Then run the fixture by hand: `mkdir -p fx/scripts; cp release.sh fx/scripts/; printf tok > fx/.vsce-pat.local; chmod 644 fx/.vsce-pat.local; fx/scripts/release.sh; echo $?` → prints the warning, then "release.sh: the tracked tree has uncommitted changes" and "fatal: not a git repository", exit 128.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16

Two halves, and the second reaches outside the suite.

The executed example asserted `status.success? == false` plus the
message, neither of which is tied to the PAT check. It asserts
`exitstatus == 1` and that nothing a later check prints appears --
both branches of the clean-tree check name the tracked tree, so one
string covers them. Watched failing against the demoted script this
entry describes.

`release.sh` reads `git diff --quiet`'s exit status instead of
`if ! git ...`: 0 clean, 1 dirty, above 1 "could not answer". The
third refuses too, saying that is what happened, rather than
announcing uncommitted changes about a tree git never read. Against
the PAT fixture's non-repository tmpdir it used to print "the tracked
tree has uncommitted changes" and exit 128; it now names the exit
status git gave it.

The window example is re-anchored on the deciding condition: the
status is captured before the branch now, so a window opened at the
first `diff --quiet` would have walked back to the check above and
pinned that one's refusal.

## 024.159 The measured-claim marker and the number a reader sees are separate strings, so the prose can say anything while the marker verifies

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** A new example compares the marker's integer with the numbers in the sentence it annotates, thousands separators stripped. The marker is re-derived every run and the sentence beside it is not, so they have to be the same number or the marker is proof of nothing.

It found one immediately: `docs/design/docs/02-architecture.md` had the marker at the start of a line and the number at the end of the previous one, so the two were never adjacent to begin with. The marker sits on the number's line now, which is the convention the `documents:` markers already follow.

Pinned in both directions, against planted text rather than the tree: a sentence that agrees and a sentence that has drifted, plus a thousands-separated one, because a rule that failed on every large number would be relaxed away rather than kept.

**On the mutation manifest.** These five decisions live in `core/spec/meta/measured_claims_spec.rb`, and `scripts/check_pinned_mutations.rb` mutates `core/lib/` and `scripts/` only -- a spec file is refused, because a mutation there could delete the example that would have caught it. So each is pinned by a distinguishing example and by nothing underneath it. The direction is to move this machinery into `scripts/`, beside `DeferredFindings`, `HomePaths` and `DocumentedCounts`, which is where every sibling scanner already lives and is what `024.181` found the cost of: the scanner in the spec and the scanner in the script diverged, in the same file, ninety lines apart. Recorded under `024.121`.

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, and the `matches what the tree actually says` example), `docs/design/docs/02-architecture.md` (threading section)

`claims` captures the integer inside `[measured marker for name]` and compares that to the deriver. The number in the sentence it annotates is an unrelated hand-typed string that nothing reads. So the guarantee as literally stated holds — the marker's value is re-derived every suite run — while the thing the guarantee exists for, the number a reader takes away, is free to rot, and rots invisibly because the marker beside it reads as proof that it was checked. This is the file's own stated failure mode, 'the check passes for a reason other than the one it states': `documented_counts_spec`, the precedent cited in this file's header, does not have this shape — `DocumentedCounts.stated(document)` (scripts/documented_counts.rb:42) compares against the number as written in the prose, which is the form that actually holds. The architecture document already shows the wider version: the same count is written three times in the threading section — line 269 「現在 31 箇所あり」, line 291 「上の 31 箇所のうちの1つ」, line 300 「上の 31 箇所に」 — and exactly one carries a marker; the other two are precisely the unmarked hand-typed numbers the marker mechanism was built to abolish, in the section whose stated purpose is that it stopped contradicting the code. Fix shape (from the finding): require the marker's value to appear in the prose it annotates, the way `DeferredFindings#documents?` (scripts/deferred_findings.rb:182) insists an anchor's line carry content in front of it — noting that here the marker sits on the line *after* the sentence it belongs to, so a same-line rule alone would not fit the one live instance.

**Reproduce:** From the repo root: `perl -i -pe 's/現在 31 箇所あり/現在 999 箇所あり/' docs/design/docs/02-architecture.md` (line 269; leaves the marker on line 270 at 31), then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures, with the threading section now reading 「`core/lib` には現在 999 箇所あり」. `git checkout -- docs/design/docs/02-architecture.md`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.160 Counts in 046 that describe this tree carry no basis, are not marked, and several are stale at HEAD

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Corrected in 0.2.18 by dating the file rather than the numbers.**

The header claimed "Every count below was re-derived at that revision",
which reads as a live guarantee and is not one: the file carries zero
`<!-- measured: -->` markers and nothing re-derives anything in it. Its
header now says so — that every number in it describes `6bc31b9`, that
several have since moved, that one quantity has two denominators, and
that a reader must re-derive before quoting one forward.

**Not marked live, deliberately.** A `<!-- measured: -->` marker with a
present-tense deriver would rewrite these numbers on every release,
which is `024.184`'s defect and is exactly how `024.172`'s (c) came to
be wrong. A release record is a claim about the revision it was written
at; the repair is to say which revision, not to keep it current.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md (lines 3-4, 25-30, 42, 131, 278, 295, 336, 421)

The file's header says "Measured at `6bc31b9`. Every count below was re-derived at that revision." The file contains zero `<!-- measured: -->` markers, nothing re-derives any of its numbers, and at HEAD several are wrong: (a) :25 "66 of its 88 resolved entries" — 90 at HEAD (88 was true only at 8f1d4f4..577704b, 74 at 6bc31b9); the 66 still holds; (b) :27 "Exactly one is cited from nowhere outside it" — three at HEAD (024.144, 024.146, 024.152); (c) :421 "fires on zero of 74 entries" — a second, different denominator for the same quantity in the same file; (d) :295 "+6,256 / -4,588 — a net increase of 1,668 lines" — true at 577704b, now +7,157/-4,731, net +2,426; (e) :42 "1,753 lines an agent must read at session start" — the plausible set sums to 1,514 and no set is defined; (f) :131 "249 edits across 41 files" — `0.3.0` occurs 151 times across 35 tracked files; (g) :30/:334/:336 "7 sentences repeat", "52.7% comment", "47% of the file" — no method stated for any; (h) :278 records make-final-review-bundle.sh at 918 while the ledger's own 3,975 total is only reachable using git's 919. Round 3 corrected six numbers in this file and introduced (a), (b) and (d) in doing so.

**Reproduce:** grep -c '<!-- measured: -->' on the file -> 0. ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); puts DeferredFindings.resolved(md).keys.length' -> 90 (74 at 6bc31b9, 88 at 577704b). git diff --shortstat main..HEAD -> 7157/4731. wc -l CLAUDE.md AGENTS.md README.md docs/design/docs/01-product-requirements.md docs/DOCUMENTATION_MAP.md -> 1514. git grep -c '0\.3\.0' -- . ':!core/vendor' ':!vscode/node_modules' -> 35 files / 151 lines. git show main:make-final-review-bundle.sh | grep -c '' -> 919 vs wc -l 918.

**Re-triaged in 0.2.17** (`024.276`). A header claiming every count was re-derived at a named revision, above a file with no markers and several counts that are wrong at HEAD. 0.2.17 fixed the two this release touched — the acceptance-box count now has a deriver, and `024.161`'s and `024.165`'s numbers went with their entries — and the rest are still to do. Patch-line work: it is about this repository's own record, not about what the extension answers.

## 024.161 046's round-3 correction states that the "4,000 lines of revert" phrase "is removed"; the phrase is still the file's closing sentence

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** The phrase is gone from the closing sentence, so the round-3 correction that says it was removed is now true. The rule the sentence carries -- grep the tree for the thing being deleted before committing the deletion -- stands on `024.47` alone, which is what it always rested on. No replacement number was written in: a fresh count about a historical change set is a fresh claim, and the correction did not need one.

Pinned by `core/spec/meta/record_corrections_spec.rb`, which counts the phrase and requires exactly the one occurrence that is the correction. Watched failing against the file at the commit before the fix: two occurrences.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:302-303, :1405-1406

Round 3 corrected the deletion ledger and closed the correction with: "The closing phrase \"this change set is 4,000 lines of revert\" is not what the diff shows and is removed." The phrase was not removed. It is the last clause of the document (:1405-1406), under "Two rules over the whole thing": "...and this change set is 4,000 lines of revert." So the file now contains both a false statement about the change set and a statement that it was deleted — a correction that records work it did not do, in the release whose title is making the record true. The diff is +7,157/-4,731, a net increase of 2,426 lines.

**Reproduce:** grep -n '4,000 lines of revert' docs/design/tasks/046-0.2.14-making-the-record-true.md -> two hits: :303 (saying it is removed) and :1405 (the phrase itself). git diff --shortstat main..HEAD -> 105 files changed, 7157 insertions(+), 4731 deletions(-).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.162 046's recorded departure from the `drive` round rests on a false enumeration of the change set

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:497-502, :1381-1386

041 asks that one review round use `drive`. 046 records a departure justified by "This change set alters no engine answer — the only `core/lib` edits in the range are two comment rewrites and one deleted tombstone comment, and the corpus is not consulted by anything that changed". Both halves are false as stated. `core/lib` has 16 changed files (+38/-47): one comment rewrite (receiver_resolution.rb), one deleted tombstone (engine.rb), and thirteen one-line citation repoints plus query_service.rb. And the corpus consumer changed in this very change set: scripts/corpus_diagnostics.rb is +125/-4 with a new 119-line spec (C8), and 046's own C8 note records that building it exposed a live hole where a mistyped path became a corpus of one — exactly what a `drive` round would have exercised. The conclusion (no engine answer changed) survives: zero non-comment, non-blank changed lines in core/lib. The defect is that a departure from a mandatory cadence rule is recorded twice, restated "because it must be re-checked each round", and rests on an enumeration nobody re-checked.

**Reproduce:** git diff --numstat main..HEAD -- core/lib | wc -l -> 16. git diff main..HEAD -- core/lib | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#' | grep -vE '^[+-][[:space:]]*$' | wc -l -> 0. git diff --numstat main..HEAD -- scripts/corpus_diagnostics.rb core/spec/meta/corpus_diagnostics_spec.rb -> 125/4 and 119/0.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16 by deriving the enumeration, and keeping one copy of it

Reproduced at `6bc31b9..6155cf4`, the revisions the departure was
written between: 16 changed files under `core/lib` (+38/-47), of
which thirteen are one-line citation repoints, plus
`semantic/query_service.rb`, one comment rewrite and one deleted
tombstone -- and `scripts/corpus_diagnostics.rb` at +125/-4 with a
new 119-line spec, so the corpus consumer did change inside the
range.

`046`'s departure paragraph carries that enumeration with the
revisions named, so it can be re-derived rather than believed, and
the restatement under "Review cadence" points at it instead of
repeating it. Both copies were wrong, which is what a justification
kept in two places does. The conclusion is unchanged and re-derives
on its own: zero non-comment, non-blank changed lines under
`core/lib` in that range.

## 024.163 046's round-2 header asserts every attacker worked in a clean tree, and 046's own recorded findings say the tree was dirty and changing throughout

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.15
```

**It was already fixed, in 0.2.15, and carried open for two releases after that.** `a6f20a6` replaced the round-2 header with the opposite statement -- "The working tree was dirty for almost all of this round, and it was mine" -- naming the window, the entry being written through it, and the fact that what was actually verified was `git status --porcelain` afterwards. It says in as many words that the old sentence "has been corrected to this one".

Driven at 0.2.17: the assertion appears nowhere in the round-2 section. What remains are two quotations of it -- the corrected header quoting the sentence in order to say it was wrong, and a round-3 finding quoting it to report it. Both are the record working.

**So the closing paragraph this entry carried was false.** It said the entry had been driven during 0.2.16's backlog sweep, with a control in its own fixture, and still reproduced. It had been fixed before 0.2.15 shipped. `024.276` is the entry for how fifty-four of these came to say that.

Pinned in 0.2.17 by `core/spec/meta/record_corrections_spec.rb`, which reads the round-2 section and requires the correction rather than the claim. The example cannot be watched failing against `HEAD`, because `HEAD` is already correct -- it fails against `a6f20a6`'s parent, and what it defends is the sentence coming back.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:675-677, :762-764, :1378, :1384, :1386

The round-2 header states "Every attacker worked in a clone or reverted, and the tree was verified clean and at the same HEAD afterwards", and commit 54b7274's message repeats it. Four findings recorded in the same document say the opposite: a round-2 [medium] entry ("Concurrent agents left the working tree modified; the dirty set changed three times during one review round", naming a `continue-on-error: true` added to ci.yml's suites-ran job and RELEASE_CHECKLIST test filenames rewritten to files that do not exist, both later reverted, while an attacker was measuring), and three round-3 agents each reporting five modified tracked files at session end that were none of theirs. CLAUDE.md's measurement rule names this hazard explicitly ("Never run this hunk-by-hunk sweep while another agent is mutating the same working tree. Concurrent mutation invalidates both results. Sequence them."), and the round-2 finding says it made the hunk-level half of that reviewer's work unsafe to perform. The header is the sentence a later reader uses to decide how much round 2's results are worth.

**Reproduce:** sed -n '675,677p' docs/design/tasks/046-0.2.14-making-the-record-true.md against sed -n '762,764p' of the same file; grep -n 'Working tree was NOT clean\|dirty set changed three times\|already dirty when this session started' on the same file -> four hits contradicting the header.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.164 046 states finding totals whose stated dispositions do not account for them

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Corrected in 0.2.18 for the one of the three that can be**, and the
correction is a subtraction rather than an addition.

The opening audit's arithmetic reproduces exactly: 15 + 9 + 28 = **52 of
122**, and the other 70 have no stated disposition anywhere. The
document now says that, in the paragraph that states the totals, rather
than leaving it to be summed — it *was* summed, by a reader two releases
later, and not by whoever wrote it.

The other two are not repairable from here. Round 2's 15-fixed/55-open
split cannot be reconstructed: no item carries a marker and the commits
that "named them" name them in prose. Round 3 states no disposition at
all. Inventing either would produce a record that reads as verified and
is not, which is `024.154`'s reason in the other direction.

What that leaves is `024.151`'s reader, who gets 70 items of which some
number are already done. That is now visible in the document rather than
discoverable by arithmetic, which is as far as this can honestly go.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:10-13, :691-694, :1042-1380

Three places state a finding total and then fail to account for it. (1) The opening audit: "Nine auditors over disjoint areas produced 122 findings; each non-trivial one was then given to a second agent whose instructions were to refute it. 15 survived adversarial check, 9 were refuted, 28 low-severity carried forward" — 15+9+28 = 52, and the other 70 have no stated disposition anywhere. (2) Round 2: "15 are fixed in this release, named in the commits that fixed them. The remaining 55 are open under 024.151" — none of the 70 items carries a fixed/open marker, so the split is unverifiable from the record and a reader picking up 024.151 in 0.2.15 gets 70 items of which 15 are already done and no way to tell which. (3) Round 3: 63 findings in six subsections plus 37 incidental, with no disposition statement at all. 024.151 is the deferral that points here, so this is the cost paid by the release scoped against it.

**Reproduce:** sed -n '8,14p' docs/design/tasks/046-0.2.14-making-the-record-true.md and add the three figures -> 52 of 122. awk 'NR>=672 && NR<=1013' <same file> | grep -c '^- \*\*\[' -> 70, with no fixed/open marker or strike-through on any. awk 'NR>=1014' <same file> | grep '^#### ' -> six subsections summing to 63, none with a disposition line.

**Re-triaged in 0.2.17** (`024.276`). Three finding totals in `046` whose stated dispositions do not add up to them, in the file `024.151` points at for 55 deferred findings — so whoever picks that up gets a list of which some are already fixed and no way to tell which. The repair is to write the dispositions or to say plainly that they are not recoverable; either is record work on the patch line.

## 024.165 046 keeps 138 acceptance boxes on the stated ground that no box has ever been ticked; 56 are ticked, 13 of them in a file this change set edited

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** The decision stands and the reason is replaced. Boxes are ticked across this tree's task files, `008.5` among them -- inside the stated range, and one of the two files that change set edited -- so "no box has ever been ticked" could not carry it. What does carry it was already in the same sentence: they are stage milestones rather than tracked obligations, and `RELEASE_CHECKLIST` quotes one as its own charter.

The 138 itself now has a deriver (`unticked-acceptance-boxes-001-022`) and a marker, so the one number in the bullet is recomputed rather than trusted -- half of `024.160`, taken here because this is the line it was already about. The correction deliberately writes no new count, for the same reason.

Pinned by `core/spec/meta/record_corrections_spec.rb`, with a control asserting the decision is still recorded so deleting the whole bullet does not pass. The needle is the bullet, not the sentence: two of `046`'s own findings quote the false claim in order to report it.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:319-321, docs/design/tasks/008.5-runtime-and-index-corrections.md:90-102

The "What is kept" section keeps all 138 unticked acceptance boxes in tasks 001-022 with: "No box has ever been ticked in this repository's history; they are stage milestones, not tracked obligations." The 138 re-derives exactly. The justification does not: 56 boxes are ticked across nine task files, and 13 of them are in docs/design/tasks/008.5-runtime-and-index-corrections.md under `## 完了基準` — inside the stated 001-022 range, and in one of the two files this change set edited. The other 43 are across eight 023.* files. Ticking is established practice, so the argument for keeping 138 empty boxes rests on a false fact. The decision may still be right; the reason given for it is not.

**Reproduce:** grep -rc -- '- [x]' docs/ | grep -v ':0$' -> 9 files, 56 total, 13 in 008.5. grep -h -- '- [ ]' docs/design/tasks/00*.md docs/design/tasks/01*.md docs/design/tasks/02[0-2]*.md | wc -l -> 138. sed -n '89,103p' docs/design/tasks/008.5-runtime-and-index-corrections.md shows the 13.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.166 Two rows of 046's checks table describe checks that were built differently, and the "changed shape" list omits one

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:365-366, :370-372, scripts/reindex_findings.rb:54-66, scripts/corpus_diagnostics.rb:81-89

The checks table is what a reader auditing the release compares the built checks against, and two of its nine rows do not describe what shipped. C4's row says "extract `DeferredFindings` into `scripts/`; delete `metadata_of` **and its false comment**" — `metadata_of` is still defined at scripts/reindex_findings.rb:54, called at :66, and asserted at core/spec/meta/deferred_findings_spec.rb:113-114; it was rewritten as a one-line delegation to `DeferredFindings.entries` and its comment replaced with a true one, which is a better outcome than deletion but is not the row. The section immediately below, "Four changed shape once built, and the changes are the part worth reading", lists C2, C6, C7 and C8 — C4 changed shape and is absent. C8's row says the check fails on "`026`'s three recorded false results" while the header comment this same change set added to scripts/corpus_diagnostics.rb says "`026-0.2.1-review-loop.md` lists five" and enumerates five; CLAUDE.md is consistent with five.

**Reproduce:** grep -rn 'metadata_of' scripts/ core/spec/ -> 4 hits, definition at scripts/reindex_findings.rb:54. sed -n '365,372p' docs/design/tasks/046-0.2.14-making-the-record-true.md against sed -n '81,89p' scripts/corpus_diagnostics.rb and CLAUDE.md's "A measurement is a claim" section.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16, and the third limb was inverted

Limbs 1 and 2 reproduced as written. `046`'s C4 row described a
deletion that did not happen: `metadata_of` is a one-line delegation
to `DeferredFindings.entries` with its false comment replaced, which
is a better outcome than deletion and is what the row says now. C4 is
added to the "changed shape" list, which had four items and needed
five.

Limb 3 reproduced backwards, so the correction goes the other way.
`026-0.2.1-review-loop.md`'s table lists **three** false measurement
results, which makes `046`'s C8 row right; the false sentence is
`scripts/corpus_diagnostics.rb`'s header, which attributed all five
to that file. `CLAUDE.md` carries the other two, both from 0.2.1's
last day, and the comment says so now.

## 024.167 046's three review rounds record no per-place tracking, so CLAUDE.md's same-place rule cannot be applied and was not

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Recorded in 0.2.18 in the place the rule asks for.**

Nothing can retroactively add per-place tracking to three rounds that
did not keep it. What can be said, and now is, in `046`'s own header:
the rounds kept none, so `CLAUDE.md`'s "two rounds in a row on the same
place" rule could not be applied and was not — and the two places that
qualify are named, `release.sh`'s clean-tree refusal and the
`RELEASE_CHECKLIST` evidence column, each hand-fixed where the rule asks
for a mechanical countermeasure.

That is the whole of the available repair. The rule's value is in the
round that applies it; a release four releases past cannot supply that,
and pretending otherwise would make the record read as if the rule had
been followed.

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:490-1380

CLAUDE.md's "Two rounds in a row on the same place" rule requires tracking, per round, which code each finding is about, and — the first time a place is found twice in a row — a mechanical countermeasure of a different shape rather than a third hand-fix, with a rollback and a register entry if the place is found again after that. 046's review-rounds section records no per-place tracking and never invokes the rule; the only mentions in the file are at :38 (about 024.15/024.47 in CLAUDE.md, not this release) and inside one round-2 finding body at :940. At least two places qualify across three consecutive rounds. release.sh's clean-tree refusal: round 1 fixed C6's self-naming hole, round 2 filed three findings against the same `block_containing` decision (one noting the rule applies), round 3 confirms at :1042 that the whole refusal block is still deletable with release_script_guard_spec at 8 examples, 0 failures. scripts/check_doc_links.rb: round 1 (105 relative links outside the check, a rescue that reported nothing), round 2 (SKIP an unpinned constant), round 3 (the "all 19 dangling citations live in source comments" claim false, and the SHORTHAND count wrong).

**Reproduce:** grep -in 'same place\|same-place\|Two rounds in a row' docs/design/tasks/046-0.2.14-making-the-record-true.md -> three hits, none in the review-rounds section's own bookkeeping. Then read :940 and :1042 against round 1's release_gate_spec finding at :617, and the three rounds' check_doc_links.rb findings at :644, :724 and :1040.

**Re-triaged in 0.2.17** (`024.276`). `CLAUDE.md`'s same-place rule needs per-round tracking of *which place* each finding is about, and `046`'s three rounds record none — so the rule could not be applied and was not, with at least two places qualifying across three consecutive rounds. This is about how this project runs its review loop, which is patch-line work and is a precondition for the loop being worth its cost.

## 024.168 The ledger's reason for keeping 05-protocol.md's section numbering counts four source comments where one exists, and the claim was copied into the shipped document

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:283, docs/design/docs/05-protocol.md:198

The deletion ledger's row for 05-protocol.md gives as its reason for rewriting §6/§8 in place rather than renumbering: "The file stays — four source comments lean on §7." Exactly one does. `core/lib` holds four citations of 05-protocol.md, and only agent_process_manager.rb:16 names a section; the other three (runtime_agent/agent.rb:9, :107, :165) cite the file generally and two of them name `agent/snapshot` and `agent/model`, which are §4 subsections. Read the other way, `core/lib` holds four occurrences of the string "section 7" and three of them name docs/03-semantic-engine.md §7.1/§7.3 — a different document whose numbering 05-protocol.md cannot break. Either way the count is one. The measurement is a grep over an undifferentiated string, which is the same mistake as C6's first version that this release records as "the mistake it audits", and the argument has since been copied into the shipped design document at 05-protocol.md:198 ("番号を詰めると `section 7` を指すソースコメントが壊れる"), so it now stands in two places.

**Reproduce:** grep -rn '05-protocol' core/lib -> 4 hits, one naming a section. grep -rn 'section 7' core/lib -> 4 hits, three naming docs/03-semantic-engine.md. sed -n '283p' docs/design/tasks/046-0.2.14-making-the-record-true.md and grep -n '番号を詰める' docs/design/docs/05-protocol.md.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** Re-derived at HEAD: `core/lib` holds four
citations of the file and exactly one names a section. `046`'s row
says "a source comment", names which one, and records that it said
"four" until now. `05-protocol.md` keeps both reasons and names the
file the comment lives in rather than counting -- a location a reader
can check beats a number a reader must trust, which is the entry's
point rather than an aside.

## 024.169 `check_doc_links.rb`'s CITATION comment describes anchor/punctuation stripping that no caller performs

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** scripts/check_doc_links.rb:79-80

The comment above the CITATION constant reads "What a documentation path looks like, inside backticks or a Markdown link. Anchors and trailing punctuation are stripped by the caller." Nothing strips anything. The two callers of the match are the scan loop (which takes `Regexp.last_match[:path]` verbatim) and `resolve`/`candidates_for`, neither of which touches the string; the effect the comment describes is produced by CITATION's own character class `[A-Za-z0-9._-]+\.md`, which simply stops before an anchor. The comment names a responsibility that lives somewhere it does not, in the file whose whole subject is that a stated guarantee has to be the guarantee. A maintainer acting on it would either add stripping that already happens or widen the class trusting a caller to clean up. (The neighbouring RELATIVE_LINK regex does consume an anchor, `(?:\#[^)]*)?`, which is likely where the belief came from — but that is the pattern, not the caller, and it is a different constant.)

**Reproduce:** sed -n '79,80p' scripts/check_doc_links.rb, then read the scan loop at :231-245 and `resolve`/`candidates_for` at :168-180 — no `sub`, `gsub`, `chomp`, `delete_suffix` or `split` on `raw` anywhere between the match and the file test.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by saying what the code does.** The sentence now records that
nothing strips anything: the character class stops before an anchor or a
trailing full stop, so the capture is already a bare path and both readers
of it — the scan loop and `resolve` — take it verbatim. It also names
`RELATIVE_LINK` as the constant that really does consume an anchor, in the
pattern rather than in a caller, since that is where the belief came from.

No behaviour changed, and no check can fail on a comment. That is the
honest limit of this one: it is a correction to the file whose whole
subject is that a stated guarantee has to be the guarantee.

## 024.170 The doubled-entry check counts `**Area:**` lines, so a body duplicated anywhere below that line is invisible

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/deferred_findings_spec.rb` ("states each entry's Area exactly once, so a doubled body cannot pass"), `docs/design/tasks/024-deferred-review-findings.md`

The check exists because a scripted edit doubled 024.69's entire body and every other check stayed green. It detects that by counting `**Area:**` occurrences per entry — which detects duplication only when the duplicated slice happens to contain the Area line. The 024.140 incident's own diagnosis is "a `String#find` that returned -1 when its terminator was absent, so a slice meant to end at a paragraph ran to the end of the entry": a class of bug whose slice boundary is wherever the terminator search failed, which for a register entry is far more often somewhere in the body than above the Area line, since the Area line sits in the first few lines of every entry. The countermeasure is therefore roughly one line wide against a defect that can start anywhere in a 200-line entry, and `CLAUDE.md`'s rule is explicit that a regression test for the specific instance is not a countermeasure. A content-based test — no paragraph of an entry appearing twice, or a normalised-body hash — is the shape that matches the defect.

**Reproduce:** In a clone at aa1185f, take 024.13's block, find the newline after its `**Area:**` line, and append everything from there to the end of the block a second time (2,515 characters). Then `ruby scripts/reindex_findings.rb --check` → `current`, exit 0, and from `core/`: `bundle exec rspec spec/meta/deferred_findings_spec.rb` → 37 examples, 0 failures. Control: append from just after the *heading* instead, so the Area line falls inside the duplicated slice — the same run fails with `entries not stating exactly one Area: 024.13 (2 Area lines)`.

### Fixed in 0.2.16

Reproduced first, against this tree rather than the clone the entry was
written in: 7,017 bytes of `024.13`'s body pasted back below its Area
line left `reindex --check` current, `states each entry's Area exactly
once` green, and the whole meta suite green.

The Area count stays and a content check joins it: no run of three
consecutive lines occurs twice inside one entry. The two catch different
halves. `!= 1` also catches a *deleted* Area line, which a content check
cannot see; the content check catches a slice pasted anywhere below it,
which is where `024.140`'s class of bug actually puts a boundary.

**What is compared is an entry's prose** — fenced blocks and indented
blocks dropped — and that is the half that decides the window, not the
number three. Quoted material legitimately repeats inside one entry:
`024.40` states a table header and its separator twice, and `024.28`
carries two pasted interpreter sessions sharing a three-line preamble,
which `024.220` makes the normal case rather than a curiosity. Comparing
every line needs a window of four to clear that; comparing prose clears
it at three, and at two `024.40` is the single offender. A window that
grows whenever somebody quotes a similar session is a maintained number;
"compare the narration" is a rule.

The cost, stated because it is real: a slice doubled entirely inside a
code block is invisible to this. The Area count and
`duplicate_headings_spec` are what still see that.

`024.28` is how this was found. The check was written against an earlier
base, went green there, and reported that entry the moment the change
was rebased onto the tree that had gained it.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.171 Three entries closed in 0.2.14 state as done something HEAD contradicts, two of them naming a countermeasure that was never built

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**All three reproduce at HEAD, and all three are repaired in 0.2.18.**

**(1) `024.139`.** `## 残課題` is still at 008.5:104 and
`## 残っているKnown Issue` still at 008.6:89. The sentence said "Both
sections are deleted"; it now says what happened — the *items* are gone,
replaced by a pointer, and the headings remain, which is the better
outcome rather than a shortfall.

The countermeasure it named was never built, and now is:
`core/spec/meta/task_findings_section_spec.rb`. It asserts the thing
that matters rather than the thing the sentence promised — not that a
task document may have no findings section, but that one carrying items
has to say where findings actually go. Watched failing: removing the
pointer from 008.5 names that file and nothing else.

Top-level `##` sections only. `023.8` has a `####` heading naming one
known gap inside a numbered list, which is a detail of the task rather
than a findings section, and sweeping it in would make the check fire on
ordinary writing.

**(2) `024.141`.** `DOCUMENTATION_MAP` had no row for the release
procedure — `grep` for `release.sh` in it returned nothing — so editing
it triggered no documentation obligation, which is that entry's own
diagnosis happening to that entry. The row exists now, and says plainly
that neither check it cites fires on an edit to `release.sh` itself.

**(3) `024.143`.** It listed as one of preflight's two needed properties
"It asserts a non-zero example count", which is the exact assertion
`024.148` — released alongside it — records as unable to fail, because a
skipped example is still an example. Corrected to what preflight does:
it reads each example's status.

**The common cause is what the entry says**: an entry's closing
paragraph is prose nothing re-reads, and the countermeasures it names
change shape afterwards. Two of these three were a *countermeasure named
and not built*; the third was a rule superseded in the same release that
wrote it.

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (024.139, 024.141, 024.143), `docs/design/tasks/008.5-runtime-and-index-corrections.md`, `docs/design/tasks/008.6-agent-and-index-hardening.md`, `docs/DOCUMENTATION_MAP.md`, `scripts/preflight.rb`

0.2.14 closed these three entries with a sentence about what is now true, and in each case HEAD says otherwise. (1) 024.139: "Both sections are deleted, and this entry is where they went" — `## 残課題` is still at 008.5:104 and `## 残っているKnown Issue` still at 008.6:89; their items were replaced by pointers to the register, which is a reasonable outcome but is not deletion. It then names its countermeasure — "046's C4 ... so a check can assert that `docs/design/tasks/*.md` other than 024 carry no findings section of their own" — and C4 as executed only moved `DeferredFindings` into `scripts/`; nothing anywhere asserts anything about other task documents, so a third task file growing its own findings section is still invisible. (2) 024.141: the instance is genuinely fixed, but its diagnosis is that the class is "a fix applied at the place that runs and not at the place that tells a person what to run", and it says `DOCUMENTATION_MAP` has no row for "the release procedure changed" and that 046's C6 is where that goes. C6 is a different check (every script in RELEASE_CHECKLIST's evidence column must be invoked by something), and the map still has no such row, so editing `vscode/scripts/release.sh` triggers no documentation obligation. (3) 024.143 lists as one of preflight's two needed properties "It asserts a non-zero example count rather than reading the exit status" — the exact assertion 024.148, released in the same release, records as unable to fail because a skipped example is still an example, and which preflight no longer uses for that check. A reader who lands on 024.143 is told the superseded rule is the shipped one. The common cause is that an entry's closing paragraph is prose nothing re-reads, and the countermeasures it names changed shape after it was written. The direction: closing an entry includes re-deriving the sentence that closes it, and a countermeasure named in an entry has to be pointed at by number or path so a reader can check it exists.

**Reproduce:** `grep -n '^## 残課題' docs/design/tasks/008.5-runtime-and-index-corrections.md` and `grep -n '^## 残っているKnown Issue' docs/design/tasks/008.6-agent-and-index-hardening.md` — both hit. `grep -rn 'findings section' core/spec/meta scripts` and `grep -rln '残課題' core/spec scripts` — no matches. `grep -n 'PUBLISHING' docs/DOCUMENTATION_MAP.md` — two hits, both about install steps and the site, none about the release procedure; read 046 line 365 for what C6 actually is. Read 024.143's first bullet beside 024.148's "a skipped example is still an example" paragraph, then `scripts/preflight.rb` lines 44-67 and 83-92: `SUITES_RAN` delegates to `CheckSuitesRan.complaints`, and `NON_EMPTY_SUITE` is attached only to the full-suite check.

**Re-triaged in 0.2.17** (`024.276`). Three entries closed in 0.2.14 state as done something HEAD contradicts, two of them naming a countermeasure that was never built. That is the same class as `024.276` itself, one release earlier and in the closing direction rather than the retargeting one, which is why it is worth doing next to it rather than later.

## 024.172 Four counts derived about this tree are wrong and unmarked, one of them inside the entry about a record that drifted

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Three corrected in place in 0.2.18; the fourth cannot be.**

Re-derived first, and **(c) had drifted again** since this entry was
written — which is the entry making its own point:

```
  (a) git grep -l 'ls-files' 23196a8^ -- 'scripts/*' 'core/spec/*'  ->  9
  (b) rows in docs/RELEASE_ARTIFACTS.md                             -> 33
  (c) wc -w AGENTS.md                                               -> 1,856
      (1,478 at 8f1d4f4^, 1,562 in the commit that wrote the claim)
```

- **(a)** `024.147` said "Ten checks — two scripts and eight specs". It
  now says ten *call sites* across **nine files** — two scripts and
  seven specs, one of which has two — which is what makes its own later
  "all ten sites use it" true.
- **(b)** `024.141` said "eleven releases", which is the 0.1.x line
  alone. Twenty-five.
- **(c)** `024.150` said "It grew by 15 words". That was true at
  `8f1d4f4^` and at no time since; the sentence now carries all three
  figures **with the revisions they belong to**, because an undated
  number is precisely what this entry is about.

**(d) stays as a note**, and deliberately: `dc9b044`'s "seven numbered
gates" lives in an immutable commit message, where five other places say
five. Correcting it would mean rewriting history to make a record look
better than it was, which is the opposite of what this entry is for.

**The Direction is followed rather than the corrections alone.** Its
words: "a count stated about this tree in the release record gets a
`<!-- measured: -->` marker and a deriver, or a `@<rev>` date". (a) and
(b) are historical facts about a named revision and now read as such;
(c) carries its dates inline. None of the three gets a live marker,
because a live marker would rewrite them on every release — which is
`024.184`'s defect, and is how (c) came to be wrong in the first place.

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (024.141, 024.147, 024.150), `core/spec/meta/measured_claims_spec.rb`, and commit `dc9b044`'s message

`measured_claims_spec.rb` exists because "a number in a document that describes this tree is a claim about it", and it is opt-in by design — it "cannot know which numbers in prose are claims". Four numbers written during 0.2.14 fail re-derivation, and none carries a marker. (a) 024.147 opens "Ten checks — two scripts and eight specs — enumerated their input with `git ls-files`": at 23196a8^ there were nine such files, seven specs and two scripts; the eighth spec at HEAD, `untracked_visibility_spec.rb`, was created by that very commit and cannot have enumerated anything the old way. "Ten" survives as a count of *call sites* (release_gate_spec has two), which is also what makes the later "all ten sites use it" true — the breakdown is what is wrong, in the entry whose subject is checks answering a different question from the one they claim. (b) 024.141's "What makes this its own entry rather than a typo" paragraph rests on "kept the pre-fix command for eleven releases": the fix landed in e9d09d5 at version 0.1.3, and 25 releases were published between there and 0.2.13; eleven is the 0.1.x line alone. (c) 024.150 says "046 asserted that the paraphrase would shrink in 0.2.14. It grew by 15 words": AGENTS.md is 1463 words on main and 1562 at HEAD, a growth of 99. +15 was true at 8f1d4f4^ only, and the same commit that wrote the claim took the file to 1562 — a present-tense, undated, unmarked number in the entry that exists because a record drifted, in the release whose headline fix was to date 037's register count as `register-open-defects@f67e743e6eec`. (d) dc9b044's message opens "919 lines that RELEASE_CHECKLIST named as the enforcement for seven numbered gates": five numbered rows plus one prose line named it, and 046 line 278, fe05e3f and 0e84e1a all say five — the outlier is the commit whose whole argument is a gate-by-gate account of what still covers each row. That last one lives in an immutable commit message and can only be corrected by a note, which is a reason to record it rather than to drop it. The direction is not four corrections: it is that a count stated about this tree in the release record gets a `<!-- measured: -->` marker and a deriver, or a `@<rev>` date, and that a number in a commit message describing a count should be derived before the commit is written.

**Reproduce:** (a) `git grep -l 'ls-files' 23196a8^ -- 'scripts/*' 'core/spec/*' | wc -l` → 9; `git log --oneline --diff-filter=A -- core/spec/meta/untracked_visibility_spec.rb` → 23196a8. (b) `git log --format=%h -S packagePath -- vscode/scripts/release.sh | tail -1` → e9d09d5; `git show e9d09d5:vscode/package.json` → 0.1.3; count the published rows in `docs/RELEASE_ARTIFACTS.md` from 0.1.3 to 0.2.13 → 25 (0.1.14/0.1.15 appear only in the second table, which records that no VSIX was built for either). (c) `git show origin/main:AGENTS.md | wc -w` → 1463; `git show HEAD:AGENTS.md | wc -w` → 1562; `git show 8f1d4f4^:AGENTS.md | wc -w` → 1478. (d) `git show dc9b044^:docs/RELEASE_CHECKLIST.md | grep -n 'make-final-review-bundle'` → lines 33, 38, 39, 51, 53, 54 — one prose line and five numbered rows; `sed -n '278p' docs/design/tasks/046-0.2.14-making-the-record-true.md` → "five `RELEASE_CHECKLIST` rows".

**Re-triaged in 0.2.17** (`024.276`). Four counts written during 0.2.14 fail re-derivation and none carries a marker — one of them inside the entry about a record that drifted. 0.2.17 widened the marker scanner to the whole tree and gave the marker's number a reader in the sentence beside it (`024.181`, `024.159`), so the machinery to fix these now reaches them; the numbers themselves are still to correct.

## 024.173 The shipped-target guard sees only `kind: defect`, and `released-in:` is written by 16 entries and read by no check

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17, both directions.**

The shipped-release comparison runs over every open entry rather than open *defects*. `024.124` states the guard as failing "on an **open** entry whose target is in that table", and the implementation filtered `kind == "defect"` on top of that -- so an open `friction` or `roadmap` entry naming a released version passed silently, in the guard written to make that unreachable. Latent when found, and it is pinned in both kinds now.

`released-in:` has a reader. It sat in `KNOWN_KEYS` and was read only by the index renderer, as a display fallback. The rule: a resolved entry names a version this project published, or one it has written release notes for, or `reverted`; a version *above* everything published is the release being prepared and is the ordinary state of a branch mid-flight. What is refused is a value at or below the highest published version that was never published -- which is `024.124`'s situation arriving through this key, and is what sixteen entries asserted while `version.rb` still held the release before it.

It found five immediately: `024.31`, `024.32`, `024.33`, `024.156` and `024.157` were resolved with **no `released-in` at all**, each naming its release only in prose. Filled in from that prose -- 0.2.13 for the first three, 0.2.16 for the other two, whose stale `target:` came off at the same time.

`reverted` is a deliberate value with a reason rather than a blank, which would read as somebody forgetting to fill it in. Two entries carry it: `024.52` and `024.54`, whose fixes were rolled back before release.

Both decisions are in `scripts/deferred_findings.rb`, so the mutation harness reaches them; two entries added.

**Area:** `scripts/deferred_findings.rb` (`#open_entries_targeting_a_shipped_release`, `#open_defects`, `KNOWN_KEYS`), `core/spec/meta/deferred_findings_spec.rb` ("has no open entry naming a release that has already shipped"), `docs/design/tasks/024-deferred-review-findings.md`

024.124 states the guard as failing "on an **open** entry whose target is in that table", and says the mechanism means "the next release cannot inherit the situation the way three have". The implementation is narrower in both directions. `open_entries_targeting_a_shipped_release` is built on `open_defects`, which additionally filters `kind == "defect"`, so an open `friction` or `roadmap` entry naming a shipped release passes silently — latent today, since the five open non-defect entries are all roadmap and none targets a published version, but it is exactly the state 024.124 was written to make unreachable. The mirror direction is unguarded outright: `released-in` sits in `KNOWN_KEYS` and its only reader anywhere is `reindex_findings.rb:69`, where it is a display fallback for the index's release column. Nothing validates it. Sixteen entries currently assert `released-in: 0.2.14` while `core/lib/ovallsp/version.rb` is still `0.2.13` and `docs/RELEASE_ARTIFACTS.md` has no 0.2.14 row — so if this branch ships under any other number, the register re-creates 024.124's situation in the key that was added to prevent it, and no check can say so. The fix is to run the shipped-release comparison over all open entries regardless of kind, and to give `released-in` a reader: it must name a version `RELEASE_ARTIFACTS.md` records as published.

**Reproduce:** Read `scripts/deferred_findings.rb:112-119` beside `#open_defects` at line 99. `grep -rn 'released-in' core/spec/meta scripts` → three hits: a prose comment in the spec, the `KNOWN_KEYS` list, and `reindex_findings.rb:69`. Then `ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); e=DeferredFindings.entries(md); puts e.count{|_,f| f["released-in"]=="0.2.14"}'` → 16, against `grep VERSION core/lib/ovallsp/version.rb` → `0.2.13` and `grep -n '^| 0\.2\.1' docs/RELEASE_ARTIFACTS.md`, whose newest row is 0.2.13.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.174 A relative Markdown link beginning `docs/` is resolved against the repository root instead of the citing file's directory

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (line 249, the `next if raw.start_with?("docs/")` shortcut in the relative-link pass)

The relative-link pass, added in 0.2.14 round 1 precisely because relative links resolve against the citing file's own directory, hands every link whose text begins `docs/` back to the CITATION pass on the grounds that it is "already counted by the pass above". The CITATION pass resolves against ROOT. The two passes therefore agree only for Markdown at the repository root; for any nested document the checker validates a path the reader will never follow. A Markdown link to the roadmap written with its full repository-relative path, inside a task file, really targets that path appended to the task directory, and the checker reports it resolved. (Neither form is spelled out here: this register is scanned, so quoting either would make the entry the finding — `024.126`.) This is the failure the relative pass was built to close, reopened by the pass's own optimisation. Latent today: 0 live instances at HEAD (the two occurrences in 046 are inside inline backticks and do not render as links). It is the link a writer produces by copying a path out of `docs/DOCUMENTATION_MAP.md` into a task file.

**Reproduce:** In a scratch worktree at HEAD: write `<probe>.md` under the task directory holding that link, then `ruby scripts/check_doc_links.rb` -> prints "every documentation path resolves", exit 0, while the directory the link really names does not exist. Direction: drop the shortcut and treat a link as relative unless the citing file is at the repository root, or require one of the two interpretations to resolve and say which.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by deleting the shortcut.** A link written with a leading `docs/`
now goes through the relative pass like every other link, resolved against
the citing file's own directory. It is still counted by the CITATION pass
as well, which asks a different question of the same text, so such a link
contributes two to the citation total — the whole cost, and cosmetic.

Pinned by `doc_links_spec.rb`, "resolves a relative link written as a docs
path against the citing file's directory too": a throwaway repository where
the target exists at the root and does not exist beside the citing file, so
the two interpretations give *different* answers and the fixture cannot
pass under either one by accident. Watched failing against the unfixed
script.

Landing it turned this entry's own illustrations into dangling citations of
the kind `024.126` describes. They are described rather than quoted now,
here and in `046`'s round note, and the register was not exempted.

## 024.175 Doc-link resolution goes through File.file?, so a case-only typo passes on macOS and fails on Linux and GitHub

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (`resolve`/`candidates_for`, lines 163-175), `scripts/preflight.rb` (line 101), `.github/workflows/ci.yml` (the doc-links job, ubuntu-latest)

Resolution is `File.file?(File.join(ROOT, target))`. On APFS that is case-insensitive, so the roadmap's path with its filename lower-cased, and this register's path with one word of its filename upper-cased, both "resolve" and the check exits 0 (neither is spelled out: this register is scanned, and quoting a case-typo makes the entry the finding — `024.126`) — while both are dead links in a Linux checkout and in GitHub's web renderer. CI runs the identical script on ubuntu-latest, so `preflight.rb`, the gate whose entire purpose is to run *before* the commit, is strictly weaker than CI on this class of typo: the same local-green/CI-red asymmetry CLAUDE.md already records for the real-Rails and capability suites. It also makes the script disagree with itself: `ever_existed?` asks git, which is case-sensitive, so the resolver and the history query can answer differently about the same path.

**Reproduce:** On macOS, from the repository root: `ruby -e 'p File.file?("docs/ROADMAP.md")'` prints `true`, and so does the same call with the filename lower-cased. Then write `<probe>.rb` holding a source comment that cites the lower-cased spelling and run `ruby scripts/check_doc_links.rb` -> "every documentation path resolves", exit 0. Direction: after `File.file?` succeeds, require the resolved path to appear verbatim in `RepoFiles.list`, which is byte-exact and already enumerated.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by asking the repository instead of the disk.** `resolve` and the
relative pass both go through `carried?`, which tests membership of the
same `RepoFiles.list` enumeration the scan itself reads. That is
byte-exact, so a case-only typo is a dead link here exactly as it is on
Linux and in GitHub's renderer — and it is the same question
`ever_existed?` already put to git, so the resolver and the history query
can no longer answer differently about one path.

The case instance cannot fail an example on a case-sensitive filesystem, so
the pin is the rule rather than that instance: "resolves only against files
git carries" plants a file present on disk and ignored by git, which the
working tree answers for and this repository does not have. It distinguishes
the two behaviours on every platform, and it was watched failing against the
unfixed script.

## 024.176 The `[deletion marker]` marker admits a pointer to a renamed file, which the paragraph defining it says is still a failure

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (the marker paragraph, lines 141-153; `ever_existed?`, lines 189-195)

The marker's design paragraph ends: "A pointer to a *renamed* file is also still a failure, because the marker is a deliberate edit on the line that needs it rather than a mode the file is in." `ever_existed?` asks `git log --all -1 -- <path>`, which is true for a path git carried under its pre-rename name — so a marked citation of a file that was renamed away passes, and is counted in the "naming a deleted file on a line marked as recording the deletion" total. The stated reason does not support the stated claim either: per-line marking says nothing about renames. Renames are the common case for documents in this tree (046's own A4 table repoints five task filenames), so the exemption is widest exactly where it was meant to be narrowest, and the count the check prints is not the count it names.

**Reproduce:** In a tmpdir: `git init`; commit `<probe>.md`; `git mv `<probe>.md` `<probe>.md` and commit; commit `note.md` containing ``A pointer to `<probe>.md` [deletion marker]`` and ``A pointer to `<probe>.md` [deletion marker]``; run `CHECK_DOC_LINKS_ROOT=<tmpdir> ruby scripts/check_doc_links.rb`. Only NEVER_EXISTED_AT_ALL is reported; the output says "1 naming a deleted file". Either make the marker check that no commit's *current* tree still carries the content under another name, or correct the paragraph to say what the code does.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16, and made true rather than weakened.** The marker
now asks whether the content survives under another name and reports
a renamed-away citation separately, because the repair differs:
nothing needs restoring, the citation needs repointing.

One implementation detail worth keeping, because it is the reason the
obvious version does not work: `git log --diff-filter=R --name-status
-- <path>` reports **nothing** for a renamed path, since the pathspec
limits the diff before rename detection runs and the two halves are
never paired. Measured both ways. So the rename map is read once
without a pathspec -- 136 renames across this history, 40ms -- and
chased through multi-step renames.

Both directions watched failing: with the detection disabled the
renamed-away citation is admitted again; with a rename treated as
disqualifying on its own, the *renamed-then-deleted* case goes red,
which is the false positive the entry warned about and which the
"does it exist now" test avoids.

## 024.177 check_doc_links names only an enumerated set of docs subdirectories, so a citation in any other one is silently unchecked

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (`CITATION`, line 93: `docs/(?:design/)?(?:tasks/|adrs/|docs/|schemas/)?[A-Za-z0-9._-]+\.md`)

Round 2's fix added the root and `vscode/` documents and added `schemas/` to the enumeration, which closed the reported instances. What it did not do is stop enumerating. The pattern can name a path only in the four listed leaf directories; a path in a `docs/` subdirectory that is not on the list — or any subdirectory added tomorrow — is invisible (an example is described rather than written, since quoting one would make this entry the finding — `024.126`), and the file's headline still says "Every documentation path named in tracked content must resolve to a file that exists." The scanner's scope is a hand-written list — the same shape `024.151` names in its third open bullet, one level in. Latent: 0 live instances at HEAD, because every docs subdirectory that exists today happens to be on the list. It becomes a false clean the first time someone adds one.

**Reproduce:** In a scratch worktree at HEAD: `printf '# See <probe>.md\n' > <probe>.rb; ruby scripts/check_doc_links.rb` -> "every documentation path resolves", exit 0. Add `<probe>.md` to the same probe and that one *is* reported, which is the contrast. Direction: match any `[A-Za-z0-9._/-]+\.md` token beginning with a real top-level directory of this repository rather than enumerating subdirectories; the coverage floor added in 0.2.14 pins how much of the tree is *read*, not how much of a path the pattern can *name*.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by removing the enumeration, and then by measuring the reach.**
CITATION's first branch is any depth under `docs/` now, so a subdirectory
added tomorrow is inside the check on the day it appears.

The enumeration was the symptom. The class is that the pattern's reach was
a property nobody measured, so shrinking it cost nothing and showed
nowhere. The checker prints `unnameable-documents=N` — the tracked Markdown
files CITATION cannot name — and `doc_links_spec.rb` requires it to be zero
for this repository. It is the mirror of the per-root coverage floor beside
it: that one says how much of the tree is *read*, this says how much of it
can be *referred to*, and a hand-written list shrinks the second without
touching the first. Watched failing by planting a lower-case Markdown file
outside `docs/`, which took the count to 1.

Reported rather than refused. The first shape of this check refused such a
tree outright and took four unrelated examples red with it, because a
throwaway repository built by a spec legitimately holds a document nothing
cites.

## 024.178 check_doc_links' founding census is stated as living entirely in source comments; one of the nineteen was in a Markdown document

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (lines 25-27), `core/spec/meta/doc_links_spec.rb` (lines 8-12 and the failure message at line 65), `docs/design/tasks/046-0.2.14-making-the-record-true.md` (line 229)

Four tracked places assert that all 19 of the citations this check was built for lived in source comments, and draw a design conclusion from it — "a checker that read only Markdown would have reported this tree clean", which is the argument for scanning `.rb` at all. Re-running the A0-era checker against the pre-A0 tree reproduces the census exactly (19 citations, 5 never-committed names, 17 distinct files) and shows 18 in `.rb` comments and the nineteenth in `docs/design/plugin-sdk.md:5` — the "public SDK document" the immediately preceding sentence names in both the script and the spec. A Markdown-only checker would have found one of the nineteen, not zero. The conclusion survives at 18-of-19; the absolute quantifier that carries it does not, and one of the four places is an rspec failure message, so the false claim is what a future failure prints at the reader. <!-- deleted -->

**Reproduce:** `git worktree add --detach /tmp/w6bc 6bc31b9; cd /tmp/w6bc; git show 26243e0:scripts/check_doc_links.rb > scripts/check_doc_links_a0.rb; ruby scripts/check_doc_links_a0.rb`. It prints "19 citation(s) resolve to nothing, naming 5 path(s)"; the last hit line is `docs/design/plugin-sdk.md:5`. Fix the sentence in all four places, not three — the spec's failure message at line 65 is easy to miss. <!-- deleted -->

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in the four places, quantifier only.** The census re-runs exactly as
the entry describes — 19 citations, five never-committed names, 17 distinct
files — with 18 in `.rb` comments and the nineteenth in the public SDK
document, which is the file the preceding sentence already names in both the
script and the spec. Each place says 18 of the 19 now and keeps the
conclusion, which survives: a checker that read only Markdown would have
found one of nineteen and reported the rest of the tree clean.

The place that mattered is `doc_links_spec.rb`'s coverage failure message,
because that sentence is what a future failure prints at its reader.

### The fifth place, found by the verifier and corrected in the same release

Closed as "fixed in the four places, quantifier only" — and a fifth
tracked place still asserted it, in `046`, the document this entry's own
Area names. `046`'s A0 narrative said the founding census was "every one
in a source comment", three lines above the A0 paragraph that *was*
corrected.

Re-derived rather than argued: the A0-era checker restored from its own
commit and run against the tree of the day gives 19 citations, 5 paths,
17 distinct files — eighteen `.rb` comments and one Markdown document,
the plugin SDK's, since deleted by `024.234`. Its path is described
rather than written: this entry is about a census of citations that
resolve to nothing, and writing one here makes this file the twentieth.
Corrected in place, marked as a correction so the round record still
reads as a record.

## 024.179 Hand-typed counts in check_doc_links' header do not reproduce, and none carries a measured marker

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (the SHORTHAND comment, lines 39-54; the CITATION root-document comment, lines 95-109), `docs/design/tasks/046-0.2.14-making-the-record-true.md` (lines 230-231)

Three numbers in this file are claims about this tree, each argued from, and none re-derives. (1) The shorthand census. It was "91 times across 39 files"; that figure is a raw grep of the short form, which also matches the *tail* of the fully-qualified form — the shape that is not a shorthand and needs no rewriting — so the cost side of "rewriting them costs more than it buys" was roughly doubled. Round 3 re-derived it to "45 times across 20 files", and that is wrong too: counted with the file's own SHORTHAND/CITATION/SKIP over `RepoFiles.list` it is 48 across 23 at HEAD *and* 48 across 23 at 6155cf4, the commit that wrote the sentence. 45/22 was true only at 54b7274, one commit earlier. (2) `046`:231` still carries the retracted "91 occurrences across 39 files", so the release record and the script now disagree. (3) The root-document comment says "twenty tracked Markdown files" and then enumerates fifteen, undercounting `vscode/` as six when it is eight and omitting the `.ja` halves of SECURITY, SUPPORT and CODE_OF_CONDUCT. That list is what a reader consults to decide whether the structural pattern still covers what it claims. None of the three carries a `<!-- measured: -->` marker, so `core/spec/meta/measured_claims_spec.rb` — the mechanism built in this same release for exactly this failure — never sees them.

**Reproduce:** Shorthand: eval the script's own `SHORTHAND`, `SKIP` and `CITATION` source lines, scan `RepoFiles.list(root)` minus SKIP line by line, count matches where the CITATION capture matches SHORTHAND -> 48 across 23 at HEAD; repeat in worktrees at 6155cf4 (48/23), 577704b (48/23), 54b7274 (45/22). Raw-grep reading at 6bc31b9: `git ls-files -z | xargs -0 /usr/bin/grep -oaE 'docs/[0-9]{2}-[a-z0-9-]+\.md' | wc -l` -> 91, `-laE ... | wc -l` -> 39. Root documents: `git ls-files | ruby -ne 'p=$_.chomp; puts p if p =~ %r{\A(?:vscode/)?[A-Z][A-Z0-9_]*(?:\.ja)?\.md\z}'` -> 20 files, 8 under vscode/. Direction: mark each with `<!-- measured: -->` and add its deriver, which is what the release's own mechanism is for.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by removing the numbers rather than re-typing them.** All three are
claims about a tree that moves, and re-deriving the shorthand census with
the file's own patterns bears that out: 45 across 22 one commit before
the sentence was written, 48 across 23 on the commit that wrote it, and a
third pair again on the commit this was closed at. A count typed into a
comment is stale by the next release.

- The shorthand comment states no count. The argument it supports —
  rewriting those citations costs more than it buys — does not rest on one,
  and the comment now records both retracted figures and why each was wrong.
- The root-document comment no longer says "twenty" and no longer
  enumerates. It was wrong in both directions at once, counting `vscode/`
  as six against eight and dropping three `.ja` halves, and it is the list
  a reader consults to decide whether the structural pattern still covers
  what it claims. `024.177`'s coverage line answers that every run instead.
- `046`'s A0 paragraph no longer carries the retracted "91 occurrences
  across 39 files". It records that the figure was a raw grep which also
  matched the fully-qualified form, and was withdrawn.

The entry's direction was to mark each with a measured marker and add a
deriver. **That is not available at this file.** The measured-claim scanner
reads four hand-written globs and `scripts/` is outside all of them
(`024.181`), so a marker written here would be inert — a claim that looks
checked and is not, which is the failure this whole batch is about. If
`024.181` is closed by widening that scanner, the shorthand census is the
first number worth marking.

## 024.180 The citation guard reads nine file extensions, so the published site's register pointers are outside every check

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`scanned_files`, line 199-205), `site/index.html`, `site/security.html`, `site/ja/index.html`, `site/ja/security.html`

`scanned_files` takes `RepoFiles.list(TREE_ROOT)` — every tracked-or-untracked file — and then filters it with `/\.(rb|ts|js|md|json|yml|yaml|sh|erb)\z/`. That extension list is written directly beneath a comment explaining that the first version of this scanner used four globs, missed both changelogs, and that "a guard whose scope is a list somebody remembered has the defect it was built to catch": the fix replaced a list of directories with a list of extensions. At aa1185f the filter drops 38 of 561 files — all 11 `site/*.html` pages, every extensionless file (`LICENSE`, `.gitignore`, `core/.rspec`), 4 `.rbs`, `core/ovallsp.gemspec`, `vscode/resources/core-job.ps1`, `site/robots.txt`, `site/sitemap.xml`, `site/assets/css/site.css`, `.gitleaks.toml`, `core/Gemfile.lock`. Four of the dropped pages cite `024.55` today (`site/index.html:499`, `site/security.html:205`, `site/ja/index.html:462`, `site/ja/security.html:196`), and no other check in the tree looks at them: `scripts/check_site_links.rb` verifies links, anchors and assets and contains no `024.` handling; `scripts/check_doc_links.rb` verifies file paths; `deferred_findings_spec.rb` reads four named Markdown files. So deleting or renumbering `024.55` — the case the register's legend asks for a grep before — leaves four dangling pointers on the published site with the whole suite green. `024.151`'s remaining-work list names this class in one line ("several scanners' scopes are hand-written glob or extension lists"); this entry is the concrete instance, with the unchecked content named and a reproduction, which that entry does not carry.

**Reproduce:** In a scratch worktree at aa1185f: `printf '<!-- see 024.<n> -->\n' >> site/index.html` then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. `ruby scripts/check_site_links.rb` also exits 0. The identical line appended to any `.md` fails the example. Enumerate the blind region with `ruby -e 'require_relative "scripts/repo_files"; l=RepoFiles.list(Dir.pwd); puts (l - l.select{|p| p.match?(/\.(rb|ts|js|md|json|yml|yaml|sh|erb)\z/)})'`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed by stating the scope as what it excludes.** `scanned_files` no
longer filters on nine extensions; it takes `RepoFiles.list` and rejects
vendored trees and files that are not authored text. The published pages,
every extensionless file, the `.rbs` signatures, the gemspec and the
PowerShell job script are read now, and the only tracked files dropped are
the dependency lock file and two icons. Getting a denylist wrong is noisy;
getting an allowlist wrong is silent, and silent is the direction this
scanner had been failing in twice running.

Pinned by "reads the published pages too, not only the file types somebody
listed", which asserts the property — a published page carrying a register
pointer is read — rather than restating the denylist back at itself.
Watched failing under the extension list, where no page was being read at
all; and the pointer guard itself watched failing on a bogus register
number appended to a site page, which was green before this change.

This retires the concrete instance `024.151`'s third bullet names for this
scanner. The other half of that bullet, the four globs `claims` reads, is
`024.181` and is untouched here.

## 024.181 The measured-claim scanner reads four hand-written globs, so a marker anywhere else is inert

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** The scan reads `RepoFiles.list` -- the same enumeration every other tree-wide scanner here reads -- instead of four hand-written globs. It also picks up untracked files, so a marker in a new file is checked before it is committed.

Measured at the time of the change: 8 markers tree-wide, all 8 already inside the old globs. So this was a coverage gap rather than a live wrong number, which is why it survived; the inert locations were repo-root documents, both changelogs, `scripts/`, `site/` and `.github/`.

The example is a floor naming files from three of those locations, so a scope that narrows again fails rather than passing quietly. That is the shape `024.151` argues for and the shape the citation scanner ninety lines below had already been fixed into -- this was the last reader in the file still carrying the remembered list.

**On the mutation manifest.** These five decisions live in `core/spec/meta/measured_claims_spec.rb`, and `scripts/check_pinned_mutations.rb` mutates `core/lib/` and `scripts/` only -- a spec file is refused, because a mutation there could delete the example that would have caught it. So each is pinned by a distinguishing example and by nothing underneath it. The direction is to move this machinery into `scripts/`, beside `DeferredFindings`, `HomePaths` and `DocumentedCounts`, which is where every sibling scanner already lives and is what `024.181` found the cost of: the scanner in the spec and the scanner in the script diverged, in the same file, ninety lines apart. Recorded under `024.121`.

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, line 105-119)

`claims` scans `%w[docs/**/*.md core/lib/**/*.rb core/spec/**/*.rb vscode/src/**/*.ts]`, which is the pre-fix shape of the citation scanner ninety lines below it in the same file — the one whose comment says the four-glob version "missed both changelogs … A guard whose scope is a list somebody remembered has the defect it was built to catch." Both examples that read `claims` — "matches what the tree actually says" and "names a deriver for every claim, so none can be marked and left uncomputed" — are therefore blind outside those four globs, including to a marker naming a deriver that does not exist. Inert locations verified by probe: repo-root `.md` (`README.md`, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`), `vscode/**/*.md` (`vscode/CHANGELOG.md`, `vscode/README.md`), `scripts/**`, `site/**`, `.github/**`, `core/*.md`, and any non-`.md` file under `docs/`. The header's stated guarantee, "a claim cannot be marked and left uncomputed", is true only inside the four globs. Two further consequences of the same line: three of the four globs are asserted by nothing (no marker exists under `core/lib`, `core/spec` or `vscode/src`, so narrowing `patterns` to `%w[docs/**/*.md]` leaves all six examples green — an unpinned behavioural line, and this half is `024.151`'s class); and the file's positive control, "reads a claim out of a document and compares it", re-implements the scan inline against a tmpdir fixture and never calls `claims`, so nothing exercises the real scope. Fix by scanning `RepoFiles.list` filtered on text extensions, as the citation half already does — which dissolves the unpinned-glob half at the same time.

**Reproduce:** In a scratch worktree at aa1185f, write `probe [measured marker for no-such-deriver]` to each of `ZZ_probe_root.md`, `vscode/ZZ_probe.md`, `scripts/ZZ_probe.rb`, `site/ZZ_probe.html`, `.github/ZZ_probe.md`, `docs/design/ZZ_probe.txt`, `core/ZZ_probe.md`, and append `probe [measured marker for register-entries]` to `CLAUDE.md` and `vscode/CHANGELOG.md`; then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. Separately, change line 106 to `patterns = %w[docs/**/*.md]` and rerun → 6 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.182 A sub-numbered register entry is invisible to the citation guard, and a citation of one truncates to its parent

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`CITATION` line 182, `register_numbers` line 187-191), `core/spec/meta/deferred_findings_spec.rb:143-144`

Sub-numbered entries are a supported shape — `DeferredFindings::ENTRY_HEADING` is `/^## (024\.[0-9R][0-9.]*) /` and `046`'s C4 made that module the single parser of the register — but two hand-rolled readers of the same headings survived that consolidation and neither can express a sub-number. `register_numbers` uses `/^## (024\.[0-9R]+) /`, which does not match `## 024.30.<n>`, so a sub-numbered entry is not in the guard's set of known numbers at all. `CITATION` is `/\b024\.(?<number>[0-9]+|R[0-9]+)\b/`, which matches `024.30.<n>` as `024.30`. The two failures compose in both directions: a pointer at `024.13.<n>` — an entry that was never written, or one renumbered away — passes because `024.13` exists, while `024.<n>.1` is reported dangling under the wrong number `024.<n>`. The consolidation comment at lines 76-88 of this file says round 1 removed a third and fourth reader for exactly this reason; these are the fifth and sixth. `deferred_findings_spec.rb`'s "indexes every entry" example carries the same regex on both sides asymmetrically (`/^## (024\.[0-9R]+)/` captures `024.30` from a sub-numbered heading, `/^\| \[`(024\.[0-9R]+)`\]/` captures nothing from its index row), so adding a sub-numbered entry would also fail that example spuriously.

**Reproduce:** Append `See 024.13.<n> and 024.<n>.1 for the reasoning.` to any scanned `.md` (e.g. `docs/design/tasks/037-0.2.7-concurrency-foundations.md`) and run `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` — one failure, naming only `024.<n>`. For the reader divergence: `ruby -e 'require_relative "scripts/deferred_findings"; s="## 024.30.<n> A sub entry\n"; p DeferredFindings.headings(s); p s.scan(/^## (024\\.[0-9R]+) /).flatten; p "see 024.30.<n>".scan(/\\b024\\.([0-9]+|R[0-9]+)\\b/).flatten'` → `["024.30.<n>"]`, `[]`, `["30"]`.

### Fixed in 0.2.16

Reproduced first, all three halves: the module read the sub-number,
`register_numbers` read nothing, the citation pattern read the parent —
and a pointer at a sub-entry that has never existed was accepted while a
sub-entry of a nonexistent parent was reported under the wrong number.

`CITATION` is now `DeferredFindings::CITATION`, built from the one number
grammar rather than written a second time, and `register_numbers` reads
`DeferredFindings.headings` and `.retired_numbers`. `indexes every
entry` reads that grammar on both of its sides. A pointer at a sub-entry
that does not exist is now reported as itself. See `024.216`, which is
the same root cause counted across all six readers.

Widening it turned every illustration of a sub-number in this file, in
`046`'s round notes and in `deferred_findings_spec.rb` into a dangling
pointer — `024.126` arriving inside the change that caused it. The
spec's are assembled with `unspellable_number`; the prose writes the
sub-part as this register's own `<n>` placeholder, which keeps the
parent resolving and the sentence legible. No file was exempted.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.183 The citation guard skips the register itself, where most `024.N` cross-references are written

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`scanned_files`, line 202), `docs/design/tasks/024-deferred-review-findings.md`

`scanned_files` rejects `024-deferred-review-findings.md` outright, so a `see 024.NNN` typo inside an entry's body — the densest place `024.N` cross-references are written, and the place a reader most often follows one from — is unverifiable. The exclusion appears to exist so the entry headings and the index table do not match `CITATION` and report themselves; a scan that skips `^## ` headings and `^| [` index rows would keep the body prose in scope without that. Scanning the register's own body today finds four references that resolve to nothing — `024.61` at lines 85, 95 and 3998, and `024.<n>` at line 7092 — and all four are deliberate prose (the legend explains the vacated `024.61` at length; line 7092 records `046`'s C4 assembling a synthetic entry from parts because writing `024.<n>` tripped this very guard). None of them is a live defect, which is the point: a real typo would be indistinguishable from them by machine, because nothing looks.

**Reproduce:** Append `A stray pointer to 024.<n> for the reasoning.` to `docs/design/tasks/024-deferred-review-findings.md` and run `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. The scan that would have caught it: `ruby -rset -e 'reg=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); known=(reg.scan(/^## (024\\.[0-9R]+) /).flatten+reg.scan(/^\\| `(024\\.[0-9R]+)` \\|/).flatten).to_set; reg.lines.each_with_index{|l,i| l.scan(/\\b024\\.([0-9]+|R[0-9]+)\\b/).flatten.each{|n| puts "#{i+1}: 024.#{n}" unless known.include?("024.#{n}")}}'`.

### Fixed in 0.2.16

Reproduced first. The entry's own line numbers had moved — the hand
scan reports five locations at this revision rather than the four it
names — but every one of them is a line the entry describes, and the
planted pointer was invisible exactly as written.

`scanned_files` no longer rejects this file. What the rejection was
really avoiding is the register's own scaffolding matching itself, so
that is what is skipped instead, line by line: an entry heading, a
generated index row, a "Retired numbers" row. Everything a person wrote
as prose is in scope, which is the half a reader follows.

The pre-existing deliberate lines were dealt with rather than exempted.
`024.61` now has a row in the "Retired numbers" table — the mechanism
the guard already honours — which makes the legend's paragraphs about
the hole, and the 0.2.3 cross-reference record that lists it, resolve
without any of them being reworded. The two lines that spelled a
synthetic number describe the shape instead, per `024.126`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.184 A dated `@<rev>` claim is silently derived from the present tree unless the deriver happens to use the revision

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** A deriver's arity is its declaration: `->(rev = nil)` answers about a revision, `-> {}` answers about the present tree, and a dated claim naming a present-only deriver raises with a message saying which of the two to change. `mutex-sites` is the present-only one, and it accepted a revision and discarded it.

The consequence was inverted, which is what made it worse than a missing check: a historical document carrying the **true** count for its own revision is the side that fails, and the failure message tells the author to write today's number into a document about last month.

Pinned by picking one deriver of each arity out of the table rather than naming one, so the example keeps distinguishing when the table changes -- and it asserts both that no present-only deriver is left and that no dated-capable one is, since a table that lost either would make the example vacuous.

**On the mutation manifest.** These five decisions live in `core/spec/meta/measured_claims_spec.rb`, and `scripts/check_pinned_mutations.rb` mutates `core/lib/` and `scripts/` only -- a spec file is refused, because a mutation there could delete the example that would have caught it. So each is pinned by a distinguishing example and by nothing underneath it. The direction is to move this machinery into `scripts/`, beside `DeferredFindings`, `HomePaths` and `DocumentedCounts`, which is where every sibling scanner already lives and is what `024.181` found the cost of: the scanner in the spec and the scanner in the script diverged, in the same file, ninety lines apart. Recorded under `024.121`.

**Area:** `core/spec/meta/measured_claims_spec.rb` (`DERIVERS["mutex-sites"]`, line 69-72; `MARKER`, line 61)

`MARKER` accepts `@<rev>` on any deriver, and the comment above it explains at length that this is what makes a historical document's number checkable rather than a promise to remember. `register-entries` and `register-open-defects` honour it — both pass `rev` into `register(rev)`, which shells out to `git show`. `mutex-sites` is `lambda { |_rev = nil| ... }`: it accepts the revision and discards it, the `_` prefix suppressing the lint that would say so, and globs the present `core/lib`. Nothing checks that a deriver invoked with a revision consumes it, so the guarantee is true for two derivers by construction and false for the third by accident. The consequence is inverted, which is what makes it worse than a missing check: a historical document that writes the **true** count at its revision goes red, and the failure message reads "Re-derive the number rather than editing the prose around it" — instructing the author to replace a correct dated number with a present-day one, in the file built to stop exactly that. The narrower structural fault is that a deriver's signature is what decides whether dating works, and nothing states or checks the contract.

**Reproduce:** In a scratch worktree at aa1185f, derive the truth first: `git ls-tree -r --name-only f67e743e6eec core/lib | /usr/bin/grep '\.rb$' | while read f; do git show "f67e743e6eec:$f"; done | /usr/bin/grep -c 'Mutex\.new'` → 29. Then `printf '\n[measured marker for mutex-sites]\n' >> docs/design/tasks/037-0.2.7-concurrency-foundations.md; cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → RED, "mutex-sites says 29, the tree has 31". Change 29 to 31 and rerun → 6 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.185 A second `<!-- measured: -->` marker on the same line is never parsed

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** Every marker on a line is read, not the first. `String#match` returns one `MatchData`, and a sentence stating a total and how many of them are open puts both markers on one line, which is the natural shape rather than an exotic one.

The file's own positive control could not see this, because it re-implemented the scan inline against a tmpdir fixture -- the same first-match-only call -- so it carried the bug it was controlling for and agreed with it. It goes through the real scan now.

Measured: no line in this tree carries two markers today, so this was latent. The example plants one.

**On the mutation manifest.** These five decisions live in `core/spec/meta/measured_claims_spec.rb`, and `scripts/check_pinned_mutations.rb` mutates `core/lib/` and `scripts/` only -- a spec file is refused, because a mutation there could delete the example that would have caught it. So each is pinned by a distinguishing example and by nothing underneath it. The direction is to move this machinery into `scripts/`, beside `DeferredFindings`, `HomePaths` and `DocumentedCounts`, which is where every sibling scanner already lives and is what `024.181` found the cost of: the scanner in the spec and the scanner in the script diverged, in the same file, ninety lines apart. Recorded under `024.121`.

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, line 113; positive control, line 158-166)

`claims` does `next unless (m = line.match(MARKER))`, and `String#match` returns the first `MatchData` only, so a second marker on the same line escapes both examples that read `claims` — "matches what the tree actually says" and "names a deriver for every claim, so none can be marked and left uncomputed". Two claims on one line is the natural shape, not an exotic one: the register's own marker line is "**152 entries below** [measured marker for register-entries]", and a sentence stating two counts ("152 entries, 57 of them open") puts both markers on one line. The file's positive control cannot see this, because it re-implements the scan inline against a tmpdir fixture (`File.read(path).lines.filter_map { |line| line.match(MARKER) }` — the same first-match-only call) instead of exercising `claims`. `line.scan(MARKER)`, as the citation half already does one screen below, is the fix.

**Reproduce:** In a scratch worktree at aa1185f: `printf '\nX [measured marker for mutex-sites] and Y [measured marker for register-entries]\n' >> docs/design/tasks/037-0.2.7-concurrency-foundations.md; cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures, though the register has 152 entries. Repeat with `no-such-deriver = 1` as the second marker → also green. Control: the same `register-entries = 999` marker alone on its own line → RED, "register-entries says 999, the tree has 152".

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.186 `mutex-sites` counts the string `Mutex.new`, so a comment mentioning it inflates the documented lock count

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** The deriver parses with Prism and counts a call whose receiver is `Mutex` and whose method is `new`. It counted the *substring* before, so `core/lib/ovallsp/signatures/type_converter.rb`'s comment about how RBS renders a type name counted as a lock: 31 answered for 30 real sites, and `docs/design/docs/02-architecture.md` asserted 31 with a green guard behind it.

The document says 30 now and records why the number moved without any lock being removed -- the alternative reading, that a lock disappeared, is the one a reader would otherwise reach.

This is the failure mode that file's own header names: the check passing for a reason other than the one it states. The deriver and the prose disagreed about what a lock is, and being green was the symptom.

A comment is not a node, which is the whole of the fix. Pinned against a fixture holding one real lock, one comment mentioning one, and one string literal spelling one.

**On the mutation manifest.** These five decisions live in `core/spec/meta/measured_claims_spec.rb`, and `scripts/check_pinned_mutations.rb` mutates `core/lib/` and `scripts/` only -- a spec file is refused, because a mutation there could delete the example that would have caught it. So each is pinned by a distinguishing example and by nothing underneath it. The direction is to move this machinery into `scripts/`, beside `DeferredFindings`, `HomePaths` and `DocumentedCounts`, which is where every sibling scanner already lives and is what `024.181` found the cost of: the scanner in the spec and the scanner in the script diverged, in the same file, ninety lines apart. Recorded under `024.121`.

**Area:** `core/spec/meta/measured_claims_spec.rb` (`DERIVERS["mutex-sites"]`), `docs/design/docs/02-architecture.md:270`, `core/lib/ovallsp/signatures/type_converter.rb:112`

The deriver is `File.read(f, encoding: "UTF-8").scan("Mutex.new").length` — a substring count over the whole file, comments and strings included. `core/lib/ovallsp/signatures/type_converter.rb:112` reads `# path -- \`Mutex.new\` says \`Thread::Mutex\`, which is what it is.`, a sentence about how RBS renders a type name, not a lock. So `core/lib` constructs 30 mutexes while the deriver answers 31, and `docs/design/docs/02-architecture.md:270` — the threading section whose stated purpose is that it stopped contradicting the code, and which was wrong about this same count on the release that introduced it — asserts 31 with a green guard behind it. The check is green because the deriver and the prose disagree about what is being counted, not because the count is right. The coupling also runs the wrong way: writing another comment that mentions `Mutex.new` would force the author to raise the documented number of locks, and deleting one would force lowering it.

**Reproduce:** `/usr/bin/grep -rn 'Mutex.new' core/lib --include='*.rb' | wc -l` → 31 (use `/usr/bin/grep`; the interactive shell's `grep` is a `ugrep` wrapper). `/usr/bin/grep -rn 'Mutex.new' core/lib --include='*.rb' | /usr/bin/grep -E ':[0-9]+:\s*#'` → the single comment at `core/lib/ovallsp/signatures/type_converter.rb:112`. Actual constructions: 30. `sed -n '268,272p' docs/design/docs/02-architecture.md` shows the claim and its marker, and `bundle exec rspec spec/meta/measured_claims_spec.rb` is green.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.187 A single NUL or invalid byte clears a whole file from the home-path scan, and no example can fail on it

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** The bytes are scrubbed and read. A NUL or an invalid sequence no longer removes the file, so the plain-ASCII home path sitting beside a stray byte is seen; measured before the change, the two files the old rule declined are both PNGs and neither carries a name.

The one skip left is for a path that is not a file at all, and it is recorded. `skipped_files` comes back empty over this tree now, which is the tree-scale half of the pin.

Two examples in `core/spec/meta/home_path_guard_spec.rb`, because one of them is not enough: the tree-scale one passes against a *silent* skip, which is the arrangement 0.2.5 already had to fix. The distinguishing one plants a name in the ASCII portion of a file that also holds a NUL, in a scratch root, and requires the name back. Mutation `scanning a file that holds a stray byte` is what caught the first version asserting only that nothing was skipped.

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

`offences_in_file` returns [] for the *entire* file when it contains one NUL byte or one invalid UTF-8 sequence (lines 101-110), including any real home path sitting in its plain-ASCII portion. The skip is deliberate for compiled artefacts — those are covered by `vscode/scripts/release.sh` against the packaged VSIX — but the rule is written as a property of the bytes, not of the file, so any text file that acquires a stray byte silently stops being checked. The compensating story, 'a skip is reported', is printed only by the CLI's no-offence branch; the tree scan that actually runs on every suite run is the spec, and the spec asserts nothing about which files were skipped or how many. Both examples that name the skip path are assertions that cannot fail: 'skips compiled payloads' (line 123) passes through the `File.file?` guard and never reaches the NUL branch, and 'reports what it skipped' (line 95) checks `be_an(Array)` against a memoised `[]` plus a set subtraction whose two symbols are the only ones any writer site produces. So the 0.2.5 fix — skips are announced rather than silent — is unpinned, and the skip set is free to grow to any size with the suite green. The skip set at HEAD is exactly two PNGs, which makes pinning it cheap.

**Reproduce:** In a scratch clone of HEAD (never the real tree): `printf 'built at $HOME/WorkSpace/secret\n\x00trailing\n' > `<probe>.md`, then `ruby -e 'require_relative "scripts/check_home_paths"; p HomePaths.tree_offences.size; p HomePaths.skipped_files'` => 0 offences, the file listed as `reason: :binary`. `cd core && bundle exec rspec spec/meta/home_path_guard_spec.rb` => 10 examples, 0 failures. Then, separately: delete the whole `if content.include?(NUL) ... end` block => still 10 examples, 0 failures; restore it and delete only the two `skipped_files << { ... }` lines (undoing 0.2.5) => still 10 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.188 The home-path scanner dereferences a symlink instead of reading the blob git commits

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** A symlink's content is the string git stores -- `File.readlink` -- rather than whatever the link points at. Both halves of the old behaviour are gone: a live link no longer reads bytes from outside the repository and reports a line number in a file that is not in it, and a broken one no longer returns `[]` with nothing recorded.

The `File.file?` early return was a third silent skip beside the two 0.2.5 announced. It records `:not_a_file` now, which also covers a directory and a file that vanished between being listed and being read -- possible since `RepoFiles.list` began including untracked files.

`offences_in_file` takes `root:` so the two decisions can be driven against a scratch directory. There is no other way to pin them: both are about a file on disk under the root, and the repository is not a place to create one. The pinned example points a link at a target that does not exist, deliberately -- the stored string is the whole content, so nothing needs to be there, and aiming a fixture at a real home directory is the thing this check is about.

**Area:** scripts/check_home_paths.rb

For a symlink, git stores the target string as the blob's entire content — so `ln -s $HOME/... x && git add x` commits and pushes a real home path verbatim. `offences_in_file` never reads that blob: `File.file?` (line 92) and `File.binread` (line 94) both dereference. A broken link fails `File.file?` and returns [] with no `skipped_files` entry at all, so the 0.2.5 guarantee that a file the check could not clear says so does not cover it; a live link is worse than silent, because the scanner reads *the target's* bytes and can report an offence at a line number in a file that is not in the repository. The `File.file?` early return is in fact a third silent skip alongside the two the 0.2.5 fix addressed — it also swallows directories, unreadable files, and files that vanish between listing and read (now possible, since `RepoFiles.list` includes untracked files). Nothing else compensates: gitleaks' default ruleset has no home-path rule and `.gitleaks.toml` adds none, and `release.sh` inspects the packaged VSIX rather than the repository. Latent — the tree has no symlinks today (`git ls-files -s | grep -c ^120000` => 0).

**Reproduce:** In a scratch clone of HEAD: `ln -s $HOME/WorkSpace/secret/nope docs/leak_link && git add docs/leak_link && git cat-file -p :docs/leak_link` prints the real home path that would be pushed. Then `ruby -e 'require_relative "scripts/check_home_paths"; p HomePaths.tracked_files.grep(/leak_link/); p HomePaths.tree_offences.size; p HomePaths.skipped_files'` => the file is listed, 0 offences, and no skip entry. For the live-link half, symlink a file outside the repo and confirm `offences_in_file` reports on the target's content rather than the stored path.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.189 The home-path pattern matches one spelling, so every other spelling of the same real path passes

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17, and it was not hypothetical.** The pattern takes one *or two* separators, so a doubled slash, a Windows doubled backslash and a JSON-escaped solidus are all read as the same real path; and a second pattern reads the hyphen-joined spelling an agent scratchpad produces.

**Widening the scan found that spelling of the maintainer's own home directory already committed to this public tree**, in a register entry written after this finding was raised -- `-Users-<name>-WorkSpace-...`, disclosing the username and the directory layout together. It is removed, and the entry now describes the probe instead of naming it. The username itself is the published Marketplace publisher id, so what was new here was the layout; the point is that the detector could not see any of it.

`Users` only in the hyphen pattern, and no `home`: an English hyphenated phrase ending in "home" is ordinary prose and this scanner's own output strings contain one. Pinned in both directions -- four spellings caught, two hyphenated phrases left alone.

Three documents spelled their illustrations the way a real path is spelled and became findings about themselves once the pattern widened. They describe the shape now, which is `024.126`'s repair for a comment; `SYNTHETIC` was deliberately *not* used, because a placeholder added there is one the detector stops reporting everywhere.

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

PATTERN (line 45) requires exactly one separator character immediately followed by an alphanumeric. Every other on-disk spelling of a real home path is therefore invisible, and the forms are **described rather than spelled here**, because this file is scanned by that pattern and an illustration written the way a real path is written is a finding about the entry (`024.126`): a Windows drive path with the doubled backslash JSON, TypeScript and a pasted fenced block actually store; the JSON escape that puts a backslash before the solidus; a doubled slash; and the agent-scratchpad mangling, where the whole path is joined with hyphens instead of slashes and so discloses both username and directory layout. That last one is the likeliest of the set here, given how much verbatim command output this repository's task documents quote — which is exactly how 0.2.3 leaked. The doubled-backslash case is sharpened by the file itself: line 31 writes that form and says it 'is caught', and the scanner does not flag its own line. The case-sensitivity decision beside it was argued and measured; this one was not considered at all, and the spec pins only the single-backslash Windows form.

**Reproduce:** At HEAD, build each spelling from parts rather than typing it — `["", "Users", "alice", "p"].join("//")` for the doubled slash, `join("\\\\")` for the doubled backslash, and `["", "Users", "alice", "WorkSpace"].join("-")` for the scratchpad mangling — and pass each through `HomePaths.names_in`. Every one returns `[]`, while the single-separator spelling built the same way returns the name. `core/spec/meta/home_path_guard_spec.rb` builds its fixtures exactly this way and is where the pinned versions live.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.190 Annotated tag messages are a pushed public channel neither mode of the home-path check scans

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** `--messages` reads annotated tag bodies as well as commit bodies. 28 tags carry one here; they are hand-written at release time and pushed to the public remote, and neither the tree scan nor the commit scan nor gitleaks read a byte of them. Nothing in them names anyone, so this closes a gap in coverage rather than a live disclosure -- which is the only reason it could wait this long.

`tag_bodies` is split out from `tag_offences` so an example can assert **what was read**. A wrong format string, or a clone fetched without tags, returns nothing and looks exactly like a clean scan -- the shape `shallow?` already refuses for commits, arriving through the other door. The example asserts a floor of twenty substantial bodies.

A second example pins that `message_offences` actually reports the tag half. The mutation manifest is what found that the first one did not: deleting `tag_offences` from the composition left every example green.

**Area:** scripts/check_home_paths.rb, .github/workflows/ci.yml

`message_offences` runs `git log --all --format=...%B`, which prints commit messages only. This repository has 25 annotated tags whose bodies are hand-written at release time, pushed to the public remote, and are not commit messages — 8,005 bytes of prose that neither `--tree` (blob content) nor `--messages` (commit bodies) nor gitleaks (blob rules, and no home-path rule in `.gitleaks.toml`) ever reads. Release time is precisely the moment 0.2.3 pasted a build machine's home directory into a commit message, so this is the same class of channel the check exists for, left uncovered. No tag carries a home path today, so it is latent; a leak here is also harder to repair than a commit one, since republishing tags breaks the `buildCommit` SHAs the Marketplace artifacts reference.

**Reproduce:** At HEAD: `git for-each-ref refs/tags --format='%(objecttype)' | sort | uniq -c` => 25 tag, 4 commit. `git log --all --format='%B' | grep -cF "$(git for-each-ref refs/tags/v0.2.12 --format='%(contents:subject)')"` => 0. Scanning `git for-each-ref refs/tags --format='%(contents)'` through `HomePaths.names_in` finds nothing today, so the gap is in coverage, not in current content. Fix shape: iterate `git for-each-ref refs/tags --format='%(refname:short)%00%(contents)'` in `--messages` mode.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.191 as_utf8's comment describes a hazard the same file's utf8 require already removed

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** scripts/check_home_paths.rb

Lines 67-72 justify `as_utf8` by saying backticks hand back a string in the shell's external encoding, US-ASCII when LANG is unset, so this repository's Japanese commit messages raise on the first `split` under a bare local shell while passing under CI's UTF-8 locale. That was true when it was written (4f19c67) and stopped being true in this release: 7c92b05 added `require_relative "utf8"` at line 4 of the same file, and `scripts/utf8.rb` sets `Encoding.default_external = Encoding::UTF_8` before any backtick runs. The described failure can no longer occur. `.scrub` still earns its place — a commit message can carry genuinely invalid bytes — so the method stays; the paragraph explains the wrong hazard, and a reader deleting the require would be reassured by a comment that no longer covers it. This is the shape CLAUDE.md's revert/documentation rule warns about: the prose was correct when written and nothing about the change announced that it invalidated it.

**Reproduce:** Read scripts/check_home_paths.rb line 4 and lines 67-74 together, then: `env LC_ALL=C LANG=C ruby -e 'require_relative "scripts/utf8"; p Encoding.default_external; p `git log -1 --format=%B`.encoding'` => UTF-8, UTF-8. Drop the require from the probe and the same command prints US-ASCII, US-ASCII. History: `git log -S"Backticks hand back a string tagged" -- scripts/check_home_paths.rb` => 4f19c67; `git log --diff-filter=A -- scripts/utf8.rb` => 7c92b05.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** Confirmed first: under `LC_ALL=C LANG=C` the
backtick result is already UTF-8 with the require, and US-ASCII
without it. The comment now says what `as_utf8` still buys -- `.scrub`,
for a commit message carrying genuinely invalid bytes, which no locale
setting fixes -- and says that deleting the require would bring the
old hazard back, so the two are not read as interchangeable.

## 024.192 The case-sensitivity decision is justified by a count of 37 that was never right

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

Lines 34-44 record a deliberate decision — keep PATTERN case-sensitive — and rest it on a measurement: adding `/i` 'flags 37 lines in this repository ... A check that cries wolf 37 times is a check people switch off.' Re-derived with the file's own PATTERN plus `/i`, its own SYNTHETIC list, the same file set and the same skips: 35 at HEAD, 36 at 54104b4, the commit that wrote the sentence. Never 37. The number is repeated in the spec comment (home_path_guard_spec.rb:81), where it is the reason given for an example that pins the decision, and neither copy is a marked measured claim, so `measured_claims_spec.rb` never re-derives either. The decision itself is still correct and should stand; what is wrong is a claim about this tree that nobody ran, in a file whose neighbouring paragraph makes a point of saying the decision 'was measured rather than assumed'.

**Reproduce:** At HEAD: load scripts/check_home_paths.rb, scan `RepoFiles.list(ROOT)` with `Regexp.new(HomePaths::PATTERN.source, Regexp::IGNORECASE)`, reject `HomePaths::SYNTHETIC`, apply the same NUL/invalid-encoding skips, count lines with at least one hit => 35. Repeat in a clone checked out at 54104b4 using that revision's own `tracked_files` => 36. Fix shape: mark it as a measured claim with a deriver, or state the decision without a number.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16, by removing the number from both copies rather
than correcting it.** Re-derived at HEAD with the file's own
`PATTERN` plus `/i`, its own `SYNTHETIC` list and the same skips: 35,
not 37.

The decision is right and still stands on its stated reason. What
replaces the figure is a *derivation*: `home_path_guard_spec.rb` now
scans this tree with the pattern plus `/i` on every run and asserts a
floor, so the trade-off the decision rests on is re-measured rather
than remembered. A floor rather than a total, deliberately -- the
argument is about an order of magnitude, and asserting the total
would put back the maintained figure this replaces.

Watched failing twice: a pattern whose case-insensitive form flags
nothing, and an enumeration that reads no files.

## 024.193 Existence is a suffix glob and any test: name passes unconditionally, so a citation naming a file that does not exist is accepted

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/release_gate_spec.rb (lines 111-112, the `exists` test)

Existence is `!RepoFiles.list(ROOT, "*#{base}").empty?` — a suffix glob on the basename, never compared against the cited path — and any citation starting `test:` skips the existence test entirely. Three consequences, all reproducible at HEAD: (1) a cited path whose basename is merely a suffix of a real file passes — `scripts/sbom.rb` and `tools/smoke.rb` exist nowhere in the tree yet both are accepted, matching scripts/generate_sbom.rb and vsix_semantic_smoke.rb respectively; (2) the cited path itself is never validated, so `../../../../etc/generate_sbom.rb` is accepted as gate 8's evidence; (3) a nonexistent npm script can never be reported missing — `test:integ` and `test:u` are accepted, and when the wiring half does catch a planted npm citation it reports the false message "exists but nothing invokes it". The practical cost: a script that is renamed or moved leaves its gate green whenever some other file's name ends with the old basename, and a typo in the checklist is indistinguishable from correct evidence.

**Reproduce:** In docs/RELEASE_CHECKLIST.md replace gate 11's `scripts/verify_sbom_against_vsix.rb` with `scripts/sbom.rb` `tools/smoke.rb`; `ls scripts/sbom.rb tools/smoke.rb` => No such file; `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 0 failures. Replace gate 8's `scripts/generate_sbom.rb` with `../../../../etc/generate_sbom.rb` => 0 failures. Replace gate 4's `test:unit`/`test:integration` with `test:integ`/`test:u`; `grep -c '"test:integ"' vscode/package.json` => 0; re-run => 0 failures. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** Existence is membership in the tracked file
list, not a suffix glob; a citation written as a bare basename must
match some file's basename exactly, which is the honest equivalent
when no directory was written and still rejects a name that is merely
a suffix of a real one. An npm citation is an exact key of
`vscode/package.json`'s `scripts`, and its wiring test is bounded so
a shorter name is not satisfied by a longer one.

All three of the entry's reproductions watched failing: the two paths
that exist nowhere, the traversal path, and the two npm names.

## 024.194 release_gate_spec's wiring corpus includes untracked files, so uncommitted local text satisfies a gate's "something invokes this"

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/release_gate_spec.rb (`haystack_excluding`, line 92), scripts/repo_files.rb

024.147 made RepoFiles list untracked-but-not-ignored files so that checks are not blind to a file being written before it is committed. That argument is about the files a check *inspects*. release_gate_spec applies it to the corpus it treats as *evidence of invocation*: every file of every extension under core/spec and scripts, tracked or not, is joined and searched. An uncommitted scratch file that merely names a script basename therefore flips a gate from 'nothing invokes this' to 'wired'. That consequence is nowhere argued — untracked_visibility_spec.rb and repo_files.rb both justify the inspection side only — and it means the check can pass for a reason that does not exist in any commit, which is the same failure the spec's own comment says round 1 caught. Distinct from the substring defect: requiring an invocation-shaped line would not fix it, since an untracked file can contain an invocation-shaped line.

**Reproduce:** First remove the three non-comment mentions of generate_sbom.rb (core/spec/meta/sbom_spec.rb:19, scripts/verify_sbom_against_vsix.rb:27, core/spec/meta/pinned_mutations.yml:179) so the check correctly reports "gate 8: scripts/generate_sbom.rb exists but nothing invokes it". Then create an untracked file `scripts/notes.txt` containing the single line `todo: look at generate_sbom.rb tomorrow` — `git check-ignore -v scripts/notes.txt` reports it is not ignored — and re-run `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 0 failures. Delete the scratch file and revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16 by splitting the two questions one helper was answering

Reproduced exactly: with the three real invocations of the SBOM
generator removed the gate correctly reports it unwired, and one
uncommitted scratch file under `scripts/` naming the basename turns
it green again.

`RepoFiles.tracked` is the committed-only half, and
`release_gate_spec`'s wiring corpus reads it. `024.147`'s argument is
about the files a check *inspects*; this corpus is what the check
accepts as evidence that something happens, and "nothing runs this"
must not be answered on evidence no commit contains. The `exists`
lookup beside it still reads `RepoFiles.list`, deliberately, and the
comment at each says why they differ.

Pinned by an example that writes an untracked probe under `scripts/`
and asserts the corpus does not read it -- watched failing with the
call site put back to `RepoFiles.list`.

## 024.195 Every prose statement of what the preflight gate runs is stale, and nothing derives any of them

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/preflight.rb` (header, line 17), `CONTRIBUTING.md` + `.ja.md`, `docs/design/tasks/024-deferred-review-findings.md` (024.143)

`ruby scripts/preflight.rb --list` prints **8** checks naming **6** distinct scripts (`documented_counts.rb`, `check_home_paths.rb`, `check_doc_links.rb`, `reindex_findings.rb`, `check_swallowed_failures.rb`, `check_site_links.rb`) plus two `rspec` invocations. Four passages describe that gate and no two agree with it or with each other: `scripts/preflight.rb:17` says "the checks are in six places (the suite, three scripts, a git state, a derived number)" -- and **no check inspects git state at all**; `CONTRIBUTING.md:147` and `CONTRIBUTING.ja.md:140` say seven; `024.143` says "Seven things must be true" (:7731), "They live in seven places" (:7734) and "runs all seven" (:7746). `024.143` is stale in two further ways the same round already fixed in `CLAUDE.md` and left here: it says "the two real-Rails-backed suites" where there are three (`real_rails_spec`, `capabilities_spec`, `client_behaviour_spec`), and its second bullet still states the count-based rule -- "It asserts a non-zero example count rather than reading the exit status" -- which is precisely the arrangement `024.148` records as the defect and `8f1d4f4` replaced with `CheckSuitesRan.complaints`. So the register's own account of the gate instructs a reader to rely on the check the register elsewhere says could not fail. The eighth check was added by `024.145` inside this release, and every one of these statements drifted inside the release that added it. Root cause: these are hand-typed numbers about this tree, which `CLAUDE.md` says must be derived -- and the mechanism for that, `measured_claims_spec.rb`'s `<!-- measured: -->` markers, globs only `docs/**/*.md`, `core/lib/**/*.rb`, `core/spec/**/*.rb` and `vscode/src/**/*.ts`, so neither `CONTRIBUTING.md` nor anything under `scripts/` can carry a checked claim. A `preflight-checks` deriver plus widening that glob list closes the whole family.

**Reproduce:** `ruby scripts/preflight.rb --list | grep -c '^[a-z]'` -> 8. Then read `sed -n '13,20p' scripts/preflight.rb`, `sed -n '145,150p' CONTRIBUTING.md`, `sed -n '138,143p' CONTRIBUTING.ja.md`, and `sed -n '7729,7750p' docs/design/tasks/024-deferred-review-findings.md`. Confirm the absent git-state check with `ruby scripts/preflight.rb --list | grep -i git` (no output).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16 by removing the enumeration, not by correcting it

Found again the moment a ninth check was added (`024.220`'s session
checker): four places stated the count and three of them were already
wrong, including `preflight.rb`'s own header, which named "a git state"
among the checks when no check inspects git state.

Correcting four numbers leaves four numbers to drift. What was done
instead: **no prose states what preflight runs.** `CLAUDE.md`,
`CONTRIBUTING.md`, `CONTRIBUTING.ja.md` and `preflight.rb`'s header all
point at `ruby scripts/preflight.rb --list`, which derives the list from
the array that runs.

One property is still stated in prose, deliberately, because the list
cannot show it: the three environment-dependent suites are run
separately and read per-example status rather than counts. That sentence
is about *why* the gate is shaped as it is, and it does not go stale
when a check is added.

Historical statements in `046` and in earlier register entries are left
as they are: they record what was true when they were written, and
rewriting a record to match the present is the opposite of what this
entry is about.


## 024.196 The measurement that justifies reading per-example status is quoted three times, attributed to a different file each time, and matches none of them

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.17
```

**Fixed in 0.2.17.** None of the three places quotes an example count now. The argument is about the *shape* -- a suite that skipped in full reports every one of its examples as pending, zero failures, and exit 0 -- and the shape is what makes a count-based rule unable to fail. A number was never load-bearing in it.

Each of the three had drifted differently, which is what a frozen figure does: `scripts/preflight.rb` attributed it to `real_rails_spec.rb`, contradicting the entry it cites as its authority in the same comment; `scripts/check_suites_ran.rb` attributed it correctly to the e2e suite, which had since grown; `CLAUDE.md` named no file at all, added by a round that was fixing a different defect in the same paragraph.

Pinned by `core/spec/meta/record_corrections_spec.rb` in both directions: none of the three carries the frozen figure, and all three still make the argument -- so deleting the paragraph is not how it passes. Watched failing against `HEAD`, where all three carried it.

**Area:** `scripts/preflight.rb:52-57`, `scripts/check_suites_ran.rb:17-23`, `CLAUDE.md:505-511`

The argument for `024.148`'s fix rests on one measurement -- what a fully skipped suite reports. It is quoted in three places as "45 examples, 0 failures, 41 pending", and at HEAD it belongs to none of them. `scripts/preflight.rb:54` attributes it to `spec/integration/real_rails_spec.rb`, which has **16** examples -- and `024.148`, the entry that comment cites as its authority, itself says "all 16 `real_rails` examples marked pending", so the comment contradicts its own citation. `scripts/check_suites_ran.rb:18-19` attributes it correctly to the e2e capability suite, but that suite now has **57**. `CLAUDE.md:509` repeats the figure with no file named at all, added by round 3 while it was fixing a different defect in the same paragraph -- so a round that existed to make the record true propagated a stale number into the operating document. A measurement is a claim (`CLAUDE.md`, "A measurement is a claim, and it needs the same care as a test"); this one is unpinned, misattributed, and now carried in three files that must agree about it -- the `042` D8 shape, a thing assembled three times.

**Reproduce:** From `core/`: `bundle exec rspec --dry-run spec/integration/real_rails_spec.rb` -> 16 examples; `bundle exec rspec --dry-run spec/e2e/capabilities_spec.rb` -> 57; `bundle exec rspec --dry-run spec/meta/client_behaviour_spec.rb` -> 7. Then `sed -n '52,58p' scripts/preflight.rb`, `sed -n '17,24p' scripts/check_suites_ran.rb`, `sed -n '505,512p' CLAUDE.md`, and `sed -n '8060,8066p' docs/design/tasks/024-deferred-review-findings.md` for 024.148's own "16".

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Retargeted to 0.3.0 in 0.2.16's closing pass.** Driven during that
release's backlog sweep, with a control in its own fixture, and still
reproduces. It is not fixed in 0.2.16 and the target says so rather
than naming a release that has shipped.

## 024.197 0.2.14's review loop edited its own standard and added a capability between rounds, with no departure recorded

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
released-in: 0.2.18
```

**Recorded in 0.2.18 as the departure `CLAUDE.md` requires.**

The rule is "Departing from this rule is written down, where the release
is recorded". `046` now records it: each round was given `CLAUDE.md` as
its standard, three of the four commits in the range edited `CLAUDE.md`,
and the three rounds were therefore held to three standards — so their
counts, 18 / 70 / 63, are not comparable the way the cadence rule
assumes.

Written four releases late, which is itself the finding: a departure
noticed by a later audit rather than by the round that made it is a
departure nobody chose. `024.36` is the same failure arriving through
the *instructions* rather than through the standard.

**Area:** `CLAUDE.md`, `docs/design/tasks/046-0.2.14-making-the-record-true.md`

`046:505` states that each round was given "`CLAUDE.md` and `AGENTS.md` ... as the standard to hold it to". `CLAUDE.md` was edited by three of the four commits in the range: `8f1d4f4` (round 1) softened the trusted-root paragraph; `54b7274` (round 2) added a new mandatory section, "Writing a check means writing bait for the other checks" (+29 lines); `6155cf4` (round 3) added another, "Promoting a finding is making a claim" (+39/-2), plus the preflight paragraph. Rounds 1, 2 and 3 were therefore each held to a different standard, and their finding counts (18 / 70 / 63) are not comparable in the way `CLAUDE.md`'s cadence rule assumes -- the same failure `024.36` records for 0.1.15, arriving through the standard rather than through the prompt. Separately, `e100388`, between rounds 2 and 3, extended `scripts/check_pinned_mutations.rb` to `scripts/` (+18 lines), added seven manifest entries and refactored `scripts/documented_counts.rb` to extract a pure function. `CLAUDE.md:50` says "During a review loop, fix; do not add ... every addition between rounds resets it", and `046:349` invokes that exact rule to decline an `AGENTS.md` restructure in the same release -- so the rule was applied to a documentation change and not to a change in the checking machinery the rounds are measured with. `CLAUDE.md` requires that "Departing from this rule is written down, where the release is recorded"; the only recorded departure in `046` is the one about the `drive` method. This one is written down nowhere, and the release shipped.

**Reproduce:** `git log --oneline main..HEAD -- CLAUDE.md` -> 7c92b05, 8f1d4f4, 54b7274, 6155cf4 (the last three are the round commits). `git show 54b7274 -- CLAUDE.md` and `git show 6155cf4 -- CLAUDE.md` show the two added mandatory sections; `git show 8f1d4f4 -- CLAUDE.md` shows the softened trusted-root paragraph. `git show --stat e100388 -- scripts/check_pinned_mutations.rb core/spec/meta/pinned_mutations.yml scripts/documented_counts.rb`. Then `grep -rn 'do not add' docs/ CLAUDE.md AGENTS.md CHANGELOG.md` -- the only recorded departure (`046:497`) is about the `drive` method, and `046:1299` is this finding still sitting untriaged in round 3's own list.

**Re-triaged in 0.2.17** (`024.276`). `CLAUDE.md` was edited by three of the four commits in 0.2.14's range, so each round was held to a different standard and their counts are not comparable — and a mandatory section was added between rounds with no departure recorded, which the rule about not adding during a loop exists to prevent. About how this project reviews itself; patch-line work, and it belongs beside `024.167`.

## 024.198 The packaged-artifact inspection count is derived from the directory alone, so a grep aimed at the wrong pattern or with wider exclusions still reports a healthy count

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `vscode/scripts/release.sh` lines 165-193, `core/spec/meta/release_script_guard_spec.rb` (`"makes the artifact check say what it inspected…"`)

The INSPECTED countermeasure was added so that "aimed at nothing" becomes visible, and release.sh's own comment states the principle: "A count that is not derived from what was actually searched guards the variable rather than the search." It still guards the variable. `find "$INSPECT_ROOT"` and the grep share only `INSPECT_ROOT`; "aimed at nothing" has three dimensions — directory, pattern, exclusion set — and the count covers one. Changing the pattern to `"$HOME/.ovallsp-never-exists"`, or appending `--exclude='*.js' --exclude='*.json' --exclude='*.map' --exclude='*.rb'`, makes the check match nothing while the log still prints `PASS: packaged-artifact path inspection (N files inspected)` with the same four-figure N, and every text assertion stays true because the literal `grep -rlF --exclude` and `INSPECTED=` are untouched. This is a defect in the countermeasure that `024.151` holds up as direction #1 ("every check states its own coverage… this kills the whole narrow-the-input family at once"): coverage stated as a file count does not kill it. Recording it separately so that correction is not lost inside the class entry.

**Reproduce:** Scratch mirror as above. (a) Change line 174's pattern to `"$HOME/.ovallsp-never-exists"` → 10 examples, 0 failures. (b) Instead, append `--exclude='*.js' --exclude='*.json' --exclude='*.map' --exclude='*.rb'` to line 174 → 10 examples, 0 failures. Behaviour: build a fake artifact of 150 plain files plus one `.js` containing `$HOME`; the shipped grep lists the leaking file, both mutants match nothing, and all three print `PASS: packaged-artifact path inspection (151 files inspected)`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16, and the entry's own direction was not sufficient.**
Measured against a 151-file fake artifact holding one leak: replacing
`find` with `grep -L` catches an unreachable directory and nothing
else -- a pattern that matches nothing still counts 151, a widened
exclusion set still counts 150 against the shipped 150.

What covers the other two dimensions is a **positive control**: a
scratch directory of files that certainly contain the pattern, in the
extensions an exclusion could be widened to cover, which the same
command with the same flags must find all of. Its *content* is
written from `$HOME` rather than from the check's own variable, so
changing what is searched for cannot change what is planted.

A fourth mutation the entry does not list survived all of that:
widening the exclusions on the inspection grep alone, leaving the
count and the control untouched and green, and shipping the leak.
That is three copies of one list, which is this entry's own defect
one level in. There is now one list all three read, and
`release_script_guard_spec.rb` fails on an invocation that adds an
exclusion of its own -- watched failing.

## 024.199 The guard spec's absolute-grep pin is satisfied by the advisory grep, and its bare-grep scan cannot see an indented call

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/release_script_guard_spec.rb` lines 188-191, `vscode/scripts/release.sh` lines 174-181

Two holes in one example, `"calls the grep it means, not whatever the shell resolves"`. (a) `expect(code).to include("/usr/bin/grep -rlF")` is satisfied by line 179 — the *advisory* grep whose output goes to /dev/null and which only prints a note — so the hard-failure grep on line 174 need not be absolute at all. (b) The scan `/(?:^|[|&;(]\s*|\bif\s+|!\s*)grep\s/` requires `grep` at a line start with no leading whitespace, or immediately after `| & ; (`, `if `, or `!`. Any indented bare `grep` escapes, as do `; then grep`, a backticked grep and a continuation line after `&& \` — and almost every grep inside an `if` or a function body is indented, so the scan misses the common case. Together they let the release script's one credential-leak check fall back to whatever `grep` the shell resolves — which is the ugrep-wrapper failure mode 0.2.3 filed and withdrew a register entry over, and the reason release.sh calls `/usr/bin/grep` by absolute path in the first place.

**Reproduce:** Scratch mirror as above. Replace release.sh line 174 with: ``` artifact_carries_home_path() { grep -rlF --exclude='*.bundle' --exclude='*.so' --exclude='*.dylib' "$HOME" "$INSPECT_ROOT" } if artifact_carries_home_path; then ``` From `core/`, `bundle exec rspec <m>/core/spec/meta/release_script_guard_spec.rb` → 10 examples, 0 failures, with the hard-failure grep now shell-resolved.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16

(a) The absolute-path pin is asserted inside the hard-failure grep's
own `if ... fi` window rather than over the whole file, so the
advisory grep -- the one whose output goes to /dev/null and whose
only effect is printing a note -- can no longer satisfy it alone.

(b) The scan is a whole-word one, `grep` preceded by neither a path
separator nor a word character, so position stops mattering.
Measured against this entry's own reproduction, which moves the
refusal into a shell function and leaves the call indented: the old
scan returns nothing and the old whole-file `include` still passes,
while the new pair reports it.

## 024.200 Nothing checks that release.sh parses, so a syntax error past the first refusal leaves every check green

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `vscode/scripts/release.sh`, `core/spec/meta/release_script_guard_spec.rb`, `.github/workflows/`

Nothing anywhere runs `bash -n` or shellcheck on release.sh — not the guard spec, not CI (there is no shell-syntax job in `.github/workflows`). Every non-executed assertion is a text match, and the three executed examples exit at line 55 or line 83, so bash's parser never reaches anything later. An unterminated `if` introduced anywhere past line 83 leaves the only publish path unrunnable while the suite is green, and it is discovered by the person attempting the release, at the moment they attempt it. One line fixes it: `expect(system("bash", "-n", SCRIPT)).to be(true)`. `vscode/scripts/verify-installed-extension.sh` has the same exposure and no spec at all.

**Reproduce:** Scratch mirror as above. Prefix `echo "-- SHA-256 --"` with `if [ -n "$VSIX_PATH" ]; then` and add no closing `fi`. `/bin/bash -n <m>/vscode/scripts/release.sh` → `line 255: syntax error: unexpected end of file`, exit 2. From `core/`, `bundle exec rspec <m>/core/spec/meta/release_script_guard_spec.rb` → 10 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16

One example runs `bash -n` over every shell script beside
`release.sh`, so `verify-installed-extension.sh` -- which had no spec
at all -- is covered by the same line. Watched failing on this
entry's mutation, an `if` opened before the SHA-256 echo with no
closing `fi`, which leaves the only publish path unrunnable with
every other example green; and again on a deliberate break in the
other script.

## 024.201 The NOT YET escape hatch is guarded against a hand-copied two-suite list that has drifted from the three-suite table it covers

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/ci_skip_guard_spec.rb, scripts/check_suites_ran.rb, core/spec/meta/client_behaviour_spec.rb

`CheckSuitesRan::SUITES` names three spec files that skip themselves for want of an environment, and `ALLOWED_PENDING = "NOT YET"` exempts a pending example whose message says so. The example that stops that exemption swallowing the environment skip -- "does not exempt the environment skip it exists to catch" -- iterates a hand-written two-element array (real_rails_spec, capabilities_spec) instead of the three-element table it is meant to cover. `spec/meta/client_behaviour_spec.rb`, added to SUITES in the same release, is unguarded. So `skip("NOT YET -- vscode/node_modules is not installed")` leaves every check green, and check_suites_ran then prints its success line -- "all 7 client-behaviour examples ran." -- and exits 0 for a run in which the two examples docs/CLIENT_BEHAVIOUR.md marks **checked** never executed. The checker states the opposite of the truth in its own output, which is the failure 024.148 was written to close, reopened for the third file that entry's own table lists. Secondly, the loop cannot simply be extended: the scan is `/^\s*skip\s+"([^"]+)"/`, which requires the paren-less form; client_behaviour_spec writes `skip("...")`, so adding the path makes the example fail on `not_to be_empty` rather than check anything. The fix is one place iterating `CheckSuitesRan::SUITES` with a regex that accepts `skip(` -- the hand-copied list is the defect, not the missing element.

**Reproduce:** In a scratch worktree at HEAD: `sed -i '' 's/skip("vscode\/node_modules is not installed")/skip("NOT YET -- vscode\/node_modules is not installed")/' core/spec/meta/client_behaviour_spec.rb`, then `cd core && bundle exec rspec spec/meta` -> 192 examples, 0 failures. With `vscode/node_modules` absent, `bundle exec rspec spec/meta/client_behaviour_spec.rb --format json --out /tmp/cb.json`, then from the repo root `ruby -e 'require "./scripts/check_suites_ran"; require "json"; r=JSON.parse(File.read("/tmp/cb.json")); s={"client-behaviour"=>"spec/meta/client_behaviour_spec.rb"}; p CheckSuitesRan.complaints(r, suites: s)'` -> `[]`, while two of the seven examples are pending. For the second half, add `spec/meta/client_behaviour_spec.rb` to the array at ci_skip_guard_spec.rb:128 and run that file -> 13 examples, 1 failure, `expected [].empty? to be falsey`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16 by reading the table instead of a copy of it

Reproduced: `NOT YET` on the client-behaviour suite's environment
skip left the whole of `spec/meta` green, and
`CheckSuitesRan.complaints` returned `[]` for a report in which two
of seven examples were pending.

The example iterates `CheckSuitesRan::SUITES`, so a fourth suite
added to that table is guarded on the day it is added. The scan
accepts the paren form *and* ignores position: the third file writes
its skip inside a one-line `before { ... }`, where a line-anchored
scan finds nothing -- so widening only to `skip(` would have left the
example passing on an empty result had `not_to be_empty` not been
there. Both shapes watched red.

## 024.202 The release-tag accounting invariant runs nowhere continuous: the job that runs the suite checks out without tags

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/release_artifacts_spec.rb, .github/workflows/ci.yml, scripts/check_suites_ran.rb

release_artifacts_spec's two tag examples -- "accounts for every tag, in one table or the other" and "records no version that was never tagged" -- call `skip` when `git tag --list 'v*'` is empty. The core job, the only job that runs the suite, checks out with a bare `- uses: actions/checkout@v4` (ci.yml:23): no `fetch-depth`, no `fetch-tags`, so the checkout has no tags and both examples are pending on every CI run while rspec exits 0. Nothing watches those pendings. The file is not in `CheckSuitesRan::SUITES`, so the skip guard has no opinion on it, and ci.yml's "Fail if a documented-count check skipped" step reads only documented_counts_spec.rb. This is exactly the shape the skip guard exists to prevent -- a suite that skipped for want of an environment reported as a suite that passed -- occurring in a file the guard does not cover. The invariant is not entirely unenforced: preflight.rb runs the full suite before a commit, and a maintainer's checkout has tags, so it does execute there. But it is unenforced anywhere continuous, and it is the invariant written because 0.1.14 and 0.1.15 were tagged, never built, and noticed only by someone looking at the Marketplace by eye. A contributor's PR, and a reviewer reading a tarball or a `git archive` extraction, both get a vacuous pass. Candidate fixes, each with a cost the entry should weigh: give the core job's checkout `fetch-tags: true` and add the path to `CheckSuitesRan::SUITES` (but a tarball reviewer would then fail rather than skip); or move the two tag examples to a job that already fetches full history -- secret-scan checks out with `fetch-depth: 0`.

**Reproduce:** `sed -n '23,25p' .github/workflows/ci.yml` -> the core job's checkout takes no `with:` block. Then, with a stub that makes `git tag` return nothing: `mkdir -p $SCRATCH/stub && printf '#!/bin/sh\nfor a in "$@"; do case "$a" in tag) exit 0;; esac; done\nexec /usr/bin/git "$@"\n' > $SCRATCH/stub/git && chmod +x $SCRATCH/stub/git && cd core && PATH=$SCRATCH/stub:$PATH bundle exec rspec spec/meta/release_artifacts_spec.rb` -> 4 examples, 0 failures, 2 pending, exit 0. Without the stub the same command is 4 examples, 0 failures, which is why the gap is invisible locally (this checkout has 29 v* tags).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16, with the belief about the checkout made checkable

Reproduced with `git tag` stubbed empty: 4 examples, 0 failures, 2
pending, exit 0 -- which is what every CI run got, the core job
checking out bare.

Two changes. The core job's checkout asks for tags. And ci.yml's
documented-count guard, which read one hard-coded filename, reads a
list now with `spec/meta/release_artifacts_spec.rb` on it -- so if
the tags do not arrive the build goes red rather than the invariant
going on being vacuously green. A line about `actions/checkout` is a
claim about something outside this tree, and this is what makes it
checkable instead of believed.

Deliberately not `CheckSuitesRan::SUITES`: a reviewer reading a
source tarball or a `git archive` extraction has no tags either, and
for them skipping is the right answer. The guard is CI-only text, so
only CI can never take the skip -- and `024.203`'s helper is what
keeps that text from being deleted or disabled unnoticed.

## 024.203 suites_ran_spec's ci.yml link asserts a text substring, so it passes for a step that has been deleted, commented out, or disabled

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/suites_ran_spec.rb

The example "is what ci.yml runs, not a second implementation" reads the whole workflow file and asserts `include("scripts/check_suites_ran.rb")`. A commented-out step keeps that text, as does a step carrying `if: false` or `continue-on-error: true`, so the example passes under every mutation it appears to guard against. ci_skip_guard_spec.rb's header comment states precisely why that form is wrong -- 0.2.3 merge round 6, a text slice stays green when the step is commented out -- and that file does it correctly, locating the step in parsed YAML. So this example costs no coverage today: it is backstopped. What it costs is trust. It reads as an independent guard on the link 024.148 was written to establish, and a reader who relies on it gets nothing. Under CLAUDE.md's rule that an assertion which cannot fail in the case it names is not a test, it should either assert the parsed step the way its neighbour does, or be deleted with a pointer to the file that already checks this. Recorded separately from the `if`/`continue-on-error` entry because the reproduction and the consequence differ: that one is a real coverage gap, this one is a misleading guard over covered ground. A single fix -- one helper both files call -- would close both.

**Reproduce:** In a scratch worktree at HEAD, replace the two lines of the guard step in .github/workflows/ci.yml with commented-out copies (` # - name: Fail if the real-Rails or capability suites were skipped instead of run` / ` # run: ruby scripts/check_suites_ran.rb core/tmp/rspec.json`). Then `cd core && bundle exec rspec spec/meta/suites_ran_spec.rb` -> 6 examples, 0 failures; `bundle exec rspec spec/meta/ci_skip_guard_spec.rb` -> 1 failure on "still runs in the core job at all", which is the only thing that catches it. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

### Fixed in 0.2.16 by one helper both files read

`core/spec/support/ci_workflow.rb` locates a step in the parsed YAML.
`suites_ran_spec`'s example asserts the located step's `run`, so a
commented-out step fails it -- watched, having first watched the
substring form pass on exactly that mutation.

`CiWorkflow.executed?` closes the sibling `046`'s round 2 recorded at
the same time: `if:` or `continue-on-error: true` leaves every
asserted string in place and turns the gate green. This example and
`ci_skip_guard_spec`'s "still runs in the core job at all" both
assert it now, watched failing against `if: false`. `ci_skip_guard_spec`
reads the same helper rather than keeping its own parse, which is the
divergence that produced this entry.

## 024.204 The `git ls-files` guard reads 49 files in two directories, so the enumeration it forbids is invisible everywhere else in the tree

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/untracked_visibility_spec.rb

The example is titled "is the only way this tree enumerates its own files" and its failure message says "these enumerate the repository the old way", but line 78 reads `scripts/*.rb` and `core/spec/meta/*.rb` — 49 files, against 340 tracked non-vendor `.rb` files. git's `*` does cross `/`, so the `scripts/` half is fine; `core/spec/meta/*.rb` reaches neither `core/spec/support/` (which already holds two shared helpers the meta specs depend on, so moving an enumeration there is an ordinary refactor) nor `core/spec/ovallsp/`, `core/spec/spec_helper.rb`, `core/spec/e2e/`, `core/spec/integration/`, `.github/workflows/`, `vscode/`, or `Rakefile`. Line 79 widens the same hole from the other side: `next if rel.end_with?("scripts/repo_files.rb")` is a suffix match, so `scripts/*/repo_files.rb` is silently exempt, when the one file that needs exempting has a known exact path. The scope decision is neither stated at the site nor asserted — the class round 2 fixed for `check_doc_links` by making per-root coverage an assertion. Latent rather than live at HEAD: I scanned all 544 tracked non-vendor, non-site files for a non-comment `git ls-files` and found no offender outside the guard's scope (the out-of-scope hits are prose in `docs/DOCUMENTATION_MAP{,.ja}.md`, `028`, `046`, and a quoted code line at `core/spec/meta/pinned_mutations.yml:156`).

**Reproduce:** From a clone at aa1185f: `printf '\nPLANTED = `git ls-files docs` if false\n' >> core/spec/ovallsp/cold_indexer_spec.rb`, then `cd core && bundle exec rspec spec/meta/untracked_visibility_spec.rb` -> 3 examples, 0 failures. Same result for `core/spec/support/unspellable.rb`. Control: the identical line in `core/spec/meta/spec_constants_spec.rb` -> 1 failure naming the file. For the exemption: `scripts/xscripts/repo_files.rb` containing a backtick `git ls-files docs` -> 3 examples, 0 failures; renamed to `scripts/xscripts/other.rb` -> 1 failure.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The guard reads the whole tree minus vendored
and generated directories rather than two globs, and the exemption is
an exact path rather than a suffix. Markdown is excluded, stated as a
decision: a document cannot spawn a subprocess, and six tracked
documents discuss this rule by name, so scanning them would report
the rule's own explanation as a violation of it. The mutation
manifest's quotation of the exempt file's own line is exempted *from
the manifest*, so the exemption cannot outlive the entry it is about.

A coverage floor and a membership assertion make an empty scan fail,
which was the other half of the entry. Both planted offenders from
the reproduction watched failing, and the suffix-exemption case too.

## 024.205 The duplicate-heading check tracks a fence by its character and not its length, so a four-backtick block leaves the rest of the file unread

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb

`headings_in` (lines 37-51) stores `marker[0]` — the fence character, discarding the length. CommonMark closes a fence only on a marker of the same character AND at least the opener's length, so inside a ````-fenced block that quotes ```-fenced code (the markdown-in-markdown shape this repo writes constantly), the inner ``` is read as the closer and the real ```` closer then opens a fence that never closes. Every heading from that line to EOF is invisible, and nothing asserts the fence state is closed at EOF, so the check reports a file clean having examined none of it — `CLAUDE.md`'s named pattern, a check that cannot see the thing it checks reporting what a working check reports. Latent at HEAD (0 of 118 tracked Markdown files use a 4+ char fence, 0 end with an open fence), but this is the shape a fix for the h3/indentation gaps would make more likely, since quoting Markdown inside Markdown is how those documents are written. Direction: close only on a marker of the same character and >= the opener's length, and assert the fence state is closed at EOF for every file scanned (a structural coverage assertion, not a maintained number).

**Reproduce:** From a clone at aa1185f, write `<probe>.md` containing `# T`, a blank line, a ```` line, a ```ruby line, `x = 1`, a ```` line, a blank line, then `## Dup`, `a`, `## Dup`, `b`. `cd core && bundle exec rspec spec/meta/duplicate_headings_spec.rb` -> 3 examples, 0 failures. Control: the same file without the fence block -> 1 failure, "documents stating a heading more than once". Remove the file.

### Fixed in 0.2.16

Reproduced first, and the latency the entry claims re-derived at this
revision rather than quoted forward: of the tracked Markdown documents,
none uses a fence marker longer than three characters and none is left
with a fence open at end of file.

The scan stores the whole marker and closes only on the same character
at a length at least the opener's, so a three-character fence quoted
inside a four-character one is content.

The second half matters more than the first. "No repeated heading" and
"the scan stopped reading at line twelve" were the same report, so the
scan now returns its fence state alongside the headings and a second
example fails on any document left with a fence open at EOF. A
structural property, not a maintained number: it says the check read the
file, whatever the file turns out to contain.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.206 The duplicate-heading check sees only unindented h1 and h2, while `024.140` records the guarantee as every heading

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb, docs/design/tasks/024-deferred-review-findings.md

The heading pattern is `/\A\#{1,2} \S/` — h1 and h2, column zero only. Two consequences and one record defect. (a) h3+ is never checked, and that is exactly the motivating incident: register entries and design documents carry `###` subsections routinely, so a scripted edit whose end boundary misses inside one pastes it back with the offender count unchanged. Five tracked files already state a heading twice at h3 and the check calls the tree clean: `docs/design/docs/08-implementation-plan.md` (`### Deliverables`, `### Exit criteria`), `docs/design/tasks/024-deferred-review-findings.md` (`### What was kept`), `docs/design/tasks/034-diagnostics-precision-review-gpt-5.6-sol.md` (`### Proposed correction`), `vscode/CHANGELOG.md` (`### Details`), `vscode/CHANGELOG.ja.md` (`### 詳細`). (b) A heading indented up to three spaces, or nested to a list item's content column, is a heading to every renderer and is not collected at all — while the fence regex in the same function is `/\A\s*.../` and does tolerate indentation. (c) The record: `024.140` states the guarantee as "**no tracked Markdown document states the same heading twice**" and the spec's own comment as "the same question asked of every tracked Markdown document". Both are false at HEAD, and nothing in either place records the h1/h2 scoping or argues for it. Direction: `/\A {0,3}\#{1,6} \S/`, normalise leading whitespace before tallying, and either raise the level or write the scoping down where the guarantee is stated.

**Reproduce:** From a clone at aa1185f: `<probe>.md` with `# I`, blank, `### Dup`, `a`, blank, `### Dup`, `b` -> `cd core && bundle exec rspec spec/meta/duplicate_headings_spec.rb` reports 3 examples, 0 failures. Repeat with ` ## Dup` (three leading spaces) twice -> 3 examples, 0 failures. Control: `## Dup` twice at column zero -> 1 failure. For the record half, no clone needed: run the spec's own `headings_in` with the level raised to 6 over `RepoFiles.list(root, "*.md")` and it names the five files above.

### Fixed in 0.2.16

Reproduced first, both halves and the record half: at level 6 keyed on
the heading text alone, the tracked Markdown gives five offenders — the
five files the entry names, and no others.

The check now reads levels one to six and tolerates up to three leading
spaces, which is what a renderer reads as a heading.

**The level raise is affordable only because the tally is keyed on the
heading path** — the nearest enclosing headings plus its own text —
rather than the text alone. The entry understates this half: every one
of those five repeats is a legitimate section name under a *different*
parent, a per-release or per-task subsection, not a pasted block. A
pasted block duplicates its parent too, so it still repeats the whole
path. Same tracked Markdown, same level: five offenders keyed on the
text, none keyed on the path.

The path keying is stated with its own failing case, or it could not be
told from a rule that reports nothing: an example asserts that the same
subsection name under two different parents is left alone.

The record half needs no wording, which is the better outcome of the two
the entry offers: there is no scoping left to write down.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.207 Two decisions in the duplicate-heading fence parser have no fixture that can distinguish them

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb

`CLAUDE.md`: a behavioural line that no test fails on when it is reverted is a defect regardless of whether the behaviour is correct. Two mutations of `headings_in` leave all three of the spec's examples green and produce zero offenders across all 118 tracked Markdown files: (1) replacing `elsif marker[0] == fence then fence = nil` with an unconditional `fence = fence.nil? ? marker[0] : nil`; (2) deleting the `~{3,}` alternative from the marker regex. Mutation (1) removes precisely the rule the comment above the method asserts — "a fence closes on the same marker -- so a ``` inside a ~~~ block is content, which is how this file's own examples stay quotable" — so the spec states a guarantee in prose that its own fixtures cannot tell the difference about. The spec's fixtures use only backtick fences and never nest one marker inside the other, which is why neither mutation is visible.

**Reproduce:** Extract `headings_in` verbatim and run it against these two fixtures. For (1): `# Doc` / blank / `~~~markdown` / ``` / `## Quoted` / ``` / `~~~` / blank / `## Real` / x / `## Real` / y — original returns ["# Doc","## Real","## Real"], the always-toggle mutant returns ["# Doc","## Quoted","## Real","## Real"]. Note this fixture does NOT distinguish (2). For (2) use `# Doc` / `~~~` / `## Quoted` / `~~~` / `## Real` / `## Real` — original ["# Doc","## Real","## Real"], no-tilde mutant ["# Doc","## Quoted","## Real","## Real"]. Both fixtures need adding as examples; a decision inside a spec cannot go in `pinned_mutations.yml` (024.151 records why the applier is unsafe for spec files).

### Fixed in 0.2.16

Both mutations reproduced first, against the scan as `024.205` and
`024.206` left it rather than as the entry found it, and both fixtures
still distinguish exactly the one decision the entry says they do.

Two examples, one per decision, each asserting the scan's exact return
value rather than "no offenders" — which is what makes them
distinguishing. A backtick fence nested inside a tilde fence pins "a
fence closes on the same marker"; a bare tilde fence pins that a tilde
run opens a fence at all. Neither fixture can see the other decision, so
both are needed, exactly as the entry says.

A second example is the available mechanism here: `pinned_mutations.yml`
cannot hold a decision inside a spec, because the applier refuses a path
outside `core/lib` and `scripts`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.208 `Encoding.default_internal = nil` is the half of the locale fix that nothing pins

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** scripts/utf8.rb, core/spec/meta/script_encoding_spec.rb

`scripts/utf8.rb:32` can be deleted with `script_encoding_spec.rb` reporting 5 examples, 0 failures — nothing in the tree sets an internal encoding, so the probe cannot distinguish its presence from its absence, and `default_internal` appears nowhere else in `core/spec`, `core/lib` or `scripts`. Line 31 is pinned (deleting it fails the spec); line 32 is not. The line DOES earn its place, contrary to the doubt raised with the finding: with an internal encoding set, `File.read` transcodes and a UTF-8 needle no longer compares against it. So this is an unpinned correct line, which `CLAUDE.md` calls a defect in its own right — one refactor away from being an incorrect line with no test — and it has a cheap distinguishing fixture.

**Reproduce:** From a clone at aa1185f: `/usr/bin/sed -i '' '/^Encoding.default_internal = nil$/d' scripts/utf8.rb`, then `cd core && bundle exec rspec spec/meta/script_encoding_spec.rb` -> 5 examples, 0 failures. Control: deleting line 31 instead -> 1 failure. The pinning fixture: run the spec's existing probe with `RUBYOPT="-E UTF-8:EUC-JP"` added to its environment — with line 32 it prints `true,true,UTF-8,UTF-8`; without it, it raises `Encoding::CompatibilityError: incompatible character encodings: EUC-JP and UTF-8` at the `include?`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The line is correct and now pinned, by a fixture
that can tell its presence from its absence: an inherited `RUBYOPT`
of `-E UTF-8:EUC-JP`, which is how an internal encoding actually
arrives. With the line the probe prints `true,true,UTF-8,UTF-8`;
without it the same command raises `Encoding::CompatibilityError` at
the `include?`. Watched failing, and `pinned_mutations.yml` carries
the mutation so the pin is re-verified rather than asserted.

## 024.209 The §5 status-bar comparison is set equality against a regex sample of clientPresentation.ts, not against the file's status strings — and two records state the stronger guarantee

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/design_doc_drift_spec.rb` (the `07 §5` example), `docs/DOCUMENTATION_MAP.md` (line 41, the command-id/setting/status-string row), `docs/design/docs/07-vscode-extension.md` §5, `docs/design/tasks/046-0.2.14-making-the-record-true.md` (C5 row, line 364)

The code side of §5 is `source.scan(/["'](\$\([a-z~-]+\)\s*)?(OvalLSP: [^"']+)["']/)`. 0.2.14 widened it to accept double quotes and to make the icon prefix optional, which closed the reported repro. Three conditions still gate candidacy, and each is a shape ordinary TypeScript takes: the literal must be delimited by `'` or `"`, so a template literal is invisible; an icon prefix, if written, must be `[a-z~-]` only, and a digit in a codicon name makes the whole literal unmatchable rather than partially matched, because the optional group fails and the label no longer abuts the opening quote; and the label must begin with the literal `OvalLSP: `. There is still no linter in the extension package — no eslint config anywhere in the tree, no lint script in vscode/package.json, no lint job in ci.yml — so none of these shapes is constrained. The consequence is one-directional and is the direction the records claim is closed: the file may define a status string the document does not list, with all six examples green. `docs/DOCUMENTATION_MAP.md:41` states "§3, §5, §6, §7 against `package.json` and `clientPresentation.ts` — set equality both ways" and closes "All five sections the row names are machine-checked"; `046`'s C5 row records the check as failing on "the exact drift measured". That is a record claiming a guarantee stronger than the mechanism delivers, sitting in the row written to prevent exactly that. The check is already blind to one string the shipped extension can produce: `statusPresentation`'s fallback `` `OvalLSP: ${outcome.state}` `` at clientPresentation.ts:109, which `clientPresentation.test.ts` deliberately pins ('renders an unrecognised state by name, not as an error') and which §5 does not mention while calling the file the 唯一の定義 of five strings. Two smaller things live in the same example: `.reject { |s| s.include?("\#{") }` tests for Ruby interpolation, which cannot occur in a TypeScript literal this regex can match — deleting the line leaves all six examples green, an unpinned behavioural line by this project's own definition; and the comparison reads only clientPresentation.ts, so a status string assigned anywhere else in `vscode/src` is outside it (today `extension.ts:620` is the only `statusBarItem.text =` and it takes `statusPresentation`'s value, but nothing asserts that). Note for whoever fixes this: the §7 half of the record's overstatement is already true — the documented-side charset is now `[A-Za-z0-9._-]` and a documented setting that does not exist goes red — so only the §5 half needs either a stronger extraction or a weaker sentence.

**Reproduce:** From the repo root, append to `vscode/src/clientPresentation.ts` either of: (a) ``export const STATUS_UNTRUSTED_TEXT = `$(lock) OvalLSP: Untrusted workspace`;`` (backticks) (b) `export const STATUS_X = '$(check-all2) OvalLSP: Done';` (digit in the icon name) Then `cd core && bundle exec rspec spec/meta/design_doc_drift_spec.rb` → 6 examples, 0 failures, while §5's fence lists five strings and the file now defines six. For contrast, the double-quoted form the finding was raised against — `export const STATUS_UNTRUSTED_TEXT = "$(lock) OvalLSP: Untrusted workspace";` — goes RED, which is the half that was fixed. For the inert reject: delete the `.reject { |s| s.include?("\#{") }` line from design_doc_drift_spec.rb → 6 examples, 0 failures. Restore with `git checkout -- vscode/src/clientPresentation.ts core/spec/meta/design_doc_drift_spec.rb`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** Both reproductions confirmed first, then the
pattern widened to accept all three of TypeScript's string delimiters
and any codicon charset, and the inert `.reject` deleted. §5 now
lists `statusPresentation`'s template fallback, marked as a template
-- the string the shipped extension can produce that the section
calling itself the only definition did not mention.

The record's overstatement is repaired by saying which check covers
which section rather than by claiming all five are the same check.

**What the entry asked for and this deliberately did not do:** scan
every `.ts` under `vscode/src`. Dozens of notification messages, log
lines and command titles begin the same way and are not status-bar
strings, so a wider scan would compare §5 against a list it has no
business listing. What makes §5's claim true is asserted directly
instead: every assignment to a status bar item's `text` takes
`statusPresentation`'s value. Watched failing by moving one.

## 024.210 The plugin-sdk check asks whether a name is defined anywhere under core/lib/ovallsp/plugins, not whether it is callable on the receiver the document shows

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal, and now moot: the document the check guards, and the
  subsystem it documented, are both deleted (`024.234`). The check
  went with them.
target: 0.2.16
released-in: 0.2.16
```

**Area:** removed — the `design_doc_drift_spec.rb` example that guarded it, and `docs/design/plugin-sdk.md`, are both deleted (`024.234`). <!-- deleted -->

`named` is every `register_[a-z_]+` word anywhere in plugin-sdk.md; `defined` is every `^\s*def (register_[a-z_]+)` across `core/lib/ovallsp/plugins` and `plugins.rb`, flattened into a single set with no record of which object defines which name. Four receivers contribute: `Ovallsp::Plugins` singleton (`register_static`, `register_runtime`), `StaticContext` (`register_declarations`, `register_generic_rules`, `register_diagnostics`), `RuntimeContext` (`register_snapshot_section`, `register_reload_hook`). The document's entire purpose is to tell a plugin author what to call on the `context` its examples yield, and `named - defined` cannot tell such a call apart from a call on a different class in the same directory — nor from a module function, nor from a private method, since `^\s*def` matches under `private` just as well. So the document can instruct an author to write a line that raises `NoMethodError` at load time and the example stays green; that is the same class of falsehood the example was created for, since `06`'s five registration methods had been fictional. This is not just a stronger-assertion wish: the check answers a question about a directory while the example's own comment states the guarantee as "[e]very method it shows a plugin author calling must exist", which is a claim about a receiver. Fix shape: load the classes and compare against `StaticContext.public_instance_methods` / `RuntimeContext.public_instance_methods` / `Ovallsp::Plugins.singleton_methods`, attributing each name in the document to the receiver its fenced block yields.

**Reproduce:** In `docs/design/plugin-sdk.md`, inside the `Ovallsp::Plugins.register_static("ovallsp-my-plugin") do |context|` block, add `context.register_static("nested")` and `context.register_reload_hook { }` above the existing `context.register_declarations([`. Then `cd core && bundle exec rspec spec/meta/design_doc_drift_spec.rb` → 6 examples, 0 failures. Confirm both lines are false: `cd core && bundle exec ruby -e 'require "ovallsp/plugins/static_context"; c = Ovallsp::Plugins::StaticContext.new("x"); p c.respond_to?(:register_static); p c.respond_to?(:register_reload_hook); p c.respond_to?(:register_declarations)'` → `false`, `false`, `true`. `git checkout -- docs/design/plugin-sdk.md`. <!-- deleted -->

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.211 `check_pinned_mutations.rb --verify-only` prints the applier's conclusion after applying nothing

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/check_pinned_mutations.rb`, `core/spec/meta/pinned_mutations_spec.rb`

In `--verify-only` every entry takes the `next` at line 105 after only a `rspec --dry-run` selection check: no file is written, no example is run to failure. Control still falls through to line 139, which prints `check-pinned-mutations: N mutation(s), every one caught by the example that names it.` and exits 0. `pinned_mutations_spec.rb` shells out in exactly this mode, so every ordinary suite run emits a sentence asserting a property that run did not establish -- the project's own "the answer that would be right if nothing had gone wrong" shape, in the checker built to detect it, and the shape the script's own header warns about ("a checker that cannot see the thing it checks reports the same 'not caught' as a checker that works"). The failure branch is wrong symmetrically: it warns `N of M mutation(s) not caught` for what in this mode can only be manifest-shape problems (an example selecting zero or two). The guarantee itself is genuinely held -- ci.yml's "Pinned mutations" job runs the real applier -- so what is defective is the claim the message makes, not the coverage. The fix is a mode-specific summary: `--verify-only` establishes that the manifest is well-formed and its examples still exist and select uniquely, and should say only that.

**Reproduce:** At HEAD: `time ruby scripts/check_pinned_mutations.rb --verify-only` -> prints "check-pinned-mutations: 21 mutation(s), every one caught by the example that names it." in about 9 seconds wall, with no per-entry `pinned <label>` line, while the real applier runs 21 full rspec invocations against mutated source. Read `scripts/check_pinned_mutations.rb:96-105` (the `verify_only` early `next`) against `:137-141` (the unconditional summary), and `core/spec/meta/pinned_mutations_spec.rb:16` (the suite's invocation, `--verify-only`).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The summary is per mode now. `--verify-only` states
what that mode established -- every `from` matches its file exactly once,
every named example exists and is selected uniquely -- and says in the same
sentence that nothing was applied, so nothing it prints claims an example
fails under its mutation. The failure branch matches: in that mode a failure
can only be a manifest that no longer selects what it names, and it says
that instead of "not caught". `pinned_mutations_spec.rb` gained a second
example asserting the wording, watched failing against the old
unconditional sentence before the fix went in.

**What is pinned, and what is not.** The success sentence -- the one the
ordinary suite printed on every run -- is pinned by that example. The
failure sentence is not: reaching it means handing the script a manifest
that no longer selects what it names, which the script can only be given
by editing the tracked one, so it was exercised by hand and nothing in
the suite would notice it reverting. Reported here rather than pinned,
because the override that would make it reachable is a second place that
must agree about where the manifest lives, and the roots refusal a few
lines above has been unpinned for the same reason since it was written.

## 024.212 pinned_mutations.yml's header documents the mechanism the applier abandoned, and a scope it no longer has

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/pinned_mutations.yml` (header, lines 16-30), `scripts/check_pinned_mutations.rb`

The manifest header says the script "applies each mutation to a throwaway copy of `core/lib` and runs the named example against it. The live tree is never modified: the copy goes first on the load path." That is the arrangement the script's own header records as tried and abandoned because it silently does not work -- the Gemfile's `gemspec` puts the real `core/lib` at the front of `$LOAD_PATH`, so the first version reported all four mutations uncaught -- and the code writes into the real file and restores it (`File.write(source, original.sub(...))`, `source = File.join(ROOT, entry["file"])`). The header states the *reverse* of the actual safety property, in the dangerous direction: a reader is told the applier cannot touch the tree, when it edits `core/lib` and `scripts/` in place and CLAUDE.md forbids running it while anything else mutates the tree. The same header also says `file` is "a path under `core/lib`", while seven of twenty-one entries name `scripts/`. Both halves went stale in one commit (e100388), which added the `scripts/` entries and left the header untouched -- the documentation-is-part-of-the-change failure, inside the apparatus 0.2.14 built to catch that failure elsewhere.

**Reproduce:** `sed -n '16,31p' core/spec/meta/pinned_mutations.yml` beside `sed -n '15,30p;105,125p' scripts/check_pinned_mutations.rb`. Then `grep -c '^ file: scripts/' core/spec/meta/pinned_mutations.yml` -> 7, against `grep -c '^- why:'` -> 21. `git show e100388 --stat` shows the yml gaining those entries with its header unchanged.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16 by removing the restatement, not by correcting it.** Both
halves were the manifest header repeating something the applier owns, so the
header stops repeating either. The run paragraph now states only the
property a reader has to act on -- it writes into the real tracked file, so
the applying mode must not run beside anything else that mutates the tree --
and points at that script's header for how it restores and why the
load-path copy was abandoned. The `file` line points at the script for the
accepted roots, and says it used to name them and was wrong, so the next
reader does not helpfully put them back.

In the script those roots were two further copies: a literal argument list
and a refusal message spelling them again in prose. They are one frozen
constant the refusal reads, so an entry outside them is refused with the
list itself -- watched, against an entry naming a spec file.

## 024.213 A mutation entry's stated reason describes a mutation different from the one it encodes

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/pinned_mutations.yml` (the `check_doc_links`' SKIP entry, lines 142-147), `scripts/check_pinned_mutations.rb`

The entry's `why` reads "check_doc_links' SKIP -- widening it to exclude core/ drops inspection from 537 files to 117 ... which is round 2's break verbatim." None of its three claims derives. The encoded replacement `"|core/spec/fixtures/rails_real/" -> "|core/|"` splices an *empty alternative* into SKIP (`\A(core/vendor/|vscode/node_modules/|core/||(.*/)?...)`), so SKIP matches every path and the checker inspects 0 files, not 117. The `why`'s own literal description -- exclude `core/` -- gives 210. Round 2's actual regex, recorded verbatim in 046's `doc-links` section, gives 118. And the unmutated checker inspects 536, not 537. The pin works (the coverage floor fails on 0 inspected), so nothing catches the entry: `check_pinned_mutations.rb` validates that `from` matches exactly once and that `example` selects exactly one, and validates nothing that relates `why` to `from`/`to`. This is a claim about this tree that was typed rather than derived, sitting in the file whose own header says a comment claiming an example distinguishes something is a claim about this tree and must be derived. The countermeasure shape available: have the applier print what the mutation actually did (inspected-count, or the failing assertion) so a `why` carrying numbers can be checked against them -- or drop derived numbers from `why` and cite 046 for them.

**Reproduce:** At HEAD, without modifying the tree: `ruby -e 'require_relative "scripts/repo_files"; files = RepoFiles.list(Dir.pwd); src = File.read("scripts/check_doc_links.rb")[/^SKIP = %r\{(.*)\}$/, 1]; {"encoded" => src.sub("|core/spec/fixtures/rails_real/", "|core/|"), "why-as-written" => src.sub("core/spec/fixtures/rails_real/", "core/")}.each { |n, s| puts "#{n}: #{files.reject { |f| f.match?(Regexp.new(s)) }.length}" }'` -> `encoded: 0`, `why-as-written: 210`. `ruby scripts/check_doc_links.rb | head -1` -> "536 file(s) inspected". Round 2's four-root regex from docs/design/tasks/046-0.2.14-making-the-record-true.md:724, run the same way -> 118.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The `why` describes the mutation it encodes -- an empty
alternative spliced into SKIP, which matches at the start of every path, so
the checker inspects nothing and the example's per-root coverage floor is
what notices -- and cites `046`'s doc-links section for round 2's numbers
rather than restating them. Derived rather than reasoned: the mutation
applied to a copy of the checker in a tmpdir and run against this tree
read-only reports zero files inspected and zero coverage on all five roots,
while exiting 0 itself.

**The adjacent entry had the same defect, and is fixed in the same change.**
Its `why` claimed a count of links between task files, which matches neither
the checker's own relative-link total nor the number of relative links
written inside the tasks directory -- both derived here, neither equal to
it. Neither `why` carries a typed number now. The countermeasure this entry
sketches, teaching the applier to print what a mutation did so a numeric
`why` could be checked, is still not built and is still a separate decision.

## 024.214 generate_sbom.rb's header tells the reader a stale SBOM is caught by nobody, in the release that made a spec catch it

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/generate_sbom.rb` (header, lines 17-20), `core/spec/meta/sbom_spec.rb`

The header ends "Run manually via `ruby scripts/generate_sbom.rb` whenever ... changes; not run automatically by CI/tests (RELEASE_CHECKLIST.md item 8)." The same change set added `core/spec/meta/sbom_spec.rb`, which runs `ruby scripts/generate_sbom.rb --check` on every suite run and a second time into a tmpdir with a planted divergence to prove `--check` is not inert -- and the `--check` block installed a few lines below in the same file carries the comment "046's C7", the same marker as the spec. So the file's own header contradicts the mechanism its own commit installed, in the direction that matters: it tells a contributor that a stale SBOM goes unnoticed until somebody remembers to run this by hand, which is precisely the state `sbom_spec.rb` was written to end (its own comment: "What enforced it before this existed: nothing").

**Reproduce:** `sed -n '14,21p' scripts/generate_sbom.rb` against `core/spec/meta/sbom_spec.rb`. `cd core && bundle exec rspec spec/meta/sbom_spec.rb` -> 2 examples, 0 failures (neither skipped nor pending), the first shelling out to `ruby scripts/generate_sbom.rb --check`. `git diff main..HEAD -- scripts/generate_sbom.rb` shows the `--check` path added and the header untouched in one diff.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The header says what is true: `--check` runs from
`core/spec/meta/sbom_spec.rb` on every suite run and therefore in CI, and
the manual invocation is how a divergence is *fixed* rather than how it is
found. The checklist-item pointer is gone rather than renumbered -- that
document carries two numbered tables and the second one's item 8 is about
something else entirely, so the pointer had become a coin toss. Watched: a
version planted into the tracked `docs/SBOM.md` turns that spec red, naming
the line and both values; restored, it is green at two examples, neither
pending.

## 024.215 A scripted comment rewrite in corpus_diagnostics.rb cut a sentence mid-clause, and nothing in the tree can see it

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/corpus_diagnostics.rb` (lines 169-175)

The comment above the engine assembly reads "... That is not a smaller measurement, it is a measurement of something else, and it is why a" and the next line starts a new bolded sentence, "**Assembled, not wired here** (`042`'s D8)." The clause after "why a" was cut -- 024.140's class exactly, a scripted edit whose end boundary silently missed. It is byte-identical on `main`, so it predates the change set, and that is the point rather than a mitigation: 0.2.14 is a whole-repository audit whose subject is the record matching the tree, and the two checks that read prose (`duplicate_headings_spec`, `check_doc_links`) see structure and citations respectively -- neither can see a sentence that simply stops. Whether this is worth a mechanism or only a repair is the open question; a heuristic scan of every tracked .rb/.yml/.md for the same shape produced only this one genuine hit against a large volume of ordinary wrapped prose, which suggests a repair plus a note, not a checker.

**Reproduce:** `sed -n '169,176p' scripts/corpus_diagnostics.rb`. Confirm it is pre-existing rather than introduced by 0.2.14: `git show main:scripts/corpus_diagnostics.rb | sed -n '70,80p'` yields the identical text.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Repaired in 0.2.16, and no checker built.** The entry's own
measurement is the argument: a heuristic scan of every tracked
`.rb`/`.yml`/`.md` for this shape produced exactly one genuine hit
against a large volume of ordinary wrapped prose, so a check would be
almost entirely false positives. Recording that as the decision is
the other half of the fix, so the next reader does not re-derive it.

The restored clause is marked at the site as a **reconstruction**:
the original wording is not recoverable from any commit, and a
sentence somebody wrote later reading as the author's is the failure
this register spends several entries on.

## 024.216 The register's entry number is parsed by six readers with three grammars, so a sub-numbered entry is indexed as a duplicate of its parent

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/reindex_findings.rb` (`number_of`, `title_of`, `rebuild`'s split), `core/spec/meta/deferred_findings_spec.rb` (the "indexes every entry" scans, the Area-line split), `core/spec/meta/measured_claims_spec.rb` (`register_numbers`, `CITATION`), against `scripts/deferred_findings.rb` (`ENTRY_HEADING`, `METADATA_BLOCK`)

046's C4 unified the reading of an entry's *yaml block* into `DeferredFindings.entries`, and its comment and `measured_claims_spec`'s both now say `DeferredFindings` is "the single parser of this file". It is not the single parser of the *primary key*. The entry number is still read by six hand-rolled regexes in three incompatible grammars: `DeferredFindings::ENTRY_HEADING` = `/^## (024\.[0-9R][0-9.]*) /` (accepts sub-numbers), `ReindexFindings.number_of` = `/\A## (024\.[0-9R]+)/` (truncates, and needs no trailing space), `ReindexFindings.title_of` = `/\A## 024\.[0-9R]+ (.*)/` (fails outright), `ReindexFindings.rebuild`'s split `/^(?=## 024\.)/`, `deferred_findings_spec`'s two scans `/^## (024\.[0-9R]+)/` and its Area split `/^## (?=024\.[0-9R]+ )/`, `measured_claims_spec#register_numbers` = `/^## (024\.[0-9R]+) /` (matches nothing), and `measured_claims_spec::CITATION` = `/\b024\.([0-9]+|R[0-9]+)\b/` (truncates). A sub-numbered entry is a supported shape — `scripts/deferred_findings.rb:38` was widened for it deliberately and `core/spec/meta/deferred_findings_spec.rb:250` asserts "reads a sub-numbered entry as itself, in both readers" — so this is not an input nobody promised to handle. Two consequences, one latent and one live now: 1. **Latent.** Adding `## 024.13.<n> A sub-numbered follow-up` makes `reindex_findings.rb` emit a second index row numbered `024.13`, with an empty title and the dead anchor `#02413-`, adjacent to the real `024.13`. `entry_key` gives both `[0, 13]`, and Ruby's `sort_by` is not stable, so which of the two comes first is unspecified. The check that exists to catch exactly this — "indexes every entry, so the table cannot silently omit one" — passes, because both of its scans truncate the same way and therefore agree while both are wrong. This is C4's own declared failure mode, recorded at `046` line 363 as the thing C4 was supposed to prevent. 2. **Live at HEAD, no register change needed.** `CITATION` cannot express a sub-number, so a citation of `024.13.<n>` — a sub-entry that has never existed — resolves to `024.13` and passes the dangling-pointer guard. The asymmetry is visible in one run: `024.<n>.1` is correctly reported dangling (because `024.<n>` does not exist) while `024.13.<n>` is accepted. The root cause is not any one regex. It is that the primary key has no single reader, and each reader is the only reader of its own result — the same shape `024.68` records for the metadata grammar, one layer down. Fix direction: route every number read through `DeferredFindings` (a `number_of`/`title_of` there, and a `CITATION` derived from `ENTRY_HEADING` rather than written independently), or delete sub-number support outright — widen nothing, narrow `ENTRY_HEADING` to `[0-9R]+`, and delete the spec at line 250 that promises it. Either is coherent; what is not coherent is one reader promising the shape and five others corrupting it.

**Reproduce:** At HEAD, from the repository root. The divergence, in one line: ruby -r./scripts/deferred_findings -r./scripts/reindex_findings -e 'h="## 024.13.<n> X\n\n```yaml\nstatus: open\nkind: defect\n```\n"; p DeferredFindings.headings(h), ReindexFindings.number_of(h), ReindexFindings.title_of(h), h.scan(/^## (024\.[0-9R]+) /).flatten' prints `["024.13.<n>"]`, `"024.13"`, `""`, `[]`. The full round trip (do this on a scratch copy, or in memory — it rewrites the register). Insert a valid sub-numbered entry immediately before `## 024.14 `, with a yaml block and **no** `**Area:**` line: ## 024.13.<n> A sub-numbered follow-up ```yaml status: open kind: friction target: unscheduled ``` prose. Bump the `register-entries` marker in the register from 152 to 153, run `ruby scripts/reindex_findings.rb`, then `cd core && bundle exec rspec spec/meta/deferred_findings_spec.rb spec/meta/measured_claims_spec.rb`. Both files are green, and the index carries | [`024.13`](#02413-) | open | unscheduled | | Note the variant matters: give the sub-entry an `**Area:**` line and `deferred_findings_spec`'s "states each entry's Area exactly once" fails with the misleading message `024.13 (2 Area lines)` — because its split truncates too, and merges the sub-entry's body into its parent's chunk. The suite is fully green only for the no-Area variant. The citation half needs nothing inserted: ruby -rset -e 'reg=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); known=(reg.scan(/^## (024\.[0-9R]+) /).flatten+reg.scan(/^\| `(024\.[0-9R]+)` \|/).flatten).to_set; ["024.13.<n>","024.<n>.1"].each{|c| n=c[/\b024\.([0-9]+|R[0-9]+)\b/,1]; puts "#{c} -> 024.#{n} known? #{known.include?("024.#{n}")}"}' prints `024.13.<n> -> 024.13 known? true` and `024.<n>.1 -> 024.<n> known? false`.

### Fixed in 0.2.16

Reproduced first: the one-line divergence printed the four different
answers the entry lists, from four readers of one heading.

Direction (a), the one that keeps the promised shape. `NUMBER` in
`scripts/deferred_findings.rb` is the single grammar, and
`ENTRY_HEADING`, `METADATA_BLOCK`, `RETIRED_ROW` and a new `CITATION`
are all built from it. `number_of` and `title_of` live there and
`reindex_findings.rb` calls them; `ENTRY_SPLIT` is shared by the three
places that split the file into entries; `measured_claims_spec` reads
its three patterns from the module rather than writing them again.

`headings` is the one reader that stays deliberately *looser*, and that
is not an oversight: `024.155` is the defect that exists when the two
sides of `parses every entry` agree, so this is the one place two
readers are meant to disagree, and the module says so where the
constant is written.

`entry_key` compares the tail element-wise, so a sub-entry sorts under
its parent instead of tying with it and leaving `sort_by` to decide.

The live half is `024.182`, closed with the same change; its section
records the illustrations that widening the citation grammar turned into
dangling pointers.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.217 `rescue_verdicts.yml`'s header tells a reader the 98 arguments are unargued defaults, and names a verdict the checker rejects as the safe one

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/spec/meta/rescue_verdicts.yml` (header, lines 3-16), `scripts/check_swallowed_failures.rb` (the no-verdict problem message)

The header of `rescue_verdicts.yml` describes a state of the file that ended in 0.2.13. It says the verdicts "are a *first pass*: every site whose handler raises or reports was marked `surfaces` mechanically, and the rest are marked `swallows` — which is the safe default and the honest one, since nothing has yet been argued. Moving one to `contained` is the review work `024.122` describes." Every clause of that is now false. No entry carries `swallows` — the only three occurrences of the word in the 158-entry file are in this header. All 98 non-`surfaces` sites carry `contained: <why>` with an argument written at the site, which is the review work the header calls outstanding; `024.122` is `status: fixed`, `released-in: 0.2.13`; and `CLAUDE.md`'s "Catching a failure and continuing is not the default" section records the enumeration as done, saying "Two verdicts are allowed". Worse than stale: it is an instruction that fails. `scripts/check_swallowed_failures.rb` rejects any `swallows` verdict (its own comment: "**The column is empty, and stays empty.** ... `swallows` remains spellable so that this message can name it, not so that a site can sit in it"). So an author who adds a new rescue site and follows the header's "safe default" fails the suite and the CI job. The checker's own no-verdict message points the same way — "Add one to core/spec/meta/rescue_verdicts.yml -- surfaces, contained, or swallows" — offering a verdict its very next branch refuses. The cost is not cosmetic. The 98 arguments are the only thing standing between this project and the class of defect the section exists for, and the file's header tells the next reader they are mechanical placeholders nobody has thought about — which is exactly the reason not to trust one, and exactly the reason not to bother reviewing one. `CLAUDE.md` already flags these arguments as "one author's, reviewed by nobody else yet"; the header makes that harder to act on rather than easier. Nothing checks that this header stays true.

**Reproduce:** At HEAD, from the repository root: sed -n '1,17p' core/spec/meta/rescue_verdicts.yml # the claim grep -n swallows core/spec/meta/rescue_verdicts.yml # lines 4, 9, 14 only — all header prose ruby scripts/check_swallowed_failures.rb # "158 rescue site(s) -- 60 surface, 98 contained, and none swallowing." ruby -ryaml -e 'v=YAML.safe_load_file("core/spec/meta/rescue_verdicts.yml"); puts v.count{|_,x| x.to_s.start_with?("swallows")}' # 0 Then, for the failing instruction: add a `rescue StandardError` to any file under `core/lib`, give it the verdict the header calls the safe default (`swallows`), and run `ruby scripts/check_swallowed_failures.rb` — it exits non-zero telling you `swallows` is not allowed. Revert. Cross-check the record: `024.122` in `docs/design/tasks/024-deferred-review-findings.md` reads `status: fixed` / `released-in: 0.2.13`, and `scripts/check_swallowed_failures.rb` lines 73-76 state the contrary of the header in the same repository.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

**Fixed in 0.2.16.** The header states what is true: two verdicts, no
third option, and the outstanding work is *review of* the arguments
rather than writing them. The checker's no-verdict guidance is built
from one list of allowed verdicts rather than typed, so the message
and the branch that judges it cannot disagree.

The countermeasure is that the two are now related rather than merely
both correct: `swallowed_failures_spec.rb` reads the allowed list
from the checker (`--verdicts`) and fails if the file's header offers
anything else, and proves the guidance by *running* the checker
against a throwaway tree holding one unverdicted rescue -- rather
than by searching the script for its own message, which is the family
`024.151` names. Both watched failing.

A third statement of the same false claim lived in
`swallowed_failures_spec.rb`'s own header and is corrected too; the
register's older entries describing the first-pass state stay as they
are, being historical.

## 024.218 Six isolated agents branched from the wrong commit, and the evidence was deleted before it was checked

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is roughly two and a half hours of
  parallel work on five engine defects, of which one survived.
target: 0.2.15
released-in: 0.2.15
```

**Area:** the 0.2.15 implementation workflow (a `Workflow` script, not
tracked here), `docs/design/tasks/047-0.2.15-scope.md`

Six agents were given one engine defect each and run in **isolated git
worktrees** so they could edit freely without colliding. All six
reported success. One fix reached the tree.

**Two failures, and the second is what did the damage.**

*They branched from the wrong commit.* Five of the six worktrees were
created at `57e98da` — "0.2.13 published" — **22 commits behind HEAD**.
So they implemented against a tree with none of 0.2.14 in it: no
`RepoFiles`, no corrected documents, a register missing 64 entries, and
an example count three hundred out of date. Their diffs edit
`docs/RELEASE_CHECKLIST.md` to say `2,331 examples`. Nothing in the
launch checked what base the isolation would use, and nothing in the
result announced it.

*The worktrees were removed before the diffs were confirmed to apply.*
Only one agent had committed inside its worktree; the other five held
their work as uncommitted changes. Removing the worktrees destroyed the
only complete copy. What is left is the diff each returned through a
JSON field — against a 22-commit-old base, and three of the six arrive
truncated (`git apply` reports *corrupt patch*).

**What survived:** `024.40`, cherry-picked from the one branch that had
a commit on it, its `pinned_mutations.yml` entry merged with 0.2.14's
seven, and its mutation confirmed caught (22 of 22).

**What this says.** Isolation is not free, and its cost is not the disk:
it is that **the work exists somewhere the main tree cannot see**, so
every assumption about where it came from and whether it still applies
has to be checked rather than assumed. Both halves of this failure are
that one sentence.

**The rule, and it is cheap:**

- **Verify the base before the work, not after.** An isolated agent
  reports the commit it started from as its first act, and the
  orchestrator refuses a base that is not the intended one.
- **Never remove an isolated worktree until its output is in the main
  tree.** A diff that has been through a serialisation boundary is a
  copy, not the thing. `git apply --check` on every one *before*
  cleanup, and the worktree stays until it passes.

*It is the same shape as `024.149` — a result read from a summary rather
than from the thing itself — with the added cost that here the thing
itself was then thrown away.*

### Three of the six agents reported the drift, and I did not read it

Checked afterwards: `024.128`, `024.134` and `024.40` all named the wrong
base in the fields they returned. One opened with it in capitals —
**"BASE DRIFT — READ FIRST. This worktree is based on `main` @ 57e98da
(0.2.13 published)"** — and went on to list three consequences for
whoever applied the diff.

**The information was in my hands before I deleted anything.** I read
the `outcome` field, saw six `fixed`, and went to integrate. The
`notes` field is where an agent puts what does not fit the schema's
other slots, which is exactly where a surprise lands.

So the rule above is not enough on its own, and the missing half is
small: **read every field a run returns before acting on any of them.**
A schema with an `outcome` slot invites reading that slot; the fields
that carry the reason it might be wrong are the ones easiest to skip.
`024.149` is the same failure against a workflow's summary, and this is
it against an agent's own report — twice now, one level apart.


## 024.219 A three-part claim shipped with one part pinned, and the other two were false

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets directly -- the defect the false claim hid is
  `024.111`, and that one they did. What this cost is that the
  register, which is where a worker goes to find out what is already
  true, asserted a behaviour for two releases that a six-line script
  disproves.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md`
(`024.117`, `024.111`), `core/lib/ovallsp/parser_service.rb`

`024.117` closed in 0.2.13 by asking the interpreter, and wrote down what
it heard:

> A visibility section, a `module_function` and an `attr_accessor`
> written in an ordinary iterator block **all reach the enclosing body**,
> and the frame was containing all three.

The interpreter session was right. The sentence about this engine was
one third right. `Cref#in_block(shares_self: true)` returns `self`, so
no frame is opened — but `#visit_block_node` restored `@cref` in an
`ensure` **unconditionally**, and `Cref` is an immutable value. An
`attr_accessor` inside the block records its declaration *while* the
shared cref is installed, so its owner came out right and the claim
looked true. A `private` produces no declaration; it produces a *new
cref*, which lived in `@cref` until the `ensure` overwrote it. Both
visibility halves were inert on the day they were declared fixed.

The claim had **four copies**: `024.117`, `Cref#in_block`'s comment, and
0.2.13's changelog bullet in both languages — the last of which shipped
to the Marketplace, so it is annotated in place rather than edited, and
anyone who read the original can see the correction beside it.

`024.111` then copied the claim forward — "**Narrowed in 0.2.13.** The
literal-receiver half is fixed with `024.117`: `[1].each { private }` and
`1.times { module_function }` reach the enclosing body now" — and two
releases of the register asserted a behaviour that a six-line script
disproves.

**What made it survive:** the three behaviours were established in one
interpreter session and fixed by one line, so they were treated as one
thing. They are not: two are state that must outlive the block, one is an
event inside it. The specs `024.117` added pinned the event. Nothing
failed, and the register recorded the count of examples rather than the
count of claims.

**Fixed in 0.2.15** with `024.111`, whose entry now records the correction
rather than the inherited claim. `visibility_through_block_spec.rb` pins
each of the three separately, in both directions, with the `included do`
and `class_eval` controls that say why the frame exists at all.

**The countermeasure is the `CARRIED_OUT` and `CONTAINED` tables** in
`spec/ovallsp/visibility_through_block_spec.rb`. The list of constructs a
self-sharing block carries out now exists once; the examples are
generated from it, so a construct cannot be named without being pinned,
and `Cref#in_block`'s comment points at the table instead of restating it
— which is the pair of copies that diverged here. Same shape as
`Types::LiteralTypes`, and the same reason.

A regression test for `private` alone would not have been one: it pins
the case that was reported and leaves the next construct to a reviewer,
which is how `protected` and `public` — never mentioned by either entry,
both broken, both fixed by the same line — went two releases unnoticed.

**What no mechanical check here would have caught** is the underlying
mistake: three behaviours were established in one interpreter session and
fixed by one line, so they were counted as one thing, and the register
recorded the number of examples rather than the number of claims. Two of
the three are *state that must outlive the block*; one is an *event
inside it*. `CLAUDE.md`'s "Promoting a finding is making a claim" is the
rule that covers that, and it is prose because the count of claims lives
in a sentence. Saying a table catches it would be the same error again.

## 024.220 The interpreter sessions pasted through this tree are never re-run

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it costs is that the evidence a fix
  rests on is unverifiable text, and the rule that produced it says
  it exists so the next reader need not trust that somebody checked.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md`,
`core/lib`, `core/spec` (55 sessions across 26 files), a new
`scripts/check_interpreter_sessions.rb`

`CLAUDE.md` requires a claim about Ruby's semantics to be taken from
Ruby, run, and pasted in "so the next reader can see what the
expectation rests on rather than trusting that somebody checked". The
rule works — several defects were found by obeying it. It has produced
70 pasted sessions with their output written beside them (the opener is
not quoted here, for the reason the shape description below gives), and
**every one was inert text.** Nothing re-ran them. A mis-transcribed
result, a session edited out of agreement with the code beside it, and a
session that stops being true on a later Ruby all read exactly like a
correct one, and each would be believed — which is the whole point of
pasting them.

Two shapes are in the tree, and both parse. **They are described here
rather than quoted**, because an illustration spelled the way a real
session is spelled becomes a session the checker extracts, runs, and
reports — and the first run of the checker reported exactly that, twice,
about this paragraph. `CLAUDE.md`'s "writing a check means writing bait
for the other checks" is the rule, and describing the shape is what it
says to do instead.

- The **multi-line** shape: an opener ending in the `-e` flag and an
  opening quote, the program on the following lines carrying the same
  comment prefix, a line holding only the closing quote, then one
  arrow-prefixed comment line per line of standard output, then
  optionally a comment naming the interpreter version that answered.
- The **one-line** shape: the whole program on the opener between the
  quotes, with the output lines following in the same arrow-prefixed
  form.

The version line is a note about *which* interpreter answered rather
than part of the answer, so the comparison drops it.

A checker extracts each session, runs it, and compares. It must **fail
on a session it cannot parse rather than skipping it**: a checker that
passes over what it does not understand reports exactly what a working
checker reports when everything is fine, which this register already
records happening twice (`scripts/check_pinned_mutations.rb` on its first
run, and `024.147`).

**Raised while closing `024.111`, and deliberately not built there.**
`024.219` is the entry that prompted it, and this would *not* have caught
`024.219` — there the transcript was right and the engine disagreed with
it, which no amount of re-running the interpreter can see. It is a
separate, real class: the evidence a fix rests on ceasing to say what it
says.

### Built in 0.2.16, as the countermeasure the same-place rule called for

Not scheduled: **triggered**. Two review rounds inside 0.2.16 each found
a false claim about a macro's behaviour written as prose in the same
rewritten bullet list — round one that `enum` stores the token, round two
that `delegate` under `prefix:` does not keep it as a substring. Same
place twice, so `CLAUDE.md` forbids a third hand fix and asks for
something mechanical instead.

**And the mechanical thing cannot read prose**, which is the honest
limit of it. What it can do is make the *session* the checked form, so
that stating a behavioural claim as prose is the unverified path and
stating it as a session is the verified one. `CLAUDE.md`'s rule was
extended to say so in the same change.

**What the first run found is not what this entry expected.** Of 70
sessions, 50 carry a recorded answer, and **every one of them
reproduces**. Not one was a false claim. The five the first run reported
were all artefacts, and each is worth naming because each is a way this
check could have been built wrong:

- **Seven wrapped answers.** A long result line-wrapped to fit its
  comment. Comparing line by line reports all seven, and a check that
  reports seven non-defects on its first run gets disbelieved. The
  comparison collapses whitespace.
- **Three broken by the runner, not the tree.** The first runner passed
  a no-gems flag the sessions never asked for, so `gem` and a `require`
  of an installed library failed. A session runs with its own flags.
- **Two error transcriptions** written as the message a `rescue` would
  give, where the session as pasted crashes and Ruby prints the frame
  and the class. Both were corrected in the tree — the pasted form was
  the human's, not the interpreter's, which is exactly the class this
  entry is about, found by the check on its first run.
- **One refusal that was wrong**, and wrong expensively: a hazard pattern
  containing a bare backtick refused `024.225`'s session, whose *subject*
  is a backslash-backtick inside a replacement string. Fixed by asking
  Ripper whether a backtick opens a command instead of matching text —
  which also stops a hazard *named* inside a string from counting.
- **Two of this entry's own illustrations**, spelled the way a real
  session is spelled and therefore extracted, run, and reported. That is
  `CLAUDE.md`'s "writing a check means writing bait for the other checks"
  arriving on schedule, in the entry that specifies the check. They are
  described rather than quoted now.

So this closes no defect. It stops one arriving, and it converts 50
inert paragraphs into 50 assertions that can fail. The cost measured
before wiring it in: the whole run is 50 subprocesses and finishes in
under ten seconds, which is inside the suite's budget, so it runs in
`spec/meta` and in `preflight` rather than in CI only.

**Built in 0.2.16.** `scripts/check_interpreter_sessions.rb` runs in
the suite and in `preflight`; 64 sessions, 2.8 seconds.

Three things the entry did not anticipate, each of which changed the
design:

- **Six shapes, not two.** Besides the two documented, the tree
  writes a program that starts on the opener's own line and runs on;
  output as an arrow annotation at the end of the line that produces
  it; output as an arrow comment inside the program; and output as a
  bare line after it. Accepting all six was cheaper and more honest
  than rewriting 60-odd correct transcripts into one house style.
- **The checker is bait for itself.** Its first draft quoted the
  opener in its own header, twice, and then tried to run its own
  prose -- in the file whose subject is that problem. Nothing in it
  spells the opener now; the shapes are described and the constant is
  assembled. The same repair was needed in this entry, which is why
  the two illustrations above are prose.
- **Bundler leaks into the child.** Run from inside the suite, two
  correct ActiveSupport sessions died with "is not part of the
  bundle" -- an error about the harness reported as a defect in the
  transcript. The child is detached from Bundler explicitly.

**It found six real defects on its first complete run**, all of them
in evidence that had been read and believed: two transcripts merging
two `p` outputs onto one arrow line, one omitting a warning Ruby
prints, one gluing prose onto an arrow, and two sessions that raise
rather than print (rewritten with a `rescue`, so the raise is
recorded as output instead of as a stack trace nobody compares).

Coverage is stated per root and floored, because a scan that found
nothing prints the same reassuring line as one that found everything
and cleared it -- which is the confusion this check exists about,
arriving one level up. Watched failing three ways: a corrupted real
transcript, an unparseable session, and an enumeration that reads
nothing.

### The checker's own blind spot, found by a reviewer three weeks in

Its opener pattern read long flags only — `(?:--[\w-]+ )*` before the
`-e`. Four sessions in the tree are written `$ ruby -r<lib> -e`, and
**one of them is in this checker's own comment**, demonstrating the
Ripper question the hazard test turns on. All four were skipped in
silence.

That is exactly the failure this entry exists to stop, performed by the
thing that stops it: a checker that passes over what it does not
recognise reports what a working checker reports when everything is
fine. The register already records it twice — `check_pinned_mutations`
on its first run, and `024.147` — and this is the third.

Widened to `(?:-{1,2}[\w-]+ )*`; the count went 104 to 109, and the five
that appeared all reproduce. Pinned by an example that fails when the
pattern is narrowed back, verified by narrowing it.

The general form, for whoever writes the next scanner here: **the count
is the assertion that it ran over the tree, and a count is only as good
as the pattern that produced it.** This one had an example asserting the
session count was above sixty, and sixty was true with four sessions
invisible.

## 024.223 One unresolvable `include` in a project's own RBS turns its whole class into false reports

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`
(`#compute_ancestors`, `#compute_member_names`, `#build_definition`),
`core/lib/ovallsp/semantic/method_resolver.rb` (`#accounted_for?`),
`core/spec/meta/rescue_verdicts.yml`

Two projects, **identical Ruby**, whose `sig/` differs by one line:

```rbs
module App
  class Key
    include _ToJson          # <- the only difference; nothing loaded declares it
    def digest: () -> String
  end
end
```

```ruby
k = Key.new(1)
k.digest              # declared in sig/ right above
k.definitely_absent   # declared nowhere -- the planted control
```

| | reports |
|---|---|
| without the `include` | 1 — `definitely_absent`. Correct. |
| with it | 2 — `definitely_absent`, **and one saying `App::Key` has no method named `digest`** |

The user is told a method does not exist, naming the class whose own
signature file declares it, because of an unrelated line elsewhere in
that file.

**Mechanism.** `RBS::EnvironmentLoader` is built from the project `sig/`
and the Bundler gem sig directories only (`#build_loader`), so an
interface declared in an stdlib signature nobody added is unresolvable.
`instance_ancestors` then raises `RBS::NoMixinFoundError`, and
`#compute_ancestors` swallows it:

    clean:  instance_ancestors -> ["::App::Key", "::Object", "::Kernel", "::BasicObject"]
    broken: instance_ancestors -> RBS::NoMixinFoundError
            compute_ancestors  -> []

**The chain includes the class itself**, so an empty chain does not
merely lose what `Key` inherits — it loses what `Key` *declares*. Every
method in that class becomes unknown at once.

**The recorded verdict for this rescue is wrong, and that is the finding
under the finding.** `rescue_verdicts.yml:167` reads:

> `contained: an empty chain is what a type RBS does not declare
> produces, and every consumer reads it as less knowledge`

The first clause is exactly the problem: **the failure is made
indistinguishable from the ordinary "RBS does not know this type"**, and
a consumer that is entitled to conclude "not declared anywhere" from the
second is then entitled to conclude it from the first. `CLAUDE.md`'s
test is not whether the failure is important but *whether the fallback
lets a caller assert something*, and this one does — the same shape as
`Engine#rbs_known_constant?` answering `false` for "RBS does not know
this name" when the question could not be asked. `024.122` enumerated
158 sites and says a `contained` that turns out wrong is an ordinary
finding; this is one.

**And it is silent twice over.** `Environment` carries a `diagnostics`
array documented as collecting "*what* was skipped so a caller can still
explain the gap". Measured on the pair above, it is `[]` on **both**
sides. The one channel built to report a signature that failed to load
never hears about it, so `explainType` cannot explain it either.

**Direction.** Not `loader.add(library: "json")` — that fixes `_ToJson`
and leaves every other unresolvable include. Not "stop swallowing" —
a type RBS genuinely does not declare must still produce a chain, and
raising would take the server down for a workspace with one bad line.

The fix is to make the two cases **distinguishable at the point where
they differ**, which is inside `#compute_ancestors`: "RBS does not
declare this type" and "RBS declares it and the chain could not be
built" must not both be `[]`. The second has to reach the consumer as
*cannot say*, so the closed-nominal decision declines instead of
asserting, and it has to reach `#diagnostics` so the gap is
explainable. Both consumers named in the current verdict need re-reading
against the new value rather than trusting the sentence that is being
corrected.

**Scope beyond this reproduction is measured but not by me.** A review
pass over rbs 4.0.3 (89 hand-written `.rbs` for 102 `.rb` — the first
hand-written-signature corpus this project has pointed the engine at)
reports **20 false `unknown-method` and 3 false `argument-type`**, all
from this cause, and `member_names("::RBS::Location")` goes from 0 to
155 when the missing library is loaded — so completion is hit as well.
Those numbers are recorded as reported and want re-deriving here before
they are promoted anywhere; the paired fixture above is this entry's own
evidence and was run at `1a06f60`.

**Found by an independent verifier sent to refute a different finding**
about `024.37`, which named `#compatible_nominal?`'s name spellings as
the cause. That was the symptom: the one-line spelling fix takes
`argument-type` 3 to 0 and leaves all 20 `unknown-method` reports
standing. The spelling defect is real and is `024.224`.

### Fixed in 0.2.15

`Signatures::Environment::UNAVAILABLE` is a frozen empty Array, and
`.unavailable?` compares by **identity** — `[] == UNAVAILABLE` is true
and would mark every unknown type. It is produced in one place, by the
three rescues that all swallowed the same error, and only for a type
`#rbs_declares?` confirms RBS carries: an unresolvable name raises from
the same call, and calling *that* a failure would be the same conflation
facing the other way.

Being an ordinary empty Array is what keeps the change small. A caller
that only adds reachable names needs no edit and still reads it as less
knowledge. `MethodResolver#accounted_for?` is the one that had to ask,
and it asks **before** its `entry.kind` shortcut: the workspace knowing
`App::Key` is a class does not say what `App::Key` contributes.

`Environment#diagnostics` now hears about it. That channel is documented
as collecting what was skipped so a caller can explain the gap, and it
was `[]` on both sides of the pair; a workspace with one bad `include`
fails once per type that reaches it, so the messages are deduplicated.

**The affected receiver goes quiet entirely, and that is the fix rather
than a cost of it.** Once the surface cannot be enumerated the engine
cannot tell `digest`, which the sig declares, from `definitely_absent`,
which nothing does — so it declines about both. An earlier draft of the
spec asserted the opposite, reasoning that a fix should not lose a true
report; that reasoning asks the engine to answer from a question it
could not ask. What must not happen is the decline spreading, and a
control pins that a class whose own chain is fine keeps being reported.

Measured over rbs 4.0.3 with its own `sig/` as the signature root — 102
files, `corpus-sha256` `d454c9e3…`, both sides identical, control
`unresolved-constant` identical at 319:

| | before | after |
|---|---|---|
| `unknown-method` | **20** | **0** |
| `argument-type` (`024.224`, untouched) | 3 | 3 |

All 20 were `RBS::Location has no method named …` — `buffer`,
`_start_pos`, `_optional_keys` — each declared in `sig/location.rbs`.
Over four Rails gems with no project `sig/` at all: 0 added, 0 removed,
which is what a change that only fires on a failed signature build should
do there.

**`scripts/hunk_sweep.rb` against the change set: 7 hunks, 5 pinned, 1
comment-only, and 1 unpinned** — `#build_definition`'s failure
recording. The spec asserted only that `#diagnostics` was *non-empty*,
which the ancestors recording already satisfied on its own, so reverting
the other one left the suite green. Each failure is now asserted by
name.

**And the pin for that had to be written twice.** The first attempt at
the deduplication example called `#ancestors` and `#member_names` five
times each — but both memoize, so five calls compute once, the duplicate
never arises, and the example passed against an engine with the guard
deleted. That is an assertion that could not fail, written in the act of
pinning one, and only a mutation run found it. What makes the guard
reachable is that instance members, singleton members and type
parameters are three different cache keys that all reach
`#build_definition` and all produce the same sentence; the example asks
those three, and without the guard it sees 3 where it wants 1.

*A flake found on the way, and fixed here: the new spec defined `SOURCE`,
and a constant written inside `RSpec.describe` lands on `Object`, so it
silently replaced `server_receiverless_spec.rb`'s fixture and five of its
examples failed under one seed. `spec/meta/spec_constants_spec.rb` exists
for exactly this and named it. Worth recording is the bad control: the
first attempt to decide whether it was pre-existing stashed only the two
`core/lib` files and left the new spec in place, so the "it fails without
my change too" run still contained the cause.*

## 024.225 A scripted edit inserted the entire file before its own anchor, and the line count was the only symptom

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it costs is that the standard way of editing
  a large tracked document in this repository can silently duplicate
  thousands of lines, and the check that noticed was counting entry
  numbers rather than looking at the edit.
target: 0.2.16
released-in: 0.2.16
```

**Area:** working practice; `CLAUDE.md`'s "Two working-practice traps"

`String#sub` expands backreferences **in the replacement string**, and
one of them is not a digit. A replacement containing a backslash followed
by a backtick means *everything before the match*.

Asked of Ruby rather than reasoned about:

    $ ruby -e '
    s = "AAAA" + "ANCHOR"
    p s.sub("ANCHOR", "x \\` y" + "ANCHOR")
    p s.sub("ANCHOR") { "x \\` y" + "ANCHOR" }
    '
    # => "AAAAx AAAA yANCHOR"
    # => "AAAAx \\` yANCHOR"
    # ruby 3.4.10

`024.223`'s entry contained a Markdown table cell with an escaped
backtick in it — an ordinary way to write a literal backtick inside bold
text. Inserting that entry took the register from 11,555 lines to
**25,878**, twice, because the replacement carried two of them and each
one pasted the preceding 7,000 lines back in.

**What is worth keeping is how it was found.** Not by reading the diff,
which was far too large to read, and not by any check that looks at
edits. `spec/meta/deferred_findings_spec.rb` failed with *"reused entry
numbers: 024.1, 024.6, 024.8, …"* — 108 of them — and that was the first
sign. The file had been through `reindex_findings.rb` and a meta run in
between, and the first guess was that the reindexer had done it; the
actual isolation came from restoring the file from `HEAD` and replaying
each scripted edit one at a time with `wc -l` after each.

This is `024.140`'s class arriving by a new route. That one was
`str.find` returning `-1` and duplicating an entry body; the shared shape
is **a scripted edit to a tracked document whose failure mode is
insertion, in a file too large for the diff to be read.**

**The countermeasure is the block form**, which does not expand anything:

    src.sub(anchor) { replacement }     # not src.sub(anchor, replacement)

It costs two characters and removes the whole class — `\0`, `\1`, `\&`,
`` \` `` and `\'` all stop being special. Every edit script in this
session was converted after the fact; what wants deciding is whether
`CLAUDE.md` should say so where it lists the traps that cost a session,
alongside `git checkout <file>` and polling an output file.

**Left open rather than closed** because the countermeasure so far is a
habit, and a habit is what `024.126` records twelve failures of in one
session. A check could plausibly catch it — the shape is "a tracked
document grew by more than the edit could account for" — and that wants
designing rather than asserting.

**Closed in 0.2.16.** The open question the entry poses was already
answered when it was written: `CLAUDE.md`'s working-practice traps
carry the block-form bullet, added in the same commit. The entry now
says so rather than leaving it open.

`scripts/check_pinned_mutations.rb` uses the block form. Its `to` is
author-supplied YAML, so "no current value bites" was a property of
today's manifest and not of the code. `scripts/documented_counts.rb`
is converted too -- the same shape, writing into tracked documents --
and its comment says plainly that no test distinguishes the two forms
there, because the difference is unreachable through that function's
own inputs and a green suite is not cover for it.

**No checker.** The shape the entry gestures at -- a tracked document
growing by more than the edit can account for -- wants a harness
around every scripted edit, and this session's edits print their line
count before and after instead. Recorded as the decision so it is not
re-opened as an oversight.

## 024.226 An argument written as a paren-less call is judged by its own last argument

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`#infer_span`,
`#locate`), `core/lib/ovallsp/diagnostics/engine.rb`
(`#mismatched_arguments`)

With `Widget#label: (String)`, `#resize: (Integer)` and
`#make: (Integer) -> String` declared in a project `sig/`:

| written | what Ruby passes | what the engine said |
|---|---|---|
| `w.label(w.make 1)` | a String, correctly | **reported**: expects String, but Integer is given |
| `w.resize(w.make 1)` | a String, wrongly | **nothing** |
| `w.label(w.make(1))` | a String, correctly | nothing — correct |
| `w.resize(w.make(1))` | a String, wrongly | reported — correct |

One defect in both directions: a false report on code that runs, and a
real mistake suppressed. Only the paren-less spelling is affected.

**Mechanism**, taken from Prism rather than reasoned about:

    Widget.new.label(Widget.new.make 1)
    argument "Widget.new.make 1"   17...34
    its own trailing `1`           33...34   <- both end at 34

`#mismatched_arguments` asked `infer_at(document, range[:end])`, and
`#infer_at` answers about the **innermost** node at an offset. That is
the right question for a cursor and the wrong one here: the caller
already knows which node it means and passing an offset throws that
away. The end offset was chosen because the *start* of
`SmallInteger.new` lands on the constant and answers
`ClassOf[SmallInteger]`; the comment at `engine.rb:441-449` already said
what the real answer was — "asking for that means carrying the argument
*node* here rather than a range".

**Fixed by carrying it.** `LocalInferencer#infer_span(document, range)`
takes both offsets and stops the descent at the node whose location
matches exactly, then evaluates that node. It reuses the existing
`#locate` walk rather than adding a second one — the env threads down
that walk and accumulates bindings, and a parallel walker would be two
things that must agree about the same descent, which is the shape
`CLAUDE.md`'s same-place rule names. The stop is one line in `#locate`,
guarded by an ivar that is nil for every other caller, so a cursor query
cannot reach it.

**Prevalence, derived here rather than quoted.** Over 997 files of
activesupport, actionpack, activerecord and railties: 41,332 positional
arguments examined, 3,117 whose own last descendant ends exactly where
they do, of which **300 are the `CallNode -> ArgumentsNode` shape** this
entry is about — a paren-less call written as an argument.
(A review pass reported 16 using a narrower filter over a different
file set; the number above is this one, from `prev20.rb`'s walk, and the
two are not the same measurement.)

**What the corpora could not show.** Rails gems: 0 added, 0 removed,
control `unresolved-constant` identical at 2,987. rbs 4.0.3 with its own
`sig/`: 0 added, 0 removed, control identical at 319, `argument-type`
unchanged at 3 — those three are `024.224`, a different defect. Both
runs bound the regression risk and neither can exercise the fix: the
check needs a *declared* parameter type, and the only hand-written-sig
corpus available has no paren-less call argument at a checked position.
The spec is what pins the fix, in both directions, with the two
parenthesised spellings and a plain literal argument as controls.

**Split out of `024.20` rather than filed under it.** `024.20` is about
`#contains?` being inclusive, which is the *upstream* cause; this is a
wrong answer with its own reproduction, its own fix, and a
`KNOWN_LIMITATIONS` paragraph it needs and `024.20` never had — that
entry is cited only inside a paragraph about blocks having no type,
which is the entry's own recorded complaint about itself, still true one
release later.

**Not widened.** `#operator_expression?` still declines an argument
carrying a top-level operator, and `#infer_span` would now answer
correctly for many of them. Relaxing that is a change that *adds*
reports, and this release is not the place: 0.2.0 produced 795 false
positives by widening this exact check. Worth its own entry and its own
corpus run.

## 024.227 Every outline symbol's `selectionRange` was its whole declaration

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/index/document_symbol_builder.rb`
(`#build_children`), `core/lib/ovallsp/index/declaration.rb` (the
`name_location` comment), `docs/CLIENT_BEHAVIOUR.md` + `.ja.md`

`#build_children` wrote `decl.location` into **both** `range` and
`selectionRange`, for every symbol — a class, a module, a constant, a
plain `def`. Picking a class in the outline therefore selected and
revealed its entire body.

`selectionRange` is a different field, and the claim is taken from the
installed types rather than remembered:

    /**
     * The range that should be selected and revealed when this symbol is
     * being picked, e.g the name of a function.
     * Must be contained by the `range`.
     */
    selectionRange: Range;

    vscode/node_modules/vscode-languageserver-types/lib/esm/main.d.ts

Writing the whole declaration into both is legal — it *is* contained by
`range`, being equal to it — and defeats the field entirely. That is why
nothing caught it: there was no rule to break.

**The narrow range existed the whole time.** `Declaration#name_location`
is populated for exactly these symbols, and `textDocument/prepareRename`
already returns it — measured on one document in one server run,
`class K` reports `(0,6)-(0,7)` for rename and `(0,0)-(4,3)` for the
outline, from the same `Declaration` object. The product emitted the
identifier for one feature and discarded it for another.

**Fixed** with `decl.name_location || decl.location`. The fallback is
the whole range rather than nil because the field is not optional and
the whole range still satisfies the containment the types require.

**What made it invisible on reading** is corrected in the same change:
`Declaration`'s own comment said `location` "is correct for
documentSymbol/folding" without distinguishing `range` from
`selectionRange`. It is correct for one of them. A row for the protocol
fact is now in `docs/CLIENT_BEHAVIOUR.md` and `.ja.md`, which is where a
claim about outside this tree belongs — the file exists because a claim
about `vscode-languageclient` was quoted forward for two releases and
was false.

**Split out of `024.27`**, which filed it as part of "one outline entry
per name a macro declares". It is not about macros: it reproduces on a
macro-free file, on every symbol kind. `024.27` keeps the macro half.

## 024.228 Every stdlib `Klass.method(` answered nothing, in three features at once

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/lib/ovallsp/types.rb` (`.class_object_lookup`,
`.class_object?`), `core/lib/ovallsp/semantic/query_service.rb`
(`#rbs_signatures`, `#signature_definition_locations`,
`#add_signature_members`, `#add_active_record_api_members`),
`core/lib/ovallsp/semantic/method_resolver.rb`
(`#normalize_class_receiver`)

`String.new(`, `File.read(`, `Integer.sqrt(`, `Time.at(` — signature
help, hover and go to definition all answered nothing.

`String` types as `ClassOf[String]`, and `#each_nominal` on that yields
a nominal named **`ClassOf`**, so RBS was asked about a class of that
name. Two moves are needed: unwrap to the type argument, and ask the
*singleton* surface. `#add_signature_members` already made both for
completion, and its own comment names two more places that make them —
so the rule existed in three hand-rolled copies while two lookups made
neither move.

**The second of those two is why this is one entry and not two.**
`#signature_definition_locations` carried a byte-identical copy of the
un-normalised lookup, so a fix aimed at signature help alone would have
left go to definition broken for exactly the calls it repaired.

**Measured before and after**, 14 stdlib class-method calls and 6
controls:

| | before | after |
|---|---|---|
| `String.new`, `Array.new`, `Hash.new`, `File.read`, `File.open`, `File.exist?`, `Dir.glob`, `Integer.sqrt`, `Time.at`, `IO.read`, `Process.pid`, `Struct.new`, `Random.rand`, `Kernel.puts` | 0 signatures, 0 definitions | answering, both |
| `Widget.build` (workspace class method) | 1 / 1 | 1 / 1 — unchanged |
| `String#upcase`, `Array#map`, `Hash#fetch` (RBS instance) | answering | identical |
| `Widget#emit` (workspace instance) | 1 / 1 | 1 / 1 — unchanged |
| `String#definitely_not_a_method` | 0 / 0 | 0 / 0 — unchanged |

Every control is byte-identical, which is what says the fix did not
start answering for everything.

**The countermeasure is `Types.class_object_lookup`**, a module function
the readers call. The rule was in three places and a fix would have made
four, with `#signature_definition_locations` a waiting fifth — the shape
`CLAUDE.md`'s same-place rule names. Deliberately **not** pushed into
`#each_nominal`: that fans it out to seven call sites including the
model-membership paths, and moving a rule to where the value is produced
is what `024.47` had to roll back.

**The corpus cannot measure this.** `scripts/corpus_diagnostics.rb`
drives diagnostics, and diagnostics do not read `#signatures_of` or
`#definitions_of` — 0 added, 0 removed with all three controls identical
is the expected result rather than evidence about the fix. The table
above is the measurement, run against both trees at the same revision.

**Split out of `024.43`**, whose stated mechanism is false — see there.

## 024.229 Signature help says nothing at the top level of a file, and cannot be fixed the way the register says

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/server.rb` (`#method_signature_help`),
`core/lib/ovallsp/semantic/query_service.rb` (`#scope_at`),
`core/lib/ovallsp/local_inferencer.rb` (`#capture_scope`)

At the top level of a file, `puts(` and `format(` answer nothing.
`#scope_at` gives `self_type = nil` outside any class body, and
`#method_signature_help` returns `{signatures: []}` before consulting
anything. RBS already has the answer:
`signatures_of(Nominal("Object"), "puts")` is `["puts(...) -> nil"]`.

**Both obvious fixes are wrong, and that is the finding.**

*Shape 2 — the entry's own stated Direction*, making the shared scope
fall back to `Object`, fails two examples, and one is a real regression:
every `Kernel` method jumps from band 3 to band 1 in bare-prefix
completion, above every workspace constant, at the top level of every
file. Worse, the spec that carries the *deliberate* decision —
`prefix_completion_spec.rb:23-34`, "does not ask for the members of a
receiver it does not have" — stays **green**, because it builds
`Scope.new(self_type: nil)` by hand and stubs the query service. It
would go on asserting about a state that no longer occurs while the
per-keystroke cost it exists to prevent came back unpinned. A green
suite is not a blast radius, exactly as `CLAUDE.md` says.

*Shape 1 — a fallback confined to `#method_signature_help`* — passes the
whole suite, and **turns silence into a wrong answer on a file in this
repository**. `core/spec/ovallsp/server_documentation_spec.rb:19`
declares `def open(uri, text, language_id: "ruby")` at the top level and
calls `open(...)` thirty lines below; with the fallback, signature help
answers with `Kernel#open`'s *file-opening* signature. Measured
collisions between top-level `def`s and `::Object`'s 120 instance
methods: 8 in `core/spec` (`open` ×5, `initialize` ×3), 2 in the stdlib,
2 in installed gems. Section 0 ranks that below the silence it replaces.

**And a guard on "is there an enclosing class" cannot stop it** — at
that position there genuinely is none, so the guard is satisfied and the
fallback fires. It is aimed at the wrong mechanism.

**What actually blocks this is `024.230`**: a top-level `def` is indexed
with `owner: nil`, so the workspace half is unreachable and an `Object`
fallback supplies Kernel's signature wherever the name collides. Fix
that first and the fallback has something correct to prefer.

**Also worth keeping**: fixing this would *not* fix the entry's headline
example. An in-class `puts(` answers as of 0.2.16 — that was `024.43` —
but a *module* body still does not, which is `024.240`, and the top
level is this entry. So a changelog line saying "signature help now
answers for Kernel calls" would be false either way. It must name the
position it means.

**Re-triaged in 0.2.17** (`024.276`). Blocked on `024.230`, which is the index side of the same position — not on the enumeration question. Its own body says the fix would not even close its headline example, because an in-class call answers, a module body is `024.240` and the top level is this entry. Turning a silence into an answer is capability, so the target stands for that reason. Not re-driven since `024.240` was split out.


**Driven at 0.3.0 and it does not reproduce.** The entry says `puts(`
and `format(` answer nothing at the top level of a file. They answer:

    puts(   -> ["puts(...) -> nil"]
    format( -> ["format(String, ...) -> String"]

with `signatures_of(Nominal("Object"), "puts")` as the control, which
the entry itself names. Something between the entry and this revision
closed it; the entry's own record of *why both obvious fixes are
wrong* is the part worth keeping, and it is why this is being closed
by measurement rather than by finding the commit.

**Closed in 0.3.0 by measurement**, not by a change: it no longer reproduces.

## 024.230 A top-level `def` is indexed with no owner, so nothing can look it up

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.18
```

### Fixed in 0.2.18, and it took three places agreeing plus a fourth decision

**The blast radius this entry feared is not where it is.** Before
changing anything: over 513 files of activesupport and bundler, 7,384
declarations, the ones carrying `owner: nil` are 358 modules and 177
classes — top-level namespaces, where `nil` is correct — one constant,
and exactly **one** instance method. The owner rule changes for that
kind and nothing else.

**Fixing the index alone bought nothing.** With the declaration recorded
on `::Object`, all four features still answered exactly what they
answered before, and so did the tree at BASE — checked, so that this was
not read as a regression. Three places have to agree:

1. the **declaration's** owner (`ParserService`), which is this entry;
2. the **call candidate's** owner — a bare call at the top level has
   `Object` as its receiver, and with none `ReceiverResolution` answers
   no receiver type at all;
3. what a **bare call's receiver is** at the top level, which
   `Server#receiverless_definitions` asks of `scope_at`.

Driven end to end afterwards: definition jumps to the `def`, hover shows
`helper(a)` and its location, signature help shows the parameter, and
Find References finds the call.

### Two questions were being asked of one value, and separating them is the fix

The first attempt gave `Scope#self_type` an `Object` fallback and broke
completion's banding: `puts` moved from band 3 (Kernel's) to band 1
(your own class's), above a workspace `Putter`. The existing example
`reports no self type at the top level of a file` failed, and **it was
right** — there is no lexically enclosing class there.

`self_type` and "what a bare call's receiver is" are different
questions. `Scope#implicit_self_type` is the second; definition, hover
and signature help read it, completion keeps reading the first.
`CLAUDE.md`'s test — do all the readers want the same answer? — says
they want it *most* of the time, which is the case that says they do not.

### And the check had to stop reporting about `Object`

Giving a bare call its `Object` receiver made `Object` a
workspace-declared class with a complete chain, so the undefined-method
check began judging it **closed**. Measured over 997 files of
activesupport, activerecord, actionpack and railties:

```
  25 introduced, 0 removed        every one false
     9 x  Object has no method named `gem`          (RubyGems' Kernel#gem)
     4 x  Object has no method named `include`      (top-level include is main's)
     7 x  java_import / javax / java / org          (a JRuby-only file)
```

`Object`'s member set is whatever the process has loaded, so no static
analysis can enumerate it — which `024.239` had already met from the
other side, hard-coding `trap`, `set_trace_func` and `iterator?` because
the signature set omits them. A list like that can only ever be partial;
the argument is for declining, not for extending it.

With the decline: **0 introduced and 2 removed**, both pre-existing false
reports in activesupport's own `core_ext` duck-typing. Control
`unresolved-constant` held at 2,987 throughout.

What it costs is a genuine typo written at the top level, which is not
reported. `024.129` records the same decline and the same cost for the
other core classes, and `unread_include_spec`-style, the cost is an
assertion rather than a sentence.

**Four fixtures had to reopen `Object` to mean anything.** Written
without a `class Object` in the workspace, all four passed with the
decline removed — the check never judges a receiver closed unless the
workspace declares it. Every Rails application has one;
`core_ext/object/blank.rb` is exactly it.

Three mutation entries, one per decision, and each needed a different
example: the declaration owner is caught by the index example, the call
owner **only** by Find References — definition, hover and signature help
work without it — and the decline only by a fixture that reopens
`Object`.

**Area:** `core/lib/ovallsp/parser_service.rb` (the owner a top-level
`def` is recorded under), `core/lib/ovallsp/index/symbol_id.rb`

A `def helper` written at the top level of a file is indexed as
`SymbolId(kind: :instance_method, owner: nil, …)` — `nil`, not
`"Object"`. Ruby puts it on `Object` as a private instance method:

```
$ ruby -e 'def helper(a); end
           p [Object.private_instance_methods(false).include?(:helper),
              self.class]'
# => [true, Object]
# ruby 3.4.10
```

So neither an `Object` nor a `Kernel` receiver reaches it —
`definitions_of` and `members_of` for both answer `[]` — and a call to
it from anywhere gets nothing from hover, completion, signature help or
go to definition.

**Found while sizing `024.229`**, and it is what makes that entry's fix
unsafe rather than merely incomplete: with the workspace half
unreachable, an `Object` fallback has nothing correct to prefer and
supplies Kernel's signature instead. 8 collisions in this repository's
own `core/spec` alone.

**Not fixed with `024.229`** because the two are different subsystems —
this is the index's, that is the server's — and because changing the
owner a declaration is recorded under is read by every feature at once.
It wants its own change set and its own corpus run.

**Re-triaged in 0.2.17** (`024.276`). This one is a **wrong answer**, not a silence: with the workspace half unreachable an `Object` fallback supplies Kernel's signature instead, 8 collisions in this repository's own `core/spec` alone. That makes it a repair of something already claimed rather than a capability, so it belongs on the patch line.

Its own body says why it is not small: the owner a declaration is recorded under is read by every feature at once, so it wants its own change set and its own corpus run. That is a reason to give it a release of its own, not a reason to file it under one that is about gems.

## 024.231 A permission written down once was still missed, and the script that hid it said the opposite

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is a release stopping to ask for a
  permission that had been granted, in writing, two years of releases
  ago -- and asking on the grounds of a script comment that contradicts
  the document.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `AGENTS.md`, `vscode/scripts/release.sh` (the header),
`docs/PUBLISHING.md` (unchanged -- it was right)

Preparing 0.2.14's publish, a session read `release.sh`'s header:

> That prompt is the one part of this script intentionally not automated
> away: initial publish and every later publish are supposed to need a
> human saying "yes, publish this" at the moment it actually happens,
> not a standing approval baked into a script that runs unattended.

and concluded it could not answer the prompt. It then asked the owner,
who replied that a patch is releasable without asking.

**The permission was written down, in full, and had been for a long
time.** `docs/PUBLISHING.md`, Publishing section: "**A patch does not
need the owner asked again.**" — the go-ahead granted in advance for a
patch, conditional on the secret and privacy checks having run and
passed, with the four conditions named. The paragraph immediately above
it goes further: the prompt "does *not* require the owner's own fingers
on the keystroke", and 0.2.3 was published by an agent driving the
script under instruction, which "is within the rule".

**That paragraph predicts this failure in its own text.** It says it is
written there "because a permission carried only in a conversation is one
compaction away from being either forgotten or assumed larger than it
is". This is the third variant: **assumed smaller**. The document
anticipated the direction of drift and still could not prevent it,
because of where it sits.

**Why one correct copy was not enough.** The reader was looking at the
script, not the document — which is the right place to look when about
to run a script. `release.sh`'s header describes the prompt's purpose
and **does not say where the delegation is written**, so it reads as the
whole rule when it is half of one. The document is at line 259 of a
three-hundred-line file that a session opens only when publishing, and
this session *was* publishing and still missed it.

**Fixed by putting the conclusion where a session already reads**, not
by restating the conditions in a second place:

- `AGENTS.md`'s first section, "Read this first, every time", now states
  that a patch is pre-approved and conditional on the checks, and points
  at `PUBLISHING.md` for the conditions themselves.
- `release.sh`'s header now names the delegation and where it lives,
  instead of implying none exists.

`PUBLISHING.md` is unchanged. It was correct; the failure was that
nothing else pointed at it.

## 024.232 The fixture proving a check has teeth lost its own teeth when a version shipped

```yaml
status: fixed
kind: friction
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that the example whose only job
  is to prove the site check can still fail would have reported the
  check toothless -- while the check was working correctly.
target: 0.2.15
released-in: 0.2.15
```

**Area:** `core/spec/meta/site_version_guard_spec.rb`, `docs/ROADMAP.md`
+ `.ja.md`

`scripts/check_site_links.rb` compares each roadmap panel's item count
against `ROADMAP.md`, **except for a version that has shipped** — a
shipped panel answers to the changelog instead, and skipping the
comparison there is correct.

The example that proves the check still has teeth plants an extra item
in a panel and expects a complaint. It chose the panel like this:

```ruby
planned = File.read(.../ROADMAP.md)[/^## (\d+\.\d+\.\d+)/, 1]
```

**The first heading, not the first unshipped one** — and its own comment
one line above says why that distinction matters: "shipped panels answer
to the changelog instead, so mutating one of those would test the wrong
branch." The selection did not enforce what the comment knew.

Cutting 0.2.15 made it true. `ROADMAP.md` still opened with `## 0.2.15`,
0.2.15 entered the changelog, and the fixture landed on a shipped panel.
The script skipped the comparison, correctly; the example saw no
complaint and reported **"a roadmap panel disagreeing with ROADMAP.md
passed the site check"**. The check was fine. The fixture had gone
blind, and it failed in the direction that accuses the thing it is
guarding.

**Two fixes, and only the second is the countermeasure.**

- `ROADMAP.md` and `.ja.md` drop the 0.2.15 section, which is the
  convention already — 0.2.14 and everything below it are gone from
  those files. That makes the fixture correct again *today*.
- The fixture now selects the first version in `ROADMAP.md` that is
  **not** in the changelog. Verified against the state one release
  ahead: with 0.3.0 shipped it selects 0.4.0 rather than going blind.
  Without this, the same failure returns the day 0.3.0 ships with its
  section still in place, which is exactly how this one arrived.

*Found by preflight during 0.2.15's release, between the changelog going
in and the tag being cut.*

## 024.233 The guard against naming a shipped release could not fire until the release had shipped

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that 0.2.15 shipped with six
  entries still naming it as their target -- the exact state `024.124`
  exists to prevent, on the fourth occurrence, with the guard green the
  whole way.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `scripts/deferred_findings.rb`
(`#open_entries_targeting_a_shipped_release`),
`core/spec/meta/deferred_findings_spec.rb`

0.2.15 was tagged, merged, published and recorded with **six open entries
still carrying `target: 0.2.15`** — `024.136`, `024.138`, `024.154`,
`024.155`, `024.156`, `024.157`. Preflight was 8/8 green before the tag,
before the merge and before the publish. The check went red on the very
next run.

**Because the fact it keys on is written after the release it should
protect.** `#open_entries_targeting_a_shipped_release` decided "shipped"
from `docs/RELEASE_ARTIFACTS.md`, whose row carries the SHA-256 of the
published VSIX and therefore cannot exist until the VSIX is published.
The guard was structurally incapable of firing in time; it reported the
mistake once the mistake had shipped.

Measured, by reconstructing the state at the moment the tag was cut —
one entry planted back at `0.2.15`, and the 0.2.15 artifact row removed:

    artifacts only (the guard as it was):   []
    artifacts + changelog (the guard now):  ["024.136 (0.2.15)"]

**Fixed by adding a source that becomes true earlier.** A changelog
section is written before the tag — it was written before the preflight
run that passed — so reading `vscode/CHANGELOG.md` as well lets the same
rule fire while there is still something to do about it.
`RELEASE_ARTIFACTS.md` stays in the union as a backstop rather than
being replaced: it is the stronger evidence, just the later one.

**This is `024.124`'s fourth occurrence**, and the first three each
produced a guard. The guard was right about what to check and wrong
about when it could know — which is a different defect from the one it
was built for, and is why a fourth hand-correction would not have
helped.

*What did not fail: `docs/RELEASE_CHECKLIST.md` names a pre-release step
for exactly this, "run the reproductions of the entries targeting this
release", and `scripts/deferred_findings.rb --targeting <version>` exists
to do it. Neither is wired into `preflight`, and preflight is what
actually gets run. A step that lives only in a checklist competes with
the gate that runs itself, and loses.*

## 024.234 The plugin subsystem was unreachable from the shipped product, and eight documents said otherwise

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  No user could reach it, which is the point: 1,028 lines of engine and
  790 of spec existed behind an option the only shipped client never
  sends, while README, the Marketplace description, the site and the
  security page all advertised it as a feature.
target: 0.2.16
released-in: 0.2.16
```

**Area:** deleted — `core/lib/ovallsp/plugins*`,
`core/spec/ovallsp/plugins*`, `core/spec/fixtures/plugins`,
`docs/design/docs/06-plugin-system.md`, `docs/design/plugin-sdk.md`, <!-- deleted -->
`docs/design/schemas/plugin-manifest.schema.json` <!-- deleted -->

The only entry point was `Server#load_static_plugins`, which returns
early unless `initializationOptions[:pluginManifests]` is a non-empty
array. The shipped extension sends `workspaceTrusted` and
`ovallspClient` and nothing else (`vscode/src/extension.ts:233-239`), and
`pluginManifests` appears **nowhere** in `vscode/src`. So the early
return always fired.

Everything the project uses to decide whether something is a feature said
it was not one:

- `docs/ROADMAP.md` and `.ja.md`: **no plugin item, in any release**.
- `docs/EXTENSION_CAPABILITIES.md`: **no plugin row** — never a verified
  capability.
- `024.73`, the fixed entry about `Marshal.load` across the plugin fork,
  says in its own note: "Reachable only by a client that sends
  `pluginManifests`, and the shipped extension sends none, so **no user of
  the published build was exposed**."

And four documents said the opposite, in both languages: the root README
and the Marketplace README listed "Plugin API (static/runtime),
process-isolated plugin execution" as implemented; `site/index.html`
carried a feature card for it; `site/security.html` carried a
threat-model card and two guarantees — "Plugins run in a real OS process
boundary" and "Runtime plugins — the highest-privilege kind — never load
at all in an untrusted workspace".

**Deleted, with the claims corrected in the same change.** Removing the
implementation and leaving the claims would have manufactured, in one
commit, exactly the state 0.2.14 spent a whole release repairing.

    core/lib/ovallsp/plugins*          1,028 lines
    server.rb wiring                      89   (4,025 -> 3,936)
    specs and the trust-gate block       790
    fixtures                              12 directories
    rescue verdicts                       11 rows (160 -> 149 sites)

**Three consequences worth keeping**, each found by the suite rather than
by reading:

- `collector_spec` had **borrowed** `fixtures/plugins` as "a directory
  that is not this fixture's root". Nothing about the example was about
  plugins; it needed any real path. Re-pointed at a neighbour the
  observation fixtures own, with the reason recorded so the next deletion
  does not puzzle over it.
- `Rename::Planner`'s comment cited a plugin declaration as the reason it
  keys on `origin: :generated` rather than a missing `name_location`.
  The decision stands and its illustration is gone; the comment now says
  so rather than pointing at a subsystem that no longer exists.
- `site/security.html` claimed the Core "refuses a protocol mismatch on
  **both** of its inbound boundaries. Agent ↔ Core and plugin ↔ Core
  alike". There is one inbound boundary now, and the sentence says one.

**Not a `major` by `docs/PUBLISHING.md`'s table**, which defines that
tier as "a ✅ row removed" among other things a user relies on. There is
no ✅ row to remove, and no user of a published build could reach the
feature. It is recorded here rather than argued in a commit message
because the next person to read the README's history will find a feature
that was listed and then was not.

## 024.238 `alias` to a method an included module declares is reported as unknown

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/index/*`

`024.91` shape C, which does still reproduce, with its control alive:

    module Escaping
      def escape(s) = s
    end
    class Page
      include Escaping
      alias safe_escape escape
    end
    Page.new.safe_escape("x")            # Page has no method named `safe_escape`
    Page.new.definitely_not_a_member     # reported, so the check keeps its edge here

Taken from Ruby, `ruby 3.4.10`:

    Page.new.respond_to?(:safe_escape)   # => true
    Page.new.safe_escape("x")            # => "x"

`alias` to a `def` in the same class body is fine; it is the hop through
the included module that is not followed. Left for 0.3.0 rather than
patched here: it is a shared path with `024.91`'s other shapes and with
the alias handling `024.R7` will have to revisit anyway, and 0.2.16 is
not the release to start that.

**Fixed in 0.3.0.** `MethodResolver#candidates_for_type` now carries a
resolved alias name back to the rest of the chain when the ordinary
pass finds nothing, so an `alias` whose target an included module
declares resolves. Only when the ordinary pass is empty, so it can add
an answer where there was none and cannot change one already given.
Corpus: activesupport + i18n, 335 files, **0 introduced, 0 removed**,
control `unresolved-constant` identical at 916.

## 024.239 A name Ruby gives every object, reported missing because RBS omits it

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`,
`core/lib/ovallsp/diagnostics/engine.rb`

`024.91` shape D. The signature set's `::Object` does not declare
everything the interpreter puts on every object, and each name in that
gap was reported as missing on the user's own class:

    class Runner
      def go
        trap("INT") { nil }   # Runner has no method named `trap`
      end
    end

A gap in this engine's signature set, stated as an assertion about
somebody's working code — the shape section 0 ranks worst. `trap` is
everyday CLI and server Ruby.

Taken from Ruby and from RBS, both sides with no gem loaded:

    $ ruby --disable-gems --disable-did_you_mean -e \
        'puts (Object.private_instance_methods + Object.instance_methods).size'
    122
    ruby=3.4.10 rbs=4.0.3
    (bare Ruby's names) - (RBS ::Object's) => ["iterator?", "set_trace_func", "trap"]

Fixed by declining on exactly those three.
**One-directional, which is why it is safe to apply at all**: it can
only remove a report, and only for a name Ruby genuinely gives every
object, so it cannot silence a typo — a typo is not such a name. The
spec's control asserts precisely that, with `definitely_not_a_member`
written into the same body.

**A first version asked this process's own `Object` and got nineteen
names rather than three** — `json` puts `to_json` there, `uri` puts
`URI`, `pp` puts `pretty_inspect`. Declining on those would have been
this engine guessing that the user's project loads whatever *it* happens
to load, which is the class of guess being removed rather than extended.
Narrowed to core Ruby: names no gem can supply and no index can
discover. What a gem defines stays `024.R7`'s question, so `URI(...)` is
still reported and correctly belongs to that entry.

Measured on `024.91`'s own corpus, both sides identical
(`corpus-sha256` equal, `unresolved-constant` control equal at 891):
`unknown-method` **18 → 16**, the two removed being rspec-core's real
`trap` calls at `bisect/coordinator.rb:52` and `runner.rb:175`, and
**nothing introduced**. The nineteen-name version removed a third,
`runner.rb:170`'s `URI` — the report that measurement made look like a
bonus is exactly the one that was a guess.

A written list is what keeps a gem out of the answer, and a written list
is what goes stale on the next Ruby or the next RBS, so
`object_signature_gap_spec.rb` re-derives both sides in a subprocess and
fails if either moves. Writing that check found its own defect: the
subprocess inherited bundler's `RUBYOPT`, so `--disable-gems` read as
honoured while rubygems was loaded back in and three names came out six.
The same lesson as 0.2.3's gate — confirm you invoked the implementation
you think you did.

## 024.240 Hover answers nothing in a view where completion and go-to-definition both answer

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/server.rb` (`#hover_result`,
`#explain_type_result`)

Driven through the real server at `bea3f38`. A `User` model carrying a
documented method, a controller assigning `@user` in a `before_action`,
and `<%= @user.full_name %>` in the view. With the caret on
`full_name`:

    textDocument/hover      -> null
    textDocument/completion -> ["full_name"]      (identical position)
    textDocument/definition -> user.rb:3          (identical position)
    hover on the same call in a .rb file
                            -> full_name(first, last)
                               Origin: source declaration
                               Defined: …:3
                               Full name of the user.

So the engine has the answer at that position and one of the three
handlers throws it away.

**Cause — and this entry stated it wrongly, which the fix corrects.**
The entry said `hover` and `explainType` both fail to build the
extracted-Ruby document the other seven handlers build. Driven,
`#explain_type_in_view` *did* build one, with the identical
`TextDocument` construction; probed at nine view positions its answers
are byte-identical before and after. What landed in ERB text was
`#hover_lines`'s document, which is why the `!erb_view?` compensation
lived there and nowhere else. Recording the wrong cause in a closed
entry freezes it into the record, so it is corrected here rather than
left standing beside a fix that contradicts it.

**Found by the `049` audit, not by a review round**, and that is the
part worth noting: the duplicate path looked exactly like the working
one, and nothing pinned the silence — adding an example for it took the
suite from 2,188 to 2,189.

`049` proposes the substitution (one view environment, one document,
read by all nine) and measured it: the view hover becomes byte-identical
to the `.rb` hover, with the suite and an activesupport corpus unchanged
either side. **The defect is filed separately from the substitution** so
that it is fixed whether or not the wider change is taken.

### Fixed in 0.2.16

Hover and `explainType` join the other seven position handlers: one view
environment, one document, so the nine cannot answer differently about
the same position again. Driven through a real server, the view hover is
byte-identical to the `.rb` hover for the same call.

A verifier drove 30 hover positions across 22 ERB shapes on both sides:
every difference is `nil` to an answer, or an answer to a richer one.
Nothing was lost and nothing new was asserted — every position that must
decline still declines.

**Two things kept out of the fix and recorded instead.**
`#view_initial_env`'s `erb_view?` guard is a second place encoding what
`VIEW_PATH_PATTERN` already encodes; replacing the body with a bare
`ivars_for_view(uri)` leaves 2,305 examples green, so it is redundancy
rather than a defect — the DTSTTCPW "N-th place that must agree" shape,
in the small. And a view hover now computes `#ivars_for_view` twice per
request where the old path computed it once, because the second call
used to be short-circuited by the guard this removes. Completion already
paid it once per request, so it is not out of line with the feature set,
but nothing measures it.


## 024.241 Find References answers from a comment, a bare literal, and `end`

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/server.rb` (`#symbol_id_and_range_at`, and
the two spellings that are gone)

Driven through the real server at `bea3f38`:

    class Widget
      def build
        # a plain comment
        42
      end
    end

with `w1.build` and `w2.build` in a second file. With the caret on a
word *inside the comment*, on the bare `42`, and on `end`,
`textDocument/references` answers **both call sites of `build`**.
`textDocument/prepareRename` at the same three positions correctly
answers `nil`.

**Cause.** Three spellings of "the symbol under the cursor" exist, and
only one applies the name-range rule. References reads a spelling that
picks the smallest declaration whose *whole range* contains the caret —
so anywhere inside a method body is inside that method's declaration.
Rename reads the spelling that requires the caret to be on the name.

The engine's own comment at `server.rb:2110-2124` already lists "the
`def` and the `end`" among the answers it calls wrong, so this is a
known judgement arriving at a handler that did not get it, rather than a
new question.

Found by the `049` audit. Nothing pinned the whole-range reading:
adding an example took the suite from 2,188 to 2,189.

**Fixed in 0.2.16.** The two whole-range spellings are deleted, not
corrected: `#reference_symbol_id_at` and `#declaration_symbol_id_at`
are gone, and `#references_result` and `#show_type_evidence_result`
now read `#symbol_id_and_range_at`, which is what Rename and
prepareRename already read. Correcting the second spelling in place
would have left the shape the entry is actually about — two readers of
one question, free to diverge again — so the fix is that there is one
reader. `showTypeEvidence` had the same defect for the same reason and
was never reported; it answered a method's observed signature from
that method's `end`.

Pinned by seven examples in the references spec — the comment, the
literal, `end` and `def` answering nothing, and three controls: the
method's own name, a call site, and the class's own name all still
answer — plus one in the observation spec that asks
`showTypeEvidence` at the `end` and at the name in the same example,
so a wholesale decline cannot pass. All five failed against the
previous code before the change was written.

**One deliberate consequence, and the argument for it.** Under the
name-range rule, References on the `class` *keyword* goes from three
answers to none, exactly as References on the `def` keyword goes from
two to none. This is the same judgement applied consistently rather
than a loss:

- `#declaration_named_at`'s own comment already named "the `def` and
  the `end`" as answers it calls wrong. The `class` keyword is that
  same position — beside a name, not on one — and nothing distinguishes
  it except that no one had written it down.
- prepareRename already refused at both keywords. A References that
  answered where Rename refuses is the disagreement the entry reports;
  it cannot be removed while keeping the keyword answering.
- The name is one token away and still answers. Nothing becomes
  unreachable; the caret has to be on the thing being asked about,
  which is where a user invoking "find references to this method" puts
  it, and where Rename has always required it.

The alternative — keep whole-range containment for the keyword alone —
is a third rule, needing a list of which keywords count, and would put
back the thing that made the defect invisible for so long.

### The second handler this narrows, which the fix did not record

`textDocument/references` is the one the entry is about. The same
deletion reaches `ovallsp/showTypeEvidence`, and a verifier measured it
where the author had not.

Probed at every position of this repository's own
`observation_runner` fixture — `class Calculator; def add(a, b); a + b;
end; end` — on both sides of the change:

    before: 26 positions answer
    after:   4 positions answer, and they are byte-identical
             (the four characters of `add` itself)

Now declining: the `def` keyword, both parameter names, the body line,
and `end`. Its caller is the palette command in
`vscode/src/extension.ts`, which sends `editor.selection.active` — the
caret wherever the reader left it — so in practice it now requires
landing on the method name.

**Kept, deliberately.** Two spellings of "the symbol under the cursor"
is the defect this entry is about, and exempting one handler
reintroduces it with a smaller blast radius rather than removing it. The
positions that stopped answering were answering *about the enclosing
method* from a comment, a parameter or an `end` — the same wrong answer
`textDocument/references` was giving, and the reason the engine's own
comment already listed "the `def` and the `end`" among the answers it
calls wrong.

The cost is real and is a usability one rather than a correctness one:
a command meant to explain what you are looking at now wants the caret
on a name. If that proves worse in use, the fix is to give the palette
command a *caret-to-name* step of its own — resolving the enclosing
declaration and then pointing at its name — rather than to give it back
a second lookup rule.

## 024.242 A class held in a local variable loses an RBS overload

```yaml
status: fixed
kind: defect
user-visible: yes
user-visible-note: >
  Fixed in 0.2.16. The two spellings of one call answer the same
  thing, and both narrow to the overload the signature declares for
  the argument's type.
target: 0.2.16
released-in: 0.2.16
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (the call-resolution
ladder), `core/lib/ovallsp/semantic/query_service.rb`

With a workspace signature declaring
`Zoo.pick: (Integer) -> String | (String) -> Symbol`:

    Zoo.pick(1)            # => String | Symbol
    k = Zoo; k.pick(1)     # => String

The same call, one hop through a local, and one of the two declared
overloads is gone. The second answer is not merely narrower — it is a
different answer to the same question, and a reader has no way to know
which of the two spellings they are being told about.

**Cause.** Two call-resolution ladders exist for one question. One is
reached when the receiver is written as a constant, decided on the AST;
the other when the receiver is a value whose type is a class object,
decided on the value. They do not have the same rungs.

`049` measured the substitution (one ladder, with the argument that made
the divergence possible turned from optional into required so no site
can omit it while its twin passes it) across five corpora with controls,
finding no change to any diagnostic. **Filed separately from it** so the
defect is fixed whichever way the shape question goes.

### Fixed in 0.2.16, and the entry had the two answers the wrong way round

The divergence is exactly one keyword. `#resolve_signature_call` takes
an `env:`, which is what lets it evaluate the argument expressions at
the call site and pick the overload RBS keys on their types
(`024.128`'s mechanism). It defaulted to `nil`, and of its five call
sites **one** omitted it: the constant-receiver rung in
`#resolve_call`. Without an env, `argument_types` is nil and every
overload of the right arity joins the union.

So the fix is to pass `env:` at that rung and make the keyword
**required**, which is `049`'s own countermeasure: a regression test
pins this one call, and only a required keyword stops the next site
being written without it. The one caller that legitimately has no
environment -- a spec invoking the private method on a bare parsed
fragment -- now states `env: nil` rather than omitting it, so the
absence is a visible decision instead of an oversight.

**What this entry got wrong, in the shape `024.131` warns about.** The
observations above are accurate; the reading of them is backwards. The
title says the local spelling *loses* an overload, and the published
limitation said it answered "from a narrower set". But narrow is
correct here: RBS declares the Integer argument returns `String`, and
`String` is the answer. It was the *constant* spelling that was wrong,
asserting `Symbol` was possible for a call the signature says returns a
`String`. The fix therefore moves the constant spelling to the local
one's answer -- the opposite direction from the one the entry's title
implies, and worth recording because a reader repairing this from the
title alone would have widened the wrong side.

**Controls, since a fix that made the engine narrow everywhere would
look identical to a correct one.** An argument whose type is unknown
must still yield both declared returns --
`OverloadResolver#narrow_by_argument_types` returns its matches
untouched rather than guessing -- and it does, on both spellings,
before and after. A `String` argument must select the *second*
declared overload and answer `Symbol`, which distinguishes "reads the
argument type" from "answers the first overload". A single-overload
method must still answer, and a name the signature does not declare
must still answer nothing.

## 024.244 prepareRename is refused on any class or module written inside a `module`/`class` body, while th

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/reference_resolver.rb`, `core/lib/ovallsp/server.rb`

prepareRename is refused on any class or module written inside a
`module`/`class` body, while the identical caret position on the compact
spelling is offered. `ReferenceResolver#resolve_constant` rebuilt a
SymbolId from `#resolve_type_name` and `#type_kind` and had to invent
the `owner` those two do not carry; `nil` is only correct for the
compact spelling. `Rename::Planner` then found no declaration for the
class, and because `Server#prepare_rename_result` does not rebuild the
reference index, `#locations_for` was empty and `#prepare` answered null
— so the editor shows its own "cannot be renamed" message. FIXED BY THIS
PATCH. Over `activerecord 8.1.3.1`'s `lib`, this is 1,060 of the 1,481
classes and modules the gem both declares and uses — 72% not renameable
at all — plus 79 whose rename plan edited every call site and left the
declaration behind, which is the 0.1.14 failure `024.28` describes as
producing a file that does not run.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Fixture, one file, both spellings present so the compact one is the control:

  module Api
    class Widget
    end
  end

  class Api2::Widget2
  end

  a = Api::Widget.new
  b = Api2::Widget2.new

Driven through the real server (didOpen, then textDocument/prepareRename), cold — nothing asked first, which is what an editor does when the user presses F2:

BEFORE (7bce3c4):
  nested  `class Widget` inside `module Api` -> nil
  compact `class Api2::Widget2`              -> {range: {start: {line: 5, character: 12}, end: {line: 5, character: 19}}, placeholder: "Widget2"}

AFTER (patched):
  nested  `class Widget` inside `module Api` -> {range: {start: {line: 1, character: 8}, end: {line: 1, character: 14}}, placeholder: "Widget"}
  compact `class Api2::Widget2`              -> {range: {start: {line: 5, character: 12}, end: {line: 5, character: 19}}, placeholder: "Widget2"}

The mechanism, probed directly on `module Foo; class Bar; end; end` + `Foo::Bar.new` (one class, two identities, each index answering about only one):

BEFORE:
  declared identity: #<data SymbolId kind=:class, owner="::Foo", name="::Foo::Bar">
  owner="::Foo" -> declarations 1, references 0
  owner=nil     -> declarations 0, references 2
  plan for owner="::Foo": edits at lines [1]     (1 = the declaration, 5 = the call site)
  plan for owner=nil:     edits at lines [1, 5]

AFTER:
  owner="::Foo" -> declarations 1, references 2
  owner=nil     -> declarations 0, references 0
  plan for owner="::Foo": edits at lines [1, 5]
  plan for owner=nil:     edits at lines []      (prepare correctly answers nil: it names no declaration)

Corpus census over `/opt/homebrew/lib/ruby/gems/3.4.0/gems/activerecord-8.1.3.1/lib`, 397 files, identical corpus-sha256 both sides, asking for every declared class/module whether the identity a *use* of that name resolves to is the identity the declaration is stored under, and whether prepareRename answers the way the server asks it (cold):

  metric                            before   after
  class/module declarations          1564    1564   (control, unchanged)
  never used in this corpus            83      83   (control, unchanged)
  used in this corpus                1481    1481   (control, unchanged)
  identity agrees with declaration    395    1455
  identity splits                    1086      26
  prepareRename (cold) answers        421    1481
  prepareRename (cold) refuses       1060       0
  rename plan edits its declaration  1402    1481
  plan misses its declaration          79       0

The census reconciles against an independent count that touches 
```

**Fixed in 0.2.17, and it needed a second half nobody had asked for.**
`ReferenceResolver#resolve_constant` asks
`WorkspaceIndex#resolve_type_symbol` for the declared identity instead
of rebuilding one from `#resolve_type_name` and `#type_kind` and
inventing the owner those two do not carry. That alone would have made
a *latent* wrong answer reachable: the same method resolved a bare name
with no nesting at all, so a caret on one of two same-named classes in
different namespaces answered about the other, and handing back a
declared identity would have turned an answer the cold path refused
into one it offers. `ReferenceCandidate` has carried `lexical_nesting`
since 0.2.10 and the *receiver* path has walked it since `024.103`; the
constant path had not, and now does.

Driven through the real server on `module Api; class Widget; end; end`
beside `module Web; class Widget; end; end`, caret on the one in `Web`,
`newName: "Gadget"`:

```
before   edits at lines [1, 6]    (both `class` lines -- two classes, one name)
after    edits at lines [6]
```

**The census, re-run against the tree this was fixed in**, over
`activerecord 8.1.3.1`'s `lib`. Both sides were handed the identical
file list (`corpus-sha256 fb3648b6…` on each), and the declaration
counts are the control -- the change resolves uses and declares
nothing, so they must not move:

```
                                     before   after
class/module declarations               799     799   (control)
  declared under >1 identity              2       2   (control)
never used in this corpus                78       4
used in this corpus                     721     795
  identity agrees with declaration        6     795
  identity splits                       715       0
prepareRename (cold) answers              6     795
prepareRename (cold) refuses            715       0
```

Two rows are worth reading past the headline. `never used` falls
because the workspace-wide pick was sending uses of 74 of these names
to some *other* class's name entirely; the nesting sends them to the
one they were written under. And `declared under >1 identity` is the
residue this does not touch: a class spelled `class Foo::Bar` in one
file and `module Foo; class Bar` in another is two SymbolIds, and a
rename still reaches only one of them. Two of 799 here.

**One hunk of this came back from the sweep unpinned, and the second
sweep's "0 unpinned" is worth less than it looks.** The hunk is
`#nested_type_name` delegating to the helper `#resolve_type_symbol`
reads. Reverse-applying it leaves the suite green because the body it
restores computes the same answer -- a behaviour-preserving extraction,
which from outside is indistinguishable from a line nothing tests.

What the sweep was pointing at underneath is real: that method had no
example of its own in nine releases, only three callers exercising it
through `024.103`'s fix. It has one now, over two same-named classes in
different namespaces, and it fails when the body is changed to fall
through to the workspace-wide pick -- which is the decision, and is in
`pinned_mutations.yml`.

**The second sweep then reported the hunk pinned, and that is not what
it sounds like.** Reverse-applying it now deletes the line the new
manifest entry names, so what goes red is
`pinned_mutations_spec.rb`'s "matches 0 times", not a behavioural
example -- checked by hand, by reverting that hunk alone and running
both spec files. The extraction remains behaviour-preserving and
nothing can pin it, because there is no behaviour to pin; the decision
inside it is what is covered. Recorded here rather than left to read as
a clean sweep.

## 024.245 `Server#prepare_rename_result` does not call `#ensure_reference_index_current`, while `#referenc

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/semantic/reference_resolver.rb`, `core/lib/ovallsp/server.rb`

`Server#prepare_rename_result` does not call
`#ensure_reference_index_current`, while `#references_result` and
`#rename_result` both do. With the reference index cold — which is its
state until the user has run Find All References or an actual rename,
and again after every edit that bumps the generation —
`Rename::Planner#locations_for` sees declarations only. For a local
variable and for an instance variable the workspace index holds no
declaration, so prepareRename answers null and the editor refuses the
rename box, while `textDocument/rename` at the identical position goes
ahead and produces the correct edits. NOT FIXED BY THIS PATCH: it is
`Server`'s dispatch rather than the identity, and folding a second
behavioural change into a measured substitution would leave neither
attributable. The fix looks like one line — the same
`ensure_reference_index_current` call the other two handlers make — but
it is O(workspace) and the method's own comment weighs that cost, so it
wants its own measurement.


*Found by the follow-up measurement `051` records.*

```
Driven through the real server. For each position: prepareRename with nothing asked first (cold); prepareRename after a references request at the same position (warm); and rename at that position.

AFTER (patched worktree — the same four rows hold at 7bce3c4 except the first, which this patch fixes):

  class in a module body      prepare(cold)=true  prepare(warm)=true  rename=nil edit(s)
  class, compact spelling     prepare(cold)=true  prepare(warm)=true  rename=nil edit(s)
  instance method             prepare(cold)=true  prepare(warm)=true  rename=2 edit(s)
  local variable              prepare(cold)=false prepare(warm)=true  rename=2 edit(s)
  instance variable           prepare(cold)=false prepare(warm)=true  rename=nil edit(s)

BEFORE (7bce3c4), first row only differs:

  class in a module body      prepare(cold)=false prepare(warm)=true  rename=nil edit(s)

The local-variable row is the clean one: source `def a\n  x = 1\n  x\nend\n`, caret at line 1 character 2. prepareRename answers null, so VS Code shows "The element can't be renamed" — and textDocument/rename at that exact position returns a WorkspaceEdit with 2 correct edits. The engine can rename it; the editor is told it cannot.

(The `rename=nil` cells on the three class/ivar rows are an artefact of the probe's `newName: "zzz"`, which `Planner#valid_identifier?` rejects for `:class` and `:ivar`. They are not part of the finding; the prepare columns are.)
```

**Not fixed in 0.2.17. Deferred deliberately, and this section is the
record of the decision rather than a note that nobody got to it.**

The one-line change was made, measured, and taken back out. It does
exactly what the paragraphs above ask — `#prepare_rename_result` calls
`#ensure_reference_index_current`, and cold F2 stops refusing. **The
only other thing it does is put `textDocument/rename` within reach of
F2 alone**, and rename is not correct for local variables.

Driven both ways: the emitted edits applied back to the source, the
result re-parsed, and where it parses, run. Eight shapes, each a `def`
holding one local, renamed at its assignment (at its use for the rescue
row). Both sides were handed the identical eight fixtures
(`corpus-sha256 c3ce1d89` on each). The run below is `98fc14e` itself,
with a Find All References at the same caret ahead of the F2 so that
every row gets an answer — which is also, exactly, what the one-line
change makes the *first* F2 do: measured separately against the patched
tree, cold, and identical row for row.

```
shape                    prepare  edits  parses  ruby before -> ruby after
hash shorthand           offers   2      NO      {name: "n"}  ->  SyntaxError
keyword shorthand        offers   2      yes     "n"  ->  ArgumentError (given 1, expected 0; required keyword: name)
arrow lambda parameter   offers   3      yes     [50, 1]  ->  [10, 1]
multiple assignment      offers   2      yes     [2, 3]  ->  [1, 3]
rescue binding           offers   1      yes     "boom"  ->  NameError: undefined local variable or method 'err'
def on a local receiver  offers   2      yes     :x  ->  NameError: undefined local variable or method 'ty'
use inside a block       offers   2      yes     4  ->  NoMethodError: undefined method '+' for nil
op-assign binding        offers   2      yes     1  ->  NoMethodError: undefined method '+' for nil
```

Eight for eight the file stops meaning what it meant; six of them stop
running, and the first does not parse. `KNOWN_LIMITATIONS` already
describes six of these eight, in both languages, as making the file
stop running — so this is not a discovery, it is the same list arriving
one keystroke closer to the user.

**Without the change, at the same revision, every one of the eight is
refused**, because prepareRename is the first request of the session and
the reference index is cold:

```
shape                    prepare
hash shorthand           refuses
keyword shorthand        refuses
arrow lambda parameter   refuses
multiple assignment      refuses
rescue binding           refuses
def on a local receiver  refuses
use inside a block       refuses
op-assign binding        refuses
```

**So the refusal is load-bearing, and it is load-bearing by accident.**
Nothing in `#prepare_rename_result` decided it; it is what a missing
call happens to do. A protection nobody designed is still a protection,
and removing it is still removing it.

**It is one gesture's worth of protection, not a guard**, and that half
of the measurement is why this entry stays open rather than being closed
as working-as-intended. At `98fc14e`, unchanged, one Find All References
at the caret is enough:

```
                                       prepareRename on `n` in
                                       `def go; n = 1; [1,2].each { |i| n += i }; n; end`
cold (F2 first)                        null
warm (Find All References, then F2)    {range: …1:2–1:3, placeholder: "n"}
```

So a user who has used Find References once is already exposed to all
eight. What the deferral buys is the first gesture of a session, and
the difference between a wrong edit being one keystroke away and two.
Worth having; not worth calling safe.

**The obvious middle course does not exist.** "Warm the index, and have
`#prepare_rename_result` decline for the shapes known to be wrong" needs
those shapes to be *nameable*, and six of the eight are not. They are
not a wrong *edit* the planner emits; they are a mention the engine does
not hold against this symbol, and there is nothing to decline on:

- `+=`, `||=`, `&&=`, a multiple-assignment target, a `for` variable and
  a rescue's `=> e` are not recorded as local-variable sites at all
  (`024.260`).
- A closed-over local's uses inside a block are not recorded
  (`024.262`).
- An arrow lambda's parameter is recorded as the *enclosing* local
  rather than as a binding of its own (`024.261`, `024.263`), so the
  engine believes it has every mention.
- The `ty` in `def ty.outer` is recorded under the method's own scope
  (`024.271`) — a different symbol rather than a missing one, so this
  one is nameable in principle, and only by fixing it.

The two that *were* nameable are the two this change set fixed: the
shorthand rows, where the site is recorded and the edit over it was
wrong (`024.274`).

The general form — decline when the local's own scope contains an
identifier we did not record — is a larger change than this entry, and
every version of it refuses renames that are fine: the same word appears
as a method call, a symbol, a string and a comment inside the body it
would scan.

**What the cost measurement said, since the paragraphs above asked for
one and it is the reason the change looked cheap.** Driven through the
real server, both sides, with the rebuild timed inside the one method
the change touches; the gesture is F2 on a local then rename at the same
caret, over a real gem's `lib` opened file by file, each pair given the
identical file list:

```
activemodel 8.1.3.1                without    with
workspace files                        73       73
ensure_reference_index_current          1        2   calls
  call 1                            1.095s   1.089s
  call 2                                 -   0.000s
prepareRename answered               null    {…, placeholder: "x"}
rename edits                            2        2   (control, unchanged)

activerecord 8.1.3.1               without    with
workspace files                       397      397
ensure_reference_index_current          1        2   calls
  call 1                           56.698s  51.566s
  call 2                                 -   0.000s
prepareRename answered               null    {…, placeholder: "x"}
rename edits                            2        2   (control, unchanged)
```

One real rebuild per gesture either way, because the rebuild is a no-op
when the index is current — so the gesture as a whole costs what it
always did, and the second call is free. **The 56.698 against 51.566 is
not a speed-up**: nothing here touches the rebuild and another agent's
corpus pass was running across both pairs. Read them as one number with
several seconds of noise. What is new is where the wait falls: somebody
who starts a rename and abandons it would pay a rebuild they used to get
out of. That is a real cost and it is *not* what stopped this — an
instant refusal to rename something the engine can rename correctly is
still the wrong answer. What stopped it is the eight rows above.

**What was done instead.** The call is not there; the comment on
`#prepare_rename_result` says the absence is a decision and names what
it is sequenced behind; and
`core/spec/ovallsp/server_rename_spec.rb` holds that decision with the
warm ask beside it as a control, so re-adding the line goes red rather
than waiting for a reviewer. The example fails in the other direction
too — if the deferral were turned into a blanket refusal of local
variables, which is a different decision and would need its own record
and its own `KNOWN_LIMITATIONS` paragraph.

This closes when the shapes close, which is why it keeps `target:
0.2.17` beside them rather than moving out on its own.

**Two of the eight were closed on the way past**, because that defect
was this change set's own to fix rather than the scope-frame work's: the
two shorthand rows, where the recorded range covered the colon.
`024.274`. The six that remain are what this is waiting on.

**Retargeted in 0.2.17 to the release its blockers are in.** The refusal is the guard, and it stays until the shapes behind it are fixed: six of the eight remain, and the two largest — `024.273` and `024.274` — are at 0.3.0. Warming the index here before they are done converts "the editor refuses" into "the editor rewrites your file wrongly", which section 0.4 ranks the other way round. Nothing about this waits on 0.2.17; it waits on them.

**Fixed in 0.3.0.** `Server#prepare_rename_result` calls
`#ensure_reference_index_current`, as `#references_result` and
`#rename_result` already did. Not the trade `documentHighlight`
makes: highlights are asked on every cursor move and this is asked
once, when the user presses F2 -- `capabilities_spec`'s third F
example still asserts the generation does not move across five
highlight requests.

## 024.246 One unresolvable `include` in a project's own RBS makes the engine report a method the same file

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`, `core/lib/ovallsp/index/type_name_resolution.rb`

One unresolvable `include` in a project's own RBS makes the engine
report a method the same file declares — through
`Index::TypeNameResolution.substitution?`, in the shipped `:safe` mode,
on `unknown-method`. `substitution?` refuses to report about a bare
inferred type that the workspace answered with a differently-namespaced
class of its own; it decided "signatures declare this name" from
`!ancestors(...).empty?`, so a chain that could not be built switched
the refusal off and the engine reported against the wrong class. This is
024.223's cause at a consumer 024.223 does not enumerate (it names two,
`#compute_ancestors`' readers and `MethodResolver#accounted_for?`), and
it is not 024.224 (no namespace comparison is involved). Fixed by this
patch and pinned by a fresh pair of examples in
`unbuildable_ancestry_spec.rb`.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Two workspaces, identical Ruby, `sig/app.rbs` differing by one line.

    # sig/app.rbs
    class Widget
      include _ToJson        # <- the only difference; nothing loaded declares it
      def label: () -> String
    end
    class Factory
      def make: () -> Widget
    end

    # a.rb
    module Zoo
      class Widget
        def zoo_only
          :here
        end
      end

      class Other
        def planted_bad
          definitely_absent      # the planted control
        end
      end
    end

    w = Factory.new.make         # arrives as a BARE `Widget`, from RBS
    w.label                      # declared on Widget, right above the include

Driven at `mode: :safe` — the mode the shipped extension gets, since nothing in `vscode/` ever sets `initializationOptions.diagnosticsMode`.

  BASE (7bce3c4):
    Widget's chain builds      : ["Zoo::Other has no method named `definitely_absent`"]
    Widget's chain unbuildable : ["Widget has no method named `label`",
                                  "Zoo::Other has no method named `definitely_absent`"]
  PATCHED (same script, patch-applied clean BASE tree):
    Widget's chain builds      : ["Zoo::Other has no method named `definitely_absent`"]
    Widget's chain unbuildable : ["Zoo::Other has no method named `definitely_absent`"]

The control holds on all four arms. Mutating the fix back (`!= false` -> `== true`) puts the report straight back, which is how the new pair was watched failing:

    expected collection contained:  [(a string including "definitely_absent")]
    actual collection contained:    ["Widget has no method named `label`",
                                     "Zoo::Other has no method named `definitely_absent`"]

The receiver has to *arrive* bare, which is why the type comes back from a signature rather than being written — a written `Zoo::Widget` carries its namespace and `WorkspaceIndex#guessed_type_name?` blanks it one line earlier.
```

## 024.247 A constant declared only in a signature file is reported `cannot resolve constant` when that fil

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because it was found by
  driving the product and is invisible to a reader of the code.
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`, `core/lib/ovallsp/index/type_name_resolution.rb`

A constant declared only in a signature file is reported `cannot resolve
constant` when that file's ancestry cannot be built —
`Engine#rbs_known_constant?` derived its answer from
`!ancestors(...).empty?`, so "declared, chain unbuildable" read as "RBS
does not know this name". The method's own comment already says it must
fail towards "known" (024.122); the sentinel introduced by 024.223's fix
is what it could not see. Fixed by this patch. **Not user-visible in the
shipped configuration, and that qualification is load-bearing:**
`unresolved_constant_findings` runs only at `MODE_RANK >= :standard`,
`Server#diagnostics_mode_from` defaults to `:safe`, and nothing under
`vscode/` sets `initializationOptions.diagnosticsMode`. It is what the
engine answers, and what any client requesting `standard`/`strict` —
including `scripts/corpus_diagnostics.rb` — is shown.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Same paired workspace as 024.223, with Ruby that *references* the RBS-declared constant rather than declaring it (a name the Ruby source declares is settled by the workspace index one line earlier and never reaches RBS):

    # sig/app.rbs — the resolvable side; the broken side adds `include _ToJson`
    module App
      class Key
        def digest: () -> String
      end
    end

    # a.rb
    module App
      def self.use
        App::Key
      end

      def self.planted_bad
        DefinitelyAbsentConstant     # the planted control
      end
    end

  BASE (7bce3c4):
    chain builds      : ["cannot resolve constant `DefinitelyAbsentConstant`"]
    chain unbuildable : ["cannot resolve constant `App::Key`",
                         "cannot resolve constant `DefinitelyAbsentConstant`"]
  PATCHED:
    chain builds      : ["cannot resolve constant `DefinitelyAbsentConstant`"]
    chain unbuildable : ["cannot resolve constant `DefinitelyAbsentConstant`"]

And on a corpus rather than a fixture — this repository's own `core/lib` (87 files) with rbs 4.0.3 as the signature root, both sides over the identical directory, corpus-sha256 `ed465e09f3ac847ef8047878254d070493046085d2eb0c70390e8eb0c0dd9741` on both:

    only BEFORE (removed):
      unresolved-constant  .../core/lib/ovallsp/signatures/environment.rb:483:13
                           cannot resolve constant `RBS::TypeName`
    only AFTER (added):
      (none)

`RBS::TypeName` is declared in rbs 4.0.3's own `sig/typename.rbs`; a probe confirms the cause is that file's `include _ToJson` ("failed to build ancestors of ::RBS::TypeName: … Could not find mixin: _ToJson"). The report was raised against `environment.rb`'s own `RBS::TypeName.parse` call.
```

## 024.248 `Diagnostics::Engine#ancestor_names` calls `AncestorEntry#name` with no `identified?` guard, so

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`, `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

`Diagnostics::Engine#ancestor_names` calls `AncestorEntry#name` with no
`identified?` guard, so an argument whose class has a parent nobody
could identify raises `Semantic::UnidentifiedAncestor` out of
`Engine#analyze` and the WHOLE document loses every diagnostic.
`Server#publish_diagnostics_for` rescues, logs and returns without
calling `publish_findings`, so the editor keeps whatever it was last
shown for that file — a stale answer that looks live, and it depends on
document content, so a user typing such a call freezes that file's
diagnostics from that keystroke on. FIXED IN THIS PATCH:
`#ancestor_names` returns `nil` when the chain is incomplete, and
`#compatible_nominal?` declines on `nil` (the reachable set is a lower
bound, so a miss is not evidence of a mismatch). This is the sixth
reader of the chain and the one 024.80's closure did not find.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Corpus, both sides, identical directory (`corpus-sha256=d454c9e39695b4e905b3226c78e5f0b16d50be42b87d02f8cc3eca051dbbebc4`, 102 files), from `<tree>/core`:

  OVALLSP_SIGNATURE_ROOT=/opt/homebrew/lib/ruby/gems/3.4.0/gems/rbs-4.0.3 \
    bundle exec ruby ../scripts/corpus_diagnostics.rb \
    /opt/homebrew/lib/ruby/gems/3.4.0/gems/rbs-4.0.3/lib

BEFORE (BASE copy, revision=(not a git repository), dirty=0):
  ANALYZE-ERROR .../lib/rbs/prototype/runtime.rb: Ovallsp::Semantic::UnidentifiedAncestor: an ancestor reached by superclass could not be identified
  ANALYZE-ERROR .../lib/rbs/prototype/runtime/value_object_generator.rb: (same)
  count.unresolved-constant=319   count.argument-type=3   -> 322 findings

AFTER (worktree, revision=7bce3c4…, dirty=4):
  no ANALYZE-ERROR
  count.unresolved-constant=326   count.argument-type=7   count.unknown-method=2   -> 335 findings

The control moved (319 -> 326) BECAUSE OF THE FIX, so I re-ran the comparison over the files that analysed on both sides. Excluding those two files: 322 findings both sides, `diff` empty, control `unresolved-constant` = 319 on both. Every one of the 13 differences is inside the two previously-unanalysable files.

Backtrace at BASE (`scratchpad/w4/al/backtrace.rb`):
  hierarchy_index.rb:67 AncestorEntry#name -> engine.rb:608 #ancestor_names -> engine.rb:583 #compatible_nominal? -> engine.rb:467 #mismatched_arguments -> engine.rb:70 #analyze

Spec, watched failing at BASE, green after, controls alive both ways (`core/spec/ovallsp/diagnostics/unidentified_ancestor_argument_spec.rb`): BASE `4 examples, 2 failures`; after `4 examples, 0 failures`. Mutating the fix's decline (`return true if reachable.nil?` -> `return false`) takes it back to 1 failure, so the decline is pinned and not merely present.

HONEST COST, and it is the precedent 024.31 already set ('removing a wrong silencer shows what it was silencing'): the 13 recovered findings are 7 `unresolved-constant` (standard mode only, hidden from a default-configured user), 4 `argument-type` that are 024.224 ('`generate_mixin` expects RBS::TypeName here, but TypeName is given' — false), and 2 `unknown-method` that are new_defects[3] (false). So a default-mode user opening those two files goes from nothing to 6 false warnings. The fix does not create those; it stops one comparison's crash from suppressing a whole file, and the restored output carries the engine's usual mix. The alternative — leaving a raise that also freezes stale diagnostics in place — is worse on section 0's own terms, because a frozen wrong answer outranks a visible one.
```

## 024.249 `QueryService#member_available_on?` asked the signature environment about the Union branch's OWN

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`, `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

`QueryService#member_available_on?` asked the signature environment
about the Union branch's OWN name and nothing above it, while the source
that put the name into the list walks the whole chain. For a workspace
class RBS has never heard of that is nothing at all, so every name Ruby
gives every object was labelled `conditional: true` and sorted into
completion's on-one-branch-only bucket. FIXED IN THIS PATCH by routing
it through `#rbs_owner_chains`, the same seam `#add_signature_members`
reads. This is the 'fifth copy' the brief asked about; it joins through
`#lookup_owners`, not by reading `Link`.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
`scratchpad/w4/probe_entries.rb`, both sides, fixture `class Widget; def shared_zzz; end; def widget_only_zzz; end; end` and `class Gadget; def shared_zzz; end; end`, receiver `Widget | Gadget`:

  BEFORE  unconditional members 1 of 122; frozen? conditional=true; to_s conditional=true
  AFTER   unconditional members 121 of 122; frozen? conditional=false; to_s conditional=false
  CONTROLS unchanged both sides: shared_zzz conditional=false, widget_only_zzz conditional=true

Spec watched failing (`core/spec/ovallsp/semantic/union_conditional_members_spec.rb`): BASE `3 examples, 1 failure` (expected false, got true), both controls green; after `3 examples, 0 failures`.

Blast radius: completion ordering only — `Member#conditional` is read in exactly one place, `Server#member_completion_items`, where it selects `MEMBER_ON_ONE_BRANCH`/`MEMBER_ON_EVERY_BRANCH` for `sortText`. Both corpora are byte-identical, which is consistent rather than contradictory: `corpus_diagnostics.rb` runs the diagnostics engine and never asks `members_of`.
```

### Fixed in 0.2.17, by deleting the lookup

`#member_available_on?` is gone, and with it the fifth opinion. It
was asked one name at a time *after* the four sources had answered,
which is what made it a copy of a question already settled --
`#members_of` now enumerates each Union branch on its own and a name
is unconditional exactly when every branch's enumeration produced
it. There is no chain left to walk a second time, and so no chain to
walk differently.

Driven on the entry's own fixture, `Widget | Gadget`: unconditional
members 1 of 122 before, 121 of 122 after; `frozen?` and `to_s`
conditional before, not after. Controls unchanged both sides:
`shared_zzz` false, `widget_only_zzz` true.

**What it leaves behind, deliberately.** `MethodResolver#complete`
still merges its own per-type `conditional`, and
`#add_source_members` no longer reads it. That is dead output rather
than a competing authority -- its only caller now hands it one
branch, so its answer is always `false` -- and removing the field
changes a public method's shape and its `method_resolver_spec`
examples, which is a change of its own rather than part of this one.

## 024.250 `QueryService#member_available_on?` cannot answer about a `nil` branch, so EVERY member of a nil

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`, `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

`QueryService#member_available_on?` cannot answer about a `nil` branch,
so EVERY member of a nilable Union is labelled conditional — including
the class's own methods and the names `nil` really does answer.
`Types::NIL` is a `Types::NilType`, not a `Nominal`, so the `case` that
unwraps the receiver falls through and the method returns `false` for
every name. `Types.class_of` already knows the answer (`NilType ->
ClassOf[NilClass]`), so the information is available and thrown away.
NOT FIXED — it is a different defect from the fifth-copy one (a receiver
shape the method does not handle, not a second spelling of the chain),
it moves completion ordering for the commonest union in the engine, and
it needs its own measurement.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
`scratchpad/w4/probe_entries.rb`, receiver `Widget | nil` where `class Widget; def shared_zzz; end; def widget_only_zzz; end; end`:

  BEFORE  members_of(Widget|nil) total 122, of which unconditional 0
  AFTER   members_of(Widget|nil) total 122, of which unconditional 0   (unchanged)
  CONTROL widget_only_zzz conditional on Widget|nil: true on both sides (correctly — nil has not got it)

`frozen?`, `to_s` and `inspect` are on both branches and are labelled conditional. Taken from Ruby, `ruby 3.4.10`:

  $ ruby -e 'class Widget; end
             p [Widget.new.frozen?, nil.frozen?, Widget.new.to_s.class, nil.to_s]'
  # => [false, true, String, ""]

This is the measurement 024.88's last paragraph records ('121 members offered today, 0 of them unconditional, including the class's own methods') and it now has a cause. Fixing it is one line — map `Types::NIL` to `Nominal("NilClass")` before the chain lookup — but it changes the sort order of every nilable receiver's completion list, which is a corpus-and-drive question rather than a free one.
```

### Fixed in 0.2.17 -- half of it, because the other half was not a defect

A `nil` branch is now enumerated as `NilClass`, which
`Types.class_of` already names and this does not restate. On
`Widget | nil`: 0 of 121 members unconditional before, 120 of 121
after, with `spin` -- the class's own method -- the one that stays
conditional.

**That one is the entry reading its own defect too wide.** It says
"*every* member ... including the class's own methods", and the
class's own method really is conditional on a nilable receiver: the
nil branch really does raise. `query_service_spec`'s "keeps members
conditional on a nilable receiver" is the control that says so and it
still passes. Only the second half -- the names `nil` answers -- was
wrong.

**And the nil branch is counted without being offered from**, which
is a rule and was decided by measurement rather than by taste.
Letting it offer its names too is the simpler rule; over
activesupport 8.1.3.1's `lib` (289 files, 1,569 receiver positions)
it moves 37 positions, of which 27 are `Unknown | nil` -- where
nothing else can be enumerated, so the whole offer would have been
`NilClass`'s 150 names at a receiver whose only certain property is
that it is not what the caller wants (`@max_key_size.` and
`module_parent_name.split(` are two of them). Counting but not
offering moves 8, every one of them an improvement. A receiver that
is *only* `nil` still offers them: there is nothing else it could
mean.

## 024.251 `def <local>.method` is recorded on the lexically enclosing class

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`, `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

`def <local>.method` is recorded on the lexically enclosing class.
`ParserService#visit_def_node` calls `#receiver_owner_name`, which
cannot name a local-variable receiver and falls back to `current_owner`
— so a singleton method the enclosing class does not have is INVENTED on
it, and receiverless calls inside that body are attributed to the
enclosing class and reported as unknown. Two of the false reports
recovered by new_defects[0] are this shape, in real gem source. NOT
FIXED — it is in the parser, not the lookup path, and changing the owner
a declaration is recorded under is read by every feature at once.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
`scratchpad/w4/al/probe_local_singleton.rb`, IDENTICAL ON BOTH SIDES (so pre-existing, not introduced here). Reduced from `rbs-4.0.3/lib/rbs/prototype/runtime.rb:270`:

  class Runner
    def go
      ty = Thing.new
      def ty.to_s
        location or raise
        location.source
      end
      ty
    end
    def control_typo
      definitely_not_a_member_zzz
    end
  end

  declarations recorded:
    instance_method  owner="::Runner" name=go
    singleton_method owner="::Runner" name=to_s      <-- invented on Runner
    instance_method  owner="::Runner" name=control_typo

  findings:
    unknown-method  line 4  Runner has no method named `location`      <-- false
    unknown-method  line 5  Runner has no method named `location`      <-- false
    unknown-method  line 10 Runner has no method named `definitely_not_a_member_zzz`   <-- CONTROL, correct

The control shows the check keeps its edge in the same body, so this is not the wholesale decline of 024.237.

Taken from Ruby, `ruby 3.4.10`:

  $ ruby -e 'class Runner
               def go
                 ty = Object.new
                 def ty.tagged_zzz; :from_local; end
                 ty
               end
             end
             p [Runner.singleton_methods(false), Runner.new.go.tagged_zzz, Runner.respond_to?(:tagged_zzz)]'
  # => [[], :from_local, false]

So the engine records a singleton method Ruby puts nowhere near `Runner`, and `Runner.respond_to?(:tagged_zzz)` is `false`. Both halves are user-visible: go-to-definition and signature help on `Runner.to_s` land on the wrong body, and the two `location` calls are reported on code that runs.
```

**Fixed in 0.2.17 by declining, which was a choice.** The engine cannot
know what the local holds, so `#receiver_owner_name` answering nil is
the honest answer and the `|| current_owner` behind it was what turned
it into an assertion. Nothing is recorded for the `def`, and its body
gets `Index::Cref#in_unnameable_method` -- an ordinary method body with
no owner and a depth that says so -- so the receiverless calls in it are
attributed to no class rather than to the wrong one. Both halves of the
reproduction above go quiet and the `control_typo` beside them still
reports.

**What declining costs, stated because it is not free.** Ruby's default
definee inside such a body is the lexical cref, so a `def` written
*inside* `def <local>.m` really does land on the enclosing class -- the
session is in `def_on_constant_spec.rb`. Keeping that one true answer
means keeping the owner that produces the false reports above, so it is
given up: a `def` nested there is declined too. That is the same answer
a block whose owner cannot be named already gives (`024.31`).

**How much that costs was counted rather than guessed**, over every
installed gem plus the 3.4.10 stdlib, with Prism alone
(`corpus-sha256 bcfec38a…`):

```
files parsed:                               9160
def on a NAMED (constant or self) receiver: 5507
def on an UNNAMEABLE receiver:                76
plain def nested inside an unnameable one:     0
files carrying at least one unnameable:       38
```

The shape the fix is about occurs 76 times in 38 files, and the one true
answer the fix gives up occurs zero times.

**Driven, both sides, over 1,763 files** -- the `lib` of seven Rails
components, `rbs` at three versions, `concurrent-ruby`, `irb` and
`minitest`. The two runs were given the identical file list
(`corpus-sha256 695f9f80…` on each) and the control was stated before
the second ran, from the first's own count: `unresolved-constant` at
4,759, which came out at 4,759. **Nothing was introduced anywhere.**
What went away was the shape the entry names, in every version of `rbs`
measured:

```
code            path                                  message
unknown-method  rbs-3.8.0/lib/rbs/prototype/runtime.rb:262,263  Runtime has no method named `location`
unknown-method  rbs-4.0.3/lib/rbs/prototype/runtime.rb:272,273  Runtime has no method named `location`
unknown-method  rbs-4.2.0/lib/rbs/prototype/runtime.rb:274,275  Runtime has no method named `location`
```

`unknown-method` 447 → 441; `argument-count` 5 → 5 and `argument-type`
1 → 1, neither of which the change can reach.

**Re-measured from scratch in the repair round that followed**, because
the numbers above were carried in the same change set that produced
them and a `reproduce` pass is worth more than a re-read. Both sides
were run again over the identical file list
(`corpus-sha256 695f9f80…`, 1,763 files), the base side from a
`git archive` of `98fc14e` into a plain directory — which is why its
header prints `revision=(not a git repository)` while the other prints
the SHA and a dirty count, so the two sides are visibly different code.
`unresolved-constant` came out at 4,759 on both, `unknown-method` 447
against 441, `argument-count` 5 against 5, `argument-type` 1 against 1,
and the set difference is exactly the six `location` lines above with
nothing introduced anywhere. The figures reproduce.

**`block_depth` is reused rather than a flag added**, and that is worth
a sentence because the first attempt at this entry, written against an
older `#visit_def_node`, argued the opposite. It had to: back then
`Cref#nameless_context?` was read by an early `return` that skipped a
scope-frame push the method-level `ensure` popped anyway, so declining
through it collapsed the enclosing method's frame. `024.258` moved that
guard into a method of its own which pushes and pops its own frame, so
the hazard is gone and the field that already means "a definition here
belongs to something this parser cannot name" is the right one to say
it with. A second flag would have been a third place to keep in
agreement, and two more transitions that must remember to clear it.
What *is* reset beside the owner is `module_owner`, because it
describes an owner that is no longer there; the example that says so is
in `def_on_constant_spec.rb`.

## 024.252 `conditional` says a method is on every branch of a Union when one branch declares it private, s

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/types.rb`

`conditional` says a method is on every branch of a Union when one
branch declares it private, so completion sorts it into the every-branch
band while calling it raises NoMethodError. This is the wrong-answer
direction section 0 ranks worst, and it is the shape 024.88's own text
says cannot happen ("#members_of decided conditional correctly all
along"). Cause: `member_available_on?` asked `MethodResolver#resolve`,
which does not filter visibility, while `#complete` — whose per-branch
answer was being discarded — does.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
From <worktree>/core, index `class Pub; def shared; end; end` and `class Priv; private; def shared; end; end`, then `members_of(normalize_union([Nominal("Pub"), Nominal("Priv")]), prefix: "shared")`.
  BASE 7bce3c4: shared -> origin=source conditional=FALSE
  patched:      shared -> origin=source conditional=TRUE
Ruby (pasted as a session in the new spec, re-run by scripts/check_interpreter_sessions.rb):
  $ ruby -e 'class Pub; def shared; end; end; class Priv; private; def shared; end; end; p Pub.new.respond_to?(:shared); p Priv.new.respond_to?(:shared)'
  # => true
  # => false
Control in the same fixture: both declarations public -> conditional=false on both sides. Script scratchpad/w4mpv/mpv_probe.rb section [D]; spec `keeps a member conditional when the other Union branch declares it private`, watched failing at BASE.
```

### Fixed in 0.2.17

The per-branch enumeration answers this by construction: `#complete`
filters visibility, so `Priv`'s branch never produces `shared`, so
the fold counts one branch of two and the member is conditional. The
old lookup asked `#resolve`, which does not filter, and got the
opposite answer from the same tree.

`Pub | Priv`, `shared`: conditional false before, true after.
Control in the same fixture, both declarations public: false on both
sides.

## 024.253 Every Object/Kernel-inherited name on a Union of two workspace classes was labelled one-branch-o

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/types.rb`

Every Object/Kernel-inherited name on a Union of two workspace classes
was labelled one-branch-only, so 121 of 122 completion items sorted into
the bottom band and the 0.2.15 sortText work inverted the list it was
meant to order. Recorded without a number inside 024.43's round-2 list
and left alone pending a measurement; that measurement is in this patch.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Index `class P; def only_p; end; def both; end; end` and `class Q; def both; end; end`; `members_of(P | Q, prefix: "")`.
  BASE:    to_s/inspect/frozen?/tap conditional=true; unconditional = 1 of 122
  patched: all four conditional=false;                unconditional = 121 of 122
Controls unchanged both sides: `both` false, `only_p` true. Script scratchpad/w4mpv/mpv_probe.rb section [C]; spec `calls a member every Union branch inherits from Object unconditional`.
```

### Fixed in 0.2.17

`P | Q`, prefix `""`: unconditional 1 of 122 before, 121 of 122
after; `to_s`, `inspect`, `frozen?` and `tap` conditional before, not
after. Controls unchanged both sides: `both` false, `only_p` true.

The cause is `024.249`'s, and so is the fix -- this entry is what it
looks like from the completion list.

## 024.254 Active Record's own API is labelled one-branch-only on a Union of two models, so `save`/`destroy

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/types.rb`

Active Record's own API is labelled one-branch-only on a Union of two
models, so `save`/`destroy`/`find` — the one thing both branches
certainly answer to — sorted below columns that only one of the two has.
`member_available_on?` consulted source resolution, the model's
columns/associations and RBS, and never
`ModelRegistry#active_record_api` at all, so it could not see the source
that produced the member.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Register models `User` (column email) and `Post` (column title), `install_active_record_api(instance: %w[save destroy update], singleton: %w[find where all], ...)`, then `members_of(User | Post, prefix: "")`.
  BASE:    save origin=model_api conditional=TRUE,  email true, title true
  patched: save origin=model_api conditional=FALSE, email true, title true
Control (`User | String`, one branch a model): save conditional=true on both sides. Script scratchpad/w4mpv/mpv_probe.rb sections [F] and [F2]; spec `calls the Active Record API unconditional when every Union branch is a model`.
```

### Fixed in 0.2.17

`#add_active_record_api_members` runs per branch like the other
three, so the API a branch produces is the API that branch is counted
as having. Nothing had to be taught about `ModelRegistry`; the
lookup that could not see it is gone.

`User | Post`, both models: `save` `origin=model_api` conditional
true before, false after. Controls: `email` and `title` conditional
on both sides, and `User | String` keeps `save` conditional on both
sides.

## 024.255 Completion answered nothing at all for a Union of class objects — `k = cond ? Foo : Bar` then `k

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/types.rb`

Completion answered nothing at all for a Union of class objects — `k =
cond ? Foo : Bar` then `k.` — while either branch on its own answers.
`Types.class_object_lookup` unwraps a receiver that IS a `ClassOf`, and
a Union of them is not one, so `each_nominal` yielded a nominal
literally named `ClassOf` and every source came back empty. This is
`024.228`'s defect surviving in the one receiver shape that entry's fix
does not reach; no register entry names it. Found in real code three
times in two gem corpora.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Index `class Foo; def self.foo_only; end; def self.shared_cm; end; end` and `class Bar; def self.shared_cm; end; end`; `k = cond ? Foo : Bar` infers `ClassOf[Bar] | ClassOf[Foo]`; `members_of` at `k.`:
  BASE:    total=0   (foo_only ABSENT, shared_cm ABSENT, new ABSENT, name ABSENT)
  patched: total=198 (shared_cm conditional=false, foo_only conditional=true, new false, name false)
Ruby (pasted as a session in the new spec): `k = (1 == 1) ? Foo : Bar; p [k.respond_to?(:shared_cm), k.respond_to?(:foo_only)]` # => [true, true].
Soundness, both sides (scratchpad/w4mpv/mpv_soundness.rb): the 198 names the Union now offers are byte-for-byte the 198 the single `ClassOf[Foo]` control offers on BOTH sides — "names the union offers that the single control does not: []" — so this is the engine's existing class-object answer reaching one more receiver shape, not a new class of answer. 0 instance methods leak in. The 5 names neither branch responds to (append_features, extend_object, module_function, prepend_features, refine — Module's private API from RBS) are identical on the single-receiver control at BASE, so they are pre-existing and not introduced here.
In corpora: activesupport core_ext/object/with.rb:44:6 (`[NilClass, TrueClass, FalseClass, Integer, Float, Symbol].each do |klass|` then `klass.`) 0 -> 247 members; notifications/fanout.rb:356:25 0 -> 244; actionpack testing/assertions/response.rb:98:17 (`handle = @controller || ActionController::Redirecting` then `handle.`) 0 -> 193, all conditional because the other branch is Unknown.
```

### Fixed in 0.2.17

Each branch gets its own `Types.class_object_lookup`, so a
`ClassOf[Foo]` member is unwrapped as the class object it is instead
of being read as a class named `ClassOf`. `ClassOf[Foo] |
ClassOf[Bar]`: 0 members before, 198 after, `shared_cm` unconditional
and `foo_only` conditional.

Soundness, pinned in the spec rather than only measured: the names
the Union offers are a subset of the ones the single `ClassOf[Foo]`
control offers, so this is the engine's existing class-object answer
reaching one more receiver shape rather than a new kind of answer.

A *mixed* Union -- one class object and one branch nothing can
enumerate -- is handled by the same move, because the unwrap is per
branch rather than a property the whole receiver has to have.

## 024.256 Go to definition still answers nothing for a Union of class objects, and this patch makes the as

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`, `core/lib/ovallsp/types.rb`

Go to definition still answers nothing for a Union of class objects, and
this patch makes the asymmetry visible rather than creating it: after
the patch, completion offers `shared_cm` at that receiver, signature
help answers one signature (it did on both sides), and
`textDocument/definition` returns zero — for a name the user can see in
the completion list. `#definitions_of` hands the whole receiver to
`MethodResolver#resolve`, whose `nominal_members` drops each `ClassOf`
branch via `Types.base_nominal`. NOT FIXED HERE; it needs the same per-
branch treatment in `#definitions_of`, which is a wider blast radius
than this substitution.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Same fixture as above. `u = normalize_union([class_object(Nominal("Foo")), class_object(Nominal("Bar"))])`.
  BASE:    members_of(u,'shared_cm')=[]            definitions_of(u,'shared_cm')=0  signatures_of=1
  patched: members_of(u,'shared_cm')=["shared_cm"] definitions_of(u,'shared_cm')=0  signatures_of=1
  CONTROL, single ClassOf[Foo], both sides: members=["shared_cm"] definitions=1 signatures=1
Script scratchpad/w4mpv/mpv_probe.rb section [I].
```

### Fixed in 0.2.17, and the entry's own verdict on itself was right

Driven at BASE before anything was changed:
`definitions_of(ClassOf[Foo] | ClassOf[Bar], "shared_cm")` answered
0, with the single-`ClassOf[Foo]` control answering 1. So the
completion fix *made the silence visible* rather than causing it,
exactly as the entry says.

Two places had to ask per branch, and neither is a band reordering:
`#definitions_of`'s source band, because
`MethodResolver#nominal_members` reads a Union by dropping every
member it cannot name and a `ClassOf` is one of those; and
`#rbs_lookup_chains`, because `Types.class_object_lookup` answers
about one receiver and a Union of class objects is not one. The
*bands* stay whole-receiver and in their existing order -- they rank
by authority, not by branch, and each already asked per nominal.

Now 2 locations for `shared_cm` and 1 for `foo_only`, with a name
neither branch declares still answering nothing.

## 024.257 An unrooted compact class path whose head resolves OUTWARD gets the enclosing frame glued onto i

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.17
```

**Fixed in 0.2.17**, at `#push_nesting` rather than at `#locate_in_namespace` as the Direction proposed. The two are the same place: `#push_nesting` is where the frame is built, and at that moment `@lexical_nesting` still holds the *parent* frames -- which is exactly the cref Ruby resolves a compact head against. So `#qualify_constant` is called on the head with nothing rearranged, and `#nesting_frame_for` states the rule in one place.

**A compact path's head is looked up; a simple name is not.** `class Runner` inside `module App` means `App::Runner` whatever else exists. `class Other::Runner` written there means whichever `Other` the enclosing nesting resolves to, and `Runner` inside that -- which is why the same source answers `[Other::Runner, App]` with no `App::Other` and `[App::Other::Runner, App]` with one. Both sessions are in the spec.

A rooted `class ::Widget::Inner` is handled by the same method: the frame is the written path with the prefix stripped, whatever encloses it.

**Blast radius, driven rather than assumed.** The four Rails gems contain 11 compact class paths and *none* nested, so that corpus could not distinguish anything -- output byte-identical, control `unresolved-constant` at 2,987. The corpus that does contain the shape is bundler and rubygems: **29 nested compact paths**, all of the `module Bundler; class CLI::Add` form where `Bundler::CLI` exists, so the head must resolve *inward*. Byte-identical there too, control at 2,114, same corpus sha256 on both sides and twelve dirty tracked files on the after side to prove the two ran different code. That is the answer the change must give: it is a lookup, and where the lookup already agreed with gluing, nothing moves.

Four examples in `nested_bare_name_spec.rb`, two per direction, because either direction alone passes against a wrong fix: dropping the enclosing frame for every compact path satisfies the outward pair, and keeping the old rule satisfies the inward pair. One mutation entry reverts it.

**Area:** `core/lib/ovallsp/local_inferencer.rb`

An unrooted compact class path whose head resolves OUTWARD gets the
enclosing frame glued onto it, and both directions invert. `module App;
class Other::Runner` written where no `App::Other` exists opens Ruby's
frame `Other::Runner`; the walk records `App::Other::Runner`, which
names nothing, so a bare constant falls through to the top-level class.
The working call is reported as an unknown method and the raising call
is silent. This is the case `024.112`'s last sentence explicitly claims
is handled correctly, and it reproduces identically at BASE and after
this patch -- the patch's rule keys on the leading `::` and this shape
has none. It is a false report, not a decline.


*Found by the follow-up measurement `051` records.*

```
Ruby first, so the expectation is not a belief:

  $ ruby -e '
  class Cfg; def top_only; end; end
  class Other; class Runner; class Cfg; def cfg_only; end; end; end; end
  module App
    class Other::Runner
      def nesting_here = Module.nesting
      def go  = Cfg.new.cfg_only
      def bad = Cfg.new.top_only
    end
  end
  p Other::Runner.new.nesting_here
  p ["go",  (Other::Runner.new.go  rescue $!.class)]
  p ["bad", (Other::Runner.new.bad rescue $!.class)]
  '
  # => [Other::Runner, App]
  # => ["go", nil]
  # => ["bad", NoMethodError]
  # ruby 3.4.10

The engine, driven through `Diagnostics::Engine` in `mode: :standard`, filtering `unknown-method`, with three files indexed -- `class Cfg; def top_only; end; end`, `class Other; class Runner; class Cfg; def cfg_only; end; end; end; end`, and the reopening above. Identical output on both sides:

  adjacent: unrooted compact head resolving outward (`App::Other` absent)
    go  (Ruby: works)          expected []          got ["cfg_only"]
    bad (Ruby: NoMethodError)  expected [top_only]  got []

Probe: two scratch scripts, run from a session scratchpad outside the
repository and not kept. The third block of the first is what the table
above reports; the reproduction is the session below, which is the part
that has to survive.

Why it is not fixed here: the frame is computed from the written path alone, and the written path is not enough to decide it -- Ruby resolves the compact head through the *enclosing* nesting, so `App::Other` existing or not changes the answer. Verified both ways:

  $ ruby -e '
  class Other; class Runner; end; end
  module App; module Other; class Runner; end; end; end
  module App
    class Other::Runner
      def nesting_here = Module.nesting
    end
  end
  p App::Other::Runner.new.nesting_here
  '
  # => [App::Other::Runner, App]
  # ruby 3.4.10

So the fix belongs at `#locate_in_namespace`, where `@workspace_index` is in reach -- resolve the head with the same nesting lookup a bare constant gets (`#qualify_constant` against the *parent* cref, which is exactly Ruby's rule), then build the frame from the resolved head. That is a behaviour change over every compact class definition in every file and needs its own corpus; a control example for the inward-resolving case is already in `nested_bare_name_spec.rb` ("leaves an unrooted compact path qualified by the enclosing frame") and it is the one and only example that fails when the frame rule is over-applied, so the fixture to hold that fix is already in place.
```

## 024.258 `#visit_def_node`'s method-level `ensure` popped `@scope_stack` for a push its early `return` ha

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

`#visit_def_node`'s method-level `ensure` popped `@scope_stack` for a
push its early `return` had skipped, so the frame the *enclosing*
construct opened was thrown away and every local written after it was
attributed one scope further out. Two unrelated locals of the same name
then shared one `owner#scope_id` — the key `Semantic::ReferenceResolver`
builds a local's SymbolId from and `Rename::Planner` selects edits by —
so renaming one rewrote the other. No register entry names it.

**A fix exists**, in the `049` substitution `parser-def-guard` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Ruby first (a method body does not see the local scope it is written in):
  $ ruby -e 'class A; v = 7; def m1; v; end; end; begin; A.new.m1; rescue NameError => e; p e.class; end'
  # => NameError    (ruby 3.4.10)

Driven through the real server, `textDocument/rename` at line 1 char 2 (the class-body `v`) of:
  class A
    v = 0
    def m1
      k = Class.new do
        def h; end
      end
      v = 1
      v
    end
  end

BASE (7bce3c4) — three edits, two of them in a different variable:
  {line: 1, character: 2}, {line: 6, character: 4}, {line: 7, character: 4}

Control, the identical fixture with `Class.new do … end` replaced by a plain value — one edit:
  {line: 1, character: 2}

HEAD — [1] for the class-body local, and [3, 4] for the method's own (the second is the control against a wholesale decline).

The scope-id shift, from the two directories the two corpus sides ran from, on `Anon = Class.new do; def a; n=1; n; end; def b; n=2; n; end; end`:
  BEFORE: scope=2, scope=2, scope=1, scope=1     # `1` is the top-level scope the block's ensure had already popped past
  AFTER:  scope=3, scope=3, scope=4, scope=4
  named-class control identical on both sides (3, 3, 4, 4)
```

### Fixed by splitting the guard out of the method that carries the `ensure`

`#visit_def_node` saved three things and restored them in a method-level
`ensure`, and its early `return` ran before the saves. So the `ensure`
undid work the early path never did: it popped the enclosing construct's scope frame for a push that had not
happened, and restored a local that had never been assigned.

The fix is not a guard on the `ensure` — it is that the guard no longer
lives in the method that carries it. `#visit_def_node` is a guard with no
`ensure` plus a `#record_and_walk_def` where every save is above every
exit. `@skip_block_frame` — a one-shot flag set in one method and cleared
in another eighty lines away — is gone with it.

Found by building `049`'s substitution, not by a review round.


## 024.259 The same `ensure` restored `@included_hook_parameter` from a local the early `return` never assi

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

The same `ensure` restored `@included_hook_parameter` from a local the
early `return` never assigned, clearing it to nil. An old-style
concern's `def self.included(base)` then stopped recognising
`base.extend(ClassMethods)` as the concern hook as soon as a `def`
inside a nameless block preceded it, so no `concern_class_methods`
ancestor fact was emitted and `HierarchyIndex` lost the edge that makes
`include OldStyle` reach `OldStyle::ClassMethods`. No register entry
names it.

**A fix exists**, in the `049` substitution `parser-def-guard` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Ruby (the hook runs and the class methods arrive whatever else the body contains):
  $ ruby -e '
  module OldStyle
    def self.included(base)
      Class.new { def h; end }
      base.extend(ClassMethods)
    end
    module ClassMethods
      def old_cm; :cm; end
    end
  end
  class Article
    include OldStyle
  end
  p Article.respond_to?(:old_cm)
  '
  # => true    (ruby 3.4.10)

Parser output, `summary.ancestor_facts`:
  BASE, that exact source:                       (none)
  BASE, the same hook without the Class.new line: concern_class_methods ::OldStyle -> ClassMethods
  HEAD, both:                                    concern_class_methods ::OldStyle -> ClassMethods

Pinned as `keeps the included-hook parameter bound across a nameless def`, with the no-Class.new form as the control; the pinned_mutations entry (re-adding `@included_hook_parameter = nil` to `#walk_nameless_def`) turns it red: `caught: … (1 example, 1 failure)`.
```

### Fixed by splitting the guard out of the method that carries the `ensure`

`#visit_def_node` saved three things and restored them in a method-level
`ensure`, and its early `return` ran before the saves. So the `ensure`
undid work the early path never did: it popped the concern hook's parameter for a push that had not
happened, and restored a local that had never been assigned.

The fix is not a guard on the `ensure` — it is that the guard no longer
lives in the method that carries it. `#visit_def_node` is a guard with no
`ensure` plus a `#record_and_walk_def` where every save is above every
exit. `@skip_block_frame` — a one-shot flag set in one method and cleared
in another eighty lines away — is gone with it.

Found by building `049`'s substitution, not by a review round.


## 024.260 `textDocument/rename` on a local misses every binding written as a compound or target node: `+=`

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

`textDocument/rename` on a local misses every binding written as a
compound or target node: `+=` (`LocalVariableOperatorWriteNode`),
`||=`/`&&=` (`LocalVariableOr/AndWriteNode`), a multiple-assignment
target and a `rescue => e` binding (`LocalVariableTargetNode`).
`ParserService::Visitor` records local references only from
`#visit_local_variable_read_node` and
`#visit_local_variable_write_node`, so those nodes produce no reference
candidate at all. The result is not a decline: rename edits *some* of
one variable's occurrences and leaves the rest, producing source that no
longer runs. `core/lib/ovallsp/semantic_tokens.rb:118-120,244` already
handles exactly these node kinds, so the gap is in the reference
recorder alone. No register entry names it.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Ruby — all of these are one variable:
  $ ruby -e '
  def m
    total = 0
    total += 1
    total ||= 2
    other, total = 1, 3
    begin
      nil
    rescue StandardError => total
      total
    end
    total
  end
  p m
  '
  # => 3    (ruby 3.4.10)

Driven through the real server at HEAD, rename `total` at line 2 char 4 of:
   0| class A
   1|   def m
   2|     total = 0
   3|     total += 1
   4|     total ||= 2
   5|     other, total = 1, 3
   6|     begin
   7|       nil
   8|     rescue StandardError => total
   9|       total
  10|     end
  11|     [1].each { |total| total }
  12|     total
  13|   end
  14| end

  edits: [[2, 4], [9, 6], [12, 4]]

Lines 3, 4, 5 and 8 are silently left alone (line 11's `|total|` is correctly left alone — a block parameter shadows). After the rename the file has `renamed = 0` followed by `total += 1` on an undefined local. Identical at BASE, so this is pre-existing and not a regression.
```

### Fixed by making a scope frame carry the names Prism says it binds

`@scope_counter` and `@scope_stack` — two ivars that had to stay in
step — are one array of frames, each carrying its node's own `#locals`,
pushed and popped by a single `#in_scope`. Every scope node opens one
through it, `ProgramNode` and `LambdaNode` included; the second had
none at all.

The rule that closes this entry is in `#binding_scope`: a reference is
tagged with the id of the frame that *binds* the name, not the
innermost frame that happens to be open. Ruby says the `w` inside
`[1].each { w = 2 }` is the same variable as the one outside, and the
`v` inside `->(v) { v }` is a different one; the innermost-frame rule
answered both backwards, and Prism had already computed both facts per
scope node.

Pinned in `core/spec/ovallsp/parser_scope_frames_spec.rb`.

### The four declines, and that none is a dead branch

Recording four more node kinds means recording ranges Prism did not
compute as names, and two of the new spellings carry rules of their own,
so a local-variable node is declined in four places. Each was counted at
the site that decides, rather than assumed, by wrapping those sites and
driving the Ruby 3.4.10 stdlib plus every installed gem:

```
9,160 files, 610,104 local-variable node visits:

  recorded                                604,577
  declined: the range is not the name         330  -- 305 a value-omitted shorthand read,
                                                     whose range carries the colon
                                                     (`JITState.new(iseq:, cfp:)`); 25 a
                                                     named capture whose range is the whole
                                                     regexp literal
  declined: a shorthand pattern binding        18  -- `024.272`; its range is the bare name,
                                                     so the comparison above cannot see it
  declined: an underscore-prefixed target   5,179  -- `024.274`
  declined: no frame binds the name             0

  604,577 + 330 + 18 + 5,179 + 0 = 610,104, so nothing here is counted twice or missed.

The no-frame branch, driven directly on the minimal case Prism recovers from:
  `x, nil = 1, 2\n`  ->  2 visits, 1 recorded, 1 declined (no frame); the declined
                        one is `[:nil, "nil"]`, a target node for a name
                        `ProgramNode#locals` does not contain.
```

So three of the four are reached constantly on real source and the
no-frame decline only on source Prism recovered from -- which is what an
editor holds mid-edit, and why it declines rather than guessing. All
four are pinned as examples rather than left as branches nothing
reaches.

**The 305 are also the measurement behind `024.272`'s shape.** Those
reads reach the range comparison and it declines every one, which is why
the node-level question is asked for the pattern binding alone: asking
it for the reads as well would be a line no example could fail on.

### The corpus, and why its headline number is zero

`scope_id` is a key every reader of `reference_candidates` sees, so the
blast radius was measured rather than reasoned about. Both sides over
the identical corpus, each printing its own provenance first:

```
scripts/corpus_diagnostics.rb over the Ruby 3.4.10 stdlib, 976 files,
corpus-sha256=2decf7788c4f16a241859c6de298c1150fd1af0c945805367f3cc4a8034ec9ef on both sides.

before  98fc14e extracted with `git archive`   7,435 findings
after   the same tree with this change set     7,435 findings
control count.unresolved-constant=7204 on both sides -- a category this change
        cannot touch, printed by each run before its findings.
count.unknown-method=231 on both sides.
sorted diff: 0 lines.

Each side printed its own cwd and corpus sha before it ran, and both say
`revision=(not a git repository)` because both are extracted trees rather than
checkouts -- so provenance alone does not distinguish them, which is the shape
`026` records as a false result. What does: `diff` of the file the change set
touches reports 343 changed lines between the two trees, so the two sides really
did run different code.
```

**Zero is the expected answer here and it is also what a run against
the wrong tree looks like**, so it is not read on its own. No check in
`Diagnostics::Engine` reads a `:local_variable` candidate — they filter
for `:method_call`, `:ivar` and `:constant` — so what changed is
Find References and Rename, which that script does not drive. The two
sides really did run different code, and the thing that changed was
measured directly over the same 976 files:

```
`summary.reference_candidates` where `kind == :local_variable`, dumped as
path/line/character/name/"owner#scope_id":

  before  103,090 occurrences recorded
  after   105,672

  recorded now and not before   2,647  -- `+=`, `||=`, `&&=`, and every target node
                                          except the underscore-prefixed ones (`024.274`)
  recorded before and not now      65  -- every one a value-omitted shorthand (`024.272`)
                                          (`JITState.new(iseq:, cfp:)`, `dump_disasm(from, to, test:)`)

Each of those 65 was classified by asking Prism which node is at the position
rather than by reading the names: 65 of 65 are reached through an `ImplicitNode`.
The 202 positions this release records less than its first attempt are, by the
same classification, 202 of 202 underscore-prefixed targets and nothing else.

Grouping, over the positions both sides recorded (raw ids are not comparable
between the two implementations, so the partition is):

  files with occurrences on both sides   831
  files whose grouping changed           479
  positions regrouped                 37,554
```

## 024.261 `#visit_lambda_node` pushes no scope frame where `#visit_block_node` does, so a lambda body shar

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

`#visit_lambda_node` pushes no scope frame where `#visit_block_node`
does, so a lambda body shares the enclosing scope id. A local created
only inside a lambda is a distinct variable in Ruby, but the engine
gives it the enclosing method's `owner#scope_id` and rename rewrites
both. Adjacent to, and better fixed with, the scope-frame substitution
that carries Prism's own `#locals`; I did not fix it here because two
patches restructuring `@scope_stack` in the same release will not merge.
No register entry names it.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Ruby — the lambda's `n` and the method's `n` are different variables:
  $ ruby -e '
  def m
    f = -> { n = 2; n }
    n = 1
    [f.call, n]
  end
  p m
  '
  # => [2, 1]    (ruby 3.4.10)

(If they were one variable, `f.call` would set it to 2 and the answer would be [2, 2].)

Driven through the real server at HEAD, rename `n` at line 3 char 4 (the method's own local) of:
   0| class A
   1|   def m
   2|     f = -> { n = 2; n }
   3|     n = 1
   4|     [f, n]
   5|   end
   6| end

  edits: [[2, 13], [2, 20], [3, 4], [4, 8]]

Both occurrences on line 2 are inside the lambda and are a different variable. Parser keys confirm the merge: every local in that fixture is `::A#3`. Identical at BASE — pre-existing, not a regression.
```

### Fixed by making a scope frame carry the names Prism says it binds

`@scope_counter` and `@scope_stack` — two ivars that had to stay in
step — are one array of frames, each carrying its node's own `#locals`,
pushed and popped by a single `#in_scope`. Every scope node opens one
through it, `ProgramNode` and `LambdaNode` included; the second had
none at all.

The rule that closes this entry is in `#binding_scope`: a reference is
tagged with the id of the frame that *binds* the name, not the
innermost frame that happens to be open. Ruby says the `w` inside
`[1].each { w = 2 }` is the same variable as the one outside, and the
`v` inside `->(v) { v }` is a different one; the innermost-frame rule
answered both backwards, and Prism had already computed both facts per
scope node.

Pinned in `core/spec/ovallsp/parser_scope_frames_spec.rb`.

## 024.262 Rename leaves a closed-over local's uses inside a block behind, producing code that no longer ru

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

Rename leaves a closed-over local's uses inside a block behind,
producing code that no longer runs. Find References misses them too. No
register entry names this.

**A fix exists**, in the `049` substitution `parser-scope-locals` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Open `def m\n  thing = 1\n  [1].each { thing = 2 }\n  thing\nend\n`, caret on `thing` at (1,2), textDocument/rename newName="renamed".
BASE 7bce3c4 -> `def m / renamed = 1 / [1].each { thing = 2 } / renamed / end` (the block's assignment is not rewritten; `thing` is now an undefined method call).
WITH PATCH -> `[1].each { renamed = 2 }`.
textDocument/references at the same caret: BASE [[0,0]] over the two-line form `thing = 1 / [1].each { thing }`; WITH PATCH [[0,0],[1,11],[2,0]] over `thing = 1 / [1].each { thing = 2 } / thing`.
Ruby says they are one variable: `def m; w = 1; [1].each { w = 2 }; w; end` returns 2.
```

### Fixed by making a scope frame carry the names Prism says it binds

`@scope_counter` and `@scope_stack` — two ivars that had to stay in
step — are one array of frames, each carrying its node's own `#locals`,
pushed and popped by a single `#in_scope`. Every scope node opens one
through it, `ProgramNode` and `LambdaNode` included; the second had
none at all.

The rule that closes this entry is in `#binding_scope`: a reference is
tagged with the id of the frame that *binds* the name, not the
innermost frame that happens to be open. Ruby says the `w` inside
`[1].each { w = 2 }` is the same variable as the one outside, and the
`v` inside `->(v) { v }` is a different one; the innermost-frame rule
answered both backwards, and Prism had already computed both facts per
scope node.

Pinned in `core/spec/ovallsp/parser_scope_frames_spec.rb`.

## 024.263 Rename rewrites an arrow lambda's own parameter when renaming a same-named enclosing local, sile

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

Rename rewrites an arrow lambda's own parameter when renaming a same-
named enclosing local, silently changing what the lambda returns.
`lambda { |v| }` was already correct, so the two spellings of one
construct disagreed.

**A fix exists**, in the `049` substitution `parser-scope-locals` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Open `def m\n  v = 1\n  f = ->(v) { v }\n  v\nend\n`, caret on `v` at (1,2), textDocument/rename newName="renamed".
BASE 7bce3c4 -> `f = ->(v) { renamed }` — the lambda stops returning its parameter and closes over the method local.
WITH PATCH -> `f = ->(v) { v }`.
textDocument/references at (1,2): BASE [[1,2],[2,14],[3,2]]; WITH PATCH [[1,2],[3,2]].
Ruby: `v = 1; f = ->(v) { v * 10 }; f.call(7) # => 70; v # => 1`. Cause: `#visit_lambda_node` was the one scope node with no frame.
```

### Fixed by making a scope frame carry the names Prism says it binds

`@scope_counter` and `@scope_stack` — two ivars that had to stay in
step — are one array of frames, each carrying its node's own `#locals`,
pushed and popped by a single `#in_scope`. Every scope node opens one
through it, `ProgramNode` and `LambdaNode` included; the second had
none at all.

The rule that closes this entry is in `#binding_scope`: a reference is
tagged with the id of the frame that *binds* the name, not the
innermost frame that happens to be open. Ruby says the `w` inside
`[1].each { w = 2 }` is the same variable as the one outside, and the
`v` inside `->(v) { v }` is a different one; the innermost-frame rule
answered both backwards, and Prism had already computed both facts per
scope node.

Pinned in `core/spec/ovallsp/parser_scope_frames_spec.rb`.

## 024.264 a false `unknown-method` on a concern's class methods

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

a false `unknown-method` on a concern's class methods. A `def` inside
`base.class_eval do … end`, written before `base.extend(ClassMethods)`
in `def self.included(base)`, cleared the recorded hook parameter, so
the concern_class_methods ancestor fact was never produced.

**A fix exists**, in the `049` substitution `parser-scope-locals` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Two-file corpus, driven with scripts/corpus_diagnostics.rb on both sides over the identical directory (corpus-sha256=72085dc3a5cd99e20edc24995734b896c4f80838b22ab7f721bd166d23efc420):
concerns.rb: `module Trackable; def self.included(base); base.class_eval do; def track_now; 1; end; end; base.extend(ClassMethods); end; module ClassMethods; def tracked?; true; end; end; end` plus an identical `Auditable` with nothing nested.
uses.rb: `class Widget; include Trackable; end`, `class Gadget; include Auditable; end`, and a Caller calling `Widget.tracked?`, `Gadget.audited?`, `Gadget.audted?`.
BASE 7bce3c4: count.unknown-method=2 — `uses.rb:12:11 Widget has no method named ``tracked?``` and `uses.rb:20:11 Gadget has no method named ``audted?```.
WITH PATCH: count.unknown-method=1, stated as --expect-control=unknown-method:1 before the run and held — only the deliberate typo remains. `Gadget.audited?` silent on both sides.
Cause: `previous_hook_parameter` was assigned BELOW `return super if @cref.nameless_context?` and restored unconditionally by the method-level `ensure`, so the early path restored nil.
```

### Already closed on `main` by the guard split, before this entry was worked

This is the user-visible statement of a defect recorded twice: the
cause is `#visit_def_node`'s method-level `ensure` undoing saves its
early `return` had skipped, which `024.258` and `024.259` record from
the mechanism's side and which the guard split fixed. Re-driven against
`98fc14e` — the tree that split landed in, and the base 0.2.17's scope
frames were built on — the reproduction above no longer reproduces, and
the scope-frame change did not touch it either:

```
`ParserService#summarize` of the concern from the reproduction above — a `def track_now` inside
`base.class_eval do … end`, written before `base.extend(ClassMethods)` — reading
`ancestor_facts` for the `concern_class_methods` relation.

98fc14e (base):                    ["ClassMethods"]
with the scope frames (this set):  ["ClassMethods"]
```

Pinned on `main` already, as `parser_def_frame_spec.rb`'s "keeps the
included-hook parameter bound across a nameless def", with the same
hook and no nested `def` as its control.

## 024.265 the same `ensure` popped the scope stack without a matching push, so one `def` inside a nameless

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

the same `ensure` popped the scope stack without a matching push, so one
`def` inside a nameless block emptied it and every later top-level local
in the file was tagged `scope_id: nil`.

**A fix exists**, in the `049` substitution `parser-scope-locals` — which is what
found it. Building the single path made the difference visible; the
duplicate path had looked like the working one.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
`ParserService#summarize` of `x = 1\nClass.new do\n  def a\n    q = 1\n  end\nend\nx = 2\nx\n`, reading the local_variable reference candidates' scope_ids.
BASE 7bce3c4: x@0:0 -> 1, x@6:0 -> nil, x@7:0 -> nil.
WITH PATCH: 1, 1, 1.
The file already knew the rule: `#visit_namespace`'s comment says "Guarding with a bare early `return` above an `ensure` in this same method would have popped four stacks that were never pushed", and moved its pushes into `#within_namespace` for exactly this. `#visit_def_node` was the place where the shape was still written.
```

### Already closed on `main` by the guard split, before this entry was worked

This is the user-visible statement of a defect recorded twice: the
cause is `#visit_def_node`'s method-level `ensure` popping a frame its
early `return` had never pushed, which `024.258` records from the
mechanism's side and which the guard split fixed. Re-driven against
`98fc14e` — the tree that split landed in, and the base 0.2.17's scope
frames were built on — the reproduction above no longer reproduces:

```
`ParserService#summarize` of `x = 1\nClass.new do\n  def a\n    q = 1\n  end\nend\nx = 2\nx\n`,
reading the local_variable reference candidates' scope_ids.

98fc14e (base):                    x@0:0 -> 1, q@3:4 -> 3, x@6:0 -> 1, x@7:0 -> 1
with the scope frames (this set):  x@0:0 -> 1, q@3:4 -> 3, x@6:0 -> 1, x@7:0 -> 1
```

The entry recorded `nil` for the last two, against `7bce3c4`. What
changed between them is `c612669`, not this change set — the scope
frames keep the answer rather than producing it. Pinned on `main`
already, as `parser_def_frame_spec.rb`'s "leaves the enclosing method
body its own scope after a nameless def"; `parser_scope_frames_spec.rb`
adds this entry's own fixture as "keeps every top-level local in the
file's own frame across a nameless def", because the frames are now
built a different way and the answer has to survive that too.

## 024.266 Find References and Rename ignore four of Prism's six local-variable node kinds

```yaml
status: done
kind: defect
user-visible: no
user-visible-note: >
  A duplicate of `024.260`, which two agents found independently in the
  same measurement. The published limitation is there; this entry keeps
  the second reproduction, which is the more precise of the two.
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

Find References and Rename ignore four of Prism's six local-variable
node kinds. `n += 1`, `n ||= 2`, `n &&= 3` and every
`LocalVariableTargetNode` (`a, b = 1, 2`; `for i in`; `rescue => e`;
pattern captures) are not recorded as reference candidates at all, so
Rename leaves them behind and writes code that does not run. No block or
scope is needed to reproduce it.


**Found by `051`'s follow-up measurement**, which built each remaining
`049` substitution and drove the register entries it was expected to
close. It closed almost none of them, and surfaced this instead.

```
Open `def m\n  n = 0\n  n += 1\n  n\nend\n`, caret on `n` at (1,2), textDocument/rename newName="renamed".
BOTH SIDES (7bce3c4 and with this patch) -> `def m / renamed = 0 / n += 1 / renamed / end`. The `n += 1` line is untouched and now raises NameError/NoMethodError.
Same on `def m\n  memo = nil\n  [1].each { memo ||= 1 }\n  memo\nend\n` -> `[1].each { memo ||= 1 }` left behind.
Enumeration: `Prism.parse("n = 0\nn += 1\nn ||= 2\nn &&= 3\nn, m = 1, 2\nfor fi in [1]\n  fi\nend\nbegin\nrescue => er\n  er\nend\n")` yields LocalVariableWriteNode, LocalVariableOperatorWriteNode, LocalVariableOrWriteNode, LocalVariableAndWriteNode, LocalVariableTargetNode x4, LocalVariableReadNode x2. `core/lib/ovallsp/parser_service.rb` defines only `#visit_local_variable_read_node` (:850) and `#visit_local_variable_write_node` (:855).
Deliberately NOT folded into this patch: it touches the same two visit methods, so mixing it would destroy the control this substitution's corpus and mutation evidence rests on, and it needs its own name-range decision per node kind, its own spec and its own drive. It is a small, self-contained one-file change and should be its own measured patch.
```

### The same defect as `024.260`, found twice in one pass

Two agents building different substitutions arrived at it independently
— one through the `def`-guard split, one through the scope frames — and
neither could see the other's report. That is the shape worth keeping:
the defect is in a path both substitutions had to touch, and neither
entry is wrong.

`024.260` carries the published limitation. This entry is folded into it
and keeps the sharper statement of the count: **four of Prism's six
local-variable node kinds** are ignored, not "some compound forms".


## 024.267 latent, spec suite only

```yaml
status: done
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because it was found by
  driving the product and is invisible to a reader of the code.
released-in: 0.2.17
```

**It does not reproduce, and the entry was wrong when it was written.** `core/spec/meta/spec_constants_spec.rb` has carried the example "defines each one in only one file" since 0.2.3 -- it walks every spec file with Prism, collects the constants that land on Object, and fails on a name defined in two of them. That is exactly the check this entry says nothing does.

It is not merely present, it is live: it fired during 0.2.17 on a `ROOT` written inside a new meta spec's `describe` block, which had silently taken the value of another file's `ROOT` and made that spec read its paths relative to the wrong directory. Caught in the same session, by the check this entry says does not exist.

Closed as not reproducing rather than fixed. The hazard is real and is what the entry describes; the claim that nothing checks for it is what was false.

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

latent, spec suite only. A constant assigned inside a `describe` block
lands on Object, so two spec files using the same name silently redefine
each other's fixture and one of them stops testing what it names.
Nothing checks for it.


*Found by the follow-up measurement `051` records.*

```
I hit this while writing this change: my new spec defined `USES = <<~RUBY …` inside its describe block, and `core/spec/ovallsp/diagnostics/reopened_foreign_class_spec.rb:58` already defines `USES = "s = \"x\"\ns.squish\ns.blank?\ns.upcase\n"` the same way. Running `bundle exec rspec spec/ovallsp/parser_scope_frames_spec.rb spec/ovallsp/diagnostics --seed 1` produced a failure whose message was about neither file's subject (`expected ["audted?"] got []`), and the file that loaded second was the one silently changed. Fixed on my side by using `let`; the hazard remains.
Scope of the exposure at 7bce3c4: `/usr/bin/grep -rnE "^  [A-Z][A-Z0-9_]+ *=" core/spec` and grouping by name shows every such constant is currently unique across the tree, so there are 0 live instances — it becomes a false-green the first time two files pick the same ordinary word. This is `024.126`'s family arriving from a different direction (a spec is tracked content, and a fixture name is a needle), and the cheap countermeasure is a meta example asserting no two spec files assign the same top-level constant.
```

## 024.268 `AgentProcessManager#force_kill` — the SIGKILL escalation behind a SIGTERM that never landed — i

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because it was found by
  driving the product and is invisible to a reader of the code.
released-in: 0.2.17
```

**Fixed in 0.2.17.** `core/spec/fixtures/stubborn_agent/boot.rb` answers `agent/hello`, ignores `agent/shutdown`, and traps SIGTERM -- so nothing but the SIGKILL escalation can end it, and "the process is gone" is a distinguishing assertion rather than a true one.

`mute_agent` was not enough on its own: it ignores shutdown but dies on the default TERM handler, so `#wait_for_exit` still succeeds and the branch is still not reached. Trapping TERM is the half that does it.

The example costs the two seconds `#wait_for_exit`'s deadline is set to, and there is no way to reach the branch without paying them.

A mutation entry removes the `ChildProcess.signal(@pid)` from `#force_kill`; the harness confirms the example fails without it, which is the direct evidence the branch is now reached at all. The older example this entry criticises keeps its own subject -- that the teardown still runs when TERM is refused -- and its comment no longer has to carry a claim about the escalation.

**Area:** `core/lib/ovallsp/agent_process_manager.rb`

`AgentProcessManager#force_kill` — the SIGKILL escalation behind a
SIGTERM that never landed — is reached by no example in its own spec
file, and the example whose comment claims to drive it asserts the
opposite of what happens. Present at BASE.


*Found by the follow-up measurement `051` records.*

```
At BASE (7bce3c4), replace `#force_kill`'s first statement with a `raise`:

    def force_kill
      raise "PROBE: force_kill reached"
      return unless @pid
      ...

then `cd core && bundle exec rspec spec/ovallsp/agent_process_manager_spec.rb` -> **34 examples, 0 failures**. The same probe against the equivalent line in the new shape, before the spec fix, also gave 34 examples, 0 failures.

Why: the example "still tears down its pipes, reader thread and pid when the TERM signal itself fails to land" builds the ordinary `rails_minimal` fixture Agent and calls `#stop`, which sends `agent/shutdown` *before* teardown. That Agent obliges and exits, so by the time `ChildProcess.signal(pid, "TERM")` is refused with EPERM, `#wait_for_exit`'s very first `Process.wait(pid, WNOHANG)` reaps the corpse and answers `true` — `force_kill` is never called. The example finishes in **0.23s**; the escalation path costs at least the two-second wait. Its own comment says "The SIGKILL escalation is what must still get to run: TERM never landed, so nothing else would have ended this process", and the second clause is false.

What that leaves unpinned: `#force_kill` is the only thing that ends a child which ignores or never receives SIGTERM, and `ChildProcess.reap`'s `Process.detach` fallback is the only thing that stops such a child becoming a zombie for the rest of the LSP session.

Fixed in this patch: the example now uses `spec/fixtures/mute_agent/boot.rb`, which completes the handshake and then answers nothing — so the child is still alive when TERM is refused and the escalation is the only thing that can end it. After the fix the same `raise` probe gives **34 examples, 1 failure**, and removing the escalation (`wait_for_exit(child.pid, 2) || force_kill(child.pid)` -> `wait_for_exit(child.pid, 2)`) gives **1 example, 1 failure**. Both are now entries in `core/spec/meta/pinned_mutations.yml`.
```

## 024.269 `AgentProcessManager#alive?` is asserted only in the false direction

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because it was found by
  driving the product and is invisible to a reader of the code.
released-in: 0.2.17
```

**Fixed in 0.2.17.** "leaves no process behind after #stop" asserts `alive?` is `true` before the stop as well as `false` after it. Five examples asserted the false direction and none the true one, so the whole body could be replaced with `false` and every example stayed green -- a live Agent reported as gone, with nothing able to say so.

Pinned by a mutation entry that returns `false` from the method's first line, which the harness confirms the example now catches. `CLAUDE.md` classes an unpinned behavioural line as a defect in its own right, and this was one in the purest form: the method could have been a constant.

**Area:** `core/lib/ovallsp/agent_process_manager.rb`

`AgentProcessManager#alive?` is asserted only in the false direction.
Replacing its whole body with `false` leaves every example in its spec
file green — so the method round 13 was written to make total could have
been a constant, and a live Agent would be reported as gone. Present at
BASE.


*Found by the follow-up measurement `051` records.*

```
Replace `#alive?`'s body with `false` and run `cd core && bundle exec rspec spec/ovallsp/agent_process_manager_spec.rb` -> **34 examples, 0 failures**. Five examples assert `alive?` is `false` (after `#stop`, after a cancelled start, after a hello timeout, and round 13's own "answers false rather than raising"); none asserts it is `true`. The `exit-hook retention` block checks liveness with the spec's own `process_alive?` helper, not with the method.

Not user-visible: nothing under `core/lib` calls `#alive?` — it is a public probe used by specs and by anything embedding the manager. It is an unpinned behavioural line, which CLAUDE.md classes as a defect in its own right.

Fixed in this patch: "leaves no process behind after #stop" now asserts `expect(@manager.alive?).to be(true)` while the Agent is running, before stopping it. The same probe then gives **34 examples, 1 failure**, and the mutation is recorded in `pinned_mutations.yml`.
```

## 024.270 Not a defect — recorded so nobody promotes it into one

```yaml
status: done
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because it was found by
  driving the product and is invisible to a reader of the code.
released-in: 0.2.17
```

**Closed as recorded rather than fixed**, which is what it was filed for: it is not a defect, it was driven on both sides at `LINES=400` and `LINES=20000`, three runs each at BASE and two after, and every line came back labelled with the Agent's pid. The pump always wins the race, because the teardown only begins once the reader thread sees stdout EOF and the pump has drained by then.

Kept in the register so the next reader who notices `#log_stderr` taking the pid as an argument does not read it as a fix and re-raise it. The signature changed because the slot went away, not because anything was wrong.

**Area:** `core/lib/ovallsp/agent_process_manager.rb`

Not a defect — recorded so nobody promotes it into one. `#log_stderr`
re-read `@pid` per line at BASE, so a line pumped after the teardown had
nil'd it would have been logged `[agent pid=]`. Driven on both sides, it
does not reproduce.


*Found by the follow-up measurement `051` records.*

```
A generated Agent that answers hello, writes N stderr lines and then `exit 1` (the shape of a crashing Agent writing its backtrace, since stdout EOF — which triggers the teardown — and the stderr backlog arrive together). `LINES=400` and `LINES=20000`, three runs each at BASE and two at HEAD, over a `RecordingLogger`:

    start => :ready
    stderr lines logged: 20000 of 20000
    labelled with the agent's pid: 20000
    labelled `[agent pid=]` (the slot had already been cleared): 0

Identical on both sides. The pump always wins the race, because the teardown only starts once the reader thread sees stdout EOF, by which time the pump has drained. `#log_stderr(stderr_read, pid)` takes the pid as an argument now as a consequence of the slot going away, not as a fix; no example distinguishes the two, and I am not claiming one. The probe doubles as a control that the change did not break the labelling.
```

## 024.271 Renaming a local leaves `def <local>.method` behind, so the file stops running

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.17
```

**Fixed in 0.2.17, and the cause was not quite the one written above.** The receiver is visited before the `@cref` switch and outside the frame `#in_scope` pushes -- not with the frame temporarily lifted, as the Direction proposed. There is nothing to take off and put back that way, so nothing here needs an `ensure` of its own, which is what `024.258` and `024.259` exist to keep out of this method.

**Driven at `160cfe6`, the scope-id half no longer reproduced.** 0.2.17's scope-frames work had already fixed it: `ty` on the `def` line binds in the enclosing frame, because it is not in the `def` node's `#locals` and `#binding_scope` walks out to find it. All three occurrences came back `scope=3`.

What was still live was the **owner**. The receiver was walked with the other children, after `@cref` had become `in_unnameable_method` -- and a receiver this parser cannot name has no owner at all, so the `def` line's `ty` was `nil#3` while the assignment that created it was `::Runner#3`. The identity is `owner#scope_id`, so one variable still had two of them and rename still left the file not running. Same symptom, other half of the cause.

Measured over 1,973 files -- activesupport, activerecord, actionpack, railties and Ruby 3.4.10's own stdlib. Six `def <local>.name` receivers in all of it: **0 of 6 carried an owner before, 6 of 6 after.** A corpus diagnostics run over the four gems came out byte-identical on both sides, `unresolved-constant` held at 2,987 as the control and the same corpus sha256 on each, which is the expected answer -- the change moves what the *reference* index records and diagnostics do not read it for locals. The two sides were confirmed to differ: the after run reported seven dirty tracked files against the same revision.

Pinned three ways. `parser_scope_frames_spec.rb` asserts the receiver and its assignment share one identity, that a local written *inside* the singleton body still does not, and that the receiver is recorded at all -- without the third, the cheapest wrong fix is to stop visiting it and the first two pass with nothing to compare. `server_rename_spec.rb` drives the real rename end to end and parses the result. Two mutation entries revert each half, and the harness confirms both examples fail without them.
**Area:** `core/lib/ovallsp/parser_service.rb`

`ParserService#record_and_walk_def` pushes the `def`'s own
local-variable frame before walking its children, and the receiver of
`def <expr>.name` is one of those children. So the `ty` written in `def
ty.outer` is recorded under the *method's* scope id while the `ty = …`
that created it, and every later read, are under the enclosing one. The
two get different `owner#scope_id` keys, Find References answers about
one of them, and a rename rewrites every mention except the one on the
`def` line -- which is `024.28`'s failure exactly: a WorkspaceEdit that
leaves the file not running.

Ruby evaluates that receiver in the enclosing scope, and the local is
not visible inside the singleton body at all, `ruby 3.4.10`:

```
$ ruby -e '
class Runner
  def go
    ty = Object.new
    def ty.reads_outer
      defined?(ty)
    end
    [ty.reads_outer, binding.local_variable_defined?(:ty)]
  end
end
p Runner.new.go
'
# => [nil, true]
```

**Found while building `024.251`'s fix.** The scope example written for
it asserted that `ty` and a local beside it shared one frame, passed,
and could not have failed -- the fixture could not distinguish the two
candidate answers. Strengthening it so that it could is what surfaced
this, and the strengthened example no longer makes the claim, because
the claim is false.

Driven through the real server at `98fc14e`, source
`class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      :x\n    end\n    ty\n  end\nend\n`,
caret on the assignment at line 2, `newName: "thing"`:

```
rename `ty` -> edits at lines [2, 6]

class Runner
  def go
    thing = Thing.new
    def ty.outer
      :x
    end
    thing
  end
end
```

The parser's own view of the same file, three candidates for one local:

```
line 2   name=ty     scope=3
line 3   name=ty     scope=4      <-- the receiver, in the def's frame
line 6   name=ty     scope=3
```

**Direction.** The receiver has to be walked with the enclosing frame on
top -- the push stays where it is, and the one child that is the
receiver is visited with the frame temporarily off, restored in an
`ensure` of its own. Not done in the change set that found it, for two
reasons: the edit moves a walk relative to the frame push whose
placement `024.258` and `024.259` exist to protect, and 0.2.17's
scope-frame work is rebuilding that same method in parallel. It belongs
there rather than bolted onto a change set about what rename can name.

## 024.272 Renaming a local leaves every value-omitted shorthand behind, so the rename is still partial

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.2.17
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/rename/planner.rb`

`helper(limit:)` is `helper(limit: limit)`, `{a:}` is `{a: a}`, and
`in {a:}` binds `a` from the key `a:`. Renaming the local needs
`helper(limit: renamed)` — an **insert**, where `Rename::Planner`
replaces one range with one `newText` built from the new name. Both
edits that shape can express are wrong, and each is wrong silently:

- replace the range Prism reports for the read, which carries the
  colon, and `helper(limit:)` becomes `helper(renamed)` — a keyword
  argument turned into a positional one, which still parses;
- replace the name alone and it becomes `helper(renamed:)` — a
  *different keyword* passed, which also still parses.

0.2.17 takes neither. All three spellings are declined, by two rules
that answer the same question for different shapes:
`#record_local_variable`'s "is this range the name?" comparison, which
answers *no* for the two whose range holds `name:`, and
`#visit_implicit_node`, which declines the pattern binding — the one
whose range **is** the bare name, so the comparison cannot see it. The
occurrence is then not a reference candidate at all: rename leaves it as
written, Find References does not list it, and what the user gets is a
file where `helper(limit:)` names a local that no longer exists. That
is the same partial rename `024.260` published, in the one shape
0.2.17 did not close.

**Ranked deliberately, not overlooked.** Section 0 puts the two wrong
edits below saying nothing, and the first of them is what the engine
did until 0.2.17 — so this entry records a narrowing that is an
improvement and still not an answer. What it needs is an edit kind
`Rename::Planner` does not have.

### The pattern spelling is why the decline moved, and it is the one that mattered

0.2.17's first attempt declined on a comparison —
`location.slice == name.to_s` — which catches the two spellings whose
reported range carries the colon **by accident** and says nothing
about the third. A *pattern's* shorthand target is reported without
the colon, so the comparison passes it and the edit rewrites the hash
pattern's key:

```
$ ruby -e '
require "prism"
{ "in {a:}" => "case h\nin {a:}\nend\n",
  "h = {a:}" => "a = 1\nh = {a:}\n",
  "helper(limit:)" => "limit = 1\nhelper(limit:)\n" }.each { |label, src|
  Prism.parse(src).value.breadth_first_search { |node|
    next false unless node.is_a?(Prism::ImplicitNode)
    p [label, node.value.class.name.split("::").last, node.value.location.slice]
    false
  }
}
'
# => ["in {a:}", "LocalVariableTargetNode", "a"]
# => ["h = {a:}", "LocalVariableReadNode", "a:"]
# => ["helper(limit:)", "LocalVariableReadNode", "limit:"]
# ruby 3.4.10
```

Rewriting a key changes which values the `case` matches, and with an
`else` branch **nothing raises at all**:

```
$ ruby -e '
def before(h) = (case h; in {a:} then a + 1; else :fell_through; end)
def after(h)  = (case h; in {renamed:} then renamed + 1; else :fell_through; end)
p before({ a: 1 })
p after({ a: 1 })
'
# => 2
# => :fell_through
# ruby 3.4.10
```

Driven on real gem source — `net-imap-0.6.6/lib/net/imap/errors.rb`,
caret on `tag`, `textDocument/rename`:

```
BASE 98fc14e         3 edits, lines 337, 338, 342.
the comparison-only guard  4 edits — line 334's `response => TaggedResponse[tag:, name: status]`
                           among them, so the destructuring looks for a key the response
                           does not have and the method raises ArgumentError instead of working.
asking Prism (shipped)     3 edits, lines 337, 338, 342 — the same as BASE.
```

So the comparison is necessary and is not sufficient, and asking the
node above is asking Prism for the thing itself rather than inferring
it from the text.

**The node question is asked only where the comparison cannot answer**,
which is the pattern. Declining the two read spellings there as well
would be a line no example could fail on — the comparison has already
declined them by the time it would run — and this project treats an
unpinnable behavioural line as a defect of its own. What that leans on
is the property in the session above, that both read ranges carry the
colon, and that is not left to memory:
`scripts/check_interpreter_sessions.rb` re-runs the session on every
suite run, so a Prism that stopped including the colon fails a check
instead of quietly widening a rename.

**Found while closing `024.260`**, by counting where the location
guard fires rather than assuming it fired only on the regexp shape it
was written for; the pattern half was found by a review round driving
the first attempt.

```
How often each spelling occurs, counted with Prism over every installed gem
(7,647 files) and over the Ruby 3.4.10 stdlib (976 files):

  stdlib      read, range carries the colon        65
  gems        read, range carries the colon       221
  gems        pattern binding, bare name            3   net-imap errors.rb:334, 337, 338

Over the stdlib, the positions 0.2.17 stops recording relative to BASE are
exactly 65, and every one of them is this shape — `JITState.new(iseq:, cfp:)`,
`dump_disasm(from, to, test:)`, `Label.new(id: @label_id += 1, name:)`.
```

Pinned as `parser_scope_frames_spec.rb`'s "declines keyword-argument
shorthand, whose location carries the colon", "declines a hash
pattern's shorthand binding, whose range is the pattern's key too",
"declines the same shorthand written as a hash literal's value" and
"leaves a hash pattern's shorthand key as written", with "records a
pattern binding the source writes out in full" as the control — so the
decline is a decision with an example rather than a side effect nobody
stated.

### Closed by the other half of the same release, once the two halves met

Filed as a narrowing on the argument that "the correct edit inserts where
`Rename::Planner` replaces one range with one newText". A sibling cluster
had already made the planner expand it: the whole `name:` is the site and
`name: renamed` is the new text.

The two never met because **both clusters wrote a `#visit_implicit_node`
and the later silently replaced the earlier**, so the expansion was dead
code. The suite said so — two examples failed the moment both landed —
and one method now makes both decisions, because the two spellings that
arrive there want opposite answers:

- a **target** binds *from* the key (`in {a:}` matches the key `a`), so
  expanding rewrites the key and changes which key is matched. Declined,
  and `024.274`'s neighbour records what that costs.
- a **read** is the value half (`{a:}` is `{a: a}`), so expanding is
  right, and it is the one shape where replacing a range with a longer
  string is not lossy.

Driven through a real server after the merge, renaming `label`:

```
  [{ label: }, take(label:)]   ->   [{ label: renamed }, take(label: renamed)]
```

three edits, the file parses, and the keys are untouched.



**0.3.0 changed one of this entry's two answers.** The pattern half —
`in {a:}`, where the key is left as written and the use is rewritten —
was chosen here on the argument that a partial rename is louder than a
`case` that silently matches differently. Both of those are wrong
answers. The third, refusing, was not weighed, and section 0 ranks it
above either.

`024.273` takes it, and not as a decision about patterns: the planner
now refuses a local rename when no occurrence of the local is a write,
which is to say when this engine does not know where the local is
bound. A hash pattern's shorthand is one of the two bindings it does
not record, so it is refused with a reason instead of half-rewritten.
The `helper(limit:)` and `{a:}` halves of this entry are unaffected:
those are recorded, and they expand.

## 024.273 Renaming a local that is a parameter leaves the parameter behind, and the answer can be silent

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/parser_service.rb`

`ParserService::Visitor` records a local-variable reference from the
six node kinds that *use* a local. It records nothing from the node
kinds that declare a **parameter** — `RequiredParameterNode`,
`OptionalParameterNode`, the two keyword parameter nodes,
`RestParameterNode`, `KeywordRestParameterNode`, `BlockParameterNode`
— and a parameter is where most locals in real code are bound. So
renaming `value` in `def double(value); value * 2; end` rewrites the
body and leaves the `def` line, and the method stops working.

**The failure is not always loud, and that is what makes this the
largest of the rename findings rather than an untidy one.** Where the
remaining occurrence assigns before reading, the renamed file runs and
answers something else:

```
$ ruby -e '
def before(names) = ((names = names || ["fallback"]); names)
def after(names)  = ((renamed = renamed || ["fallback"]); renamed)
p before(["given"])
p after(["given"])
'
# => ["given"]
# => ["fallback"]
# ruby 3.4.10
```

Both halves reproduce at BASE `98fc14e`, so this predates 0.2.17 and
is not caused by it.

**Measured, because the size of it is the argument for taking it
next.** Every local-variable symbol in 1,179 files of activerecord,
activesupport, actionpack, railties, rbs and irb was renamed to a
fresh same-length name, the edits applied, the file re-parsed, and the
two syntax trees compared with the new name mapped back:

```
ruby rename_oracle.rb, 1,179 files, identical corpus on every side.

                                renames   locals whose rename       of those, the name is
                                checked   changes the meaning       a parameter in that file
  BASE 98fc14e                   25,863                 9,157                        —
  this release                   23,091                 7,813                    7,816 of 7,901*

  renames that stop the file parsing:  BASE 130    this release 0

* the parameter count is over this release's set including the 88 that are also
  counted under another shape; 99% of what remains is this entry.
```

**0.2.17 adds instances to it**, and the entry says so rather than
leaving it to be discovered: recording the compound spellings
(`024.260`) makes a parameter renameable from an occurrence that used
to have no candidate. Over the same corpus that is **one** local —
`activerecord/lib/active_record/encryption/encryptable_record.rb`'s
`attribute_names`, an optional parameter whose only other spelling is
`|=`, where the renamed file runs and answers `true`. Against 130
non-parsing renames and 1,344 broken locals removed, the release is
taken with this recorded rather than held.

**The direction** is to record the parameter's own range, declining
the two keyword-parameter nodes for `024.272`'s reason — `def m(by:)`
spells the method's interface, and rewriting it renames the keyword
every caller passes, not the local. That is a capability change with
its own corpus to drive, which is why it is an entry rather than a
hunk in a review round.

Pinned as `parser_scope_frames_spec.rb`'s "does not record a
parameter's own range, so a rename leaves the `def` line behind", so
the gap is a written decision rather than an absence.

**Taken in 0.3.0, and the shape of the fix is not quite the one this
entry named.** The direction above was "record the parameter's own
range, declining the two keyword-parameter nodes". The recording half
is done: seven parameter kinds now record their binding site as a
write, which also gave 0.3.0's `documentHighlight` (F1) the occurrence
it was missing — the feature did not work for the commonest local in
Ruby without it.

**Declining to record the keyword nodes was not enough on its own**,
and this entry did not see it. With no binding site recorded, Rename
did not refuse — it rewrote the body and left the signature, which is
this entry's own failure arriving through the exception it named:

```
def m(by:)      def m(by:)
  by * 2    ->    factor * 2
end             end
```

This entry argued that "an occurrence nothing records is one nothing
can miss". That is true of the occurrence and false of the *count*:
`Rename::Planner` now refuses a local rename when **no occurrence of
the local is a write**, which is to say when this engine does not know
where the local is bound. Every binding form the parser records is
recorded as a write, so the question is always answerable, and any
binding form added later is refused rather than half-rewritten until
it is recorded. `Index::Reference` carries `write` for that reader, the
way it already carried `implicit_hash_value` for the same one.

**Not re-measured.** The corpus figures above were taken before the
fix. `scripts/rename_oracle.rb` over the same 1,043-file corpus is the
way to re-take them, and it was not run to completion here; the
published limitation was rewritten to state the shape rather than to
carry a number nothing measured.
## 024.274 An underscore-prefixed target is not recorded, because Ruby lets one pattern bind it twice

```yaml
status: fixed
kind: defect
user-visible: yes
target: 0.3.0
released-in: 0.3.0
```

**Area:** `core/lib/ovallsp/parser_service.rb`

A pattern may bind the same name twice only when the name begins with
an underscore:

```
$ ruby -e '
["case [1, 2]; in [_a, _a] then :ok; end",
 "case [1, 2]; in [zz, zz] then :ok; end"].each { |src|
  begin
    p eval(src)
  rescue SyntaxError => e
    p e.message.include?("duplicated variable name")
  end
}
'
# => :ok
# => true
# ruby 3.4.10
```

Each of those two ranges really is the name and nothing else, so no
question asked *at a range* can see the problem: it is the pair that
is illegal. `Rename::Planner` builds one `newText` per range and has
no way to know that two of its ranges share a pattern, so renaming
`_a` to anything without the underscore produces a file that does not
parse.

`024.260` recorded `LocalVariableTargetNode` for the first time in
0.2.17, which is what made those two ranges reachable. 0.2.17 declines
an underscore-prefixed target rather than emitting the pair — the
state before `024.260` for exactly those names, so no user loses an
answer they had — and what that leaves is a partial rename: the
binding is not rewritten and the reads are.

```
Driven, rbs-4.2.0/lib/rbs/prototype/helpers.rb, caret on `_rest` at line 50:

  BASE 98fc14e            1 edit  (line 50)              — partial
  without this decline    2 edits (lines 34 and 50)      — complete
  shipped                 1 edit  (line 50)              — partial, as BASE

Over the Ruby 3.4.10 stdlib, 976 files, the decline costs 202 positions and
every one of them is an underscore-prefixed target; nothing else changes.
```

**The rule is blunter than Ruby's**, which keys on the name *and* on
the name being bound twice by one pattern. Writing it precisely means
a per-pattern set of repeated names, carried across
`InNode`/`MatchRequiredNode`/`MatchPredicateNode` — three visits that
must agree and one more piece of state. Measured against what that
buys: over 23,091 corpus renames the blunt rule costs **one** local
the precise one would have kept. So the blunt one is written, and this
entry is where the precise one is recorded for whoever finds the cost
higher than that.

Pinned as `parser_scope_frames_spec.rb`'s "declines an
underscore-prefixed target, which a pattern may repeat", "declines an
underscore-prefixed multiple-assignment target" — the reach of the
rule, so it is not inferred from prose — and "still records a target a
pattern may not repeat" as the control.

**Fixed in 0.3.0.** The decline is scoped to patterns, which is the
only place Ruby permits the repeat -- a multiple assignment, a `for`
variable and a `rescue => _e` cannot produce the illegal pair, and
declining them cost documentHighlight and Find References an
occurrence apiece. The parser tracks pattern depth and declines an
underscore target only inside one.

## 024.275 A workspace-identity example fails only in a full-suite run, and not reproducibly

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets that is known. It is filed because the example
  guards a user-visible invariant -- that the root is the one the editor
  named -- and an assertion that fails sometimes is either a defect in
  the product or a defect in the test, and neither is acceptable
  unexamined.
target: 0.3.2
```

**Area:** `core/spec/ovallsp/server_workspace_identity_spec.rb`,
`core/lib/ovallsp/server.rb` (`#client_workspace_root`)

`takes the first workspace folder when the client sends no rootUri`, and
its neighbour `keeps its own cwd when the named root does not exist`,
failed in a full-suite run during 0.2.17. What is known, all measured:

- Three consecutive full runs gave **2 failures, then 1, then 0**, in
  declining step with the number of other agents running suites on the
  same machine.
- **The same seed is not deterministic**: `--seed 48603` gave one failure
  and then, re-run, none. So it is not example ordering.
- The file alone passes: six runs, and six more while four other suites
  were deliberately loading the machine.
- Pairing it with the neighbours most likely to leak — the cache specs,
  the cold-index spec, the observation directory, the cache-sweep spec —
  passes every time.

**One hypothesis was tested and refuted**, and it is worth recording
because it is the one this repository's own history points at. If a
`Cache::Store` prune ever aimed outside its cache root it could delete
another process's `Dir.mktmpdir` — the `/Applications` incident's shape,
with the tmpdir parent shared by every agent on the machine. Driven:
`remove_within` refuses any path not strictly inside the expanded cache
root, and `prune_generations_of` is aimed by `File.dirname(current)` with
`root` passed separately rather than derived. The containment holds.

**What has not been established** is the value the assertion actually
saw. Both runs that captured the message were the runs that passed, so
the `got` side is unknown, and the two obvious readings —
`File.directory?` answering false for a symlink whose target still
exists, and the root simply never being adopted — have not been told
apart.

Filed rather than guessed at. The next full-suite run that reproduces it
should capture the failure message before anything else; that one line
decides whether this is the product or the test.

**Not reproduced in 0.2.17, and not fixed.** Three full-suite runs during this release — 2,791, 2,794 and 2,799 examples — came back with zero failures in this file, on a machine running nothing else. That is consistent with the load hypothesis the entry already records and is not evidence of anything on its own: the same file passed twelve times during the original investigation too.

Moved to the patch line rather than left naming a release that is being cut, because there is nothing here to do until it fails again. The instruction stands and is the whole of the work: **the next full-suite run that reproduces it captures the failure message before anything else.** That one line decides whether this is the product or the test, and it has never been captured.

### A second example of the same shape, 0.2.18

`spec/ovallsp/observation/collector_spec.rb`'s "lets an object given a
singleton method inside an observed run be collected" failed once in a
full-suite preflight and passed three times out of three when run alone.

It is a **GC** example — it asserts an object becomes collectable — so
the obvious hypothesis is different from the workspace-identity one:
the longer the suite, the more live objects a `GC.start` has to work
through, and a test that asserts collection has happened by a given
point is measuring the collector's schedule rather than the code.

Recorded here rather than as its own entry because what this entry is
about is the *class*: an example that fails only in a full run and not
reproducibly. Two of them now, in unrelated subsystems, which is itself
the argument that the cause is the run and not either subject.

**Still nothing captured.** Neither instance has had its failure message
read at the moment it failed. That remains the whole of the work.
### 0.2.18: the instruction is now the assertion, not a sentence

**What this entry has been waiting on is one line of output, and it
asked for it in a way that could not fire.** "The next full-suite run
that reproduces it captures the failure message before anything else"
addresses whoever happens to be watching. Nobody was, twice, across two
releases — and *both* runs that recorded a message were runs that
passed, so the `got` side has still never been seen.

So the capture is built into the assertion.
`spec/support/workspace_identity_report.rb` is attached to **all five**
root assertions in that file, not only the two that have failed, and a
reproduction now records itself:

```
workspace root is not the one the editor named.
expected="…/link"
got="…/real"
load=3.02
  real: …/real exists=true directory=true symlink=false
  link: …/link exists=true directory=true symlink=true -> …/real
```

That tells the entry's two readings apart in one line each:
`File.directory?` answering false for a symlink whose target still
exists shows as `symlink=true exists=false dangling`, and a root never
adopted shows as `got=` the cwd with `link` intact. The load figure is
there because the load hypothesis is the only one both halves of this
entry share. `server_identity_report_spec.rb` pins what the report
says, so it cannot quietly stop naming one of them.

**Verified by forcing it**: `client_workspace_root` was made to decline
every path in a scratch copy, and the report above is what came out.

### And the fabricated absolute path is gone

`keeps its own cwd when the named root does not exist` named
`file:///nonexistent-<pid>` — a path at the filesystem root chosen to
be obviously fake, which is the shape `CLAUDE.md`'s `/Applications`
rule is about. Nothing here deletes, so it was never that incident's
hazard. What it was is an assertion whose verdict depended on the state
of the machine's root directory, in a file whose failures came and went
with how many other processes were running. The absent root is now
inside the example's own tmpdir; the guard is still pinned (removing
`File.directory?` still fails it).

### The GC pair, same entry, different hypothesis

The two `collector_spec.rb` examples recorded above now re-collect and
re-measure up to ten times rather than asserting on the first count.
Their hypothesis is specific — they assert an object *has been*
collected by a given point, which measures the collector's schedule as
much as the code.

**It cannot weaken them**, which is what made it allowed: pre-fix the
delta is `CHURN_COUNT` *permanently*, so no number of further
collections moves it. Confirmed by reintroducing the retention in a
scratch copy — the example still fails, `expected: < 2`.

**Still open**, and now for a reason it can discharge: nothing here
claims to have found the cause. What changed is that the next
reproduction will say what it was, without anyone having to be present.
**Target moved to `unscheduled`, which is what it has always been.**
It said 0.2.18, and there is nothing here anyone can schedule: the
work is to read a failure message, and the failure has occurred twice
in some sixty full-suite runs. Naming a release for it makes a
commitment nobody can keep and pushes it forward one release at a
time, which is how it reached 0.2.18 from 0.2.16.

What changed in 0.2.18 is that the trigger no longer needs a person.
When it fires, the message arrives with it, and the entry becomes
ordinary work in whatever release that is.



**Retargeted to 0.3.2.** An assertion that fails sometimes is either a defect in the product or a defect in the test, and leaving it unscheduled is how it stays neither. 0.3.0 attached a self-recording report to the assertion, so the next reproduction carries the value nobody has seen; 0.3.2 is when that evidence is read, and if it has still not fired the entry is a candidate for closure as unreproducible rather than for another wait.

**Closed in 0.3.2 as unreproducible, which is what this entry asked
for.** 0.2.18 attached a self-recording report to the assertion
precisely so the next reproduction would carry the value nobody had
seen, and set 0.3.2 as when that evidence gets read. It has not fired:
**27 CI runs since the report landed, 3 of them failures, none of them
this.** Nor has any local run in this release, including several full
suites and the two real-Rails suites run concurrently.

The report stays where it is. Closing this is not a claim that the
behaviour is correct — it is a refusal to keep an entry open on
evidence that has had three releases to arrive and has not. If it fires
once, the line it prints is the entry, and it will be a better one than
this.

**The file moved underneath it in 0.3.2**, which is worth saying rather
than leaving for someone to notice: four examples there dispatched
`initialize` without joining the cold-index thread, and the `around`
block removed the cache tmpdir underneath it. That is a *different*
failure — `Errno::ENOTEMPTY` at teardown, not a wrong workspace root —
found by the Ruby 4.0 job and fixed. Whether it was ever a contributor
to this one cannot be established now, and pretending otherwise would
be inventing the reproduction this entry never got.

## 024.276 A closing pass retargeted 54 entries at 0.3.0, and 53 of them give one of two pasted reasons

```yaml
status: fixed
target: 0.2.17
released-in: 0.2.17
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. It is filed because it is the record
  defect that decides which user-visible defects get worked on: 35 open
  user-visible entries name a release that two scope documents say is
  not taking them, so nothing schedules them at all.
```

**Fixed in 0.2.17**, both halves of the Direction.

**All 54 re-triaged**, each with a reason of its own taken from its own body rather than from a template. The triage rule is `docs/PUBLISHING.md`'s own table: a wrong answer is a repair and belongs on the patch line, a silence turned into an answer is capability and belongs in a minor, and something about this repository's own checks or record is neither and belongs on the patch line. 25 moved to 0.2.18; 27 kept 0.3.0 on an argument of their own -- for `024.76`, `024.83` and `024.106` that argument really is the enumeration question, which is what `045` records as D2.

Driving them found what the pasted paragraphs had hidden. **`024.163` had been fixed before 0.2.15 shipped** and was carried open through two releases under a sentence saying it still reproduced. **`024.20` carries its own Direction one paragraph above** the sentence claiming it needs to know what gems define. **`024.267`, re-driven while closing it, turned out to be wrong when written** -- the check it says nothing does has existed since 0.2.3 and fired during this release.

**The countermeasure** is `DeferredFindings.repeated_paragraphs`, read by `deferred_findings_spec`. It groups open entries by verbatim paragraph and fails on any shared by three or more. The threshold is read off the distribution rather than picked: at the revision it was written, 570 paragraphs of 120 characters or more appeared in exactly one open entry and four appeared in two, then nothing until 6, 13, 21 and 40. Three sits in the gap.

It cannot tell a true reason from a false one and does not try. What it can see is that forty entries gave the same one, which was available and unread. Five examples distinguish it -- a shared paragraph in three entries is reported, in two is not, the metadata block is not read (twenty-one entries share a `user-visible-note` legitimately), a resolved entry does not count, and a repeated line under the length floor does not.

The sixth group it found was honest shared provenance: six entries repeating the same sentence about the measurement that surfaced them. That is what the Direction says to do with one -- write it once and cite it -- so they now carry a one-line pointer to `051` instead.

What this does not do is make a reason true. A release that moves 25 entries to 0.2.19 can still give each a distinct sentence that says nothing. What it removes is the cheapest way to do it, and the one that happened.

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (the
`target:` field and the closing paragraph on the entries counted below),
`docs/design/tasks/051-0.2.16-shipped.md` ("What is left of 0.2.x"),
`docs/design/tasks/045-0.3.0-scope.md` (the 0.2.14 amendment)

**54 open entries say they were retargeted to 0.3.0 in 0.2.16's closing
pass, and 53 of them justify it with one of exactly two paragraphs,
byte-identical within each group.** Counted by grouping every open
entry's closing paragraph and reading off the group sizes; the two
groups are 40 and 13, and the remaining one is `024.243`.

Each paragraph asserts something about how the entry was verified, and
each is pasted onto entries the assertion cannot be true of.

**The group of 40** says the entry was driven during the backlog sweep
*with a control in its own fixture* and still reproduces. Among the 40:
`024.150` (one operating document paraphrases another and the paraphrase
drifts), `024.154` (findings truncated mid-sentence in `046`), `024.163`
(a header in `046` asserts something about how its reviewers worked),
`024.190` (annotated tag messages are a channel no scan reads),
`024.196` (a measurement that justifies reading per-example status).
None of those has a fixture, and none can have a control. Seven of the
40 have an Area entirely under `docs/`, where a fixture is not a thing
that exists; the others above are in `AGENTS.md`, in this register, and
in `scripts/`.

**The group of 13** says the fix needs the enumeration question answered
— what the gems define, or what a running application responds to —
which is `024.R7`'s work. Three of the 13, checked one at a time:

- **`024.20`** — `contains?` treats an exclusive end offset as
  inclusive. Its own **Direction**, written in 0.2.15 one paragraph
  above, is "make `contains?` exclusive, then fix each caller that
  passes a range end", and the reason it gives for deferring is blast
  radius plus section 0's ranking: what remains "is a decline, not a
  wrong answer". Offset arithmetic on the user's own buffer. The entry
  now carries two contradictory reasons for its target and the false one
  is the one a reader reaches last.
- **`024.121`** — Area `scripts/check_pinned_mutations.rb`,
  `scripts/hunk_sweep.rb`. How much of *this tree* no test would notice
  changing.
- **`024.151`** — Area `core/spec/meta/pinned_mutations.yml`,
  `scripts/check_pinned_mutations.rb`. A check can be disabled and no
  check notices.

Three were enough to establish the class; the other ten are part of the
re-triage below rather than a separate claim.

### What it cost

`045`'s 0.2.14 amendment says 0.3.0 "is now **capability-only**" and
that the open defects aimed at it "are the accuracy line's". `051`'s
closing section says "What is left of 0.2.x: **Nothing.**" Both are read
off a register that says the opposite: **64 open entries name 0.3.0, 35
of them user-visible.** `ruby scripts/deferred_findings.rb --targeting
0.3.0` prints them.

So the accuracy backlog was not cleared by the patch line and was not
absorbed by a release either. It was relabelled, and both scope
documents then reported the label. A release `045` requires to add
capability only is on the hook for 35 user-visible defects — the state
`docs/PUBLISHING.md`'s minor-release condition exists to make
unreachable, reached from the other side: by moving the target rather
than by leaving it blank.

### The class

**A mass retarget is a mass promotion.** `CLAUDE.md` already says
promoting a finding is making a claim and requires the reproduction be
re-run against the tree being promoted into; applied to nine entries in
0.2.14 that rule caught two errors in nine — one that did not reproduce
at all and one stated backwards. Applied to fifty-four here, it was
replaced by two paragraphs pasted forty and thirteen times.

Nothing in the tree can tell a reason written for an entry from a reason
pasted onto it. That is what makes this cheap to do and invisible
afterwards, and it is the same shape as `024.151`: the rule is correct,
its reachability is not defended.

**Direction:** two halves, and the second is the countermeasure.

1. Re-triage all 54 against this tree — drive the reproduction, write
   one reason per entry, and let the target follow the reason rather
   than the reverse. An entry whose real blocker is `024.R7` keeps
   0.3.0 and says so in its own words.
2. A check that fails when open entries repeat a closing paragraph
   verbatim. It cannot judge whether a reason is true, but "forty
   entries give the same one" is one grouping, and it was the signal
   available and unread here. It has to count an entry that *describes*
   the duplication as one entry, not as another instance — which is why
   this one describes the two paragraphs rather than quoting them.
### 0.2.18: marked fixed with one of its own three files untouched

**This entry's Area names three files. Two were edited in 0.2.17 and
`051` was not**, so the sentence this entry disproved — that every
entry naming 0.2.16 was "retargeted with a reason each, from the
release's own measurements" — stood in `051` for two more releases, in
a summary table row and again in its "What is left of 0.2.x" section.

Confirmed rather than assumed: `git log` shows `051` last touched by
`7bce3c4`, the commit that created it, while the register and `045`
both moved afterwards.

Corrected in both places, with what was actually counted, and pinned by
`core/spec/meta/record_corrections_spec.rb` — the file this entry's own
re-triage created, for exactly this ("a record defect fixed by editing
a document leaves nothing behind that would fail if it came back").

**The shape worth keeping.** A `status: fixed` is a claim about every
place the entry's Area names, and nothing checked that the Area had
been walked. This is the same defect as the one the entry records,
one level up: the 0.2.17 pass verified the *entries* and not its own
*file list*. Found in 0.2.18 by asking whether the 0.2.x line was
genuinely closed, which is the only reason it was looked for at all.

**Reopened rather than left fixed**, because what is unpaid is not the
correction — that is done — but the check: nothing today reads an
entry's Area and asks whether those files changed when it was closed.
`024.190` already records annotated tag messages as a channel no scan
reads; this is the same class in the register itself.

**Closed in 0.3.0's sweep, as a record correction rather than a
change.** The body has opened with "Fixed in 0.2.17, both halves of the
Direction" since that release, while `status:` stayed `open` and
`target:` stayed 0.3.0 -- so the entry was one of the 39 counted
against a release whose work it does not need.

Verified before closing rather than taken from the sentence:
`DeferredFindings.repeated_paragraphs` exists, five examples
distinguish what it does and does not report, and one more runs it
over **the live register** and fails on any paragraph three open
entries share. That last is the guard the entry asked for; the other
five are what stop it from being satisfied by a checker that cannot
see anything.

## 024.277 A local variable's identity follows the cref, so a block that changes `self` splits it

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/parser_service.rb`

**A local variable has no owner.** Ruby's locals are lexical, and a
block that changes `self` does not change which variable a name is:

```
$ ruby -e '
module Mod; end
def m
  ks = [1]
  Mod.module_eval do
    ks << 2
  end
  ks
end
p m
'
# => [1, 2]
# ruby 3.4.10
```

`#record_reference` took every candidate's owner from `@cref` at the
point of *use*, and `#visit_block_node` gives an `instance_eval`,
`instance_exec`, `class_eval`, `class_exec`, `module_eval` or
`module_exec` block the receiver as its owner -- correctly, for the
macros those blocks contain. Identity is `owner#scope_id`, so the `ks`
inside came out `::Mod#2` while the same variable outside was `nil#2`.
Rename rewrote the outer occurrences and left the inner one, which then
names nothing: the file the editor hands back calls a method that does
not exist.

**Found by the rename oracle, in the release that shipped the oracle,
and only by enumerating what it reported.** The release record said the
residual meaning-changing renames were all `024.273` and `024.274`.
Listed rather than asserted, some were neither -- `activerecord`'s
`store.rb`, whose `keys` is closed over inside a `module_eval do` block,
is the clean instance and is fixed here. Two others in
`activesupport`'s `redis_cache_store.rb` turned out to be the oracle's
own defect rather than the product's (`024.279`), which only appeared
because they were investigated one at a time instead of being counted
and characterised in a batch.

**This is `024.271`'s cause in its general form.** That entry moved the
`def` receiver's walk above the cref switch, which fixed the one
instance. The rule is that the owner belongs to the frame that *binds*
the name, so `Scope` carries the cref owner captured when the frame was
pushed and `#record_local_variable` reads it from there. One rule covers
the `def` receiver, the six `*_eval` spellings, and a superclass
expression -- `parser_scope_frames_spec.rb` had an example asserting the
last of those was *still broken*, whose comment said only moving the
walk could fix it and called that "a wider change than this one, with
its own corpus to drive". That was the wrong diagnosis; nothing had to
move.

`024.271`'s skip of the already-visited receiver is kept and re-pinned:
the duplicate it prevents is no longer a second *identity*, but it is
still two identical edits in one WorkspaceEdit and one occurrence
counted twice by Find References. Measured -- without the skip that
position appears twice.

Pinned by six examples, one per `*_eval` spelling, plus two controls: a
macro inside such a block is still recorded against the block's own
owner, and two same-named locals in different methods are still apart.
One mutation entry -- blanking `owner: frame.owner` at the call site.

**A second mutation was written for `Scope#owner` itself and removed,
because nothing distinguishes it.** Blanking the field left every
example green, and asking why is what led to `024.278`: within one file
the frame id is already unique, so once the *file* is in the identity
the owner adds nothing to it.

**So the simplification was attempted, and measured, and rolled back.**
Dropping the field and building a local's identity from the file and the
frame alone is genuinely fewer places that must agree, and it makes this
defect unrepresentable rather than corrected. What it broke is
`parser_scope_frames_spec.rb`'s `identity` helper, which reads the
*candidate*'s owner -- 7 examples. Repairing that means either teaching
the helper to go through the resolver, or restating `#resolve_local`'s
rule inside the spec, and the second is a new place that must agree in
the layer whose job is to catch places that disagree. `048`'s result
stands: measured, the simplification did not reduce the number this
project counts. The field stays, redundant and correct, and this
paragraph is why -- so the next reader who notices it does not spend the
same afternoon.

## 024.278 A local variable's identity has no file in it, so renaming one edits another file

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.17
```

**Area:** `core/lib/ovallsp/semantic/reference_resolver.rb`

`#resolve_local` builds a synthetic owner of `"#{owner}##{scope_id}"`.
**Scope ids are counted per file**, so two files whose counters and cref
owner agree share one identity -- and a local variable never spans
files.

A top-level `def` has no owner at all, so any two files written that way
collide on their first method's locals. A class reopened across two
files collides on `::Widget#<n>`, which is ordinary Rails.

Driven through the real server at `279e7e5` -- the 0.2.17 tag commit --
with `a.rb` holding `def m; ks = 1; ks; end` and `b.rb` holding
`def n; ks = 2; ks; end`, renaming `ks` in `a.rb`:

```
file:///a.rb: 2 edit(s)
file:///b.rb: 2 edit(s)      <-- a file the user never opened
```

**This is a worse failure than the nine shapes 0.2.17 fixed.** Those
left one file wrong. This one writes edits into a second file, and Find
References over-answers in the same way for the same reason.

Found while pinning `024.277`: a mutation that blanked the frame owner
was *not* caught by the example claiming to distinguish two same-named
locals, because within one file the scope id already separates them.
Asking what the owner was actually for is what surfaced that it was
carrying the file, badly.

**Fixed** by putting the `uri` -- already a parameter of that method,
for the location -- into the identity. Only this kind is qualified: a
method rename must still cross files, and a control example asserts it
does.

## 024.279 The rename oracle put the caret in the wrong place, so its first numbers were part measurement

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. Recorded because the numbers it produced were
  published in a changelog, a release record and two register entries
  before the defect was found, which is the failure `CLAUDE.md`'s
  "a measurement is a claim" section exists to prevent.
released-in: 0.2.17
```

**Area:** `scripts/rename_oracle.rb`

`#line_and_character` sliced the source by **characters** up to Prism's
`start_offset`, which is a **byte** offset. Any multi-byte character
earlier in the file moved the caret, and the server then answered about
whatever symbol it landed on.

Driven, `activesupport`'s `redis_cache_store.rb`: the caret meant for
`values` at line 356 column 10 was placed at column 26, which is inside
`failsafe`. The run recorded ten edits renaming a *method* as a failed
local rename, and the file was reported twice in the residual as a
product defect it does not have.

**What it cost.** The numbers `6 / 704` and `0 / 74` were published in
`vscode/CHANGELOG.md` and `.ja.md`, in `052`, and in `024.277`'s first
draft, and were part measurement and part this. Re-measured with the
caret corrected, on the identical corpus of 1,043 files and 3,123
renames:

```
                       v0.2.16              0.2.17
  unparseable                6                   0
  meaning-changed          711                  58
    binding behind         471                  57
    occurrences behind     240                   1
  refused                    0                   0
```

`refused` was 33 on both sides before the correction and is 0 after: a
misplaced caret often lands where nothing is renameable, and the oracle
counted that as the product declining.

**Fixed** by taking the line and the byte column from Prism directly --
it provides both -- and converting the column to UTF-16 units per line,
which is the protocol's rule and the same conversion
`Index::SourceLocation.to_position` makes. Reading the caret back out of
the engine's own recorded range was rejected: it would make the measure
depend on the thing measured.

**The general lesson is the one already written down and not followed.**
`CLAUDE.md` says to print the thing you are asserting rather than
assuming it. The oracle printed totals and a truncated list of forty
details. Nothing printed a caret next to the line it was supposed to be
on, and one line of that would have shown this immediately.

## 024.280 Renaming a local bound by a regexp named capture leaves the capture, silently

```yaml
status: fixed
kind: defect
user-visible: yes
released-in: 0.2.18
```

**Fixed in 0.2.18 by recording the name's own range**, which is the
second of the two candidate directions this entry names.

`024.260`'s decline was right about what it declined: Prism gives the
`LocalVariableTargetNode` the range of the *whole regexp literal*, and
rewriting that destroys the pattern. What it could not do was leave the
uses recorded and the binding not — that is the half-rename this entry
is, and it fails silently.

The name is written literally inside the pattern, so its own range is
computable. `#visit_match_write_node` finds `(?<name>` or `(?'name'` in
the regexp's own source and records *that*. Both of Ruby's spellings are
handled; an interpolated pattern, or a name the scan cannot find, stays
declined — which is where this started, and is a decline rather than a
wrong answer.

**Prism does not always hand back the literal**, which the first attempt
did not know: `/(?<n>x)/o` — with a flag — gives the target the name's
own range and was already recorded. Recording it again here is a
duplicate, so a target whose range already is the name is skipped.
`parser_scope_frames_spec`'s "records each named capture exactly once,
whichever way Prism gives it" is the control, and it is what caught it.

**Measured.** The rename oracle over 1,043 files of activesupport,
activerecord, actionpack, railties and i18n: meaning-changing renames
**58 -> 57**, `unparseable` 0 on both sides, and the residual is now a
single shape — **all 57 are `024.273`**, a binding whose declaration is a
parameter. The one case that was neither that nor `024.274` is gone.

**What it still cannot see** is a `Regexp.last_match[:where]` written
elsewhere: that is a string, the same blind spot `send` has, and the
same one every other rename lives with. Refusing instead would have kept
that safe and left the silent half-rename in place, which section 0
ranks lower.

**Area:** `core/lib/ovallsp/parser_service.rb`

A named capture in a regexp used with `=~` binds a local:

```
$ ruby -e '
/(?<where>\d+)/ =~ "a12"
p where
p defined?(where)
'
# => "12"
# => "local-variable"
# ruby 3.4.10
```

`024.260` records that this binding is **declined** -- 25 of 610,104
local-variable node visits over 9,160 files -- because Prism gives the
read's range as the whole regexp literal rather than as the name. The
decline is right on its own terms: rewriting the literal's whole range
would destroy the regexp.

What was never recorded is the consequence at the other end. The
*binding* is not recorded and the *uses* are, so renaming from a use
rewrites the uses and leaves the capture behind. It is the last of the
58 residual meaning-changing renames that is not `024.273`, in
`activerecord`'s `sqlite3/schema_statements.rb`:

```
                   /...(?<where>.+).../ =~ index_sql     LEFT
  line 30          where = where.sub(...) if where       EDITED
  line 50          where: where,                         EDITED
```

**And it fails silently rather than loudly**, which is why it is filed
rather than left inside `024.260`'s notes. Line 30 assigns before it
reads, so the renamed name is a defined-but-nil local: `if zzz` is
false, the `sub` never runs, and line 50 passes `nil` where a string was
expected. Nothing raises.

**Direction.** Two candidates, and the choice is not obvious, which is
why this is an entry. **Refuse**: a use whose binding could not be
recorded should not be renameable at all -- section 0.4 ranks a decline
above a wrong answer -- but the resolver has no way today to know a
binding was declined, so this needs the decline to be recorded rather
than dropped. **Record the capture's own range**: the name appears
literally inside the regexp source, so its sub-range is computable, and
renaming it is what Ruby needs. That one is complete rather than safe:
it changes the regexp, and anything reading the match by `[:where]`
elsewhere is a string this rename cannot see.

Not attempted here. `024.277` and `024.278` are two parser changes in
this change set already, and `CLAUDE.md`'s review cadence says a third
belongs in its own round rather than bolted onto this one.

## 024.281 The `.erb` integration test asserted an answer the engine correctly declines

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. The product was right and the test was wrong, so
  no shipped behaviour changes -- but it held the extension's only
  end-to-end ERB check red for a week, which is why it is recorded.
released-in: 0.2.17
```

**Area:** `vscode/src/test/integration/erb.spec.ts`,
`vscode/test-fixtures/sample-workspace/view.html.erb`

The test opened `view.html.erb`, whose whole content was
`<h1><%= @title %></h1>`, and polled `vscode.executeHoverProvider` at
**position (0, 0)** for ten seconds. Position (0, 0) is the `<` of an
HTML tag. The only Ruby in the file is `@title`, an ivar nothing in the
fixture workspace assigns.

So the assertion could not pass unless the engine asserted something it
does not know, at a position that is not Ruby. **That is the shape
section 0 ranks worst, written into a test as the pass condition.** It
is the twin of `CLAUDE.md`'s "an assertion that cannot fail is not a
test": this one could not *pass* without the product being wrong.

**Driven before rewriting it**, because "the test is wrong" is a claim
about the product and needed checking. Through the real Core:

```
  <% name = "x" %>
  <h1><%= name.upcase %></h1>

  hover on `name` (the use)      -> String
  hover on `name` (the binding)  -> String
  hover on `upcase`              -> upcase() -> String
  hover on `@title` (old fixture)-> nil
  hover on `<`     (old position)-> nil
```

`.erb` reaches the Core and answers; the fixture was the only thing in
the way. The fixture now binds a local and the test asks about it, and
asserts the answer *contains* `String` rather than merely being
non-empty — without that it is satisfied by any hover from any provider.

Found while wiring `024.125`. Both integration variants now report
6 passing, 0 failing, against the source Core and the packaged layout.

## 024.282 CI was red on `main` for a week and nothing in the tree said so

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets directly. Recorded because the gate that decides
  whether the product is fit to ship was failing while release work
  continued on top of it, and no local check could see that.
released-in: 0.2.17
```

**Area:** `.github/workflows/ci.yml`, `scripts/preflight.rb`

`gh run list --branch main` at `cf97c72e`:

```
  33263014821  cf97c72e  failure  2026-08-29
  33241282125  7bce3c4f  failure  2026-08-29
  33240634626  9f5d97a6  failure  2026-08-29
  32688579193  bdd0ebeb  failure  2026-08-24
  32686673234  ab893c1d  failure  2026-08-24
  32557978897  57e98da2  success  2026-08-22
```

Five consecutive red runs across six days. `Core Server (Ruby 3.4)`
reported `2653 examples, 6 failures` — all in `spec/meta`: three in
`doc_links_spec`, one in `measured_claims_spec`, two in
`interpreter_sessions_spec`. `VS Code extension (integration, real
editor)` was red from 2026-08-24 on `024.281`.

**Why no local run could see it.** `scripts/preflight.rb` runs the Ruby
suites and the tree checks. It does not run anything under `vscode/`, so
a local "all 9 checks passed" says nothing about the extension — which
is precisely the state this session was in while `024.281` was failing
on every push. The Ruby-side failures are the other half: they are
`spec/meta` examples that read the *tree*, and several are sensitive to
what a CI checkout contains, so a green local run does not predict them.

**Not fixed here, and the reason is which fix.** The cheap move is to add
`vscode` to preflight, and that is the wrong shape: preflight would then
need a VS Code download and a display, so the gate most often run by
hand becomes the slowest one. The question worth answering is how a
session learns CI is red without being told — a `gh run list` line in
preflight's output costs nothing and needs network, or the release
record grows a row. That is a decision about the working loop rather
than a hunk, and `CLAUDE.md`'s review cadence says an addition mid-loop
is a finding to record.

The six Ruby failures were at `cf97c72e`; this tree is seven commits
further on and green locally on all of them. **Whether they are fixed or
merely invisible here is unknown until something is pushed**, and that
is the entry's own reproduction step.


**Answered by pushing, which is what the entry said its reproduction
was.** The eight commits went to `main` and the run at `6ee8c878` came
back with `VS Code extension (integration, real editor)` **green** —
`024.281`'s repair and `024.125`'s new packaged step both pass in CI —
and `Core Server` still red at `2815 examples, 7 failures`.

So the Ruby-side failures were not fixed by those commits and were never
visible locally. **All seven have one cause**, and the checks diagnosed
it themselves:

```
  home_path_guard_spec:286   "only 0 tag(s) came back with a body. Either the
                              format string stopped reading `%(contents)`, or
                              this clone was fetched without tags"
  doc_links_spec (x3)        "check-doc-links: this is a shallow clone; a
                              citation census over part of a tree is not a census."
  measured_claims_spec:262   the same tree census
  interpreter_sessions_spec  found no sessions to run
```

The `core` job checked out with `fetch-tags: true` and the default
`fetch-depth: 1`. That brings the tag *refs* without their objects, so
`%(contents)` was empty for all 28 of them — and a scan that reads
nothing is clean, which is why only the "there are some to read" example
could catch it. **The comment above that line already said the claim was
not to be trusted on its own; the claim was wrong and the example it
pointed at is what found out.**

Fixed with `fetch-depth: 0`. The seven examples are the same ones this
entry lists at `cf97c72e`, plus `home_path_guard_spec` — which was
*added* by 0.2.17 and started failing immediately, on a job that had
been red for a week, so nothing distinguished the new failure from the
old ones.

**What stays open is the other half**, and it is now its own entry:
`preflight` runs nothing under `vscode/` and cannot see a red CI, which
is the state this session worked in for a day. `024.284`.

## 024.283 The packaged Core is driven only on Linux, so the macOS build is still smoke-tested

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: yes
target: 0.3.2
```

**Area:** `.github/workflows/ci.yml`

The residue of `024.125`. That entry is closed because the packaged
*layout* — the Core inside the extension, runtime gems vendored — is now
driven through a full editor session on every push. The runner is
`ubuntu-latest`, so what is driven has **Linux** native extensions.

The VSIX that is published is `darwin-arm64`, and its native extensions
are still exercised only by `vsix_semantic_smoke.rb` at publish time and
by hand. `023.5` was specifically a darwin-arm64 packaging and update
regression, so this is the half of `024.125`'s risk that survives its
fix, not a hypothetical.

Published in `KNOWN_LIMITATIONS` in both languages, which is what
`024.125`'s paragraph became rather than being deleted: the section it
had was correct about a gap and wrong about which one.

**Direction.** A macOS runner for the packaged integration job is the
obvious answer and is not free — `macos-latest` minutes are billed at a
multiple of Linux, and this job downloads VS Code and vendors gems. It
is also entangled with `024.R4`, which is about publishing more than one
platform at all: if a second target is ever published, this job has to
run per target rather than once, and deciding that first avoids building
the one-target version twice. Targeted at 0.3.0 for that reason rather
than because the risk is small.


**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Driving the
packaged Core on the platform it is published for is a gap against
what `024.125` already claimed.

**Fixed in 0.3.2.** A `macos-packaged` job runs `copy-core` on an Apple Silicon runner -- compiling prism and rbs for darwin-arm64, which is the thing that was never built in CI -- checks `PLATFORM_MANIFEST.json` says so rather than trusting the runner, and drives the result through `vsix_semantic_smoke.rb`, the publish gate's own test. The manifest check is what stops a green run that vendored Linux from looking identical to one that did the job. Driven locally before being written: the smoke test refused a relative path, because `require_relative` resolves against the script rather than the caller, so it now expands the argument -- `release.sh` always passed an absolute one and nothing else had ever called it.

## 024.284 Nothing local can see that CI is red, and preflight does not run the extension

```yaml
status: fixed
released-in: 0.2.18
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. Recorded because it is the reason `024.281` and
  `024.282` survived a week: every local signal said the tree was fine.
```

**Area:** `scripts/preflight.rb`

Two gaps, one consequence.

**`preflight` runs nothing under `vscode/`.** Its nine checks are the
Ruby suites and the tree checks. So "all 9 checks passed" is a statement
about the Core and says nothing about the extension — and `024.281` was
failing the extension's only end-to-end ERB check on every push while
this session ran preflight to green eight times.

**And nothing local reads CI at all.** `024.282`'s seven failures were
invisible here by construction: they are `spec/meta` examples that refuse
a partial tree, and a local clone is never partial. A green local run
cannot predict them and never could.

**Direction, and why neither obvious fix is taken here.** Adding
`vscode` to preflight needs a VS Code download and a display, which makes
the most-run gate the slowest — and the packaged variant additionally
vendors gems, so it is minutes, not seconds. Adding a `gh run list` line
needs network and fails differently offline. The cheap honest form is
probably a check that *reports* rather than gates: one line of
`gh run list --branch main --limit 1` output at the end of preflight,
skipped without network, so a session learns the state of the gate
without waiting on it. That is a decision about the working loop and
belongs in its own change set.
### Fixed in 0.2.18: it reports, and it cannot gate

`scripts/ci_status.rb` prints one line saying what CI last said about
the current branch, and preflight runs it **after** its verdict, on
both the passing and the failing path.

```
ci: main success -- https://github.com/<owner>/<repo>/actions/runs/<id>
ci: cannot tell -- `gh` is not installed (see CONTRIBUTING.md)
```

It **exits 0 in every case**, including the ones it cannot answer,
because neither "no network" nor "no `gh`" says anything about the
tree. That is what makes it safe at the front of every commit, and it
is why it is not a tenth `Check`: a check that needs the network would
turn an offline commit into a failing one.

**This covers both gaps, and it covers the second one better than
running the extension locally would.** CI runs `vscode/`'s suites and
the packaged Core, so a red extension check is now visible from here —
without a VS Code download, a display, or the minutes of vendoring the
packaged variant needs. And the `spec/meta` examples that refuse a
partial tree are *only* observable through CI, because a local clone is
never partial: nothing run locally could ever have caught `024.282`.

**Three defects on the way in, each caught by something this repository
already had:**

- The first run raised `Encoding::InvalidByteSequenceError` out of
  `JSON.parse` — a pipe arrives as US-ASCII, and the first non-ASCII
  byte in a run title escaped a `rescue JSON::ParserError`, which is
  the too-narrow-rescue shape. Fixed at the layer that owns it:
  `scripts/utf8.rb`, which a meta example requires of every script.
- It spawned `git` directly, so an inherited `GIT_DIR` would have aimed
  it at another repository. Now through `RepoFiles.capture`.
- The paragraph in `AGENTS.md` explaining `024.150`'s markers spelled
  one the way a real one is spelled, and that file's own new scanner
  read it as a marker — in the commit that wrote the scanner. Exactly
  "writing a check means writing bait for the other checks", found by
  the check rather than by a reviewer.

It also reports when the newest run is not HEAD's commit, because
"success" about a commit you have since amended is the misreading this
entry exists to prevent.


## 024.285 Three interpreter sessions resolved against whatever the machine had installed

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. Recorded because the checker built in 0.2.17 to
  stop a claim about Ruby going unchecked was itself resolving against
  an undeclared gem, which is the same defect one layer up.
released-in: 0.2.17
```

**Area:** `core/ovallsp.gemspec`, `scripts/check_interpreter_sessions.rb`

Three sessions ask Ruby about `delegate` and `ActiveSupport::Concern`,
so they open with `gem "activesupport"`. The checker runs each session
with `BUNDLE_*` cleared — deliberately, because **a session is a claim
about Ruby, not about this bundle**, and `024.220` records a session
behaving differently inside one.

Cleared of the bundle, `gem "activesupport"` resolved against whatever
the machine happened to have installed. On this maintainer's machine
that is Rails 8.1.3.1, so all three passed. On a CI runner `GEM_PATH` is
the vendored bundle and nothing else, and activesupport was not in it:

```
  Could not find 'activesupport' (>= 0) among 69 total gem(s)
  Checked in 'GEM_PATH=/home/runner/work/OvalLSP/OvalLSP/core/vendor/bundle/ruby/3.4.0'
```

The checker reported **four wrong answers that were really four
absences** — three sessions plus one more in this register — and the
`--count` example failed with it.

**This is the defect the checker exists to prevent, one layer up.**
`024.220` built it because a claim about Ruby's semantics can go stale
or be mis-transcribed and read exactly like a correct one. A session
that runs only where an undeclared gem happens to be installed is the
same thing: it reads as checked, everywhere, while being checked in one
place.

**Fixed by declaring it** — `activesupport` is a development dependency
of `core` now, so it is in the bundle both environments read, and the
sessions run where they are asked to run rather than where the gems
happen to be. Clearing `BUNDLE_*` stays: it is what makes a session a
claim about Ruby, and the gem being *declared* is what makes that claim
answerable.

Found by pushing, on the run after `024.282`'s `fetch-depth` fix took
the same job from seven failures to two.

## 024.286 A session recorded on one Ruby was compared against another, so the 3.3 job called true answers wrong

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. Recorded because it kept a gating CI job red on
  code that was correct, which is the kind of red that teaches people to
  ignore CI.
released-in: 0.2.17
```

**Area:** `scripts/check_interpreter_sessions.rb`

Every session in this tree carries a note saying which interpreter
answered — `# ruby 3.4.10`. The checker read that note only to *drop* it
from the expected output, and then compared the recording against
whatever interpreter it was running on.

**Ruby's own output moves between minor versions.** The CI matrix runs
3.3, 3.4 and 4.0:

```
  3.4   p({name: "n"})   =>  {name: "n"}
  3.3   p({name: "n"})   =>  {:name=>"n"}

  3.4   backtrace: -e:3:in 'Somewhere::User#go': ... (NameError)
  3.3   backtrace: -e:3:in `go': ... (NameError)
```

So the 3.3 job reported sessions as not reproducing when they reproduce
exactly on the interpreter they were taken from. Two true answers, one
called wrong.

**The note is the condition, and it was being read as decoration.** A
session records what *one* interpreter said; comparing it elsewhere is
comparing different things. The checker now declines where the recorded
minor version differs, and **counts and prints the declines** —
`other-version=N` — because a decline this script does not name reads
exactly like a pass, which is the failure the script exists to prevent.

A session with no note carries no condition and is compared on every
interpreter. That is the right default: with no note it claims to be
about Ruby rather than about one Ruby, and if it turns out to be
version-sensitive, the right repair is to record which Ruby answered.

Minor-version granularity, not patch: 3.4.10's recording is still
checked on 3.4.12.

Pinned by a pair in `interpreter_sessions_spec.rb`, and neither example
means anything alone — a foreign-version recording with a wrong answer
must be declined, and a same-version one with a wrong answer must still
fail. Without the second, "decline everything" passes.

Found by pushing, on the third CI run of the day: `024.282`'s
`fetch-depth` took the job from seven failures to two, `024.285`'s
declared gem took 3.4 to green, and this is what was left holding 3.3.

## 024.287 The informational Ruby 4.0 job reported five checkout failures and one real difference

```yaml
status: fixed
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. Recorded because an informational job whose
  output is mostly noise is one nobody reads, which costs exactly the
  signal it exists to carry.
released-in: 0.2.18
```

**Area:** `.github/workflows/ci.yml`

`024.282` gave the gating `core` job `fetch-depth: 0` and did not give it
to `core-ruby-4`. So that job went on reporting the same five
shallow-clone refusals — three from `doc_links_spec`, one from
`measured_claims_spec`, one from `home_path_guard_spec` — alongside its
**one** real 4.0 difference (`024.288`).

An informational job exists to carry a signal nobody is required to act
on. Five sixths noise is how that signal stops being read, and this job's
own comment says what it is for: "that row used to end 'nothing
continuously verifies 4.0', and it was right."

Fixed by giving it the same checkout as the gating job.

## 024.288 Ruby 4.0 puts a fourth name on Object that RBS does not declare

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: yes
target: 0.3.2
```

**Area:** `core/lib/ovallsp/signatures/environment.rb`

`024.239` records that the signature set's `::Object` omits names the
running Ruby gives every object, and that each omission became a false
`unknown-method` report against the user's own class. Three were found
on Ruby 3.4 — `trap`, `set_trace_func`, `iterator?` — and
`UNIVERSAL_RUBY_NAMES` names them.

`object_signature_gap_spec` re-derives that list rather than trusting it,
"because a written list is exactly the thing that goes stale on the next
Ruby or the next RBS". **It went stale, and the spec said so**, on the
informational 4.0 job:

```
  expected: ["iterator?", "set_trace_func", "trap"]
       got: ["instance_variables_to_inspect", "iterator?", "set_trace_func", "trap"]
```

So on Ruby 4.0 a call to `instance_variables_to_inspect` on the user's
own class is reported missing, exactly as `trap` was before `024.239`.

**Recorded rather than fixed, which is this job's standing decision**:
`docs/SUPPORT_MATRIX.md` calls 4.0 best effort, and ci.yml says in as
many words that "a 4.0-specific failure gets recorded rather than fixed
— a required job would turn the first one into work nobody agreed to
do."

**And the one-line fix is the wrong one.** Adding the name
unconditionally would make the engine decline on it under 3.3 and 3.4,
where Ruby does not define it — so a genuine typo of that name goes
silent on every currently supported Ruby. That is `024.13`'s failure,
which cost four real typo reports for exactly this kind of proxy.

**Direction.** The list is hand-derived and pinned by a spec that
re-derives it; the shape that does not go stale is to derive it at load
from the running interpreter minus the signature set, which is what the
spec already does in a subprocess. Cost is startup time on every boot
against a list that changes once per Ruby release, so it is a real
trade rather than an obvious win — hence an entry.


**Cannot be driven here.** This is a Ruby 4.0 fact and 0.3.0's
measurements were taken on `ruby 3.4.10`, where
`object_signature_gap_spec` re-derives `UNIVERSAL_RUBY_NAMES` and
agrees with it. The entry is about what the informational 4.0 job
reports, and nothing in this session could reach that. Left open
with its target unchanged rather than re-triaged on a run that did
not happen.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A repair, and one
that cannot be driven until this project runs on Ruby 4.0 -- the
patch line is where it waits.

**Scheduled for 0.3.2, and that is a change of decision rather than a
reading of the old one.** The standing decision this entry cites is
`ci.yml`'s, and it is scoped in its own words to "the 0.2.x line". That
line closed with 0.2.18. Nothing replaced it, so between 0.3.0 and this
paragraph the 4.0 job had no policy at all -- it reported a failure that
no release owed and no rule excused.

The argument for naming a release rather than restoring "record, not
fix": a decision with no end date is indistinguishable from never doing
it. `024.239` is the same defect on Ruby 3.4 and it was fixed; leaving
the 4.0 instance open forever would make the two inconsistent for no
reason anyone could state.

**What it is not**: the 4.0 job stays `continue-on-error`. Naming a
release commits to fixing this one report, not to making 4.0 gate; the
reason a required job would be wrong is unchanged, and
`docs/SUPPORT_MATRIX.md` still calls 4.0 best effort.

**The shape of the fix, so 0.3.2 does not rediscover it.**
`UNIVERSAL_RUBY_NAMES` is a frozen three-element list and
`object_signature_gap_spec` re-derives it from the running interpreter
and core RBS. Adding `instance_variables_to_inspect` to the list makes
the 3.4 and 3.3 jobs fail, because their Ruby does not have that name
and the re-derivation would no longer match. So the fix is a list that
can differ per Ruby, not a fourth element -- and the spec that catches
this is the thing to keep, since it is what turned "a written list goes
stale on the next Ruby" from a prediction into a failing job.

**Fixed in 0.3.2.** The gap is keyed by the Ruby that moves it. Three rows, each measured: 3.3 and 3.4 re-derived on every suite run, 4.0 taken from the job that reported the difference. An unlisted Ruby gets the union, which errs towards silence because a missing name costs a false report on every class and a surplus one costs a single true report. Two new examples: every Ruby `ci.yml` names has a row, and the fallback is asked about a version nothing will ship.

## 024.291 A repeated key in a metadata block is resolved silently, and one of them discarded a withdrawal

```yaml
status: fixed
released-in: 0.2.18
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that the register's
  machine-readable view of an entry disagreed with the entry's own
  text about whether the defect was real, and every count derived
  from the register read the wrong one.
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md`,
`core/spec/meta/deferred_findings_spec.rb`

A metadata block is a `key: value` list, and `DeferredFindings` keeps
the **last** occurrence of a repeated key. Nothing said which was
meant, and no reader could tell it had happened.

**It was not harmless.** `024.153` carried `user-visible-note` twice.
The first said the entry had been **withdrawn** because it does not
reproduce; the second described the defect as live and published to
users. The parser kept the second — so every derived count, and every
check reading that field, saw a real defect that had been fixed, while
the entry's own text said it had been withdrawn. That is `024.130`'s
class arriving through the metadata rather than the prose, and
`024.130` is the entry about publishing a limitation the product does
not have.

`024.220` had `released-in` twice with the same value: idempotent, and
the same defect.

Merged so the withdrawal is what a reader and the parser both see, and
checked by an example in `deferred_findings_spec` that names the entry
and the key. Watched failing on both before the fix.

**How it was found, which is the part worth keeping.** Not by a
reviewer. 0.2.18 was published, and the question "is 0.2.x really
closed" was asked once more. A sweep for entries marked `fixed` whose
Area named files that never changed in the closing release produced
seven candidates — and **the sweep's premise was wrong**: an Area names
where a defect *lives*, and this repository fixes many by pinning
rather than by editing the named file, so `024.268` and `024.269`
correctly leave `agent_process_manager.rb` untouched. Narrowed to
entries whose Area is *documents only*, where a documentary correction
has nowhere else to land, it produced one — and that one
(`024.153`) was also a false positive, because `045` had been updated a
release earlier than the sweep assumed.

The duplicate key was seen while checking that false positive. The
sound narrowing found nothing; looking closely at what it did find
found this. Recorded because the useful move was **not trusting the
sweep's own hits**, which is the same discipline the measurement
section asks for.

## 024.292 `045` disagrees with its own table about what 0.3.0 is blocked on

```yaml
status: fixed
released-in: 0.3.0
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that the document deciding
  0.3.0's work order overstated by three what the release's largest
  item blocks, and understated by one what can proceed today.
```

**Area:** `docs/design/tasks/045-0.3.0-scope.md`

`045`'s dependency table is nine rows and is unambiguous:

- **two** rows name `024.R7` — unknown methods on gem-inheriting
  classes, and `Article.all.` completing;
- **five** say "the inference / the diagnostics / the reference index
  that already exists" — inlay hints, quick fixes, go to type
  definition, call hierarchy, highlight occurrences;
- one is `024.85` (shipped in 0.2.16) and one is `024.86`.

Its prose contradicts that in three places:

| where | said | the table says |
|---|---|---|
| opening paragraph | "**five of them wait on the same one**" | two do |
| "`024.R7` last" | "**five promises hang off it**" | two do |
| "Where to start" | "the **four** that need only what is already built", listing occurrences, call hierarchy, go-to-type-definition, inlay hints | five, and **quick fixes** is the one left out |

The first two look like the count of the *unblocked* rows with the
wrong predicate attached to it. Whatever produced them, the effect is
the same in both directions: a session reading the prose believes most
of 0.3.0 is gated behind the release's largest item, and does not know
quick fixes is available now.

**Found by counting the table against the sentence above it**, while
answering "what is left in 0.3.0" — not by a reviewer, and not by
reading the paragraph again. `046` is the release whose subject was
exactly this, and this is the same shape in the document that orders
the next one.

### Fixed in 0.3.0

All three corrected against the table, each saying what it used to say
rather than being quietly rewritten. The table was not touched: it is
the thing that turned out to be right.
## 024.293 `check_pinned_mutations.rb` reads a skipped example as a mutation that escaped

```yaml
status: fixed
released-in: 0.3.0
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user meets. What it cost is that the check built to say
  "this decision is pinned" said the opposite about four decisions
  that were pinned, in the one environment where nobody could see it
  was wrong.
```

**Area:** `scripts/check_pinned_mutations.rb`, `.github/workflows/ci.yml`

The checker applies a mutation, runs the one example that names it, and
reads `N examples, M failures` out of the output. **A skipped example
is still an example**: without its dependencies the capability suite
reports `1 example, 0 failures, 1 pending` and exits 0, which is
byte-for-byte what a mutation that escaped produces.

The `pinned-mutations` CI job installs no Rails and no sqlite3, so
0.3.0's four `documentHighlight` mutations — all of which pass locally
— came back as **"4 of 104 mutation(s) not caught"** on the first push
that had them.

This is `024.148`'s shape *inside the checker built for that class*:
a check that cannot see its subject reporting exactly what a working
check reports when nothing is pinned. `CLAUDE.md` states it in the
general form — "a checker that cannot see the thing it checks reports
exactly what a working checker reports when nothing is pinned" — and
the paragraph is about this very script's first run.

### Fixed in 0.3.0, in both halves

**The report** now reads the pending count and says which it is: *the
example did not run — N pending; that says nothing about the mutation,
it says this environment cannot verify it.* Verified by forcing every
example in the capability suite to skip and running the checker: it
names the four and refuses, rather than calling them unpinned.

**The job** now installs Rails and sqlite3, the same step the `core`
job already carries, so the answer is a verification rather than an
honest refusal.

Both halves, because either alone leaves something wrong: without the
first, the next suite that skips is misreported again; without the
second, four real decisions go unverified on CI.
## 024.296 Renaming a local a pattern also binds rewrites the rest and leaves the pattern

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: yes
target: 0.3.2
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`declined_underscore?`),
`core/lib/ovallsp/rename/planner.rb` (`binding_site_unknown?`)

A pattern's binding site is not recorded, and `024.273`'s refusal only
fires when *no* occurrence of the name is a write. An ordinary
assignment of the same name in the same scope defeats it, so the rename
goes ahead on the occurrences it can see and leaves the pattern:

    def m(pair)
      _a = 0
      case pair
      in [_a, 1]
        _a
      end
    end

Driven against the real server, with a non-underscore name bound the
same way as the control in the same fixture:

    rename `_a` from its read -> edits at [[1, 2], [4, 4]]
    rename `zz` from its read -> edits at [[6, 2], [8, 6], [9, 4]]

The control rewrites its pattern site at line 8; the subject leaves line
3 alone. What comes back parses, runs, and answers something else:

    $ ruby -e '
    def before(pair); _a = 0; case pair; in [_a, 1]; _a; end; end
    def after(pair);  bb = 0; case pair; in [_a, 1]; bb; end; end
    p before([5, 1])
    p after([5, 1])
    '
    # => 5
    # => 0
    # ruby 3.4.10

**The published limitation said the opposite until this entry.**
`KNOWN_LIMITATIONS` read "so none is made", which is true only for the
half where nothing else assigns the name -- there the rename is refused.
The half where it *does* edit is the one a user meets, and it was
described as the one that does not happen. That is `024.131`'s shape:
an entry understating its defect in the direction that argues for the
lower triage. Both languages now carry the shape that reproduces.

**Not the hash-pattern shorthand.** `in {a:}` is left behind for every
name, underscore or not, which is the recorded shorthand gap rather
than this. The control for that spelling does not behave, so it is not
counted here.

**Why 0.3.2 and not 0.4.0**: it is a wrong answer applied to the user's
file, which `docs/PUBLISHING.md`'s table puts on the patch line.

**Fixed in 0.3.2.** The parser records the *name* a pattern binds even where it declines the occurrence, `WorkspaceIndex` counts it per file exactly as it counts `open_surface_owners`, and `Rename::Planner` refuses on it -- the shape CLAUDE.md calls giving a guard the input it could not see. Taken from Ruby before anything was written: the same method answers 5 before the rename and 0 after it, so this was a working program rewritten into a different one. `FileSummary` gains a member, so `SCHEMA_VERSION` is 7; the golden pair moved with it, which is what that spec exists to force.

## 024.305 One name, six modules, and the index keeps the empty one

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >-
  Driven, and the observable consequence could not be established.
  Completion on a relation is 228 items as shipped against 227
  repaired -- a wash, 13 delegation names traded for 12 real ones --
  and no diagnostic changed either way. It is recorded because the
  state is one `gem_index.rb`'s own header says must never exist, and
  because `024.295` cannot write anything to disk while it does.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/runtime_agent/agent.rb` (`#each_named_module`),
`core/lib/ovallsp/semantic/gem_index.rb:52`

Rails' per-model relation classes override `.name` to return their
parent's, so after `eager_load!` **six Module objects report
`ActiveRecord::Relation`** — one real, five shadows
(`ApplicationRecord::ActiveRecord_Relation`, `User::…`, and so on).
`GemIndex#initialize` keys by name and the last writer wins, and the
copy that survives is a shadow with no methods of its own:

    ActiveRecord::Relation      knows=true  instance_methods=0  ancestors=23
    …::CollectionProxy          knows=true  instance_methods=0
    CONTROL ActiveRecord::Base  knows=true  instance_methods=116

So the index holds a class it says it knows the whole surface of, with
no surface — the one state that file's header says must not exist,
because a check built on "closed" then asserts something nobody
established. Four names are affected on this repository's fixture.

The collapse is guaranteed rather than incidental: one module reports
that name after boot and six after `eager_load!`, and
`RailsBootstrap#populate_registries` eager-loads before
`#ensure_gem_index` can fire.

**Two candidate fixes, and the obvious one is a wash.** Keeping the
copy with the largest method set trades 13 delegation names for 12
real ones. Keeping the module the constant actually resolves to
(`Object.const_get(name).equal?(mod)`) drops exactly the 20 shadows
and no legitimate class — measured, with `ActionController::Metal`
identical on both sides as the control. That is the better shape and
it is not free: `const_get` on a qualified name can trigger autoload
inside the Agent, which is a side effect the walk does not have today.
Establishing that it is harmless is the work, and it is why this is
not a patch.

**Fixed in 0.3.2.** The Agent keeps a module only where the name resolves back to it, so a class that overrides `.name` to answer its parent's no longer displaces the real one. Measured on this repository's fixture: 2,098 entries seen, 2,078 kept, 20 shadows dropped across 4 names, and `ActiveRecord::Relation` goes from an entry with **0** instance methods to one with 78, `CollectionProxy` from 0 to 185, with `ActiveRecord::Base` unchanged at 116 as the control. The autoload risk that kept this out of a patch was measured rather than argued: `const_get` over all 2,098 names after `eager_load!` loads **0** files. The alternative -- keep whichever copy has the most methods -- was measured a wash, 228 completion items against 227.

## 024.306 The 0.3.0 record states as measured that a `:method_call` candidate never resolves to a constant

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >-
  A record defect, not a product one. Nothing a user meets changes;
  what changes is what the next reader believes about the resolver
  before touching it, which is how a line gets deleted on a false
  premise.
target: 0.3.2
```

**Area:** `docs/design/tasks/054-0.3.0-the-first-release-that-adds.md`,
section "One of the four turned out to be dead, and was removed"

The record says a `:method_call` candidate "resolves to a method kind
or to nothing — never to a constant or a class", and removes a line on
that basis. `ReferenceResolver` also resolves such a candidate to
`:route_helper` and to an Active Record column, neither of which is a
method kind. The conclusion may still hold; what does not hold is the
premise as written, and the record presents it as measured.

**Fixed in 0.3.2.** The record said the line was removed; the code had put it back, and the guard is live against a route helper. Corrected in `054`, which is what the entry was about.

## 024.307 The capability suite's own fixtures cannot reach six shapes the release found

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  Coverage, so nothing is wrong until something else breaks. Recorded
  because the gap is in the file that decides whether a capability row
  may say PASS.
target: 0.3.2
```

**Area:** `core/spec/e2e/capabilities_spec.rb`, the "in the current
file" block and W5/W6

No example uses a namespaced constant, an instance variable, a route
helper, a symbol declared twice in one file, nested `def`s on one line,
or a `prepareCallHierarchy` issued at a call site rather than at a
`def`. Six of 0.3.0's review findings live in exactly those shapes, so
the suite that certifies the rows could not have found any of them.

**Fixed in 0.3.2.** Six examples, one per shape the entry names: an instance variable across methods, a namespaced constant against a same-named one in another namespace, a route helper whose every occurrence is a call, two same-named methods in one file, two `def`s on one line where line numbers cannot separate the bindings, and a call hierarchy prepared at a call site rather than at a `def`. Every one of them answers correctly today -- the gap was in what the suite could see, not in what the engine does.

## 024.308 `ReferenceResolver#resolve` states no contract about alignment

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  An unstated invariant that every caller currently happens to
  respect. It costs nothing today and costs a wrong answer the first
  time somebody indexes the result against the input.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/semantic/reference_resolver.rb:43-45`

`resolve` is a `filter_map`, so its result is shorter than its input
whenever a candidate declines — and nothing says so. Its pre-0.3.0
callers avoid the assumption by accident rather than by being told:
two pass a single-element array, one iterates. A caller that zips the
two lists would be wrong on the first declining candidate.

**Fixed in 0.3.2.** The contract is stated at `#resolve`, and pinned by an example that resolves two constants where one is declared and one is not. The control asserts both were candidates, so the shorter answer is the resolver declining rather than the parser finding one name.

## 024.309 The quick-fix E2E example asserts that the result parses, which both answers do

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  The behaviour it guards is correct; the guard is what is thin. A
  fixture that cannot tell the two candidate answers apart is the
  shape CLAUDE.md calls unpinned even while it passes.
target: 0.3.2
```

**Area:** `core/spec/e2e/capabilities_spec.rb`, Q1's "inserts into the
right body when the class's end is not the first one"

It drives three shapes and asserts `Prism.parse(applied).success?` for
each, with a `match_array` so no shape can be skipped. Both of those
are worth having. Neither distinguishes a `def` inserted inside the
class from one inserted after it: 0.3.0 found exactly that, by hand,
after this example had been passing on both placements.

**Fixed in 0.3.2.** The example asserts the `def` is inside the class it was called on, walked with Prism so a nested class does not count as the outer one. A second example is the judge's own control: same method, two placements, both parsing, and it has to tell them apart. Verified by mutating the insertion back to the pre-0.3.0 placement -- the strengthened example fails, and the old `Prism.parse` assertion would not have.

## 024.310 A range arity reads "takes 0..1 argument"

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: yes
target: 0.3.2
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb:695-698`

The plural follows `maximum` rather than the count being printed:
`"argument#{maximum == 1 ? '' : 's'}"`. For a range whose upper bound
is 1 the sentence comes out singular over a plural count — `def opt(a = 1)`
called with three arguments reports that it "takes 0..1 argument".

Worth one caution before fixing it: `Server#diagnostic_maximum` reads
the arity back out of this message with
`/takes (?:\d+\.\.)?(\d+)(?: positional)? argument/`. The pattern has
no word boundary, so the plural is safe to change — but two places
agree about one user-facing string and only one of them formats it.

**Fixed in 0.3.2.** `#expected_arity` asks whether the count is exactly one rather than whether the upper bound is, so a range is never singular. Four examples, three of them controls, and one of those pins the pattern `Server#diagnostic_maximum` reads the number back out with.

## 024.311 `ReferenceCandidate`'s comment omits a field four readers use

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  Documentation of an internal shape. It misleads whoever reads the
  comment instead of the producer, and 0.3.0 added the fourth reader
  without the comment gaining the field.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/index/reference_candidate.rb:48-52`

The comment gives the shape as `{ positional:, splat:, keywords:, block: }`.
`ParserService#call_argument_shape` also records `positional_locations:`,
which the argument-type check, inlay hints, the surplus-argument action
and `diagnostic_maximum` all read.

**Fixed in 0.3.2.** `positional_locations` is in the shape the comment gives, with its four readers named.

## 024.312 The release record has one direction of the ivar split and not the other

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >-
  Half a fix described as the whole of it. The product does both
  directions; a reader of the record would believe it does one, and
  would find the second half unexplained on the next visit.
target: 0.3.2
```

**Area:** `docs/design/tasks/054-0.3.0-the-first-release-that-adds.md:609`

The record explains that an `@x` written in `def self.build` used to be
offered inside instance methods. The change also runs the other way —
an ivar written in the class body is the class object's, and 0.3.1
found and fixed the depth test that decided it — and the record does
not say so.

**Fixed in 0.3.2.** `054` carries both directions of the ivar split now, and says which release found the second.

## 024.313 Four comment lines and a chain sit at the wrong indentation

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  Layout only. It is here because the file is one the parser's
  reviewers read closely, and mis-indentation there reads as a
  different block structure than the one that runs.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/parser_service.rb`,
`#record_assigned_struct_members`

The comment opening "`SymbolNode` only." starts at eight spaces with
its continuations at four, and the `names = ...` assignment with its
chained `select`/`filter_map` is indented to the enclosing block
rather than to the method.

**Fixed in 0.3.2.** The comment and the chained call sit at the method's indentation, the continuations aligned on the receiver.

## 024.314 A comment numbers a schema bump that was not made

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >-
  Nothing reaches a user. The hazard is the next bump: a numbered
  entry for a version that does not exist invites the following one to
  take the number after it, and the cache key would then skip a value.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/cache/key.rb`, above `SCHEMA_VERSION = 6`

The list above the constant carries an entry numbered 7, describing
`singletonAncestors` and closing "Left at 6 deliberately". Numbering a
note about a bump that did not happen, inside the list that records the
bumps that did, is the confusion that list exists to prevent.

**Fixed in 0.3.2.** The note about `singletonAncestors` is unnumbered, so the next real bump cannot take a number the list has already spent.

## 024.315 Inlay hints label block parameters, and no release note says so

```yaml
status: fixed
released-in: 0.3.2
kind: defect
user-visible: no
user-visible-note: >-
  The labels are correct, so a user meets a feature rather than a
  fault. It is filed because an undescribed behaviour cannot be
  reviewed against intent, and a capability nobody wrote down is one
  nobody can decide to remove.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/server.rb`, `#local_type_hints`

Parameter binding sites are recorded as writes, so
`[1, 2].each { |n| n }` renders as `[1, 2].each { |n: Integer| n }`.
Driving `def f(a)` and `def f(a = 1)` produced no wrong label, so this
is a description gap rather than a defect in the hint.

**Fixed in 0.3.2.** `054` records that a block parameter gets a label, and that it is a consequence of the `write` flag rather than a separate decision.

## 024.316 Two lines each drop a top-level call, and only both together are pinned

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  Redundancy inside one method. Neither line is wrong and the pair is
  pinned honestly; what is unresolved is which of the two should
  remain, and that is a call-hierarchy design question rather than a
  review finding.
target: 0.3.2
```

**Area:** `core/lib/ovallsp/server.rb`, `#incoming_calls_result`

Measured: mutating `next unless enclosing` alone leaves both W5
examples green, mutating the render's `or next` alone does too, and
mutating both fails them. `pinned_mutations.yml` names the containment
test the pair shares rather than claiming to pin a line.

**Fixed in 0.3.2.** Resolved by driving the premise rather than by choosing a line to delete: neither is redundant. `next unless enclosing` is what keeps `enclosing.symbol_id` from being asked of nil for a call at file scope, and the render's `or next` guards the indexing thread replacing a summary between the two passes -- `#incoming_calls_result` does not hold `@index_mutation_mutex` while `#apply_file_summary` writes under it. "Mutating either alone leaves the examples green" meant neither was reached, not that either was spare. The file-scope half has an example now, verified by mutating the guard away; the interleaving half is stated at the site as one no single-threaded example can reach.

## 024.317 Six of the documentation map's trigger rows have nothing enforcing them

```yaml
status: fixed
released-in: 0.3.2
kind: friction
user-visible: no
user-visible-note: >-
  A gap in the machinery rather than in the product. Its cost is
  measured though: of the eight rows that were unenforced before
  0.3.1, three had already drifted.
target: 0.3.2
```

**Area:** `docs/DOCUMENTATION_MAP.md`, the trigger table

Of twenty-one rows, six carry nothing in the "Checked by" column:
a change reverted mid-release, a review round finding the same place
twice, install steps and the extension id, anything about the Runtime
Agent or workspace trust, which Ruby and Rails the product accepts,
and thread and lock ownership.

0.3.1 closed two of the eight that were open — the protocol document
and release-branch pointers, both of which had drifted by the time a
check was written for them, and a third drift (a guard hunting a
retired branch spelling) was repaired in the same pass. That is three
of eight found the first time anybody looked, which is the argument
for closing the rest.

**Fixed in 0.3.2.** Three of the six closed, and the three that remain are named rather than left as a count. The extension id is compared against `vscode/package.json`, which is the only place it is true; SECURITY gets the parity check PRIVACY has had, on structure and the reporting route rather than on prose; and the Ruby patch releases named as tested must agree across both support matrices and both Marketplace READMEs -- a set the matrices had three of and the READMEs two for a whole release. What is left is two rows that ask for a judgement no scanner can make (whether a revert left documentation behind, whether a review round found the same place twice) and one that could be mechanised in the rescue-verdicts shape but is a release of its own: every `Mutex.new` in `core/lib` accounted for in the architecture document. `024.320` carries that.

## 024.R2 Argument *type* checking (done, 0.2.0)

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

as the narrow version this entry described: the expected type comes from an RBS/RBI declaration, the signature must have exactly one overload and no `*rest`, and both the declared and the inferred type must be concrete classes with no ancestor relation between them. Everything else stays silent.

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


## 024.R5 A reopened gem class still looks closed (done, 0.1.7)

```yaml
status: done
kind: roadmap
released-in: 0.1.7
```

Measured against the same real application that reported it: 2 diagnostics before, 0 after.

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

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

scoped to views, which is where the symptom the entry describes actually appears. A view is handed exactly what its controller action and callback chain assign, and that set was already computed for type propagation; everything else receives its ivars from wherever it likes, so nothing is reported there.

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

```yaml
status: done
kind: roadmap
released-in: 0.3.0
```

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
### 0.3.0: the Agent half is done, and the Core half is scoped by what it owes

**Done, and measured against this repository's own Rails fixture
rather than against this entry's estimate:**

| | this entry said | measured |
|---|---|---|
| gems | 63 | **33** |
| classes attributed | 2,204 | **2,098** |
| methods defined directly on them | 15,868 | **14,617** |
| payload | ~365 KB, names only | **938 KB** |
| classes defining `method_missing` | — | **17** |

The payload is 2.6x the estimate because ancestors are reported too and
`Object`'s chain repeats 2,098 times. Asked once per boot, never on the
request path, which is the decision that estimate was for.

- `agent/gemIndex` walks every loaded module and attributes each to the
  gem whose directory `Object.const_source_location` puts it in — **by
  definition site, not by namespace**, so a class the application
  reopens is still the gem's.
- `Semantic::GemIndex` holds it Core-side. **A class defining
  `method_missing` is never `knows?`**, whatever the index holds: it
  answers to names no enumeration can list.
- The Server asks once when an Agent becomes ready and reports the size
  through `ovallsp/status`, which is what an E2E example asserts
  against real Rails.
- Protocol version 1 → 2.

**Nothing reads it to decide an answer yet, and that is deliberate.**

### What the Core half owes, precisely

Making a gem class *closed* without also giving the engine that class's
methods turns every correct call on a gem into a report. So four
things move together or none of them do:

1. `HierarchyIndex` must continue an ancestor chain **into** gem
   classes. Today it is built from the workspace, so
   `ActiveRecord::Base` has no entry and the chain stops.
2. `MethodResolver#candidates_for_type` must offer the gem's methods,
   or a closed receiver becomes a report factory.
3. `#accounted_for?` and `#declares_method_missing?` must consult the
   index — those two are one-line changes and are the *only* part that
   looks small.
4. Persistence per gem-version in the cache store, so a single bumped
   gem re-indexes one gem and not thirty-three.

**And the measurement it owes does not exist.** `045` requires a corpus
run with a control for any change that alters what the engine asserts,
and `scripts/corpus_diagnostics.rb` has no Agent path at all — grep it
for `agent` and the answer is nothing. This change turns silence into
reports across every file of every Rails application, which is the
largest assertion change this product has ever made, and the tool that
would measure it has to be built first.

`024.18` remains a required part of this and is untouched.

**Not started rather than half-built**, deliberately: a capability that
answers *sometimes* is a wrong answer where it does not, and this one
answers about the code every Rails developer writes.
### Done in 0.3.0, and the measurement refused two versions of it first

"Closed" now means "we know its full method set". `Semantic::GemIndex`
is what the running application reported; `HierarchyIndex` continues a
chain into it; `MethodResolver` answers the gem's own methods, and
`#accounted_for?`, `#declares_method_missing?` and
`Engine#locally_accounted_for?` all read it.

**Measured, activerecord's own 397 files, index off then on, same
`corpus-sha256`, control `unresolved-constant` identical at 1,609:**

| version | `unknown-method` | introduced | removed |
|---|---|---|---|
| baseline, no index | 96 | — | — |
| spliced in `MethodResolver` | 130 | **47, all false** | 13 |
| rooted, modules included | 891 | **795, all false** | 13 |
| **shipped** | **83** | **0** | **13** |

The two rejected versions are the point of the entry.

**The splice was in the wrong class.** Rooting a chain needs three
things `HierarchyIndex` owns and a splice elsewhere skips:
`DEFAULT_OBJECT_CHAIN`, whose `Kernel` is a **module** and which the
splice called a class; the singleton tail, without which `.new` is not
on the chain; and `dedupe_named`. `Foo.new` and `raise` were reported
as missing.

**Modules must not be rooted.** A `ClassMethods`-style module's `self`
at call time is whatever class extended it, which nothing here knows.
With modules rooted, activerecord reported `superclass`, `name` and
`primary_key` on its own modules — 795 false reports, all correct code.

### `ActiveRecord::Base` can never be closed, and that is right

Asked of the running application:

```
$ bundle exec ruby -e 'require "./config/environment"
p ActiveRecord::Base.private_method_defined?(:method_missing)'
# => true
```

`ActiveRecord::AttributeMethods` defines it, so a model answers to
names no enumeration can list. **The roadmap's promise cannot be kept
for the headline case**, and keeping it would be a wrong answer. 577
of this bundle's classes have no such ancestor and are checked; the
capability rows say both halves, and `G18`'s second example is the
model staying silent.

### The last link was the Agent's evidence defeating the Agent's index

With everything above in place the capability was still off: the chain
was rooted, the receiver closed, and then `#reopened_elsewhere?`
deferred — because a gem ancestor is neither workspace code nor
declared by RBS, which is `024.R5`'s deferral doing its job against
information that had since arrived. `#locally_accounted_for?` reads
the index now, and that is a third way a name is accounted for and the
strongest of the three.

### What is not done

**Persistence per gem-version.** The index is fetched once per boot and
held in memory; the cache store is untouched. A cold start pays the
walk again. That is a cost, not a wrong answer.

**`024.18` is untouched** and remains a required part of this.

### And the measurement now exists

`scripts/corpus_diagnostics.rb --rails-root=DIR` boots a Runtime Agent
and analyses with the index it reports, printing `gem-index-classes` in
its provenance so a diff whose two sides disagree about that number is
visibly measuring the flag rather than the change.

## 024.R8 Completion does nothing until you type a dot (done, 0.2.0)

```yaml
status: done
kind: roadmap
released-in: 0.2.0
```

The entry's own reading was right: the work was mostly ranking and bounding, not calling the existing pieces. The order it proposed is the order that shipped (locals, methods on self, workspace constants, Kernel), with two decisions it left open settled as it suggested — a hard cap with `isIncomplete`, and a one-character prefix that returns only the two sources near the cursor.

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


## 024.R9 This register outgrew its file, and 0.3.0 moves it

```yaml
status: done
released-in: 0.3.0
kind: roadmap
target: 0.3.0
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md`,
`core/spec/meta/deferred_findings_spec.rb`,
`docs/DOCUMENTATION_MAP.md`, `CLAUDE.md`

This file runs to thousands of lines across dozens of entries — `wc -l`
and `grep -c '^## 024\.'` give the current figures; the precise count
this sentence once carried went stale within the release that imported
it — and it lives in
`docs/design/tasks/` — a directory of per-task implementation notes,
numbered by the task that produced them. Everything else in there is a
record of one finished piece of work. This one is a live register that
every release appends to, and it is the only document in the repository
that is never done.

The consequence is that an entry is *recorded* and still not *found*. A
finding lands in the middle of a document nobody reads front to back,
under a number whose only advertisement is the `<!-- documents: -->`
marker in `KNOWN_LIMITATIONS` and whatever source comments happen to cite
it. The legend's "one place" rule is still right; the file it names is no
longer the right place for it.

**What the move must preserve** — each of these is currently load-bearing,
and a move that drops one is worse than no move:

- **The numbers.** Source and spec comments cite `024.N` as the only
  route to the reason a piece of code is the way it is; the legend
  already forbids deleting a resolved entry while such a citation
  survives. So this is a move plus an index, never a renumber. Entries
  keep the `024.` prefix precisely because it is quoted in the tree.
- **The `yaml` grammar and its guard.** `deferred_findings_spec.rb` reads
  those blocks, and 024.25 records what happened the last time this data
  was parsed as prose. The guard gets re-aimed at the new location; it
  does not get relaxed for the duration of the move.
- **The `<!-- documents: 024.N -->` anchors in both languages**, and the
  same-count rule behind them.
- **One place to look.** The reason for the rule, as distinct from the
  file it currently names. A split by *state* (open defects / roadmap /
  resolved-but-still-cited) keeps that; a split by release or by
  subsystem does not, because a reader with a number in hand would have
  to know which file it went to.

**Proposed shape:** a dedicated register at the top of `docs/`, not under
`design/tasks/`, with this file reduced to a stub pointing at it, a row
added to `DOCUMENTATION_MAP.md`, and the guard spec re-pointed.

**What a move breaks: measure it with a grep at the revision that
moves it, not from this paragraph.** The count here was wrong on
arrival — this entry said "nineteen files" over an itemized list of
eighteen, and the unified 0.2.3's merge round re-counted and got a
different membership besides (`docs/ROADMAP.md` + `.ja.md` cite the
relative link rather than the full path; sibling task files cite the
full path; `AGENTS.md` cites the bare filename and goes stale on a
move too). The shape of the blast radius, which is what matters:

- `CLAUDE.md` — the rollback rule names this path as where a rolled-back
  thread's root cause is written. That rule stops being followable the
  moment the path is a stub.
- the READMEs, `docs/PUBLISHING.md`, `docs/ROADMAP.md`,
  `docs/KNOWN_LIMITATIONS.md`, `docs/DOCUMENTATION_MAP.md` and their
  `.ja.md` pairs, both changelogs, the roadmap site pages, sibling
  task files.
- `core/spec/meta/deferred_findings_spec.rb`, and two source files
  (`runtime/ancestry_registry.rb`, `runtime_agent/agent.rb`).

The stub is what makes this survivable rather than a flag-day across
every citing file: the path keeps resolving, and the citations are
corrected as they are next touched. The exceptions are `CLAUDE.md` and the guard spec,
which must move with the file — a working agreement pointing at a
forwarding address is not a working agreement.

**Why this is not in `docs/ROADMAP.md`.** That document and README's
matrix describe what a user can do; this changes nothing a user can
observe. A row there would misdescribe the release, and
`roadmap_parity_spec.rb` requires README and the roadmap to agree row for
row, so it would also have to be invented in a second place. An internal
reorganisation belongs in the register, which is where this entry is.

This makes it the first `024.R*` entry with no roadmap row: R1, R3, R4
and R7 — every other open one — are cited from `docs/ROADMAP.md`. The
absence here is deliberate, not an omission, which is why the paragraph
above exists rather than a silent gap. `DOCUMENTATION_MAP.md`'s roadmap
row reads in one direction only — a *product* roadmap item needs a
matching `R` entry — and nothing requires the reverse.

**When:** 0.3.0, and before the entries it will hold are written rather
than after. Doing it inside a review loop is what `CLAUDE.md`'s "during a
review loop, fix; do not add" exists to prevent — the move touches a
guard spec, and a change set that grows a guard mid-loop resets the round
that was reviewing it.

---
### Done in 0.3.0: split by state, and the path did not move

| | before | after |
|---|---|---|
| live register | 20,703 lines | **5,033** |
| entries in it | 287 | 48 open |
| archive | — | 15,696 lines, 239 resolved |

**The shape is the alternative this entry offered, not its "proposed
shape", and the numbers chose it.** The proposal was a move to the top
of `docs/`; 26 tracked files name the register by path, and every one
would have had to change to buy a shorter string. Measured instead: 239
of 287 entries were resolved — 15,670 lines, **75.7%** — so the file
every session reads, and every scripted edit risks, was three-quarters
archive. Splitting that out is what this entry's own complaint was
about; moving it is not. The move stays available and is recorded here
as not taken.

**What it had to preserve, and how each is held:**

- **The numbers.** Unchanged; 278 files cite one and none was touched.
  A move plus an index, never a renumber, exactly as this entry says.
- **The `yaml` grammar and its guard.** `DeferredFindings.register` is
  the only place that knows there are two files, and every function in
  that module already took markdown — so each check reads one register
  and needed no change of its own.
- **One place to look.** The generated index lives in the live file and
  carries **all 287**, with a resolved entry's row linking across.
  `register_split_spec` fails if an archived number has no row.
- **The `documents:` anchors.** Unchanged, and the citation check now
  resolves against both.

**Three checks caught the split before the suite did, which is the part
worth keeping.** Each was reading the live file directly:

- `measured_claims_spec`'s `register-entries` deriver said **48** where
  the tree has 287;
- its citation check reported **every citation of a resolved entry** as
  a dangling pointer, `.github/workflows/ci.yml` first;
- `deferred_findings_spec`'s index check compared the index against the
  live file's own headings.

That last one then failed a second time for a different reason, and it
was the check being wrong rather than the split: it compared **ordered**
lists, which was right while the register was one file kept in numeric
order and is not across two, where the combined order is
state-then-number. It is compared by entry key now, and the live file's
numeric order and index currency are still asserted byte-for-byte by
`is in numeric order with its index current`. The archive's own order
had nothing asserting it and now does.

