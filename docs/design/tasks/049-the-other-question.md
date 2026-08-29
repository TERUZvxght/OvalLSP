# 049 — the same codebase, asked the other question

`048` asked **"is this needed?"** of every subsystem and verified by
**deletion**. It produced 101 pieces of excess, of which eight were large
enough to change a release, and **not one survived measurement**. Its
conclusion — that the complexity here is earned — is correct within the
question it asked.

This document asks the other question:

> Given that this behaviour is required, **what is the simplest thing that
> could possibly work?** Is the code that shape?

Asked on 2026-08-25, after the maintainer asked whether re-running the
audit under DTSTTCPW rather than YAGNI would change the content.

## It changes the content, and the overlap is empty by construction

| | `048` (YAGNI, verified by deletion) | this (DTSTTCPW, verified by substitution) |
|---|---|---|
| findings | 101 | 35 |
| large enough to change a release | 8 | 15 |
| **survived measurement** | **0 of 8** | **11 of 16** |
| measured to make the product worse | 4 | 4 |
| unproven | 2 | 1 |

And the number that says the two audits cannot find each other's work:
**35 of 35 findings contain no unused line at all.** A deletion
audit is structurally blind to every one of them — remove any part and
something breaks, which is exactly why `048` reported the subsystems they
live in as already minimal.

## The shapes, counted

| shape | found |
|---|---|
| information destroyed upstream and reconstructed downstream | 11 |
| two readers of one fact, kept in step by hand | 9 |
| N bookkeeping structures where one value would do | 8 |
| a guard at each caller instead of at the thing guarded | 4 |
| a sentinel every reader must remember to check | 3 |

The first was predicted before the audit ran, from `024.224`'s root cause
written the same day: the comparison is asked to recover an identity that
was already lost upstream, and every recovery rule strong enough to
reunite two spellings of one class also unites two different classes.
Eleven more instances of the same shape came back.


## Complexity was hiding defects, which is the finding under the finding

Three of the eleven substitutions that held were built to reduce moving
parts and **turned up a live, user-visible wrong answer on the way**.
None was reported by any review round; each was invisible because the
duplicate path looked like the working one.

- **Hover answers nothing in a view.** `hover` and `explainType` fetched
  the document differently from the other seven position handlers. In a
  view, with a model method under the cursor: hover `null`, while
  completion at the identical position offered the method and go to
  definition found it.
- **Find References answers from a comment.** Three spellings of "the
  symbol under the cursor" existed and only one applied the name-range
  rule. With the caret on a word inside a comment, on a bare `42`, and on
  `end`, `textDocument/references` returned both call sites of a method —
  while `prepareRename`, reading the third spelling, correctly declined.
- **A constant held in a local loses an overload.** Two call-resolution
  ladders. `Zoo.pick(1)` infers `String | Symbol`; `k = Zoo; k.pick(1)`
  infers `String`.

A deletion audit could not have found these either: every line involved
has a caller.

## The four that failed, and one of them is the whole reason for the bar


**2. RbiParser stops truncating a written type path to its last segment**

The diagnosis is right and the two lines are right in isolation —
RbiParser really is still doing what 0.2.5 measured the harm of, and the
change buys a missed report plus an honest message. It still fails the
bar, because the corpus diff contains a difference I cannot defend: on
ordinary correct code (RBI says `Zoo::Animal`, the workspace declares
`Zoo::Animal`, the value arrives via a method return) it produces a
class reported incompatible with itself where HEAD was silent. That is
`024.224` arriving on the RBI path, and section 0 ranks a wrong answer
below the silence it replaces. It is not a rare shape: HEAD is safe here
only because truncation happened to make the two spellings meet. Fixing
it requires 024.224 attempt 1's fourth hand-built spelling — measured to
work, and the exact class of defect the register says not to add — so
this is not a two-line change, it is a change that


**3. Carry `private def`/`private attr_reader` as a cref visibility section instead of two side channels**

Fails as described. It is the one proposal here whose defect is not that
it does nothing, but that it asserts something false: three declarations
flip from public to private, and the interpreter says all three should
be public — including one case, `private def a2; def b2; end; end`, that
HEAD currently gets RIGHT. Section 0 ranks a wrong answer below no
answer, and this trades a correct answer for a wrong one in a mechanism
that feeds Rails action detection and completion filtering. The proposal
anticipates the direction but mis-ranks it, calling the change "making
the two spellings agree" rather than what it is. A corrected variant
does hold by every criterion — green, both corpora empty with controls
held, a 6,601-row visibility census byte-identical, one row improved —
but reaching it needs a visibility reset inside `Cref#in_method`, which
is shared code with a much wider blast radiu


**P1 seed: nesting for the controller-to-view ivar path**

Fails, and fails in the direction section 0.4 ranks worst: it replaces a
correct answer with a confident wrong one for compact-spelled
controllers, and its own named falsifier cannot detect that because the
falsifier never enters the code. The premise is sound — the missing
nesting is a real defect, it reproduces, and Part A is what makes it
visible instead of inherited — but the fix cannot be derived from the
owner name at all. The exact nesting is known only to
`MethodMapLocator`, which walks the namespace nodes to find the method
and currently throws the spelling away; carrying it out of the locator
is the shape that could be right. That is a different change from the
one proposed, and it belongs in its own task. Note also that a gem
corpus can never measure it: any future attempt needs a real Rails app
driven through views/controller_ivars.rb, or the measurement will come
back clean


**Publish Signatures::Environment#declares? and retire the UNAVAILABLE sentinel**

