# External review of Task 034 — diagnostics precision and structural sealing

**Reviewer:** GPT-5.6 Sol  
**Reviewed branch:** `feat/0.2.5`  
**Source briefing:** `docs/design/tasks/034-diagnostics-precision-briefing.md`  
**Status:** proposal/review input, not an adopted design decision

This review treats the repository's current source as authoritative and the documents as evidence only. The requested scope is broader than Task 034's latest failing examples: the goal is to find places where a local guard has merely sealed one manifestation of a deeper problem, and to identify structures under which the same class of problem cannot recur by construction.

## Executive conclusion

The central problem is not only `Diagnostics::Engine#closed_nominal?`.

OvalLSP currently has several paths where **"unknown / incomplete" is reduced to "nothing was found"**, after which consumers reconstruct uncertainty with local guards. This produces exactly the pattern Task 034 is concerned about: one reader is patched, another reader interprets the same representation differently, and the same bug class reappears elsewhere.

The durable rule should be:

> A negative diagnostic may assert absence only when it also has evidence that every source capable of making the assertion false has been completely accounted for.

Positive queries such as Completion, Hover and Definition may remain best-effort. A negative assertion such as `unknown-method` is different: "I did not find this method" is not equivalent to "this method does not exist".

The minimal structural direction I recommend is to make uncertainty first-class in three places:

```text
ConstantResolution
  written name + lexical context
  -> exact / lexical / ambiguous / unresolved

AncestorChain
  entries
  + complete?
  + uncertainty reasons

MemberAvailability
  receiver type + member name
  -> present / absent / conditional / unknown
  + evidence
```

`MemberAvailability` should combine the existing `MethodResolver`, `ModelRegistry`, Runtime Agent facts and `Signatures::Environment`; it does not require another type inference engine. The key is that `absent` must become a strong result rather than the current default after every positive lookup has failed.

A useful definition is:

```text
absent
= no provider contains the method
  AND constant identity is sufficiently established
  AND the relevant ancestry/method surface is complete
  AND every relevant Union branch is absent
```

If any of those conditions cannot be established, the result is `unknown`, not `absent`.

## Finding 1 — Task 034's twelve-line `include Helpers` reproduction should be re-run against the current HEAD

Task 034 records this as a fact:

```ruby
module Rackish
  module Helpers
    def helper_method; end
  end

  class Request
    include Helpers
    def call = helper_method
  end
end
```

and says that `HierarchyIndex#ancestors("Rackish::Request")` omits `Helpers`.

A static read of the current `feat/0.2.5` source does not make that result obvious anymore. `ParserService` records `include Helpers` as an `AncestorFact` whose owner is the qualified enclosing class and whose target is the constant path as written. `HierarchyIndex#ancestor_entries_for` then resolves that target through the workspace. In an isolated workspace containing only the sample above, `Helpers` has a single plausible class/module declaration (`::Rackish::Helpers`).

I therefore would **not use this twelve-line result as a current causal premise until it has been re-run against the exact current HEAD**. The GitHub connector used for this review permits source inspection but not execution of the repository's test harness, so this particular point is a source-level contradiction to verify, not a claim that the measurement is false.

The 12 corpus findings can still be real. The more durable issue is that `AncestorFact` does **not carry lexical nesting**, while Ruby constant lookup is lexical. It stores only:

```text
owner / relation / target / location
```

and `WorkspaceIndex#resolve_type_name` explicitly performs name-heuristic resolution rather than real lexical constant resolution. Its own implementation documents that ambiguous simple names are resolved deterministically to an alphabetically first candidate.

That means the isolated example and the real gem corpus can diverge exactly when the real workspace contains multiple same-simple-name modules. The likely structural failure is therefore not merely "include vanished" but:

> The fact that identifies an ancestor reference loses the lexical context required to identify that ancestor before the semantic hierarchy is built.

### Proposed correction

Ancestor references should retain the same lexical-resolution evidence already retained for ordinary references. For example:

```ruby
AncestorFact(
  owner:,
  relation:,
  target:,
  lexical_nesting:,
  location:
)
```

and one constant-resolution component should resolve both ordinary references and ancestor references.

This does **not** require perfect Ruby constant resolution in 0.2.6. A resolver is allowed to return `ambiguous` or `unresolved`; what must stop is collapsing those states into a guessed exact ancestor and later treating that chain as closed.

## Finding 2 — `HierarchyIndex` currently uses incompatible representations for the same semantic fact: "an ancestor exists but we cannot identify it"

The superclass path has already moved in the right direction. A dynamic or guessed superclass becomes a nameless ancestor entry:

```ruby
AncestorEntry.new(name: nil, kind: nil, origin: :superclass, location: nil)
```

That preserves uncertainty, so downstream code can refuse to call the chain complete.

