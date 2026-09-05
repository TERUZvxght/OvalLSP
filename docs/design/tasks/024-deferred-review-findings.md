# Task 024: Deferred review findings

Findings from independent review that were deliberately **not** fixed in
the change set they were found in, because fixing them would have widened
that change set beyond what its own goal required.

**This is the single place deferred findings are collected.**
[`024-deferred-review-findings-resolved.md`](024-deferred-review-findings-resolved.md)
is the other half of *this* register and not a second one — resolving an
entry moves it there, the index below carries both, and
`DeferredFindings.register` is what every check reads. `024.R9` and the
measurement behind the split are in the archive's own header. Do not open
a third file, and do not scatter `TODO` comments through the source for
them — an item that is worth deferring is worth being findable in one
place. Append new entries here; remove an entry only when it is actually
fixed, and say in the fixing commit which entry it closes.

Each entry states the symptom, who it affects, how to reproduce it, and a
proposed direction. Nothing here is a shipping blocker; every item was
triaged as such by the reviewer that raised it.

Every entry opens with a fenced `yaml` block, directly under its
heading, and that block is the entry's status — the prose beneath it adds
narrative and does not restate it:

```yaml
status: open        # open | fixed | done. Anything else reads as open.
kind: defect        # defect | roadmap | friction. See below.
released-in: 0.1.14 # only on a resolved entry
user-visible: yes   # on an open defect: does a user see this?
target: 0.2.4       # optional on an open entry: the release its fix is routed to
```

**`kind`** is one of three. **`defect`** is a fault in what the product
answers. **`roadmap`** is a plan, not a fault. **`friction`** is
something that made *working in this repository* harder — a document that
misled, a name that had to be looked up twice, a step whose order was not
obvious, a check whose failure did not say what to do. It is a first-class
kind rather than a `defect` with `user-visible: no` because the two are
triaged differently and by different people: a user never meets friction,
and only somebody working here can report it.

**Anyone may raise one — planner, implementer or reviewer — and raising
one without recording it is not allowed.** A finding that is mentioned in
a message and not written down here is lost at the next compaction, which
is how `024.109`'s two unnamed examples were lost and how `024.122`'s own
first count survived a release. If it was worth saying, it is worth an
entry; an entry costs four lines.

A friction entry needs no `user-visible` half — it is `user-visible: no`
with a note, like any other entry a user does not meet.

An open defect with `user-visible: yes` must be cited by number in
`docs/KNOWN_LIMITATIONS.md` **and** `.ja.md`, so a finding recorded here
reaches the people it affects. An entry with no user-visible half says
`user-visible: no` and a `user-visible-note` giving the reason.
`core/spec/meta/deferred_findings_spec.rb` checks all of that, and fails
on an entry whose heading carries no block rather than skipping it.

The block exists because the previous attempt at this check parsed the
file's *prose* and had to be rolled back — 024.25 records why, and this
format is the direction that entry recommended.

**One entry states one defect, with one Area and one reproduction.**
`024.90` held nine, under one `user-visible: yes` and one anchor — and
that anchor documented seven of them, so two live defects were documented
nowhere while the guard read green. A number cited once covers everything
filed under it, which is why nine cannot share one. Not machine-checked:
a rule counting bullets would be guessing at intent.

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

**`024.61` does not exist.** The 0.2.4-bound branch's round 37 renumbered
two entries that had both landed as `024.60`, and the number it vacated
was never reused. The guard below rejects a duplicate and says nothing
about a gap, deliberately: numbers are cited from source and specs, so
reusing a vacated one is the dangerous move and leaving a hole is the
safe one. Take the next number after the highest, never the first free
one. In this unified register the gap exists for the same reason, and the
numbering continues after the highest number *either* line has used.
`024.64` and `024.65` were the reserved pair while the two lines were
apart; they are here now, with the rest of that branch's entries, and
the hole at `024.61` stays a hole.

**`024.70` does not exist either**, for a different reason and under
the same rule. It was written during 0.2.3's pre-publish gate,
claiming the packaging step's native-extension path warning could not
see a Homebrew-built VSIX — and withdrawn the same session, because
the warning does see it and had already said so. The claim came from
re-running the gate's own `grep` in a shell where the name resolves to
a `ugrep` wrapper that skips binary files without `-a`; the gate gets
`/usr/bin/grep`, which does not. `028`'s "A second finding that was the
measurement, not the tree" records it, because a withdrawn finding is
worth as much as a kept one when the thing it caught was the method.
The number stays vacant.

**The two lines are one register again.** Entries `024.51`–`024.54`,
`024.57`, `024.58`, `024.64` and `024.65` were written on the branch
that carried 0.2.4's engine thread and are merged in here unchanged,
with that thread, by 0.2.4's `M-1`. That branch's own `024.49` — the red
toast 0.2.1 removed still being shown from `compareVersionInfo` — held a
number this register had already spent on something else, so it is
**`024.72`** here, per the rule three paragraphs up: the next number
after the highest, never a free or vacated one. Five source and spec
comments in `vscode/src` cite it and were renumbered with it — found by
grepping rather than assumed, which is the point of the rule that says an
entry is not deleted or renumbered while the tree still names it.

Entries numbered `024.R*` are roadmap items rather than defects: work
that is understood, deliberately not scheduled for the current release,
and too large to fold into one. They live here rather than in a separate
roadmap file for the same reason everything else does — one place.

---

## Retired numbers

**320 entries below** <!-- measured: register-entries = 320 -->,
counted by `core/spec/meta/measured_claims_spec.rb` rather than by hand.
The marker lives here rather than in the Index, which
`scripts/reindex_findings.rb` regenerates and would strip it from.


An entry is deleted once nothing in the tree still cites it, and the
legend says to grep before deleting rather than going by the calendar.
That grep was skipped, repeatedly: **25 citations across source
comments, spec comments, the VS Code extension, a task record and both
changelogs point at numbers that are not here** — `024.67` recorded seven
of them and undercounted by eighteen.

The first version of the guard that replaced the grep undercounted too:
it scanned `core/lib`, `core/spec`, `vscode/src` and `docs`, and missed
both changelogs — which `024.67`'s own **Area** list names. A review
round ran the guard's logic over the files it could not see and found
`024.5` cited in both, unrecovered, in the same sentence as three numbers
the table did have. The scan now covers every tracked text file.

A pointer to a reason is worth having, so the numbers resolve again,
here. Each names what the entry said; the reason itself is in the
comment that cites it, which is where a reader is standing.

| # | what it recorded |
|---|---|
| `024.2` | `Hash.new` / `Set.new` hover as `Hash[Unknown]` / `Set[Unknown]` |
| `024.3` | an `untyped` RBS singleton signature still shadows source resolution |
| `024.4` | `BeforeActionFinder#record` mutates the Prism AST in place |
| `024.5` | `Server#index_references` is dead |
| `024.7` | `rootIdentity`'s refresh assignment cannot affect any decision |
| `024.9` | a forced crash popup can still appear for deliberate stops |
| `024.12` | a hash literal and `Hash.new` still render differently |
| `024.61` | nothing — vacated by the renumber described above and never reused. A row here rather than prose alone, because the citation guard now reads this file too (`024.183`) and the paragraphs explaining the hole cite the number they explain |
| `024.70` | withdrawn, not fixed — the packaged-VSIX path warning was not blind; the re-run that "disproved" it went through a `ugrep` wrapper that skips binary files without `-a`. See CLAUDE.md's "A tool with the right name is not necessarily the tool under test" |

`core/spec/meta/measured_claims_spec.rb` checks that every `024.N` cited
anywhere in the tree resolves either to an entry below or to a row here,
so the next deletion cannot leave a dangling pointer whether or not
anyone remembers to grep.

---

## Index

**Generated from the entries below; do not hand-edit.** Regenerate with
`ruby scripts/reindex_findings.rb`, which `core/spec/meta/deferred_findings_spec.rb`
checks is current. It exists because answering "is this known?" used to mean
reading four thousand lines in no particular order — 25 of 72 entries were out
of numeric sequence. Findability is what makes a record worth keeping; a record
nobody can search is the recording habit without the benefit.

