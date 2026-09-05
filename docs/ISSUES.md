# Issues

Every known defect, friction and roadmap item in this project, in one
view — and, above it, the rule for where a new one goes. `AGENTS.md`'s
"Documents and the record" lines point here.

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
| **How a release went** | `docs/design/tasks/NNN-*.md`. Narrative, per release. Findings are recorded here as they are produced; one that outlives the release goes to the intake below, and to the register once it has been driven. |
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

**Those four decisions are the command's arguments.** Once they are
made, `ruby scripts/issues.rb promote <n> --kind K --target V --area A
--direction D --user-visible yes|no [--note "…"]` takes the n-th item
out of intake — `ruby scripts/issues.rb intake` numbers them —
allocates a number never used before, writes the entry in the legend's
shape, drops the bullet, and re-runs the register's three guards. It
**refuses** each of the four rather than defaulting it: a default here
is an assertion about the product made by a script, and `024.130` is
what one of those costs. The line saying the item was never driven does
not travel with it, because promoting it is the claim that it was.

**Closing one is `ruby scripts/issues.rb close 024.N --released-in V`.**
It sets the status, moves the entry to the archive, and re-indexes — and
it **refuses while either language still publishes a paragraph for the
finding**, printing both locations. `--drop-paragraphs` is permission
for those sections to go, and then the whole `##` section goes rather
than the marker: removing the marker alone leaves the limitation
published and the guard that would report it quiet, which is the worse
of the two outcomes and the harder one to notice.

**Give it a reason written for it.** `DeferredFindings.repeated_paragraphs`
fails on any paragraph three open entries share, because a closing pass
once retargeted 54 entries with two pasted sentences between them
(`024.276`). It has already refused a commit in 0.3.0 for the same
reason.

**Deleting beats archiving a stale entry.** An entry nothing cites by
number, whose defect no longer reproduces, is removed — but grep for the
number first, and go by that rather than by the calendar.

## Intake

Something noticed and not yet driven goes here, with where it was seen
and what was seen — `ruby scripts/issues.rb intake add "<title>"
--where=W --detail=D`. It leaves for the register once it has been
driven and its kind, target and user-visibility are known — in that
order, per "The rule" above, and by its position in this list, which
`ruby scripts/issues.rb intake` prints. Nothing here has a number,
because a number is a claim that the thing exists.

- **`scripts/check_release_pointers.rb` takes any mention of a branch's
  name as naming it.** Seen in 058: a task document's record of the
  check failing on another session's local release branch quoted the
  branch, and the check passed on that sentence. What "names the branch"
  should mean mechanically — the `**Branch:**` line of a task document,
  most likely — has to be driven against the older release records
  first, some of which name their branch in prose.

- **`scripts/check_doc_links.rb`'s deletion marker is not restricted to
  records.** Seen in 058's attack round: on a live document's line the
  marker admits a citation of a deleted file, and so does a marker placed
  before a citation written in a code span. A never-existed path is still
  refused, so one marker cannot launder a typo beside a real deletion.
- **A citation of a document's section is checked by nothing.** Seen in
  058: a changelog pointer named a `docs/CODE_DISCIPLINE.md` section that
  does not hold the rule it quoted, in two rounds running, while
  `check_doc_links.rb` sees only paths.
- **`scripts/issue_index.rb` reads the documents-marker with a third grammar of its own**
  - found by: 059's diff round, reading the two readers that now share one
  - It scans the marker with its own pattern rather than through `DeferredFindings`, and that pattern cannot express a sub-numbered entry, so a published sub-entry would be counted by the register's guards and not by the generated index. Nothing has gone wrong from it yet: no sub-numbered entry is published today. Driving it means writing one and comparing the two counts.
  - unverified: not yet driven against the tree

**Four items above; the rest was emptied deliberately.** The twenty-one items that had
accumulated by 0.3.1 were driven and dispositioned in one pass:
fourteen became `024.306` through `024.319`, and seven left without a
number. The seven, and why:

| what it said | why no entry |
|---|---|
| rename leaves an underscore binding inside a pattern | `024.296` already owns it |
| `KNOWN_LIMITATIONS` has no paragraph for documentHighlight or call hierarchy | a paragraph is owed by an open finding, and documentHighlight has none; call hierarchy's is `024.297`'s |
| `LocalInferencer#locate` has no case for multi-write targets | `024.303` already owns it, published in both languages |
| `EXTENSION_CAPABILITIES`' Q1 and Q3 claim PASS for behaviour the driven cases lack | does not reproduce — `server.rb` documents both fixes |
| `024.294` and its published paragraph are false | true when written, fixed in 0.3.1 |
| `open_surface?` silences the gem-backed check on a realistic controller | `024.304` already owns it |
| four readers of the ancestor chain write the same three decisions | does not reproduce as stated |