`include` / `prepend` / `extend` do not have the same contract. In `ParserService#record_ancestor_call`, an argument for which `raw_constant_name` cannot produce a static name is skipped; no `AncestorFact` is recorded at all.

So the following two facts become indistinguishable downstream:

```text
there was no include
there was an include whose target could not be named statically
```

That is exactly the "unknown becomes absent" transformation that a negative diagnostic cannot safely tolerate.

### More importantly: `name: nil` itself is an unstable representation

`nil` is also a legitimate semantic owner elsewhere in the index: top-level methods are indexed under an owner of `nil`.

`MethodResolver#build_candidate` knows this and explicitly returns early for a nameless `AncestorEntry`, with a comment documenting the real bug that otherwise occurs: an unknown parent can accidentally inherit top-level methods.

But `MethodResolver#names_for_type`, used by completion, has no corresponding `entry.name.nil?` guard before asking `WorkspaceIndex#method_symbol_ids(entry.name, ...)`.

This is a concrete surviving example of the requested bug class:

> one consumer locally sealed an ambiguous representation, while a second consumer of the same representation did not.

Adding the same `nil` guard to `names_for_type` is necessary as an immediate defect fix, but it is not the structural fix.

### Proposed correction

Do not encode an unresolved ancestor as a fake ordinary ancestor whose `name` happens to be `nil`.

Either return a result object such as:

```ruby
AncestorChain.new(
  entries: [...],
  complete: false,
  reasons: [:dynamic_superclass, :unresolved_include]
)
```

or use a distinct unresolved-link type that no method lookup API accepts as an owner.

The important invariant is:

> An unresolved hierarchy edge cannot be passed to an API that expects a real declaration owner.

With that invariant, the top-level-owner collision becomes impossible instead of being guarded at every reader.

## Finding 3 — Diagnostics and Completion currently implement two different answers to "does this receiver have this method?"

`unknown_method_findings` performs its own availability test:

1. ask reference resolution whether the call already resolved;
2. require a single `Types::Nominal` receiver;
3. require `closed_nominal?` or `model_closed?`;
4. separately ask `rbs_resolves?`;
5. separately ask `model_resolves?`;
6. if all fail, report absence.

Completion uses `QueryService#members_of`, which combines a different set of providers:

- workspace source methods through `MethodResolver`;
- Active Record columns;
- Active Record associations;
- Runtime Agent Active Record API and per-model methods;
- RBS/RBI signatures;
- Union conditionality normalization.

Those paths therefore have no structural reason to agree.

This is not merely duplication. `ReferenceResolver` answers a navigation/reference-resolution question; it is not an authority on whether a method exists at runtime. A generated or runtime-known member may be valid while having no source declaration to navigate to.

This repository already contains the precedent for the right correction. `Diagnostics::Engine#receiver_type_for` delegates receiver identification to `Semantic::ReceiverResolution` because previous duplicated receiver logic produced the same namespace bug in multiple consumers. Method availability should receive the same treatment.

### Proposed correction: exact member availability API

Keep `QueryService#members_of` as the enumeration API for completion. Add an exact-name query beneath or beside it, for example:

```ruby
availability = query_service.member_availability(
  receiver_type,
  method_name,
  context: ...
)

availability.status
# => :present | :absent | :conditional | :unknown
```

It should reuse the existing providers rather than reimplement them in Diagnostics.

This is much smaller than replacing QueryService or rewriting Completion. For 0.2.6, only `unknown-method` needs to migrate to the new exact query.

### What is lost

The immediate cost is that some calls that Diagnostics currently labels as absent will become `unknown` and therefore silent. That is the correct loss under the project's stated precision policy. Positive features can still offer best-effort results from the same incomplete inputs.

## Finding 4 — the `Billing::Order.recent.first.tracking_label` recall gap has a direct structural explanation

The current `LocalInferencer` models relation-like `#first` as:

```text
T | nil
```

Specifically, `Relation[T]#first` and `CollectionProxy[T]#first` return a Union containing `T` and `nil`.

`unknown_method_findings`, however, proceeds only when:

```ruby
receiver_type.is_a?(Types::Nominal)
```

A `Types::Union` is discarded before any method-availability question is asked.

That explains the observed asymmetry:

```ruby
Billing::Order.find(id).tracking_label
# receiver is nominal Billing::Order -> eligible for the check

Billing::Order.recent.first.tracking_label
# receiver is Billing::Order | nil -> the check exits early
```

Completion and `MethodResolver` already contain Union-aware machinery. The correct fix is therefore not a `Relation#first` special case in Diagnostics.

### Proposed correction

`MemberAvailability` should evaluate Union receivers branch by branch.

For a negative diagnostic, a safe rule is:

- report `absent` only when every non-nil reachable branch establishes absence;
- return `conditional` when the method exists only on some branches;
- return `unknown` when any branch is semantically incomplete.

How nil itself should affect the user-facing diagnostic is a separate product question (`NoMethodError` on nil may deserve its own future check), but it should not force the entire member-existence engine to refuse Union receivers.

This also gives the recall fix a structural home instead of adding another special case to `unknown_method_findings`.

## Finding 5 — metaprogrammed method surfaces cannot be made sound by adding more known DSL names

The 31 metaprogramming findings in Task 034 are a different mechanism from ancestor resolution.

`ParserService` correctly turns several known declarations into explicit generated methods (`attr_reader`, `attr_writer`, `attr_accessor`, `enum`, `scope`, `delegate`, etc.). That is useful positive information.

But a negative diagnostic needs a second fact: whether the class's method surface is closed.

Examples such as:

```ruby
attr_atomic :foo
attr_volatile :bar
singleton_class.send(:alias_method, :[], :new)
```

are not evidence that `foo`, `bar` or `[]` are absent merely because this parser does not model those macros.

Adding `attr_atomic`, then `attr_volatile`, then the next gem's DSL one at a time is precisely the local-sealing cycle this review was asked to avoid.

### Proposed correction

Track method-surface completeness separately from the methods positively discovered.

Conceptually:

```ruby
MethodSurface.new(
  known_methods: ...,
  complete: false,
  open_reasons: [:unmodelled_class_body_macro]
)
```

A class/module body containing an unaccounted-for operation capable of defining methods should make the negative method surface open unless a plugin/runtime/signature provider can close that gap.

A whitelist is appropriate here because the failure direction matters: a newly introduced unknown macro must default to silence, not to an assertion that it defines nothing.

The implementation need not classify every Ruby expression immediately. 0.2.6 can begin with the class-body operations already known to affect method definition and treat the remainder conservatively. The structural requirement is that "not modelled" becomes an explicit reason for incompleteness, not an empty contribution.

## Finding 6 — position-based internal expression inference is another local-sealing structure outside Task 034

This is outside the latest unknown-method examples but matches the review request closely.

`LocalInferencer#contains?` currently treats a Prism node's `end_offset` as inclusive. The source itself says that exclusive is the semantically correct rule, but changing it breaks many callers because internal queries have come to rely on this endpoint behavior.

Parser/reference code compensates by carefully selecting positions such as a receiver's exclusive end. Argument-type diagnostics compensate again: because asking `infer_at` at an argument's end can select a sub-expression rather than the argument itself, `operator_expression?` excludes several expression shapes instead of inferring the argument node directly.

The comments already identify the structural destination: the argument node itself, rather than a position, is the correct object to type.

### Proposed correction

Separate human-cursor lookup from internal semantic inference.

```text
infer_at(document, cursor_position)
  # LSP/Hover-style "what expression is at this cursor?"

infer_expression(document, source_range_or_node_identity)
  # internal semantic question about one exact expression
```

Diagnostics, reference resolution and method-call analysis should use the exact-expression path wherever the parser already knows the receiver/argument range.

Then changing the cursor containment convention cannot silently change the type of an internal diagnostic input. This is not required to ship the 0.2.6 unknown-method correction, but it is a strong next structural target.

## Finding 7 — `unassigned-ivar` repeats the same completeness problem outside the briefing

`Server#assigned_ivars_for` currently reconstructs completeness by a series of local refusals. It returns `nil` when, among other things:

- dynamic ivar assignment exists;
- an ancestor may not have been read;
- a class is reopened;
- a mixin contributes unknown behavior;
- a class-body call is unmodelled;
- the view renders something whose effects are not enumerated.

This is sound in direction — silence is preferred to a false report — but structurally fragile. `whole_chain_was_read?` even documents a remaining hole: it can validate the immediate parent while failing to detect an unread workspace ancestor farther up a chain such as:

```text
UsersController < BaseController < ApplicationController
```

Again, the underlying issue is that the data being passed around is "the ivars I found", while "whether this is the complete set" is reconstructed later.

### Proposed correction

The result of an enumeration intended to justify a negative diagnostic should carry completeness:

```ruby
AnalysisResult.new(
  value: assigned_ivars,
  complete: false,
  reasons: [...]
)
```

`unassigned-ivar` then becomes a pure consumer: it reports only from a complete result. The list of guards moves to the producer of the analysis result and becomes part of the result's contract rather than duplicated policy in the diagnostic caller.

This does not need to be part of 0.2.6, but it is the same architectural debt and should not be mistaken for a separate class of problem.

## Assessment of Task 034 hypotheses

### H1 — partially right, but too narrow

> `closed_nominal?` confuses "all ancestors I found are known" with "I found all ancestors".

