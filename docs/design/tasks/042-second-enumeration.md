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
