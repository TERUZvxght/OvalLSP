# Task 036: The road to 1.0.0, derived from section 0

**Why this file exists.** Work has been proceeding item by item — a
finding, a fix, a round — and the path to 1.0.0 was implied rather than
written. An implied path is the thing this project loses across a context
compaction. This states what 1.0.0 requires, what is measured today, and
what closes the gap, so the next session can see the distance rather than
infer it.

It is derived from **two axes and nothing else**:

- **Axis A** — the obligations shipping a product to other people
  creates, independent of the product's vision.
- **Axis B** — section 0 of
  [`01-product-requirements.md`](../docs/01-product-requirements.md).

Nothing here is a new requirement. Anything that cannot be traced to one
of the two axes is not on this list, however real.

---

## 1. What 1.0.0 means

Section 0.2, in the maintainer's words: **1.0.0 is where this becomes
usable in practice, and a Ruby/Rails engineer is measurably better off.**
Section 0.3: the scope is *make the foundation solid, with Pylance as the
reference*; conveniences that are not load-bearing are 2.x.x.

Section 0.1 says what the foundation is: **type checking, and calls to
methods that do not exist** — so that tests can narrow to what they are
actually for.

`docs/PUBLISHING.md` adds the environment half — every published target
verified, a plain Ruby project guaranteed — and section 0.7 records that
those are necessary and not sufficient.

So 1.0.0 has two halves, and the capability half is the one currently
failing.

## 2. Where the capability half actually stands

Measured, not estimated. Every figure here was taken by driving the real
server; where a number is from a single run it says so.

| what a user asks | measured today |
|---|---|
| "is this call undefined?" — **precision** | **54 reports over 213 files of real gem source; 53 wrong** (`024.76`) |
| "is this call undefined?" — **recall** | missed entirely through `Model.scope.first` — a Union receiver, which the check discards before asking anything (`024.77`) |
| "what are this receiver's members?" | a class with an unidentifiable parent offered the workspace's top-level methods (fixed in 0.2.5, `024.80`); a nested core type is shadowed by a workspace class of the same basename (`024.78`) |
| "what type is this?" | `Model.first.` answers nothing while `Model.scope.first.` answers 329 (`024.79`) |

**By section 0.4 — a wrong answer is worse than no answer — the check is
currently worth less than its own absence.** That sentence is the whole
argument for what comes next, and it is the project's own standard, not
an outside one.

### The root, as far as it is established

An external review (`034-…-review-gpt-5.6-sol.md`) named it, and its
central claim reproduces:

> A negative diagnostic may assert absence only when it also has evidence
> that every source capable of making the assertion false has been
> completely accounted for.

Today "unknown" collapses into "nothing found" in at least four places,
and each consumer reconstructs the uncertainty with a local guard —
which is why fixing one reader leaves the next one wrong. Verified
instances:

- an ancestor reference resolved to **a different namespace's module**
  because `AncestorFact` carries no lexical nesting and ambiguous simple
  names resolve alphabetically (reproduced: an unrelated `Aaa::Helpers`
  captures `Rackish::Request`'s `include Helpers`);
- an unresolvable `include` is **not recorded at all**, so "no include"
  and "an include I could not name" are the same downstream;
- `AncestorEntry(name: nil)` is accepted by a method-lookup API for which
  `nil` means *the top-level owner* (`024.80`);
- a Union receiver is discarded before any question is asked
  (`engine.rb:121`), which is the entire recall gap.

## 3. The path

Each step states the axis it serves. Sizes are relative, not schedules.

### 0.2.6 — negative diagnostics get a proof model *(axis B)*

The review's recommended scope, which this project accepts as the shape
but will re-measure item by item:

1. preserve ancestor-reference uncertainty instead of dropping it;
2. carry lexical context for ancestor constant references, or return
   ambiguity rather than picking a namespace and later claiming closure;
3. make an unresolved link impossible to pass to an owner lookup;
4. one exact-name member-availability query, with `unknown-method` moved
   onto it — and **only** that check, not completion enumeration;
5. Union receivers evaluated branch-wise;
6. unrecognised class-body macros make the surface *open*, so
   metaprogramming yields `unknown` rather than `absent`.

**Success is measured, not declared:** re-run the 213-file corpus. The
target is not zero reports; it is that a report that survives is one a
Ruby developer would agree with, and that `Model.scope.first.missing` is
caught.

Also in it: `024.73` (`Marshal.load` on plugin output — axis A),
`024.78`, `024.79`.

### 0.2.7 — the remaining foundations *(axis B)* — **in progress on `feat/0.2.7`**

Recorded in `037-0.2.7-concurrency-foundations.md`, which lives on that
branch. Named here per CLAUDE.md's residency rule: a pointer to a file
that exists only on an unnamed branch is a pointer to nothing.


`024.47`'s naming-convention decision, and `029`'s `M-2`/`M-3`
(immutable document snapshots; one writer with memory for the publish
funnel — noting `M-3` is a no-op as originally specified). These are
correctness-under-concurrency and answer-stability, not new capability.

### 0.3.0 — the first release that may add capability *(axis B)*

Whatever the roadmap holds once the foundation is sound. Deliberately not
enumerated here: enumerating features before the foundation is measured
is how a release recedes.

### Before 1.0.0 — the environment half *(axis A, and PUBLISHING.md)*

- published, verified artifacts for the targets beyond `darwin-arm64`
  (`024.R4`);
- a plain Ruby project guaranteed, not only a Rails one (`024.R1`);
- `024.69` — the two suites that drive a real editor run only on the
  maintainer's machine; before 1.0.0 they run somewhere else too;
- `024.71` — the shared Rails fixture blocks parallelisation, which is
  what makes the above affordable.

## 4. What decides that 1.0.0 has arrived

Three things, all measurable, and none of them "the backlog is empty":

1. **The undefined-method check is trustworthy on real code.** The
   corpus measurement is the instrument. A developer who sees a report
   believes it.
2. **The daily paths answer.** `Model.first`, `Model.scope.first`,
   a namespaced model, a concern-shaped `include` — hover, completion,
   definition and diagnostics all answer, and answer the same thing.
3. **The environment half of `PUBLISHING.md` holds**, verified rather
   than asserted.

Section 0.4 governs the whole list: **a wrong answer is worse than no
answer, but letting 1.0.0 recede forever in pursuit of accuracy is worse
than either.** Every item above is here because it is measured to be on a
path people walk. Anything that is not stays a known limitation and
ships.

## 5. What this file is not

Not a schedule, and not a promise about content beyond 0.2.6 — 0.2.7 and
0.3.0 are named so the direction is visible, and they will be re-argued
from measurement when they open. It is deleted when 1.0.0 ships.