That is a real class of defect, but the deeper mechanism begins before `closed_nominal?`: some producers discard or guess uncertainty before the chain is built, and the resulting `Array<AncestorEntry>` has no first-class completeness contract.

So moving another condition into `closed_nominal?` is not enough.

### H2 — substantially right

The metaprogramming population is a distinct mechanism from name/ancestor resolution. The common structural cure is nevertheless the same: method-surface incompleteness must survive to the negative assertion instead of being interpreted as absence.

The suggested "unrecognised class-level call makes the class not closed" is a valid conservative 0.2.6 approximation, provided it is implemented as a method-surface completeness rule rather than another special case only inside `unknown_method_findings`.

### H3 — right at the architectural boundary, not necessarily the same immediate defect

The recall gap and precision gap do not need one immediate root cause. They do show that Diagnostics and Completion independently answer member availability and therefore drift.

The unification target should be the **exact member-availability question**, not wholesale movement of all type-name resolution rules into one lower layer. That distinction matters because the earlier `024.47` rollback demonstrates that a rule safe for refusing a negative diagnostic may be too conservative for positive completion/navigation.

## Recommended 0.2.6 scope

Task 035 correctly warns against restructuring for its own sake. I would still make a small structural change here because continuing to add local guards has already demonstrated cross-consumer drift.

A patch-sized 0.2.6 can reasonably do the following:

1. **Preserve ancestor-reference uncertainty.** Dynamic `include`/`prepend`/`extend` must not disappear as if no relation existed.
2. **Carry lexical context for ancestor constant references**, or at minimum return ambiguity instead of selecting a different namespace and later claiming closure.
3. **Replace the fake `AncestorEntry(name: nil)` owner representation** with an ancestor-chain completeness/result contract, or otherwise make unresolved links impossible to feed to owner lookup APIs.
4. **Fix the existing `MethodResolver#names_for_type` nameless-entry leak immediately**, even if the larger representation change lands in the same patch.
5. **Introduce one exact-name `MemberAvailability` query** over source / model runtime facts / signatures.
6. **Move only `unknown-method` onto that query** in 0.2.6. Do not rewrite Completion enumeration at the same time.
7. **Evaluate Union receivers branch-wise**, closing the `Relation[T]#first` recall hole without a relation-specific diagnostic special case.
8. **Mark statically unaccounted-for method-definition surfaces as open** so unrecognised metaprogramming produces `unknown`, not `absent`.

### What should not be pulled into this patch

The eight platform-specific reports are an execution-reachability problem, not a method-availability problem. They need platform/reachability analysis or an explicit limitation.

The abstract-template `challenge` call is literally absent on the abstract base class. Suppressing that class of report requires a concept of abstract/template protocols and should not distort method lookup.

The two `::JSON.parse` reports were not isolated by the briefing. They should be re-measured after constant/member availability changes and only then minimized if they survive.

The internal exact-expression inference work and `unassigned-ivar` completeness work should be recorded as follow-up structural debt unless they block the 0.2.6 implementation directly.

## What would make this proposal the wrong shape

The proposal should be rejected or narrowed if reproduction shows any of the following:

1. The dominant false positives occur even when constant identity, ancestry and method-surface completeness are all demonstrably complete. In that case this is not primarily a completeness problem.
2. A shared exact-name member query cannot reuse the existing provider results without duplicating expensive full enumeration on every diagnostic call. If so, the interface should be moved lower, not abandoned; exact lookup should be cheaper than completion enumeration.
3. Preserving lexical context in `AncestorFact` materially duplicates an already-authoritative constant-reference representation. In that case `AncestorFact` should reference/reuse that representation rather than introducing a second lexical-resolution model.
4. Marking unknown class-body macros as open suppresses a large fraction of ordinary classes because the parser cannot distinguish harmless calls from method-defining calls. If measurement shows that, the boundary needs a narrower capability model, potentially with runtime/plugin evidence, rather than a blanket class-body-call rule.

## Final recommendation

Do not treat 0.2.6 as "patch the 53 false findings".

Treat it as the first patch that gives negative diagnostics a minimal proof model:

> **absence is reportable only when the semantic surface is known complete enough for absence to mean absence.**

That structure directly addresses the requested class of failures: unresolved ancestors, guessed constants, dynamic mixins, unmodelled metaprogramming and Union receivers can no longer become a high-confidence `unknown-method` finding merely because one consumer forgot the guard another consumer added.

The strongest concrete evidence that this is not theoretical is already in the current source: `MethodResolver#build_candidate` contains a local guard protecting a nameless ancestor from being interpreted as the top-level owner, while `MethodResolver#names_for_type` consumes the same `AncestorEntry` representation without that guard. The immediate bug can be patched in one line; the representation should be changed so that the bug is not writable in the first place.
