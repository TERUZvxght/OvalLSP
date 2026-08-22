# 042 — The second enumeration: where the decision is made

The maintainer asked for this exercise a second time, after `024.102`'s
stocktake. The first one produced eight classes and eight mechanisms; the
stocktake re-ran twenty of the entries those classes claimed and found
**C1 discharged 0 of 5, C2 1 of 9, C3 0 of 3**. The mechanisms are built.
The instances are not gone.

So this is not a repeat. It changes two things about how the exercise is
done, and both changes come from a specific way the first one failed.

## What went wrong the first time, precisely

**A class was defined by what its entries looked like, not by where the
wrong decision was made.** `024.26` and `024.32` sat under C1, "the
parser decides an owner from six parallel stacks". `024.26`'s decision is
made in `HierarchyIndex`, which has no parser state to read; `024.32`'s
is made by a Prism node-class test on a receiver. C1 could have been
built perfectly and neither would have moved — and it was, and neither
did. Two of five entries were never within reach of the mechanism that
claimed them, and nothing in the exercise could have revealed that,
because the exercise never asked "where is this decided?".

**And a class was treated as discharged when its mechanism shipped.**
That is the sentence `036` carried for two releases: 0.2.8 and 0.2.10
"carry" these entries. Carrying is not fixing, and the register recorded
the first as though it were the second.

## The two rules this exercise runs under

1. **A class is a place where a decision is made, not a shape a symptom
   takes.** Every entry is assigned by naming the function that produces
   the wrong value. An entry whose function is not inside the class's
   mechanism does not belong to the class, however similar it looks.
2. **A class is discharged when its entries stop reproducing, measured
   — never when its mechanism ships.** Each class below carries an
   acceptance test that is a reproduction, and the class stays open until
   every entry under it fails to reproduce. This is the rule `024.102`
   lacked.

A third, from the same stocktake: **a mechanism that collects state
without collecting the question does nothing.** `Index::Cref` replaced
six flags with one value and the parser still reads `declares_singleton?`
at seven sites and `defines_surface?` at one, so a recorder can still ask
the wrong one of nine predicates. Collecting the storage is not
collecting the question. Where a class below proposes a value, it also
says which accessors must *not* exist.

---

## D1 — Resolution answers a name where it must answer a name and its basis

**Entries:** `024.13`, `024.19`, `024.35`, `024.37`, `024.40`, `024.47`,
`024.82`, `024.84`

**Where the decision is made:** `WorkspaceIndex#resolve_type_name` and
`#resolve_type_symbol_locked`, which return a `String` or `nil`.

Every one of these is a consumer treating a guess as certain. The index
answers "which class is this name" by exact match, then by namespace
suffix, then by whichever candidate sorts first — and hands back a name
with no trace of which rule produced it. `024.19` judges an argument
against a class the receiver is not; `024.47` loses a namespaced class's
diagnostics to a same-named core class; `024.13` reads a reopened core
class as closed. `Engine#receiver_type_for` already refuses
`guessed_type_name?`, which is the shape of the answer — applied at one
call site, by a predicate that has to be remembered.

**The logic under which none of these could arise:** resolution returns a
value, not a name. `Resolution(name:, basis:)` where `basis` is one of
`:written_and_declared`, `:nesting`, `:ancestor`, `:sole_bare_candidate`,
`:none`. There is no accessor that yields the name without the basis, so
a caller that asserts about the user's code cannot spend a
`:sole_bare_candidate` without writing that it is doing so.

**Acceptance:** `024.19`'s `Widget.make(1)` with one workspace `Widget`
produces no `argument-type`; `024.47`'s namespaced class keeps its
diagnostics; `024.13`'s reopened `String` still answers `squish`; and a
corpus run shows the `unresolved-constant` control unmoved.

**Why not already done:** 0.2.1 moved a *shadowing test* into resolution
and broke every bare name written from inside its own namespace
(`024.47`). This is the opposite move — resolution says less, not more,
and refusal stays with the caller who knows what it is for.

---

## D2 — An enumeration's completeness is not carried by the enumeration

**Entries:** `024.18`, `024.22`, `024.27`, `024.28`, `024.76`, `024.77`,
`024.83`, `024.91`, `024.106`, `024.110`, `024.116`