Fails as described, on its own terms, and the failing piece is one of
the four conversions the proposal treats as obviously safe. Converting
`Engine#locally_accounted_for?` to `#declares?` newly reports
`Vendor::Thing has no method named `shout`` on a receiver whose Agent-
reported ancestor is declared in the project's own sig with the method
on it — a chain that could not be built, asserted as a chain that is not
there. That is precisely 024.223 re-entering through a different door,
and it is invisible to every check the proposer ran: the suite is green,
the corpus diff is byte-identical, and the named falsifier probes at 0.
It only appears when you build a fixture where the RECEIVER's chain is
fine and only a foreign ancestor's is broken, which is the shape
`locally_accounted_for?` exists for. The proposal's own framing is what
hid it — counting readers by whether they test the sentinel


The third of those is the one worth remembering. It does not merely fail
to help: it takes three declarations from public to private when the
interpreter says all three are public, and one of them —
`private def a2; def b2; end; end` — is a case HEAD currently gets
**right**. Section 0 ranks a wrong answer below no answer, and a
simplification that trades a correct answer for a wrong one is worse than
the complexity it removes. That is the same arithmetic `048`'s four
failures produced, arriving from the other direction, and it is why the
bar is a measured substitution rather than a read one.

## Disposition

**Not 0.2.16.** Every one of these is a retrospective simplification of
code that already works, and `CLAUDE.md`'s DTSTTCPW rule — written the
same day, from `048`'s evidence — says those carry an ordinary change's
obligations. Eleven of them in one release is the blast radius 0.2.1 lost
a release to.

Three carry a live user-visible defect and are worth taking on their own
merit rather than as simplifications; they are recorded as register
entries so the defect is fixed whether or not the substitution is.

The rest belong to 0.3.0, where `024.R7` already opens the signature and
index sides together — which is where four of the eleven land anyway.

## Every material finding

| # | area | shape | title |
|---|---|---|---|
| 1 | types-and-signatures | sentinel-every-reader-checks | Four callers derive "the signature environment declares this name" from `#ancestors(...).e |
| 2 | types-and-signatures | identity-lost-upstream | `RbiParser` truncates a written type path to its last segment — the exact operation `TypeC |
| 3 | types-and-signatures | identity-lost-upstream | `024.224` reproduces at HEAD, and `Types::Nominal`'s structural equality rules out the ent |
| 4 | parser-and-cref | guard-at-callers | `#visit_def_node`'s early return sits above a method-level `ensure` that undoes three save |
| 5 | parser-and-cref | identity-lost-upstream | `scope_id` re-derives, from the node's *kind*, a binding fact Prism has already computed a |
| 6 | parser-and-cref | two-readers-one-fact | Three mechanisms carry one fact — "a wrapping call's modifier applies to what it wraps" —  |
| 7 | local-inferencer | n-structures-one-value | Three parallel walk structures where one immutable cref would do — and one entry point see |
| 8 | local-inferencer | two-readers-one-fact | resolve_call writes the same lookup ladder twice — once keyed on the AST, once on the valu |
| 9 | diagnostics-engine | identity-lost-upstream | "RBS declares this name" is a fact the Environment computes, discards into the emptiness o |
| 10 | resolution-and-index | identity-lost-upstream | The resolved type identity is published as two lossy projections, and the one consumer tha |
| 11 | method-resolution | identity-lost-upstream | `members_of` flattens away which Union branch supplied each name, then re-derives it with  |
| 12 | method-resolution | two-readers-one-fact | Four copies of "walk the ancestors, skip the ones nobody identified, work out which side t |
| 13 | server-dispatch | two-readers-one-fact | The view environment is still fetched at four independent places, and hover is the reader  |
| 14 | server-dispatch | two-readers-one-fact | Three spellings of "the symbol under the cursor"; the two that share a spelling still use  |
| 15 | agent-and-observation | n-structures-one-value | Seven slots describe one child process; one value does, and three convention-held invarian |

Full evidence for each — the requirement enumerated, the construction,
the falsifier, the blast radius, and for the sixteen that were built the
suite counts and corpus diffs on both sides — is in the audit's own
transcript. What is carried forward into the register is the subset with
a defect attached.

## Where the two built substitutions actually live

Two of the eleven were implemented and left on local branches while the
audit ran, and a branch nothing names is a pointer to nothing. Named
here, with what each one is:

| branch | what it holds | measured |
|---|---|---|
| `spike/049-visit-def-guard` | `#visit_def_node`'s guard split out of the method carrying the `ensure`, and `@skip_block_frame` deleted — a one-shot flag set in one method and read eighty lines away | moving parts 5 → 1; suites identical both sides |
| `spike/049-scope-locals` | scope frames carry Prism's own `#locals` and the frame that binds a name is picked, replacing a counter and a stack that had to stay in step | moving parts 6 → 3; two corpora, controls held, 0-line diffs |

**Both are local to the machine the audit ran on and are not pushed.**
That is deliberate rather than an oversight: their conclusions are in
this document, 0.3.0 will re-derive from it, and the branches are a
convenience rather than the record. A session that cannot see them has
lost nothing but the typing.

## Method, and its one honest limit

Eight subsystems, one auditor each, given `048` to read first and told
what shapes to hunt and what does not count. Every finding had to state
what the current shape delivers, the actual construction that replaces
it, a falsifier, and the blast radius. Every large or medium finding then
went to a second agent whose instruction was to **build it, not read it**:
implement it in an isolated worktree, run the proposer's own falsifier,
run the affected spec directories, and drive a corpus on both sides over
the identical directory with a control category that must come out equal.

The limit: "simpler" was measured as places that must agree, invariants
held by convention, and readers that must remember a rule. That is a
judgement, not a count, and two proposers reported line deltas that point
the other way from their moving-part counts. `048`'s headline reduction
came out at +3 net lines once it had to work, which is why line count is
not the measure here — but it does mean nothing in this document is
mechanically checkable the way an example count is.

