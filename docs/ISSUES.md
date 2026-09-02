# Issues

Every known defect, friction and roadmap item in this project, in one
view — and, above it, the rule for where a new one goes.

The list itself is **generated** by `scripts/issue_index.rb` from the
documents that already hold the issues. Nothing below `## Index` is
hand-written, and nothing here is a second copy of anything: a
consolidated document that restated the register would be a second place
to keep right, and this repository has lost a release to two documents
disagreeing before.

## Where an issue lives

| | |
|---|---|
| **The store** | [`docs/design/tasks/024-deferred-review-findings.md`](design/tasks/024-deferred-review-findings.md) for open entries, [`…-resolved.md`](design/tasks/024-deferred-review-findings-resolved.md) for closed ones. One numbered entry per issue. `DeferredFindings.register` is the only reader that knows about the split — anything reading the live file alone loses three-quarters of them. |
| **What users are told** | [`docs/KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) and its `.ja` twin, one paragraph per issue a user can meet, each ending in `<!-- documents: 024.N -->`. |
| **What the product promises** | [`docs/EXTENSION_CAPABILITIES.md`](EXTENSION_CAPABILITIES.md) and its `.ja` twin. A row here is a promise with an E2E example behind it. |
| **How a release went** | `docs/design/tasks/NNN-*.md`. Narrative, per release. Findings are recorded here as they are produced, then given a register number if they outlive the release. |
| **Not yet triaged** | The intake list below. |

## The rule

**A new issue starts in the intake list, not in the register.** The
register's entries carry a status, a kind, a target and a user-visible
flag, and `deferred_findings_spec` enforces every one of them — an entry
added before those are known is an entry that has to be corrected later,
in a file where a correction costs a re-index.

Moving one out of intake and into the register means deciding four
things, and the honest order is:

1. **Does it reproduce?** Drive it on the current tree, with a control in
   the same fixture. `024.130` was published as a limitation the product
   did not have because a split promoted nine bullets without running
   one, so this is first and it is not optional.
2. **What kind is it?** A wrong answer is a `defect`; the engine
   declining where it could answer is `friction`; a capability nobody
   was promised is `roadmap`.
3. **Which release?** [`docs/PUBLISHING.md`](PUBLISHING.md)'s table
   decides it: a repair belongs on the patch line, a silence turned into
   an answer is capability and belongs in a minor, and this repository's
   own checks, record and cost are neither and go on the patch line.
4. **Can a user meet it?** If yes it needs a paragraph in
   `KNOWN_LIMITATIONS` in **both** languages, and the marker that pairs
   them.

**Give it a reason written for it.** `DeferredFindings.repeated_paragraphs`
fails on any paragraph three open entries share, because a closing pass
once retargeted 54 entries with two pasted sentences between them
(`024.276`). It has already refused a commit in 0.3.0 for the same
reason.

**Deleting beats archiving a stale entry.** An entry nothing cites by
number, whose defect no longer reproduces, is removed — but grep for the
number first, and go by that rather than by the calendar.

## Intake

Issues found but not yet triaged into the register. Anything here is
unverified: it has been *noticed*, not driven.

Each carries where it was found and what makes it out of scope for the
release that found it. Empty means everything found has been triaged.

- **An underscore binding inside a pattern is left behind by rename, and no open entry owns it**
  - found by: 0.3.0's stale-marker sweep
  - 024.274 fixed the masgn/for/rescue forms and is archived, but the pattern form is still declined on purpose (Ruby lets one pattern bind the name twice). The KNOWN_LIMITATIONS paragraph now carries no marker because a resolved entry may not own one. Needs its own entry, kind friction, once driven.
  - unverified: not yet driven against the tree
- **The 0.3.0 release record states as measured a claim the resolver contradicts**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: docs/design/tasks/054-0.3.0-the-first-release-that-adds.md, section "One of the four turned out to be dead, and was removed"
  - The record says: "Probed: a `:method_call` candidate resolves to a method kind or to nothing — never to a constant or a class ... Removed rather than pinned." `ReferenceResolver` resolves a `:method_call` candidate to `:route_helper` and to `:active_record_col…
  - unverified: reported by a reviewer, not driven
- **KNOWN_LIMITATIONS carries no paragraph for documentHighlight or call hierarchy**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: docs/KNOWN_LIMITATIONS.md and docs/KNOWN_LIMITATIONS.ja.md
  - Neither language file mentions either 0.3.0 capability. If any of the findings above ships open, the release rule requires a register entry plus a user-facing paragraph in both. Out of scope to edit (docs/).
  - unverified: reported by a reviewer, not driven
- **capabilities_spec's F1/F2 and W5/W6 fixtures cannot see six of the findings above**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/spec/e2e/capabilities_spec.rb, the "in the current file" describe block and W5/W6
  - No example uses a namespaced constant, an instance variable, a route helper, a symbol declared twice in one file, nested `def`s on a single line, or a `prepareCallHierarchy` issued at a call site rather than a `def`. This file is editable, so the coverage belo…
  - unverified: reported by a reviewer, not driven
- **`ReferenceResolver#resolve` has no stated contract about alignment, and its one aligned caller assumed one**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/semantic/reference_resolver.rb:43-45
  - `resolve` is `candidates.filter_map { |candidate| resolve_candidate(...) }` and is documented nowhere as "the result is not positionally aligned with the input". Its three pre-0.3.0 callers all happen to avoid the assumption (two pass a single-element array an…
  - unverified: reported by a reviewer, not driven
- **`LocalInferencer#locate` has no case for multi-write targets**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/local_inferencer.rb:436-495
  - The `gap` finding about `a, b = 1, 2` bottoms out here: `locate`'s `when` list covers `LocalVariableWriteNode` and `InstanceVariableWriteNode` but not `MultiWriteNode`, so the default branch descends to the `LocalVariableTargetNode` and `eval_type` answers `Ty…
  - unverified: reported by a reviewer, not driven
- **The E2E example that drives the one-line class asserts only that the result parses**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/spec/e2e/capabilities_spec.rb:916-948 ("Q1: inserts into the right body when the class's end is not the first one")
  - The example drives three shapes and asserts `Prism.parse(applied).success?` for each, plus `expect(driven).to match_array(shapes.keys)` so a shape cannot pass by skipping. Both of those are good. But parseability cannot distinguish "the def landed in the class…
  - unverified: reported by a reviewer, not driven
- **`expected_arity` pluralises on `maximum` alone, so a range with maximum 1 reads "takes 0..1 argument"**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/diagnostics/engine.rb:695-698
  - `"#{count}#{...} argument#{maximum == 1 ? '' : 's'}"`. When `required != maximum` the count is a range and the plural should follow the range, not its upper bound. Observed while driving the arity probe: `def opt(a = 1)` called with three arguments produces "`…
  - unverified: reported by a reviewer, not driven
- **`docs/EXTENSION_CAPABILITIES.md` rows Q1 and Q3 claim PASS for behaviour the driven cases do not have**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: docs/EXTENSION_CAPABILITIES.md:247, 249
  - Q1 reads "a `def` for it is inserted into the class the call was made on" — for a one-line class it is inserted after that class. Q3 reads "the surplus arguments are removed" — for a callee whose minimum arity is 0 nothing is removed, and for a `N..M` arity a …
  - unverified: reported by a reviewer, not driven
- **`Index::ReferenceCandidate`'s documentation of `arguments` omits `positional_locations`**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/index/reference_candidate.rb:48-52
  - The comment says the shape is `{ positional:, splat:, keywords:, block: }`. `ParserService#call_argument_shape` also records `positional_locations:`, which now has four readers (the argument-type check, inlay hints, the surplus-argument action, and `diagnostic…
  - unverified: reported by a reviewer, not driven
- **`024.294` and the KNOWN_LIMITATIONS paragraph it documents are both false against release/0.3.0**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: docs/design/tasks/024-deferred-review-findings.md:4504, docs/KNOWN_LIMITATIONS.md:834
  - The register entry says "Diagnostics do not act on an `@ivar` receiver, even where hover and completion know its type" and, in bold, "**This is a silence, not a wrong answer**, which is why it is a `0.3.1` and not a blocker". The shipped paragraph repeats it: …
  - unverified: reported by a reviewer, not driven
- **`docs/design/tasks/054-0.3.0-the-first-release-that-adds.md` records one direction of the instance/singleton ivar split and not the other**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: docs/design/tasks/054-0.3.0-the-first-release-that-adds.md:609
  - The release record has "**Instance-side completion offered the class object's variables.** The walk took every `def` in the body, so an `@x` written in `def self.build` was offered inside instance methods, where reading it gives `nil`." That is the direction f…
  - unverified: reported by a reviewer, not driven
- **open_surface? silences the gem-backed check on every realistic Rails controller**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/index/workspace_index.rb (open_surface_owners), set by the parser
  - The headline case for feature 8 is "a controller inherits from ApplicationController, whose parent is in a gem". Driven against real ActionPack, a controller works only if `ApplicationController`'s body is empty. Add the two lines every real one has — `before_…
  - unverified: reported by a reviewer, not driven
- **GEM_PATH would attribute a workspace directory that looks like a gem path**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/runtime_agent/agent.rb (GEM_PATH), interacting with bundler layouts
  - `%r{/gems/(?<gem>[^/]+-[0-9][^/]*)/}` matches anywhere in the const_source_location path. A monorepo that keeps local engines under `gems/billing-1.0/` would have its own classes attributed to a "gem", which makes workspace code `knows?`-true and therefore clo…
  - unverified: reported by a reviewer, not driven
- **`record_assigned_struct_members` has four comment lines at the wrong indentation**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/parser_service.rb, in `record_assigned_struct_members` (the `names = Array(value.arguments&.arguments)` chain and the comment above it)
  - Inside the method, the comment beginning "`SymbolNode` only." starts at 8 spaces and its three continuation lines sit at 4 spaces, and the `names = ...` assignment and its chained `.select`/`.filter_map` are indented to match the 4-space block rather than the …
  - unverified: reported by a reviewer, not driven
- **The `SCHEMA_VERSION` comment documents a version 7 that does not exist**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/cache/key.rb, the comment block immediately above `SCHEMA_VERSION = 6`
  - `Cache::Key::SCHEMA_VERSION` is 6, and the comment above it carries a numbered entry "7: `ReferenceCandidate` is unchanged, but 0.3.0 also added `singletonAncestors` ... Left at 6 deliberately". Numbering a note about a bump that was *not* made in the same lis…
  - unverified: reported by a reviewer, not driven
- **Inlay hints now label block parameters, which the release note does not describe**
  - found by: the 0.3.0 review workflow, out of its scope
  - where: core/lib/ovallsp/server.rb `local_type_hints`; reproduce by driving `textDocument/inlayHint` over `"[1, 2].each { |n| n }\n"`
  - Because parameter binding sites are recorded as writes, `Server#local_type_hints` (server.rb:2402-2414) picks them up: `[1, 2].each { |n| n }` renders as `[1, 2].each { |n: Integer| n }`. I could not make it produce a *wrong* label -- `def f(a)` and `def f(a =…
  - unverified: reported by a reviewer, not driven
- **Two lines in `incoming_calls_result` each drop a top-level call, and neither can be distinguished alone**
  - found by: 0.3.0's post-workflow mutation sweep
  - where: core/lib/ovallsp/server.rb, `next unless enclosing` and the render's `declarations.find ... or next`
  - Measured: mutating either alone leaves both W5 examples green; mutating both fails them. So one is redundant as the code stands, and `pinned_mutations.yml` now pins the pair rather than pretending to pin a line. Deciding which to remove needs the call-hierarchy design, not a review round.
  - unverified: the redundancy is measured; which line should go is not decided
- **A bare name RBS does not declare is still reinterpreted as the one gem class sharing its last segment**
  - found by: core/lib/ovallsp/semantic/hierarchy_index.rb#canonical_name, core/lib/ovallsp/semantic/gem_index.rb#resolve_simple_name
  - 0.3.0 stopped a gem's nested class from claiming a core name by asking the signature environment whether the bare name already denotes something. That leaves the rule intact for every name RBS has not heard of, which is where it was needed (Relation -> ActiveRecord::Relation) and also where it can still be wrong: a class the user wrote and the workspace index has not got is indistinguishable from a name nothing claims, so a gem's SomeGem::Config would answer for a bare Config. Not driven -- what is needed is a workspace whose own class is missing from the index at the moment the question is asked, and whether that state is reachable at all is the first thing to establish.
  - unverified: not yet driven against the tree
- **Four readers of the ancestor chain each write the same three decisions out by hand**
  - found by: core/lib/ovallsp/semantic/hierarchy_index.rb, and its four callers that walk #ancestors
  - A fix-stage worktree from 0.3.0's review workflow proposed HierarchyIndex#links: one walk that skips an unidentified link, asks AncestorEntry#declaration_kind which side of the link the chain reaches, and numbers a link by its position in the whole chain rather than in the surviving subset. Four call sites currently write those three out separately, which is the shape CLAUDE.md's same-place rule calls for a countermeasure over. It did not land in 0.3.0 and nothing is known to be wrong because of it -- so this is a candidate, not a defect, and DTSTTCPW's own warning applies: 048 produced eight simplifications of working code and every one failed measurement. What would settle it is whether the four readers really want the same answer. The worktree that holds the attempt is .claude/worktrees/wf_ed17cf22-643-3, which is disposable; the idea is what is worth keeping.
  - unverified: not yet driven against the tree
<!-- intake: none -->

*(No untriaged issues.)*

## Index

*Generated by `scripts/issue_index.rb`. Do not edit below this line;
edit the register and run the script.*

**48 open**, 252 resolved. 37 of the open ones are user-visible, and 38 are published in `KNOWN_LIMITATIONS` (38 in Japanese).

### Open, by the release they are assigned to

**0.4.0 — 23**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.18`](design/tasks/024-deferred-review-findings.md#02418-the-unassigned-ivar-check-cannot-enumerate-what-it-needs-to) | defect | yes | yes | The unassigned-`@ivar` check cannot enumerate what it needs to |
| [`024.20`](design/tasks/024-deferred-review-findings.md#02420-contains-treats-an-exclusive-end-offset-as-inclusive) | defect | yes | yes | `contains?` treats an exclusive end offset as inclusive |
| [`024.22`](design/tasks/024-deferred-review-findings.md#02422-the-unassigned-ivar-check-is-silent-in-an-application-rails-new-produces) | defect | yes | yes | The unassigned-`@ivar` check is silent in an application `rails new` produces |
| [`024.28`](design/tasks/024-deferred-review-findings.md#02428-rename-refuses-on-a-macro-declared-method-rather-than-editing-it) | defect | yes | yes | Rename refuses on a macro-declared method rather than editing it |
| [`024.44`](design/tasks/024-deferred-review-findings.md#02444-a-partials-local-is-not-resolved-and-c11s-stated-basis-names-it) | defect | yes | yes | A partial's local is not resolved, and C11's stated basis names it |
| [`024.83`](design/tasks/024-deferred-review-findings.md#02483-the-undefined-method-check-is-loudest-exactly-where-no-runtime-agent-can-answer) | defect | yes | yes | The undefined-method check is loudest exactly where no Runtime Agent can answer |
| [`024.88`](design/tasks/024-deferred-review-findings.md#02488-completion-unions-a-unions-members-the-diagnostic-intersects-them) | defect | yes | yes | Completion unions a union's members; the diagnostic intersects them |
| [`024.100`](design/tasks/024-deferred-review-findings.md#024100-the-four-features-answer-from-different-code-paths-and-disagree-at-one-position) | defect | yes | yes | The four features answer from different code paths and disagree at one position |
| [`024.106`](design/tasks/024-deferred-review-findings.md#024106-modulefunction-and-extend-self-produce-nothing) | defect | yes | yes | `module_function` and `extend self` produce nothing |
| [`024.129`](design/tasks/024-deferred-review-findings.md#024129-no-undefined-method-report-on-a-core-library-receiver) | defect | yes | yes | No undefined-method report on a core-library receiver |
| [`024.132`](design/tasks/024-deferred-review-findings.md#024132-a-scope-defined-in-a-concerns-included-do-has-no-type) | defect | yes | yes | A scope defined in a concern's `included do` has no type |
| [`024.237`](design/tasks/024-deferred-review-findings.md#024237-four-shapes-stopped-reporting-by-declining-on-the-body-not-by-reading-it) | defect | no | yes | Four shapes stopped reporting by declining on the body, not by reading it |
| [`024.243`](design/tasks/024-deferred-review-findings.md#024243-signature-help-says-nothing-for-a-receiverless-call-inside-a-module-body) | defect | yes | yes | Signature help says nothing for a receiverless call inside a module body |
| [`024.289`](design/tasks/024-deferred-review-findings.md#024289-a-class-that-includes-an-unread-module-is-not-checked-at-class-level-so-a-typo-there-is-silent) | friction | yes | yes | A class that includes an unread module is not checked at class level, so a typo there is silent |
| [`024.290`](design/tasks/024-deferred-review-findings.md#024290-nothing-is-reported-about-a-call-whose-receiver-is-object) | friction | yes | yes | Nothing is reported about a call whose receiver is `Object` |
| [`024.297`](design/tasks/024-deferred-review-findings.md#024297-call-hierarchy-lists-no-callee-reached-through-send-super-or-a-macro) | defect | yes | yes | Call hierarchy lists no callee reached through `send`, `super` or a macro |
| [`024.298`](design/tasks/024-deferred-review-findings.md#024298-an-inlay-hint-on-foonew-names-news-parameters-not-initializes) | defect | yes | yes | An inlay hint on `Foo.new(...)` names `new`'s parameters, not `initialize`'s |
| [`024.299`](design/tasks/024-deferred-review-findings.md#024299-completion-on-a-relation-offers-none-of-the-models-own-scopes-or-class-methods) | friction | yes | yes | Completion on a relation offers none of the model's own scopes or class methods |
| [`024.300`](design/tasks/024-deferred-review-findings.md#024300-ivar-completion-offers-nothing-from-a-superclass-or-an-included-concern) | friction | yes | yes | `@ivar` completion offers nothing from a superclass or an included concern |
| [`024.301`](design/tasks/024-deferred-review-findings.md#024301-the-route-helper-quick-fix-ignores-the-pathurl-split-and-the-helpers-arity) | defect | yes | yes | The route-helper quick fix ignores the `_path`/`_url` split and the helper's arity |
| [`024.302`](design/tasks/024-deferred-review-findings.md#024302-the-def-quick-fix-is-offered-for-one-receiver-shape-of-three) | friction | yes | yes | The `def` quick fix is offered for one receiver shape of three |
| [`024.303`](design/tasks/024-deferred-review-findings.md#024303-a-multiple-assignments-targets-get-no-inlay-hint) | friction | yes | yes | A multiple assignment's targets get no inlay hint |
| [`024.304`](design/tasks/024-deferred-review-findings.md#024304-the-gem-backed-check-is-silenced-by-any-class-body-call-the-parser-cannot-read) | friction | yes | yes | The gem-backed check is silenced by any class-body call the parser cannot read |

**0.3.2 — 19**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.13`](design/tasks/024-deferred-review-findings.md#02413-a-reopened-core-class-looks-closed-in-both-directions-03x) | defect | yes | yes | A reopened core class looks closed, in both directions (0.3.x) |
| [`024.19`](design/tasks/024-deferred-review-findings.md#02419-the-argument-type-check-judges-against-a-class-the-receiver-is-not) | defect | yes | yes | The argument-type check judges against a class the receiver is not |
| [`024.37`](design/tasks/024-deferred-review-findings.md#02437-the-argument-type-check-reports-nothing-on-measured-real-ruby) | defect | yes | yes | The argument-type check reports nothing on measured real Ruby |
| [`024.38`](design/tasks/024-deferred-review-findings.md#02438-scopeat-copies-the-whole-environment-once-per-descent-step) | defect | no | — | `scope_at` copies the whole environment once per descent step |
| [`024.39`](design/tasks/024-deferred-review-findings.md#02439-localinferencer-keeps-per-request-state-and-020-gave-it-a-second-thread) | defect | no | — | `LocalInferencer` keeps per-request state, and 0.2.0 gave it a second thread |
| [`024.42`](design/tasks/024-deferred-review-findings.md#02442-an-rbs-signature-label-says-unknown-where-rbs-says-self-and-leaks-method-type-variables) | defect | yes | yes | An RBS signature label says `Unknown` where RBS says `self`, and leaks method type variables |
| [`024.45`](design/tasks/024-deferred-review-findings.md#02445-re-analysis-after-a-keystroke-is-seconds-on-a-large-file-against-a-stated-300-ms) | defect | yes | yes | Re-analysis after a keystroke is seconds on a large file, against a stated 300 ms |
| [`024.47`](design/tasks/024-deferred-review-findings.md#02447-a-namespaced-class-named-after-a-core-class-loses-its-diagnostics-and-the-readers-disagree-about-a-shadowed-literal) | defect | yes | yes | A namespaced class named after a core class loses its diagnostics, and the readers disagree about a shadowed literal |
| [`024.62`](design/tasks/024-deferred-review-findings.md#02462-two-per-file-stores-are-separated-by-nothing-but-their-payload) | defect | no | — | Two per-file stores are separated by nothing but their payload |
| [`024.71`](design/tasks/024-deferred-review-findings.md#02471-one-mutable-rails-fixture-is-shared-by-every-worker-so-the-suite-cannot-be-parallelised) | defect | no | — | One mutable Rails fixture is shared by every worker, so the suite cannot be parallelised |
| [`024.76`](design/tasks/024-deferred-review-findings.md#02476-fifty-four-unknown-method-reports-over-real-gem-source-and-all-of-them-false) | defect | yes | yes | Fifty-four `unknown-method` reports over real gem source, and all of them false |
| [`024.121`](design/tasks/024-deferred-review-findings.md#024121-nothing-measures-how-much-of-this-tree-no-test-would-notice-changing) | defect | no | — | Nothing measures how much of this tree no test would notice changing |
| [`024.137`](design/tasks/024-deferred-review-findings.md#024137-workspaceindexsearch-scans-every-symbol-in-the-workspace) | defect | yes | yes | `WorkspaceIndex#search` scans every symbol in the workspace |
| [`024.151`](design/tasks/024-deferred-review-findings.md#024151-a-check-can-be-disabled-and-no-check-notices) | defect | no | — | A check can be disabled, and no check notices |
| [`024.221`](design/tasks/024-deferred-review-findings.md#024221-a-block-whose-receiver-cannot-be-vouched-for-contains-a-private-that-ruby-would-let-through) | defect | yes | yes | A block whose receiver cannot be vouched for contains a `private` that Ruby would let through |
| [`024.224`](design/tasks/024-deferred-review-findings.md#024224-a-namespaced-type-is-reported-incompatible-with-itself) | defect | yes | yes | A namespaced type is reported incompatible with itself |
| [`024.283`](design/tasks/024-deferred-review-findings.md#024283-the-packaged-core-is-driven-only-on-linux-so-the-macos-build-is-still-smoke-tested) | defect | yes | yes | The packaged Core is driven only on Linux, so the macOS build is still smoke-tested |
| [`024.288`](design/tasks/024-deferred-review-findings.md#024288-ruby-40-puts-a-fourth-name-on-object-that-rbs-does-not-declare) | defect | yes | yes | Ruby 4.0 puts a fourth name on Object that RBS does not declare |
| [`024.296`](design/tasks/024-deferred-review-findings.md#024296-renaming-a-local-a-pattern-also-binds-rewrites-the-rest-and-leaves-the-pattern) | defect | yes | yes | Renaming a local a pattern also binds rewrites the rest and leaves the pattern |

**0.3.1 — 2**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.294`](design/tasks/024-deferred-review-findings.md#024294-diagnostics-do-not-act-on-an-ivar-receiver-even-where-hover-and-completion-know-its-type) | defect | yes | yes | Diagnostics do not act on an `@ivar` receiver, even where hover and completion know its type |
| [`024.295`](design/tasks/024-deferred-review-findings.md#024295-the-gem-index-is-fetched-on-every-boot-and-persisted-nowhere) | defect | yes | yes | The gem index is fetched on every boot and persisted nowhere |

**1.0.0 — 2**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.R1`](design/tasks/024-deferred-review-findings.md#024r1-rails-specific-behaviour-has-no-explicit-boundary-roadmap-100) | roadmap |  | — | Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0) |
| [`024.R4`](design/tasks/024-deferred-review-findings.md#024r4-only-one-platform-is-published-or-verified-roadmap-100) | roadmap |  | — | Only one platform is published or verified (roadmap, 1.0.0) |

**unscheduled — 2**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.R3`](design/tasks/024-deferred-review-findings.md#024r3-feature-parity-roadmap-measured-against-pylance) | roadmap |  | — | Feature parity roadmap, measured against Pylance |
| [`024.275`](design/tasks/024-deferred-review-findings.md#024275-a-workspace-identity-example-fails-only-in-a-full-suite-run-and-not-reproducibly) | defect | no | — | A workspace-identity example fails only in a full-suite run, and not reproducibly |

### Open, user-visible, and not published

None. Every open user-visible entry carries a `<!-- documents: -->`
marker in both languages.