**Where the decision is made:** `WorkspaceIndex#method_symbol_ids` and
`#open_surface?`, and `Server#assigned_ivars_for` — each returns a
collection whose emptiness means both "nothing there" and "I could not
look".

This is C2's axis, and the stocktake showed C2 built it for *ancestors*
only: `MethodResolver#unenumerable_reason` walks the chain, so a chain
that is fully accounted for yields `absent` however much of the class's
own body the parser could not read. Every survivor is that — a `Struct`
accessor, an alias target, an RBS gap, a macro. `024.110` is the sharpest
case: the engine reports the macro *and* declines to report what it might
define, two answers about one fact, and 0.2.11's attempt to fix it
silenced `Foo.bar` across the whole workspace because `Module`'s open
surface is on every class's chain.

**The logic under which none of these could arise:** the per-owner member
set is produced *with* its completeness, by the recorder that knows.
`ParserService` knows it met a call it could not read, and for which
owner; the RBS loader knows it had no signature. `MemberSet(names:,
complete:, incomplete_because:)`, and `absent` is a thing only a
`complete: true` set can answer. Then `024.110` is not a policy question
at all: the macro's owner is incomplete, so nothing is asserted about it,
and `Module` being incomplete says nothing about `Widget` because the
completeness is per-owner rather than per-chain.

**Re-derived in 0.2.13, against the rule this document sets for itself.**
D2 claimed eleven entries. Two are discharged by its mechanism —
`024.110` and `024.116` — and **five of the remaining nine are not this
class**, which is the miscategorisation 042 exists to catch *before*
building rather than after:

| entry | where its decision is actually made |
|---|---|
| `024.18`, `024.22` | the unassigned-ivar check needs a *different source of knowledge* — the entry's own Direction is "ask the Runtime Agent". Carrying completeness on a set this engine cannot compute at all is not the same problem |
| `024.27`, `024.28` | `selectionRange` and `name_location` on a generated declaration. An outline that lists one node per name, and a rename with nothing to edit. Nothing to do with an enumeration's completeness |
| `024.77` | a receiver's *type* after a relation hop, which is D3's axis |

**Four are genuinely D2 and are not done:** `024.76`, `024.83`, `024.91`
and `024.106`'s second half. What they share is that the completeness
proof has to come from a layer *above* the parser — the index knowing it
has seen every file that reopens a module, the RBS loader knowing its
signature set is short. 0.2.13 built the parser's half, which is what
`024.110` and `024.116` needed; the other half is a real piece of work
and it is what D2 still names.

**Acceptance:** the four-line `class Module; alias_method …` reproduction
in `unreadable_macro_spec.rb` keeps `Widget.tpyo_class` reported while
`HostC`'s own macro is not; `024.91`'s Struct/Data/alias shapes stop
reporting; a 16-gem corpus shows constant-receiver findings unchanged and
`unknown-method` down.

---

## D3 — The four features compute their input by four routes

**Entries:** `024.42`, `024.43`, `024.44`, `024.63`, `024.85`, `024.86`,
`024.87`, `024.88`, `024.89`, `024.99`, `024.100`

**Where the decision is made:** `Server#hover` (≈1896), `Server#completion`
(≈3076) and `Server#publish_diagnostics` (≈554) each build the receiver
type for a position their own way, and `QueryService#members_of` /
`#signatures_of` never call `MethodResolver#availability` at all.

This is C2's **unbuilt half**. The stocktake located it exactly: hover
and completion pass `initial_env: ivars_for_view(uri)`; the diagnostics
path passes a set of *names*; and `initial_env` appears nowhere in
`engine.rb`. So `024.100`'s headline — a view's block parameter answers
`Post` to hover and `Unknown` to the check — is not a bug in either
feature. One query per position was built as one query about a *type*.

**The logic under which none of these could arise:** one
`ReceiverResolver#at(document:, position:)` returning a `Receiver` value,
and the features receive a `Receiver` they have no constructor for. The
visibility field `024.99` needs lives on it, because "can this be called
from here" is a property of the position, which is what the resolver has
and the type does not.

**Acceptance:** `024.100`'s four bullets, driven through the real server,
answer identically across hover, completion, definition and diagnostics;
`024.88`'s `x = cond ? "s" : 1` stops offering `upcase`; `024.99`'s
"69 of 121 labels not callable" falls to zero.

