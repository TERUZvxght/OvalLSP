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

### 0.2.7 — the remaining foundations *(axis B)* — **shipped**

Recorded in `037-0.2.7-concurrency-foundations.md`, prepared on
`feat/0.2.7`. Named here per CLAUDE.md's residency rule while it was in
flight: a pointer to a file that exists only on an unnamed branch is a
pointer to nothing.


`029`'s `M-2`/`M-3`/`C-3`: immutable document snapshots, one writer with
memory for the publish funnel, and the architecture document's threading
section landed with them. Correctness-under-concurrency and
answer-stability, not new capability. `024.56` is what makes it a must —
a reproduced publish sequence for a closed file, present in every shipped
build, that had missed a `0.2.4` target three times.

`024.47`'s naming-convention decision is **not** in it: it is L-sized and
independent, and 0.2.7 is already the release where a first attempt at
the funnel introduced a defect worse than the one it fixed.

### 0.2.8 — the parser's bookkeeping, and a file's identity *(axis B)* — **shipped**

`037`'s C1 and C8. A declaration's owner and kind stop being decided by
six parallel mutable stacks and become one immutable value every recorder
is handed; a uri gets one canonical form so a symlinked workspace stops
showing every file twice.

**"Carry" was the wrong word, and this sentence said it for two
releases.** 0.2.11's stocktake re-ran all five of C1's entries —
`024.26`, `024.31`, `024.32`, `024.33`, `024.34` — and every one still
reproduces. Four were never within the mechanism's reach and one is,
and is still wrong. `024.98` (C8) is genuinely fixed. `024.102` records
the verdicts and what each says about the mechanism.

### 0.2.9 — one question, asked once, answered honestly *(axis B)* — **shipped**

`037`'s C2. One query per position answering present / absent / unknown,
with `unknown` produced by whatever failed to enumerate rather than
inferred by a caller — so a new way of not knowing makes every reader
silent by construction instead of by each reader being taught. The six
reasons `Diagnostics::Engine` had accumulated one review round at a time
moved to where the enumeration happens. Completion stopped offering names
that cannot be called from where the developer is typing: private and
protected on an explicit receiver, and a private alias, which had no
declaration for the visibility rule to read. `024.99`, `024.100`,
`024.105`, `024.107`, `024.108`.

C3 and C9 moved to 0.2.10 once C2's size was measurable rather than
estimated in advance — this was the largest thing left before 1.0.0 and
the one most likely to be attempted at the wrong size, and `024.15` and
`024.47` are what that costs here. What is still open from the loop is
`024.109`: three examples of this change set whose fixtures may not
distinguish the behaviour they pin, whose list was lost before it was
written down.

### 0.2.10 — an answer knows what it was computed from, and three that slipped *(axis B)* — **shipped**

`037`'s C3 and C9, moved out of 0.2.9 once C2's size was measurable, plus
the three 0.2.8's drive round found and recorded as 0.2.9 without their
being built there — `024.103` first, because it is a false report on
working code on an ordinary Rails layout. `024.55` joins them: written
for 0.2.4 and still open five releases later, so it is retargeted rather
than left naming a release that has shipped. They
are one thing: giving a published answer the identity of the document it
came from also refuses a slower analysis of the same buffer, and whether
those should be published at all is C9's question — 0.2.8's drive round
measured 22 wrong intermediate publishes for one method name typed on a
4,006-line file. (re-measured for 0.2.10 in `040`, in this scenario rather than a different one: **it reproduces** — 12 keystrokes, 12 publishes, all 12 reporting the unfinished name; after C9, one)

`024.57` is why it is its own release rather than an appendix: a first
attempt at the debounce was rolled back, and the precondition `029` said
it lacked shipped in 0.2.7. `024.19`, `024.44`, `024.45`, `024.57`,
`024.97`, `024.101`.

**What it took.** Three review rounds — `diff`, `attack` and `drive` —
finding 19, 12 and 8 defects. The `drive` round is the one that mattered:
the two reading rounds between them missed 41 false reports on shipped
Rails source, including a fix from the round before that had switched
`extend self` off entirely. `040` records all three tables, and the
release ships under `CLAUDE.md`'s bound with `024.106`'s second half,
`024.109`, and `024.111`–`024.116` open.

### 0.2.11 — the loop's own leavings *(axis B)* — **shipped**

What 0.2.10's rounds recorded rather than fixed, which is a coherent
release rather than an appendix: `024.106`'s second half needs the index
to prove a module's declarations are all of them; `024.114` needs
`module_function :name` to be a fact applied after both files are
indexed, the way `AncestorFact` already is; and `024.115` narrows the
concern rule to something with a marker. `024.111`, `024.112`, `024.113`,
`024.116`, `024.109` and `024.110` join them.

**What it took.** Three rounds — `attack`, `drive`, `reproduce` — finding
11, 5 and 9 defects. Six of the nine entries closed; `024.110` was tried
in its recorded one-line shape and **rolled back inside the release**
after a `drive` round measured constant-receiver findings going 117 → 0.
The `reproduce` round then found the release a net regression on its own
corpus and the headline table advertising the opposite. It ships neutral
on that corpus — 84 → 84, control identical — with its value in shapes
four Rails gems do not contain.

### 0.2.12 — the apparatus, and two small mechanical classes *(axis B)* — **shipped**

[`042-second-enumeration.md`](042-second-enumeration.md)'s **D7, D8, D6
and D4**. A spec names the mutation it pins and a check applies it; one
function assembles the analysis stack, so a harness cannot be a subset of
the server; a document identity carries its buffer, so two versions from
different buffers are `:incomparable` rather than ordered; and an
ancestor chain is a list of `Type` / `SingletonOf` / `Unidentified`, so
the `nil`-owner guards become impossible instead of remembered.

**D7 and D8 go first, and not because they are the largest.** They are
the two classes whose failures make every *other* class's measurement
untrustworthy — a spec that cannot distinguish, and a harness that is not
the server. Two of the three corpus comparisons in the 0.2.9–0.2.11 cycle
were invalidated by D8 alone, one of them in the script whose own comment
forbids exactly that.

`024.25`, `024.26`, `024.30`, `024.39`, `024.55`, `024.64`, `024.68`,
`024.69`, `024.75`, `024.80`, `024.81`, `024.97`, `024.109`, `024.118`.

### 0.2.13 — what an owner's own body says, and failures that stop being silent *(axis B)* — **next, on `feat/0.2.13`**

042's **D2** and **D5**. The largest group and C1's axis done as
questions rather than storage: a member set produced *with* its
completeness by the recorder that knows, so `absent` is a thing only a
complete set can answer; and a `Cref` that exposes `#surface_for(node)`
and nothing else, with a block frame that carries the receiver the block
runs against.

`024.106`, `024.110`, `024.111`, `024.116`, `024.117`, `024.76`,
`024.77`, `024.83`, `024.91`, `024.18`, `024.22`, `024.27`, `024.28`,
`024.31`, `024.32`, `024.33`, `024.34`.

And **D10**, raised by the maintainer and measured before it was
written down: 72 places in `core/lib` catch a failure and return a value
that looks like a real answer. Every layer of this project has been bitten
by it — a cache that silently missed, an RBS load whose failure is
indistinguishable from a type with no ancestors, and 0.2.12's own mutation
checker reporting "nothing pinned" when it could not load the code it was
mutating. `024.122` is the task, and its third step is the one that has to
come last: the policy is written into `CLAUDE.md` *after* the tree obeys
it, not before, so the rule does not arrive with 72 exceptions.

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