| # | status | release | what it is |
|---|---|---|---|
| [`024.1`](024-deferred-review-findings-resolved.md#0241-duplicate-unused-implementation-of-the-controller-callback-chain) | fixed | 0.1.10 | Duplicate, unused implementation of the controller callback chain |
| [`024.6`](024-deferred-review-findings-resolved.md#0246-the-seen-uris-spec-s-comment-overclaims) | fixed | 0.1.10 | The `seen_uris` spec's comment overclaims |
| [`024.8`](024-deferred-review-findings-resolved.md#0248-ownership-retirement-on-exited-known-size-0-is-unpinned) | fixed | 0.1.10 | Ownership retirement on `exited() && known.size === 0` is unpinned |
| [`024.10`](024-deferred-review-findings-resolved.md#02410-four-extension-ts-behaviours-cannot-be-unit-tested) | fixed | 0.1.10 | Four `extension.ts` behaviours cannot be unit-tested |
| [`024.13`](#02413-a-reopened-core-class-looks-closed-in-both-directions) | open | 0.4.0 | A reopened core class looks closed, in both directions |
| [`024.14`](024-deferred-review-findings-resolved.md#02414-workspace-wide-diagnostics-do-not-fire-against-the-real-rails-fixture) | fixed | 0.2.1 | Workspace-wide diagnostics do not fire against the real Rails fixture |
| [`024.15`](024-deferred-review-findings-resolved.md#02415-the-index-s-answers-depend-on-which-file-was-edited-last) | fixed | 0.1.13 | The index's answers depend on which file was edited last |
| [`024.16`](024-deferred-review-findings-resolved.md#02416-the-capability-e2e-suite-can-skip-in-full-while-ci-stays-green) | fixed | 0.1.13 | The capability E2E suite can skip in full while CI stays green |
| [`024.17`](024-deferred-review-findings-resolved.md#02417-vscode-src-extension-ts-is-covered-by-no-test-that-runs-anywhere) | fixed | 0.1.13 | `vscode/src/extension.ts` is covered by no test that runs anywhere |
| [`024.18`](#02418-the-unassigned-ivar-check-cannot-enumerate-what-it-needs-to) | open | 0.4.0 | The unassigned-`@ivar` check cannot enumerate what it needs to |
| [`024.19`](#02419-the-argument-type-check-judges-against-a-class-the-receiver-is-not) | open | 0.4.0 | The argument-type check judges against a class the receiver is not |
| [`024.20`](#02420-contains-treats-an-exclusive-end-offset-as-inclusive) | open | 0.4.0 | `contains?` treats an exclusive end offset as inclusive |
| [`024.21`](024-deferred-review-findings-resolved.md#02421-a-qualified-constant-is-coloured-half-one-way-half-the-other) | fixed | 0.2.15 | A qualified constant is coloured half one way, half the other |
| [`024.22`](#02422-the-unassigned-ivar-check-is-silent-in-an-application-rails-new-produces) | open | 0.4.0 | The unassigned-`@ivar` check is silent in an application `rails new`… |
| [`024.23`](024-deferred-review-findings-resolved.md#02423-the-singleton-chain-did-not-model-class-module) | fixed | 0.1.14 | The singleton chain did not model `Class`/`Module` |
| [`024.24`](024-deferred-review-findings-resolved.md#02424-every-path-url-call-is-a-missing-route-when-no-routes-are-loaded) | fixed | 0.2.0 | Every `*_path`/`*_url` call is a missing route when no routes are lo… |
| [`024.25`](024-deferred-review-findings-resolved.md#02425-a-markdown-parsing-spec-is-the-wrong-shape-for-these-two-documents-must-agree) | fixed | 0.2.12 | A Markdown-parsing spec is the wrong shape for "these two documents … |
| [`024.26`](024-deferred-review-findings-resolved.md#02426-a-workspace-def-object-foo-is-reachable-from-every-class-in-ruby-and-from-none-here) | fixed | 0.2.12 | A workspace `def Object.foo` is reachable from every class in Ruby a… |
| [`024.27`](024-deferred-review-findings-resolved.md#02427-documentsymbol-lists-one-outline-entry-per-name-a-macro-declares) | fixed | 0.2.16 | `documentSymbol` lists one outline entry per name a macro declares |
| [`024.28`](#02428-rename-refuses-on-a-macro-declared-method-rather-than-editing-it) | open | 0.4.0 | Rename refuses on a macro-declared method rather than editing it |
| [`024.29`](024-deferred-review-findings-resolved.md#02429-two-features-were-written-for-0-1-15-and-cut-from-it) | done | 0.2.16 | Two features were written for 0.1.15 and cut from it |
| [`024.30`](024-deferred-review-findings-resolved.md#02430-0-1-15-s-hunk-sweep-three-hunks-that-cannot-be-pinned-and-why) | fixed | 0.2.12 | 0.1.15's hunk sweep: three hunks that cannot be pinned, and why |
| [`024.31`](024-deferred-review-findings-resolved.md#02431-a-declaration-written-inside-a-block-has-no-owner-this-parser-can-name) | fixed | 0.2.13 | A declaration written inside a block has no owner this parser can na… |
| [`024.32`](024-deferred-review-findings-resolved.md#02432-def-foo-bar-is-recorded-as-an-instance-method-so-both-answers-are-inverted) | fixed | 0.2.13 | `def Foo.bar` is recorded as an instance method, so both answers are… |
| [`024.33`](024-deferred-review-findings-resolved.md#02433-k-instance-eval-attr-accessor-x-is-reported-k-class-eval-is-not) | fixed | 0.2.13 | `K.instance_eval { attr_accessor :x }` is reported; `K.class_eval` i… |
| [`024.34`](024-deferred-review-findings-resolved.md#02434-attr-inside-a-def-inside-class-self-is-kinded-singleton) | fixed | 0.2.13 | `attr_*` inside a `def` inside `class << self` is kinded singleton |
| [`024.35`](024-deferred-review-findings-resolved.md#02435-a-class-that-includes-a-module-the-workspace-cannot-resolve-still-reads-as-closed) | done | 0.2.18 | A class that includes a module the workspace cannot resolve still re… |
| [`024.36`](024-deferred-review-findings-resolved.md#02436-instructing-a-reviewer-narrowed-what-it-could-find-and-a-control-run-proved-it) | fixed | 0.1.15 | Instructing a reviewer narrowed what it could find, and a control ru… |
| [`024.37`](#02437-the-argument-type-check-reports-nothing-on-measured-real-ruby) | open | 0.4.0 | The argument-type check reports nothing on measured real Ruby |
| [`024.38`](#02438-scope-at-copies-the-whole-environment-once-per-descent-step) | open | 0.4.0 | `scope_at` copies the whole environment once per descent step |
| [`024.39`](#02439-localinferencer-keeps-per-request-state-and-0-2-0-gave-it-a-second-thread) | open | 0.4.0 | `LocalInferencer` keeps per-request state, and 0.2.0 gave it a secon… |
| [`024.40`](024-deferred-review-findings-resolved.md#02440-every-argument-count-report-on-the-measurement-corpus-is-false) | fixed | 0.2.15 | Every `argument-count` report on the measurement corpus is false |
| [`024.41`](024-deferred-review-findings-resolved.md#02441-typing-a-reports-a-method-on-the-next-line) | fixed | 0.2.18 | Typing a `.` reports a method on the *next* line |
| [`024.42`](#02442-a-signature-label-leaks-the-method-s-own-type-variable) | open | 0.4.0 | A signature label leaks the method's own type variable |
| [`024.43`](024-deferred-review-findings-resolved.md#02443-signature-help-answers-nothing-for-a-receiverless-stdlib-call) | fixed | 0.2.16 | Signature help answers nothing for a receiverless stdlib call |
| [`024.44`](#02444-a-partial-s-local-is-not-resolved-and-c11-s-stated-basis-names-it) | open | 0.4.0 | A partial's local is not resolved, and C11's stated basis names it |
| [`024.45`](#02445-re-analysis-after-a-keystroke-is-seconds-on-a-large-file-against-a-stated-300-ms) | open | 0.4.0 | Re-analysis after a keystroke is seconds on a large file, against a … |
| [`024.46`](024-deferred-review-findings-resolved.md#02446-typing-self-cost-55-false-diagnostics-and-was-rolled-back) | fixed | 0.2.1 | Typing `self` cost 55 false diagnostics and was rolled back |
| [`024.47`](#02447-a-namespaced-class-named-after-a-core-class-loses-its-diagnostics-and-the-readers-disagree-about-a-shadowed-literal) | open | 0.4.0 | A namespaced class named after a core class loses its diagnostics, a… |
| [`024.48`](024-deferred-review-findings-resolved.md#02448-the-measurement-tool-ran-an-engine-the-server-never-runs) | fixed | 0.2.1 | The measurement tool ran an engine the server never runs |
| [`024.49`](024-deferred-review-findings-resolved.md#02449-a-release-record-kept-asserting-durations-it-could-not-witness-ending) | fixed | 0.2.3 | A release record kept asserting durations it could not witness ending |
| [`024.50`](024-deferred-review-findings-resolved.md#02450-the-marketplace-description-promises-the-behaviour-0-2-1-removed) | fixed | 0.2.3 | The Marketplace description promises the behaviour 0.2.1 removed |
| [`024.51`](024-deferred-review-findings-resolved.md#02451-the-first-launch-after-an-upgrade-blocks-while-it-sweeps-the-old-cache) | fixed | 0.2.2 | The first launch after an upgrade blocks while it sweeps the old cac… |
| [`024.52`](024-deferred-review-findings-resolved.md#02452-a-publish-could-outlive-the-document-it-was-about-folded-into-024-56) | fixed | reverted | A publish could outlive the document it was about — folded into `024… |
| [`024.53`](024-deferred-review-findings-resolved.md#02453-the-absent-workspace-grace-measured-the-wrong-clock) | fixed | 0.2.2 | The absent-workspace grace measured the wrong clock |
| [`024.54`](024-deferred-review-findings-resolved.md#02454-an-edit-that-changed-nothing-discarded-the-edit-before-it) | fixed | reverted | An edit that changed nothing discarded the edit before it |
| [`024.55`](024-deferred-review-findings-resolved.md#02455-a-version-mismatch-is-reported-and-then-ignored) | fixed | 0.2.12 | A version mismatch is reported and then ignored |
| [`024.56`](024-deferred-review-findings-resolved.md#02456-a-publish-can-land-after-the-panel-has-been-cleared-and-after-a-newer-one) | fixed | 0.2.7 | A publish can land after the panel has been cleared, and after a new… |
| [`024.57`](024-deferred-review-findings-resolved.md#02457-the-debounce-and-why-it-was-rolled-back) | fixed | 0.2.18 | The debounce, and why it was rolled back |
| [`024.58`](024-deferred-review-findings-resolved.md#02458-bin-ovallsp-loaded-every-abi-s-vendored-gems-not-the-running-one-s) | fixed | 0.2.2 | `bin/ovallsp` loaded every ABI's vendored gems, not the running one's |
| [`024.59`](024-deferred-review-findings-resolved.md#02459-the-guard-against-a-stale-example-count-could-not-run) | fixed | 0.2.3 | The guard against a stale example count could not run |
| [`024.60`](024-deferred-review-findings-resolved.md#02460-four-test-fixtures-raced-macos-first-execution-scan) | fixed | 0.2.3 | Four test fixtures raced macOS' first-execution scan |
| [`024.62`](#02462-two-per-file-stores-are-separated-by-nothing-but-their-payload) | open | 0.4.0 | Two per-file stores are separated by nothing but their payload |
| [`024.63`](024-deferred-review-findings-resolved.md#02463-the-dispatch-layer-owns-view-inference-and-it-has-broken-the-query-layer-s-one-guarantee-twice) | fixed | 0.2.16 | The dispatch layer owns view inference, and it has broken the query … |
| [`024.64`](024-deferred-review-findings-resolved.md#02464-three-rounds-on-extension-ts-s-wiring-and-the-countermeasure-was-aimed-at-the-symptom) | fixed | 0.2.12 | Three rounds on `extension.ts`'s wiring, and the countermeasure was … |
| [`024.65`](024-deferred-review-findings-resolved.md#02465-a-different-ruby-engine-produces-two-error-toasts-where-it-produced-one) | fixed | 0.2.3 | A different Ruby engine produces two error toasts where it produced … |
| [`024.66`](024-deferred-review-findings-resolved.md#02466-a-marketing-card-kept-carrying-claims-about-what-an-error-s-text-says) | fixed | 0.2.3 | A marketing card kept carrying claims about what an error's text says |
| [`024.67`](024-deferred-review-findings-resolved.md#02467-seven-register-numbers-are-cited-from-the-tree-and-resolve-to-nothing) | fixed | 0.3.0 | Seven register numbers are cited from the tree and resolve to nothing |
| [`024.68`](024-deferred-review-findings-resolved.md#02468-three-rounds-of-guards-on-a-hand-rolled-grammar-each-blind-one-assumption-deeper) | fixed | 0.2.12 | Three rounds of guards on a hand-rolled grammar, each blind one assu… |
| [`024.69`](024-deferred-review-findings-resolved.md#02469-the-two-suites-that-drive-a-real-editor-are-run-by-nobody-but-the-maintainer) | fixed | 0.2.12 | The two suites that drive a real editor are run by nobody but the ma… |
| [`024.71`](#02471-one-mutable-rails-fixture-is-shared-by-every-worker-so-the-suite-cannot-be-parallelised) | open | 0.4.0 | One mutable Rails fixture is shared by every worker, so the suite ca… |
| [`024.72`](024-deferred-review-findings-resolved.md#02472-the-red-toast-0-2-1-removed-is-still-shown-from-the-other-code-path) | fixed | 0.2.2 | The red toast 0.2.1 removed is still shown, from the other code path |
| [`024.73`](024-deferred-review-findings-resolved.md#02473-the-fork-boundary-is-undone-by-marshal-load-in-the-parent) | fixed | 0.2.6 | The fork boundary is undone by `Marshal.load` in the parent |
| [`024.74`](024-deferred-review-findings-resolved.md#02474-the-trust-gate-stands-in-front-of-callers-not-in-front-of-what-executes) | fixed | 0.2.16 | The trust gate stands in front of callers, not in front of what exec… |
| [`024.75`](024-deferred-review-findings-resolved.md#02475-a-documented-field-selects-nothing) | fixed | 0.2.12 | A documented field selects nothing |
| [`024.76`](#02476-fifty-four-unknown-method-reports-over-real-gem-source-and-all-of-them-false) | open | 0.4.0 | Fifty-four `unknown-method` reports over real gem source, and all of… |
| [`024.77`](024-deferred-review-findings-resolved.md#02477-a-call-to-a-method-that-does-not-exist-is-missed-through-a-relation) | fixed | 0.2.15 | A call to a method that does not exist is missed through a relation |
| [`024.78`](024-deferred-review-findings-resolved.md#02478-completion-did-not-get-the-fix-hover-and-diagnostics-did) | fixed | 0.2.6 | Completion did not get the fix hover and diagnostics did |
| [`024.79`](024-deferred-review-findings-resolved.md#02479-model-first-completes-to-nothing) | fixed | 0.2.6 | `Model.first` completes to nothing |
| [`024.80`](024-deferred-review-findings-resolved.md#02480-an-unresolved-hierarchy-edge-is-expressible-as-a-method-owner) | fixed | 0.2.12 | An unresolved hierarchy edge is expressible as a method owner |
| [`024.81`](024-deferred-review-findings-resolved.md#02481-an-ancestor-reference-carries-no-lexical-context-so-an-ambiguous-name-is-picked-rather-than-resolved) | fixed | 0.2.12 | An ancestor reference carries no lexical context, so an ambiguous na… |
| [`024.82`](024-deferred-review-findings-resolved.md#02482-foo-class-new-bar-is-not-a-type-the-index-knows) | fixed | 0.2.15 | `Foo = Class.new(Bar)` is not a type the index knows |
| [`024.83`](#02483-the-undefined-method-check-is-loudest-exactly-where-no-runtime-agent-can-answer) | open | 0.4.0 | The undefined-method check is loudest exactly where no Runtime Agent… |
| [`024.84`](024-deferred-review-findings-resolved.md#02484-a-constant-is-typed-as-a-class-object-whatever-it-holds) | fixed | 0.2.18 | A constant is typed as a class object whatever it holds |
| [`024.85`](024-deferred-review-findings-resolved.md#02485-self-completes-nothing) | fixed | 0.2.16 | `self.` completes nothing |
| [`024.86`](024-deferred-review-findings-resolved.md#02486-an-ivar-assigned-in-another-method-has-no-type-except-in-the-view) | fixed | 0.3.0 | An ivar assigned in another method has no type, except in the view |
| [`024.87`](024-deferred-review-findings-resolved.md#02487-a-relation-stops-being-a-relation-after-one-hop) | fixed | 0.3.0 | A relation stops being a relation after one hop |
| [`024.88`](#02488-completion-unions-a-union-s-members-the-diagnostic-intersects-them) | open | 0.4.0 | Completion unions a union's members; the diagnostic intersects them |
| [`024.89`](024-deferred-review-findings-resolved.md#02489-signature-help-strips-the-parameter-kinds-and-never-advances) | fixed | 0.2.15 | Signature help strips the parameter kinds and never advances |
| [`024.90`](024-deferred-review-findings-resolved.md#02490-smaller-answers-a-review-round-measured) | fixed | 0.2.14 | Smaller answers a review round measured |
| [`024.91`](024-deferred-review-findings-resolved.md#02491-the-undefined-method-check-reports-on-ordinary-ruby-it-cannot-read-split-and-re-measured) | done | 0.2.16 | The undefined-method check reports on ordinary Ruby it cannot read —… |
| [`024.92`](024-deferred-review-findings-resolved.md#02492-a-plugin-chooses-how-much-memory-the-parent-allocates) | fixed | 0.2.6 | A plugin chooses how much memory the parent allocates |
| [`024.93`](024-deferred-review-findings-resolved.md#02493-process-kill-sig-0-signals-the-caller-s-own-process-group) | fixed | 0.2.6 | `Process.kill(sig, 0)` signals the caller's own process group |
| [`024.94`](024-deferred-review-findings-resolved.md#02494-a-windows-workspace-could-have-its-own-ruby-exe-run-before-it-is-trusted) | fixed | 0.2.6 | A Windows workspace could have its own `ruby.exe` run before it is t… |
| [`024.95`](024-deferred-review-findings-resolved.md#02495-a-deep-enough-file-ended-the-session-and-three-rescues-did-not-catch-it) | fixed | 0.2.6 | A deep enough file ended the session, and three rescues did not catc… |
| [`024.96`](024-deferred-review-findings-resolved.md#02496-every-malformed-lsp-frame-ended-the-process) | fixed | 0.2.6 | Every malformed LSP frame ended the process |
| [`024.97`](024-deferred-review-findings-resolved.md#02497-a-later-pass-at-the-same-version-overwrites-a-corrected-answer) | fixed | 0.2.12 | A later pass at the same version overwrites a corrected answer |
| [`024.98`](024-deferred-review-findings-resolved.md#02498-a-workspace-opened-through-a-symlink-shows-every-file-twice-and-one-copy-can-never-be-cleared) | fixed | 0.2.8 | A workspace opened through a symlink shows every file twice, and one… |
| [`024.99`](024-deferred-review-findings-resolved.md#02499-completion-offers-members-that-cannot-be-called-from-where-it-was-asked) | fixed | 0.3.0 | Completion offers members that cannot be called from where it was as… |
| [`024.100`](#024100-the-four-features-answer-from-different-code-paths-and-disagree-at-one-position) | open | 0.4.0 | The four features answer from different code paths and disagree at o… |
| [`024.101`](024-deferred-review-findings-resolved.md#024101-analysis-runs-per-keystroke-so-the-answers-fall-behind-the-cursor-and-every-wrong-one-is-published) | fixed | 0.2.10 | Analysis runs per keystroke, so the answers fall behind the cursor a… |
| [`024.102`](024-deferred-review-findings-resolved.md#024102-eight-classes-and-the-logic-each-one-could-not-have-happened-under) | fixed | 0.2.16 | Eight classes, and the logic each one could not have happened under |
| [`024.103`](024-deferred-review-findings-resolved.md#024103-a-bare-class-name-inside-a-namespace-answers-with-an-arbitrary-same-named-class) | fixed | 0.2.10 | A bare class name inside a namespace answers with an arbitrary same-… |
| [`024.104`](024-deferred-review-findings-resolved.md#024104-class-methods-do-in-a-concern-is-attributed-to-the-instance-side) | fixed | 0.2.10 | `class_methods do` in a concern is attributed to the instance side |
| [`024.105`](024-deferred-review-findings-resolved.md#024105-visibility-is-not-recorded-for-singleton-methods-at-all) | fixed | 0.2.9 | Visibility is not recorded for singleton methods at all |
| [`024.106`](#024106-a-module-s-singleton-calls-go-unchecked-module-function-and-extend-self-producing-nothing-is-withdrawn) | open | 0.4.0 | A module's singleton calls go unchecked — `module_function` and `ext… |
| [`024.107`](024-deferred-review-findings-resolved.md#024107-an-alias-never-appears-in-completion-though-every-other-feature-knows-it) | fixed | 0.2.9 | An alias never appears in completion, though every other feature kno… |
| [`024.108`](024-deferred-review-findings-resolved.md#024108-protected-methods-are-offered-on-an-explicit-external-receiver) | fixed | 0.2.9 | Protected methods are offered on an explicit external receiver |
| [`024.109`](024-deferred-review-findings-resolved.md#024109-specs-whose-fixture-cannot-distinguish-the-behaviour-they-pin) | fixed | 0.2.12 | Specs whose fixture cannot distinguish the behaviour they pin |
| [`024.110`](024-deferred-review-findings-resolved.md#024110-the-macro-is-reported-and-what-it-might-define-is-not) | fixed | 0.2.13 | The macro is reported, and what it might define is not |
| [`024.111`](024-deferred-review-findings-resolved.md#024111-a-visibility-section-written-inside-a-block-does-not-reach-the-body-it-runs-in) | fixed | 0.2.15 | A visibility section written inside a block does not reach the body … |
| [`024.112`](024-deferred-review-findings-resolved.md#024112-a-bare-constant-is-not-looked-up-through-the-enclosing-class-s-ancestors) | fixed | 0.2.11 | A bare constant is not looked up through the enclosing class's ances… |
| [`024.113`](024-deferred-review-findings-resolved.md#024113-the-publish-funnel-s-memory-is-keyed-by-uri-not-by-buffer) | fixed | 0.2.11 | The publish funnel's memory is keyed by uri, not by buffer |
| [`024.114`](024-deferred-review-findings-resolved.md#024114-module-function-name-cannot-see-a-module-reopened-in-another-file) | fixed | 0.2.11 | `module_function :name` cannot see a module reopened in another file |
| [`024.115`](024-deferred-review-findings-resolved.md#024115-include-m-reaches-m-classmethods-whether-or-not-m-is-a-concern) | fixed | 0.2.11 | `include M` reaches `M::ClassMethods` whether or not M is a Concern |
| [`024.116`](024-deferred-review-findings-resolved.md#024116-def-self-method-missing-and-define-singleton-method-do-not-open-a-surface) | fixed | 0.2.13 | `def self.method_missing` and `define_singleton_method` do not open … |
| [`024.117`](024-deferred-review-findings-resolved.md#024117-the-two-spellings-of-a-class-body-macro-get-opposite-answers) | fixed | 0.2.13 | The two spellings of a class-body macro get opposite answers |
| [`024.118`](024-deferred-review-findings-resolved.md#024118-workspaceindex-stale-compares-versions-across-buffers) | fixed | 0.2.12 | `WorkspaceIndex#stale?` compares versions across buffers |
| [`024.119`](024-deferred-review-findings-resolved.md#024119-twenty-eight-spec-files-assemble-their-own-analysis-stack) | fixed | 0.2.12 | Twenty-eight spec files assemble their own analysis stack |
| [`024.120`](024-deferred-review-findings-resolved.md#024120-the-integration-watcher-example-could-not-retry-and-it-looked-like-a-linux-defect) | fixed | 0.2.12 | The integration watcher example could not retry, and it looked like … |
| [`024.121`](#024121-nothing-measures-how-much-of-this-tree-no-test-would-notice-changing) | open | 0.4.0 | Nothing measures how much of this tree no test would notice changing |
| [`024.122`](024-deferred-review-findings-resolved.md#024122-a-failure-is-turned-into-a-plausible-value-in-72-measured-places) | fixed | 0.2.13 | A failure is turned into a plausible value, in 72 measured places |
| [`024.123`](024-deferred-review-findings-resolved.md#024123-a-private-alias-was-offered-and-the-register-said-it-was-not) | fixed | 0.2.12 | A private alias was offered, and the register said it was not |
| [`024.124`](024-deferred-review-findings-resolved.md#024124-four-entries-named-a-release-that-had-already-shipped-for-the-third-time) | fixed | 0.3.0 | Four entries named a release that had already shipped, for the third… |
| [`024.125`](024-deferred-review-findings-resolved.md#024125-the-packaged-core-is-never-driven-end-to-end-and-two-gates-say-it-is) | fixed | 0.2.17 | The packaged Core is never driven end to end, and two gates say it is |
| [`024.126`](024-deferred-review-findings-resolved.md#024126-a-text-scanner-matches-its-own-prose-exempts-itself-and-stops-checking-a-file-that-can-hold-the-real-thing) | fixed | 0.2.14 | A text scanner matches its own prose, exempts itself, and stops chec… |
| [`024.127`](024-deferred-review-findings-resolved.md#024127-hover-answers-an-empty-string-where-lsp-expects-null) | fixed | 0.2.15 | Hover answers an empty string where LSP expects null |
| [`024.128`](024-deferred-review-findings-resolved.md#024128-integer-arithmetic-answers-a-four-way-union) | fixed | 0.2.15 | Integer arithmetic answers a four-way union |
| [`024.129`](#024129-no-undefined-method-report-on-a-core-library-receiver) | open | 0.4.0 | No undefined-method report on a core-library receiver |
| [`024.130`](024-deferred-review-findings-resolved.md#024130-a-hover-label-drops-the-namespace-when-the-name-was-written-bare-withdrawn-it-does-not-reproduce) | fixed | 0.2.14 | A hover label drops the namespace when the name was written bare — w… |
| [`024.131`](024-deferred-review-findings-resolved.md#024131-after-on-a-nil-local-hover-answers-nil-a-wrong-answer-not-an-absent-one) | fixed | 0.2.15 | After `||=` on a nil local, hover answers `nil` — a wrong answer, no… |
| [`024.132`](#024132-a-scope-defined-in-a-concern-s-included-do-has-no-type) | open | 0.4.0 | A scope defined in a concern's `included do` has no type |
| [`024.133`](024-deferred-review-findings-resolved.md#024133-a-positional-argument-to-a-keyword-only-method-reads-as-nonsense) | fixed | 0.2.15 | A positional argument to a keyword-only method reads as nonsense |
| [`024.134`](024-deferred-review-findings-resolved.md#024134-wait-until-ready-never-returns-for-a-non-rails-workspace) | fixed | 0.2.15 | `wait_until_ready` never returns for a non-Rails workspace |
| [`024.135`](024-deferred-review-findings-resolved.md#024135-observation-runner-deserialises-a-subprocess-s-output-with-marshal-load) | fixed | 0.2.16 | `Observation::Runner` deserialises a subprocess's output with `Marsh… |
| [`024.136`](024-deferred-review-findings-resolved.md#024136-a-route-s-optional-segments-are-detected-by-matching-the-literal-format) | fixed | 0.2.16 | A route's optional segments are detected by matching the literal `(.… |
| [`024.137`](#024137-workspaceindex-search-holds-the-index-lock-for-the-whole-walk) | open | 0.4.0 | `WorkspaceIndex#search` holds the index lock for the whole walk |
| [`024.138`](024-deferred-review-findings-resolved.md#024138-no-test-mixes-a-schema-change-and-a-model-file-change-in-one-batch) | fixed | 0.2.16 | No test mixes a schema change and a model-file change in one batch |
| [`024.139`](024-deferred-review-findings-resolved.md#024139-task-documents-grew-their-own-findings-sections-outside-the-register) | fixed | 0.2.14 | Task documents grew their own findings sections, outside the register |
| [`024.140`](024-deferred-review-findings-resolved.md#024140-a-scripted-edit-doubled-a-register-entry-and-every-check-stayed-green) | fixed | 0.2.14 | A scripted edit doubled a register entry, and every check stayed gre… |
| [`024.141`](024-deferred-review-findings-resolved.md#024141-publishing-md-documented-the-publish-command-that-shipped-a-corrupt-v0-1-2) | fixed | 0.2.14 | `PUBLISHING.md` documented the publish command that shipped a corrup… |
| [`024.142`](024-deferred-review-findings-resolved.md#024142-a-corpus-run-did-not-say-what-it-had-run) | fixed | 0.2.14 | A corpus run did not say what it had run |
| [`024.143`](024-deferred-review-findings-resolved.md#024143-did-i-run-everything-was-answered-from-memory) | fixed | 0.2.14 | "Did I run everything?" was answered from memory |
| [`024.144`](024-deferred-review-findings-resolved.md#024144-a-design-document-restating-a-manifest-is-two-copies-with-nothing-between-them) | fixed | 0.2.14 | A design document restating a manifest is two copies with nothing be… |
| [`024.145`](024-deferred-review-findings-resolved.md#024145-re-deriving-the-example-count-was-three-hand-edits-per-commit) | fixed | 0.2.14 | Re-deriving the example count was three hand edits per commit |
| [`024.146`](024-deferred-review-findings-resolved.md#024146-a-script-crashes-under-a-locale-less-shell-on-the-input-a-check-exists-to-report) | fixed | 0.2.14 | A script crashes under a locale-less shell, on the input a check exi… |
| [`024.147`](024-deferred-review-findings-resolved.md#024147-every-check-was-blind-to-a-file-until-it-was-committed-and-the-commit-gate-runs-before-that) | fixed | 0.2.14 | Every check was blind to a file until it was committed, and the comm… |
| [`024.148`](024-deferred-review-findings-resolved.md#024148-the-check-for-did-the-suite-actually-run-could-not-fail-in-the-case-it-existed-for) | fixed | 0.2.14 | The check for "did the suite actually run" could not fail in the cas… |
| [`024.149`](024-deferred-review-findings-resolved.md#024149-a-review-harness-that-reports-nothing-found-when-its-own-post-processing-crashed) | fixed | 0.2.14 | A review harness that reports "nothing found" when its own post-proc… |
| [`024.150`](024-deferred-review-findings-resolved.md#024150-agents-md-paraphrases-claude-md-and-the-paraphrase-drifts) | fixed | 0.2.18 | `AGENTS.md` paraphrases `CLAUDE.md`, and the paraphrase drifts |
| [`024.151`](#024151-a-check-can-be-disabled-and-no-check-notices-closed-on-one-instalment-in-0-3-2-reopened) | open | 0.4.0 | A check can be disabled, and no check notices — closed on one instal… |
| [`024.152`](024-deferred-review-findings-resolved.md#024152-a-leak-check-counted-every-descriptor-in-the-process-and-flaked-under-load) | fixed | 0.2.14 | A leak check counted every descriptor in the process, and flaked und… |
| [`024.153`](024-deferred-review-findings-resolved.md#024153-a-quarter-of-the-open-work-is-in-no-release-and-0-3-0-has-become-where-the-rest-goes) | fixed | 0.2.15 | A quarter of the open work is in no release, and 0.3.0 has become wh… |
| [`024.154`](024-deferred-review-findings-resolved.md#024154-findings-recorded-in-046-are-truncated-mid-sentence-in-rounds-1-and-3-in-the-same-commit-that-untruncated-round-2) | fixed | 0.2.18 | Findings recorded in 046 are truncated mid-sentence in rounds 1 and … |
| [`024.155`](024-deferred-review-findings-resolved.md#024155-a-register-heading-the-entry-grammar-does-not-match-is-skipped-rather-than-failed-so-an-entry-can-exist-and-be-checked-by-nothing) | fixed | 0.2.16 | A register heading the entry grammar does not match is skipped rathe… |
| [`024.156`](024-deferred-review-findings-resolved.md#024156-the-evidence-extractor-recognises-only-rb-sh-js-and-test-so-typescript-tests-and-ci-job-names-the-sole-evidence-for-eight-gates-are-never-checked) | fixed | 0.2.16 | The evidence extractor recognises only .rb/.sh/.js and test:, so Typ… |
| [`024.157`](024-deferred-review-findings-resolved.md#024157-a-git-subprocess-in-a-throwaway-repository-obeys-the-inherited-git-dir-so-the-suite-commits-to-the-real-repository) | fixed | 0.2.16 | A git subprocess in a throwaway repository obeys the inherited GIT_D… |
| [`024.158`](024-deferred-review-findings-resolved.md#024158-the-executed-pat-mode-example-passes-on-a-release-sh-that-only-warns-because-its-exit-status-comes-from-a-later-check-misreporting-a-non-repository-as-dirty) | fixed | 0.2.16 | The executed PAT-mode example passes on a release.sh that only warns… |
| [`024.159`](024-deferred-review-findings-resolved.md#024159-the-measured-claim-marker-and-the-number-a-reader-sees-are-separate-strings-so-the-prose-can-say-anything-while-the-marker-verifies) | fixed | 0.2.17 | The measured-claim marker and the number a reader sees are separate … |
| [`024.160`](024-deferred-review-findings-resolved.md#024160-counts-in-046-that-describe-this-tree-carry-no-basis-are-not-marked-and-several-are-stale-at-head) | fixed | 0.2.18 | Counts in 046 that describe this tree carry no basis, are not marked… |
| [`024.161`](024-deferred-review-findings-resolved.md#024161-046-s-round-3-correction-states-that-the-4-000-lines-of-revert-phrase-is-removed-the-phrase-is-still-the-file-s-closing-sentence) | fixed | 0.2.17 | 046's round-3 correction states that the "4,000 lines of revert" phr… |
| [`024.162`](024-deferred-review-findings-resolved.md#024162-046-s-recorded-departure-from-the-drive-round-rests-on-a-false-enumeration-of-the-change-set) | fixed | 0.2.16 | 046's recorded departure from the `drive` round rests on a false enu… |
| [`024.163`](024-deferred-review-findings-resolved.md#024163-046-s-round-2-header-asserts-every-attacker-worked-in-a-clean-tree-and-046-s-own-recorded-findings-say-the-tree-was-dirty-and-changing-throughout) | fixed | 0.2.15 | 046's round-2 header asserts every attacker worked in a clean tree, … |
| [`024.164`](024-deferred-review-findings-resolved.md#024164-046-states-finding-totals-whose-stated-dispositions-do-not-account-for-them) | fixed | 0.2.18 | 046 states finding totals whose stated dispositions do not account f… |
| [`024.165`](024-deferred-review-findings-resolved.md#024165-046-keeps-138-acceptance-boxes-on-the-stated-ground-that-no-box-has-ever-been-ticked-56-are-ticked-13-of-them-in-a-file-this-change-set-edited) | fixed | 0.2.17 | 046 keeps 138 acceptance boxes on the stated ground that no box has … |
| [`024.166`](024-deferred-review-findings-resolved.md#024166-two-rows-of-046-s-checks-table-describe-checks-that-were-built-differently-and-the-changed-shape-list-omits-one) | fixed | 0.2.16 | Two rows of 046's checks table describe checks that were built diffe… |
| [`024.167`](024-deferred-review-findings-resolved.md#024167-046-s-three-review-rounds-record-no-per-place-tracking-so-claude-md-s-same-place-rule-cannot-be-applied-and-was-not) | fixed | 0.2.18 | 046's three review rounds record no per-place tracking, so CLAUDE.md… |
| [`024.168`](024-deferred-review-findings-resolved.md#024168-the-ledger-s-reason-for-keeping-05-protocol-md-s-section-numbering-counts-four-source-comments-where-one-exists-and-the-claim-was-copied-into-the-shipped-document) | fixed | 0.2.16 | The ledger's reason for keeping 05-protocol.md's section numbering c… |
| [`024.169`](024-deferred-review-findings-resolved.md#024169-check-doc-links-rb-s-citation-comment-describes-anchor-punctuation-stripping-that-no-caller-performs) | fixed | 0.2.16 | `check_doc_links.rb`'s CITATION comment describes anchor/punctuation… |
| [`024.170`](024-deferred-review-findings-resolved.md#024170-the-doubled-entry-check-counts-area-lines-so-a-body-duplicated-anywhere-below-that-line-is-invisible) | fixed | 0.2.16 | The doubled-entry check counts `**Area:**` lines, so a body duplicat… |
| [`024.171`](024-deferred-review-findings-resolved.md#024171-three-entries-closed-in-0-2-14-state-as-done-something-head-contradicts-two-of-them-naming-a-countermeasure-that-was-never-built) | fixed | 0.2.18 | Three entries closed in 0.2.14 state as done something HEAD contradi… |
| [`024.172`](024-deferred-review-findings-resolved.md#024172-four-counts-derived-about-this-tree-are-wrong-and-unmarked-one-of-them-inside-the-entry-about-a-record-that-drifted) | fixed | 0.2.18 | Four counts derived about this tree are wrong and unmarked, one of t… |
| [`024.173`](024-deferred-review-findings-resolved.md#024173-the-shipped-target-guard-sees-only-kind-defect-and-released-in-is-written-by-16-entries-and-read-by-no-check) | fixed | 0.2.17 | The shipped-target guard sees only `kind: defect`, and `released-in:… |
| [`024.174`](024-deferred-review-findings-resolved.md#024174-a-relative-markdown-link-beginning-docs-is-resolved-against-the-repository-root-instead-of-the-citing-file-s-directory) | fixed | 0.2.16 | A relative Markdown link beginning `docs/` is resolved against the r… |
| [`024.175`](024-deferred-review-findings-resolved.md#024175-doc-link-resolution-goes-through-file-file-so-a-case-only-typo-passes-on-macos-and-fails-on-linux-and-github) | fixed | 0.2.16 | Doc-link resolution goes through File.file?, so a case-only typo pas… |
| [`024.176`](024-deferred-review-findings-resolved.md#024176-the-deletion-marker-marker-admits-a-pointer-to-a-renamed-file-which-the-paragraph-defining-it-says-is-still-a-failure) | fixed | 0.2.16 | The `[deletion marker]` marker admits a pointer to a renamed file, w… |
| [`024.177`](024-deferred-review-findings-resolved.md#024177-check-doc-links-names-only-an-enumerated-set-of-docs-subdirectories-so-a-citation-in-any-other-one-is-silently-unchecked) | fixed | 0.2.16 | check_doc_links names only an enumerated set of docs subdirectories,… |
| [`024.178`](024-deferred-review-findings-resolved.md#024178-check-doc-links-founding-census-is-stated-as-living-entirely-in-source-comments-one-of-the-nineteen-was-in-a-markdown-document) | fixed | 0.2.16 | check_doc_links' founding census is stated as living entirely in sou… |
| [`024.179`](024-deferred-review-findings-resolved.md#024179-hand-typed-counts-in-check-doc-links-header-do-not-reproduce-and-none-carries-a-measured-marker) | fixed | 0.2.16 | Hand-typed counts in check_doc_links' header do not reproduce, and n… |
| [`024.180`](024-deferred-review-findings-resolved.md#024180-the-citation-guard-reads-nine-file-extensions-so-the-published-site-s-register-pointers-are-outside-every-check) | fixed | 0.2.16 | The citation guard reads nine file extensions, so the published site… |
| [`024.181`](024-deferred-review-findings-resolved.md#024181-the-measured-claim-scanner-reads-four-hand-written-globs-so-a-marker-anywhere-else-is-inert) | fixed | 0.2.17 | The measured-claim scanner reads four hand-written globs, so a marke… |
| [`024.182`](024-deferred-review-findings-resolved.md#024182-a-sub-numbered-register-entry-is-invisible-to-the-citation-guard-and-a-citation-of-one-truncates-to-its-parent) | fixed | 0.2.16 | A sub-numbered register entry is invisible to the citation guard, an… |
| [`024.183`](024-deferred-review-findings-resolved.md#024183-the-citation-guard-skips-the-register-itself-where-most-024-n-cross-references-are-written) | fixed | 0.2.16 | The citation guard skips the register itself, where most `024.N` cro… |
| [`024.184`](024-deferred-review-findings-resolved.md#024184-a-dated-rev-claim-is-silently-derived-from-the-present-tree-unless-the-deriver-happens-to-use-the-revision) | fixed | 0.2.17 | A dated `@<rev>` claim is silently derived from the present tree unl… |
| [`024.185`](024-deferred-review-findings-resolved.md#024185-a-second-measured-marker-on-the-same-line-is-never-parsed) | fixed | 0.2.17 | A second `<!-- measured: -->` marker on the same line is never parsed |
| [`024.186`](024-deferred-review-findings-resolved.md#024186-mutex-sites-counts-the-string-mutex-new-so-a-comment-mentioning-it-inflates-the-documented-lock-count) | fixed | 0.2.17 | `mutex-sites` counts the string `Mutex.new`, so a comment mentioning… |
| [`024.187`](024-deferred-review-findings-resolved.md#024187-a-single-nul-or-invalid-byte-clears-a-whole-file-from-the-home-path-scan-and-no-example-can-fail-on-it) | fixed | 0.2.17 | A single NUL or invalid byte clears a whole file from the home-path … |
| [`024.188`](024-deferred-review-findings-resolved.md#024188-the-home-path-scanner-dereferences-a-symlink-instead-of-reading-the-blob-git-commits) | fixed | 0.2.17 | The home-path scanner dereferences a symlink instead of reading the … |
| [`024.189`](024-deferred-review-findings-resolved.md#024189-the-home-path-pattern-matches-one-spelling-so-every-other-spelling-of-the-same-real-path-passes) | fixed | 0.2.17 | The home-path pattern matches one spelling, so every other spelling … |
| [`024.190`](024-deferred-review-findings-resolved.md#024190-annotated-tag-messages-are-a-pushed-public-channel-neither-mode-of-the-home-path-check-scans) | fixed | 0.2.17 | Annotated tag messages are a pushed public channel neither mode of t… |
| [`024.191`](024-deferred-review-findings-resolved.md#024191-as-utf8-s-comment-describes-a-hazard-the-same-file-s-utf8-require-already-removed) | fixed | 0.2.16 | as_utf8's comment describes a hazard the same file's utf8 require al… |
| [`024.192`](024-deferred-review-findings-resolved.md#024192-the-case-sensitivity-decision-is-justified-by-a-count-of-37-that-was-never-right) | fixed | 0.2.16 | The case-sensitivity decision is justified by a count of 37 that was… |
| [`024.193`](024-deferred-review-findings-resolved.md#024193-existence-is-a-suffix-glob-and-any-test-name-passes-unconditionally-so-a-citation-naming-a-file-that-does-not-exist-is-accepted) | fixed | 0.2.16 | Existence is a suffix glob and any test: name passes unconditionally… |
| [`024.194`](024-deferred-review-findings-resolved.md#024194-release-gate-spec-s-wiring-corpus-includes-untracked-files-so-uncommitted-local-text-satisfies-a-gate-s-something-invokes-this) | fixed | 0.2.16 | release_gate_spec's wiring corpus includes untracked files, so uncom… |
| [`024.195`](024-deferred-review-findings-resolved.md#024195-every-prose-statement-of-what-the-preflight-gate-runs-is-stale-and-nothing-derives-any-of-them) | fixed | 0.2.16 | Every prose statement of what the preflight gate runs is stale, and … |
| [`024.196`](024-deferred-review-findings-resolved.md#024196-the-measurement-that-justifies-reading-per-example-status-is-quoted-three-times-attributed-to-a-different-file-each-time-and-matches-none-of-them) | fixed | 0.2.17 | The measurement that justifies reading per-example status is quoted … |
| [`024.197`](024-deferred-review-findings-resolved.md#024197-0-2-14-s-review-loop-edited-its-own-standard-and-added-a-capability-between-rounds-with-no-departure-recorded) | fixed | 0.2.18 | 0.2.14's review loop edited its own standard and added a capability … |
| [`024.198`](024-deferred-review-findings-resolved.md#024198-the-packaged-artifact-inspection-count-is-derived-from-the-directory-alone-so-a-grep-aimed-at-the-wrong-pattern-or-with-wider-exclusions-still-reports-a-healthy-count) | fixed | 0.2.16 | The packaged-artifact inspection count is derived from the directory… |
| [`024.199`](024-deferred-review-findings-resolved.md#024199-the-guard-spec-s-absolute-grep-pin-is-satisfied-by-the-advisory-grep-and-its-bare-grep-scan-cannot-see-an-indented-call) | fixed | 0.2.16 | The guard spec's absolute-grep pin is satisfied by the advisory grep… |
| [`024.200`](024-deferred-review-findings-resolved.md#024200-nothing-checks-that-release-sh-parses-so-a-syntax-error-past-the-first-refusal-leaves-every-check-green) | fixed | 0.2.16 | Nothing checks that release.sh parses, so a syntax error past the fi… |
| [`024.201`](024-deferred-review-findings-resolved.md#024201-the-not-yet-escape-hatch-is-guarded-against-a-hand-copied-two-suite-list-that-has-drifted-from-the-three-suite-table-it-covers) | fixed | 0.2.16 | The NOT YET escape hatch is guarded against a hand-copied two-suite … |
| [`024.202`](024-deferred-review-findings-resolved.md#024202-the-release-tag-accounting-invariant-runs-nowhere-continuous-the-job-that-runs-the-suite-checks-out-without-tags) | fixed | 0.2.16 | The release-tag accounting invariant runs nowhere continuous: the jo… |
| [`024.203`](024-deferred-review-findings-resolved.md#024203-suites-ran-spec-s-ci-yml-link-asserts-a-text-substring-so-it-passes-for-a-step-that-has-been-deleted-commented-out-or-disabled) | fixed | 0.2.16 | suites_ran_spec's ci.yml link asserts a text substring, so it passes… |
| [`024.204`](024-deferred-review-findings-resolved.md#024204-the-git-ls-files-guard-reads-49-files-in-two-directories-so-the-enumeration-it-forbids-is-invisible-everywhere-else-in-the-tree) | fixed | 0.2.16 | The `git ls-files` guard reads 49 files in two directories, so the e… |
| [`024.205`](024-deferred-review-findings-resolved.md#024205-the-duplicate-heading-check-tracks-a-fence-by-its-character-and-not-its-length-so-a-four-backtick-block-leaves-the-rest-of-the-file-unread) | fixed | 0.2.16 | The duplicate-heading check tracks a fence by its character and not … |
| [`024.206`](024-deferred-review-findings-resolved.md#024206-the-duplicate-heading-check-sees-only-unindented-h1-and-h2-while-024-140-records-the-guarantee-as-every-heading) | fixed | 0.2.16 | The duplicate-heading check sees only unindented h1 and h2, while `0… |
| [`024.207`](024-deferred-review-findings-resolved.md#024207-two-decisions-in-the-duplicate-heading-fence-parser-have-no-fixture-that-can-distinguish-them) | fixed | 0.2.16 | Two decisions in the duplicate-heading fence parser have no fixture … |
| [`024.208`](024-deferred-review-findings-resolved.md#024208-encoding-default-internal-nil-is-the-half-of-the-locale-fix-that-nothing-pins) | fixed | 0.2.16 | `Encoding.default_internal = nil` is the half of the locale fix that… |
| [`024.209`](024-deferred-review-findings-resolved.md#024209-the-5-status-bar-comparison-is-set-equality-against-a-regex-sample-of-clientpresentation-ts-not-against-the-file-s-status-strings-and-two-records-state-the-stronger-guarantee) | fixed | 0.2.16 | The §5 status-bar comparison is set equality against a regex sample … |
| [`024.210`](024-deferred-review-findings-resolved.md#024210-the-plugin-sdk-check-asks-whether-a-name-is-defined-anywhere-under-core-lib-ovallsp-plugins-not-whether-it-is-callable-on-the-receiver-the-document-shows) | fixed | 0.2.16 | The plugin-sdk check asks whether a name is defined anywhere under c… |
| [`024.211`](024-deferred-review-findings-resolved.md#024211-check-pinned-mutations-rb-verify-only-prints-the-applier-s-conclusion-after-applying-nothing) | fixed | 0.2.16 | `check_pinned_mutations.rb --verify-only` prints the applier's concl… |
| [`024.212`](024-deferred-review-findings-resolved.md#024212-pinned-mutations-yml-s-header-documents-the-mechanism-the-applier-abandoned-and-a-scope-it-no-longer-has) | fixed | 0.2.16 | pinned_mutations.yml's header documents the mechanism the applier ab… |
| [`024.213`](024-deferred-review-findings-resolved.md#024213-a-mutation-entry-s-stated-reason-describes-a-mutation-different-from-the-one-it-encodes) | fixed | 0.2.16 | A mutation entry's stated reason describes a mutation different from… |
| [`024.214`](024-deferred-review-findings-resolved.md#024214-generate-sbom-rb-s-header-tells-the-reader-a-stale-sbom-is-caught-by-nobody-in-the-release-that-made-a-spec-catch-it) | fixed | 0.2.16 | generate_sbom.rb's header tells the reader a stale SBOM is caught by… |
| [`024.215`](024-deferred-review-findings-resolved.md#024215-a-scripted-comment-rewrite-in-corpus-diagnostics-rb-cut-a-sentence-mid-clause-and-nothing-in-the-tree-can-see-it) | fixed | 0.2.16 | A scripted comment rewrite in corpus_diagnostics.rb cut a sentence m… |
| [`024.216`](024-deferred-review-findings-resolved.md#024216-the-register-s-entry-number-is-parsed-by-six-readers-with-three-grammars-so-a-sub-numbered-entry-is-indexed-as-a-duplicate-of-its-parent) | fixed | 0.2.16 | The register's entry number is parsed by six readers with three gram… |
| [`024.217`](024-deferred-review-findings-resolved.md#024217-rescue-verdicts-yml-s-header-tells-a-reader-the-98-arguments-are-unargued-defaults-and-names-a-verdict-the-checker-rejects-as-the-safe-one) | fixed | 0.2.16 | `rescue_verdicts.yml`'s header tells a reader the 98 arguments are u… |
| [`024.218`](024-deferred-review-findings-resolved.md#024218-six-isolated-agents-branched-from-the-wrong-commit-and-the-evidence-was-deleted-before-it-was-checked) | fixed | 0.2.15 | Six isolated agents branched from the wrong commit, and the evidence… |
| [`024.219`](024-deferred-review-findings-resolved.md#024219-a-three-part-claim-shipped-with-one-part-pinned-and-the-other-two-were-false) | fixed | 0.2.15 | A three-part claim shipped with one part pinned, and the other two w… |
| [`024.220`](024-deferred-review-findings-resolved.md#024220-the-interpreter-sessions-pasted-through-this-tree-are-never-re-run) | fixed | 0.2.16 | The interpreter sessions pasted through this tree are never re-run |
| [`024.221`](#024221-a-block-whose-receiver-cannot-be-vouched-for-contains-a-private-that-ruby-would-let-through) | open | 0.4.0 | A block whose receiver cannot be vouched for contains a `private` th… |
| [`024.223`](024-deferred-review-findings-resolved.md#024223-one-unresolvable-include-in-a-project-s-own-rbs-turns-its-whole-class-into-false-reports) | fixed | 0.2.15 | One unresolvable `include` in a project's own RBS turns its whole cl… |
| [`024.224`](#024224-a-type-declared-only-in-sig-is-reported-incompatible-with-itself-the-half-0-3-2-did-not-fix) | open | 0.4.0 | A type declared only in `sig/` is reported incompatible with itself … |
| [`024.225`](024-deferred-review-findings-resolved.md#024225-a-scripted-edit-inserted-the-entire-file-before-its-own-anchor-and-the-line-count-was-the-only-symptom) | fixed | 0.2.16 | A scripted edit inserted the entire file before its own anchor, and … |
| [`024.226`](024-deferred-review-findings-resolved.md#024226-an-argument-written-as-a-paren-less-call-is-judged-by-its-own-last-argument) | fixed | 0.2.15 | An argument written as a paren-less call is judged by its own last a… |
| [`024.227`](024-deferred-review-findings-resolved.md#024227-every-outline-symbol-s-selectionrange-was-its-whole-declaration) | fixed | 0.2.15 | Every outline symbol's `selectionRange` was its whole declaration |
| [`024.228`](024-deferred-review-findings-resolved.md#024228-every-stdlib-klass-method-answered-nothing-in-three-features-at-once) | fixed | 0.2.15 | Every stdlib `Klass.method(` answered nothing, in three features at … |
| [`024.229`](024-deferred-review-findings-resolved.md#024229-signature-help-says-nothing-at-the-top-level-of-a-file-and-cannot-be-fixed-the-way-the-register-says) | fixed | 0.3.0 | Signature help says nothing at the top level of a file, and cannot b… |
| [`024.230`](024-deferred-review-findings-resolved.md#024230-a-top-level-def-is-indexed-with-no-owner-so-nothing-can-look-it-up) | fixed | 0.2.18 | A top-level `def` is indexed with no owner, so nothing can look it up |
| [`024.231`](024-deferred-review-findings-resolved.md#024231-a-permission-written-down-once-was-still-missed-and-the-script-that-hid-it-said-the-opposite) | fixed | 0.2.15 | A permission written down once was still missed, and the script that… |
| [`024.232`](024-deferred-review-findings-resolved.md#024232-the-fixture-proving-a-check-has-teeth-lost-its-own-teeth-when-a-version-shipped) | fixed | 0.2.15 | The fixture proving a check has teeth lost its own teeth when a vers… |
| [`024.233`](024-deferred-review-findings-resolved.md#024233-the-guard-against-naming-a-shipped-release-could-not-fire-until-the-release-had-shipped) | fixed | 0.2.16 | The guard against naming a shipped release could not fire until the … |
| [`024.234`](024-deferred-review-findings-resolved.md#024234-the-plugin-subsystem-was-unreachable-from-the-shipped-product-and-eight-documents-said-otherwise) | fixed | 0.2.16 | The plugin subsystem was unreachable from the shipped product, and e… |
| [`024.237`](#024237-four-shapes-stopped-reporting-by-declining-on-the-body-not-by-reading-it) | open | 0.4.0 | Four shapes stopped reporting by declining on the body, not by readi… |
| [`024.238`](024-deferred-review-findings-resolved.md#024238-alias-to-a-method-an-included-module-declares-is-reported-as-unknown) | fixed | 0.3.0 | `alias` to a method an included module declares is reported as unkno… |
| [`024.239`](024-deferred-review-findings-resolved.md#024239-a-name-ruby-gives-every-object-reported-missing-because-rbs-omits-it) | fixed | 0.2.16 | A name Ruby gives every object, reported missing because RBS omits it |
| [`024.240`](024-deferred-review-findings-resolved.md#024240-hover-answers-nothing-in-a-view-where-completion-and-go-to-definition-both-answer) | fixed | 0.2.16 | Hover answers nothing in a view where completion and go-to-definitio… |
| [`024.241`](024-deferred-review-findings-resolved.md#024241-find-references-answers-from-a-comment-a-bare-literal-and-end) | fixed | 0.2.16 | Find References answers from a comment, a bare literal, and `end` |
| [`024.242`](024-deferred-review-findings-resolved.md#024242-a-class-held-in-a-local-variable-loses-an-rbs-overload) | fixed | 0.2.16 | A class held in a local variable loses an RBS overload |
| [`024.243`](#024243-signature-help-says-nothing-for-a-receiverless-call-inside-a-module-body) | open | 0.4.0 | Signature help says nothing for a receiverless call inside a module … |
| [`024.244`](024-deferred-review-findings-resolved.md#024244-preparerename-is-refused-on-any-class-or-module-written-inside-a-module-class-body-while-th) | fixed | 0.2.17 | prepareRename is refused on any class or module written inside a `mo… |
| [`024.245`](024-deferred-review-findings-resolved.md#024245-server-prepare-rename-result-does-not-call-ensure-reference-index-current-while-referenc) | fixed | 0.3.0 | `Server#prepare_rename_result` does not call `#ensure_reference_inde… |
| [`024.246`](024-deferred-review-findings-resolved.md#024246-one-unresolvable-include-in-a-project-s-own-rbs-makes-the-engine-report-a-method-the-same-file) | fixed | 0.2.17 | One unresolvable `include` in a project's own RBS makes the engine r… |
| [`024.247`](024-deferred-review-findings-resolved.md#024247-a-constant-declared-only-in-a-signature-file-is-reported-cannot-resolve-constant-when-that-fil) | fixed | 0.2.17 | A constant declared only in a signature file is reported `cannot res… |
| [`024.248`](024-deferred-review-findings-resolved.md#024248-diagnostics-engine-ancestor-names-calls-ancestorentry-name-with-no-identified-guard-so) | fixed | 0.2.17 | `Diagnostics::Engine#ancestor_names` calls `AncestorEntry#name` with… |
| [`024.249`](024-deferred-review-findings-resolved.md#024249-queryservice-member-available-on-asked-the-signature-environment-about-the-union-branch-s-own) | fixed | 0.2.17 | `QueryService#member_available_on?` asked the signature environment … |
| [`024.250`](024-deferred-review-findings-resolved.md#024250-queryservice-member-available-on-cannot-answer-about-a-nil-branch-so-every-member-of-a-nil) | fixed | 0.2.17 | `QueryService#member_available_on?` cannot answer about a `nil` bran… |
| [`024.251`](024-deferred-review-findings-resolved.md#024251-def-local-method-is-recorded-on-the-lexically-enclosing-class) | fixed | 0.2.17 | `def <local>.method` is recorded on the lexically enclosing class |
| [`024.252`](024-deferred-review-findings-resolved.md#024252-conditional-says-a-method-is-on-every-branch-of-a-union-when-one-branch-declares-it-private-s) | fixed | 0.2.17 | `conditional` says a method is on every branch of a Union when one b… |
| [`024.253`](024-deferred-review-findings-resolved.md#024253-every-object-kernel-inherited-name-on-a-union-of-two-workspace-classes-was-labelled-one-branch-o) | fixed | 0.2.17 | Every Object/Kernel-inherited name on a Union of two workspace class… |
| [`024.254`](024-deferred-review-findings-resolved.md#024254-active-record-s-own-api-is-labelled-one-branch-only-on-a-union-of-two-models-so-save-destroy) | fixed | 0.2.17 | Active Record's own API is labelled one-branch-only on a Union of tw… |
| [`024.255`](024-deferred-review-findings-resolved.md#024255-completion-answered-nothing-at-all-for-a-union-of-class-objects-k-cond-foo-bar-then-k) | fixed | 0.2.17 | Completion answered nothing at all for a Union of class objects — `k… |
| [`024.256`](024-deferred-review-findings-resolved.md#024256-go-to-definition-still-answers-nothing-for-a-union-of-class-objects-and-this-patch-makes-the-as) | fixed | 0.2.17 | Go to definition still answers nothing for a Union of class objects,… |
| [`024.257`](024-deferred-review-findings-resolved.md#024257-an-unrooted-compact-class-path-whose-head-resolves-outward-gets-the-enclosing-frame-glued-onto-i) | fixed | 0.2.17 | An unrooted compact class path whose head resolves OUTWARD gets the … |
| [`024.258`](024-deferred-review-findings-resolved.md#024258-visit-def-node-s-method-level-ensure-popped-scope-stack-for-a-push-its-early-return-ha) | fixed | 0.2.17 | `#visit_def_node`'s method-level `ensure` popped `@scope_stack` for … |
| [`024.259`](024-deferred-review-findings-resolved.md#024259-the-same-ensure-restored-included-hook-parameter-from-a-local-the-early-return-never-assi) | fixed | 0.2.17 | The same `ensure` restored `@included_hook_parameter` from a local t… |
| [`024.260`](024-deferred-review-findings-resolved.md#024260-textdocument-rename-on-a-local-misses-every-binding-written-as-a-compound-or-target-node) | fixed | 0.2.17 | `textDocument/rename` on a local misses every binding written as a c… |
| [`024.261`](024-deferred-review-findings-resolved.md#024261-visit-lambda-node-pushes-no-scope-frame-where-visit-block-node-does-so-a-lambda-body-shar) | fixed | 0.2.17 | `#visit_lambda_node` pushes no scope frame where `#visit_block_node`… |
| [`024.262`](024-deferred-review-findings-resolved.md#024262-rename-leaves-a-closed-over-local-s-uses-inside-a-block-behind-producing-code-that-no-longer-ru) | fixed | 0.2.17 | Rename leaves a closed-over local's uses inside a block behind, prod… |
| [`024.263`](024-deferred-review-findings-resolved.md#024263-rename-rewrites-an-arrow-lambda-s-own-parameter-when-renaming-a-same-named-enclosing-local-sile) | fixed | 0.2.17 | Rename rewrites an arrow lambda's own parameter when renaming a same… |
| [`024.264`](024-deferred-review-findings-resolved.md#024264-a-false-unknown-method-on-a-concern-s-class-methods) | fixed | 0.2.17 | a false `unknown-method` on a concern's class methods |
| [`024.265`](024-deferred-review-findings-resolved.md#024265-the-same-ensure-popped-the-scope-stack-without-a-matching-push-so-one-def-inside-a-nameless) | fixed | 0.2.17 | the same `ensure` popped the scope stack without a matching push, so… |
| [`024.266`](024-deferred-review-findings-resolved.md#024266-find-references-and-rename-ignore-four-of-prism-s-six-local-variable-node-kinds) | done | 0.2.17 | Find References and Rename ignore four of Prism's six local-variable… |
| [`024.267`](024-deferred-review-findings-resolved.md#024267-latent-spec-suite-only) | done | 0.2.17 | latent, spec suite only |
| [`024.268`](024-deferred-review-findings-resolved.md#024268-agentprocessmanager-force-kill-the-sigkill-escalation-behind-a-sigterm-that-never-landed-i) | fixed | 0.2.17 | `AgentProcessManager#force_kill` — the SIGKILL escalation behind a S… |
| [`024.269`](024-deferred-review-findings-resolved.md#024269-agentprocessmanager-alive-is-asserted-only-in-the-false-direction) | fixed | 0.2.17 | `AgentProcessManager#alive?` is asserted only in the false direction |
| [`024.270`](024-deferred-review-findings-resolved.md#024270-not-a-defect-recorded-so-nobody-promotes-it-into-one) | done | 0.2.17 | Not a defect — recorded so nobody promotes it into one |
| [`024.271`](024-deferred-review-findings-resolved.md#024271-renaming-a-local-leaves-def-local-method-behind-so-the-file-stops-running) | fixed | 0.2.17 | Renaming a local leaves `def <local>.method` behind, so the file sto… |
| [`024.272`](024-deferred-review-findings-resolved.md#024272-renaming-a-local-leaves-every-value-omitted-shorthand-behind-so-the-rename-is-still-partial) | fixed | 0.2.17 | Renaming a local leaves every value-omitted shorthand behind, so the… |
| [`024.273`](024-deferred-review-findings-resolved.md#024273-renaming-a-local-that-is-a-parameter-leaves-the-parameter-behind-and-the-answer-can-be-silent) | fixed | 0.3.0 | Renaming a local that is a parameter leaves the parameter behind, an… |
| [`024.274`](024-deferred-review-findings-resolved.md#024274-an-underscore-prefixed-target-is-not-recorded-because-ruby-lets-one-pattern-bind-it-twice) | fixed | 0.3.0 | An underscore-prefixed target is not recorded, because Ruby lets one… |
| [`024.275`](024-deferred-review-findings-resolved.md#024275-a-workspace-identity-example-fails-only-in-a-full-suite-run-and-not-reproducibly) | fixed | 0.3.2 | A workspace-identity example fails only in a full-suite run, and not… |
| [`024.276`](024-deferred-review-findings-resolved.md#024276-a-closing-pass-retargeted-54-entries-at-0-3-0-and-53-of-them-give-one-of-two-pasted-reasons) | fixed | 0.2.17 | A closing pass retargeted 54 entries at 0.3.0, and 53 of them give o… |
| [`024.277`](024-deferred-review-findings-resolved.md#024277-a-local-variable-s-identity-follows-the-cref-so-a-block-that-changes-self-splits-it) | fixed | 0.2.17 | A local variable's identity follows the cref, so a block that change… |
| [`024.278`](024-deferred-review-findings-resolved.md#024278-a-local-variable-s-identity-has-no-file-in-it-so-renaming-one-edits-another-file) | fixed | 0.2.17 | A local variable's identity has no file in it, so renaming one edits… |
| [`024.279`](024-deferred-review-findings-resolved.md#024279-the-rename-oracle-put-the-caret-in-the-wrong-place-so-its-first-numbers-were-part-measurement) | fixed | 0.2.17 | The rename oracle put the caret in the wrong place, so its first num… |
| [`024.280`](024-deferred-review-findings-resolved.md#024280-renaming-a-local-bound-by-a-regexp-named-capture-leaves-the-capture-silently) | fixed | 0.2.18 | Renaming a local bound by a regexp named capture leaves the capture,… |
| [`024.281`](024-deferred-review-findings-resolved.md#024281-the-erb-integration-test-asserted-an-answer-the-engine-correctly-declines) | fixed | 0.2.17 | The `.erb` integration test asserted an answer the engine correctly … |
| [`024.282`](024-deferred-review-findings-resolved.md#024282-ci-was-red-on-main-for-a-week-and-nothing-in-the-tree-said-so) | fixed | 0.2.17 | CI was red on `main` for a week and nothing in the tree said so |
| [`024.283`](024-deferred-review-findings-resolved.md#024283-the-packaged-core-is-driven-only-on-linux-so-the-macos-build-is-still-smoke-tested) | fixed | 0.3.2 | The packaged Core is driven only on Linux, so the macOS build is sti… |
| [`024.284`](024-deferred-review-findings-resolved.md#024284-nothing-local-can-see-that-ci-is-red-and-preflight-does-not-run-the-extension) | fixed | 0.2.18 | Nothing local can see that CI is red, and preflight does not run the… |
| [`024.285`](024-deferred-review-findings-resolved.md#024285-three-interpreter-sessions-resolved-against-whatever-the-machine-had-installed) | fixed | 0.2.17 | Three interpreter sessions resolved against whatever the machine had… |
| [`024.286`](024-deferred-review-findings-resolved.md#024286-a-session-recorded-on-one-ruby-was-compared-against-another-so-the-3-3-job-called-true-answers-wrong) | fixed | 0.2.17 | A session recorded on one Ruby was compared against another, so the … |
| [`024.287`](024-deferred-review-findings-resolved.md#024287-the-informational-ruby-4-0-job-reported-five-checkout-failures-and-one-real-difference) | fixed | 0.2.18 | The informational Ruby 4.0 job reported five checkout failures and o… |
| [`024.288`](024-deferred-review-findings-resolved.md#024288-ruby-4-0-puts-a-fourth-name-on-object-that-rbs-does-not-declare) | fixed | 0.3.2 | Ruby 4.0 puts a fourth name on Object that RBS does not declare |
| [`024.289`](#024289-a-class-that-includes-an-unread-module-is-not-checked-at-class-level-so-a-typo-there-is-silent) | open | 0.4.0 | A class that includes an unread module is not checked at class level… |
| [`024.290`](#024290-nothing-is-reported-about-a-call-whose-receiver-is-object) | open | 0.4.0 | Nothing is reported about a call whose receiver is `Object` |
| [`024.291`](024-deferred-review-findings-resolved.md#024291-a-repeated-key-in-a-metadata-block-is-resolved-silently-and-one-of-them-discarded-a-withdrawal) | fixed | 0.2.18 | A repeated key in a metadata block is resolved silently, and one of … |
| [`024.292`](024-deferred-review-findings-resolved.md#024292-045-disagrees-with-its-own-table-about-what-0-3-0-is-blocked-on) | fixed | 0.3.0 | `045` disagrees with its own table about what 0.3.0 is blocked on |
| [`024.293`](024-deferred-review-findings-resolved.md#024293-check-pinned-mutations-rb-reads-a-skipped-example-as-a-mutation-that-escaped) | fixed | 0.3.0 | `check_pinned_mutations.rb` reads a skipped example as a mutation th… |
| [`024.294`](#024294-a-template-s-ivar-receiver-is-not-checked-and-its-type-is-one-action-s) | open | 0.4.0 | A template's `@ivar` receiver is not checked, and its type is one ac… |
| [`024.295`](#024295-the-gem-index-is-fetched-on-every-boot-and-persisted-nowhere) | open | 0.4.0 | The gem index is fetched on every boot and persisted nowhere |
| [`024.296`](024-deferred-review-findings-resolved.md#024296-renaming-a-local-a-pattern-also-binds-rewrites-the-rest-and-leaves-the-pattern) | fixed | 0.3.2 | Renaming a local a pattern also binds rewrites the rest and leaves t… |
| [`024.297`](#024297-call-hierarchy-lists-no-callee-reached-through-send-super-or-a-macro) | open | 0.4.0 | Call hierarchy lists no callee reached through `send`, `super` or a … |
| [`024.298`](#024298-an-inlay-hint-on-foo-new-names-new-s-parameters-not-initialize-s) | open | 0.4.0 | An inlay hint on `Foo.new(...)` names `new`'s parameters, not `initi… |
| [`024.299`](#024299-completion-on-a-relation-offers-none-of-the-model-s-own-scopes-or-class-methods) | open | 0.4.0 | Completion on a relation offers none of the model's own scopes or cl… |
| [`024.300`](#024300-ivar-completion-offers-nothing-from-a-superclass-or-an-included-concern) | open | 0.4.0 | `@ivar` completion offers nothing from a superclass or an included c… |
| [`024.301`](#024301-the-route-helper-quick-fix-ignores-the-path-url-split-and-the-helper-s-arity) | open | 0.4.0 | The route-helper quick fix ignores the `_path`/`_url` split and the … |
| [`024.302`](#024302-the-def-quick-fix-is-offered-for-one-receiver-shape-of-three) | open | 0.4.0 | The `def` quick fix is offered for one receiver shape of three |
| [`024.303`](#024303-a-multiple-assignment-s-targets-get-no-inlay-hint) | open | 0.4.0 | A multiple assignment's targets get no inlay hint |
| [`024.304`](#024304-the-gem-backed-check-is-silenced-by-any-class-body-call-the-parser-cannot-read) | open | 0.4.0 | The gem-backed check is silenced by any class-body call the parser c… |
| [`024.305`](024-deferred-review-findings-resolved.md#024305-one-name-six-modules-and-the-index-keeps-the-empty-one) | fixed | 0.3.2 | One name, six modules, and the index keeps the empty one |
| [`024.306`](024-deferred-review-findings-resolved.md#024306-the-0-3-0-record-states-as-measured-that-a-method-call-candidate-never-resolves-to-a-constant) | fixed | 0.3.2 | The 0.3.0 record states as measured that a `:method_call` candidate … |
| [`024.307`](024-deferred-review-findings-resolved.md#024307-the-capability-suite-s-own-fixtures-cannot-reach-six-shapes-the-release-found) | fixed | 0.3.2 | The capability suite's own fixtures cannot reach six shapes the rele… |
| [`024.308`](024-deferred-review-findings-resolved.md#024308-referenceresolver-resolve-states-no-contract-about-alignment) | fixed | 0.3.2 | `ReferenceResolver#resolve` states no contract about alignment |
| [`024.309`](024-deferred-review-findings-resolved.md#024309-the-quick-fix-e2e-example-asserts-that-the-result-parses-which-both-answers-do) | fixed | 0.3.2 | The quick-fix E2E example asserts that the result parses, which both… |
| [`024.310`](024-deferred-review-findings-resolved.md#024310-a-range-arity-reads-takes-0-1-argument) | fixed | 0.3.2 | A range arity reads "takes 0..1 argument" |
| [`024.311`](024-deferred-review-findings-resolved.md#024311-referencecandidate-s-comment-omits-a-field-four-readers-use) | fixed | 0.3.2 | `ReferenceCandidate`'s comment omits a field four readers use |
| [`024.312`](024-deferred-review-findings-resolved.md#024312-the-release-record-has-one-direction-of-the-ivar-split-and-not-the-other) | fixed | 0.3.2 | The release record has one direction of the ivar split and not the o… |
| [`024.313`](024-deferred-review-findings-resolved.md#024313-four-comment-lines-and-a-chain-sit-at-the-wrong-indentation) | fixed | 0.3.2 | Four comment lines and a chain sit at the wrong indentation |
| [`024.314`](024-deferred-review-findings-resolved.md#024314-a-comment-numbers-a-schema-bump-that-was-not-made) | fixed | 0.3.2 | A comment numbers a schema bump that was not made |
| [`024.315`](024-deferred-review-findings-resolved.md#024315-inlay-hints-label-block-parameters-and-no-release-note-says-so) | fixed | 0.3.2 | Inlay hints label block parameters, and no release note says so |
| [`024.316`](024-deferred-review-findings-resolved.md#024316-two-lines-each-drop-a-top-level-call-and-only-both-together-are-pinned) | fixed | 0.3.2 | Two lines each drop a top-level call, and only both together are pin… |
| [`024.317`](024-deferred-review-findings-resolved.md#024317-six-of-the-documentation-map-s-trigger-rows-have-nothing-enforcing-them) | fixed | 0.3.2 | Six of the documentation map's trigger rows have nothing enforcing t… |
| [`024.318`](#024318-a-workspace-directory-shaped-like-a-gem-path-would-be-attributed-to-a-gem) | open | 0.4.0 | A workspace directory shaped like a gem path would be attributed to … |
| [`024.319`](#024319-a-bare-name-no-signature-declares-is-still-read-as-the-one-gem-class-sharing-its-last-segment) | open | 0.4.0 | A bare name no signature declares is still read as the one gem class… |
| [`024.320`](#024320-no-check-knows-which-lock-guards-what) | open | 0.4.0 | No check knows which lock guards what |
| [`024.321`](#024321-a-stdlib-class-can-be-answered-about-but-not-judged-against-the-half-0-4-0-left) | open | 0.4.0 | A stdlib class can be answered about but not judged against — the ha… |
| [`024.322`](#024322-the-server-never-passes-bundle-context-so-gem-rbs-is-never-loaded-while-the-cache-fingerprint-hashes-the-lockfile-that-decides-it) | open | 0.4.0 | The server never passes bundle_context, so gem RBS is never loaded -… |
| [`024.323`](024-deferred-review-findings-resolved.md#024323-the-define-quick-fix-writes-a-file-that-does-not-parse-on-a-class-made-by-assignment) | fixed | 0.4.0 | The Define quick fix writes a file that does not parse, on a class m… |
| [`024.R1`](#024R1-rails-specific-behaviour-has-no-explicit-boundary-roadmap-1-0-0) | open | 1.0.0 | Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0) |
| [`024.R2`](024-deferred-review-findings-resolved.md#024R2-argument-type-checking-done-0-2-0) | done | 0.2.0 | Argument *type* checking (done, 0.2.0) |
| [`024.R3`](#024R3-feature-parity-roadmap-measured-against-pylance) | open | 1.0.0 | Feature parity roadmap, measured against Pylance |
| [`024.R4`](#024R4-only-one-platform-is-published-or-verified-roadmap-1-0-0) | open | 1.0.0 | Only one platform is published or verified (roadmap, 1.0.0) |
| [`024.R5`](024-deferred-review-findings-resolved.md#024R5-a-reopened-gem-class-still-looks-closed-done-0-1-7) | done | 0.1.7 | A reopened gem class still looks closed (done, 0.1.7) |
| [`024.R6`](024-deferred-review-findings-resolved.md#024R6-reading-an-instance-variable-that-is-never-assigned-done-0-2-0) | done | 0.2.0 | Reading an instance variable that is never assigned (done, 0.2.0) |
| [`024.R7`](024-deferred-review-findings-resolved.md#024R7-index-what-the-gems-actually-define-and-keep-it-fresh-roadmap-0-3-0) | done | 0.3.0 | Index what the gems actually define, and keep it fresh (roadmap, 0.3… |
| [`024.R8`](024-deferred-review-findings-resolved.md#024R8-completion-does-nothing-until-you-type-a-dot-done-0-2-0) | done | 0.2.0 | Completion does nothing until you type a dot (done, 0.2.0) |
| [`024.R9`](024-deferred-review-findings-resolved.md#024R9-this-register-outgrew-its-file-and-0-3-0-moves-it) | done | 0.3.0 | This register outgrew its file, and 0.3.0 moves it |
| [`024.R10`](#024R10-the-repository-is-closed-to-external-contributions-until-1-0-0-roadmap-1-0-0) | open | 1.0.0 | The repository is closed to external contributions until 1.0.0 (road… |

---

## 024.13 A reopened core class looks closed, in both directions

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

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

### 0.2.15: it cannot be observed before `024.129`, so it moves beside it

Attempted, with the entry's own fixture and a control:

```
without the reopening:  no unknown-method report for `a.second`
                        or `a.totally_bogus`
with the reopening:     the same — no report either way
```

**Nothing is reported on a core-library receiver at all**, which is
`024.129`. So the experiment cannot distinguish "the reopening wrongly
closed the chain" from "this receiver is never reported on", and neither
half of this entry — the false report on `a.second`, the correct one on
`a.totally_bogus` — is observable yet.

That is a **scheduling fact, not a reprieve**: `024.13` is downstream of
`024.129`, which is in the design-decision set, so it moves to 0.2.16
beside it. Fixing it first would mean writing a fix whose effect nothing
can see, and pinning it with a fixture that passes for the wrong reason.

*Found by trying rather than by reading the two entries side by side.
The dependency is not stated in either.*

### Attempted in 0.2.16, measured, and reverted

**It reproduces, and more strongly than this entry's own 0.2.15 note
believes.** That note says the defect "cannot be observed before
`024.129`" because the experiment used container literals, which are
`Generic`/`Hash[Unknown]` and outside the gate. A **String** literal is
inside it. Driven with a control:

    workspace reopens String:  ["String has no method named `squish`",
                               "String has no method named `blank?`"]
    workspace does not:        []
    `s.upcase` in both arms:   never reported

`upcase` staying silent is the control that matters — RBS is loaded and
resolving. What changes is that the workspace now *declares* `String`,
and `MethodResolver#accounted_for?` reads "the workspace declares this
ancestor" as "the workspace can enumerate it".

**The fix attempted was a proxy, and the proxy is too wide.** A new
`#reopens_foreign_class?` — the workspace declares the class *and* the
signature environment already knew it, with the project's own `sig/`
excluded via a new `Environment#declared_by_project_sig?` reading RBS's
recorded buffer paths. The exclusion works (`::Widget` from a project
sig answers true, `::String` false), and a corpus pass measured 11 false
reports removed and 0 introduced.

**Four examples then failed, all the same shape: a typo stopped being
reported.**

    class Object
      def self.foo; end     # an innocuous reopening
    end
    Widget.nope             # a typo, and it went silent

`object_singleton_chain_spec.rb:58`, `:64`,
`class_object_ancestors_spec.rb:85`, `unreadable_macro_spec.rb:167`. The
first of those carries its own comment saying why it exists: "a name
`Object` does *not* declare is still reported, so the chain gained a
link rather than losing its edge." The proxy removes that edge.

Reverted. This is `024.224`'s shape from the same release — a fix that
buys false positives by spending true ones — and `048`'s finding
repeating a third time.

**The real fix is already scheduled.** `squish` and `blank?` are
activesupport's, and this engine does not index what gems define. That
is `024.R7`, a 0.3.0 item, which `045` records as the dependency five of
0.3.0's nine promises share. Reopening is a *proxy* for "this project
probably loads gems that patch core classes", and a proxy that cannot
tell activesupport from `def self.foo` costs more than it buys. Nothing
narrower was found: the distinction the proxy needs is exactly the
enumeration question `024.R7` answers by asking the running application.

**Two things worth keeping from the attempt.** The reproduction above,
with its control — this entry previously had none that fired. And
`Environment#declared_by_project_sig?`'s shape: RBS records the buffer
each declaration was parsed from, so "is this class declared by the
project's own sig/" is answerable exactly rather than by guessing at
names. Whoever builds `024.R7` will want that.

**And the target moves with it, to 0.3.0.** The yaml said `0.2.16`
while the paragraph above said the fix is `024.R7`, which is a 0.3.0
item — a schedule no check can see, because the shipped-release guard
only fires once a release is tagged. `024.85` found it by resting an
argument on it: that entry ships 39 new reports of exactly this shape
and had written "when `024.13` is fixed the 39 go with it" on the
strength of a `target:` this entry's own body had already invalidated.


**Driven at 0.3.0: the false report is gone, the silence is not.**
With a Runtime Agent connected -- which is what the entry predicted
would close the wrong-answer half -- a reopened `Array` no longer
produces `a.second`. Neither does it produce `a.totally_bogus_method`,
which the entry expected to be correctly reported.

So what is left is a decline rather than a wrong answer, and a
smaller finding than the entry describes. Re-triage on that basis
rather than on the entry's own wording, which was written when both
halves were live.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** The false report is
gone and what is left is a decline on a reopened core class -- a
repair of the remaining half, and a smaller one than the entry's
title.

## Not attempted in 0.3.2: what is left is a decline, not a wrong answer

Driven at 0.3.0 and what is left is a *decline*: with an Agent
connected a reopened `Array` no longer reports `a.second`, and it does
not report `a.totally_bogus_method` either. Turning that silence back
into an answer means knowing what the gems define for a class the
workspace has partly reopened, and the entry's own record of the
attempt says why a proxy for it does not work — `#reopens_foreign_class?`
removed 11 false reports, introduced none, and took four true ones
with it, one of whose specs states in its own comment that it exists
to keep that edge.

Without an Agent the answer has to come from somewhere else, and
building that somewhere is capability, which `docs/PUBLISHING.md`
puts outside a patch. Moved to 0.4.0. The published limitation stands
unchanged in both languages, because what it describes is still true.

## 0.3.3: the version marker in the title is dropped, having been false for four retargets

The heading carried a bare `(0.3.x)` from 0.1.9, when this entry had no
yaml block at all and that parenthetical was its only schedule
statement — written while the Direction above still read "Scheduled with
`024.R7`", then a 0.3.0 item. The target has since moved to 0.2.16, then
0.3.0, then 0.3.2, then 0.4.0, each move argued in the sections above,
and the title moved with none of them. 0.3.0, 0.3.1 and 0.3.2 have all
shipped, so an open entry was titled with a closed release family and the
generated Index rendered the entry's status, its `target: 0.4.0` and a
contradicting `(0.3.x)` in one row.

**Dropped rather than re-spelled as the current target.** This file's
legend says the yaml block "is the entry's status — the prose beneath it
adds narrative and does not restate it", and a version in the heading is
a second place that has to agree with it. It is also a place no check can
see: `open_entries_targeting_a_shipped_release` reads the yaml `target:`
and never the parsed title, so a heading naming a shipped release does
the exact thing that guard forbids through the one channel it cannot
read. That is why it survived four retargets.

Nothing about the work changes. What is left is the decline described
above, `target: 0.4.0` stands, and `docs/KNOWN_LIMITATIONS.md` and its
`.ja` twin cite this entry by number rather than by title, so the marker
never reached a user.

## 024.18 The unassigned-`@ivar` check cannot enumerate what it needs to

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

and **blocked on 024.R7** for the part that needs it. Three of the five shapes are closed in 0.2.0 by staying silent rather than guessing: a class-body call this analysis does not model (which covers every gem macro), a view that renders anything, and everything rounds 3 and 4 fixed. What is left is *precision* -- turning those two silences back into answers -- and one shape that is still wrong rather than silent, and one that is wrong only at depth two or more:

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

**Re-triaged in 0.2.17** (`024.276`). The enumeration question really is what blocks this one: the check needs a witness for what a gem-backed controller assigns, and neither the static chain nor the workspace index can supply it. That is `024.R7`, and 0.3.0 keeps it for that reason rather than because a closing pass said so. Not re-driven since 0.2.16.



**Not driven at 0.3.0.** Its own body says it is blocked on `024.R7`
for the part that needs it, and `024.290` now records that R7 as
shipped carries no core classes -- so the blocker is still there and
is now measured. The rest of it is view-side precision, which needs
the `capabilities_spec` Rails harness rather than the probes this
sweep used.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Turning the
unassigned-`@ivar` check's silences into answers adds what the
product can say, and its own blocker is `024.R7`'s scope.

**The blocker is gone, and the cross-controller shape was driven in
0.3.1.** `024.R7` shipped in 0.3.0, so the attribution this entry
waited for exists. The first of its two remaining shapes reproduces
as written, and with a control:

    A  view reads `@widget`, which only WidgetsController assigns,
       and WidgetsController renders "articles/show"
       -> [unassigned-ivar] `@widget` is never assigned before this is read
    B  CONTROL: the same assignment moved into the view's own action
       -> (no diagnostics)

A false report on code that runs, which is the direction section 0
ranks worst — and it is *published*, not deferred, because
`unassigned-ivar` is on by default.

**It also reaches the type side, which this entry did not say.** The
same blindness makes hover answer `Post`, completion offer Post's
methods, and `explainType` answer `{type: "Post"}` on a template
`WidgetsController#index` renders with a `Comment`. So the "precision"
half is not only a silence to be turned into an answer; three shipped
capabilities already answer, and answer wrongly, on the same shape.
`024.294` is the fourth reader of the same fact and is the one that
declines.

What closes all four is one thing: a reverse lookup from a template
path to every action that renders it. The index already holds every
literal render target, so this is a lookup rather than new evidence —
and until it exists, no consumer of `#ivars_for_view` should be given
more authority than it has.
## 024.19 The argument-type check judges against a class the receiver is not

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

Reported by an independent review that drove the engine over 25 installed gems; not reproduced from a fixture here, which is why it is recorded rather than fixed.

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
The entry's own reported instance was driven directly. From core, with no other corpus run in flight (`ps -axo pid=,command= | grep corpus_diagnostics` empty first):

  OVALLSP_SIGNATURE_ROOT=/opt/homebrew/lib/ruby/gems/3.4.0/gems/prism-1.9.0 \
    bundle exec ruby ../scripts/corpus_diagnostics.rb \
    /opt/homebrew/lib/ruby/gems/3.4.0/gems/prism-1.9.0/lib

  corpus-diagnostics: cwd=core
  corpus-diagnostics: revision=5d20fe7877e37862c077f30c101fe7d9dfe2fd38
  corpus-diagnostics: dirty-tracked-files=0
  corpus-diagnostics: ovallsp-version=0.2.13
  corpus-diagnostics: signature-root=/opt/homebrew/lib/ruby/gems/3.4.0/gems/prism-1.9.0
  corpus-diagnostics: corpus-files=41
  corpus-diagnostics: corpus-sha256=8447e7cf624dc129d5668f70a2a18bc5cb9ecfcc4638d29b72a6f129630e7a8c
  corpus-diagnostics: count.unresolved-constant=392

`grep -c '^argument-type' prism.out` => 0. Not one argument-type report over the whole gem, with the gem's own sig loaded.

At the exact reported location — prism-1.9.0/lib/prism/translation/parser.rb line 320, `::Parser::Source::Comment.new(build_range(comment.location, offset_cache))` — the only reports are (0-based line 319):

  unresolved-constant  .../translation/parser.rb:319:28  cannot resolve constant `::Parser::Source::Comment`
  unresolved-constant  .../translation/parser.rb:319:20  cannot resolve constant `::Parser::Source`
  unresolved-constant  .../translation/parser.rb:319:12  cannot resolve constant `::Parser`

This also falsifies the entry's own second paragraph, which says "precisely when the fallback fires, the full constant is *not* reported unresolvable. Only its unresolvable prefixes are." The FULL constant is reported, alongside its prefixes.

Fixture-level confirmation (<scratch> and specs_19b.rb, project sig declaring `class Widg
```

</details>

### Driven again in 0.2.16, and it reproduces — the half that is fixed is not the half this entry names

A triage pass reported this entry already fixed elsewhere, and an
independent verifier agreed. **Both were wrong**, and the way they were
wrong is worth more than the correction: they drove the *rooted and
namespaced* spellings, which really are fixed — `resolve_type_symbol_locked`
requires an exact match for a leading `::` and a `namespace_suffix?` match
otherwise (`024.78`) — and did not drive the **bare** name, which is what
the title and the published limitation are about.

Driven at HEAD, `sig/` declaring `Vendor::Gadgets::Widget.make: (Integer) -> String`
and the workspace declaring the same class:

    module Somewhere
      class User
        def go
          Widget.make("nope")
        end
      end
    end

    argument-type  app.rb:9:18  `make` expects Integer here, but String is given

Taken from the interpreter rather than reasoned about:

    $ ruby -e '
    module Vendor; module Gadgets; class Widget; def self.make(n) = n.to_s; end; end; end
    module Somewhere; class User; def go = Widget.make(1); end; end
    Somewhere::User.new.go'
    # => -e:3:in 'Somewhere::User#go': uninitialized constant Somewhere::User::Widget (NameError)
    # =>     from -e:5:in '<main>'
    # ruby 3.4.10

Ruby cannot see that constant from there at all — nesting is
`Somewhere::User`, `Somewhere`, `Object` — and the engine resolves it by
last segment and then judges an argument against it. So the report is
about a call that does not exist, on a class the receiver is not, which
is exactly what the title says.

**What this says about the method, not the entry.** A refutation is the
dangerous direction here, which is why the pass had a verifier at all;
this one agreed and was still wrong, because it inherited the first
agent's *fixture* rather than the entry's claim. A verifier given the
same spelling to try is not an independent measurement. The cheap
countermeasure, for whoever runs the next such pass: a refutation must
re-derive its reproduction from the entry's own text and from the
paragraph the entry documents in `KNOWN_LIMITATIONS`, not from the
report it is checking.

Stays open. The residual is a constant-resolution question — respecting
`Module.nesting` for a bare name, which `Index::Cref` already models —
and not the enumeration one, so it is not blocked on `024.R7`. It is
also the area `024.47` records a rollback in, which is why it is not
being changed inside a release that already carries other changes to how
a type name is resolved.

**Re-triaged in 0.2.17** (`024.276`). A false report, so a patch is the shape: the release makes the product do what an earlier one already claimed. The residual is a constant-resolution question — respecting `Module.nesting` for a bare name, which `Index::Cref` already models — as this entry's own body says two paragraphs up. It is also the area `024.47` records a rollback in, which is the real reason to give it a change set that carries nothing else. Not re-driven since the triage agents' pass, whose method its own body criticises.

### Reproduced in 0.2.18, after two fixtures that said it was gone

`024.35` records the same trap and this entry hit it twice more. Driven
against HEAD, **two shapes are silent and either alone reads as
"fixed"**:

```
  ::Vendor::Gadgets::Widget.new.make("s")     []      rooted; 0.2.11 fixed this
  bare Widget, nested Widget declared         []      the nesting rule finds it
  bare Widget, nested Widget NOT declared     reported  <- the defect
  Widget.new.make("s") at the top level       reported  <- the control, must stay
```

The published limitation names the third exactly — "a **bare** name that
exactly one class in your workspace claims" — and it is the only one that
makes the index's last-segment path reachable.

### And the engine is right about the code it can see, which is why it moves

With no `Vendor::Gadgets::Widget` anywhere, Ruby resolves a bare `Widget`
written inside that namespace to the top-level one:

```
$ ruby -e '
class Widget; def make(n) = n; end
module Vendor; module Gadgets
  class Caller; def go = Widget.new.make("s"); end
end; end
p Vendor::Gadgets::Caller.new.go
'
# => "s"
# ruby 3.4.10
```

So the check is not applying a wrong rule. It is asserting on a
workspace that cannot see the gem where the real
`Vendor::Gadgets::Widget` lives, and **neither direction in this entry's
own Direction reaches that**: the closedness gate does not fire, because
the top-level `Widget` genuinely is closed and workspace-declared; and
"require the resolved name to end with the constant path as written"
passes, because the written path *is* `Widget`.

**Retargeted to 0.3.0, beside `024.R7`.** Knowing what the gems declare
is what makes this answerable; until then the only alternative is to
stop asserting about every bare name in a namespace, which would take
the control above with it.

**The reported instance is already fixed.** It is
`::Parser::Source::Comment.new(...)` — a *rooted* path, and 0.2.11
stopped those reaching the fallback. What remains is the bare case,
which no report in the wild has yet been attributed to.

`bare_name_argument_type_spec.rb` holds all four rows: the reproduction
pending with its reason, the two silences that misled, and the control
that makes them mean something. The entry said "not reproduced from a
fixture here"; it is now.



**Not driven at 0.3.0.** It is about `WorkspaceIndex`'s simple-name
fallback reaching the argument-type check, which `024.224`'s re-drive
touched from the other side -- that corpus's entire `argument-type`
output was `024.224`, so nothing there exercised this. A fixture that
resolves a constant path the workspace does not declare is what it
needs, and building one that fails for *this* reason rather than
another is the work.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A call judged
against a class the receiver is not is a wrong answer, which the
table puts on the patch line.

## Not attempted in 0.3.2, and the reason is this release's own change

The residual is constant resolution respecting `Module.nesting` for a
bare name — this entry's own Direction, and `024.47`'s area, where a
rollback is recorded.

0.3.2 changes how an argument's type is compared: `024.224`'s fix
makes `Engine#ancestor_names` decline when the signature chain for a
reachable name could not be built. That is one change to that
comparison. This entry is a second, and `024.47`'s closing sentence is
that two changes to how a type name is compared, in one release,
reviewed together, is how that rollback happened.

So it moves for a reason specific to this release rather than a
general one, and it moves to 0.4.0. `bare_name_argument_type_spec.rb`
holds the reproduction pending with the two silences that misled and
the control that makes them mean something; none of that is disturbed.

## 024.20 `contains?` treats an exclusive end offset as inclusive

```yaml
status: open
kind: defect
user-visible: yes
user-visible-note: >
  What remains is a decline, not a wrong report: at the `.` after a
  block, hover, completion and signature help answer nothing for a
  receiver the inferencer can type. The wrong-answer half is `024.226`,
  fixed in 0.2.15.
target: 0.4.0
```

**The half that reached users is fixed in 0.2.1**, and it was the
largest single source of wrong diagnostics this engine produced. The
receiver position a candidate records is the receiver's *exclusive* end
now, which works with the inclusive `contains?` rather than against it:
no inner element's range reaches that offset and the receiver's does, so
the walk answers with the receiver.

Measured over Ruby 3.4.7's standard library, five Rails 8.1.3 gems and
minitest, both revisions over one corpus, diffed by position:
**`unknown-method` 3,747 -> 2,095 — 1,656 removed, 4 introduced.** (Re-measured at 0.2.1's last commit, both sides printing their own tree and version first, with `unresolved-constant` identical at 9,550 on both as the control. The first reading of this — 3,362 -> 1,810, 1,556 removed — was taken four commits earlier and against minitest 5.26.0 rather than 6.0.6.)
`[w].each` reported that a workspace class has no `each`;
`listeners[:on_x]&.each` that a Symbol has none, 604 times in prism's
`dispatcher.rb` alone.

The 4 introduced are all `OpenSSL::Cipher.new(x).key_len` and its
neighbours, and they are 024.13's family rather than this one: the
receiver now resolves *correctly* to `OpenSSL::Cipher`, which the
standard library reopens in Ruby while implementing it in C, so it looks
closed and its C methods look missing. Verified against the interpreter
-- `key_len`, `iv_len` and `digest_length` all exist. Over the real
Rails application at `ovaldev` the change introduces nothing: the two
revisions are byte-identical there, because an ordinary project does not
reopen `OpenSSL::Cipher`.

`contains?` itself is still inclusive, and the entry stays open for it.
What is fixed is one caller that had been compensating for it wrongly.

`docs/design/tasks/026-0.2.1-review-loop.md` carries what round 23 found
and has not fixed, including several entries that overlap this one.

Two things about how this survived twenty-two rounds are worth keeping:

- **The document's own user-facing half described a different
  consequence.** `KNOWN_LIMITATIONS` cited 024.20 only in the paragraph
  about blocks having no type. Nothing told a reader that the engine's
  largest false-positive family was this, so no round went looking.
- **Every round measured the total and not the shape.** 3,362 is a
  number that moves for many reasons; "1,545 of them have a receiver
  ending in `]` or `)`" is one grep, and it names the cause.

`contains?` itself is still inclusive, and that is what keeps this entry
open: it blocks a correct answer 0.2.0 had to settle for approximating.

### Re-driven in 0.2.15: the reproduction above is stale, and what remains is a decline

**Neither example this entry gives still reproduces.** `wrap(Widget.new).go`
and `[w].each` report nothing, in all three modes, against a control
built through the identical `f.wrap(...).X` shape that *does* fire and
names `Wrapper` rather than `Widget` — so the receiver resolves
correctly now, rather than the whole shape being skipped. prism's
`dispatcher.rb`, where this entry records 604 `unknown-method` reports,
yields **0**. The paragraph under **Area:** still reads in the present
tense and should be read as dated to 0.2.0.

**One wrong answer that was downstream of this is fixed separately** and
has its own entry, because it has its own reproduction and its own fix:
`024.226`, an argument written as a paren-less call being judged by its
own last argument.

**What is left is a decline, not a wrong answer**, and the distinction
decides the triage. At the `.` after a block — `[1, 2].map { |x| x }.first`
— the position query hands `#infer_at` the block's exclusive end, the
inclusive `#contains?` enters `locate_in_block`, and the answer is
`Unknown`; `#receiver_type_before_dot` maps that to nil, so hover,
completion and signature help say nothing there. Measured: the
inferencer *can* type that receiver — `Array[Integer]` — and a control
at `[1, 2].first.first` answers `Integer | nil`, so only the position
query declines. 422 receivers of that shape in 883 files, 228 of them
`CallNode -> BlockNode`.

Section 0 ranks a decline below a wrong answer, and making `#contains?`
exclusive breaks 39 examples because every caller handing it an LSP
range end depends on the current rule. That is a change to a shared
position rule with a large blast radius, in service of an answer the
product currently declines to give — so it is **not** 0.2.15's work.
Retargeted, and the entry is now about that one thing.

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

**Re-triaged in 0.2.17** (`024.276`). Nothing here needs to know what a gem defines; the paragraph that said so was pasted, and this entry's own **Direction** sits a few lines above it. What is left is a **decline**, not a wrong answer, and turning a decline into an answer is capability rather than a patch — which is what keeps the target where it is. The size is measured twice over: 39 examples on the original attempt, and `048`'s re-measurement of the same move at 114 examples, 100 added diagnostics over 1,070 Rails files, and +3 net lines once its three compensations were counted. Not re-driven since 0.2.15, when the entry's own examples were found stale.


**Retargeted to 0.4.0 in 0.3.0's closing sweep.** The `.` after a
block offers nothing; making it offer something is capability, and
`048` measured the obvious fix at 114 broken examples.
## 024.22 The unassigned-`@ivar` check is silent in an application `rails new` produces

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

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




**Not driven at 0.3.0.** The claim is about what a `rails new`
application produces, so the fixture is an application rather than a
snippet, and the sweep that gave the other entries a verdict used
`corpus_diagnostics` and in-process probes. Unverified rather than
assumed to reproduce: 0.2.14 published a limitation the product did
not have by promoting an entry nobody ran.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** A check silent in
an application `rails new` produces starts answering there, which is
a new row rather than a repair.
## 024.28 Rename refuses on a macro-declared method rather than editing it

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/rename/planner.rb`
(`#uneditable_declaration`), `core/lib/ovallsp/index/declaration.rb`

`attr_accessor :name` declares `name` and `name=` at a symbol argument.
0.1.14 emitted a `WorkspaceEdit` that renamed every call site and left
the declaration behind, producing a file that does not run; 0.1.15
refuses instead, which is what `#prepare`'s own comment had always
claimed happened.

The reason reaches the Core log only. `prepare` answers `null`, so the
editor shows its own "cannot be renamed" message and never asks for the
edit; nothing in this codebase sends `window/showMessage`. The W4 row's
E2E example calls `textDocument/rename` directly and asserts an empty
edit set, so the refusal is verified and the *explanation* is not.

**This entry's Direction was wrong, and 0.2.16 tried it.** It read: give
the declaration a `name_location` covering its symbol argument "so
`attr_reader :name` can be rewritten to `attr_reader :title`", with the
`name=`/`name` asymmetry named as the hard half. `024.27` gave every
macro declaration exactly that `name_location`, and the rewrite is still
the wrong edit — for three of the five macro families that reach
`#add_generated_method` (`attr_*`, `enum`, `delegate`, against `scope`
and `define_method`), and for a
reason the asymmetry only hints at. **The macro's argument is source the
macro reads, not this method's identifier**, and rewriting it changes
whatever else that argument feeds:

- `attr_reader :name` reads `@name`. Rewriting the token gives a reader
  of `@title`, which nothing in the class assigns. Run on ruby 3.4.10:

      class W
        def initialize = @name = "n"
        attr_reader :title      # renamed from :name by hand
      end
      p W.new.title             # => nil
      p W.instance_methods(false)  # => [:title]

  That is worse than 0.1.14's failure, not better: the file still runs
  and answers `nil`. Section 0 ranks a wrong answer below no answer.
- `attr_accessor :name` declares `name` *and* `name=` from one token.
  Run on ruby 3.4.10, and pasted as it prints rather than as it reads —
  the order is the interpreter's, and an earlier draft of this entry
  tidied it into `[:name, :name=]`, which is the class of quiet
  inaccuracy the "paste the session" rule exists to catch:

      $ ruby -e 'class W; attr_accessor :name; end; p W.instance_methods(false)'
      [:name=, :name]

  One edit renames two methods while the plan holds one symbol's call
  sites, so every `w.name = x` breaks and nothing in the plan says so.
- `enum status: { active: 0 }` — **`active` is the label, not the
  stored value.** An earlier draft of this entry said "the *stored*
  value", and eight files and both languages repeated it. Driven
  against `activerecord 8.1.3.1` on ruby 3.4.10, over a sqlite3
  database in a `Dir.mktmpdir`:

      create_table(:orders) { |t| t.integer :status }
      class Order < ActiveRecord::Base
        enum :status, { active: 0, archived: 1 }
      end
      o = Order.create!(status: :active)
      p Order.statuses   # => {"active" => 0, "archived" => 1}
      p o.status         # => "active"
      p Order.connection.select_value("select status from orders")  # => 0

  The column holds `0`; `active` is the label mapped onto it. The
  refusal is still right, and for a *larger* reason than the draft
  gave: rewriting the label renames three things besides the
  predicate. Re-run with the label spelled `live` instead:

      p Order.statuses            # => {"live" => 0, "archived" => 1}
      p Order.respond_to?(:active)  # => false
      p Order.respond_to?(:live)    # => true

  — the scope, the `statuses` key, and what the attribute reads back.
- `delegate :name, to: :company` calls `company.name`. Run with
  `activesupport 8.1.3.1` on ruby 3.4.10:

      require "active_support/all"
      class Company; def name = "acme"; end
      class Order
        attr_reader :company
        def initialize = @company = Company.new
        delegate :nickname, to: :company   # the same line, name rewritten
      end
      Order.new.nickname
      # => NoMethodError: undefined method 'nickname' for an instance of Company

  **This paragraph said "under `prefix: true` the token is not even a
  substring of the generated name", and that is false.** `prefix:`
  prepends, so the token is always the tail. It was written as prose in a
  bullet list, believed for a review round, and caught by the round
  after — which is the second false claim in the same rewritten list, and
  the trigger for `024.220`'s session checker. Written as a session now,
  so something re-runs it:

      $ ruby -e '
      gem "activesupport"
      require "active_support/all"
      class Company; def name = "acme"; end
      class Order
        def company = Company.new
        delegate :name, to: :company, prefix: true
      end
      p Order.instance_methods(false).sort
      p "company_name".include?("name")
      '
      # => [:company, :company_name]
      # => true
      # ruby 3.4.10, activesupport 8.1.3.1

  Which does not change the conclusion — the token still names the
  *target's* method and rewriting it still breaks the delegation — only
  the reason given for it.

**So refusing is the end state for `attr_*`, `enum` and `delegate`**, and
0.2.16 makes the refusal say so. It had been claiming "there is no
identifier token to rewrite", which `024.27` made false; it now names the
argument's own position — `2:18` rather than the macro call's `2:3` on
`attr_accessor :name` — and says that rewriting it is not the same edit
as renaming the method.

**What is still open is narrow, and it is not what this entry used to
say.** Two shapes remain where the token *is* exactly the method's name
and nothing else depends on its spelling:

- `scope :recent, -> { … }` — the lambda never names the scope.
- `define_method(:calc) { … }` — the block never names the method.

Both are refused with the rest, and the reason is structural rather than
deliberate: `Rename::Planner` keys the refusal on
`Declaration#origin == :generated`, which is the same value for every
macro. Nothing reaching the planner says which one produced the
declaration, so it cannot separate the two shapes it could safely edit
from the three it must not.

**Direction:** carry that distinction on the declaration — whether its
`name_location` is an *exact* spelling of the method's name and the only
method that token declares — and let rename edit in place where it is.
`Declaration#origin` is the wrong carrier (`:generated` is a contract
three documents state); a separate field set at record time, where the
macro is known, is the shape. Deliberately **not** done in 0.2.16:
enabling rename for two macros is a new capability row, its E2E example,
two READMEs and two site pages, and the change set was a correction.
Retargeted from 0.2.16 to 0.3.0 for that reason.



**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Refusing is already
the right answer; what this entry wants is the *reason* reaching the
user, and nothing here sends `window/showMessage` yet.
## 024.37 The argument-type check reports nothing on measured real Ruby

```yaml
status: open
kind: defect
user-visible: yes
user-visible-note: >
  Corrected in 0.3.3. This note read, in the present tense, that on a
  workspace stating types the way the check accepts it "is not silent
  -- it reports", that every report was false, and that the question
  could not be answered until `024.224` was fixed. 0.3.2 settled that
  premise and the entry's own closing section says so: re-measured over
  rbs 4.2.0 with its own sig/ the check produces zero, with
  unresolved-constant at 369 as the control. The entry stays open for
  the different reason that section gives -- a check that has never
  produced a true report has not been shown capable of one.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`argument_type_findings`,
`sole_declared_overload`)

G15 is one of the six capability rows 0.2.0's minor bump is justified by.
Measured at `ca66774`, after this round's fixes, with
`scripts/corpus_diagnostics.rb`:

| corpus | files | `argument-type` |
|---|---|---|
| Ruby 3.4.7 stdlib + activerecord/activesupport/actionpack/actionview/activemodel 8.1.3 + minitest 6.0.6 | 2,042 | **0** |
| prism 1.6.0, with its own `sig/` loaded | 41 | **0** |

Before those fixes the same two corpora produced **795** and **151**, and
every one of them was wrong: a call judged against a signature it does
not bind to. So the check's entire measured output, over every corpus
this project has pointed it at, was false positives — and removing them
left zero. Both diffs are by position and introduce nothing.

The second row is the one that matters, because it answers the objection.
The harness loads signatures from `Dir.pwd`, so a corpus of gems is
measured with none of its own types stated, which is the check's floor by
construction. `OVALLSP_SIGNATURE_ROOT` (added with this entry) lifts that:
pointed at a gem that ships extensive RBS, the check found 151 things to
say and all 151 were wrong, and with those fixed it says nothing.

It is not inert — making `argument_type_findings` return `[]`
unconditionally fails 9 of `argument_type_spec.rb`'s examples, and the
E2E row passes. (An earlier version of this entry said 25, which was a
guess dressed as a count; a reviewer measured it.) What it is, is narrow to the point where real code
does not meet it: an RBS/RBI declaration with exactly one overload and no
`*rest`, both the declared and the inferred type a plain class with no
ancestor relation, and no operator expression in the argument. Each of
those refusals was added to remove a false positive, and each was right
on its own.

**What is open:** whether a capability whose measured yield on real code
is zero should carry a README ✅ and a capability row. Both are defensible
today — the row is verified by an example that fails if the check breaks,
which is what ✅ is defined to mean — but a user reading the matrix
expects a check that fires. The alternatives are to widen it (which the
whole entry above argues is how it produced 795 wrong reports), to mark
the row the way the `@ivar` row is now marked, or to say plainly in
`KNOWN_LIMITATIONS` what it will and will not catch.

**Direction:** measure once more with the harness pointed at a workspace
that states types in the shapes the check accepts — a project with a
hand-written `sig/`, not a gem's generated one — before deciding. A check
that fires on the code its users write and not on gems is a different
answer from one that fires nowhere.

### The Direction was run in 0.2.15, and it changed the question

The corpus it asked for is **rbs 4.0.3** -- 89 hand-written `.rbs` for
102 `.rb`, the first hand-written-signature corpus this project has
pointed the engine at. Both of the tables above still reproduce, and the
"not inert, 9 examples" count is still exact.

**What is refuted is the characterisation.** "Narrow to the point where
real code does not meet it" is not true of a workspace that states its
own types: pointed at rbs's `sig/`, the check **reports three things**.
All three are false -- the same class written two ways
(`expects RBS::TypeName here, but TypeName is given`) -- and every one
of them is `024.224`, not this entry.

So the honest statement is no longer "measured at zero on the code we
have". It is: **on a gem corpus it says nothing, and on a typed
workspace it says something false.** Section 0 ranks those in that
order, and a paragraph promoted from this entry as written would have
told users the check is quiet while what it does on their own typed
project is assert that a class is incompatible with itself.

**The open question cannot be answered yet, and that is why this
retargets.** "Should a capability whose measured yield on real code is
zero carry a README check and a capability row" rested on the yield
being zero. It is not zero on the corpus the Direction asked for; it is
negative. Fix `024.224`, re-measure, and the question becomes answerable
-- possibly with a different answer, since a check that fires correctly
on a typed workspace is a different row from one that fires nowhere.

*Two neighbouring defects came out of running this Direction and have
their own numbers: `024.223`, fixed in 0.2.15, and `024.224`. Neither is
this entry, and closing either does not close this one.*

**Re-triaged in 0.2.17** (`024.276`). Blocked on `024.224` by its own body — a check that fires nowhere is a different row from one that fires correctly on a typed workspace, and the measurement cannot be read until the namespaced-type comparison stops rejecting a type as incompatible with itself. Both are repairs to a shipped check, so both belong on the patch line and in that order.

### Re-measured in 0.2.18, and the answer to the open question is worse than zero

The entry's own note says the premise changed: on a workspace that
states types the way the check accepts, it is not silent. Driven at
HEAD against the `rbs` gem with its own `sig/` as the signature root —
109 files, `unresolved-constant` at 369 as the control:

```
  argument-type: 6

  inline_parser.rb:559  `new` expects RBS::Location here, but Location is given
  inline_parser.rb:560  `new` expects RBS::Location here, but Location is given
  prototype/runtime.rb:527  `generate_mixin` expects RBS::TypeName here, but TypeName is given
  prototype/runtime.rb:530  `generate_methods` expects RBS::TypeName ...
  prototype/runtime.rb:567  `generate_mixin` expects RBS::TypeName ...
  prototype/runtime.rb:569  `generate_methods` expects RBS::TypeName ...
```

**All six are `024.224`** — a namespaced type reported incompatible with
itself. So the honest statement of this check's measured yield is not
"zero findings" but **zero true findings, ever, on any corpus this
project has pointed it at**, and a non-zero false yield wherever types
are actually declared.

**The published limitation understated it** and said the check produces
zero. It now says what the measurement says, in both languages. An
entry that understates its own defect is harder to catch than one that
is simply wrong, which is `024.131`.

### Where the six come from, which is not where the entry looks

Traced: the *actual* side is a signature return type —
`def rbs_location: (Prism::Location) -> Location`, declared inside a
namespace, which RBS resolves to `RBS::Location` and
`Signatures::TypeConverter` then flattens to the bare string `Location`.
The *expected* side keeps its namespace. `#compatible_nominal?` reduces
the expected side with `bare_name` (leading `::` only), so it compares
`RBS::Location` against a reachable set holding `Location` and
`::Location`.

That is the example `CLAUDE.md` names in its own words: "`TypeConverter`
knows an absolute `RBS::TypeName` at the moment it builds a
`Types::Nominal`, flattens it to a String, and three downstream readers
then normalise spellings to get the identity back." The fix is not to
widen the comparison — `024.224`'s pending spec measures what that costs
— but to stop throwing the identity away.

**Retargeted to 0.3.0, beside `024.224`**, which this entry's own note
already said: "the question this entry frames cannot be answered until
it is fixed". Whether a capability row survives is a question about a
check that currently answers wrongly; fixing the wrongness comes first.


**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A check that
reports nothing where it should is repair work against `G15`, a row
0.2.0 already claimed.

## The premise this entry was waiting on is settled in 0.3.2, and what is left is not a defect

This entry could not be answered while `024.224` stood: its own
`user-visible-note` says so — on the one corpus where the check is not
silent, every report was false, and the question "what is this check's
yield" cannot be asked of an output that is entirely one defect.

`024.224`'s unbuildable-chain half is fixed -- the half that was
producing every report on this corpus. (The entry itself is open again,
narrowed to a shape no measured corpus shows; `024.224`.) Re-measured
over rbs 4.2.0 with its own `sig/`, the
check now produces **zero** there, with `unresolved-constant` unchanged
at 369 as the control. So the honest statement of its measured yield is
the one this entry's title makes: **nothing, on every corpus it has been
pointed at** — 2,042 files of stdlib, Rails gems and minitest at zero,
and now the hand-written-signature corpus at zero too.

That is no longer a wrong answer to repair. It is a check whose gates
ask for more than real code states, and widening them means knowing
what a receiver's type is where nothing declares it — the enumeration
question. Moved to 0.4.0 on that basis, and the published paragraph in
both languages now carries the zero rather than the six.

**The zero is not itself evidence the check is sound**, and the entry
stays open for that reason rather than closing beside `024.224`: a check
that has never produced a true report has not been shown to be capable
of one. Producing a deliberate mismatch a real corpus contains, and
watching it be reported, is what would settle that — and no measurement
here has done it.

## 024.38 `scope_at` copies the whole environment once per descent step

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  A cost, not an answer. It is quadratic in the number of locals in one
  scope, which real code keeps small -- 1.2ms at 100 locals, where the
  measurable curve starts. Recorded rather than fixed because the fix is
  in the inference core and the round that found it was already
  repairing the round before it.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`locate`, `capture_scope`)

`locate` calls `capture_scope(env)` at the top of *every* step, and
`capture_scope` builds a new Hash of the whole environment. Only the last
one survives. 0.2.0 is what makes it matter: `PrefixCompletion#items`
calls `scope_at` for every bare-prefix completion, so this runs on the
request path per keystroke.

Measured by a reviewer, same document, 10 iterations, parse cache warm,
against `infer_at` on the same document and position as an in-process
reference:

| locals in scope | `scope_at` | `infer_at` |
|---|---|---|
| 50 | 0.24 ms | 0.03 ms |
| 100 | 1.17 ms | 0.04 ms |
| 200 | 3.93 ms | 0.10 ms |
| 400 | 14.78 ms | 0.19 ms |
| 800 | 56.10 ms | 0.36 ms |

Four times per doubling, bounded only by `max_steps: 5000`.

**Direction:** capture on *write*, not on step. Keep the `env` reference
and the self type, and materialise the snapshot at the moment the
environment is about to be mutated -- there are nine such sites and most
are on fresh child environments. Taking the snapshot at the end instead
is wrong: `x = <cursor>` would then see `x`, because
`LocalVariableWriteNode` assigns after descending into its value.

It wants `spec/meta/workspace_index_cost_spec.rb`'s treatment -- a
source assertion -- since reversing it changes no answer.

### Fixed in 0.2.16 — and the Direction above was aimed one level too deep

Re-measured first, at `8d39437`: the curve is the entry's, and the
captures were counted alongside it. **803 snapshots for 800 locals** —
so essentially every one of them came from a single site, the re-capture
after each statement in `#locate_in_statements`, and not from `#locate`'s
per-step capture at all. `#locate` descends only into the child holding
the cursor, so its captures are bounded by nesting depth.

That makes the fix local and provably answer-preserving: **only the last
pre-cursor statement's snapshot is ever read.** Every earlier one is
overwritten before anything can look at it, and nothing can read one in
between, because a statement that *contains* the cursor is strictly after
every statement that ends before it. So the loop takes that one and skips
the rest.

| locals | `scope_at` before | after | captures before | after |
|---|---|---|---|---|
| 50 | 0.418 ms | 0.169 ms | 53 | 4 |
| 100 | 1.773 ms | 0.109 ms | 103 | 4 |
| 200 | 3.610 ms | 0.156 ms | 203 | 4 |
| 400 | 13.664 ms | 0.624 ms | 403 | 4 |
| 800 | 52.851 ms | 0.695 ms | 803 | 4 |

`infer_at` over the same walk is the control and does not move: 0.032 /
0.080 / 0.133 / 0.238 / 0.454 ms before, 0.092 / 0.067 / 0.160 / 0.301 /
0.520 after.

**The Direction's "capture on write" was the wrong shape here.** Of the
ten sites that mutate an environment, most are inside `#eval_type` —
which `infer_at` walks too, so guarding them would have put the scope
machinery's cost on the path that wants none of it, and would have been a
guard at each of ten callers rather than at the thing guarded.

Answers were driven rather than reasoned about: `scope_at` at 25,782
positions over 842 files of activerecord/actionpack/activesupport 8.1.3.1,
before and after, **byte-identical** (`9a2bec91…`). The control that the
two sides ran different code is the table above, re-run on each.

Pinned by a **count**, not a timing threshold — a threshold on a shared
machine is a flake, and the count is the property that produced the
timing. `spec/ovallsp/local_inferencer_spec.rb`'s "snapshots once for the
statements before the cursor" reports 83 against 8 with the old guard
restored, and `pinned_mutations.yml` carries that mutation.

### Attempted in 0.2.16, measured unsound, and withheld

The change is exactly the one this entry asks for: capture only at the
last pre-cursor statement, since every earlier capture is overwritten
before anything can read it, and each copies the whole environment.

**It is not answer-preserving when the walk aborts.** The step budget or
any `StandardError` inside `eval_type` ends the walk part-way, and the
old shape had already captured at each earlier statement, so `scope_at`
answered with everything accumulated. The new one has captured nothing
until it reaches the last, so it answers with none.

Reproduced by a verifier at the **default** budget of 5,000 — no
production caller passes a smaller one — on a `db/seeds.rb` shape with
2,500 top-level statements:

    scope_at(..., line 3002).locals.keys
    before  ["admin"]   (steps=5001)
    after   []          (steps=5001)

Identical through 2,400 statements and diverging from 2,500, at two
steps per statement.

So the entry's reasoning — "every earlier capture is overwritten before
anything reads it" — is true of a walk that *finishes*, and the walk is
budgeted precisely because it may not. The direction is to keep a single
capture and make it survive the abort: capture on the way out rather than
at a chosen index, or have the abort itself publish what it has. Not
attempted here, because a review round is not where a new mechanism goes.

The rest of this cluster shipped; only this file was held back.

**Re-triaged in 0.2.17** (`024.276`). Nothing user-facing and nothing to do with gems: a per-descent copy of the whole environment inside a walk that is budgeted precisely because it may not finish. The Direction is to keep a single capture and make it survive the abort. Its own body says why it was held back — a review round is not where a new mechanism goes — which is an argument for a change set of its own, on the patch line.

### 0.2.18: the curve is real and no real code is on it

Re-measured, and the distribution measured for the first time.

```
  locals in one scope    scope_at
             10          0.021 ms
             50          0.272 ms
            100          0.874 ms
            200          3.645 ms
```

Quadratic, as recorded — 5x the locals for 13x the time, then 2x for
4x. And over **27,297 methods in 1,973 files** (four Rails gems plus
Ruby 3.4.10's stdlib):

```
  <10 locals   26,980   98.84%
  10-24           307    1.12%
  25-49             8    0.03%
  50-99             1
  100+              1     (rdoc's markdown.rb#_Code, 155)
```

**Two methods in the whole corpus** are past 50, and at 10 the call
costs 0.021ms. The entry's own note said "real code keeps small"; that
is now a number rather than a belief.

**And the obvious fix does not work.** `capture_scope` cannot store the
`env` by reference and build the Hash once at the end: `locate`
*mutates* `env` as it descends — its own comment says so — so a stored
reference would answer with the deepest scope's bindings at every
level. Capturing only where the descent stops is the shape, and it
trades a guarantee (whatever path `locate` takes, the last capture is
right) for 0.85ms on a method one corpus in two has.

Retargeted to 0.3.0, where the inference core's cost is `024.45`'s
subject anyway — and `024.45`'s profile says the time is in `SymbolId`
and the indexes, not here.


**Not taken in 0.3.0.** `capture_scope` on every descent step is on
the completion request path, and the entry's own table is the
measurement that justifies it (0.24 ms at 50 locals, growing). The
change is to capture at the final step rather than each one, which
is small -- but it is a hot path this release has not otherwise
touched, and 0.3.0 spent its measurement budget on the enumeration
family. Recorded rather than attempted so the next release starts
from the number rather than the title.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Cost on the
completion request path. Nothing new is announced by making it
cheaper.

## Re-measured in 0.3.2, and the curve is where it was

Same shape as the table above, on this machine, `scope_at` over one
method with N locals:

    locals   0.3.2      as recorded
        10   0.021 ms   0.021 ms
        50   0.308 ms   0.272 ms
       100   0.686 ms   0.874 ms
       200   2.868 ms   3.645 ms

Unchanged within the noise of a laptop — and the two larger figures
are *lower* than the ones recorded, which is the direction that says
nothing has regressed rather than that anything improved.

Moved to 0.4.0 on the entry's own reasoning: the fix is in the
inference core, where an environment copied per descent step becomes
an environment shared and unwound. `docs/PUBLISHING.md` puts that
outside a patch, and 0.3.2 has already spent its measurement on the
entries it could finish.

## 024.39 `LocalInferencer` keeps per-request state, and 0.2.0 gave it a second thread

```yaml
status: open
kind: defect
user-visible: no
target: 0.4.0
user-visible-note: >
  No wrong answer has been produced. A reviewer ran 2,000 concurrent
  `infer_at` pairs and 400 `scope_at`/`infer_at` pairs in both size
  directions and got zero wrong answers, zero leaked locals and zero
  exceptions. What is recorded is that the reason it holds is not an
  invariant.
```

**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/server.rb`

`@steps`, `@step_budget`, `@self_type_stack`, `@scope_capture`,
`@capturing_scope` and `@parse_cache` are instance state reset at the top
of each entry point. `publish_diagnostics` and `workspace_findings_for`
both hold `@index_mutation_mutex`, so those two are serialised — but
`hover_result` and `completion_result` do not take it, and 0.2.0 is the
release that put `analyze` on a background thread.

`@capturing_scope` is the sharpest edge: a background `infer_at` running
inside a foreground `scope_at` would call `capture_scope` and overwrite
the completion's answer with another document's locals.

What makes it safe today is that the GVL rarely preempts inside one walk.
That is a probability, not an invariant, and nothing states it.

**Direction:** the state belongs in a per-call object rather than on the
inferencer, which is also what would let `@parse_cache` be shared safely
instead of being the one piece of it that wants to be.

**Re-triaged in 0.2.17** (`024.276`). Per-request state on a shared object, safe today only because the GVL rarely preempts inside one walk — a probability, not an invariant, and nothing states it. Moving the state into a per-call object repairs an existing guarantee rather than adding one, so it is patch work.

### 0.2.18: recorded, and the cheap fix is measurably the wrong trade

Nothing new reproduces — the entry already records 2,400 concurrent
pairs with zero wrong answers, zero leaked locals and zero exceptions.
What it says is that the reason it holds is not an invariant, and that
is still true.

**The cheap fix is a mutex around `infer_at` and `scope_at`**, and it
serialises hover and completion against diagnostics — on the path
`024.45` measures at 3.0–5.4 seconds per analysis. That is the one place
in this server where a lock is most expensive, and buying an invariant
there with a keystroke's latency is the wrong way round.

The shape that works is per-request state threaded as arguments rather
than held on the instance, which is a rewrite of the inference core's
entry points. Retargeted to 0.3.0 with `024.45` and `024.38`, which are
the same core and the same rewrite.


**Not taken in 0.3.0, and it is the one here that is a correctness
hazard rather than a cost.** `@capturing_scope` and the rest are
per-request state on an object two threads reach since 0.2.0 put
`analyze` on a background thread. Nothing in this release made it
likelier or safer. It wants either per-call state or a lock, and
both are changes to how the inferencer is entered rather than to
what it computes -- which is why it is recorded here rather than
pushed at from the side during a review loop.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Per-request state
on an object two threads reach is a correctness repair, and announces
nothing.

## Not attempted in 0.3.2: the same file as `024.38`, and it should be touched once

Per-request state on a long-lived object is the same class of change
as `024.38` and lands in the same file. Attempting one without the
other would mean touching `LocalInferencer`'s lifecycle twice, and
`048`'s record — eight restructurings of working code proposed, every
one measured worse — is the argument for doing it once, deliberately,
with a corpus on both sides. Moved to 0.4.0 alongside `024.38`.

## 024.42 A signature label leaks the method's own type variable

```yaml
status: open
kind: defect
user-visible: yes
user-visible-note: >
  Partly fixed in 0.2.15: the label carries the word RBS wrote where
  the conversion loses it. The method type variable half is open.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/signatures/type_converter.rb` (`convert`),
`core/lib/ovallsp/semantic/query_service.rb` (`rbs_signature`)

Signature help shows `push(...) -> Unknown` for `Array#push`, which RBS
declares as `-> self`, and `map() -> Array[U]`, where `U` is the method's
own type variable and means nothing to a reader.

`TypeConverter` maps `self`, `void`, `untyped`, `top` and `bottom` all to
`Types::UNKNOWN`, which is right for the *type model* — nothing
downstream can act on any of them — but a signature *label* is prose for
a human, and "Unknown" is a worse answer than the word RBS actually
wrote. The label is built from the converted type, so it inherits a
decision made for a different purpose.

It became visible in 0.2.1 rather than new: populating `parameters` for
RBS signatures made these labels the thing `activeParameter` points into,
so people read them.

**Direction:** keep the raw declared return alongside the converted one
on `Signatures::Overload`, and render the label from the raw. Not the
converter — every other reader of it is right to get Unknown. Deferred
rather than done because it touches the shape a signature is stored in,
and 0.2.1 was days from release; the two label defects that needed no
model change (a dropped block, duplicate overloads) are fixed.

### The `self`/`void` half, fixed in 0.2.15

`Overload` carries `declared_return` — the word the source wrote —
beside `return_type`, which stays the model's value. Two answers to two
different questions, rather than one answer bent to serve both.

**`#return_label` uses the declared word only where the conversion lost
something**, that is where the converted type is `Types::UNKNOWN`.
Everywhere else the converted form is what the rest of the tree renders.

*The first version did not have that restriction and reached for the
declaration always. Three `query_service_spec` examples caught it
immediately: `-> ::String` where every other reader in the tree says
`String`. Signature help would have become the one place using RBS's
fully-qualified spelling. The entry's complaint was about types that
lose their meaning in conversion, not about qualification, and the
restriction is what keeps the fix to the complaint.*

**Five specs were pinning the old labels** — four in
`untyped_function_spec` reading `-> Unknown` where the fixture declares
`-> void`, and one in `query_service_spec`. Each was correct for the
behaviour of the day, and the behaviour was the defect: `void` tells a
reader the return is not meant to be used, and `Unknown` tells them
nothing. Updated with the reason recorded at each site.

**And one that stays `Unknown`, correctly**: `Proc#call` reaches the
`untyped_overload` fall-back, built without a `declared_return` because
there is no declared return to carry. `Unknown` is what a reader should
see for a signature that states nothing. A blanket replace had changed
that one too, and it is restored.

**Measured**: 269 files of real gem source, both sides on corpus digest
`8143600c…` at different revisions — byte-identical, control
`unresolved-constant` 1,485 and `unknown-method` 22 on both.

### Still open: the method type variable half

`map() -> Array[U]` still shows `U`, the method's own type variable,
which means nothing to a reader. That is a different question — what a
label should say about a type parameter that is unbound at the call site
— and it is not answered by carrying the source's word, since the source
wrote `U` too. Left open and retargeted.

**Re-triaged in 0.2.17** (`024.276`). The remaining half is a question about what a label *should* say for a type parameter unbound at the call site, not about what a gem defines — the source wrote `U` too, so carrying the source's word does not answer it. Deciding that is a refinement rather than a repair, which is why the target stands. Not re-driven since the half above it was fixed.


**Driven at 0.3.0: the headline is fixed, the rest is not.**

    push  -> ["push(...) -> self"]
    map   -> ["map() { |E| ... } -> Array[T]", "map() -> Enumerator[Array[Unknown]]"]
    size  -> ["size() -> Integer"]

`Array#push` shows `-> self`, which is what RBS wrote and what this
entry asked for. What remains is the second half: `Array[T]` puts the
method's own type variable in front of a reader, and
`Enumerator[Array[Unknown]]` still leaks the converted sentinel into
a label. Both are prose problems on a surface that is prose, and
neither reaches the type model or the check.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A signature label
is prose for a reader; `Array[T]` and a leaked `Unknown` are repairs
to what an existing surface says.

**Fixed in 0.3.2.** The half that was left. `push -> self` was fixed when the entry was written, and `Array#each` was not: RBS declares `::Enumerator[Elem, self]`, the outer type converts to a Nominal so the top-level test was false, and inside the brackets `self` had become `Unknown` and `Elem` had been dropped -- a reader saw `Enumerator[Unknown]` for a method the source describes exactly. The test is now whether the *rendered* type contains the word the model prints when it has nothing to say, at any depth, and the declaration is spelled the way the rest of the tree spells a name. Two examples, and the three that already refused `::String` are the control that keeps the rule from widening back.

## Half of this shipped in 0.3.2, and half did not

**Closed:** the `Unknown` half. `push -> self` was already right when
the entry was written; `Array#each` was not, because the test asked
whether the *whole* return had become `Unknown` and `::Enumerator[Elem,
self]` converts to a `Nominal` at the top while losing `self` and
`Elem` inside the brackets. It reads `Enumerator[Elem, self]` now, and
the three examples that refuse `::String` are the control that keeps
the rule from widening back.

**Open, and what this entry is now about:** `map() -> Array[U]`. `U` is
the method's own type variable and means nothing to a reader. Unlike
the half above there is no better word in the source to fall back to —
`::Array[U]` is exactly what RBS wrote — so answering well means
*binding* the variable to the block's return, which is inference rather
than rendering. That is why it moves rather than closing.

## 024.44 A partial's local is not resolved, and C11's stated basis names it

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`ivars_for_view`,
`analyzable_document`), `core/lib/ovallsp/local_inferencer.rb`

In a scaffolded application, `app/views/articles/_article.html.erb` uses
`article` — a local the *`render` call site* supplies. Hovering it
answers `""` and `article.` completes to nothing, while the same file's
`@article` (were there one) resolves through the controller action.

C11 reads PASS, and its example writes `<% post = Post.new %>` into the
template first — a local the template assigns itself, which is a
different thing. The example's own comment gives the row's justification
as "a local in a template is what a partial receives", which is exactly
the case it does not cover. The row now says so; this entry is what it
points at.

**Direction:** the type comes from the `render` call site
(`render @article`, `render partial: "article", locals: {article: a}`),
so it needs the same propagation `ivars_for_view` already does for
instance variables, keyed by partial name instead of by action. Deferred
rather than done: it is a new inference path, not a correction, and 0.2.1
is a patch.

**Re-triaged in 0.2.17** (`024.276`). Stays where it is, on its own body's argument rather than the pasted one: the type has to come from the `render` call site, which needs the same propagation `ivars_for_view` does for instance variables but keyed by partial name — a new inference path, not a correction. `C11`'s row already states the gap in the document users read, so nothing is claimed that is not delivered.



**Not driven at 0.3.0.** A partial's local needs an ERB template
rendered from an action, which only the E2E harness sets up. Left
unverified.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** A partial's local
gaining a type is an answer where there is none.
## 024.45 Re-analysis after a keystroke is seconds on a large file, against a stated 300 ms

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`#reindex`, `#publish_diagnostics`,
called synchronously from `#handle_did_change`),
`core/lib/ovallsp/workspace_index.rb`, `core/lib/ovallsp/diagnostics/engine.rb`

Measured as the difference between a run with five `didChange`
notifications and one with none, so the one-off RBS load cancels:

| file | lines | per-edit re-analysis |
|---|---|---|
| `uri/generic.rb` | 1,592 | 4.31 s |
| `net/http.rb` | 2,574 | 2.06 s |
| `rubygems/specification.rb` | 2,666 | 5.25 s |

Super-linear: a synthetic file at 506 lines costs 0.10 s and at 16,006
lines 23.7 s. `ParserService#summarize` is about 19 ms of it; the rest is
reference resolution and the diagnostics engine.

`docs/design/docs/01-product-requirements.md` states `p95 <= 300ms` for
single-file re-analysis, so this is seven to seventeen times over on
files an ordinary Rails application contains. The Core answers one
request at a time, so hover, completion and signature help queue behind
every keystroke.

**Not a 0.2.1 regression** -- `main` measures 4.86 s on
`specification.rb` against 0.2.1's 5.17 s. It is recorded now because
nothing recorded it: `KNOWN_LIMITATIONS` had no mention of latency or
file size in either language, so the product shipped a numeric
requirement it misses by an order of magnitude with no limitation row.

**Direction:** the requirement is about *re-analysis*, and the Server
does it on the dispatch thread inside `didChange`. The two halves are
debouncing (which `024.41` also wants, for a different reason) and
incremental re-analysis of the edited region rather than the file. Both
are their own task; neither belongs in a patch.

**Re-triaged in 0.2.17** (`024.276`). This one is a published requirement the product misses by an order of magnitude, with no limitation row — which makes it exactly the class 0.2.x exists to clear: something the project said it did and does not. Its own body's "neither belongs in a patch" is an argument about size, not about kind, and size is a reason for a change set of its own rather than for a capability release. Travels with `024.57`, which holds the rolled-back half of the same work.

### Re-measured in 0.2.18, and one of the measurements was wrong

**The table above no longer describes this tree, and the first attempt
to say so measured the wrong thing.**

Driven through the real Server, five `didChange` against a baseline with
none — the method this entry's own table used — the per-edit cost came
out at 0.007–0.061 s and looked like a fix. **It was not.** Since 0.2.10
five edits with no read between them coalesce into *one* analysis, and
the baseline run already performs one on `didOpen`, so the difference
between them is close to zero whatever an analysis costs. It measured
the coalescing.

Measured where the cost actually is — one `summarize` plus one
`analyze`, on a warm stack, five repeats, at `ecdb4e6`:

| file | lines | summarize | analyze |
|---|---|---|---|
| `uri/generic.rb` | 1,592 | 0.008 s | 4.96 s |
| `net/http.rb` | 2,574 | 0.010 s | 3.53 s |
| `rubygems/specification.rb` | 2,594 | 0.025 s | 5.41 s |

So `summarize` is 0.2–0.7% of it, as this entry said, and **a single
re-analysis is 12–19x the stated 300 ms p95** — worse than the 2.06–5.25 s
recorded when this entry was written. `:safe` mode, which is what a
default user runs, costs the same as `:standard`.

### What was fixed here, and what it bought

`Signatures::Environment`'s own header said definitions are "built
lazily per symbol_id and memoized". The memo was
`@method_cache[symbol_id] ||= build_signature_method(symbol_id)`, and
**`||=` does not remember a `nil`** — which is the answer for every name
a type does not declare, and therefore the answer to almost every
question the undefined-method check asks. Counted over one `analyze` of
`net/http.rb`: **76,365 definition builds for 42 distinct
(type, singleton) pairs**, 62,644 of them `::HTTP`'s singleton side.

Two memos now: `#method_signatures` remembers a `nil`, and
`#build_definition` is keyed by (type, singleton) rather than by symbol,
so a *second* absent name on one owner no longer rebuilds it.

**It bought about 10%** — 4.96 → 4.42, 3.53 → 3.02, 5.41 → 5.38 — which
is what the profile predicted and less than the count suggested. RBS's
own `DefinitionBuilder` was absorbing most of those 76,365 calls; what
they cost was the call, not the build. Recorded because the inference
"76,365 calls must be the cost" was wrong and the profile was right.

### Where the time actually is, for whoever takes this

Sampled at `ecdb4e6`, 4.3M samples over three analyses of `net/http.rb`,
attributed to the deepest frame inside this project's own `lib`:

```
   7.5%  workspace_index.rb   String#to_s
   6.2%  hierarchy_index.rb   dedupe_named
   5.5%  index/symbol_id.rb   SymbolId#initialize
   5.1%  workspace_index.rb   String#split
   4.2%  workspace_index.rb   Array#each
   3.6%  workspace_index.rb   Kernel#lambda
   3.5%  hierarchy_index.rb   AncestorEntry#identified?
   3.5%  index/symbol_id.rb   SymbolId.qualify_owner
   3.3%  index/symbol_id.rb   core#hash_merge_kwd
```

Roughly **half the time is constructing and hashing `Index::SymbolId`s
and scanning the two indexes**, and the `String#split`/`#to_s`/
`qualify_owner` share says the same names are being taken apart and put
back together on every lookup. There is no single hotspot to remove;
what the shape suggests is that an identity computed once should not be
recomputed per query, which is `024.230`'s neighbourhood rather than a
hunk in this one.

**Stays open**, with the numbers above rather than the ones it was
written with.
### 0.2.18: the published numbers were the discredited ones, and 710,425

**What shipped to users was the measurement this entry had already
retracted.** `KNOWN_LIMITATIONS` said 2.1 s and 5.3 s in both
languages, from 0.2.1 to 0.2.17 — the five-`didChange`-minus-none
method the section above records as measuring the coalescing rather
than the analysis. The retraction was written into the register and
never carried to the document, which is `CLAUDE.md`'s "a revert is the
change most likely to leave documentation behind" arriving through a
correction instead of a revert.

Corrected in both languages, with the method named and the old numbers
explained rather than silently replaced. Re-measured here, one
`analyze` on a warm stack, median of five:

| file | lines | before | after |
|---|---|---|---|
| `uri/generic.rb` | 1,592 | 4.094 s | 3.911 s |
| `net/http.rb` | 2,574 | 2.838 s | 2.688 s |
| `rubygems/specification.rb` | 2,594 | 4.971 s | 4.744 s |

### What the 5% came from, and why it is only 5%

`Index::SymbolId.qualify_owner` is now memoised. Counted, not inferred:
one `analyze` of `net/http.rb` calls it **1,961,027 times for 385
distinct inputs**, and every call allocated a `"::#{...}"`. Removing
two million allocations bought **4.5–5.3%**.

That is the second time this entry has recorded the same lesson — the
`Environment` memo above removed 76,365 redundant builds and bought
10%. A call count says how often something happens, not what it costs,
and both times the profile was right and the count was not.

Three notes for whoever takes this further, each measured here:

- **710,425 `SymbolId` constructions for one 2,574-line file** — 276
  per line. That is the shape of the problem: the same identities are
  rebuilt per query rather than computed once, which is what this
  entry's profile section already concluded and what the count now
  quantifies.
- `%i[class module]` in `SymbolId#initialize` is reallocated on every
  one of those constructions, and a frozen constant is 28% faster on
  that line. At 710,425 calls it is about **7 ms** of 2,688 — *not*
  taken, because `CLAUDE.md` records that 0.1.12 lost a round to logic
  moved into this exact constructor, and 7 ms does not buy that risk.
- The memo's cache is keyed by the argument, so `"Widget"` and
  `"::Widget"` are two entries. Unifying them means running
  `delete_prefix` on every call to find the key, which is the
  allocation the memo removes, paid on the fast path to buy an
  identity nothing asks for. The spec was **written asserting the
  unified form and corrected** — it was a wish, not a requirement.

**Stays open.** 2.7 s is still nine times the stated 300 ms, and the
direction is unchanged: an identity computed once rather than per
query, plus incremental re-analysis. What 0.2.x owed here was that the
published figure be true, and that is what was paid.
**Target moved to 0.3.0.** It said 0.2.18, and this release's own
section above concludes the opposite: 2.7 s is nine times the stated
300 ms and the direction is an identity computed once rather than per
query — 710,425 constructions for one file is a lookup path, not a
hunk. Leaving `target: 0.2.18` would assert a resolution the entry
itself argues against, which is the shape `024.276` records. What
0.2.x owed was that the published number be true, and that is paid.
Travels with `024.38` and `024.121`, which are the same measurement
from the other two sides.




**Not taken in 0.3.0**, and the entry's own numbers are why it is not
a review-round hunk: the cost is super-linear and
`ParserService#summarize` is 19 ms of it, so the rest is reference
resolution and the index. 0.2.18 measured the same shape from the
other end -- 710,425 method identities built for one 2,574-line file
-- and recorded that fixing it is a change to how the index is
queried. Nothing in 0.3.0 moved that.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Re-analysis cost
against a stated budget. 0.2.18 moved the same measurement 5% and
shipped as a patch.

**Retargeted to 0.4.0.** Re-measured twice on a quiet machine, and the number is far worse than the entry carried: 10 keystrokes into a 4,662-line file take 525.9s to go quiet (521.6s on the first run, with a stray process pinning a core -- so that was not the cause), 51 publishes for 10 edits, hover median 0.124s and max 16.1s. The entry's own profile says why a patch cannot hold it: roughly half the time is constructing and hashing Index::SymbolId across the two indexes, with no single hotspot to remove, and the direction it names -- an identity computed once rather than per query -- is 024.230's neighbourhood and a release of its own. docs/PUBLISHING.md puts a change of that size outside the patch line. Moved with the measurement rather than with an estimate.
## 024.47 A namespaced class named after a core class loses its diagnostics, and the readers disagree about a shadowed literal

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/index/type_name_resolution.rb`
(`#substitution?`), applied by
`Diagnostics::Engine#shadowed_declared_type?` inside
`#receiver_type_for`

The substitution test recognises a *bare* name that signatures declare
being answered by a workspace class in a different namespace. It cannot
tell a name the user *wrote* -- a bare name is exactly how Ruby refers
to a class from inside its own namespace -- from a name inference
produced, so wherever the rule is applied, it is applied to both
populations at once. 0.2.1 tried both placements, and each was wrong for
one population:

- **Applied at resolution** (`HierarchyIndex#canonical_name`, built
  mid-loop): the literal case was right and every written bare name
  broke -- hover, definition and completion all stopped answering for
  `Range.new` inside `module Billing`. Rolled back before 0.2.1
  shipped.
- **Applied at the diagnostics engine** (what 0.2.1 shipped, and what
  ships today): hover, definition, completion and signature help all
  answer for the written name, and the engine declines to report about
  *any* receiver the test matches. Measured on this tree (0.2.3's
  scope-confirmation pass, controls included): `r.tagg` -- a genuine
  typo -- on a `Billing::Range` receiver is never reported, while the
  identical typo on a `Pricing::Tariff` receiver is. The check is
  silently off for exactly the classes this entry is about.

```ruby
module Billing
  class Range
    def tag(name) = name
  end
  class Invoice
    def run
      r = Range.new
      r.tag("x")     # 0.2.0: hover, definition and completion answer
      r.tagg("x")    # 0.2.1-0.2.3: they still answer -- and this typo
    end              # is never reported (a Tariff's identical typo is)
  end
end
```

(This entry's first version annotated the example "0.2.1: all three
answer nothing". That described the mid-loop resolution-side
arrangement, which was rolled back before 0.2.1 shipped, and the
`KNOWN_LIMITATIONS` paragraph written from it told users a limitation
the shipped build does not have -- while saying nothing about the
diagnostics silence it does have. Both corrected in 0.2.3; believe the
measurement above, not this file's history.)

The literal side, meanwhile, still disagrees with itself while a class
sharing the *literal's* name is indexed — a workspace
`Serializer::Elements::String` for a string literal, `Billing::Range`
for `(1..5)`: the literal's `.` completes to the workspace class's
members and none of the core class's (0.2.0's behaviour, kept
deliberately), hover and signature help on the same receiver's calls
answer from RBS, and diagnostics decline. Three readers, three
sources. A literal whose name no workspace class shares is untouched.

Applies to `Data`, `Set`, `Method`, `File`, `Time`, `Struct`,
`Comparable`, `IO` and `Random` -- any core name a namespaced class
shares. `Billing::Logger` survives only because `logger`'s RBS is not
loaded by default.

**What the 0.2.1 revert left behind, cleaned up in 0.2.3.** `CLAUDE.md`'s
revert rule ("grep the tree for the thing being reverted before
committing the revert") points here for the full inventory of what
reverting the resolution-side placement stranded:

- an unreferenced method: `Index::TypeNameResolution.canonical`, whose
  only caller was the reverted `canonical_name` (removed);
- an inert constructor parameter: `signatures:`/`@signatures` on
  `Semantic::HierarchyIndex`, assigned and never read (removed, with its
  three construction sites);
- stale comments describing the reverted arrangement as current, in
  `index/type_name_resolution.rb` (header), `semantic/hierarchy_index.rb`
  (`initialize`), `server.rb` (the `@signatures` ordering note),
  `diagnostics/engine.rb` ("resolution itself now refuses"),
  `scripts/corpus_diagnostics.rb` (naming a shadow rule in
  `canonical_name` that is not there), and `CLAUDE.md`'s countermeasure
  exemplar list (holding up the rolled-back placement as the right
  shape) -- four rewritten against the shipped arrangement, and the
  two whose subjects were themselves the dead code above
  (`hierarchy_index.rb`'s `initialize` note, `server.rb`'s ordering
  note) deleted with them;
- a published changelog bullet claiming the reverted completion fix as
  shipped, contradicting its sibling bullet under the same 0.2.1
  heading in both languages (deleted; 0.2.3's entry carries the
  notice);
- the `KNOWN_LIMITATIONS` sections in both languages described above
  (rewritten from measurement);
- a dead e2e client helper (`lsp_client.rb#document_highlights`) from
  the same rollback commit's capability removal (removed);
- a contract line nothing could observe: `substitution?`'s refusal of a
  qualified name was exercised only through the reverted resolution-side
  caller -- its one surviving caller blanks qualified receivers a line
  earlier (`WorkspaceIndex#guessed_type_name?`), and a full-suite sweep
  ran green with the line deleted. Pinned in 0.2.3 by a direct unit spec
  (`spec/ovallsp/index/type_name_resolution_spec.rb`, watched failing
  against the deleted line) rather than removed: the module states the
  bare-name precondition as its own contract, and a refusal that holds
  only because the sole caller pre-filters is 0.2.2's
  emergent-containment lesson over again.

**Direction, re-costed in 0.2.3.** The two shapes stand, and the second
was evaluated concretely against this tree before being declined for a
patch release:

1. Carry the written/inferred distinction into the type -- an inferred
   Nominal is not the same thing as a written constant reference. Still
   the shape that addresses the cause.
2. Stop choosing: let the ancestor chain hold both the workspace class
   and the RBS type, so member lookup finds whichever declares it. A
   simulation (0.2.3's review record, `028-0.2.3-review-loop.md`) showed
   the real bill, and the entry's earlier costing -- "one spurious
   completion candidate on a literal" -- understated every line of it:
   `"hello".upcase(:ascii)`, legal Ruby, becomes an `argument-count`
   false positive whenever the shadow class declares its own `upcase()`
   (`sole_source_declaration` keeps each source's answer singular while
   the receiver's identity is not, and `sole_declared_overload` has the
   symmetric RBS-side family); a written `Billing::Range` gains the
   whole core `Range` API as spurious completion candidates; one hover
   popup mixes an RBS label with a workspace `Defined:`; and making
   literal receivers closed re-opens 024.13's family -- `"".squish`
   under ActiveSupport-style direct additions -- for any workspace
   containing a shadow class. A corpus diff cannot arbitrate any of
   this: the gems that reopen core classes do it at the *top level*,
   where `substitution?` never fires, so the measurement is blind
   exactly where collisions live. Fixtures watched failing, not corpus
   deltas, are the gate if this shape is ever built.

Per the roll-back rule's own step 3 -- the problem goes to its own
release or its own task -- the fix is re-scoped out of 0.2.3, which
carries the documentation and this record instead. 027 deferred "the
hover/completion countermeasure" here; this entry is where that item
landed, and why it is not a code change in a patch.

**Not caught for seven rounds** because `scripts/corpus_diagnostics.rb`
built a `HierarchyIndex` without the `signatures:` the then-current
shadow rule read, so the rule was inert in every corpus measurement the
release quoted (024.48).

**Re-triaged in 0.2.17** (`024.276`). The rollback is done and this entry is what it left behind; the remaining half is a namespaced class losing its diagnostics because it shares a core class's last segment, which is a wrong answer about the user's own code. Patch work. Its own body carries the reason it was not caught for seven rounds — the corpus harness built a hierarchy index without the signatures the rule read, so the rule was inert in every measurement quoted — and that is a caution for whoever re-measures it, not a blocker.

### 0.2.18: the diagnostics half is gone, the literal half is not, and a fix was tried and rolled back

**Driven with the entry's own control**, because this entry has been
mis-described twice:

```
  Billing::Range receiver, typo `tagg`   ->  reported
  Pricing::Tariff receiver, same typo    ->  reported
```

**The diagnostics silence no longer reproduces.** A genuine typo on a
class that shares a core name is reported, exactly as one on a class
that shares nothing is. That was this entry's headline — "the check is
silently off for exactly the classes this entry is about" — and it is
no longer true.

**The literal half reproduces exactly**, three readers and three
answers, for `r = (1..5)` written inside `module Billing` where
`Billing::Range` exists:

```
  hover        "Range"                          right
  completion   billing_only, and no cover?      the workspace class's members
  diagnostics  nothing                          declined
```

Ruby settles which is right — a literal is `::Range`, always — so hover
is correct, completion is wrong, and the decline is safe but unchecked.

### The fix was obvious, measured, and wrong

`Types::LiteralTypes` writes bare names. Writing them **rooted**
(`::Range`) uses a rule that already exists: `resolve_type_symbol_locked`
gives a rooted name exactly one referent, which is what stopped `::JSON`
resolving to a gem's own `JSON`. It made both new examples pass.

It also broke **11 examples across 7 files** — `capabilities_spec`'s
hover row, overload narrowing three ways, the constant ladder, argument
type in two specs, root-scoped models, and non-ASCII `explainType`.
Every one of them reads the literal's name **bare**, and a `::` prefix
is the same class of change `CLAUDE.md` records from 0.2.5: one line in
a type converter, one failure in the suite, and a second consequence a
corpus found immediately.

Rolled back. **The direction is the one `024.224` needs too**: the fact
that a type came from a literal is an identity, and encoding it in the
name means every reader has to normalise the spelling back. Carrying it
beside the name — or rooting only where resolution asks — is the shape;
changing what every component reads is not.

**Retargeted to 0.3.0.** What is left is one reader disagreeing with two
others about a literal, which no user has reported and which the
published limitation covers.


**Driven at 0.3.0 in one shape and it did not reproduce there.** A
`Billing::Range` with a `Range` core class shadowed by it:

    Billing::Range has no method named `definitely_absent_on_billing_range`

is reported, with a class in the same fixture as the control. The
entry says the engine declines about *any* receiver the shadowing
test matches, and this receiver matches it. Left open rather than
closed: this entry is about two populations and a rolled-back
placement, and one fixture is not the whole of it. What it does
establish is that the headline -- a namespaced class named after a
core class loses its diagnostics -- is not true of the plain shape.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Driven at 0.3.0 and
the headline did not reproduce; whatever remains of the two
populations is a repair.

## Not attempted in 0.3.2, and it is now the only entry resting on the identity change

The literal half is pinned pending in `shadowed_literal_spec.rb` with
the measurement that stops it: writing the literal's type rooted makes
the two new examples pass and breaks 11 examples across 7 files,
because every one of them reads the literal's name bare.

What changes in 0.3.2 is the company it kept. This entry and
`024.224` were both recorded as needing the same direction — a type
that carries the identity of what produced it, rather than encoding it
in a name every reader has to normalise back. `024.224`'s *reported* half turned out
not to need it: its cause was a swallowed `UNAVAILABLE`, and one guard
fixed it. What survives in `024.224` — a type declared only in `sig/` —
is still argued there as wanting the identity carried, so the two are
not as separate as this paragraph said in 0.3.2. Corrected in 0.3.3:
the pairing is weaker than it was, not evaporated, and each should be
weighed on its own evidence.

Moved to 0.4.0, where it can be weighed as one change to a type every
component reads rather than as a shared prerequisite.

## 024.62 Two per-file stores are separated by nothing but their payload

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing is wrong in the tree today. Every call site was checked and
  each one is currently correct, so no answer the engine gives is
  affected. What is recorded is that the correctness rests on four
  call sites each remembering a different subset, rather than on the
  structure — a hazard for the fifth, not a fault in the fourth.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`,
`core/lib/ovallsp/semantic/generated_method_index.rb`,
`core/lib/ovallsp/server.rb`, `core/lib/ovallsp/cold_indexer.rb`

`HierarchyIndex` and `GeneratedMethodIndex` are updated by the same
trigger, inside the same mutex block (`Server#apply_file_summary`), keyed
by the same thing, and built from the same `FileSummary`. They differ in
the type of fact they hold and in nothing else. No reason for the
boundary is stated anywhere, and none is apparent.

The comparison is what makes it visible: the other stores in this layer
are separated by something that *forces* it.

- `ReferenceIndex` cannot be written when a file arrives at all — a
  reference resolves only once every file's declarations are known, so it
  is rebuilt asynchronously behind a dirty token, and the token is checked
  against the semantic generation before the result is installed.
- `MethodSummaryStore` is keyed by symbol and invalidated by walking a
  dependency graph, because a method's return type depends on methods in
  other files. Per-file eviction would discard the wrong entries.
- `GenericRuleRegistry` is not shared state at all: `LocalInferencer`
  builds one in its own constructor and nothing writes to it afterwards.
  It has no mutex and needs none. (Plugin-contributed generic rules are
  collected by `Plugins::StaticContext` and never installed — its own doc
  says so.)

So three of the four separations in this layer are load-bearing and one
is not.

The mechanism itself is also copied. Four stores implement "map keyed by
uri, one writer, mutex, wholesale replace, bump a generation"
(`WorkspaceIndex`, `HierarchyIndex`, `ReferenceIndex`,
`GeneratedMethodIndex`), and the mutex-plus-generation half of it recurs
in at least three more (`Observation::Store`, `Routes::RouteRegistry`,
`Signatures::Environment`) keyed by something other than a uri. Each
copy's own doc comment points at the others as precedent, which is how
seven of them came to exist without the shape ever being extracted.

**Why it is not a defect today.** The update calls are spread across
several sites, each touching a different subset, and each is currently
right for its own reason rather than by construction:

| site | touches | why it is safe |
|---|---|---|
| `ColdIndexer#index_file`'s direct path | workspace + hierarchy only | unreachable from `Server`, which always supplies `on_summary` and routes to `#apply_file_summary` |
| `Server#apply_file_summary` | all four (references via a dirty mark) | the complete path |
| `Server#remove_index_contribution` | all four | the complete path |

One of those is safe because of a fact about its *caller*, not because of
anything the stores enforce. A fourth writer added without noticing would
be the failure.

*A fourth row stood here until 0.2.16: `Server#apply_plugin_context`, the
one that touched three stores and skipped the generated-method write on
an empty fact list. It went with the plugin subsystem. The entry is
otherwise unchanged and open — the boundary question is what it is about,
and one fewer writer does not answer it.*

**Direction.** Not "merge the two" by default — the question is which of
the two shapes below is right, and that is the work:

1. one per-uri store holding several kinds of fact, which the layer's
   readers ask for what they need; or
2. one aggregation type the existing stores are built from, leaving the
   four separate but removing the seven hand-written copies of the
   mechanism.

(2) is the smaller change and does not answer the boundary question; (1)
answers it and touches every reader. Whichever is chosen, `CLAUDE.md`'s
caution from 0.1.12 applies: moving rules into a type's `initialize` is
not free, and a module function the callers invoke is usually the cheaper
form of "one place that knows the rule".

**How it was found:** not by a review round. It surfaced while writing an
architectural walkthrough of the codebase, in which all five stores in
this layer were described as sharing one update discipline. That
description was wrong — two of the five do not — and checking why
produced this entry. Worth noting as a method: describing the design to
someone who has not read it is a different probe from reviewing a diff,
and it found something eight rounds of review over this layer had not.

**Re-triaged in 0.2.17** (`024.276`). Two per-file stores in one layer with different update disciplines and nothing saying so. Internal, and worth keeping for how it was found: describing the design to someone who has not read it turned this up where eight review rounds over the same layer had not.

### 0.2.18: this is `048`'s question, and `048` answered it

The entry's own note is the disposition: "Nothing is wrong in the tree
today. Every call site was checked and each one is currently correct."
What it records is a hazard for the fifth call site.

`048` audited ten subsystems for exactly this and produced eight
proposals; **every one failed measurement**, four would have made the
product worse, and the headline consolidation came out at +3 net lines
after the compensations it needed. `CLAUDE.md` draws the rule from that:
applied to code that works, a consolidation is an ordinary change with
an ordinary change's obligations, and the measure is places that must
agree rather than lines.

Two stores updated in one mutex block from one `FileSummary` are two
places that must agree — so the direction is right. What is missing is
a measurement showing the merged shape is not a third place, and this
release has no corpus that would show it. Retargeted rather than
attempted on the strength of the idea.


**Not taken in 0.3.0.** Merging `HierarchyIndex` and
`GeneratedMethodIndex` is a consolidation, and `048` measured eight
of those in this tree: every one failed, four would have made the
product worse, and the headline came out at +3 net lines. `CLAUDE.md`
records the measure as *places that must agree*, not lines -- these
two are updated in one mutex block from one summary, so nothing
currently disagrees. Recorded as an unexplained boundary, which is
what it is, rather than acted on.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A boundary with no
stated reason is refactoring, and `048` measured that eight such
proposals in this tree all failed.

## Not attempted in 0.3.2: a simplification carries an ordinary change's obligations

Two per-file stores that differ only in payload is a real
duplication, and merging them is exactly the shape `048` measured
eight times and rejected eight times: a restructuring of code that
works, where the count that matters is places that must agree rather
than lines. It is not that this one is wrong — it is that a
simplification of working code carries an ordinary change's
obligations, and a patch release whose measurement is already spent
is the wrong place to take them on. Moved to 0.4.0.

## 024.71 One mutable Rails fixture is shared by every worker, so the suite cannot be parallelised

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing an editor user sees. The suite runs serially today and is
  green that way; what the shared fixture costs is the ability to run
  it any other way, which is a contributor and CI cost.
target: 0.4.0
```

**Area:** `core/spec/fixtures/rails_real` (its `db/*.sqlite3`, `tmp/`
and `.bundle`), `core/spec/integration/real_rails_spec.rb`,
`core/spec/e2e/capabilities_spec.rb`

The suite's cost is not its size. Measured at `4f19c67` on
darwin-arm64 / Ruby 3.4.10, over a full run of 1,964 examples taking
172s wall (example time is 99% of wall, so this is not load
overhead):

- **1,125 examples — 57% of the suite — take under 10ms each and
  total 0.3 seconds between them.**
- The ten slowest examples are **45%** of all example time; the
  slowest single one is **20.9s**, 12% of the whole suite on its own.
- By file: `e2e/capabilities_spec.rb` is **65.1s (38%)**, then
  `agent_process_manager_spec.rb` 10.3s, `integration/real_rails_spec.rb`
  9.5s, `server_rails_invalidation_spec.rb` 9.4s. The top entries all
  spawn real processes and wait on them — the diagnostics examples
  (G6–G14) wait for a Rails Runtime Agent to come up.

So parallelism is the lever, and it works — measured, with the example
count as the control on both sides:

| arrangement | wall | speedup | examples | result |
|---|---|---|---|---|
| serial | 172s | 1.0x | 1,964 | 0 failures |
| 3 workers, by file | 67s | 2.6x | 1,964 | 0 failures |
| 8 workers, by example | 24s | 7.2x | 1,964 | **1 of 3 runs failed** |

Two ceilings, both structural. **By file it stops at 2.6x** — a fourth
worker buys nothing, because `capabilities_spec.rb` is one 65.1s file.
**By example it stops near 8x**, at the 20.9s of the single slowest
example.

**The blocker is the fixture, not the harness.** One run in three at
eight workers failed `real_rails_spec.rb:544` ("uses the fixture's own
Gemfile, not the parent's genuine BUNDLE_GEMFILE") with
`user_email_column` nil — the app's schema query returning nothing.
That example passes 3 of 3 run on its own, and the full suite passed 3
of 3 serially the same day, so it is contention rather than an
inherently flaky example: every worker drives the same
`core/spec/fixtures/rails_real`, whose sqlite database and `tmp/` are
shared mutable state.

The 3-worker run passed, but that is not evidence of safety — it puts
`capabilities_spec` and `real_rails_spec` in different workers, both
touching Rails at once, so it has the same hazard at a lower rate. One
green run does not distinguish safe from lucky.

**Direction:** isolate the fixture per worker before adding any
parallel runner — a copy of `rails_real` per worker, or at minimum a
worker-scoped database path and `tmp/`. With that done, no gem is
required: distributing `file:line` locations by measured runtime is
what produced the 24s figure above. Note when doing it that 42
locations hold more than one example each (table-driven `it`s sharing
a line, the largest being 47 at
`server_word_at_cursor_spec.rb:71`), so a splitter must weight and
assign whole locations — the first attempt here did not, ran 2,991
examples instead of 1,964, and its timing meant nothing.

Worth it because CI's Core job is 5m34s today and this is most of it;
the same measurement says a fixture-isolated 8-way split lands near a
minute.

**Re-triaged in 0.2.17** (`024.276`). One mutable Rails fixture shared by every worker, so the suite cannot be split safely. Test infrastructure — it changes nothing a user meets and adds no capability. The first attempt at a splitter ran 2,991 examples instead of 1,964 because it split by example rather than by location, which is recorded here so the next one weights whole locations.

### 0.2.18: a contributor cost, and the release line is the wrong place for it

Nothing an editor user meets, which the entry says. What it costs is the
ability to run the suite any way but serially — and the suite is now
2,866 examples at roughly ten minutes, run twice per change set in this
release alone.

That cost is real and it is *this project's*, not the product's. Giving
each worker its own `rails_real` means copying a booted Rails app's
`db/`, `tmp/` and `.bundle` per worker, which is minutes of setup to
save minutes of run — a trade that needs measuring before it is made,
and measuring it needs the parallel runner that does not exist yet.

Retargeted to 0.3.0. It is on the list of things that make the loop
faster, not on the list of things that make a released claim true, and
0.2.x is the second list.


**Retargeted to 0.3.2 in 0.3.0's closing sweep.** The suite's own
fixture. It bit a 0.3.0 measurement, which is exactly the cost the
entry describes, and fixing it announces nothing.

## Driven in 0.3.2: the two suites already run concurrently, and the fixture does not move

The entry names `db/*.sqlite3`, `tmp/` and `.bundle` as what a second
worker would collide on. Measured against the fixture as it stands —
23 files, and `db/` holds none:

    real_rails_spec.rb and capabilities_spec.rb, started together
      real_rails    19 examples, 0 failures
      capabilities  95 examples, 0 failures
      fixture       byte-identical before and after

Serially, each of them alone leaves it byte-identical too. So the
*persistent* half of the hazard is gone: `capabilities_spec` copies the
fixture per run (`FileUtils.cp_r` into a per-pid tmpdir) and 0.3.1 gave
the suite its own `XDG_CACHE_HOME`, which between them moved the two
things a run used to write.

**This does not close the entry, and the difference is worth stating.**
Two workers agreeing on the end state is not the same as two workers
being safe: what was shown is one pairing, once, on one machine. The
entry's own lever — 3 workers by file, 172s to 67s — was measured
against a suite that has since grown by half again, and nothing here
re-measured *that*. What has changed is that the reason to expect
breakage is weaker than when it was written, so the next attempt starts
from an experiment rather than from an assumption.

**A measurement error worth recording**, because it nearly became the
finding: the first comparison hashed `shasum` output that carries each
file's *path*, so the backup copy and the original differed for having
been in different directories and it read as MUTATED. Compare contents,
from inside each root, or the paths are what is being compared.

## 024.76 Fifty-four `unknown-method` reports over real gem source, and all of them false

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`
(`#unknown_method_findings`, `#closed_nominal?`),
`core/lib/ovallsp/semantic/hierarchy_index.rb`,
`core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/workspace_index.rb`

Driven over 213 files of installed gem source (rack 3.2.6, i18n 1.15.2,
concurrent-ruby 1.3.8) by 0.2.5's round 2: **54 `unknown-method`
findings, of which 53 are false.** 0.25 per file; 17 of 213 files
affected. Identical on both branches, so this is not a regression — it is
the state of the check.

**One is arguably true, and round 3 was right to contest the original
"all 54".** `rack/auth/abstract/handler.rb:21` calls `challenge`, which
`Rack::Auth::AbstractHandler` genuinely does not define — it is an
abstract template method supplied by `Rack::Auth::Basic`. Called on the
abstract class directly it is a real `NoMethodError`, so the report is
literally accurate. It is also the shape a Ruby developer would not want
reported, since the pattern is deliberate and the subclass supplies it,
which makes it the *interesting* member of the set rather than a
counterexample to be dismissed. Recorded here rather than adjudicated
away: 53 of 54 wrong is the same argument as 54 of 54, and pretending the
54th does not exist would be the measurement error this entry is about.

Cause breakdown, recounted in round 3 — the first pass reported 11 and 30
and was short by three overall:

That number is the release's own standard turned on itself. Section 0
names undefined-method detection as half of what 1.0.0 is, and section
0.4 says a wrong answer is worse than no answer. A check whose entire
output on real code is wrong is worse than the check being absent.

Verified causes, from source:

- **`include` of a module defined in the same file, from a nested
  module** (12 findings) — `Rack::Request` includes `Helpers` at
  `request.rb:784` and `def request_method` is at `:202`; `Rack::Response`
  and `MockResponse` lose `buffered_body!` the same way; `Rack::Reloader`
  loses `rotation`. **This is the one that matters**: Rails concerns are
  exactly this shape, so the check reports confidently on ordinary
  application code.
- **Metaprogrammed accessors** (31) — `attr_atomic`, `attr_volatile`,
  `singleton_class.send :alias_method`. A fair limitation of static
  analysis; it should produce silence, not a report.
- **Platform-specific files** (8) — JRuby-only sources, unreachable on
  MRI.
- **`::JSON.parse` inside a namespaced module** (2) — did not reproduce
  in isolation, so context-dependent and not yet characterised.
- **One abstract template method** (1) — the arguably-true one above.

**Direction:** the check's stated policy is that a false report is worse
than a missed one (`015`), and `#closed_nominal?` is what decides a
receiver is safe to report about. It is treating "I resolved every
ancestor I could find" as "the ancestor list is complete". The `include`
case says it is not: a module referenced by a bare name from inside a
nested namespace is not being resolved, and the receiver is then judged
closed anyway. Until that resolution is right, a receiver whose chain
contains an `include` the index could not resolve should produce no
finding at all.

### 0.2.6: 54 to 6, measured the same way

Same corpus, same harness, one side per revision, with
`unresolved-constant` as the control. Four changes, each watched failing
first and each pinned by mutating the specific decision inside it:

| | change | 54 → |
|---|---|---|
| 1 | an unreadable class-body macro leaves the owner's method **surface open**, so `#closed_nominal?` declines | 18 |
| 2 | `singleton_class.send :alias_method` and `self.class_eval` count as the same thing | *(with 4)* |
| 3 | a name written `::JSON` resolves only to the root, never to a same-named class elsewhere | *(no change alone — see below)* |
| 4 | the check declines about a rooted receiver the workspace answers for from another namespace | 10 |
| 5 | an ancestor with no statically-known name opens the surface instead of being dropped | 9 |
| 6 | a singleton lookup also requires the *instance* chain to be identified | 8 |
| 7 | an alias whose target is declared later in the same file is withdrawn | 6 |

The **instance/singleton split** in (1) is the part worth carrying
forward. `attr_atomic :value` defines `#value` and not `.attr_atomic`, so
opening both surfaces would let every unreadable macro silence *its own*
report — 19 examples pin that report, established deliberately as
`024.23`. Written inside `class << self`, the same call opens the
singleton surface instead.

(3) alone moved nothing, because `ReceiverResolution` strips the leading
`::` before the receiver type is built. It is kept anyway — resolving
`::JSON` to i18n's own `I18n::Backend::KeyValue::JSON` is wrong for
go-to-definition too — and (4) is what the check needed. Declined in the
engine rather than in resolution, per `024.47`.

The measurement's control moved and is accounted for:
`unresolved-constant` went 881 → 897, all sixteen of them `::JSON`,
`::Date` and `::DateTime` in i18n, which had been "resolving" to that
gem's own nested `JSON` and `I18n::Tests::Localization::Date`. Reporting
them is the honest answer, and `unresolved-constant` does not run in the
Server's default `:safe` mode.

**The ten that remain**, and why each stays:

- **7 × `java`** — JRuby-only files (`java_count_down_latch.rb`,
  `java_non_concurrent_priority_queue.rb`, `processor_counter.rb`,
  `java_executor_service.rb`). Never loaded on MRI. Section 0.4's
  "a path almost nobody walks".
- **`Concurrent::Collection::NonConcurrentMapBackend#initialize` calls
  `validate_options_hash!`**, which only `Concurrent::Map` — its
  *subclass* — defines. Literally a `NoMethodError` on the backend
  alone, so the report is accurate and unwanted, the same shape as the
  `challenge` one below.
- **`Rack::Auth::AbstractHandler#challenge`** — the arguably-true one
  above, unchanged.
- ~~**`Rack::Reloader#rotation`**~~ — fixed in the same release, taking
  the corpus to **9**. `extend backend`, a constructor parameter, was
  dropped by `#record_ancestor_call` because `raw_constant_name` returns
  nil for anything but a written constant — so "extends a module I
  cannot name" and "extends nothing" were the same fact downstream. It
  now opens the surface, exactly as an unreadable macro does. Which
  surface follows what the call does to `self`: `extend` in a class body
  is class-level, `include`/`prepend` are instance-level, and `extend`
  inside an instance method is `Object#extend` on that instance and so
  instance-level — which is this case, and the reason it is not gated on
  being in a class body. All three branches pinned by mutation.

The `include`-from-a-nested-namespace cluster (12 findings, the row that
mattered) is gone: it was the ambiguous-bare-name resolution fixed
earlier in this release, and none of it survives in the ten.

**Re-triaged in 0.2.17** (`024.276`). The cluster that mattered is gone — the ambiguous bare-name resolution fixed earlier — and the ten that remain are the same shape as `024.83`: the check cannot tell a class the workspace merely reopens from one it owns without a witness outside the workspace. That witness is `024.R7`, which is why this stays, and `045` records it as one of D2's four.
### Re-driven in 0.3.0, after `024.R7` landed

Same three gems at the same versions, same 213 files, same
`corpus-sha256`:

| | `unknown-method` |
|---|---|
| 0.2.5 round 2, as this entry records | 54 |
| 0.3.0, no gem index | **23** |
| 0.3.0, with the gem index | **23** |

**The entry's 54 is five releases stale**; the check has since been
narrowed repeatedly and answers 23 on the same corpus. Re-measured
rather than assumed, which is what this entry's own "not a regression
— it is the state of the check" asks of a later reader.

**And the gem index changes nothing here**, which is the right answer:
these three gems are analysed as the workspace, so their own classes
are workspace-declared already. R7 speaks about a class whose *parent*
is a gem's, and rack's `Utils` has no such parent.

One report did appear on the first run with the index and it was
false: `CGI.escapeHTML`, which exists. Asked of Ruby —

```
$ ruby -rcgi -e '
p CGI.singleton_methods(false).include?(:escapeHTML)
p CGI.singleton_class.ancestors.first(3).map(&:to_s)
'
# => false
# => ["#<Class:CGI>", "CGI::Escape", "CGI::Util"]
# ruby 3.4.10
```

— an `extend`ed module puts its *instance* methods on the class-level
chain, and the index reported `singleton_methods(false)`, which cannot
see them. The Agent reports `singletonAncestors` now and the singleton
walk reads it. That is a defect `024.R7` shipped with, found by
re-driving this entry rather than by a reviewer.

**Stays open**: 23 reports over 213 files is still the state of the
check, and this entry is about that number rather than about the
index.



**Re-driven at 0.3.0 and it holds, on a smaller corpus.** Over
activesupport 8.1.3.1 and i18n 1.15.2 -- 335 files, Agent connected,
2,078 gem classes indexed -- the check produces **19** `unknown-method`
reports and **every one of them is false**. Sorted by what makes them
false:

- **5 -- a core class this very gem reopens.** `Integer has no method
  named `kilobyte``, and `minutes`, `megabytes`, `hour`. ActiveSupport
  defines them in the corpus being read.
- **6 -- a core or stdlib method the signatures do not carry.**
  `NameError#original_message`, `BigDecimal#finite?`, and `IPAddr`'s
  `ipv4?`, `ipv6?` and `prefix`.
- **4 -- a module receiver whose surface belongs to its includer.**
  `Class has no method named `redefine_method``,
  `remove_possible_method`, and `BaseTimeGroup has no method named
  `now`` twice.
- **2 -- `Kernel#BigDecimal` called receiverlessly inside a module.**
  `ActiveSupport::NumberHelper::RoundingHelper has no method named
  `BigDecimal``.
- **1 -- an operator on a core class.** `Numeric has no method named
  `*``.

**Six of the nineteen are `024.243`.** That entry's second shape --
the Object chain plus a nameless includer -- removed exactly the four
in the third group when it was measured, and the two in the fourth
are the same cause reached receiverlessly. So the module-chain
direction is worth more than the one entry it is filed under, and
this is the count to re-take when it lands.

The other thirteen are the enumeration question `024.290` now records
as unanswered: `024.R7` indexes 2,078 gem classes and no core ones.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Nineteen reports
over 335 files and every one false. A wrong answer is the patch
line's own example.

## Re-driven in 0.3.2, and the number has not moved

Same three gems, same 213 files, on `rack-3.2.7` (the entry measured
3.2.6), `i18n-1.15.2`, `concurrent-ruby-1.3.8`:

    corpus-diagnostics: count.unknown-method=23
    corpus-diagnostics: count.unresolved-constant=871

**23, exactly as recorded.** 0.3.2's gem-index repair (`024.305`) did
not move it, which is worth knowing: that fix was about a Rails class
and this corpus has no Rails in it.

What is new is that all 23 are now grouped, and **every one belongs to
a shape another open entry owns**. This entry counts; it does not have
a fix of its own.

| n | shape | where it really is |
|---|---|---|
| 18 | `Concurrent::LockLocalVar` `value` / `value=` | `LockLocalVar = ThreadLocalVar` under a runtime `if`, followed by an empty `class LockLocalVar` written for the documentation. The engine reads the empty body and calls the class closed |
| 3 | `JavaCountDownLatch#java`, `ProcessorCounter#java` | inside `if Concurrent.on_jruby?`, so it is never executed on the Ruby analysing it |
| 1 | `Rack::Auth::AbstractHandler#challenge` | defined by the subclass, `Rack::Auth::Basic#challenge` — the abstract-method shape |
| 1 | `NonConcurrentMapBackend#validate_options_hash!` | defined on the parent, `Concurrent::Map#validate_options_hash!` |

None of the four is a hunk. The first needs the engine to model a
constant that is *both* assigned a class and opened as one; the second
needs it to know a platform predicate is false, which it cannot; the
third and fourth are `024.13`'s and `024.19`'s territory. So the count
is carried forward rather than reduced, and the entry moves to where
the shapes are fixed.

## 024.83 The undefined-method check is loudest exactly where no Runtime Agent can answer

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`#closed_nominal?`,
`#reopened_elsewhere?`), `docs/design/tasks/024-deferred-review-findings.md`
`024.13`

A workspace that reopens a core class makes that class's chain look
complete, so every method some *gem* adds to it is reported missing.
`024.13` recorded the shape; a review round of 0.2.6 measured it, driving
the real server.

**74 `unknown-method` reports over `activesupport-8.1.3.1/lib` +
`activemodel-8.1.3.1/lib`** — `Date has no method named today`,
`Date.parse`, `DateTime.parse`, `Integer#minutes/megabytes/kilobyte`,
`Class#redefine_method`, `NameError#original_message`. And in a plain
project with its own `lib/core_ext.rb` reopening `String`: `String has no
method named squish`, `Integer has no method named minutes`.

`#reopened_elsewhere?` is the answer this engine has, and it needs a
Runtime Agent. So the reports appear in exactly the configurations that
cannot have one: a plain Ruby project, and a Rails project in VS Code's
Restricted Mode — which is every Rails project until the user trusts it.
The trusted-Rails run of the identical files reported none of them.

**Not fixed in 0.2.6** because the fix is `024.13`'s design question, not
a narrowing: telling "the workspace defines this class" from "the
workspace reopens a class that exists elsewhere" is what the Agent is
for, and doing it statically is its own task. Recorded here rather than
left inside `024.13` because the measurement is new and it is much larger
than that entry implies.

**Direction:** a class the workspace declares *and* that something
outside the workspace also declares is never closed. RBS is one such
witness and does not know `Date`; the gem's own `sig/` is another. Until
one exists, section 0.4 says a wrong answer on a walked path is what
blocks, and this is one.

**Re-triaged in 0.2.17** (`024.276`). This is one of the two where the pasted reason happened to be true: the Direction needs a witness outside the workspace — RBS, or a gem's own `sig/` — that says a class is declared elsewhere, and until one exists section 0.4 says a wrong answer on a walked path is what blocks. That witness is `024.R7`. Not re-driven since the measurement in the body, which is dated there.



**Not driven at 0.3.0 in its own shape**, but its premise is now
measured: it says the check is loudest where no Runtime Agent can
answer, and `024.76`'s re-drive with an Agent connected still
produced 19 reports over 335 files, every one false. So the Agent's
presence is not what separates the loud case from the quiet one,
which is worth knowing before this entry is worked on.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Its premise moved
under it: with an Agent connected the check is still all-false, so
this is about what it can newly say rather than a repair.
## 024.88 Completion unions a union's members; the diagnostic intersects them

```yaml
status: open
kind: defect
user-visible: yes
user-visible-note: >
  The list now says which members only one branch has, by ordering
  (0.2.15). What stays open is whether completion should offer them at
  all, which is D3's shared-resolver question and moves with its
  siblings.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`#members_of`),
`core/lib/ovallsp/diagnostics/engine.rb` (`#reportable_branches`)

`x = cond ? "s" : 1` — completion after `x.` offers **313** items, every
member of String's list *and* Integer's, `upcase` among them. Picking one
raises `NoMethodError` on half the branches. The undefined-method check
at the same position takes the opposite and correct stance: it reports
only when *every* branch lacks the method.

Two features answering one question about one receiver with inverted
quantifiers, and completion is the one whose answer can be acted on
wrongly. Measured through the real server by a review round of 0.2.6.

### Re-driven in 0.2.15

**The headline reproduces**: 313 items, `upcase` among them, and
accepting it raises `NoMethodError` on the Integer branch — taken from
the interpreter, `1.respond_to?(:upcase)` is `false`.

**The second sentence does not.** "The undefined-method check at the
same position takes the opposite and correct stance" is not observable
there. Driven through the engine with a control:

    union String|Integer, method on NEITHER branch  -> nothing
    union String|Integer, method on ONE branch      -> nothing
    plain String, method absent                     -> nothing
    workspace class, method absent (CONTROL)        -> reported

The check takes no view at that position at all. It is silent for
`024.129`'s separate reason — no undefined-method report on a
core-library receiver — and the intersecting stance it really does take
is visible only on a class of the user's own. The `KNOWN_LIMITATIONS`
paragraph asserted the contrast as something a user could see, which is
the `024.131` shape: a published sentence that misdescribes which way
the defect runs. Corrected in both languages.

**The bounded half is fixed in 0.2.15** and is not the quantifier
question. `#members_of` decided `conditional` correctly all along — true
for exactly the members one branch has and not the other, sorted after
the ones on both — and `Server#member_completion_items` never read it,
so every item carried the same four keys. The response now renders that
order into `sortText`, through
`Semantic::PrefixCompletion.sort_text`, which is the formatter the
bare-prefix list already uses. That list met this exact bug and its own
comment states the rule: `sortText` is what the editor orders by, so the
group is rendered into it rather than left implicit in the array order.
Member completion was the asymmetric one.

The bands are declared where they are used rather than borrowed from
`PrefixCompletion`'s scale, which orders locals, self-methods, constants
and Kernel in a different list answering a different question.

**What stays open is the quantifier**, and it is a design decision
rather than a patch. `042`'s D3 records the acceptance —
`x = cond ? "s" : 1` stops offering `upcase` — behind one shared
`ReceiverResolver#at`. Its two siblings `024.99` and `024.100` were
moved to 0.2.16 by `047` as needing new machinery or a decision about
which layer answers; this entry was left at 0.2.15, which looks like an
oversight in that split rather than a judgement. It moves with them.

And intersecting is not obviously right anyway: for a nilable receiver
`Widget | nil` a strict intersection offers **nothing** — measured, 121
members offered today, 0 of them unconditional, including the class's
own methods. Which quantifier completion wants is exactly the
"which layer answers" decision `047` used as its cut line.

**Re-triaged in 0.2.17** (`024.276`). What blocks this is the layer question `047` used as its cut line — which of completion and the diagnostic owns the quantifier over a union — and not the gem index. Intersecting is not obviously right either: for a nilable receiver a strict intersection offers nothing, measured at 121 members offered today and 0 unconditional. Capability-shaped, so the target stands on that rather than on the pasted sentence. Not re-driven since that measurement.


**Retargeted to 0.4.0 in 0.3.0's closing sweep.** The bands already
distinguish the two; what is left is telling the reader, which is a
change to what an item says.
## 024.100 The four features answer from different code paths and disagree at one position

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb`,
`core/lib/ovallsp/diagnostics/engine.rb`,
`core/lib/ovallsp/server.rb` (the signature-help handler)

Four positions, measured in single runs by 0.2.7's `drive` round:

- **A view's block parameter.** `<% @posts.each do |post| %>` then
  `post.titel` — hover answers `Post`, completion offers Post's columns,
  and the undefined-method check says **nothing**. Written
  `<% Post.all.each do |post| %>` it *is* reported, and so is the
  byte-equivalent Ruby in a `.rb` file. `@posts.each do |post|` is the
  commonest line in a Rails index view.
- **Hover against completion and diagnostics.** `p.update`, `p.save!`,
  `q.destroy` hover as `""` and answer no definition and no signature,
  while completion offers all three and the check accepts them. Hover on
  a column answers in full.
- **Signature help.** Silent for `Post.new(`, `Circle.new(`,
  `Post.find(`, `p.update(` — and answering for `takes(`,
  `"abc".split(`, `post_path(`. `Klass.new(` is the most-typed call shape
  in Ruby and its parameters are what the popup is opened for. Separately,
  an overriding method returns its label twice: `["area()", "area()"]`.
- **`024.99`**, above, is the same seam seen through visibility.

`S1`/`S2`/`S3` and `H3`/`C11` are PASS rows covering the inference these
positions rest on; none covers the disagreement.

**Direction:** one query per position that all four features read, which
is `037`'s availability item. Recorded separately because the evidence is
different: `024.76`'s family is about precision, this is about four
answers to one question.

**Re-triaged in 0.2.17** (`024.276`). The Direction is one query per position that all four features read — `037`'s availability item — which is a restructuring, not an enumeration. It stays at 0.3.0 because that restructuring is what two of that release's promises rest on, per `045`'s D3. Not re-driven since the disagreement was recorded.



**Not driven at 0.3.0**, and it is the entry most worth driving next:
it is four positions that disagree, and the first of them -- `<%
@posts.each do |post| %>` then `post.titel` -- is the commonest line
in a Rails index view. It needs the E2E harness.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Four surfaces
agreeing at one position means three of them answering where they now
do not.
## 024.106 A module's singleton calls go unchecked — `module_function` and `extend self` producing nothing is withdrawn

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/parser_service.rb`, `core/lib/ovallsp/semantic/method_resolver.rb`

```ruby
module MF
  module_function
  def mf_a; end
end
```

`MF.` completes 190 items, none of them `mf_a`. The same for
`module_function :mf_c` and for `extend self`. A plain `def self.x` or
`class << self` in a module works, and hover and definition on those are
correct — so it is these two idioms specifically, and both are everyday
plain Ruby.

Separately and in the same area: **nothing checks a module's singleton
calls at all.** `PlainClass.nope_y` is reported; `PlainMod.nope_x` is
not, on a module whose `def self.` methods the engine does know.

**Measured in 0.2.15, as a cost rather than a description.** The
`argument-count` check's recall over `core/lib` is **31 / 31** on a
class's singleton method and **0 / 16** on a module's — 47 deliberately
wrong calls, `scripts/measure_arity_recall.rb`, the numbers in `024.40`.
Every miss in that sample is this entry, with no second cause. So the
price of declining on modules is a third of the arity mistakes in a
codebase shaped like this one, and it is worth knowing that the trade is
that size rather than a rounding error — the alternative 0.2.10 tried
reported `Rails.application`, `Rails.env` and `Rails.logger` as missing,
which is still the worse half.

**Re-triaged in 0.2.17** (`024.276`). Declining on modules costs a third of the arity mistakes in a codebase shaped like this one, which its body measures — but the alternative 0.2.10 tried reported `Rails.application`, `Rails.env` and `Rails.logger` as missing, and section 0.4 ranks that worse. Answering here needs the witness `024.R7` supplies, and `045` records this as one of D2's four.


**Split by measurement at 0.3.0: the completion half is gone, the
diagnostic half is not.**

`MF.`, `Selfish.` and `PlainSingleton.` each offer **192** items and
each offers its own method -- `mf_a` under a bare `module_function`,
`es_a` under `extend self`, `ps_a` under a plain `def self.`. The
entry's "190 items, none of them `mf_a`" does not reproduce. At the
parser, `mf_a` is declared `[:instance_method, :singleton_method]`;
`es_a` is declared instance-only and reaches the singleton side
through the chain instead, which is why it completes.

The second half reproduces, with a control in the same fixture:
`PlainClass.nope_y` is reported and `PlainMod.nope_x` is not.
`MethodResolver#availability` answers `absent? = false` for a
module's singleton receiver where it answers `true` for a class.

**Not taken in 0.3.0.** It is the same code `024.243` failed at four
times in this release, and it is a silence rather than a wrong
answer -- so it waits for the ancestor-reading change that entry
asks for, rather than being pushed at from a third direction.

## 0.3.3: the title is amended to the half that survives

The heading read "`module_function` and `extend self` produce nothing"
until here, which is the half 0.3.0's measurement withdrew — and it is
the string the generated Index renders and `docs/ISSUES.md` publishes, so
the register's searchable surface asserted a completion failure the
product does not have while `docs/KNOWN_LIMITATIONS.md` and its `.ja`
twin told users the opposite. That is the shape `024.130` records, caught
before the split rather than after it.

The surviving half is not about either idiom the old title named: it
reproduces on a module whose singleton methods are written plainly, and
`core/spec/ovallsp/parser_module_function_spec.rb` pins the withdrawn
half as fixed while its own comment marks the second one open. So the
title is rewritten to that half rather than given a suffix, which is what
`024.131` did with the same problem.

Amended, not deleted: the paragraphs above are the finding as it was
raised and the measurement that halved it, and both are why the entry is
still open.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** The completion half
does not reproduce; the diagnostic half is a module's singleton
surface becoming judgeable, which is capability.
## 024.121 Nothing measures how much of this tree no test would notice changing

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing an editor user meets directly. What it costs is that a
  behaviour can be broken silently, which every user-visible entry in
  this register that began "and no test noticed" was downstream of.
target: 0.4.0
```

**Area:** `scripts/check_pinned_mutations.rb`, `scripts/hunk_sweep.rb`,
`.github/workflows/ci.yml`

Three review rounds in a row, across three releases, have found an
example that could not fail under the change it was written to guard
against. The maintainer's question — *can this be made structurally
impossible to miss, rather than found again next time?* — is the right
one, and the honest answer is that two of the three layers exist and the
third does not.

**Layer 1, per change set: `hunk_sweep.rb`.** Reverse-applies each hunk
of a change set and requires something to fail. Exists, `CLAUDE.md`
requires it. Covers *changed* lines only, is run by hand, and has a
recorded blind spot: reverting a hunk that adds a whole method removes
its only call site too, so the decisions inside it are never exercised.

**Layer 2, per commit: `check_pinned_mutations.rb`.** Added in 0.2.12.
An example that claims to distinguish two behaviours names the mutation
it claims to catch, and CI applies it and requires the failure. This is
the layer that makes a *stated* claim unable to be false — and it caught
a dead clause on its first working run.

**It is opt-in, and that is the gap.** A decision nobody thought to add
to the manifest is exactly as unprotected as before. Layer 2 turns "a
reviewer might notice the comment is wrong" into "the comment cannot be
wrong", which is real, but it does not turn "someone must think of it"
into "nobody has to".

**Layer 3, periodic and missing: every behavioural line, no manifest.**
Mutate each one mechanically — flip a boolean, drop a guard, swap a
comparison — and require some example to fail. That is ordinary mutation
testing, and it is the only form that needs nobody to remember anything.

Its cost is why it is not layer 2: a 2,276-example suite at roughly three
minutes, times thousands of mutants, is hours rather than minutes. So it
does not gate a commit. It runs on a schedule, and **what gates is a
ratchet**: the surviving-mutant count is recorded in the tree, CI fails
if a change makes it worse, and lowering it is the only edit allowed.
That is what converts "someone should look" into "the build says no",
and it is the same shape as the `<!-- measured: -->` markers this
register already uses — a number that is derived rather than typed, and
may only move one way.

Two things to settle when it is built, both learned the expensive way
here: run it on a schedule and never beside another tree-mutating run
(`026`), and seed the ratchet from a measured run rather than a guess,
because a number recorded from one run of a load-dependent quantity is
`040`'s own correction.

`024.71` is a precondition worth naming: at three minutes serial the
periodic run is hours, and the fixture isolation that entry describes
takes the suite to about a minute, which takes this from overnight to
lunchtime.

**Re-derived during 0.2.16 and left open deliberately.** The census
above still holds: `hunk_sweep.rb` is there and run by hand,
`check_pinned_mutations.rb` is there and gates from ci.yml, and layer 3
is absent on all three of its parts -- no runner, no tracked
surviving-mutant count, no scheduled job. What decided against building
it in this release was not the cost estimate but the seed: a ratchet is
a number that may only move one way, `040`'s correction says to take it
from a measured run rather than a guess, and the run that would produce
it is the one `024.71` -- still open, at the same target -- is the
precondition for. A runner with no measured seed is a script nothing
invokes and a job that cannot gate, which is worse than the gap it
would be filling. Recorded so the next session does not re-derive the
census to reach the same place.

**Re-triaged in 0.2.17** (`024.276`). Nothing about gems: this is about how much of *this tree* no test would notice changing, and its Area is `scripts/check_pinned_mutations.rb` and `scripts/hunk_sweep.rb`. It adds no capability and repairs no claim the product makes, so it belongs on the patch line and not in a capability release.

0.2.17 paid part of it in passing and found the shape sharply: five decisions fixed in `core/spec/meta/measured_claims_spec.rb` could not be pinned at all, because the manifest mutates `core/lib/` and `scripts/` only and refuses a spec file. Machinery that lives in a spec is machinery nothing can mutate — which is the gap this entry is about, arriving from inside it.
### 0.2.18: the 0.2.17 sentence above overstates it, measured

That paragraph says five decisions in `core/spec/meta/measured_claims_spec.rb`
"could not be pinned at all". **They cannot be pinned by the manifest,
and they are pinned.** Four of them were inverted by hand in a scratch
copy, one at a time:

```
scope narrowed to one file      17 examples, 2 failures
published pages excluded        17 examples, 1 failure
thousands separator ignored     17 examples, 1 failure
citation pattern unused         17 examples, 5 failures
```

Every one is caught, by a second example in the same file — which is
precisely what `check_pinned_mutations.rb`'s own header prescribes for
a spec, and for a stated reason: the applier writes to the real file
and restores it, so mutating a spec could delete the example being run.
The manifest's silence there is a scope decision, not a hole.

This is the class this register calls "promoting a finding is making a
claim": the sentence was written in the release that found the shape,
read true, and was never run against the tree.

### Retargeted to 0.3.0, on this entry's own argument

Layer 3 is unbuilt and its blocker is unchanged: a ratchet is a number
that may only move one way, `040`'s correction says to seed it from a
measured run rather than a guess, and the run that produces the seed is
the one `024.71` is the precondition for. `024.71` was measured in this
release and moved to 0.3.0 — it needs a parallel runner that does not
exist, and copying a booted Rails application per worker is minutes of
setup to save minutes of run.

A layer-3 entry cannot land in a release its own precondition is not
in. Both travel to 0.3.0 together, with `024.45` and `024.38`, which
are the same measurement problem seen from the product's side.



**Not taken in 0.3.0, and 0.3.0 is evidence for it.** The missing
third layer is a whole-tree measure of what no test would notice
changing. This release added five behavioural changes and each was
pinned by hand into `pinned_mutations.yml`, which now stands at 137
-- the manifest is layer two working exactly as described, and the
absence of layer one's automation is why every one of those pins was
a manual step. Still infrastructure of its own size.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** A measure of this
tree's own coverage. 0.3.0 pinned five decisions by hand, which is
the absence this entry names.

## Not attempted in 0.3.2: layer 3 is a capability

Layer 3 is a scheduled mutation run plus a ratchet gate in CI: a new
script, a recorded count, and a job that fails when the count rises.
That is a capability, and `docs/PUBLISHING.md` puts a capability
outside a patch — so taking it here would either mis-number the release
or hold the release for it.

Nothing about it has decayed in the meantime, and one thing has
improved: `check_pinned_mutations.rb` now refuses a `from:` that
matches no line, so layer 2 can no longer report a mutation as caught
because it was never applied. That closes the way layer 2 could have
been silently empty while the ratchet was still missing, which is the
worse of the two gaps this entry names.

Moved to 0.4.0.

## 024.129 No undefined-method report on a core-library receiver

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

`"hello".no_such_method`, `[1,2,3].no_such_array_method`, `42.upcase`:
nothing, in either mode, while completion at the same position knows the
receiver exactly.

`024.13` is why, and the trade is deliberate. It is recorded as its own
entry because section 0.1 names this check as half of what 1.0.0 is, and
because another editor flags the same typo.

**Was one of nine bullets under `024.90` until 0.2.14.**


**See `024.290`** for the measurement that `024.R7`, as shipped in
0.3.0, carries no core classes at all -- which is the direction this
entry names.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** A core-library
receiver becoming judgeable needs `024.R7` to carry core classes,
which is a scope change to the walk and a new answer at the end of
it.
## 024.132 A scope defined in a concern's `included do` has no type

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/models/model_registry.rb`

`included do scope :recent, -> { … } end` defines a scope on every
including class, and the engine gives it no type — so the chain from it
answers nothing.

Adjacent to `024.87`, which is about a relation losing its type after one
hop; this is about never having one.

**Was one of nine bullets under `024.90` until 0.2.14.**

**Re-triaged in 0.2.17** (`024.276`). A scope defined in a concern's `included do` has no type, which is a silence rather than a false answer — the product says nothing where it could say something, and giving it one is capability. Adjacent to `024.87`, which is about a relation losing its type after one hop; this is about never having one. Not re-driven since it was split out of `024.90`.



**Not driven at 0.3.0.** `included do scope :recent, -> { … } end`
needs a concern included into a model with a database behind it,
which is the E2E harness rather than a probe.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** A scope from a
concern's `included do` gaining a type is an answer where the chain
currently has none.
## 024.137 `WorkspaceIndex#search` holds the index lock for the whole walk

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/workspace_index.rb` (`#search`, `#rank`)

`workspace/symbol` runs a `downcase.include?` over every key of
`@by_symbol`, under `@mutex`, on every keystroke in the symbol picker.
`#find` has `@by_simple_name` for exact lookups; substring search has no
equivalent and cannot use that one.

**What a user sees:** the "Go to Symbol in Workspace" picker slowing as
the workspace grows, and — because the scan holds `@mutex` — it is the
same lock indexing takes, so a large workspace's picker can stall the
indexing behind it rather than only itself.

**Direction:** not a second index by default. Measure first: this is
recorded with no measurement at all, and `CLAUDE.md` says a claim about
this tree's numbers is derived rather than typed. The cheap
countermeasure if it does matter is to snapshot the key set under the
lock and filter outside it, which removes the interference without
adding an index to keep consistent.

**Where this came from:** `008.5`'s `## 残課題`. See `024.139`.

### Half of this is fixed in 0.2.16, and the entry stays open for the other half

Everything above this line is the entry as it was written. It is kept
because two of its sentences turned out to be false and the correction is
the useful part of the record — and because the half it is right about is
still true after the fix.

**The last sentence of the first paragraph is wrong.** `@by_simple_name`
maps a *downcased simple name* to the SymbolIds sharing it — its keys are
exactly the strings this query is matched against. `#find_by_simple_name`
looks a key up exactly because exact lookup is that method's question;
nothing stopped a substring search from scanning the same keys. Scanning
them is what `#search` does now, and it is the third *query* to be moved
off a full scan of the symbol table — `#method_symbol_ids` in 0.1.14,
`#prefix_search` in 0.2.0, this in 0.2.16 — each found separately, each
having derived per symbol a value an index was already holding.

The first of those moved onto `@by_owner_kind`, not onto
`@by_simple_name`: it is asked once per ancestor, and 0.1.14 grew the
singleton chain from one entry to six, so one `Widget.` completion went
from one full scan to six. This paragraph said `@by_simple_name` for all
three until a review round checked it against that structure's own
comment, against `workspace_index_cost_spec.rb`'s pre-existing example,
and against the pre-0.1.15 body of the method.

Measured on 14,958 distinct SymbolIds (16,688 declaration entries, 8,259
distinct simple names, 1,039 files) from five installed Rails components.
**One run, four implementations, one process, one index**; median of 25
interleaved calls at `limit: 100`. The run's own control is that all four
agree on every answer, digested over name, kind, owner, uri, position and
key set — they did, for every query.

| query | before | after | no `:simple` carry | snapshot | snapshot's lock hold |
|---|---|---|---|---|---|
| `""` (picker opens) | 17.9ms | 17.5ms | 20.1ms | 21.1ms | 16.6ms |
| `"a"` | 13.6ms | 11.4ms | 12.9ms | 15.6ms | 10.9ms |
| `"as"` | 5.5ms | 2.1ms | 1.7ms | 6.3ms | 1.5ms |
| `"act"` | 4.9ms | 1.4ms | 1.1ms | 5.6ms | 0.9ms |
| `"record"` | 4.3ms | 1.1ms | 0.7ms | 4.8ms | 0.5ms |
| `"association"` | 4.1ms | 1.1ms | 0.8ms | 4.7ms | 0.2ms |
| `"save"` | 3.6ms | 0.8ms | 0.5ms | 4.2ms | 0.1ms |
| `"connection"` | 4.3ms | 1.2ms | 0.8ms | 4.8ms | 0.3ms |
| `"zzzznope"` | 3.6ms | 0.7ms | 0.4ms | 3.9ms | 0.0ms |

This is the only table. An earlier draft of this entry carried different
figures from the code comment beside it and from the report that
accompanied it — three framings of one measurement, disagreeing about
whether the picker's opening state improved or regressed, in a change set
whose whole argument turns on that row. `#search`, `#rank` and
`spec/meta/workspace_index_cost_spec.rb` now all cite these numbers.
There is no separate "lock held" column for the first two: their whole
method body is inside `@mutex`, so the call time *is* the hold.

**What is fixed.** Deciding which symbols match no longer derives a name
per symbol. A query of two characters or more falls from 3.6–5.5ms to
0.7–2.1ms — roughly four times — and that is per keystroke, which is
where the repeats are.

**What is not, and why this entry stays open.** The empty query is
17.9ms before and 17.5ms after: unchanged. It matches every symbol in the
workspace *by definition*, so no improvement to "which symbols match" can
reach it; what it costs is building and ranking 16,688 candidates. And
the empty query is not an edge case — **it is what the picker sends when
it opens**, so it is the first thing a user experiences, and the second
is a one-character query at 11.4ms. Both remain linear in workspace size.

The consequence in the second half of **What a user sees** also survives,
though its stated mechanism was wrong (below): an open picker still
delays indexing, because the delay comes from the *outer* lock and the
request still holds that for its whole duration. Shortening the request
by four times shortens the stall by four times for a typed query, and not
at all for the state the picker opens in.

So the paragraph in `KNOWN_LIMITATIONS` is **narrowed, not removed** — in
both languages. Retiring it would have published silence about behaviour
the product still has; `CLAUDE.md`'s "promoting a finding is making a
claim" applies in this direction too, because deleting a limitation
restates it in the present tense as absent.

The entry's proposed countermeasure was the wrong shape twice over:

- **The snapshot does not pay.** Copying `@by_symbol.keys` under the
  lock, filtering outside it and re-taking the lock for the survivors is
  slower end to end than the shipped code at every one of the nine
  queries, because the filter still derives a simple name per symbol and
  now allocates a key array and a second hash lookup per survivor. Nor
  does it reliably hold the lock for less: ranking sits inside its second
  critical section, so the picker's opening state holds the mutex for
  16.6ms of a 21.1ms call — against 17.5ms for a call that never releases
  it. It only wins on hold time while a query is being typed, which is
  the case that was already cheap. It also opens the window the entry's
  own author flagged, in which a copied key names a symbol removed while
  the filter ran.
- **The lock it names is not the one indexing waits on.** `Server`
  dispatches `workspace/symbol` inside `with_index_snapshot`, which is
  `@index_mutation_mutex.synchronize` — and every index mutation
  (`#apply_file_summary`, the cold-index commit, the changed-files batch)
  commits under that same outer lock. `server_spec.rb` has an example per
  read request pinning that deliberately, so indexing blocks for the
  whole request whatever the inner lock does. What shortens the stall is
  shortening the call; releasing the inner mutex mid-scan would have
  measured as exactly zero improvement.

The second is the more general point: an entry naming a lock as the cause
was reasoning from the method it was reading, and the binding lock was
one layer up in a different file. Note what that does *not* buy — the
mechanism was misattributed, but the consequence the user was told about
was correct, so correcting the mechanism is not grounds for deleting the
user-facing paragraph.

**A fixture that could not distinguish what its own title claimed.** The
first control written for case-insensitivity indexed `::User` and
`::UserProfile` and asserted `search("USER")` returned them in that
order. `::User` sorts ahead of `::UserProfile` on the *name* half of the
ranking key regardless, so the example answered the same whether `#rank`
compared the bucket key against the downcased needle or against the raw
query — the exact-match half of its title was pinning nothing. Run, not
reasoned: with `rank(matches, query.to_s, limit)` the whole file reported
82 examples, 0 failures. The fixture now puts the exact match *last* on
the tail key (`::Widget` in `z.rb`, `::AbstractWidget` in `a.rb`, query
`"WIDGET"`), so the two candidate implementations invert the pair, and
the mutation is registered in `spec/meta/pinned_mutations.yml` — which is
this repository's own countermeasure for exactly this class and which the
first version of this change set did not use.

**Two lines this change cannot pin behaviourally**, recorded rather than
faked:

- `#rank` reading the carried bucket key is a source-text decision, held
  in `spec/meta/workspace_index_cost_spec.rb` the way this class's other
  cost decisions are. The first version of that assertion named the bare
  `fetch` call, which the explanatory comment inside `#rank` contains
  verbatim — so the check was answered by the prose it sat next to, and
  subscripting the hash instead left everything green. The needle now
  carries syntax no sentence would.
- `#search`'s `@by_symbol.fetch(symbol_id, [])` cannot take its default
  through any public path: `#replace_file` writes both structures and
  `#remove_file_locked` prunes both in one critical section, and `#search`
  never leaves `@mutex`. Subscripting instead leaves the whole
  behavioural file green. It is not a decision taken here in any case —
  `#initialize`'s comment states the rule for the class and all six
  readers of `@by_symbol` follow it. A source-text check that they all
  still do would be the countermeasure if a seventh ever diverges; it is
  not written, because a review loop is for fixing what was found.

**And a measurement trap, for the third recorded time.** The first
before/after comparison put this repository's own `core/lib` in the
corpus. Editing `workspace_index.rb` moved declaration line numbers
*inside the corpus*, so five of eight answer digests differed and the
change looked as though it had altered the answers — while an in-process
comparison of the two implementations against one index said "identical"
at the same moment. `CLAUDE.md` records this exact corpus as one of its
three false results, which is what made the contradiction worth chasing
instead of picking whichever number was more convenient. The corpus above
is installed gems only, and the harness refuses a root inside this tree.

**Re-triaged in 0.2.17** (`024.276`). Workspace symbol search scans every symbol on every keystroke. *(That sentence was already false when it was written -- 0.2.16 replaced the full scan with an index on the names being matched, which the published limitation says and this line did not; driven in 0.3.2, see below.)* No capability, no gem question — a repair to something `W3` already claims works. Its body carries a warning worth heeding before re-measuring: a corpus run once looked as though the change had altered the answers while an in-process comparison of both implementations against one index said they were identical, and `CLAUDE.md` names that exact corpus among its three false results.

### 0.2.18: the empty query's cost, split — and why it stays where it is

The table above times the query end to end. Split, on 997 files of four
Rails components (8,241 simple names, 14,590 symbols), median of 15:

| query | matches | building the list | ranking | whole |
|---|---|---|---|---|
| `""` | 16,194 | 5.9ms | 6.5ms | 12.4ms |
| `"a"` | 10,612 | 4.2ms | 4.3ms | 8.5ms |
| `"save"` | 59 | 0.4ms | 0.0ms | 0.5ms |

Roughly half and half for the state that costs the most. Nobody had
split it before; the previous rounds timed the whole call, and the entry
above says in as many words what that hides.

**Two optimisations were considered against that split and neither is
taken.**

*A streaming top-N*, fusing the build and the rank so 16,194 hashes are
never allocated, is worth about 2x on one frame — and replaces a legible
`min_by(limit)` with a hand-rolled bounded heap. `048`'s result is that
eight of eight optimisations of working code failed measurement; this
one passes, narrowly, and buys a frame the user sees once per picker
opening.

*Early exit on the empty query* looked free and is not. The rank key's
primary discriminator is `symbol_id.name`, **not** the
`@by_simple_name` bucket key — so walking the buckets in sorted order
and stopping at `limit` would change *which* hundred symbols the picker
shows. That is a user-visible answer, not a speed-up.

**Retargeted to 0.3.0.** What remains is inherent to "match everything":
the empty query is every symbol in the workspace by definition, and the
Direction rules out a second index by default. The published limitation
already states the cost, with its measured numbers, in both languages.

`024.139` is the sibling that this one's `#find` sentence pointed at.


**Driven at 0.3.0, and the cost is smaller than the title suggests.**
2,000 classes indexed, 200 searches: **0.031s total, 0.16 ms each**.
The scan really is O(every symbol) -- that part of the entry is
structurally true -- but at a workspace of this size it is not
something a user meets. Recorded so the number is here before anyone
optimises on the strength of the heading; the case that would justify
it is a workspace an order of magnitude larger, and this project has
not measured one.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Measured at 0.16 ms
per search over 2,000 classes -- cost, and small, so the patch line
and not urgently.

## Re-read and re-driven in 0.3.2: the entry describes code that is no longer there

It says `#search` "runs a `downcase.include?` over every key of
`@by_symbol`". It does not, and has not for some time — it walks
`@by_simple_name`, the same index `#find` uses, and only then reaches
into `@by_symbol` for the entries of the names that matched. The
premise the cost was argued from is gone.

Measured over this repository's own `core/lib` — 89 files, 1,874
symbols — with `limit: 100`:

    search("a")                    0.95 ms   (100 hits, the cap)
    search("build")                0.08 ms   (20 hits)
    search("reso")                 0.12 ms   (49 hits)
    search("definitely_not_present") 0.06 ms  (0 hits)

A single-character query is the worst case and costs under a
millisecond. What survives of the entry is the *lock*: the walk still
holds `@mutex`, which is the lock indexing takes, so a large enough
workspace could still put a picker keystroke in front of indexing. That
is a real shape and this measurement does not reach it — 1,874 symbols
is a small workspace, and the entry's concern was a large one.

So it stays open on the half that was not measured away, with the half
that was struck out rather than left to be quoted forward. Moved to
0.4.0: what is left needs a workspace big enough to show it, which is
an experiment to set up rather than a fix to write.

## 024.151 A check can be disabled, and no check notices — closed on one instalment in 0.3.2, reopened

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal, and it is the largest single class this project has
  recorded: 55 confirmed instances from one review round. Nothing a
  user meets; everything this project uses to decide whether a change
  is sound.
target: 0.4.0
```

### 0.2.18: the two checks that had no reachability assertion at all

Surveyed rather than assumed. Of the seven `scripts/check_*.rb`, five
have a spec that asserts how much they read — `doc_links` and
`site_links` six ways, `home_paths` and `suites_ran` two,
`interpreter_sessions` its `sessions=` count, which this session added
for exactly this reason. **Two had none: `check_pinned_mutations` and
`check_swallowed_failures`.**

Both now do, and the two gaps are not the same size, which took driving
to find out:

- **`check_swallowed_failures` has no emptiness guard at all.** Its
  `Dir.glob` returning nothing leaves `problems` empty, and empty is
  what it reports as success. The spec now asserts it found at least 100
  rescue sites in `core/lib` — a floor, because the exact number changes
  every release and a scan that has stopped seeing the directory does
  not return 140-something.
- **`check_pinned_mutations` already refuses an empty manifest** — exit
  1, with a message. *The first draft of this note said it did not, and
  driving it said otherwise.* What nothing caught is a manifest cut to a
  handful: not empty, consistent with itself, and it passed both
  examples. The floor is 50.

**This does not close the class.** 55 instances were confirmed and these
are two; what it closes is the two checks whose own reachability nothing
defended, which is the shape at its most embarrassing — a checker that
guards other people's guarantees and not its own.

**Retargeted to 0.3.0.** The remaining instances are spread across the
tree and each needs its own assertion; the countermeasure is a habit
(every check asserts what it read) rather than a change, and
`pinned_mutations.yml` at 100 entries is that habit already working. It
is not a defect one release closes.

**Area:** `core/spec/meta/pinned_mutations.yml`,
`scripts/check_pinned_mutations.rb`

0.2.14's round 2 took twelve guarantees and tried to make each false
while every check stayed green. **It succeeded against all twelve.** The
individual breaks are recorded in
`docs/design/tasks/046-0.2.14-making-the-record-true.md`; the class is
one sentence:

> The checks are correct. Their **reachability** is not defended.

The sharpest instance, and the one that shows the shape: `SKIP` in
`check_doc_links.rb` was an ordinary constant. Widening it dropped
inspection from 537 files to 117, left a dangling citation in a
`core/lib` source comment unreported, and all four examples passed —
because the examples asserted *outcomes on fixtures*, and none asserted
*how much of the tree was read*. The file's headline claim, "source
comments are in scope, deliberately", was one edit away from false and
nothing in the tree could tell.

**This is `CLAUDE.md`'s oldest rule, applied one level up.** *Behaviour
that no test fails on when it is reverted counts as a defect* — the
checks are behaviour, and almost none of them was pinned.

### What was built in 0.2.14, and why it is not enough

- **Coverage floors.** A scanner reports what it read, per root, and a
  spec asserts each is non-zero. Structural, so not a number to
  maintain, and not a second copy of the exclusion. Applied to
  `check_doc_links`.
- **The mutation manifest reaches `scripts/`.** `042`'s D7 exists to ask
  *does this example fail when the decision it names is inverted*, and
  until now it could only ask that of `core/lib` — so no decision inside
  a check could be pinned by the one mechanism built for pinning
  decisions. Seven entries added: `SKIP`, the relative-link pass,
  `--others`, the pending test, the `NOT YET` exemption, the
  re-derivation refusal, the SBOM comparison.
- Not the specs. The applier writes to the real file and restores it,
  which is safe for a script a spec shells out to and is **not** safe
  for a spec file, where the mutation could remove the example being
  run. A decision inside a spec needs a second example instead.

**What remains open is most of it.** 55 confirmed findings, and the
honest statement is that they were fixed at the rate of one mechanism
per class, not one patch per finding. In particular:

- Several checks prove wiring by **substring search** — an error
  message, an exemption comment, or a script's own usage string
  satisfies them. `release_gate_spec` and `script_encoding_spec` are
  both this shape.
- `preflight.rb` is 178 lines of gate that no spec reads: the whole
  thing can be reduced to a no-op with every check green.
- Several scanners' scopes are hand-written glob or extension lists —
  the exact defect the citation scanner was fixed for, in the scanners
  that check the citation scanner.

**Direction.** Not 55 patches. Two mechanisms, in this order:

1. **Every check states its own coverage, and a spec asserts a floor on
   it.** `check_doc_links` is the worked example. This kills the whole
   "narrow the input" family at once.
2. **Wiring is proved by execution, not by text.** A check that claims
   something is invoked should invoke it, or read a manifest that does,
   rather than grepping for its name. Every substring-based instance
   collapses into this one.

*Recorded rather than done, deliberately. `CLAUDE.md` bounds a review
loop at three rounds finding defects and then says to ship with what is
open written down — a 55-finding sweep started at round 2 is exactly the
unbounded loop that rule exists to prevent, and the countermeasures
above are worth more than the patches would be.*

### The ten instances round 2 and round 3 confirmed, listed

Recorded here rather than as ten entries: each is this class in a
different check, and the register's rule is one entry per defect. The
Direction below is what closes all ten; a patch that fixes one of them
and not the shape has not closed anything.

- **An Area line C3 cannot parse counts as naming no paths, so the path-existence guarantee is opt-out, and it never looks at a resolved entry at all**  
  ``scripts/deferred_findings.rb` (`AREA_PATH`, `#area_paths`), `core/spec/meta/deferred_findings_spec.rb` ("names only paths that exist, in every open entry's Area"), `docs/design/tasks/024-deferred-review-findings.md` (024.25's Area line)` — 046's RC-3 is "pointers with no resolver", and C3 answers it for `**Area:**` lines. `AREA_PATH` matches only a backticked path rooted at `core|vscode|scripts|docs|site|.github`, and `area_paths` returns `[]` for anything else with no signal at all, so an entry the matcher cannot read is silently treated as making no claim rather than as an entry the check could not verify. Two of the 57 open defects are already outsi

- **check_doc_links' unreadable-file and shallow-clone refusals are unpinned — append to 024.151 rather than opening separately**  
  ``scripts/check_doc_links.rb` (lines 128-129 and 295-301), `core/spec/meta/pinned_mutations.yml`, `core/spec/meta/doc_links_spec.rb`` — The `unless unreadable.empty? … exit 1` block is 0.2.14's repair for a swallowed failure — its own comment says "until 0.2.14 this comment claimed and nothing did" and cites CLAUDE.md's rule — and it shipped with no test. Deleting the seven lines leaves the spec green while a tracked file that is not valid UTF-8 is dropped from `inspected` with no output at all, so a citation of a document that has never existed pass

- **The SYNTHETIC allowlist can be widened to switch the detector off, and three documents cite it as the model of a guarded edit**  
  `scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb, core/spec/meta/measured_claims_spec.rb, core/spec/meta/no_wall_clock_thresholds_spec.rb, CLAUDE.md` — Adding one word to SYNTHETIC turns the detector off completely, and every check stays green: the list's contents are pinned nowhere, `pinned_mutations.yml` has no entry for this file, and the only names an addition cannot be are the four the examples plant (alice, tkato, bob, carol). The mechanism is 024.151's class — widening an allowlist constant is its sharpest recorded instance — but the second half is its own de

- **release_gate_spec proves wiring by substring, so a mention, an error message or an echo counts as an invocation**  
  `core/spec/meta/release_gate_spec.rb (`haystack_excluding`, the `include?(base)` test at line 117)` — The check's stated guarantee is that an executable cited in RELEASE_CHECKLIST's evidence column 'is invoked by something that runs'. It is implemented as: does this basename appear on a non-comment line anywhere under core/spec, scripts/, or the five named callers. Nothing distinguishes a call from a mention. Round 1's fix — excluding the candidate's own file — closed only the self-naming case; the same string in a d

- **A row can be exempted invisibly and without limit, and the example guarding against the check going inert measures the unfiltered table**  
  `core/spec/meta/release_gate_spec.rb (the `[unwired marker]` skip at line 107, the cell join at line 65, the floors at lines 135-136), docs/RELEASE_CHECKLIST.md` — Any row containing `[unwired marker]` is skipped. The marker renders as nothing, nothing bounds how many rows may carry it, and nothing enforces the prose requirement that an unwired row 'must still say what does enforce the item now'. Because line 65 joins the 状態 column with the evidence column, the marker also works from the status cell. The example written to stop the check going inert — 'finds evidence to check i

- **release.sh's payload-hash, semantic-smoke and SBOM refusals are refusals only because of `set -euo pipefail`, and nothing pins that line**  
  ``vscode/scripts/release.sh` (lines 23, 195-206), `core/spec/meta/release_script_guard_spec.rb`` — Three of the script's named guarantees — the packaged payload-hash check (line 196), the semantic smoke (line 199) and the SBOM-vs-artifact check (line 206) — are bare commands with no `||`, no `if` and no status test. That they refuse rather than log is entirely a property of `set -euo pipefail` on line 23, and nothing in the repository asserts that line exists: `release_script_guard_spec.rb` asserts only that the t

- **No workflow guard pins that a gating CI step actually gates, so any of them can be switched off with every check green**  
  `.github/workflows/ci.yml, core/spec/meta/ci_skip_guard_spec.rb, core/spec/meta/site_version_guard_spec.rb` — Every spec that guards a CI-only check locates its step in parsed YAML and then asserts the step's `run` text. None of them reads the two parsed-YAML keys GitHub Actions actually uses to decide whether a step runs and whether its failure fails the job -- `if` and `continue-on-error` -- and none rejects a `run` line whose exit status has been neutralised with `|| true`, `; true` or `set +e`, because the assertion is `

- **The locale guarantee is proved by reading the scripts' text over a hand-written glob, and no script is ever executed under a bare locale**  
  `core/spec/meta/script_encoding_spec.rb` — This is 024.151's own named instance ("`release_gate_spec` and `script_encoding_spec` are both this shape") given an exact reproduction and a one-line direction; record it under 024.151 if the maintainer prefers. The guarantee — every script in `scripts/` survives `LC_ALL=C` — is enforced entirely by reading source text, and every part of that reading is narrower than the claim. (a) Line 47 tests `File.read(...).incl

- **The enumeration guard asserts no coverage, so narrowing its pathspecs to nothing leaves it green**  
  `core/spec/meta/untracked_visibility_spec.rb` — Another instance of 024.151's class, in the file 024.147's countermeasure lives in. The third example builds `offenders` from `RepoFiles.list(UNTRACKED_ROOT, "scripts/*.rb", "core/spec/meta/*.rb")` and asserts it is empty. Nothing asserts the enumeration produced any files, and nothing asserts the needle logic would flag a planted offender, so an input of zero files is indistinguishable from a clean tree. The tree al

- **design_doc_drift_spec's non-empty floor covers three of the six extractions the file reads, so §5 can pass comparing two empty lists**  
  ``core/spec/meta/design_doc_drift_spec.rb` (the `extracts a non-empty list from each place it reads` example)` — The example exists because "[e]ach example above compares two lists, and would pass on two empty ones", and its name says it checks "each place it reads". It asserts three floors — §6's documented block, `contributes.commands`, `contributes.configuration.properties` — out of six extractions in the file. Nothing floors §5's documented block, nothing floors the status strings scanned out of clientPresentation.ts, and n

**Re-triaged in 0.2.17** (`024.276`). Nothing about gems: the subject is whether this repository's own checks are *reachable*, and twelve of them were made false with every check green. It adds no capability, so it belongs on the patch line.

0.2.17 paid several instalments of it — coverage floors on the measured-claim scanner and the home-path scanner, a reader for `released-in:` which had none, and a check that open entries do not repeat a justification word for word. Each is the shape this entry's Direction asks for: an answer where the value is produced, rather than an assertion at each reader.


**Not taken in 0.3.0.** Defending the checks' reachability is a
change to every checker, and this release instead spent its
measurement on the entries the release owed. Worth noting from the
sweep: two of 0.3.0's own checks *did* catch a disabled guard --
`check_pinned_mutations` refused a `from:` that matched zero lines
twice, and once that matched five -- so the class this entry names
is real and the instances it names are not all still open.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** The checks'
reachability is this repository's own machinery, which the table puts
on the patch line.

**An instalment paid in 0.3.2.** The last one named in the entry: `design_doc_drift_spec`'s "extracts a non-empty list from each place it reads" floored three of six extractions. \S3's activation JSON, \S5's status-bar block and the strings scanned out of `clientPresentation.ts` had nothing under them, so any of the three could have returned nothing and compared `[] == []`. All six are floored now. The class the entry names is not closed -- it never can be by one edit -- but its own Direction is spent, and what remains of the reachability question belongs to whichever check acquires the next gap.

## Reopened in 0.3.3: the entry was closed on one instalment of ten

The paragraph above ends by saying the class is not closed, and the yaml
over it said `status: fixed` / `released-in: 0.3.2`. Both cannot be true,
and the yaml is the half every check reads — this file's legend says so
in as many words. The heading has been amended and the entry is open
again at 0.4.0.

The 0.3.2 work is not in doubt: the six floors are in
`core/spec/meta/design_doc_drift_spec.rb` and
`056-0.3.2-the-backlog-the-0.3-line-owes.md` records exactly that
instalment. What is wrong is the scope of the closure. It is **one** of
the ten instances enumerated under "The ten instances round 2 and round
3 confirmed, listed", against the 55 confirmed findings this entry's own
note states, and closing on it handed the remainder to "whichever check
acquires the next gap" — which is nothing, because no successor entry
was opened. That is the shape this register's own header forbids and
records `024.90` for.

**Two of the ten are verifiably unchanged**, checked here rather than
inferred:

- `core/spec/meta/release_gate_spec.rb` still proves that a cited script
  is invoked by asking whether its basename appears as a substring
  somewhere under the roots it searches, and its `wired?` answers `true`
  unconditionally for the `ts_test` and `ci_job` kinds. Direction
  mechanism 2 — "Wiring is proved by execution, not by text" — is
  unimplemented, not spent.
- `vscode/scripts/release.sh`'s `set -euo pipefail` is what makes three
  of that script's named refusals refuse rather than log, and nothing
  asserts the line: `core/spec/meta/release_script_guard_spec.rb` does
  not mention it, `core/spec/meta/pinned_mutations.yml` has no entry for
  the file, and a repository-wide search for `pipefail` in tracked `.rb`
  and `.yml` files reaches only `.github/workflows/ci.yml`, which is
  about something else. The entry's body cites line 23 for it; the line
  has since moved, which is the second reason to read the file rather
  than the citation.

Two others are repaired and are not counted as open:
`core/spec/meta/untracked_visibility_spec.rb` now floors its enumeration,
and `core/spec/meta/ci_skip_guard_spec.rb` now reads the two parsed-YAML
keys that decide whether a step runs.

**Reopened rather than replaced by a successor.** The class is what the
number means, and the tree cites it that way — source and spec comments
in both `core/spec/meta` and `scripts` name `024.151` as "the class". A
successor would have to inherit those citations to be worth anything,
which is this entry under a new number. `released-in:` is dropped
because the legend puts it on a resolved entry only; the 0.3.2
instalment is recorded in the paragraph above.

The Direction stands unchanged and is what closes this: not 55 patches,
two mechanisms, and 0.3.2 spent an instalment on the first of them.

## 024.221 A block whose receiver cannot be vouched for contains a `private` that Ruby would let through

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/parser_service.rb` (`#iterates_a_literal?`,
`#visit_block_node`), `core/lib/ovallsp/index/cref.rb` (`#in_block`)

```ruby
class Widget
  SOME_CONST.each { private }
  def helper; end            # recorded public; Ruby may make it private
end
```

`024.111`'s literal-receiver half is fixed in 0.2.15: `[1].each { private }`
reaches the enclosing body, because a literal's `each` provably does not
rebind self. Everything else still gets a cref frame, and for
`included do ... end`, `class_eval`, `concerning ... do` and
`instance_eval` that is **correct** — they really do run their `private`
against a different module, and without the frame every method written
after such a block was recorded private, which silently dropped real
controller actions and made their ivars vanish from the matching views.

What is left is the receiver in between: `SOME_CONST.each { private }` and
`helper { private }`, where the call plainly yields with self unchanged
and containment is therefore wrong. This parser cannot currently tell
that from `included do`.

**This is the residue of `024.111`, split out rather than left inside it,
because the two want different work.** `024.111` names a concrete
reproduction that is fixed and pinned; this names a design question —
telling a nameable receiver from a self-rebinding one needs to know what
the *call* does with the block, which is the shape `024.31` and `024.33`
settled for declarations and never settled for state. A block wants a
receiver, not a boolean.

The failure direction matters and picks the current default. Containing a
`private` that should have escaped makes a method look public that is
private: the engine then answers about a method the user can call from
somewhere, which is over-permissive but not a false report. Letting one
escape that should have been contained marks a whole class private and
**removes** its answers — the 0.2.7 regression. Until the receiver
question is answered, containing is the side to fail on.

Carried in `docs/KNOWN_LIMITATIONS.md` and `.ja.md`, which described this
residue under `024.111`'s number until 0.2.15.

**Re-triaged in 0.2.17** (`024.276`). The residue is a deliberate containment, not a gap in what is known about gems: until the receiver question is answered, letting a `private` escape that should have been contained marks a whole class private and removes its answers, which is the 0.2.7 regression. Answering the receiver question is capability. Not re-driven since the residue was recorded.


**Driven at 0.3.0: it reproduces, and the recorded value is an
assertion rather than a gap.** Ruby:

    $ ruby -e '
    SOME_CONST = [1]
    class Widget
      SOME_CONST.each { private }
      def helper; end
    end
    p Widget.new.respond_to?(:helper)
    p Widget.private_instance_methods(false).include?(:helper)
    '
    # => false
    # => true
    # ruby 3.4.10

The parser records `Widget#helper` with `visibility: :public`. So the
engine believes a call Ruby refuses, which since 0.3.0 also means
completion offers it after a dot -- `024.99` filters RBS's private
members and reads the parser's word for a workspace one.

**Both blanket directions are wrong**, which is why this is still
open and not merely unfinished. Applying the block's `private` to the
enclosing body is right here and wrong for `included do … end`,
`class_eval`, `concerning … do` and `instance_eval`, which really do
run it against a different module -- and `included do` is on most
Rails concerns. Declining, which is what happens now, records
`:public`, and that is a claim.

The shape that fits is a third value -- visibility *unknown* -- and
that is a sentinel every reader of a declaration has to remember, of
the kind `024.243`'s second shape was rejected for in this same
release. Worth its own look rather than a third attempt from the
side.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** `:public` where
Ruby says private is a wrong answer, and since 0.3.0 it is one
completion acts on.

## Not attempted in 0.3.2: a fourth sentinel every reader must remember

The entry's own last section says the shape that fits is a third
visibility value — *unknown* — and that this is a sentinel every
reader of a declaration has to remember, of the kind `024.243`'s
second shape was rejected for. `CLAUDE.md`'s DTSTTCPW section names
that shape directly, with `Environment::UNAVAILABLE` as the standing
example of the cost being paid repeatedly rather than once: a
reviewer found a *new* consumer getting it wrong in 0.2.16, and
`024.224` — whose unbuildable-chain half was fixed in this release —
is a third.

Adding a fourth such sentinel to `visibility`, which every
declaration carries and many readers branch on, is not a patch's
change. Moved to 0.4.0.

## 024.224 A type declared only in `sig/` is reported incompatible with itself — the half 0.3.2 did not fix

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`
(`#compatible_nominal?`, `#ancestor_names` and the comment above them),
and `core/spec/ovallsp/diagnostics/namespaced_argument_type_spec.rb`,
whose `pending` example is the reproduction

Driven over rbs 4.0.3 with its own `sig/` as the signature root — 102
files, 89 hand-written `.rbs`, which is the first hand-written-signature
corpus this project has pointed the engine at — every `argument-type`
report it produces is this:

    <rbs>/lib/rbs/cli.rb:498            `constant` expects RBS::TypeName here, but TypeName is given
    <rbs>/lib/rbs/inline_parser.rb:533  `new` expects RBS::Location here, but Location is given
    <rbs>/lib/rbs/inline_parser.rb:534  `new` expects RBS::Location here, but Location is given

Taken from the interpreter rather than reasoned about:

    $ ruby -e 'require "rbs"; module RBS
      p [TypeName.equal?(RBS::TypeName), Location.equal?(RBS::Location)]
    end'
    # => [true, true]
    # ruby 3.4.10

They are the same class. The expected side arrives from RBS
namespace-qualified; the actual side is inferred from Ruby source written
*inside* `module RBS`, so it arrives bare, and the reachable set
`#ancestor_names` builds carries the `::`-prefixed and last-segment
spellings but not the bare qualified one that `simple_name(expected.name)`
produces.

**Any namespaced project whose parameter types come from RBS and whose
argument types are inferred from Ruby source is exposed**, which is every
project that writes `sig/` the way RBS itself does.

**This is not `024.223`**, though the same corpus produced both.
`024.223`'s fix — a chain that could not be built stops reading as an
absent one — removes all 20 false `unknown-method` reports on that corpus
and leaves these three untouched, measured: `argument-type` is 3 before
and 3 after, with `unresolved-constant` identical at 319 as the control.
The two want separate fixes and the register should not let one close the
other.

**Direction, and the caution on it.** The cheap repair is to have
`#ancestor_names` emit `Index::SymbolId.bare_name(entry)` alongside the
two spellings it already emits; a review pass measured that at 3 to 0.
That is the symptom's fix. Three spellings of a type name float between
the RBS side, the index side and the hierarchy side and each reader
normalises differently, which is the shape `CLAUDE.md`'s same-place rule
says to mechanise — `workspace_index.resolve_type_name` already maps
every spelling to one answer, so comparing through the index rather than
by `include?` over hand-built variants is the fix that removes the class.

Note what that caution is *itself* cautioned by: 0.2.1 moved the
type-name shadowing rule to where the value is produced and had to roll
it back (`024.47`). This belongs at the comparison, not in the converter.

**Also stale, and it is what makes this invisible on reading**: the
comment at `engine.rb:580-600` asserts the expected side arrives bare and
that `simple_name_of` is the form `TypeConverter` gives. Both were true
before 0.2.5 stopped truncating and are false at HEAD.

**Targeted 0.2.16 rather than 0.2.15** because the honest fix is a shared
resolution path with three readers, and 0.2.15 already carries
`024.223`'s change to the same area. Two changes to how a type name is
compared, in one release, reviewed together, is how `024.47` happened.

### Two attempts in 0.2.16, both measured unsound, and why the third is not being written

`CLAUDE.md`'s same-place rule says a hand fix does not get a third go at
one place. This is that point, so what follows is the deliverable and the
code change is not.

**Attempt 1 — the cheap repair this entry's own Direction names.** Emit
`Index::SymbolId.bare_name(entry)` from `#ancestor_names` alongside the
two spellings it already emits. Measured 3 reports to 0 on the rbs
corpus, which is why it looked finished. Declined during 0.2.16 for the
reason the Direction already gave: it adds a fourth spelling to a set of
hand-built spellings, which is the class of defect rather than the fix
for it.

**Attempt 2 — the shared resolution path the Direction actually asks
for.** A `Diagnostics::TypeIdentity.of(name, workspace_index,
signatures)` answering one identity per type name whatever spelling it
arrives in, with `#compatible_nominal?` putting both sides through it and
`#ancestor_names` replaced by an `#ancestor_identities` that asks RBS
about identities rather than raw hierarchy spellings. It refuses through
two rules this repository already owns — `WorkspaceIndex#guessed_type_name?`
and `Index::TypeNameResolution.substitution?` — rather than inventing a
resolution rule, and it deletes `#simple_name_of`. On paper this is the
right shape. A reviewer drove it and found two things the author's own
measurement could not have seen:

- **It buys a false negative wider than the false positive it removes.**
  The expected side is a name RBS produced — absolute and unambiguous by
  construction — and putting it through `guessed_type_name?` makes it
  guessed as soon as the workspace declares one class sharing its last
  segment. Reproduced on a clone, with and without the patch, `sig/`
  declaring `Zoo::Barn#feed: (Zoo::Animal) -> void`:

      # workspace as the patch's own control example writes it,
      # with no Ruby class named Animal anywhere
      base    ["`feed` expects Zoo::Animal here, but Animal is given"]
      patched ["`feed` expects Zoo::Animal here, but Farm::Animal is given"]

      # the same fixture, plus the ordinary `module Farm; class Animal; end; end`
      base    ["`feed` expects Zoo::Animal here, but Farm::Animal is given"]
      patched []          <- the true mismatch, silenced

  The patch's headline control — "it still reports a same-named class
  from another namespace" — holds only because its fixture declares no
  Ruby class named `Animal` at all. Add the class the source is written
  against and the fix loses exactly the report it was designed to keep.

- **It reintroduces `024.223`'s conflation at a consumer it adds
  itself.** Half two calls `declared_by_signatures?`, which is
  `!signatures.ancestors(...).empty?` — and `Environment::UNAVAILABLE` is
  a frozen `[]`, so a chain that could not be built reads as "not
  declared". Probed with this entry's own fixture, adding one
  `include _Serializable` to `class Key` brings the original report back
  unchanged. The two halves' fixtures each avoid the other's condition.

Four behavioural decisions in that patch were also unpinned — reverse-applied
one at a time with the whole core suite green — including the very decision
the report credits with the fix.

**The root cause, stated plainly.** Three spellings of a type name float
between the RBS side, the index side and the hierarchy side, and each
reader normalises differently. That much this entry already said. What
the two attempts add is *why a fix at the comparison keeps failing*: the
comparison is being asked to recover an identity that was **already lost
upstream**, and every recovery rule strong enough to reunite the two
spellings is also strong enough to unite two genuinely different classes.
`guessed_type_name?` and `substitution?` are refusals designed for a
*receiver*, where declining costs a missed report; on an *argument's
expected type* the same refusal costs a wrong silence, and neither rule
was written for that side.

**The direction actually needed.** The expected type must not arrive as a
name to be re-resolved at all. `Signatures::TypeConverter` knows the
absolute `RBS::TypeName` at the moment it builds the `Types::Nominal`,
and that identity is exact; it is thrown away and a String is compared
downstream. Carrying it — a nominal that remembers what resolved it —
removes the comparison's job rather than improving it, and no refusal
rule is needed on the expected side because there is nothing left to
guess. That is a change to a type every component reads, which is a
release's worth of blast radius on this project's own evidence
(`0.2.5`'s one-line converter change), and it is why this is re-scoped
rather than attempted a third time.

**Re-scoped to 0.3.0**, where `024.R7`'s work already opens the
signature and index sides together. Until then the entry stays open and
`KNOWN_LIMITATIONS` keeps its paragraph in both languages: the product
does have this defect, and 0.2.16 shipped without fixing it.


**Re-driven at 0.3.0 over rbs 4.0.3 with its own `sig/`, and it has
grown from three to seven.** 102 files, control `unresolved-constant`
at 326:

    lib/rbs/cli.rb:498               `constant` expects RBS::TypeName here, but TypeName is given
    lib/rbs/inline_parser.rb:533     `new` expects RBS::Location here, but Location is given
    lib/rbs/inline_parser.rb:534     `new` expects RBS::Location here, but Location is given
    lib/rbs/prototype/runtime.rb:525 `generate_mixin` expects RBS::TypeName here, but TypeName is given
    lib/rbs/prototype/runtime.rb:528 `generate_methods` expects RBS::TypeName here, but TypeName is given
    lib/rbs/prototype/runtime.rb:565 `generate_mixin` expects RBS::TypeName here, but TypeName is given
    lib/rbs/prototype/runtime.rb:567 `generate_methods` expects RBS::TypeName here, but TypeName is given

**Every `argument-type` report this corpus produces is this entry.**
The check's whole output on a hand-written-signature corpus is false.

**And there is a direction that is not spelling normalisation.**
`CLAUDE.md` records why normalising the two spellings cannot work --
every rule strong enough to reunite `TypeName` and `RBS::TypeName`
also unites two different classes. But the *actual* side is inferred
from Ruby source whose lexical nesting the parser already records on
the candidate: a bare `TypeName` written inside `module RBS` resolves
to `RBS::TypeName` the way Ruby resolves it, not by guessing at the
string. That is a different mechanism from the one the register
rejects, and it is the one worth measuring next -- 7 to 0, with
`unresolved-constant` at 326 as the control.

**Attempted in 0.3.0 and abandoned before a change, with one fact
gained.** The lexical-nesting direction sketched above is not the one:
two fixtures were built for it -- a bare name written inside its own
`module`, then the same across two files, which is rbs's own shape --
and **neither reproduces**. Both were deleted rather than kept, because
a passing example that does not reproduce the defect is worse than no
example: it reads as coverage.

What the fixtures ruled out is that this is Ruby-side constant
resolution. rbs writes the expected side **bare** in its own signature:

    sig/resolver/constant_resolver.rbs:29
      def constant: (TypeName constant_name) -> Constant?

and it arrives at the check as `RBS::TypeName`. So the absolutisation
RBS performs is reaching one side and not the other, and both sides
are RBS's -- not, as this entry says, an actual side "inferred from
Ruby source written inside `module RBS`".

That puts the root exactly where `CLAUDE.md` already puts it, in the
DTSTTCPW section: `Signatures::TypeConverter` holds an absolute
`RBS::TypeName` at the moment it builds the `Types::Nominal` and
flattens it to a String, after which three readers normalise spellings
to get the identity back. The direction is to keep the identity, which
is a change to what a `Nominal` carries and to its readers -- not a
hunk a review round can add.

**Retargeted to 0.3.2 in 0.3.0's closing sweep.** Seven reports and
all of them false, on the only hand-written-signature corpus this
engine has been pointed at.

## Fixed in 0.3.2, and the cause was neither of the two this entry chased

Two attempts were declined for being spelling normalisation, and the
direction recorded here was to carry `RBS::TypeName`'s identity through
`Types::Nominal` — a change to a type every component reads. Driven at
0.3.2, **the spelling is a symptom of a swallowed failure**, and the
fix is one guard in the reader that swallows it.

`Signatures::Environment#ancestors` answers `UNAVAILABLE` — a frozen
`[]` — when RBS declares a type whose ancestry it cannot build
(`024.223`). `Engine#ancestor_names` added whatever came back to the
reachable set, so an unavailable chain was indistinguishable there from
a type with no ancestors, and `#compatible_nominal?` then asserted a
mismatch from a question it could not ask. That is the exact shape
`CLAUDE.md`'s swallowed-failure rule forbids, one layer below the layer
that knows what to do with it — and the register had already noticed it
*in a proposed patch* while missing that it was at HEAD.

Why rbs's own signatures trip it, taken from the run rather than
reasoned about:

    failed to build ancestors of ::RBS::TypeName:
      sig/typename.rbs:52:4...52:19: Could not find mixin: _ToJson

`sig/typename.rbs` includes an interface rbs does not load for itself.
With the chain unavailable, `via_signatures` contributes nothing and the
set comes out as every spelling of the class except the bare-qualified
one the expected side is compared as:

    actual="TypeName"  expected="RBS::TypeName"
    reachable=["TypeName", "::RBS::TypeName", "Object", "Kernel",
               "BasicObject"]

**Measured, rbs 4.2.0 with its own `sig/` as the signature root**, 109
files, corpus-sha256 identical on both sides:

    argument-type          6  ->  0        (all six were this entry)
    unresolved-constant  369  ->  369      (control)

0 introduced. Two further corpora, each run against a `git worktree` of
HEAD so the two sides differ only in this change:

    language_server-protocol-3.17.0.6, its own sig/, 375 files
      byte-identical, both sides

    activesupport + activerecord + activemodel 8.1.3.1, 759 files,
    stdlib signatures
      unresolved-constant  1788 = 1788
      unknown-method         97 =   97
      byte-identical, both sides

`#ancestor_names` has exactly one caller, `#compatible_nominal?`, so
`argument-type` is the whole blast radius by construction — and the two
runs above are what says so from outside the code rather than from
reading it.

**The deciding control is in the spec, not in prose.** One fixture, two
signature files one `include _Missing` apart: with the chain
unbuildable the call is reported, with it buildable the same call is
silent. That is what makes the chain rather than the spelling the
cause, and an earlier fixture that lacked it passed at HEAD for a
reason unrelated to the defect.

**What it costs, pinned as an assertion rather than written as a
sentence.** A *genuine* mismatch whose argument's own chain is
unavailable is now declined too. The reachable set is a lower bound and
a chain that could not be built may well have had the expected type in
it, so this is section 0's preferred direction — a missed report rather
than a wrong one — and
`spec/ovallsp/diagnostics/unbuildable_signature_chain_spec.rb` asserts
it so the price cannot quietly change.

**What is left, and it is a different entry.** The actual side still
arrives under-qualified: a bare `TypeName` written inside a module
nested deeper than the class is recorded as written, and only the
hierarchy index recovers it. Nothing in this fix touches that, and the
fixture that reproduces it is `024.19`'s. The half this entry was
titled for — *a namespaced type reported incompatible with itself* — no
longer happens on the corpus that produced it.

## Reopened in 0.3.3: the entry was closed on one half, and the other one is its own reproduction

The section above is sound about what it changed, and the qualifier in
its last sentence is doing all the work: *on the corpus that produced
it*. Off that corpus the titled symptom still happens, and where it
happens is this repository's own reproduction.

`core/spec/ovallsp/diagnostics/namespaced_argument_type_spec.rb` holds
it, `pending`, and run at 0.3.3 the pending example still fails with

    `fetch` expects App::Key here, but Key is given

which is a namespaced type reported incompatible with itself — the
symptom the heading named. The three controls in the same file pass, so
this is not an engine that has stopped checking argument types.

**Why 0.3.2's fix does not reach it.** That fix declines when
`Signatures::Environment#ancestors` answers `UNAVAILABLE`: RBS declaring
a type whose ancestry it cannot *build*, which is what rbs's own
`sig/typename.rbs` does by including an interface rbs does not load for
itself. Nothing in this fixture is unbuildable. `App::Key` is declared in
`sig/` with no includes and there is **no Ruby class of that name** for
the hierarchy index to resolve the receiver through, so the actual side
arrives bare, the reachable set is that bare spelling and nothing else,
the expected side is `App::Key`, and the comparison misses.
`Environment.unavailable?` tells the sentinel apart by identity, so an
empty chain for a name RBS never declared is not unavailable and the new
guard does not fire. Two different causes, one symptom; 0.3.2 fixed one.

**The remaining half, stated so it cannot be closed on part of itself
again:** a type declared in `sig/` alone, with no Ruby class of that name
in the workspace, is reported incompatible with itself when the source
writes it bare under the namespace it is declared in. The spec's own
comment records that this shape was found by probe and that adding
`class Key` in Ruby hides it — so a fixture that declares the class in
both places cannot be used to check this closed.

The two attempts recorded above stand as measured-unsound, and the
direction the 0.3.2 section reaches — the identity thrown away upstream
in `Signatures::TypeConverter` — is the one this half needs, more
plainly than the other half did: there is nothing in the workspace for
any downstream reader to recover the identity *from*.

**And this closure is the failure the register keeps recording.**
`024.151`, reopened in the same pass, was closed on one instalment of
ten while its own last sentence said the class was not closed. This
entry was closed on one of two causes while its own last section said
what remained. `docs/ISSUES.md` puts "does it reproduce?" first for
moving an issue *into* the register, on the strength of `024.130`;
nothing said the same about moving one out, and both closures were made
without running the reproduction the entry already had. In this case the
reproduction is a `pending` example in the suite, which reports as
pending rather than as a failure — so nothing was going to raise a hand.

*The Area's line numbers were dropped in the same pass.* They named
positions in `engine.rb` that had drifted, and an Area is a live pointer
rather than history.

## 024.237 Four shapes stopped reporting by declining on the body, not by reading it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing false is published for these four shapes any more, so there is
  no limitation to state. It stays open because a genuine typo in the
  same body is unreported too, which is a missed report rather than a
  wrong one -- the direction section 0 prefers, and still a gap.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

The four shapes `024.91`'s table marks silent-with-a-silent-control:
`Const = Struct.new(...)` reopened as a class body, the same for
`Data.define`, `define_method`/`attr_reader` inside `Class.new do … end`,
and a literal `define_method` inside a loop block.

Measured with the control in the same fixture:

    Seed = Struct.new(:seed, :used)
    class Seed
      def describe = "#{seed}/#{used}"          # was reported; silent now
      def typo_control = definitely_not_a_member # silent too
    end

So the check answers nothing about those bodies rather than answering
correctly about them. Reading them properly means knowing what
`Struct.new` and `define_method` produce, which is the enumeration
question again, and `024.R7` is the release that takes it on.


**The syntactic half is taken in 0.3.0; the enumeration half is not.**

`Struct.new(:seed, :used)` and `Data.define(:x, :y)` name their members
in the call, and the parser now records them -- readers and writers for
`Struct`, readers only for `Data`, symbol arguments only so
`keyword_init:` and the String in `Struct.new("Named", :c)` are not
mistaken for members. Before this, `Seed.new.` offered 51 items and not
`seed`, and hover and definition had nothing to answer.

**The surface stays open, deliberately**, so the check is no louder
than it was: corpus **0 introduced, 0 removed**, control at 916.
`024.110`'s rule is that a generated enumeration cannot carry its own
completeness, and naming the class without opening it is what produced
``HeredocData has no method named `common_whitespace=` `` over real gem
source.

So what is left of this entry is the part its own last paragraph names:
reading `define_method` inside `Class.new do … end` and a literal
`define_method` in a loop, which is the enumeration question, and
`024.290` now records that `024.R7` as shipped does not answer it.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** The syntactic half
shipped in 0.3.0; what remains is reading `define_method` inside a
class-creating block, which is the enumeration question.
## 024.243 Signature help says nothing for a receiverless call inside a module body

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/method_resolver.rb`
(`#lookup_owners`), `core/lib/ovallsp/semantic/hierarchy_index.rb`
(`#instance_ancestors_locked`)

**Split out of `024.43`**, whose class-body half is fixed in 0.2.16.
Inside a module's *instance* method — a concern, a helper module, an
`ActiveSupport::Concern` — a receiverless `puts(` still answers
nothing, because the chain the fix walks never reaches `Kernel` there.

Driven against `core/lib` at this revision, in a fixture declaring a
`module Helpers` with an instance method and a singleton one, beside a
`class Report`:

```
lookup_owners(Nominal("Helpers"), singleton: false)
# => [["::Helpers", false]]
lookup_owners(Nominal("Helpers"), singleton: true)
# => [["::Helpers", true], ["Module", false], ["Object", false],
#     ["Kernel", false], ["BasicObject", false]]
lookup_owners(Nominal("Report"), singleton: false)
# => [["::Report", false], ["Object", false], ["Kernel", false],
#     ["BasicObject", false]]

signatures_of(Nominal("Helpers"), "puts")  # => []
signatures_of(Nominal("Report"), "puts")   # => ["puts(...) -> nil"]
members_of(Nominal("Helpers"), prefix: "put").map(&:name)  # => []
scope_at(inside `module Helpers; def render`).self_type
# => Nominal("Helpers")
```

`HierarchyIndex#instance_ancestors_locked` appends the synthesised
Object/Kernel/BasicObject tail only when the canonical name is a
*class*. `024.43`'s band 3 can only ask what the chain yields, so a
module's instance side has nothing to ask. `def self.` inside a module
is fine, because the singleton walk goes through `Module`.

**What the probe above does not say, and a review round had to drive the
product to find: completion is not silent here.** Through a real server,
`put` inside `module Helpers; def render` offers `puts` and `putc`:

```
COMPLETION: ["putc", "puts"]
SIGHELP:    {signatures: []}
```

`PrefixCompletion#kernel_methods` asks `Kernel` unconditionally instead
of walking the enclosing scope's chain, so it never reaches the gap the
`members_of` line above shows. The published limitation this entry was
split into said "completion is silent here for the same reason, so the
two features agree" — in both languages — and that is the opposite of
what the product does. **The asymmetry `024.43` is about is still exactly
true in a module body.** Corrected in both languages, and worth keeping
as the reason the correction was needed: an internal probe is not a
drive, and a conclusion about what a user sees has to come from the
server.

**Ruby's own answer, which is what says where the fix belongs:**

```
$ ruby -e '
    module Helpers
      def render = puts("reached Kernel#puts")
    end
    class C; include Helpers; end
    p Helpers.ancestors
    p Helpers.private_instance_methods(false)
    C.new.render
    p C.ancestors.include?(Kernel)'
[Helpers]
[]
reached Kernel#puts
true
# ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [arm64-darwin25]
```

So the chain the engine models is not wrong: a module's `ancestors`
really is just itself, and `Kernel` really is not on it. The call
works because an instance method runs with the *including* object as
`self`, and `Kernel` is on that object's chain. The fix is therefore
not "append the Object tail to modules too" — that would also answer
`Helpers.new` and every other `Object` instance method for a module
value, and `024.229` records what happens when a fallback is aimed at
the wrong mechanism. It is that a receiverless call written inside a
module's instance method reaches `Kernel` whatever the module itself
inherits, which is a different question from "what does this module
inherit" and wants asking somewhere else.

**Not the asymmetry `024.43` described.** That entry's user-facing
paragraph said completion offers the method signature help refuses;
here completion is silent too — it reads the same chain — so the
limitation is a plain absence rather than two features disagreeing.
The paragraph in `KNOWN_LIMITATIONS` was rewritten to that, in both
languages, rather than deleted with `024.43`.

**Retargeted to 0.3.0 in 0.2.16's closing pass**, as the half of
`024.43` that release did not fix.


**Four shapes tried in 0.3.0, all measured, none shipped.** The finding
reproduces exactly as written — `lookup_owners(Nominal("Helpers"),
singleton: false)` stops at `["::Helpers", false]` while `Report`
reaches `Kernel`, and `members_of(Helpers, prefix: "put")` is empty
where `Report`'s is `["putc", "puts"]`. What is not available is a fix
that does not cost more than it buys.

Every number below is `scripts/corpus_diagnostics.rb` over
activesupport 8.1.3.1 and i18n 1.15.2 — **335 files**, the same
`--rails-root` on both sides, control `unresolved-constant` identical
at **916** throughout, baseline **19** `unknown-method`:

1. **Append `DEFAULT_OBJECT_CHAIN` to a module's instance chain.**
   Suite green. Corpus: **+151 reports, −0**, every one false —
   `ActiveSupport::Benchmarkable has no method named `logger``. The
   chain makes the module *closed*, and a concern's methods come from
   its includer, which is the one thing the check cannot enumerate.
2. **Chain, plus the includer recorded as a nameless ancestor.**
   Corpus: **−4, +0**, the best result of the four. Rejected on a
   different cost: a nameless entry is a value every reader of the
   chain has to remember to skip, and **five specs that map `#name`
   over ancestors raised on it**. That is the sentinel shape
   `CLAUDE.md` names, and paying it here buys one entry.
3. **Chain for the receiver only, plus `Engine#closed_nominal?`
   asking `WorkspaceIndex#type_kind`.** The guard never fired:
   `nominal.name` is not the spelling the index is keyed by, and
   `ActiveSupport::XmlMini` answered `nil`. Corpus **+3, −0**.
4. **The same, asking a new `HierarchyIndex#module?` that
   canonicalises first.** Suite green, 612 examples. Corpus **+3, −0**
   — the same three, all module receivers reached through `extend
   self`, so they arrive on the *singleton* side that shapes 3 and 4
   deliberately leave alone.

**Rolled back**, per `CLAUDE.md`'s rule about the same place found
again after a countermeasure. Shape 1 also cost a lesson worth keeping
separately: the suite was green while the product got 151 reports
worse, and only the corpus saw it.

**The direction actually needed** is shape 2 with its readers fixed —
the chain is the right place for "Object is reachable" and a nameless
link is the right way to say "and the surface is not enumerable" — or
a receiver-side answer that also covers `extend self`, whose calls
arrive singleton-side. Either is a change to how ancestors are read
rather than a hunk in a review round, so this stays open and moves off
0.3.0.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Four shapes
measured in 0.3.0 and none shippable. The direction needs a change to
how ancestors are read, and it ends in members a module did not offer
before.
## 024.289 A class that includes an unread module is not checked at class level, so a typo there is silent

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`closed_nominal?`)

The cost of `024.35`'s rule, and the entry that carries it now that
`024.35` is closed.

`include SomeGem::Model` makes a class's class-level surface unbounded —
whatever that Concern's `class_methods do` block installs is real and
invisible from a workspace that has not read the gem. So the check
declines about that class entirely:

```
  Configish.validate(:ensure_ok)          []   <- right: the module may add it
  Configish.definitely_not_a_member       []   <- the cost: a real typo, silent
```

`024.35` predicted this in as many words — "it will silence genuine
class-level reports on every class that includes anything unread, which
is most of a Rails app before the Agent is ready" — and measured, that
is what happens.

**Friction rather than a defect**, and the distinction is section 0's:
this is the engine declining, not asserting. A decline ranks above a
wrong answer, and the alternative — judging such a class closed — is the
defect `024.35` was.

**It resolves when the gems are indexed** (`024.R7`), which is what makes
the surface knowable rather than unbounded. Until then there is nothing
to fix here that would not be `024.35` again, which is why it travels
with that work rather than standing on its own.

Asserted rather than described: `unread_include_spec.rb`'s "also says
nothing about a genuine typo there, which is what the rule costs" fails
if the decline ever narrows by accident.


**See `024.290`** for the measurement that `024.R7`, as shipped in
0.3.0, carries no core classes at all -- which is the direction this
entry names.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** Checking a class
that includes an unread module means enumerating what the module
installs -- the same scope change `024.290` records.
## 024.290 Nothing is reported about a call whose receiver is `Object`

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb` (`closed_nominal?`)

The cost of `024.230`'s decline, and the entry that carries it now that
`024.230` is closed.

**`Object`'s member set is whatever the process has loaded.** Every gem,
every core extension and RubyGems itself adds to it at run time, and the
bundled signatures declare a fraction. So the undefined-method check
never judges an `Object` receiver closed — which includes every bare
call written at the top level of a file.

What that costs is a genuine typo written there, which is silent.

**Measured in the other direction**, which is why the decline exists: over
997 files of activesupport, activerecord, actionpack and railties,
judging `Object` enumerable produced **25 reports and removed none** —
nine `gem`, four top-level `include`, seven JRuby-only names — every one
false. `024.239` met the same fact from the other side and had to
hard-code three names Ruby gives every object that RBS omits; a list
like that can only ever be partial.

**Friction rather than a defect**, on section 0's distinction: this is
the engine declining, not asserting.

**It resolves the way `024.129` does** — by knowing what is actually on
`Object` in this project, which is `024.R7`'s question. Until then there
is nothing to narrow here that would not be the 25 reports again.

Asserted rather than described: `object_receiver_decline_spec.rb`'s
"also says nothing about a genuine typo at the top level, which is what
it costs".


**`024.R7` shipped in 0.3.0 and does not answer this entry's question.**
That is worth stating plainly, because this entry and `024.129` and
`024.289` all say they resolve once the engine knows what is really on
the receiver, and name `024.R7` as where that knowledge comes from.

Measured against the release's own Rails fixture, agent booted, index
built:

    gem-index size: 2078
      Object   instanceMethods=0
      Kernel   instanceMethods=0
      String   instanceMethods=0
      Array    instanceMethods=0
      Integer  instanceMethods=0

The reason is in `RuntimeAgent::Agent#gem_index_result`, which walks
every named module and then `gem_for(mod, name) or next`: a module is
reported only when `Object.const_source_location` puts it under
`…/gems/<name>-<version>/`. A core class is not there, so it is skipped
before anything is asked of it. The index is 2,078 gem classes and no
core ones.

So the direction these three share needs the Agent to report the core
classes as well -- a scope change to `024.R7`'s walk, not a change to
the check that reads it. Whether that is affordable is its own
question: `Object`'s own list is large, it is what `024.230`'s 25 false
reports and 0.3.0's own 151 were both about, and the walk currently
earns its cheapness from that filter.

**Retargeted to 0.4.0 in 0.3.0's closing sweep.** An `Object`
receiver becoming judgeable is the largest of the enumeration
answers, and `024.R7` as shipped does not carry it.
## 024.294 A template's `@ivar` receiver is not checked, and its type is one action's

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/receiver_resolution.rb`,
`core/lib/ovallsp/views/controller_ivars.rb`

**Rewritten in 0.3.1 after being driven; half of what it said was
false.** It claimed the undefined-method check does not act on an
`@ivar` receiver anywhere, "even where hover and completion know its
type", and that 0.3.0 widened the gap. In a plain Ruby file 0.3.0's
`H8` closed it: `@article.no_such_method_zz` is reported, in the
same-method and the sibling-method shapes alike, with the control that
deleting only that line removes exactly one finding. The entry was
split off from `024.86` and never re-driven — `024.130`'s shape, a
limitation published that the product does not have, in both
languages. `core/spec/ovallsp/diagnostics/view_ivar_receiver_spec.rb`
now holds both halves.

What remains is the template. `Views::ControllerIvars#ivars_for_view`
computes the type and `Server#view_initial_env` hands it to hover,
completion, explainType and go-to-definition; the two diagnostics call
sites build their context with `assigned_ivars:` — a *name* set — and
`Diagnostics::SemanticContext` has no field for ivar types, so
`ReceiverResolution.receiver_type_for` calls `infer_at` with no
`initial_env:` and the receiver is `Unknown`.

**Wiring it as it stands would be wrong, and that is the whole
difficulty.** `#contributing_actions` reads only the view's own
controller, so for a template a second controller renders it answers
one action's type as if it were the receiver's class. Driven: seeding
it produces `Post has no method named ...` on a template
`WidgetsController#index` renders with a `Comment`, and `Comment` has
that method. Over 43 ERB views in two real applications the seed added
**zero** reports, so what it buys is not measured either.

**This is not an upper bound; it is an unenumerated union.** A second
render from the *same* controller already yields `Comment | Post` —
the difference is enumeration, not variance — so the shape is
completable rather than irreducible, and `024.18` owns the index that
would complete it. Turning this decline into an answer is what `045`
calls capability, which is why the target moved off the patch line.

## 024.295 The gem index is fetched on every boot and persisted nowhere

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb`, `core/lib/ovallsp/cache/`

`024.R7` shipped the index without the fourth of the four things its
Direction names: persistence. The walk is asked once per Core start
and thrown away at exit, so the gem-backed undefined-method check is
off for the first seconds of every session.

**Re-measured in 0.3.1, and both of the numbers this entry carried
were wrong.** The payload is **1,815 KB**, not 938 KB — the smaller
figure was taken before `singletonAncestors` and the visibility split
were added to `#module_answer`, confirmed against the commit that
wrote it. The walk itself is 17–26 ms; the wait a user meets is the
Agent's boot, not the walk.

**The per-gem-version key this entry asked for cannot work.** The
Agent attributes a module by `Object.const_source_location`, i.e. by
*definition site*, and Rails defines `<Model>::GeneratedAssociationMethods`
and `::GeneratedRelationMethods` inside activerecord's own source — so
`activerecord-8.1.3.1`'s slice contains entries that are a function of
the user's `app/models/*.rb`. Driven twice, with `Gemfile.lock`
byte-identical: adding one model grew that gem's slice, and adding one
scope put `zzz_only_posts_have_this` under it. 19 of 2,097 entries
have a root constant outside every gem. The whole-index alternative
fails the same way, because `Cache::Key.workspace_digest` has no term
that moves when `app/models/*.rb` changes.

The payload is also a function of load state — 1,941 entries after
boot, 2,097 after `eager_load!` — and the surviving copy of a
duplicated name differs across processes, so what would be frozen to
disk is not stable either. `024.R7`'s own Direction already said the
index "describes *a* boot, not the gem in the abstract"; the fourth
bullet contradicted it, and the bullet is what changed.

**What must land before anything is written to disk:** `024.305`, the
duplicate-name collapse, because persistence would freeze it.

0.3.1 fixed the half of this that was making *wrong* answers rather
than late ones: the index is now dropped when the Agent restarts.

## Where this stands after 0.3.2

`024.305` — the duplicate-name collapse this entry named as what must
land first — is fixed, so the blocker is gone. The key problem is
not: attribution is by definition site, so a model's generated
modules are filed under activerecord and change when `app/models`
does, and `Cache::Key.workspace_digest` has no term that moves when
they do. Neither the per-gem key nor a whole-index one can see that.

What is left is therefore a design question — what identity a
persisted index is keyed by — rather than plumbing. Moved to 0.4.0.
The half that was making *wrong* answers rather than late ones was
fixed in 0.3.1, as the section above already says; 0.3.2 did not
touch it.

*Corrected in 0.3.3.* The sentence immediately above read "0.3.2 fixed
the half of this ... in 0.3.1", naming two shipped releases for one
fix. It was written in 0.3.2 as a copy of the 0.3.1 sentence in the
section above with its subject overwritten and the original trailing
clause left standing. The attribution to 0.3.1 is the correct one, and
`docs/design/tasks/055-0.3.1-what-a-restart-forgets.md` and
`core/spec/ovallsp/server_gem_index_retry_spec.rb` are where it is
recorded and pinned.

## 024.297 Call hierarchy lists no callee reached through `send`, `super` or a macro

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`outgoing_calls_result`)

`outgoing_calls_result` resolves `:method_call` candidates, and
`send(:helper)`, `public_send`, `super`, a `&:sym` block-pass and the
Rails macros that name a method (`before_action`, `delegate`) are not
recorded as one. So a method whose only callees are written that way
answers **no outgoing calls**, which the panel renders identically to
a method that really has none.

The gap is the rendering, not the resolution: "nothing" is read as a
claim. `send(:x)` with a literal symbol is the half the parser can
name exactly and is the cheapest place to start.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped by that review because every one of the four forms needs its
own producer -- a reference candidate for `send(:x)`, for `super`, for
`&:sym`, for the macros -- and four producers is not a review-round
hunk.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.298 An inlay hint on `Foo.new(...)` names `new`'s parameters, not `initialize`'s

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`parameter_name_hints`)

The callee resolved for `Foo.new(1, 2)` is `Class#new`, whose RBS
signature takes `*args`, so the labels come from the wrong
declaration. What a reader wants is `initialize`'s parameter names,
which is where the arguments actually land.

Distinct from the splat and operator refusals 0.3.0 already makes:
those decline where the mapping does not hold, and this one labels
confidently from a declaration that is not the one being called.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because the severe half of the finding it came from -- labels
landing on the wrong line -- was fixed and pinned in the same pass, and
this half needs the resolver to answer `initialize` where the call
names `new`.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.299 Completion on a relation offers none of the model's own scopes or class methods

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/query_service.rb` (`receiver_members`)

`Post.where(x: 1).order(:id).` answers `ActiveRecord::Relation`'s
members and none of `Post`'s own — a `scope :published`, an `enum`'s
generated predicates, a `def self.` on the model. Rails delegates all
of those to the model, so they are callable there and the list says
they are not.

`#receiver_members` maps a `Generic` to a bare `Nominal` and drops the
`[Post]` parameter, so nothing downstream can reach the model. The
registry already holds the singleton methods the Agent reports; what
is missing is the identity to look them up by.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because the fix reaches across two layers: `#receiver_members`
would have to consult the model registry, which is a change to what a
member lookup is allowed to ask.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.300 `@ivar` completion offers nothing from a superclass or an included concern

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`sibling_ivar_env`)

The class-wide walk reads the class's own body. An `@current_user`
assigned by `ApplicationController` and read in a subclass, or one a
concern's `included do` assigns, is not offered — which in a Rails
application is most of them.

C15's row promises "the instance variables the class assigns
anywhere", and by that wording this is outside it rather than a
broken promise. It is recorded because the distinction is invisible
to a reader typing `@`.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because seeding from the ancestor chain's class bodies changes
which names the list holds for every class, and the release had no
measurement budget left to drive that.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.301 The route-helper quick fix ignores the `_path`/`_url` split and the helper's arity

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`route_helper_action`)

The replacement is chosen by edit distance over every helper name, so
`user_pathh` can be offered `user_url` — a different thing, an
absolute URL rather than a path — and a helper needing an argument
can replace one written with none, which raises at run time.

The distance ceiling stops a nonsense suggestion; it does not stop a
plausible wrong one. Both halves want the call's own candidate, which
`route_helper_action` is not given.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because both halves want the call's own candidate, and
`route_helper_action` is handed only the document, the uri and the
diagnostic.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.302 The `def` quick fix is offered for one receiver shape of three

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/server.rb` (`define_method_action`)

The unknown-method check reports on an instance receiver, a constant
receiver (`Foo.bar`) and a receiverless call. Only the first is
offered a `def`. The other two see a diagnostic with no fix, which
reads as the fix having failed rather than never having been offered.

Wiring the constant case in without also reading `candidate.singleton`
turns a missing fix into a wrong one — it would insert an instance
method for a call that needs `def self.`.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped on the finding's own argument that wiring the constant case in
without reading `candidate.singleton` turns a missing fix into a wrong
one.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.303 A multiple assignment's targets get no inlay hint

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/local_inferencer.rb` (`locate`, `eval_type`)

`a, b = 1, "x"` labels neither target. The inferencer has no case for
`Prism::MultiWriteNode`, so the walk does not descend into the
targets and each stays unknown.

Worse than a blank where a type would go: because the multi-write
never rebinds, an earlier binding of the same name survives, and a
hint from *that* assignment can be shown against the new one.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because it needs a `Prism::MultiWriteNode` case pairing each
target with its right-hand element, which is a new inference rather
than a guard.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

## 024.304 The gem-backed check is silenced by any class-body call the parser cannot read

```yaml
status: open
kind: friction
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/workspace_index.rb` (`open_surface?`)

A class body carrying a macro this parser does not model has its
surface marked open, and the undefined-method check then declines
about that class entirely. In a Rails application that is nearly
every controller — `before_action`, `helper_method`, `rescue_from` —
so 0.3.0's gem-backed check reaches far fewer classes than the
capability row suggests.

The decline itself is right: a macro may install anything. What is
not recorded anywhere is how much of a real application it covers.

Found by 0.3.0's four-stage review workflow and judged in scope.
Skipped because the decline is correct and what is missing is a
measurement of how much of a real application it costs -- a corpus
question, not a code change.
Recorded per `CLAUDE.md`'s rule that a release ships with its open
findings written down.

*Area corrected in 0.3.3.* It named a file under `core/lib/ovallsp/index/`
that has never existed on any branch; `open_surface?` is in
`core/lib/ovallsp/workspace_index.rb`, and the declining caller is
`core/lib/ovallsp/semantic/method_resolver.rb`. This was the register's
only Area path pointing at nothing, and it sat where the guard written
for exactly that — `deferred_findings_spec`'s "names only paths that
exist, in every open entry's Area" — cannot look: that example takes its
entries from `DeferredFindings.open_defects`, which filters
`kind == "defect"`, and this entry is `kind: friction`. The guard passes
green with the path broken. Reported to whoever owns that spec rather
than fixed here.

## 024.318 A workspace directory shaped like a gem path would be attributed to a gem

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >-
  The misattribution is driven; its consequence is not. Confirming
  that a monorepo's own class is then treated as closed needs a
  monorepo workspace with a booted Agent, which is why this is filed
  at the shape rather than at the report it would produce.
target: 0.4.0
```

**Area:** `core/lib/ovallsp/runtime_agent/agent.rb`, `GEM_PATH`

`%r{/gems/(?<gem>[^/]+-[0-9][^/]*)/}` matches anywhere in the path
`const_source_location` returns. A repository keeping local engines
under `gems/billing-1.0/` would have its own classes filed under a
"gem", and a gem-index entry makes a receiver closed — so the check
would report the workspace's own methods as missing.

## 024.319 A bare name no signature declares is still read as the one gem class sharing its last segment

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** `core/lib/ovallsp/semantic/hierarchy_index.rb`
(`#canonical_name`), `core/lib/ovallsp/semantic/gem_index.rb`
(`#resolve_simple_name`)

0.3.0 stopped a gem's nested class from claiming a **core** name by
asking the signature environment whether the bare name already denotes
something. That leaves the rule intact wherever RBS has never heard of
the name — which is where it was wanted (`Relation` reaching
`ActiveRecord::Relation`) and also where it can still be wrong. A class
the user wrote that the workspace index does not hold is
indistinguishable, at that moment, from a name nothing claims.

What has not been established is whether that moment is reachable: it
needs the index to be missing a workspace class while the question is
asked. Until it is driven, the shape is recorded and the rule is not
narrowed further — every recovery rule strong enough to reunite two
spellings of one class also unites two different classes, and 0.2.1
lost a release to the version of this that was too strong.

## 024.320 No check knows which lock guards what

```yaml
status: open
kind: friction
user-visible: no
user-visible-note: >-
  Internal. It is filed because the thing it would guard -- which
  mutex covers which state, and in what order they may be taken -- is
  stated in one document and enforced by nobody, and a wrong answer
  there is a data race rather than a stale sentence.
target: 0.4.0
```

**Area:** `docs/design/docs/02-architecture.md`'s threading section,
every `Mutex.new` in `core/lib`

The last of the three rows in `docs/DOCUMENTATION_MAP.md` that could
be mechanised and is not. `024.317` closed three of six; the other two
ask for a judgement no scanner can make -- whether a revert left
documentation behind, whether a review round found the same place the
previous one did -- and this one does not.

The shape is `rescue_verdicts.yml`'s, which works: enumerate the
sites, require each to be accounted for, fail on one that is not.
Every `Mutex.new` in `core/lib` would carry an entry naming what it
guards and where it sits in the lock order, and a new one without an
entry would fail. `0.3.2` found the value of that from the other
direction: `#incoming_calls_result` reads `@file_summaries` without
`@index_mutation_mutex`, which `#apply_file_summary` writes under, and
nothing in the tree says so — it took reading both to find out, and
the answer is now a comment that the next reader may or may not see.

Not in 0.3.2 because the enumeration is the work, not the check: each
mutex needs its guarded state written down and argued, which is what
`024.122` cost for the rescues.

---


## 024.321 A stdlib class can be answered about but not judged against — the half 0.4.0 left

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** core/lib/ovallsp/signatures/environment.rb

- found by: core/lib/ovallsp/signatures/environment.rb:119 and :305
- RBS::EnvironmentLoader.new is used with no add(library:), which loads Ruby's core signatures and no stdlib library. Driven: env.load(workspace_root: nil) then declares? is true for String/Integer/Array/Hash/Set/Time/File and false for JSON/Date/URI/Logger/CSV/Digest, with 0 ancestors for each. Costs answers rather than correctness -- a fixture requiring json and date produced no diagnostics at all in :safe mode, so the engine declines rather than reporting wrongly. What a user loses is hover, completion and go-to-definition on the stdlib beyond core.

**Direction:** Add the stdlib libraries RBS ships to the loader, and decide the set deliberately rather than by listing what came to mind: RBS::Repository knows what is available, and loading everything costs startup time this project measures. The control that matters is that no *new* report appears -- the gap costs answers, not correctness, so the fix must not turn a silence into a wrong answer. Drive it with a corpus run before and after, with unknown-method as the control.

---



## Half of this shipped in 0.4.0, and the half that did not is a decision

**Fixed:** the loader adds every stdlib library RBS ships — 61 of them,
listed through `RBS::Repository#gems.keys` rather than a directory guess.
`JSON`, `Date`, `URI`, `Logger`, `CSV` and `Digest` are names the engine
knows, so hover, completion and go-to-definition answer about them.
Measured on activesupport + i18n, 335 files: `unresolved-constant`
916 → 741, `unknown-method` 19 → 11, **0 introduced across every
category**, corpus-sha256 identical on both sides.

**Open, and this is what the entry is now about:** the diagnostics do not
use those signatures. A library signature is good enough to answer *from*
and not good enough to judge *against*, and that is measured rather than
cautious. Three silences became wrong reports the moment `declares?`
alone decided, each driven:

    include Singleton   `.instance` reported as a typo. RBS writes it
                        `def self.instance` on the module and cannot
                        express the `included` hook.
    include Open3       `popen2e` reported. Ruby 3.4.10 has it; RBS
                        4.0.3 omits it, with `pipeline*`.
    Shellwords.escape   a `Pathname` argument reported wrong.
                        `shellwords.rbs` says `(String str)`; the
                        implementation calls `to_s`.

And the libraries reopen core classes, which is a second shape: `json`
puts `to_json` on `Object`, `pp` puts `pretty_inspect` there,
`shellwords` puts `shellescape` on `String`, `bigdecimal` puts `to_d`
there from its own gem `sig/`. Ruby has none of them unless the program
required the library. Offered, they complete a label that raises when
picked; asserted, they silenced three correct `unknown-method` reports on
a plain fixture. So a member declared only outside core and the project's
own `sig/` is dropped from a type core declares.

**What is left is to make a library's signature judgeable when the
project actually loads it.** The parser already sees every `require`, and
the Runtime Agent already reports what the running application defines —
either could say which libraries are real for this project, which is the
fact both rules are standing in for. That is an experiment to design, not
a hunk, so it moves rather than closing.

## 024.322 The server never passes bundle_context, so gem RBS is never loaded -- while the cache fingerprint hashes the lockfile that decides it

```yaml
status: open
kind: defect
user-visible: yes
target: 0.4.0
```

**Area:** core/lib/ovallsp/server.rb

- found by: core/lib/ovallsp/server.rb:1681 and :1704
- Signatures::Environment#load takes bundle_context: for gem RBS directories, and add_gem_signatures returns immediately when it is nil. Both production call sites -- server.rb:1704 and :3853 -- pass only workspace_root:, so no gem RBS is ever loaded; the parameter is exercised by specs alone. Thirty lines above the first of them, the cache fingerprint deliberately includes rbs_collection.lock.yaml with a comment saying the lockfile decides which gem RBS get loaded. One file states that the lockfile matters and then loads nothing it names.

**Direction:** Either pass a bundle_context the server actually builds -- resolving rbs_collection.lock.yaml to its gem signature directories, which add_gem_signatures already knows how to consume -- or remove the parameter and the lockfile from the cache fingerprint, so one file stops saying the lockfile decides something and then ignoring it. Decide which before writing either. The control is the same as the stdlib entry's: gem RBS arriving must not turn a silence into a wrong answer.

---


## 024.R1 Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0)

```yaml
status: open
kind: roadmap
target: 1.0.0
```

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


## 024.R3 Feature parity roadmap, measured against Pylance

```yaml
status: open
kind: roadmap
target: 1.0.0
```

roadmap. Its three 0.2.0 rows are done; the table below carries a **shipped in** column so the entry can be read as a record rather than only as a plan. All three shipped outright. This sentence said whole-project diagnostics shipped *without* a capability row because its E2E example did not pass -- true of 0.2.0, retracted in 0.2.1 when `024.14` closed as "it does not reproduce, and did not need fixing". Row `G17` reads PASS with an example, and README marks the row ✅, not ⚠️. `024.14`'s correction reached five documents and not this one; caught in 0.4.0's opening.

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
| Diagnostics across the whole project | Open files only | **0.2.0** | 0.2.0 (`G17`) | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.0** | 0.2.0 | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.0** | 0.2.0 | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.0** | 0.3.0 | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.0** | 0.3.0 | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.0** | 0.3.0 | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.0** | 0.3.0 | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.0** | 0.3.0 | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
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


**Retargeted to 1.0.0.** A parity roadmap does not get fixed in a release; it terminates at the version whose definition it serves. The other two roadmap entries that are still open, 024.R1 and 024.R4, are both 1.0.0, and docs/PUBLISHING.md's 0.x section is what defines that bar. Unscheduled was the value that let it sit outside every release's reckoning.

### 0.3.3: the five 0.3.0 rows are filled in, three releases late

Inlay hints, code actions, go to type definition, document highlight and
call hierarchy each carried an empty **Shipped in** cell until here, and
the preamble above makes an empty cell an assertion — "Everything below
without a 'shipped in' is still absent." All five shipped in 0.3.0:
`vscode/CHANGELOG.md`'s 0.3.0 section names each, and
`core/lib/ovallsp/server.rb` advertises `inlayHintProvider`,
`codeActionProvider`, `typeDefinitionProvider`, `documentHighlightProvider`
and `callHierarchyProvider` in the `initialize` response, which is the
source this table says its capability list was read from. So this entry
asserted the absence of five capabilities across three shipped releases,
and broke its own "Keep the two in step" instruction, since `README.md`
and `README.ja.md` mark all five shipped.

Nothing about the roadmap changes: the rows are a record, the entry stays
open at 1.0.0 as a parity plan, and only the record was wrong.

## 024.R4 Only one platform is published or verified (roadmap, 1.0.0)

```yaml
status: open
kind: roadmap
target: 1.0.0
```

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

## 024.R10 The repository is closed to external contributions until 1.0.0 (roadmap, 1.0.0)

```yaml
status: open
kind: roadmap
target: 1.0.0
```

**Area:** `README.md`'s opening note, `docs/PUBLISHING.md`'s "External
contributions: none until 1.0.0", and the repository root, where a
contributing guide, a code of conduct and a support page stood until 058
with the Japanese translations of the internal process documents beside
them.

The repository does not accept issues or pull requests while the
developer is investigating and fixing things faster than an external
change could be reviewed against, and GitHub Issues are disabled. 058
removed the documents written for a contributor who cannot yet arrive —
`CONTRIBUTING`, `CODE_OF_CONDUCT` and `SUPPORT`, in both languages —
rather than keep them current for nobody, and with them the Japanese
copies of `DOCUMENTATION_MAP`, `PUBLISHING` and `CLIENT_BEHAVIOUR`, which
are internal process documents and are now single-language, as
`RELEASE_CHECKLIST` and `RELEASE_ARTIFACTS` already were. The
`/Applications` disclosure that lived in the contributing guide moved to
`SECURITY.md`, which stays bilingual because a user reads it.

**Direction:** at 1.0.0 — the point where the product is stable enough
for a contributor to work against (`docs/PUBLISHING.md`, "External
contributions: none until 1.0.0") — restore the three documents, decide
again which internal documents earn a translation, and re-enable Issues.
`README.md` states the closure and points here until then.

---