---

## D4 — A chain entry cannot express what it is

**Entries:** `024.26`, `024.80`, `024.81`

**Where the decision is made:**
`Semantic::HierarchyIndex::AncestorEntry`, which is
`Data.define(:name, :kind, :origin, :location)` — a *type* name, with no
way to say "the singleton class of that type", and `nil` for "an ancestor
I could not identify", which is also the owner a top-level `def` is
indexed under.

`024.26` is a workspace `def Object.foo`, reachable from every class in
Ruby and from none here, because `DEFAULT_CLASS_SINGLETON_CHAIN` starts
at `Class` — there is no `#<Class:Object>` to hang it on. `024.80` is the
`nil` collision, guarded at two call sites by hand.

**The logic under which none of these could arise:** the chain is a list
of `Link`s, and a `Link` is one of `Type(name)`, `SingletonOf(name)` or
`Unidentified(reason)`. `Unidentified` has no `#name`, so the guards at
the call sites become impossible rather than remembered, and
`SingletonOf` gives `024.26` somewhere to be.

**Acceptance:** `Widget.foo` after `class Object; def self.foo; end` is
silent; the two hand-written `next if entry.name.nil?` guards are deleted
and nothing regresses.

---

## D5 — A side or an owner is recomputed by every reader

**Entries:** `024.31`, `024.32`, `024.33`, `024.34`, `024.111`, `024.117`

**Where the decision is made:** `ParserService::Visitor` —
`#record_attribute_methods`, `#visit_def_node`, `#block_self_is_module`,
`#record_open_surface`.

This is C1's axis and the stocktake's verdict on it stands: `Cref`
collected the storage and not the question. `defines_surface?` answers
exactly what `024.34` needs and is read once; `declares_singleton?` is
read seven times, and `record_attribute_methods` reads it. Three review
rounds in a row found the same `origin == :extend` side computation
hand-rolled in `MethodResolver`, which 0.2.11 finally mechanised by
making both readers call `AncestorEntry#declaration_kind` — that is the
shape, applied to one pair of readers.

`024.31` and `024.33` are the part `Cref` cannot reach at all: they need
a block's *receiver*, and `#in_block` is a counter.

**The logic under which none of these could arise:** `Cref` exposes only
the questions a recorder may ask — `#surface_for(node)` returning
`[owner, side]` or `nil` — and the nine predicates become private. A
recorder cannot read `declares_singleton?` because there is no such
method to read. `#in_block` takes the receiver the block runs against,
so `included do … end` and `1.times { … }` stop being the same frame,
which is `024.111` and `024.117` together.

**Acceptance:** all six reproduce against Ruby before and none after; the
`%i[a b].each { |f| validates f }` spelling and the bare spelling get the
same answer.

---

## D6 — An identity is compared across things that are not comparable

**Entries:** `024.39`, `024.41`, `024.97`, `024.118`

**Where the decision is made:** `WorkspaceIndex#stale?` compares
`document_version` integers across buffers; `Server#publish_findings`
compares versions but not `Finding#generation`; `LocalInferencer` keeps
per-request state on an instance the server reuses.

0.2.10 gave the publish funnel a `buffer_id` and 0.2.11's `drive` round
found the reopen still dropped one layer earlier, in `#stale?`, whose
comment still asserts the premise the funnel rejects. **Two places
compared a version across buffers and one was fixed** — which is D3's
lesson arriving in a different subsystem.

**The logic under which none of these could arise:** there is one
`DocumentVersion(buffer_id:, version:)` and the bare integer is not
reachable from a `TextDocument` or a `FileSummary`. Comparing two of them
from different buffers returns `:incomparable`, which no caller can read
as "older".

**Acceptance:** `didOpen v20 → didChange v21 → didOpen v1 → didChange v2`
publishes for the new buffer; `024.97`'s `[[4, 0], [4, 1]]` becomes
`[[4, 1]]`.

---

## D7 — A claim about this tree is recorded without being re-derivable

**Entries:** `024.25`, `024.29`, `024.30`, `024.68`, `024.90`, `024.109`

**Where the decision is made:** the specs and documents themselves, and
`core/spec/meta/`.