Three of the seven were duplicates of entries already open, and two
described a tree that had moved. That ratio is the argument for
driving an item before it is given a number, rather than after.

## Index

*Generated by `scripts/issue_index.rb`. Do not edit below this line;
edit the register and run the script.*

**50 open**, 272 resolved. 37 of the open ones are user-visible, and 38 are published in `KNOWN_LIMITATIONS` (38 in Japanese).

### Open, by the release they are assigned to

**0.4.0 — 46**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.13`](design/tasks/024-deferred-review-findings.md#02413-a-reopened-core-class-looks-closed-in-both-directions) | defect | yes | yes | A reopened core class looks closed, in both directions |
| [`024.18`](design/tasks/024-deferred-review-findings.md#02418-the-unassigned-ivar-check-cannot-enumerate-what-it-needs-to) | defect | yes | yes | The unassigned-`@ivar` check cannot enumerate what it needs to |
| [`024.19`](design/tasks/024-deferred-review-findings.md#02419-the-argument-type-check-judges-against-a-class-the-receiver-is-not) | defect | yes | yes | The argument-type check judges against a class the receiver is not |
| [`024.20`](design/tasks/024-deferred-review-findings.md#02420-contains-treats-an-exclusive-end-offset-as-inclusive) | defect | yes | yes | `contains?` treats an exclusive end offset as inclusive |
| [`024.22`](design/tasks/024-deferred-review-findings.md#02422-the-unassigned-ivar-check-is-silent-in-an-application-rails-new-produces) | defect | yes | yes | The unassigned-`@ivar` check is silent in an application `rails new` produces |
| [`024.28`](design/tasks/024-deferred-review-findings.md#02428-rename-refuses-on-a-macro-declared-method-rather-than-editing-it) | defect | yes | yes | Rename refuses on a macro-declared method rather than editing it |
| [`024.37`](design/tasks/024-deferred-review-findings.md#02437-the-argument-type-check-reports-nothing-on-measured-real-ruby) | defect | yes | yes | The argument-type check reports nothing on measured real Ruby |
| [`024.38`](design/tasks/024-deferred-review-findings.md#02438-scopeat-copies-the-whole-environment-once-per-descent-step) | defect | no | — | `scope_at` copies the whole environment once per descent step |
| [`024.39`](design/tasks/024-deferred-review-findings.md#02439-localinferencer-keeps-per-request-state-and-020-gave-it-a-second-thread) | defect | no | — | `LocalInferencer` keeps per-request state, and 0.2.0 gave it a second thread |
| [`024.42`](design/tasks/024-deferred-review-findings.md#02442-a-signature-label-leaks-the-methods-own-type-variable) | defect | yes | yes | A signature label leaks the method's own type variable |
| [`024.44`](design/tasks/024-deferred-review-findings.md#02444-a-partials-local-is-not-resolved-and-c11s-stated-basis-names-it) | defect | yes | yes | A partial's local is not resolved, and C11's stated basis names it |
| [`024.45`](design/tasks/024-deferred-review-findings.md#02445-re-analysis-after-a-keystroke-is-seconds-on-a-large-file-against-a-stated-300-ms) | defect | yes | yes | Re-analysis after a keystroke is seconds on a large file, against a stated 300 ms |
| [`024.47`](design/tasks/024-deferred-review-findings.md#02447-a-namespaced-class-named-after-a-core-class-loses-its-diagnostics-and-the-readers-disagree-about-a-shadowed-literal) | defect | yes | yes | A namespaced class named after a core class loses its diagnostics, and the readers disagree about a shadowed literal |
| [`024.62`](design/tasks/024-deferred-review-findings.md#02462-two-per-file-stores-are-separated-by-nothing-but-their-payload) | defect | no | — | Two per-file stores are separated by nothing but their payload |
| [`024.71`](design/tasks/024-deferred-review-findings.md#02471-one-mutable-rails-fixture-is-shared-by-every-worker-so-the-suite-cannot-be-parallelised) | defect | no | — | One mutable Rails fixture is shared by every worker, so the suite cannot be parallelised |
| [`024.76`](design/tasks/024-deferred-review-findings.md#02476-fifty-four-unknown-method-reports-over-real-gem-source-and-all-of-them-false) | defect | yes | yes | Fifty-four `unknown-method` reports over real gem source, and all of them false |
| [`024.83`](design/tasks/024-deferred-review-findings.md#02483-the-undefined-method-check-is-loudest-exactly-where-no-runtime-agent-can-answer) | defect | yes | yes | The undefined-method check is loudest exactly where no Runtime Agent can answer |
| [`024.88`](design/tasks/024-deferred-review-findings.md#02488-completion-unions-a-unions-members-the-diagnostic-intersects-them) | defect | yes | yes | Completion unions a union's members; the diagnostic intersects them |
| [`024.100`](design/tasks/024-deferred-review-findings.md#024100-the-four-features-answer-from-different-code-paths-and-disagree-at-one-position) | defect | yes | yes | The four features answer from different code paths and disagree at one position |
| [`024.106`](design/tasks/024-deferred-review-findings.md#024106-a-modules-singleton-calls-go-unchecked-modulefunction-and-extend-self-producing-nothing-is-withdrawn) | defect | yes | yes | A module's singleton calls go unchecked — `module_function` and `extend self` producing nothing is withdrawn |
| [`024.121`](design/tasks/024-deferred-review-findings.md#024121-nothing-measures-how-much-of-this-tree-no-test-would-notice-changing) | defect | no | — | Nothing measures how much of this tree no test would notice changing |
| [`024.129`](design/tasks/024-deferred-review-findings.md#024129-no-undefined-method-report-on-a-core-library-receiver) | defect | yes | yes | No undefined-method report on a core-library receiver |
| [`024.132`](design/tasks/024-deferred-review-findings.md#024132-a-scope-defined-in-a-concerns-included-do-has-no-type) | defect | yes | yes | A scope defined in a concern's `included do` has no type |
| [`024.137`](design/tasks/024-deferred-review-findings.md#024137-workspaceindexsearch-holds-the-index-lock-for-the-whole-walk) | defect | yes | yes | `WorkspaceIndex#search` holds the index lock for the whole walk |
| [`024.151`](design/tasks/024-deferred-review-findings.md#024151-a-check-can-be-disabled-and-no-check-notices-closed-on-one-instalment-in-032-reopened) | defect | no | — | A check can be disabled, and no check notices — closed on one instalment in 0.3.2, reopened |
| [`024.221`](design/tasks/024-deferred-review-findings.md#024221-a-block-whose-receiver-cannot-be-vouched-for-contains-a-private-that-ruby-would-let-through) | defect | yes | yes | A block whose receiver cannot be vouched for contains a `private` that Ruby would let through |
| [`024.224`](design/tasks/024-deferred-review-findings.md#024224-a-type-declared-only-in-sig-is-reported-incompatible-with-itself-the-half-032-did-not-fix) | defect | yes | yes | A type declared only in `sig/` is reported incompatible with itself — the half 0.3.2 did not fix |
| [`024.237`](design/tasks/024-deferred-review-findings.md#024237-four-shapes-stopped-reporting-by-declining-on-the-body-not-by-reading-it) | defect | no | yes | Four shapes stopped reporting by declining on the body, not by reading it |
| [`024.243`](design/tasks/024-deferred-review-findings.md#024243-signature-help-says-nothing-for-a-receiverless-call-inside-a-module-body) | defect | yes | yes | Signature help says nothing for a receiverless call inside a module body |
| [`024.289`](design/tasks/024-deferred-review-findings.md#024289-a-class-that-includes-an-unread-module-is-not-checked-at-class-level-so-a-typo-there-is-silent) | friction | yes | yes | A class that includes an unread module is not checked at class level, so a typo there is silent |
| [`024.290`](design/tasks/024-deferred-review-findings.md#024290-nothing-is-reported-about-a-call-whose-receiver-is-object) | friction | yes | yes | Nothing is reported about a call whose receiver is `Object` |
| [`024.294`](design/tasks/024-deferred-review-findings.md#024294-a-templates-ivar-receiver-is-not-checked-and-its-type-is-one-actions) | defect | yes | yes | A template's `@ivar` receiver is not checked, and its type is one action's |
| [`024.295`](design/tasks/024-deferred-review-findings.md#024295-the-gem-index-is-fetched-on-every-boot-and-persisted-nowhere) | defect | yes | yes | The gem index is fetched on every boot and persisted nowhere |
| [`024.297`](design/tasks/024-deferred-review-findings.md#024297-call-hierarchy-lists-no-callee-reached-through-send-super-or-a-macro) | defect | yes | yes | Call hierarchy lists no callee reached through `send`, `super` or a macro |
| [`024.298`](design/tasks/024-deferred-review-findings.md#024298-an-inlay-hint-on-foonew-names-news-parameters-not-initializes) | defect | yes | yes | An inlay hint on `Foo.new(...)` names `new`'s parameters, not `initialize`'s |
| [`024.299`](design/tasks/024-deferred-review-findings.md#024299-completion-on-a-relation-offers-none-of-the-models-own-scopes-or-class-methods) | friction | yes | yes | Completion on a relation offers none of the model's own scopes or class methods |
| [`024.300`](design/tasks/024-deferred-review-findings.md#024300-ivar-completion-offers-nothing-from-a-superclass-or-an-included-concern) | friction | yes | yes | `@ivar` completion offers nothing from a superclass or an included concern |
| [`024.301`](design/tasks/024-deferred-review-findings.md#024301-the-route-helper-quick-fix-ignores-the-pathurl-split-and-the-helpers-arity) | defect | yes | yes | The route-helper quick fix ignores the `_path`/`_url` split and the helper's arity |
| [`024.302`](design/tasks/024-deferred-review-findings.md#024302-the-def-quick-fix-is-offered-for-one-receiver-shape-of-three) | friction | yes | yes | The `def` quick fix is offered for one receiver shape of three |
| [`024.303`](design/tasks/024-deferred-review-findings.md#024303-a-multiple-assignments-targets-get-no-inlay-hint) | friction | yes | yes | A multiple assignment's targets get no inlay hint |
| [`024.304`](design/tasks/024-deferred-review-findings.md#024304-the-gem-backed-check-is-silenced-by-any-class-body-call-the-parser-cannot-read) | friction | yes | yes | The gem-backed check is silenced by any class-body call the parser cannot read |
| [`024.318`](design/tasks/024-deferred-review-findings.md#024318-a-workspace-directory-shaped-like-a-gem-path-would-be-attributed-to-a-gem) | defect | no | — | A workspace directory shaped like a gem path would be attributed to a gem |
| [`024.319`](design/tasks/024-deferred-review-findings.md#024319-a-bare-name-no-signature-declares-is-still-read-as-the-one-gem-class-sharing-its-last-segment) | defect | yes | yes | A bare name no signature declares is still read as the one gem class sharing its last segment |
| [`024.320`](design/tasks/024-deferred-review-findings.md#024320-no-check-knows-which-lock-guards-what) | friction | no | — | No check knows which lock guards what |
| [`024.321`](design/tasks/024-deferred-review-findings.md#024321-a-stdlib-class-can-be-answered-about-but-not-judged-against-the-half-040-left) | defect | yes | yes | A stdlib class can be answered about but not judged against — the half 0.4.0 left |
| [`024.322`](design/tasks/024-deferred-review-findings.md#024322-the-server-never-passes-bundlecontext-so-gem-rbs-is-never-loaded----while-the-cache-fingerprint-hashes-the-lockfile-that-decides-it) | defect | yes | yes | The server never passes bundle_context, so gem RBS is never loaded -- while the cache fingerprint hashes the lockfile that decides it |

**1.0.0 — 4**

| # | kind | user-visible | published | what |
|---|---|---|---|---|
| [`024.R1`](design/tasks/024-deferred-review-findings.md#024r1-rails-specific-behaviour-has-no-explicit-boundary-roadmap-100) | roadmap |  | — | Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0) |
| [`024.R3`](design/tasks/024-deferred-review-findings.md#024r3-feature-parity-roadmap-measured-against-pylance) | roadmap |  | — | Feature parity roadmap, measured against Pylance |
| [`024.R4`](design/tasks/024-deferred-review-findings.md#024r4-only-one-platform-is-published-or-verified-roadmap-100) | roadmap |  | — | Only one platform is published or verified (roadmap, 1.0.0) |
| [`024.R10`](design/tasks/024-deferred-review-findings.md#024r10-the-repository-is-closed-to-external-contributions-until-100-roadmap-100) | roadmap |  | — | The repository is closed to external contributions until 1.0.0 (roadmap, 1.0.0) |

### Open, user-visible, and not published

None. Every open user-visible entry carries a `<!-- documents: -->`
marker in both languages.