Half-mechanised already: `measured_claims_spec.rb` recomputes every
`<!-- measured: -->` marker, and `home_path_guard_spec.rb` and
`check_site_links.rb` compare copies that must agree. What is not
mechanised is the one that keeps costing most — **an example whose
fixture cannot distinguish the behaviour it pins**. 0.2.11's third round
found one in the spec written to close `024.110`, whose own comment
promised it would fail under the change it was guarding against, and
which passed under it. `024.109` is three more, lost before they were
written down.

**The logic under which none of these could arise:** a spec that claims
to pin a decision names the mutation it pins, and a meta check applies
that mutation and requires the example to fail. This is the hunk sweep
turned around: the sweep asks "does anything fail when this line is
reverted", and this asks "does *this example* fail when the decision it
names is inverted".

**Acceptance:** applying `024.110`'s reversal fails
`unreadable_macro_spec.rb`'s distinguishing example, mechanically, and
the three `024.109` examples are found by the check rather than by a
reviewer.

---

## D8 — The thing under test is not the thing that ships

**Entries:** `024.55`, `024.64`, `024.69`, `024.74`, `024.75`

**Where the decision is made:** `scripts/corpus_diagnostics.rb` and every
spec that builds collaborators by hand, against `Server#initialize`; and
ci.yml, for the two suites that drive a real editor.

Twice now a fix has been measured against a harness that did not have the
collaborator the fix reads: `024.103` in 0.2.10, and `024.112` in 0.2.11,
**in the script whose own comment forbids exactly that**, added after the
first time. The 0.2.11 stocktake found the same thing in the other
direction — `hierarchy_index:` wired into `Server#initialize` and pinned
by no test at all, caught by the sweep rather than by a reviewer.

**The logic under which none of these could arise:** there is one
`Ovallsp.build_analysis_stack(...)` that `Server#initialize`, the corpus
script and the specs all call. A collaborator added to the stack reaches
every consumer of the stack at once, and a harness cannot be a subset of
the server because it does not assemble anything.

**Acceptance:** adding a constructor argument to any collaborator
requires exactly one edit; `024.69`'s two suites fail CI when skipped.

---

## D10 — A failure is turned into a plausible value

**Entries:** `024.122`, and it is upstream of `024.35` and part of D2

**Where the decision is made:** 159 `rescue` sites in `core/lib` and 21
`catch` blocks in `vscode/src`. Counted: **72 return a plausible value
silently**, 44 log and then return one, 4 re-raise as a typed error.

Added after the first nine, because the maintainer noticed it across the
codebase rather than in any one place — which is the shape of a class,
and none of D1–D9 names it. It is not a tenth *kind* of mistake so much
as the mechanism several of the others travel by: an empty ancestor list
that means "the RBS load failed" is D2's problem arriving through a
`rescue`, and a checker that reports "not pinned" when it could not load
the code is D7's.

**The logic under which none of these could arise:** catching and
continuing is not the default. A site that does it says in place what
the failure cannot affect and how a reader would find out it happened,
and a check fails the build on a new `rescue StandardError` without one.
Where the caller already has a three-state answer, the failure becomes
`unknown` — which is the machinery D2 builds, pointed at the other
source of not-knowing.

**Acceptance:** the enumeration comes out at the same 159 + 21 it started
from; no site in the third group remains; `CLAUDE.md` carries the rule;
and a deliberately-added bare `rescue StandardError` fails CI.

---

## D9 — Cost

**Entries:** `024.38`, `024.45`, `024.57`, `024.71`

Not a correctness class and deliberately not merged into one: `024.45` is
re-analysis being seconds on a large file against a stated 300 ms;
`024.38` is `scope_at` copying the environment per descent step;
`024.71` is a shared mutable fixture that makes the suite order-dependent.
C9 discharged `024.57`'s behaviour and left `024.45` reproducing at
4.310 s where the record says 4.31 s.

**The logic:** the analysis is incremental at the level of the *file
summary*, so a keystroke re-derives one method's summary rather than the
file's. That is a large change and it is the honest size of `024.45`.

---

## Not a class: individually caused

`024.20` (an exclusive end offset read as inclusive), `024.21` (a
qualified constant coloured half one way), `024.62` (two per-file stores
separated by nothing but their payload), `024.102` (the index itself).

**Listing these is part of the output, not a gap in it.** Forcing them
into a class is the specific move that made C1 claim two entries it could
never reach.

---

## The execution plan: which release, what steps, what size

Written down because the first exercise was not. `024.102` named eight
classes and left "when" and "how big" to be inferred, and the inference
that got made was "the mechanism shipped, so the class is done" — which
the stocktake then measured as 0 of 5 and 1 of 9.

**Sizes are counted, not estimated.** Each is the number of entries the
class claims, the files its mechanism touches, and the measurement its
acceptance needs. Where a number is a guess it says so.

### The procedure every class runs under

The same one, so a class cannot be "done differently":

1. **Write the acceptance reproduction first**, as an example, and watch
   it fail. It is a reproduction of a *named entry*, not a unit test of
   the mechanism — the mechanism passing its own test is what `024.102`
   mistook for progress.
2. **Build the mechanism.** Where it introduces a value, list in its own
   file which accessors must *not* exist, per this document's third rule.
3. **Re-run every entry the class claims.** An entry that still
   reproduces stays open, and the class does not close. An entry the
   mechanism cannot reach is a miscategorisation: move it and say so.
4. **Corpus, one at a time, in the foreground**, with a control category
   and both sides printing their own revision. `026`'s list applies.
5. **Hunk sweep**, tree otherwise untouched.
6. **Three review rounds**, methods differing, per `CLAUDE.md`. Ship with
   what is open recorded.

### 0.2.12 — the apparatus, and two small mechanical classes

**D8 — one assembler.** *Mechanism done.* `Ovallsp::AnalysisStack` is the
only place the four collaborators are constructed;
`core/spec/meta/analysis_stack_spec.rb` fails if anything else does, and
carries a second example proving the check fires on a real duplicate
rather than merely matching nothing. `Server#initialize`,
`scripts/corpus_diagnostics.rb` and all 28 spec files assemble nothing.
Actual size: 1 new lib file (106 lines), 2 call sites, 28 spec files, one
commit. `024.119` records it.

What remains of D8 is the *entries*: `024.55`, `024.64`, `024.69`,
`024.75`. The assembler does not fix them — it removes the condition
under which measuring them would be untrustworthy. **That distinction is
the whole point of rule 2**, and it is worth watching this class prove or
disprove it first, since D8 is the smallest place the rule can be tested.

**D7 — a spec names the mutation it pins.** The check applies that
mutation and requires the example to fail. Entries: `024.25`, `024.30`,
`024.68`, `024.90`, `024.109`. Size: 1 meta spec plus a per-example
annotation; the annotation is the work, and it is bounded by the number
of examples that *claim* to pin a decision rather than by the suite.
Start with the four `024.109` names and `unreadable_macro_spec.rb`'s
distinguishing example, which is known to be undistinguishing.

**D6 — one comparable document identity.** `DocumentVersion(buffer_id:,
version:)`; the bare integer is not reachable from `TextDocument` or
`FileSummary`; two from different buffers compare `:incomparable`.
Entries: `024.39`, `024.97`, `024.118`. Size: 1 value, 3 readers
(`WorkspaceIndex#stale?`, `Server#publish_findings`, `FileSummary`).
Acceptance is two reproductions that already exist in prose.

**D4 — a chain entry that can say what it is.** `Type` / `SingletonOf` /
`Unidentified`; `Unidentified` has no `#name`. Entries: `024.26`,
`024.80`, `024.81`. Size: `AncestorEntry` and its readers —
`HierarchyIndex`, `MethodResolver`, `Engine`. The two hand-written
`next if entry.name.nil?` guards are deleted as part of it, and their
deletion is the acceptance.

Fourteen entries, four mechanisms, no user-visible behaviour change
intended beyond `024.26` and `024.97`. **If the corpus moves at all
except for those two, something is wrong** — that is this release's
control.

### 0.2.13 — what an owner's own body says

**D2 — a member set carries its own completeness.** The largest class and
the one whose failures are user-visible false reports.
`MemberSet(names:, complete:, incomplete_because:)`, produced by the
recorder that knows: `ParserService` for a call it could not read,
the RBS loader for a missing signature. `absent` is a thing only a
complete set can answer. Entries: `024.18`, `024.22`, `024.27`,
`024.28`, `024.76`, `024.77`, `024.83`, `024.91`, `024.106`, `024.110`,
`024.116` — **11**. Size: the parser records a per-owner completeness
alongside its declarations; `WorkspaceIndex` stores it; `MethodResolver`
reads it instead of `unenumerable_reason`'s chain walk. Expect this to be
the release, not a part of one.

**D5 — `Cref` exposes questions, not flags.** `#surface_for(node)`
returning `[owner, side]` or `nil`, with the nine predicates private, and
`#in_block` taking the receiver the block runs against. Entries:
`024.31`, `024.32`, `024.33`, `024.34`, `024.111`, `024.117` — **6**.
Size: `Index::Cref` plus the seven `declares_singleton?` read sites.
`024.32`'s decision is *not* in `Cref` — it is a Prism node-class test —
so it is claimed here only because the fix belongs beside the others, and
if it does not move it goes back to individually-caused.

Seventeen entries. Both are user-visible, both need a corpus with a
control, and D2's acceptance includes the four-line `class Module`
reproduction staying reported.

### 0.2.14 — resolution says what it knows

**D1 — `Resolution(name:, basis:)`.** Entries: `024.13`, `024.19`,
`024.35`, `024.37`, `024.40`, `024.47`, `024.82`, `024.84` — **8**.
Size: `WorkspaceIndex`'s two resolvers and every consumer of a resolved
name, which is the widest blast radius of any class here. It is last of
the correctness classes for that reason and because 0.2.1's attempt at
the same area was rolled back (`024.47`).

### 0.3.0 — the first release that may add capability

**D3 — one `ReceiverResolver#at(document:, position:)`.** Entries:
`024.42`, `024.43`, `024.44`, `024.63`, `024.85`, `024.86`, `024.87`,
`024.88`, `024.89`, `024.99`, `024.100` — **11**. This is C2's unbuilt
half, and it is here rather than earlier because it changes what hover,
completion, definition and signature help *answer*, which is a capability
change by `docs/PUBLISHING.md`'s own definition. Every other class above
is meant to leave the four features answering what they already answer,
only correctly.

D3 is also the class that most wants the apparatus: it is a
four-consumer change whose failure mode is "two features disagree", and
that is invisible to a suite whose examples each build their own stack.
**0.2.12's D8 is a precondition for it**, not a nicety.

### D9 — cost

`024.38`, `024.45`, `024.57`, `024.71`. **Not scheduled here.**
`024.45`'s honest size is per-method incremental summaries, which is a
different axis from everything above, and putting a number on it before
D2 lands would be a guess — D2 changes what a file summary contains.

### What this plan does not promise

That the classes are right. Two of C1's five entries were outside its
reach and the exercise could not see it; this one asks "where is the
value produced" for every entry, which is a better question but not a
proof. **Step 3 of the procedure is where a wrong class is found** — an
entry that does not move when its mechanism ships is a miscategorisation,
and it gets moved and recorded rather than argued with.

## What this says about sequencing

| class | entries | discharges |
|---|---|---|
| D2 | 11 | the largest single group, and the one whose failures are user-visible false reports |
| D3 | 11 | C2's unbuilt half; every "two features disagree" entry |
| D1 | 8 | every "judged against a class the receiver is not" |
| D5 | 6 | C1's axis, done as questions rather than storage |
| D7 | 6 | the check that would have caught `024.109` and `024.110`'s spec |
| D8 | 5 | measured twice against a harness that could not see the fix |
| D6 | 4 | one value type, mechanically |
| D4 | 3 | small, and unblocks `024.26` which nothing else can |
| D9 | 4 | cost, not correctness |

**D7 and D8 go first**, and not because they are the largest. They are
the two classes whose failures make the *other* classes' measurements
untrustworthy — a spec that cannot distinguish, and a harness that is not
the server. Every number in this document was produced by the apparatus
those two classes are about, and two of the three corpus comparisons this
release cycle were invalidated by D8 alone.

Then D6 and D4, which are small, mechanical, and have acceptance tests
that are single reproductions.

Then D2 and D3, which are the release. They are also the two the previous
exercise claimed to have built and did not: D2 is C2's ancestor axis
extended to members, D3 is C2's half that was never written.

D1 and D5 last, because both have a rolled-back attempt behind them
(`024.47`, and C1) and want the apparatus from D7/D8 to be trustworthy
before they are measured.
