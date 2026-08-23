# Task 024: Deferred review findings

Findings from independent review that were deliberately **not** fixed in
the change set they were found in, because fixing them would have widened
that change set beyond what its own goal required.

**This is the single place deferred findings are collected.** Do not open
a second file, and do not scatter `TODO` comments through the source for
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

**217 entries below** <!-- measured: register-entries = 217 -->,
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
| [`024.1`](#0241-duplicate-unused-implementation-of-the-controller-callback-chain) | fixed | 0.1.10 | Duplicate, unused implementation of the controller callback chain |
| [`024.6`](#0246-the-seen-uris-spec-s-comment-overclaims) | fixed | 0.1.10 | The `seen_uris` spec's comment overclaims |
| [`024.8`](#0248-ownership-retirement-on-exited-known-size-0-is-unpinned) | fixed | 0.1.10 | Ownership retirement on `exited() && known.size === 0` is unpinned |
| [`024.10`](#02410-four-extension-ts-behaviours-cannot-be-unit-tested) | fixed | 0.1.10 | Four `extension.ts` behaviours cannot be unit-tested |
| [`024.13`](#02413-a-reopened-core-class-looks-closed-in-both-directions-0-3-x) | open | 0.2.15 | A reopened core class looks closed, in both directions (0.3.x) |
| [`024.14`](#02414-workspace-wide-diagnostics-do-not-fire-against-the-real-rails-fixture) | fixed | 0.2.1 | Workspace-wide diagnostics do not fire against the real Rails fixture |
| [`024.15`](#02415-the-index-s-answers-depend-on-which-file-was-edited-last) | fixed | 0.1.13 | The index's answers depend on which file was edited last |
| [`024.16`](#02416-the-capability-e2e-suite-can-skip-in-full-while-ci-stays-green) | fixed | 0.1.13 | The capability E2E suite can skip in full while CI stays green |
| [`024.17`](#02417-vscode-src-extension-ts-is-covered-by-no-test-that-runs-anywhere) | fixed | 0.1.13 | `vscode/src/extension.ts` is covered by no test that runs anywhere |
| [`024.18`](#02418-the-unassigned-ivar-check-cannot-enumerate-what-it-needs-to) | open | 0.2.16 | The unassigned-`@ivar` check cannot enumerate what it needs to |
| [`024.19`](#02419-the-argument-type-check-judges-against-a-class-the-receiver-is-not) | open | 0.2.15 | The argument-type check judges against a class the receiver is not |
| [`024.20`](#02420-contains-treats-an-exclusive-end-offset-as-inclusive) | open | 0.2.15 | `contains?` treats an exclusive end offset as inclusive |
| [`024.21`](#02421-a-qualified-constant-is-coloured-half-one-way-half-the-other) | fixed | 0.2.15 | A qualified constant is coloured half one way, half the other |
| [`024.22`](#02422-the-unassigned-ivar-check-is-silent-in-an-application-rails-new-produces) | open | 0.2.16 | The unassigned-`@ivar` check is silent in an application `rails new`… |
| [`024.23`](#02423-the-singleton-chain-did-not-model-class-module) | fixed | 0.1.14 | The singleton chain did not model `Class`/`Module` |
| [`024.24`](#02424-every-path-url-call-is-a-missing-route-when-no-routes-are-loaded) | fixed | 0.2.0 | Every `*_path`/`*_url` call is a missing route when no routes are lo… |
| [`024.25`](#02425-a-markdown-parsing-spec-is-the-wrong-shape-for-these-two-documents-must-agree) | fixed | 0.2.12 | A Markdown-parsing spec is the wrong shape for "these two documents … |
| [`024.26`](#02426-a-workspace-def-object-foo-is-reachable-from-every-class-in-ruby-and-from-none-here) | fixed | 0.2.12 | A workspace `def Object.foo` is reachable from every class in Ruby a… |
| [`024.27`](#02427-documentsymbol-lists-one-outline-entry-per-name-a-macro-declares) | open | 0.2.15 | `documentSymbol` lists one outline entry per name a macro declares |
| [`024.28`](#02428-rename-refuses-on-a-macro-declared-method-rather-than-editing-it) | open | 0.2.16 | Rename refuses on a macro-declared method rather than editing it |
| [`024.29`](#02429-two-features-were-written-for-0-1-15-and-cut-from-it) | open | 0.2.15 | Two features were written for 0.1.15 and cut from it |
| [`024.30`](#02430-0-1-15-s-hunk-sweep-three-hunks-that-cannot-be-pinned-and-why) | fixed | 0.2.12 | 0.1.15's hunk sweep: three hunks that cannot be pinned, and why |
| [`024.31`](#02431-a-declaration-written-inside-a-block-has-no-owner-this-parser-can-name) | fixed | — | A declaration written inside a block has no owner this parser can na… |
| [`024.32`](#02432-def-foo-bar-is-recorded-as-an-instance-method-so-both-answers-are-inverted) | fixed | — | `def Foo.bar` is recorded as an instance method, so both answers are… |
| [`024.33`](#02433-k-instance-eval-attr-accessor-x-is-reported-k-class-eval-is-not) | fixed | — | `K.instance_eval { attr_accessor :x }` is reported; `K.class_eval` i… |
| [`024.34`](#02434-attr-inside-a-def-inside-class-self-is-kinded-singleton) | fixed | 0.2.13 | `attr_*` inside a `def` inside `class << self` is kinded singleton |
| [`024.35`](#02435-a-class-that-includes-a-module-the-workspace-cannot-resolve-still-reads-as-closed) | open | 0.2.15 | A class that includes a module the workspace cannot resolve still re… |
| [`024.36`](#02436-instructing-a-reviewer-narrowed-what-it-could-find-and-a-control-run-proved-it) | fixed | 0.1.15 | Instructing a reviewer narrowed what it could find, and a control ru… |
| [`024.37`](#02437-the-argument-type-check-reports-nothing-on-measured-real-ruby) | open | 0.2.15 | The argument-type check reports nothing on measured real Ruby |
| [`024.38`](#02438-scope-at-copies-the-whole-environment-once-per-descent-step) | open | 0.2.15 | `scope_at` copies the whole environment once per descent step |
| [`024.39`](#02439-localinferencer-keeps-per-request-state-and-0-2-0-gave-it-a-second-thread) | open | 0.2.15 | `LocalInferencer` keeps per-request state, and 0.2.0 gave it a secon… |
| [`024.40`](#02440-every-argument-count-report-on-the-measurement-corpus-is-false) | open | 0.2.15 | Every `argument-count` report on the measurement corpus is false |
| [`024.41`](#02441-typing-a-reports-a-method-on-the-next-line) | open | 0.2.15 | Typing a `.` reports a method on the *next* line |
| [`024.42`](#02442-an-rbs-signature-label-says-unknown-where-rbs-says-self-and-leaks-method-type-variables) | open | 0.2.15 | An RBS signature label says `Unknown` where RBS says `self`, and lea… |
| [`024.43`](#02443-signature-help-answers-nothing-for-a-receiverless-stdlib-call) | open | 0.2.15 | Signature help answers nothing for a receiverless stdlib call |
| [`024.44`](#02444-a-partial-s-local-is-not-resolved-and-c11-s-stated-basis-names-it) | open | 0.2.16 | A partial's local is not resolved, and C11's stated basis names it |
| [`024.45`](#02445-re-analysis-after-a-keystroke-is-seconds-on-a-large-file-against-a-stated-300-ms) | open | 0.2.15 | Re-analysis after a keystroke is seconds on a large file, against a … |
| [`024.46`](#02446-typing-self-cost-55-false-diagnostics-and-was-rolled-back) | fixed | 0.2.1 | Typing `self` cost 55 false diagnostics and was rolled back |
| [`024.47`](#02447-a-namespaced-class-named-after-a-core-class-loses-its-diagnostics-and-the-readers-disagree-about-a-shadowed-literal) | open | 0.2.15 | A namespaced class named after a core class loses its diagnostics, a… |
| [`024.48`](#02448-the-measurement-tool-ran-an-engine-the-server-never-runs) | fixed | 0.2.1 | The measurement tool ran an engine the server never runs |
| [`024.49`](#02449-a-release-record-kept-asserting-durations-it-could-not-witness-ending) | fixed | 0.2.3 | A release record kept asserting durations it could not witness ending |
| [`024.50`](#02450-the-marketplace-description-promises-the-behaviour-0-2-1-removed) | fixed | 0.2.3 | The Marketplace description promises the behaviour 0.2.1 removed |
| [`024.51`](#02451-the-first-launch-after-an-upgrade-blocks-while-it-sweeps-the-old-cache) | fixed | 0.2.2 | The first launch after an upgrade blocks while it sweeps the old cac… |
| [`024.52`](#02452-a-publish-could-outlive-the-document-it-was-about-folded-into-024-56) | fixed | reverted | A publish could outlive the document it was about — folded into `024… |
| [`024.53`](#02453-the-absent-workspace-grace-measured-the-wrong-clock) | fixed | 0.2.2 | The absent-workspace grace measured the wrong clock |
| [`024.54`](#02454-an-edit-that-changed-nothing-discarded-the-edit-before-it) | fixed | reverted | An edit that changed nothing discarded the edit before it |
| [`024.55`](#02455-a-version-mismatch-is-reported-and-then-ignored) | fixed | 0.2.12 | A version mismatch is reported and then ignored |
| [`024.56`](#02456-a-publish-can-land-after-the-panel-has-been-cleared-and-after-a-newer-one) | fixed | 0.2.7 | A publish can land after the panel has been cleared, and after a new… |
| [`024.57`](#02457-the-debounce-and-why-it-was-rolled-back) | open | 0.2.15 | The debounce, and why it was rolled back |
| [`024.58`](#02458-bin-ovallsp-loaded-every-abi-s-vendored-gems-not-the-running-one-s) | fixed | 0.2.2 | `bin/ovallsp` loaded every ABI's vendored gems, not the running one's |
| [`024.59`](#02459-the-guard-against-a-stale-example-count-could-not-run) | fixed | 0.2.3 | The guard against a stale example count could not run |
| [`024.60`](#02460-four-test-fixtures-raced-macos-first-execution-scan) | fixed | 0.2.3 | Four test fixtures raced macOS' first-execution scan |
| [`024.62`](#02462-two-per-file-stores-are-separated-by-nothing-but-their-payload) | open | 0.2.15 | Two per-file stores are separated by nothing but their payload |
| [`024.63`](#02463-the-dispatch-layer-owns-view-inference-and-it-has-broken-the-query-layer-s-one-guarantee-twice) | open | 0.2.15 | The dispatch layer owns view inference, and it has broken the query … |
| [`024.64`](#02464-three-rounds-on-extension-ts-s-wiring-and-the-countermeasure-was-aimed-at-the-symptom) | fixed | 0.2.12 | Three rounds on `extension.ts`'s wiring, and the countermeasure was … |
| [`024.65`](#02465-a-different-ruby-engine-produces-two-error-toasts-where-it-produced-one) | fixed | 0.2.3 | A different Ruby engine produces two error toasts where it produced … |
| [`024.66`](#02466-a-marketing-card-kept-carrying-claims-about-what-an-error-s-text-says) | fixed | 0.2.3 | A marketing card kept carrying claims about what an error's text says |
| [`024.67`](#02467-seven-register-numbers-are-cited-from-the-tree-and-resolve-to-nothing) | fixed | 0.3.0 | Seven register numbers are cited from the tree and resolve to nothing |
| [`024.68`](#02468-three-rounds-of-guards-on-a-hand-rolled-grammar-each-blind-one-assumption-deeper) | fixed | 0.2.12 | Three rounds of guards on a hand-rolled grammar, each blind one assu… |
| [`024.69`](#02469-the-two-suites-that-drive-a-real-editor-are-run-by-nobody-but-the-maintainer) | fixed | 0.2.12 | The two suites that drive a real editor are run by nobody but the ma… |
| [`024.71`](#02471-one-mutable-rails-fixture-is-shared-by-every-worker-so-the-suite-cannot-be-parallelised) | open | 0.2.15 | One mutable Rails fixture is shared by every worker, so the suite ca… |
| [`024.72`](#02472-the-red-toast-0-2-1-removed-is-still-shown-from-the-other-code-path) | fixed | 0.2.2 | The red toast 0.2.1 removed is still shown, from the other code path |
| [`024.73`](#02473-the-fork-boundary-is-undone-by-marshal-load-in-the-parent) | fixed | 0.2.6 | The fork boundary is undone by `Marshal.load` in the parent |
| [`024.74`](#02474-the-trust-gate-stands-in-front-of-callers-not-in-front-of-what-executes) | open | 0.2.15 | The trust gate stands in front of callers, not in front of what exec… |
| [`024.75`](#02475-a-documented-field-selects-nothing) | fixed | 0.2.12 | A documented field selects nothing |
| [`024.76`](#02476-fifty-four-unknown-method-reports-over-real-gem-source-and-all-of-them-false) | open | 0.2.15 | Fifty-four `unknown-method` reports over real gem source, and all of… |
| [`024.77`](#02477-a-call-to-a-method-that-does-not-exist-is-missed-through-a-relation) | open | 0.2.15 | A call to a method that does not exist is missed through a relation |
| [`024.78`](#02478-completion-did-not-get-the-fix-hover-and-diagnostics-did) | fixed | 0.2.6 | Completion did not get the fix hover and diagnostics did |
| [`024.79`](#02479-model-first-completes-to-nothing) | fixed | 0.2.6 | `Model.first` completes to nothing |
| [`024.80`](#02480-an-unresolved-hierarchy-edge-is-expressible-as-a-method-owner) | fixed | 0.2.12 | An unresolved hierarchy edge is expressible as a method owner |
| [`024.81`](#02481-an-ancestor-reference-carries-no-lexical-context-so-an-ambiguous-name-is-picked-rather-than-resolved) | fixed | 0.2.12 | An ancestor reference carries no lexical context, so an ambiguous na… |
| [`024.82`](#02482-foo-class-new-bar-is-not-a-type-the-index-knows) | open | 0.2.15 | `Foo = Class.new(Bar)` is not a type the index knows |
| [`024.83`](#02483-the-undefined-method-check-is-loudest-exactly-where-no-runtime-agent-can-answer) | open | 0.2.15 | The undefined-method check is loudest exactly where no Runtime Agent… |
| [`024.84`](#02484-a-constant-is-typed-as-a-class-object-whatever-it-holds) | open | 0.2.16 | A constant is typed as a class object whatever it holds |
| [`024.85`](#02485-self-completes-nothing) | open | 0.2.15 | `self.` completes nothing |
| [`024.86`](#02486-an-ivar-assigned-in-another-method-has-no-type-except-in-the-view) | open | 0.2.16 | An ivar assigned in another method has no type, except in the view |
| [`024.87`](#02487-a-relation-stops-being-a-relation-after-one-hop) | open | 0.2.15 | A relation stops being a relation after one hop |
| [`024.88`](#02488-completion-unions-a-union-s-members-the-diagnostic-intersects-them) | open | 0.2.15 | Completion unions a union's members; the diagnostic intersects them |
| [`024.89`](#02489-signature-help-strips-the-parameter-kinds-and-never-advances) | open | 0.2.15 | Signature help strips the parameter kinds and never advances |
| [`024.90`](#02490-smaller-answers-a-review-round-measured) | fixed | 0.2.14 | Smaller answers a review round measured |
| [`024.91`](#02491-the-undefined-method-check-reports-on-ordinary-ruby-it-cannot-read) | open | 0.2.15 | The undefined-method check reports on ordinary Ruby it cannot read |
| [`024.92`](#02492-a-plugin-chooses-how-much-memory-the-parent-allocates) | fixed | 0.2.6 | A plugin chooses how much memory the parent allocates |
| [`024.93`](#02493-process-kill-sig-0-signals-the-caller-s-own-process-group) | fixed | 0.2.6 | `Process.kill(sig, 0)` signals the caller's own process group |
| [`024.94`](#02494-a-windows-workspace-could-have-its-own-ruby-exe-run-before-it-is-trusted) | fixed | 0.2.6 | A Windows workspace could have its own `ruby.exe` run before it is t… |
| [`024.95`](#02495-a-deep-enough-file-ended-the-session-and-three-rescues-did-not-catch-it) | fixed | 0.2.6 | A deep enough file ended the session, and three rescues did not catc… |
| [`024.96`](#02496-every-malformed-lsp-frame-ended-the-process) | fixed | 0.2.6 | Every malformed LSP frame ended the process |
| [`024.97`](#02497-a-later-pass-at-the-same-version-overwrites-a-corrected-answer) | fixed | 0.2.12 | A later pass at the same version overwrites a corrected answer |
| [`024.98`](#02498-a-workspace-opened-through-a-symlink-shows-every-file-twice-and-one-copy-can-never-be-cleared) | fixed | 0.2.8 | A workspace opened through a symlink shows every file twice, and one… |
| [`024.99`](#02499-completion-offers-members-that-cannot-be-called-from-where-it-was-asked) | open | 0.2.16 | Completion offers members that cannot be called from where it was as… |
| [`024.100`](#024100-the-four-features-answer-from-different-code-paths-and-disagree-at-one-position) | open | 0.2.16 | The four features answer from different code paths and disagree at o… |
| [`024.101`](#024101-analysis-runs-per-keystroke-so-the-answers-fall-behind-the-cursor-and-every-wrong-one-is-published) | fixed | 0.2.10 | Analysis runs per keystroke, so the answers fall behind the cursor a… |
| [`024.102`](#024102-eight-classes-and-the-logic-each-one-could-not-have-happened-under) | open | 0.2.15 | Eight classes, and the logic each one could not have happened under |
| [`024.103`](#024103-a-bare-class-name-inside-a-namespace-answers-with-an-arbitrary-same-named-class) | fixed | 0.2.10 | A bare class name inside a namespace answers with an arbitrary same-… |
| [`024.104`](#024104-class-methods-do-in-a-concern-is-attributed-to-the-instance-side) | fixed | 0.2.10 | `class_methods do` in a concern is attributed to the instance side |
| [`024.105`](#024105-visibility-is-not-recorded-for-singleton-methods-at-all) | fixed | 0.2.9 | Visibility is not recorded for singleton methods at all |
| [`024.106`](#024106-module-function-and-extend-self-produce-nothing) | open | 0.2.16 | `module_function` and `extend self` produce nothing |
| [`024.107`](#024107-an-alias-never-appears-in-completion-though-every-other-feature-knows-it) | fixed | 0.2.9 | An alias never appears in completion, though every other feature kno… |
| [`024.108`](#024108-protected-methods-are-offered-on-an-explicit-external-receiver) | fixed | 0.2.9 | Protected methods are offered on an explicit external receiver |
| [`024.109`](#024109-specs-whose-fixture-cannot-distinguish-the-behaviour-they-pin) | fixed | 0.2.12 | Specs whose fixture cannot distinguish the behaviour they pin |
| [`024.110`](#024110-the-macro-is-reported-and-what-it-might-define-is-not) | fixed | 0.2.13 | The macro is reported, and what it might define is not |
| [`024.111`](#024111-a-visibility-section-written-inside-a-block-does-not-reach-the-body-it-runs-in) | open | 0.2.15 | A visibility section written inside a block does not reach the body … |
| [`024.112`](#024112-a-bare-constant-is-not-looked-up-through-the-enclosing-class-s-ancestors) | fixed | 0.2.11 | A bare constant is not looked up through the enclosing class's ances… |
| [`024.113`](#024113-the-publish-funnel-s-memory-is-keyed-by-uri-not-by-buffer) | fixed | 0.2.11 | The publish funnel's memory is keyed by uri, not by buffer |
| [`024.114`](#024114-module-function-name-cannot-see-a-module-reopened-in-another-file) | fixed | 0.2.11 | `module_function :name` cannot see a module reopened in another file |
| [`024.115`](#024115-include-m-reaches-m-classmethods-whether-or-not-m-is-a-concern) | fixed | 0.2.11 | `include M` reaches `M::ClassMethods` whether or not M is a Concern |
| [`024.116`](#024116-def-self-method-missing-and-define-singleton-method-do-not-open-a-surface) | fixed | 0.2.13 | `def self.method_missing` and `define_singleton_method` do not open … |
| [`024.117`](#024117-the-two-spellings-of-a-class-body-macro-get-opposite-answers) | fixed | 0.2.13 | The two spellings of a class-body macro get opposite answers |
| [`024.118`](#024118-workspaceindex-stale-compares-versions-across-buffers) | fixed | 0.2.12 | `WorkspaceIndex#stale?` compares versions across buffers |
| [`024.119`](#024119-twenty-eight-spec-files-assemble-their-own-analysis-stack) | fixed | 0.2.12 | Twenty-eight spec files assemble their own analysis stack |
| [`024.120`](#024120-the-integration-watcher-example-could-not-retry-and-it-looked-like-a-linux-defect) | fixed | 0.2.12 | The integration watcher example could not retry, and it looked like … |
| [`024.121`](#024121-nothing-measures-how-much-of-this-tree-no-test-would-notice-changing) | open | 0.2.15 | Nothing measures how much of this tree no test would notice changing |
| [`024.122`](#024122-a-failure-is-turned-into-a-plausible-value-in-72-measured-places) | fixed | 0.2.13 | A failure is turned into a plausible value, in 72 measured places |
| [`024.123`](#024123-a-private-alias-was-offered-and-the-register-said-it-was-not) | fixed | 0.2.12 | A private alias was offered, and the register said it was not |
| [`024.124`](#024124-four-entries-named-a-release-that-had-already-shipped-for-the-third-time) | fixed | 0.3.0 | Four entries named a release that had already shipped, for the third… |
| [`024.125`](#024125-the-packaged-core-is-never-driven-end-to-end-and-two-gates-say-it-is) | open | 0.2.15 | The packaged Core is never driven end to end, and two gates say it is |
| [`024.126`](#024126-a-text-scanner-matches-its-own-prose-exempts-itself-and-stops-checking-a-file-that-can-hold-the-real-thing) | fixed | 0.2.14 | A text scanner matches its own prose, exempts itself, and stops chec… |
| [`024.127`](#024127-hover-answers-an-empty-string-where-lsp-expects-null) | fixed | 0.2.15 | Hover answers an empty string where LSP expects null |
| [`024.128`](#024128-integer-arithmetic-answers-a-four-way-union) | fixed | 0.2.15 | Integer arithmetic answers a four-way union |
| [`024.129`](#024129-no-undefined-method-report-on-a-core-library-receiver) | open | 0.2.16 | No undefined-method report on a core-library receiver |
| [`024.130`](#024130-a-hover-label-drops-the-namespace-when-the-name-was-written-bare-withdrawn-it-does-not-reproduce) | fixed | 0.2.14 | A hover label drops the namespace when the name was written bare — w… |
| [`024.131`](#024131-after-on-a-nil-local-hover-answers-nil-a-wrong-answer-not-an-absent-one) | fixed | 0.2.15 | After `||=` on a nil local, hover answers `nil` — a wrong answer, no… |
| [`024.132`](#024132-a-scope-defined-in-a-concern-s-included-do-has-no-type) | open | 0.2.16 | A scope defined in a concern's `included do` has no type |
| [`024.133`](#024133-a-positional-argument-to-a-keyword-only-method-reads-as-nonsense) | fixed | 0.2.15 | A positional argument to a keyword-only method reads as nonsense |
| [`024.134`](#024134-wait-until-ready-never-returns-for-a-non-rails-workspace) | fixed | 0.2.15 | `wait_until_ready` never returns for a non-Rails workspace |
| [`024.135`](#024135-observation-runner-deserialises-a-subprocess-s-output-with-marshal-load) | open | 0.2.15 | `Observation::Runner` deserialises a subprocess's output with `Marsh… |
| [`024.136`](#024136-a-route-s-optional-segments-are-detected-by-matching-the-literal-format) | open | 0.2.15 | A route's optional segments are detected by matching the literal `(.… |
| [`024.137`](#024137-workspaceindex-search-scans-every-symbol-in-the-workspace) | open | 0.2.15 | `WorkspaceIndex#search` scans every symbol in the workspace |
| [`024.138`](#024138-no-test-mixes-a-schema-change-and-a-model-file-change-in-one-batch) | open | 0.2.15 | No test mixes a schema change and a model-file change in one batch |
| [`024.139`](#024139-task-documents-grew-their-own-findings-sections-outside-the-register) | fixed | 0.2.14 | Task documents grew their own findings sections, outside the register |
| [`024.140`](#024140-a-scripted-edit-doubled-a-register-entry-and-every-check-stayed-green) | fixed | 0.2.14 | A scripted edit doubled a register entry, and every check stayed gre… |
| [`024.141`](#024141-publishing-md-documented-the-publish-command-that-shipped-a-corrupt-v0-1-2) | fixed | 0.2.14 | `PUBLISHING.md` documented the publish command that shipped a corrup… |
| [`024.142`](#024142-a-corpus-run-did-not-say-what-it-had-run) | fixed | 0.2.14 | A corpus run did not say what it had run |
| [`024.143`](#024143-did-i-run-everything-was-answered-from-memory) | fixed | 0.2.14 | "Did I run everything?" was answered from memory |
| [`024.144`](#024144-a-design-document-restating-a-manifest-is-two-copies-with-nothing-between-them) | fixed | 0.2.14 | A design document restating a manifest is two copies with nothing be… |
| [`024.145`](#024145-re-deriving-the-example-count-was-three-hand-edits-per-commit) | fixed | 0.2.14 | Re-deriving the example count was three hand edits per commit |
| [`024.146`](#024146-a-script-crashes-under-a-locale-less-shell-on-the-input-a-check-exists-to-report) | fixed | 0.2.14 | A script crashes under a locale-less shell, on the input a check exi… |
| [`024.147`](#024147-every-check-was-blind-to-a-file-until-it-was-committed-and-the-commit-gate-runs-before-that) | fixed | 0.2.14 | Every check was blind to a file until it was committed, and the comm… |
| [`024.148`](#024148-the-check-for-did-the-suite-actually-run-could-not-fail-in-the-case-it-existed-for) | fixed | 0.2.14 | The check for "did the suite actually run" could not fail in the cas… |
| [`024.149`](#024149-a-review-harness-that-reports-nothing-found-when-its-own-post-processing-crashed) | fixed | 0.2.14 | A review harness that reports "nothing found" when its own post-proc… |
| [`024.150`](#024150-agents-md-paraphrases-claude-md-and-the-paraphrase-drifts) | open | 0.2.15 | `AGENTS.md` paraphrases `CLAUDE.md`, and the paraphrase drifts |
| [`024.151`](#024151-a-check-can-be-disabled-and-no-check-notices) | open | 0.2.15 | A check can be disabled, and no check notices |
| [`024.152`](#024152-a-leak-check-counted-every-descriptor-in-the-process-and-flaked-under-load) | fixed | 0.2.14 | A leak check counted every descriptor in the process, and flaked und… |
| [`024.153`](#024153-a-quarter-of-the-open-work-is-in-no-release-and-0-3-0-has-become-where-the-rest-goes) | open | 0.2.15 | A quarter of the open work is in no release, and 0.3.0 has become wh… |
| [`024.154`](#024154-findings-recorded-in-046-are-truncated-mid-sentence-in-rounds-1-and-3-in-the-same-commit-that-untruncated-round-2) | open | 0.2.15 | Findings recorded in 046 are truncated mid-sentence in rounds 1 and … |
| [`024.155`](#024155-a-register-heading-the-entry-grammar-does-not-match-is-skipped-rather-than-failed-so-an-entry-can-exist-and-be-checked-by-nothing) | open | 0.2.15 | A register heading the entry grammar does not match is skipped rathe… |
| [`024.156`](#024156-the-evidence-extractor-recognises-only-rb-sh-js-and-test-so-typescript-tests-and-ci-job-names-the-sole-evidence-for-eight-gates-are-never-checked) | open | 0.2.15 | The evidence extractor recognises only .rb/.sh/.js and test:, so Typ… |
| [`024.157`](#024157-a-git-subprocess-in-a-throwaway-repository-obeys-the-inherited-git-dir-so-the-suite-commits-to-the-real-repository) | open | 0.2.15 | A git subprocess in a throwaway repository obeys the inherited GIT_D… |
| [`024.158`](#024158-the-executed-pat-mode-example-passes-on-a-release-sh-that-only-warns-because-its-exit-status-comes-from-a-later-check-misreporting-a-non-repository-as-dirty) | open | 0.2.15 | The executed PAT-mode example passes on a release.sh that only warns… |
| [`024.159`](#024159-the-measured-claim-marker-and-the-number-a-reader-sees-are-separate-strings-so-the-prose-can-say-anything-while-the-marker-verifies) | open | 0.2.15 | The measured-claim marker and the number a reader sees are separate … |
| [`024.160`](#024160-counts-in-046-that-describe-this-tree-carry-no-basis-are-not-marked-and-several-are-stale-at-head) | open | 0.2.16 | Counts in 046 that describe this tree carry no basis, are not marked… |
| [`024.161`](#024161-046-s-round-3-correction-states-that-the-4-000-lines-of-revert-phrase-is-removed-the-phrase-is-still-the-file-s-closing-sentence) | open | 0.2.16 | 046's round-3 correction states that the "4,000 lines of revert" phr… |
| [`024.162`](#024162-046-s-recorded-departure-from-the-drive-round-rests-on-a-false-enumeration-of-the-change-set) | open | 0.2.16 | 046's recorded departure from the `drive` round rests on a false enu… |
| [`024.163`](#024163-046-s-round-2-header-asserts-every-attacker-worked-in-a-clean-tree-and-046-s-own-recorded-findings-say-the-tree-was-dirty-and-changing-throughout) | open | 0.2.16 | 046's round-2 header asserts every attacker worked in a clean tree, … |
| [`024.164`](#024164-046-states-finding-totals-whose-stated-dispositions-do-not-account-for-them) | open | 0.2.16 | 046 states finding totals whose stated dispositions do not account f… |
| [`024.165`](#024165-046-keeps-138-acceptance-boxes-on-the-stated-ground-that-no-box-has-ever-been-ticked-56-are-ticked-13-of-them-in-a-file-this-change-set-edited) | open | 0.2.16 | 046 keeps 138 acceptance boxes on the stated ground that no box has … |
| [`024.166`](#024166-two-rows-of-046-s-checks-table-describe-checks-that-were-built-differently-and-the-changed-shape-list-omits-one) | open | 0.2.16 | Two rows of 046's checks table describe checks that were built diffe… |
| [`024.167`](#024167-046-s-three-review-rounds-record-no-per-place-tracking-so-claude-md-s-same-place-rule-cannot-be-applied-and-was-not) | open | 0.2.16 | 046's three review rounds record no per-place tracking, so CLAUDE.md… |
| [`024.168`](#024168-the-ledger-s-reason-for-keeping-05-protocol-md-s-section-numbering-counts-four-source-comments-where-one-exists-and-the-claim-was-copied-into-the-shipped-document) | open | 0.2.16 | The ledger's reason for keeping 05-protocol.md's section numbering c… |
| [`024.169`](#024169-check-doc-links-rb-s-citation-comment-describes-anchor-punctuation-stripping-that-no-caller-performs) | open | 0.2.16 | `check_doc_links.rb`'s CITATION comment describes anchor/punctuation… |
| [`024.170`](#024170-the-doubled-entry-check-counts-area-lines-so-a-body-duplicated-anywhere-below-that-line-is-invisible) | open | 0.2.16 | The doubled-entry check counts `**Area:**` lines, so a body duplicat… |
| [`024.171`](#024171-three-entries-closed-in-0-2-14-state-as-done-something-head-contradicts-two-of-them-naming-a-countermeasure-that-was-never-built) | open | 0.2.16 | Three entries closed in 0.2.14 state as done something HEAD contradi… |
| [`024.172`](#024172-four-counts-derived-about-this-tree-are-wrong-and-unmarked-one-of-them-inside-the-entry-about-a-record-that-drifted) | open | 0.2.16 | Four counts derived about this tree are wrong and unmarked, one of t… |
| [`024.173`](#024173-the-shipped-target-guard-sees-only-kind-defect-and-released-in-is-written-by-16-entries-and-read-by-no-check) | open | 0.2.16 | The shipped-target guard sees only `kind: defect`, and `released-in:… |
| [`024.174`](#024174-a-relative-markdown-link-beginning-docs-is-resolved-against-the-repository-root-instead-of-the-citing-file-s-directory) | open | 0.2.16 | A relative Markdown link beginning `docs/` is resolved against the r… |
| [`024.175`](#024175-doc-link-resolution-goes-through-file-file-so-a-case-only-typo-passes-on-macos-and-fails-on-linux-and-github) | open | 0.2.16 | Doc-link resolution goes through File.file?, so a case-only typo pas… |
| [`024.176`](#024176-the-deletion-marker-marker-admits-a-pointer-to-a-renamed-file-which-the-paragraph-defining-it-says-is-still-a-failure) | open | 0.2.16 | The `[deletion marker]` marker admits a pointer to a renamed file, w… |
| [`024.177`](#024177-check-doc-links-names-only-an-enumerated-set-of-docs-subdirectories-so-a-citation-in-any-other-one-is-silently-unchecked) | open | 0.2.16 | check_doc_links names only an enumerated set of docs subdirectories,… |
| [`024.178`](#024178-check-doc-links-founding-census-is-stated-as-living-entirely-in-source-comments-one-of-the-nineteen-was-in-a-markdown-document) | open | 0.2.16 | check_doc_links' founding census is stated as living entirely in sou… |
| [`024.179`](#024179-hand-typed-counts-in-check-doc-links-header-do-not-reproduce-and-none-carries-a-measured-marker) | open | 0.2.16 | Hand-typed counts in check_doc_links' header do not reproduce, and n… |
| [`024.180`](#024180-the-citation-guard-reads-nine-file-extensions-so-the-published-site-s-register-pointers-are-outside-every-check) | open | 0.2.16 | The citation guard reads nine file extensions, so the published site… |
| [`024.181`](#024181-the-measured-claim-scanner-reads-four-hand-written-globs-so-a-marker-anywhere-else-is-inert) | open | 0.2.16 | The measured-claim scanner reads four hand-written globs, so a marke… |
| [`024.182`](#024182-a-sub-numbered-register-entry-is-invisible-to-the-citation-guard-and-a-citation-of-one-truncates-to-its-parent) | open | 0.2.16 | A sub-numbered register entry is invisible to the citation guard, an… |
| [`024.183`](#024183-the-citation-guard-skips-the-register-itself-where-most-024-n-cross-references-are-written) | open | 0.2.16 | The citation guard skips the register itself, where most `024.N` cro… |
| [`024.184`](#024184-a-dated-rev-claim-is-silently-derived-from-the-present-tree-unless-the-deriver-happens-to-use-the-revision) | open | 0.2.16 | A dated `@<rev>` claim is silently derived from the present tree unl… |
| [`024.185`](#024185-a-second-measured-marker-on-the-same-line-is-never-parsed) | open | 0.2.16 | A second `<!-- measured: -->` marker on the same line is never parsed |
| [`024.186`](#024186-mutex-sites-counts-the-string-mutex-new-so-a-comment-mentioning-it-inflates-the-documented-lock-count) | open | 0.2.16 | `mutex-sites` counts the string `Mutex.new`, so a comment mentioning… |
| [`024.187`](#024187-a-single-nul-or-invalid-byte-clears-a-whole-file-from-the-home-path-scan-and-no-example-can-fail-on-it) | open | 0.2.16 | A single NUL or invalid byte clears a whole file from the home-path … |
| [`024.188`](#024188-the-home-path-scanner-dereferences-a-symlink-instead-of-reading-the-blob-git-commits) | open | 0.2.16 | The home-path scanner dereferences a symlink instead of reading the … |
| [`024.189`](#024189-the-home-path-pattern-matches-one-spelling-so-every-other-spelling-of-the-same-real-path-passes) | open | 0.2.16 | The home-path pattern matches one spelling, so every other spelling … |
| [`024.190`](#024190-annotated-tag-messages-are-a-pushed-public-channel-neither-mode-of-the-home-path-check-scans) | open | 0.2.16 | Annotated tag messages are a pushed public channel neither mode of t… |
| [`024.191`](#024191-as-utf8-s-comment-describes-a-hazard-the-same-file-s-utf8-require-already-removed) | open | 0.2.16 | as_utf8's comment describes a hazard the same file's utf8 require al… |
| [`024.192`](#024192-the-case-sensitivity-decision-is-justified-by-a-count-of-37-that-was-never-right) | open | 0.2.16 | The case-sensitivity decision is justified by a count of 37 that was… |
| [`024.193`](#024193-existence-is-a-suffix-glob-and-any-test-name-passes-unconditionally-so-a-citation-naming-a-file-that-does-not-exist-is-accepted) | open | 0.2.16 | Existence is a suffix glob and any test: name passes unconditionally… |
| [`024.194`](#024194-release-gate-spec-s-wiring-corpus-includes-untracked-files-so-uncommitted-local-text-satisfies-a-gate-s-something-invokes-this) | open | 0.2.16 | release_gate_spec's wiring corpus includes untracked files, so uncom… |
| [`024.195`](#024195-every-prose-statement-of-what-the-preflight-gate-runs-is-stale-and-nothing-derives-any-of-them) | open | 0.2.16 | Every prose statement of what the preflight gate runs is stale, and … |
| [`024.196`](#024196-the-measurement-that-justifies-reading-per-example-status-is-quoted-three-times-attributed-to-a-different-file-each-time-and-matches-none-of-them) | open | 0.2.16 | The measurement that justifies reading per-example status is quoted … |
| [`024.197`](#024197-0-2-14-s-review-loop-edited-its-own-standard-and-added-a-capability-between-rounds-with-no-departure-recorded) | open | 0.2.16 | 0.2.14's review loop edited its own standard and added a capability … |
| [`024.198`](#024198-the-packaged-artifact-inspection-count-is-derived-from-the-directory-alone-so-a-grep-aimed-at-the-wrong-pattern-or-with-wider-exclusions-still-reports-a-healthy-count) | open | 0.2.16 | The packaged-artifact inspection count is derived from the directory… |
| [`024.199`](#024199-the-guard-spec-s-absolute-grep-pin-is-satisfied-by-the-advisory-grep-and-its-bare-grep-scan-cannot-see-an-indented-call) | open | 0.2.16 | The guard spec's absolute-grep pin is satisfied by the advisory grep… |
| [`024.200`](#024200-nothing-checks-that-release-sh-parses-so-a-syntax-error-past-the-first-refusal-leaves-every-check-green) | open | 0.2.16 | Nothing checks that release.sh parses, so a syntax error past the fi… |
| [`024.201`](#024201-the-not-yet-escape-hatch-is-guarded-against-a-hand-copied-two-suite-list-that-has-drifted-from-the-three-suite-table-it-covers) | open | 0.2.16 | The NOT YET escape hatch is guarded against a hand-copied two-suite … |
| [`024.202`](#024202-the-release-tag-accounting-invariant-runs-nowhere-continuous-the-job-that-runs-the-suite-checks-out-without-tags) | open | 0.2.16 | The release-tag accounting invariant runs nowhere continuous: the jo… |
| [`024.203`](#024203-suites-ran-spec-s-ci-yml-link-asserts-a-text-substring-so-it-passes-for-a-step-that-has-been-deleted-commented-out-or-disabled) | open | 0.2.16 | suites_ran_spec's ci.yml link asserts a text substring, so it passes… |
| [`024.204`](#024204-the-git-ls-files-guard-reads-49-files-in-two-directories-so-the-enumeration-it-forbids-is-invisible-everywhere-else-in-the-tree) | open | 0.2.16 | The `git ls-files` guard reads 49 files in two directories, so the e… |
| [`024.205`](#024205-the-duplicate-heading-check-tracks-a-fence-by-its-character-and-not-its-length-so-a-four-backtick-block-leaves-the-rest-of-the-file-unread) | open | 0.2.16 | The duplicate-heading check tracks a fence by its character and not … |
| [`024.206`](#024206-the-duplicate-heading-check-sees-only-unindented-h1-and-h2-while-024-140-records-the-guarantee-as-every-heading) | open | 0.2.16 | The duplicate-heading check sees only unindented h1 and h2, while `0… |
| [`024.207`](#024207-two-decisions-in-the-duplicate-heading-fence-parser-have-no-fixture-that-can-distinguish-them) | open | 0.2.16 | Two decisions in the duplicate-heading fence parser have no fixture … |
| [`024.208`](#024208-encoding-default-internal-nil-is-the-half-of-the-locale-fix-that-nothing-pins) | open | 0.2.16 | `Encoding.default_internal = nil` is the half of the locale fix that… |
| [`024.209`](#024209-the-5-status-bar-comparison-is-set-equality-against-a-regex-sample-of-clientpresentation-ts-not-against-the-file-s-status-strings-and-two-records-state-the-stronger-guarantee) | open | 0.2.16 | The §5 status-bar comparison is set equality against a regex sample … |
| [`024.210`](#024210-the-plugin-sdk-check-asks-whether-a-name-is-defined-anywhere-under-core-lib-ovallsp-plugins-not-whether-it-is-callable-on-the-receiver-the-document-shows) | open | 0.2.16 | The plugin-sdk check asks whether a name is defined anywhere under c… |
| [`024.211`](#024211-check-pinned-mutations-rb-verify-only-prints-the-applier-s-conclusion-after-applying-nothing) | open | 0.2.16 | `check_pinned_mutations.rb --verify-only` prints the applier's concl… |
| [`024.212`](#024212-pinned-mutations-yml-s-header-documents-the-mechanism-the-applier-abandoned-and-a-scope-it-no-longer-has) | open | 0.2.16 | pinned_mutations.yml's header documents the mechanism the applier ab… |
| [`024.213`](#024213-a-mutation-entry-s-stated-reason-describes-a-mutation-different-from-the-one-it-encodes) | open | 0.2.16 | A mutation entry's stated reason describes a mutation different from… |
| [`024.214`](#024214-generate-sbom-rb-s-header-tells-the-reader-a-stale-sbom-is-caught-by-nobody-in-the-release-that-made-a-spec-catch-it) | open | 0.2.16 | generate_sbom.rb's header tells the reader a stale SBOM is caught by… |
| [`024.215`](#024215-a-scripted-comment-rewrite-in-corpus-diagnostics-rb-cut-a-sentence-mid-clause-and-nothing-in-the-tree-can-see-it) | open | 0.2.16 | A scripted comment rewrite in corpus_diagnostics.rb cut a sentence m… |
| [`024.216`](#024216-the-register-s-entry-number-is-parsed-by-six-readers-with-three-grammars-so-a-sub-numbered-entry-is-indexed-as-a-duplicate-of-its-parent) | open | 0.2.16 | The register's entry number is parsed by six readers with three gram… |
| [`024.217`](#024217-rescue-verdicts-yml-s-header-tells-a-reader-the-98-arguments-are-unargued-defaults-and-names-a-verdict-the-checker-rejects-as-the-safe-one) | open | 0.2.16 | `rescue_verdicts.yml`'s header tells a reader the 98 arguments are u… |
| [`024.218`](#024218-six-isolated-agents-branched-from-the-wrong-commit-and-the-evidence-was-deleted-before-it-was-checked) | fixed | 0.2.15 | Six isolated agents branched from the wrong commit, and the evidence… |
| [`024.R1`](#024R1-rails-specific-behaviour-has-no-explicit-boundary-roadmap-1-0-0) | open | 1.0.0 | Rails-specific behaviour has no explicit boundary (roadmap, 1.0.0) |
| [`024.R2`](#024R2-argument-type-checking-done-0-2-0) | done | 0.2.0 | Argument *type* checking (done, 0.2.0) |
| [`024.R3`](#024R3-feature-parity-roadmap-measured-against-pylance) | open | unscheduled | Feature parity roadmap, measured against Pylance |
| [`024.R4`](#024R4-only-one-platform-is-published-or-verified-roadmap-1-0-0) | open | 1.0.0 | Only one platform is published or verified (roadmap, 1.0.0) |
| [`024.R5`](#024R5-a-reopened-gem-class-still-looks-closed-done-0-1-7) | done | 0.1.7 | A reopened gem class still looks closed (done, 0.1.7) |
| [`024.R6`](#024R6-reading-an-instance-variable-that-is-never-assigned-done-0-2-0) | done | 0.2.0 | Reading an instance variable that is never assigned (done, 0.2.0) |
| [`024.R7`](#024R7-index-what-the-gems-actually-define-and-keep-it-fresh-roadmap-0-3-0) | open | 0.3.0 | Index what the gems actually define, and keep it fresh (roadmap, 0.3… |
| [`024.R8`](#024R8-completion-does-nothing-until-you-type-a-dot-done-0-2-0) | done | 0.2.0 | Completion does nothing until you type a dot (done, 0.2.0) |
| [`024.R9`](#024R9-this-register-outgrew-its-file-and-0-3-0-moves-it) | open | 0.3.0 | This register outgrew its file, and 0.3.0 moves it |

---

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


## 024.13 A reopened core class looks closed, in both directions (0.3.x)

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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


## 024.18 The unassigned-`@ivar` check cannot enumerate what it needs to

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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


## 024.19 The argument-type check judges against a class the receiver is not

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.20 `contains?` treats an exclusive end offset as inclusive

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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


## 024.22 The unassigned-`@ivar` check is silent in an application `rails new` produces

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

**Area:** `core/lib/ovallsp/server.rb` (`document_symbol_result`)

`attr_accessor :a, :b, :c` declares six methods, all at the same source
range, so the outline shows six children with byte-identical `range` and
`selectionRange` on one line. The names are right and each is genuinely a
method, so this is noise rather than a wrong answer — but an outline is
read by eye and six identical ranges read as a bug.

**Direction:** either group the methods a single macro call declares under
one outline node, or narrow each declaration's `selectionRange` to its own
symbol argument. The second would also give 024.28's rename something to
edit.


## 024.28 Rename refuses on a macro-declared method rather than editing it

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
```

Refusing is the deliberate behaviour as of 0.1.15; what is open is that
refusing is not the end state.

**Area:** `core/lib/ovallsp/rename/planner.rb`

`attr_accessor :name` declares `name` and `name=` at a symbol argument,
not at an identifier token, so there is nothing for an in-place edit to
rewrite. 0.1.14 emitted a `WorkspaceEdit` that renamed every call site and
left the declaration behind, producing a file that does not run; 0.1.15
refuses instead, which is what `#prepare`'s own comment had always
claimed happened.

The reason reaches the Core log only. `prepare` answers `null`, so the
editor shows its own "cannot be renamed" message and never asks for the
edit; nothing in this codebase sends `window/showMessage`. The W4 row's
E2E example calls `textDocument/rename` directly and asserts an empty
edit set, so the refusal is verified and the *explanation* is not.

Refusing is correct and is not the end state. The same applies to `enum`,
`scope` and `delegate`, and has since those shipped.

**Direction:** give a macro-declared declaration a `name_location`
covering its symbol argument, so `attr_reader :name` can be rewritten to
`attr_reader :title`. The writer is the hard half: `name=` and `name` are
one token in the source, so renaming `name=` to `title=` has to write
`:title`, not `:title=`. That asymmetry is why this is its own entry
rather than a line in 0.1.15.


## 024.29 Two features were written for 0.1.15 and cut from it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing shipped either way. What is open is whether these are worth
  building at all, which is a question about a future release rather than
  about anything a user can see today.
target: 0.2.15
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

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


## 024.37 The argument-type check reports nothing on measured real Ruby

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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
target: 0.2.15
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


## 024.39 `LocalInferencer` keeps per-request state, and 0.2.0 gave it a second thread

```yaml
status: open
kind: defect
user-visible: no
target: 0.2.15
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


## 024.40 Every `argument-count` report on the measurement corpus is false

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

**Still open, and the entry's title is now the wrong question.** The
check reports nothing at all on 2,095 files of real Ruby, which is the
state `024.37` describes for the argument *type* check — not a precision
of zero, a precision that is undefined. What the 0.2.1 entry asked for is
still not done: **measure it on a real application**, where the classes
are the user's own and declared, rather than on gems whose dependencies
are absent. Until that is run, nothing here says whether G5 catches a
real mistake.


## 024.41 Typing a `.` reports a method on the *next* line

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

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


## 024.42 An RBS signature label says `Unknown` where RBS says `self`, and leaks method type variables

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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


## 024.43 Signature help answers nothing for a receiverless stdlib call

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

**Area:** `core/lib/ovallsp/server.rb` (`method_signature_help`),
`core/lib/ovallsp/semantic/query_service.rb` (`signature_owners`)

`puts(` answers `{signatures: []}` while bare-prefix completion offers
`puts` from its own Kernel source. The receiverless path resolves the
enclosing `self` and asks its ancestor chain; `lookup_owners` walks what
the workspace declares, and Kernel is not in it — so every Kernel method
called the way Ruby actually calls them has no signature help.

Round 22 found S1's receiverless half, round 23 fixed it, and this is
S2's: the same row shape, one release later, for the stdlib source
instead of the workspace one.

**Direction:** the receiverless chain should end in `Kernel` the way
`PrefixCompletion#kernel_methods` already does — one source of "what a
receiverless call can reach", read by both, rather than each deciding.


## 024.44 A partial's local is not resolved, and C11's stated basis names it

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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


## 024.45 Re-analysis after a keystroke is seconds on a large file, against a stated 300 ms

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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


## 024.47 A namespaced class named after a core class loses its diagnostics, and the readers disagree about a shadowed literal

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

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
target: 0.2.15
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

**Why it is not a defect today.** The update calls are spread across four
sites, each touching a different subset, and each is currently right for
its own reason rather than by construction:

| site | touches | why it is safe |
|---|---|---|
| `ColdIndexer#index_file`'s direct path | workspace + hierarchy only | unreachable from `Server`, which always supplies `on_summary` and routes to `#apply_file_summary` |
| `Server#apply_file_summary` | all four (references via a dirty mark) | the complete path |
| `Server#apply_plugin_context` | three, and skips the generated-method write when the fact list is empty | a plugin uri is written once at boot and never re-indexed, so there is never a previous entry to clear |
| `Server#remove_index_contribution` | all four | the complete path |

Two of those four are safe because of a fact about their *caller*, not
because of anything the stores enforce. A fifth writer added without
noticing would be the failure.

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


## 024.63 The dispatch layer owns view inference, and it has broken the query layer's one guarantee twice

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Both times this structure produced a user-visible symptom the symptom
  was fixed, and no disagreement is known to be live today. What is
  recorded is that the guarantee is upheld by four call sites each
  remembering to do the same thing, and that the last release broke it
  while fixing it. The entry is about the second occurrence, not about a
  present fault.
target: 0.2.15
```

**Area:** `core/lib/ovallsp/server.rb` (roughly 1580–2004, and
`#receiver_type_before_dot` at 2735–2766),
`core/lib/ovallsp/semantic/query_service.rb`

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
assembled by `Server` and fetched independently at four places —
`#explain_type_in_view` (1584), the `@`-name list inside
`#assigned_ivars_for` (1666), `#receiver_type_before_dot` (2763), and the
diagnostics context (417, 456). The resolution is unified; its input is
not.

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

Deliberately not attempted while the 0.2.4-bound branch's release was in
flight: (1) is an architectural move, and `CLAUDE.md`'s "during a review
loop, fix; do not add" covers exactly this — a change set that grows an
architecture while being reviewed resets the round reviewing it.

**How it was found:** while describing the layering in conversation, not
by a review round, and it was the fourth reader that gave it away — the
architecture as described has one path, and the code has four.


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
of which (`024.21.1`, `024.30.1`) are synthetic fixture strings inside
`deferred_findings_spec.rb`'s own format examples — not citations of
entries, and excluded as such. Of the remaining 72, the other
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

## 024.71 One mutable Rails fixture is shared by every worker, so the suite cannot be parallelised

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing an editor user sees. The suite runs serially today and is
  green that way; what the shared fixture costs is the ability to run
  it any other way, which is a contributor and CI cost.
target: 0.2.15
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
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing a user sees, and nothing reachable today: every existing caller
  is gated. It is recorded because "every caller happens to be right" is
  the exact property 0.2.5 spent its trust work removing, and this is the
  same shape one level down.
target: 0.2.15
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
## 024.76 Fifty-four `unknown-method` reports over real gem source, and all of them false

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.77 A call to a method that does not exist is missed through a relation

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.83 The undefined-method check is loudest exactly where no Runtime Agent can answer

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.84 A constant is typed as a class object whatever it holds

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
```

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

## 024.85 `self.` completes nothing

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.86 An ivar assigned in another method has no type, except in the view

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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

## 024.87 A relation stops being a relation after one hop

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.88 Completion unions a union's members; the diagnostic intersects them

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.89 Signature help strips the parameter kinds and never advances

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.91 The undefined-method check reports on ordinary Ruby it cannot read

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

**Area:** `core/lib/ovallsp/parser_service.rb`,
`core/lib/ovallsp/diagnostics/engine.rb`

Four shapes an attack round found, all measured through the real engine,
all A/B'd against `v0.2.5` and **byte-identical** there — so none is a
0.2.6 regression, and each is a report about code that works. Over 177
files of rspec-core / i18n / psych / reline: **41 reports**, about one
per four files.

- **`Const = Struct.new(...)` then `class Const … end`** — roughly 19 of
  the 41. The members are unknown inside the reopened body:
  `Seed = Struct.new(:seed, :used)` then `def describe = "#{seed}/#{used}"`
  reports both. The same for `Data.define`, for `keyword_init: true`, and
  for a subclass of a Struct constant. This is rspec-core's whole
  `notifications.rb`. Neighbour of `024.82`, which is the same seam seen
  from resolution rather than from members.
- **`define_method` and `attr_reader` reported as unknown methods
  themselves**, inside `Class.new do … end` and
  `Module.new { define_method(…) }`. Both directions are wrong at once
  here: per `024.31` the `attr_reader :y` is *also* recorded as declaring
  a method on the enclosing class.
- **`alias` to a method from an included module.** `include Escaping`
  then `alias safe_escape escape` reports `safe_escape`. Plain `alias` to
  a `def` in the same class is fine.
- **`Kernel#trap` and `Kernel#URI`** reported missing on the user's own
  class. Probed one Kernel name per file across ~75: exactly four report
  — `trap`, `URI`, `set_trace_func`, `pretty_inspect`. `rbs-3.8.0/core`
  has no `def trap`, so this is a signature-set gap surfacing as a wrong
  report. `trap` is idiomatic in CLI and server Ruby.

And one correction to what is already recorded: the `KNOWN_LIMITATIONS`
bullet about loop-defined methods says "the name is not a literal, so the
index records nothing". A **literal** name inside a block reports too —
`[1].each { define_method(:alpha) { 1 } }` then `alpha`. 0.2.6's block
narrowing fixed the direct-in-a-class-body spelling and not this one.
Measured: 63 files / 108 sites across the installed gems and the stdlib.

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
status: open
kind: defect
user-visible: yes
target: 0.2.16
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


## 024.100 The four features answer from different code paths and disagree at one position

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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
status: open
kind: defect
user-visible: no
user-visible-note: >
  Not a defect a user meets. It is the index of the ones they do, sorted
  by how each came about rather than by where it surfaced, so a reader
  looking at any single entry below can see which class it belongs to and
  what is being built to make that class impossible.
target: 0.2.15
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

## 024.106 `module_function` and `extend self` produce nothing

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

**Narrowed in 0.2.13.** The literal-receiver half is fixed with
`024.117`: `[1].each { private }` and `1.times { module_function }` reach
the enclosing body now, which is what Ruby does, because a block
iterating a literal opens no cref frame.

**What stays open is the receiver this parser cannot vouch for.**
`SOME_CONST.each { private }` and `helper { private }` still get a frame,
and they must: `included do ... end` and `concerning ... do` run their
`private` against a different module, and without the frame every method
written after such a block was recorded private — which silently dropped
real controller actions and their ivars vanished from the corresponding
views.

Telling the two apart needs to know what the *call* does with the block,
which is `024.31` and `024.33`'s question — a block wants a receiver, not
a boolean — and remains the shape this entry is waiting on.

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

## 024.121 Nothing measures how much of this tree no test would notice changing

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Nothing an editor user meets directly. What it costs is that a
  behaviour can be broken silently, which every user-visible entry in
  this register that began "and no test noticed" was downstream of.
target: 0.2.15
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
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

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
synthetic register entry, and writing `024.999` in the spec made
`measured_claims_spec`'s pointer guard report a dangling register
citation — in the file that tests the register. Assembled from parts
instead.

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


## 024.129 No undefined-method report on a core-library receiver

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
```

**Area:** `core/lib/ovallsp/diagnostics/engine.rb`

`"hello".no_such_method`, `[1,2,3].no_such_array_method`, `42.upcase`:
nothing, in either mode, while completion at the same position knows the
receiver exactly.

`024.13` is why, and the trade is deliberate. It is recorded as its own
entry because section 0.1 names this check as half of what 1.0.0 is, and
because another editor flags the same typo.

**Was one of nine bullets under `024.90` until 0.2.14.**

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


## 024.132 A scope defined in a concern's `included do` has no type

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.16
```

**Area:** `core/lib/ovallsp/local_inferencer.rb`, `core/lib/ovallsp/models/model_registry.rb`

`included do scope :recent, -> { … } end` defines a scope on every
including class, and the engine gives it no type — so the chain from it
answers nothing.

Adjacent to `024.87`, which is about a relation losing its type after one
hop; this is about never having one.

**Was one of nine bullets under `024.90` until 0.2.14.**

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
$ ruby -e 'def kwargs(name:, size: 1, **rest) = 1; kwargs("positional")'
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
status: open
kind: defect
user-visible: no
user-visible-note: >
  The subprocess is one this extension spawned, running code from the user's own workspace, so there is no boundary crossed that the workspace itself does not already cross. What it costs is that the shape `024.73` removed elsewhere survives here.
target: 0.2.15
```

**Area:** `core/lib/ovallsp/observation/runner.rb`

`Marshal.load` on a subprocess's output. Adjacent to `024.73` and not
covered by it; the same reasoning applies and the same fix shape would —
`Plugins::Wire`'s JSON envelope.

**Documented nowhere until 0.2.14**, for the same reason as `024.134`.

**Was one of nine bullets under `024.90` until 0.2.14.**

## 024.136 A route's optional segments are detected by matching the literal `(.:format)`

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
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

## 024.137 `WorkspaceIndex#search` scans every symbol in the workspace

```yaml
status: open
kind: defect
user-visible: yes
target: 0.2.15
```

**Area:** `core/lib/ovallsp/workspace_index.rb` (`#search`)

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

## 024.138 No test mixes a schema change and a model-file change in one batch

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  A coverage gap, not a reproduced defect: the code path was read and
  judged correct when this was written, and nothing has exercised the
  combination since.
target: 0.2.15
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
that has since been done. Both sections are deleted, and this entry is
where they went.

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
countermeasure is now `core/spec/meta/duplicate_headings_spec.rb` — **no
tracked Markdown document states the same heading twice** — which is the
check both instances would have failed, and which needs no rule about how
edits are performed.

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
document describing the script kept the pre-fix command for eleven
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
  while `rspec` still exits 0. It asserts a non-zero example count
  rather than reading the exit status — `CLAUDE.md` already said to do
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

Ten checks — two scripts and eight specs — enumerated their input with
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
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. What it costs is that the file a session reads first can
  state something the file it paraphrases has since corrected, and
  nothing compares them.
target: 0.2.15
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
would shrink in 0.2.14. It grew by 15 words, and the assertion sat in
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


## 024.151 A check can be disabled, and no check notices

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal, and it is the largest single class this project has
  recorded: 55 confirmed instances from one review round. Nothing a
  user meets; everything this project uses to decide whether a change
  is sound.
target: 0.2.15
```

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
status: open
kind: defect
user-visible: yes
user-visible-note: >
  18 of the untargeted entries are open, user-visible defects: they are
  published to users as limitations, and no release has undertaken to
  fix them. That is a statement to a user that something is broken and
  nobody has said when it will not be.
target: 0.2.15
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
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md (lines 526-671, 1042-1380)

024.151 defers 55 open findings with the sentence "The individual breaks are recorded in `docs/design/tasks/046-0.2.14-making-the-record-true.md`", so 046 is the only place 0.2.15 can read them from. Round 3 found that round 2's 70 findings had been cut at ~400 characters mid-sentence and fixed them; commit 577704b did that and, in the same commit, wrote round 1's 18 findings and round 3's 65 finding bodies with the same cut. All 18 round-1 items are 574-643 characters and every one ends mid-token; 26 of round 3's 65 bodies do the same. The cut lands on the consequence clause and on the reproduction, which is the part a reader needs. 046:686-689 states "Recorded in full and untruncated" — true of round 2 only, and the sentence reads as a claim about the list.

**Reproduce:** awk 'NR>=526 && NR<=671' docs/design/tasks/046-0.2.14-making-the-record-true.md | grep '^- \*\*\[' | wc -l -> 18; the same piped through `sed 's/ *$//' | grep -cvE '[.!?)"`]$'` -> 18. awk 'NR>=1014' <same file> | grep -E '^ `' | sed 's/ *$//' | grep -cvE '[.!?)"`]$' -> 26 of 65. Tails: `sed 's/.*\(.\{35\}\)$/... \1/'` shows `Plugins::CURRENT_PROTOCOL_VERSIO`, `STATUS_LABELS\|STA`, `is not true of thr`. git log -S'Recorded in full and untruncated' --oneline -- <same file> -> 577704b, the same commit that added round 1's list.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.155 A register heading the entry grammar does not match is skipped rather than failed, so an entry can exist and be checked by nothing

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** `scripts/deferred_findings.rb` (`ENTRY_HEADING`, `METADATA_BLOCK`, `#headings`, `#entries`), `core/spec/meta/deferred_findings_spec.rb` ("parses every entry", "indexes every entry"), `scripts/reindex_findings.rb` (`#number_of`)

`DeferredFindings`' header comment states the rule the whole guard was rebuilt for: "An entry with no block is a failure, not a skip. The old guard silently dropped a heading it did not recognise, so an entry could be added and never checked. `parses every entry` compares the block count to the heading count for exactly that reason." It cannot do that. `parses every entry` computes `headings(deferred) - entries(deferred).keys`, and both sides are derived from the *same* pattern — `ENTRY_HEADING` and `METADATA_BLOCK` each require `024.N` followed by a literal space. A heading outside that shape is absent from both sets, so the subtraction is empty for it and the comparison is vacuous exactly where it was meant to bite. Three checks that could have caught it independently do not: `reindex_findings.rb` uses a looser pattern (`/\A## (024\.[0-9R]+)/`, no trailing space), so it happily renders an index row for the malformed entry with `?` for status and an empty title, which then makes `indexes every entry` and `is in numeric order with its index current` both pass. The result is a heading that reads as an entry to every human and to the generated index, and to no check. Note this is not 024.151's class: no check was edited or narrowed, and a coverage floor would not help, because the two readers agree with each other while both being too narrow. The fix has the shape `CLAUDE.md` calls for — the two ends must not share the assumption they are supposed to cross-check. `headings` should recognise deliberately more than `entries` does (any `^## 024\.` line), so that anything the strict grammar cannot parse shows up in the difference.

**Reproduce:** In a clone at aa1185f: `printf '\n## 024.<n>: A finding written with a colon after its number\n\nBody prose, no yaml block.\n' >> docs/design/tasks/024-deferred-review-findings.md`. Then `ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); puts (DeferredFindings.headings(md) - DeferredFindings.entries(md).keys).inspect'` → `[]`. Then `ruby scripts/reindex_findings.rb` (rewrites, adding `| [`024.<n>`](#024200-) | ? | — | |`) and `ruby scripts/reindex_findings.rb --check` → `current`, exit 0. Then from `core/`: `bundle exec rspec spec/meta/deferred_findings_spec.rb` → 37 examples, 0 failures, and `bundle exec rspec spec/meta` → 192 examples, 0 failures, 6 pending — byte-identical to the clean HEAD run. Control: the same body written as `## 024.<n> A finding` (space, no colon) fails `parses every entry`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.156 The evidence extractor recognises only .rb/.sh/.js and test:, so TypeScript tests and CI job names — the sole evidence for eight gates — are never checked

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** core/spec/meta/release_gate_spec.rb (`RELEASE_GATE_EXECUTABLE`, line 38; the dead `.test.ts` branch, line 116), docs/RELEASE_CHECKLIST.md

The Task 023 gate table's evidence column holds, by its own header, CI job names, specs, or release.sh steps. The extractor matches only a backticked path ending .rb/.sh/.js, or a backticked `test:` npm script. A citation of any other shape is not reported as unrecognised — it is silently treated as absent, and the row is reported clean. Gates 8, 9, 10 and 19.1 cite TypeScript test files as their sole evidence (versionInfo.test.ts, clientLifecycle.test.ts, workspaceTrust.test.ts), and gates 2, 3, 14 and 15 cite CI job names (`core`, `secret-scan`, `package-contents-inspection`); none is checked. So the delayed-start race test, the E1/C1→E2/C2 update test, the payload-hash test and the Workspace Trust manifest test can each be deleted or renamed with the gate that names them still green. The spec contains the evidence that this was believed covered: line 116's `next if base.end_with?("_spec.rb", ".test.ts")` can never fire, because the regex cannot produce a capture ending in `.test.ts`. This is distinct from 024.151's disable-ability class: nothing is switched off, the check runs and asserts a clean result over rows it never looked at.

**Reproduce:** ruby -e 'RE=/`([A-Za-z0-9_.\/-]+\.(?:rb|sh|js))`|`(test:[a-z:]+)`/; p "`clientLifecycle.test.ts`".scan(RE).flatten.compact' => []. Scan the whole of docs/RELEASE_CHECKLIST.md with the same regex: 15 captures, none ending .test.ts (the dead branch). Then in docs/RELEASE_CHECKLIST.md rewrite clientLifecycle.test.ts -> neverExisted.test.ts, versionInfo.test.ts -> ghost.test.ts, vscode/src/test/unit/workspaceTrust.test.ts -> vscode/src/test/unit/deletedLastYear.test.ts, and secret-scan / package-contents-inspection -> no-such-job; `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 3 examples, 0 failures. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.157 A git subprocess in a throwaway repository obeys the inherited GIT_DIR, so the suite commits to the real repository

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** `scripts/repo_files.rb`, `core/spec/meta/untracked_visibility_spec.rb`, `core/spec/meta/doc_links_spec.rb`, `core/spec/meta/release_script_guard_spec.rb`, `scripts/check_home_paths.rb`, `scripts/preflight.rb` (the `--install` hook)

Git exports `GIT_DIR` and `GIT_INDEX_FILE` to every hook. In a **linked worktree** they are absolute paths to that worktree's gitdir and index (measured, git 2.55.0); in an ordinary repository `GIT_DIR` is unset and `GIT_INDEX_FILE` is the relative `.git/index`, which is why this is invisible until someone works in a worktree. Nothing in this tree scrubs them: `grep -rn 'GIT_DIR|GIT_INDEX_FILE|GIT_WORK_TREE' scripts core/spec .github` returns nothing. `RepoFiles.git` spawns `IO.popen(["git", ...], chdir: root)`, and the three spec files that build throwaway repositories use `system("git", "-C", dir, ...)`. **`chdir:` and `-C` change the working directory; they do not override `GIT_DIR`.** So `git add -A` writes the throwaway repository's contents into the real worktree's index, and `git commit` lands a commit on the branch that worktree has checked out -- a commit that *deletes* every tracked file the throwaway repository does not have. Three things make it worse than a red suite: (1) **the suite stays green while it does this** -- `RepoFiles.list` unions `ls-files` with `ls-files --others`, and `--others` enumerates the filesystem, so it returns nearly the right answer from the wrong repository and the assertions still pass; (2) `scripts/check_home_paths.rb` enumerates through the same helper for `--tree` and runs `git log --all` in `ROOT` for `--messages`, so the public-repository privacy guard reads whichever repository `GIT_DIR` names and reports clean about it; (3) the vector is documented -- `ruby scripts/preflight.rb --install` installs exactly such a hook and `CONTRIBUTING.md` tells contributors to run it. This is `CLAUDE.md`'s "a test that deletes things, and an assertion that could not fail" returning by a different route: the path from a harmless-looking `Dir.mktmpdir` to a real repository runs through an environment variable no call site mentions, and reading either the spec or the helper alone cannot reveal it. Fix shape is the one that section already prescribes -- contain it where the spawn happens: one helper that every `git` invocation in `scripts/` and `core/spec/` goes through, unsetting `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_COMMON_DIR` and `GIT_NAMESPACE`, plus the same unset in `HOOK`.

**Reproduce:** ``` cd "$SCRATCH" && git init -q main0 && cd main0 git config user.email t@e.com && git config user.name T mkdir src && echo precious > src/important.rb && git add -A && git commit -qm init git worktree add -q -b featurex ../wt G="$PWD/.git/worktrees/wt" cd /path/to/OvalLSP/core GIT_DIR="$G" GIT_INDEX_FILE="$G/index" bundle exec rspec spec/meta/untracked_visibility_spec.rb # => 3 examples, 0 failures git --git-dir="$G" log --oneline featurex # => a second commit "one" git --git-dir="$G" show --stat HEAD # => `<probe>.md` | 1 + # src/important.rb | 1 - ``` Those two variables are exactly what git sets for a pre-commit hook in a linked worktree -- confirm with a hook that prints them (absolute in a worktree, `GIT_DIR` empty and `GIT_INDEX_FILE=.git/index` in a normal repository). Under the same environment `bundle exec rspec spec/meta/doc_links_spec.rb` fails 3 of its examples, so the hook also rejects the commit for a reason that is not about the commit. `git worktree list` on this repository currently shows seven linked worktrees under the scratch directory, so the precondition is this project's ordinary working practice, not a hypothetical.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.158 The executed PAT-mode example passes on a release.sh that only warns, because its exit status comes from a later check misreporting a non-repository as dirty

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** `core/spec/meta/release_script_guard_spec.rb` lines 158-182, `vscode/scripts/release.sh` lines 51-56 and 78-84

The PAT-mode example exists because "semantic mutations are invisible to any text match", and it asserts only `status.success? == false` plus `output.include?("readable beyond its owner")`. Neither is tied to the PAT check. Demote the refusal to `if [ "${OVALLSP_STRICT_PAT_MODE:-0}" = "1" ]; then exit 1; fi` and soften the echo to a warning, and the example still passes: the message is still printed, and the non-zero status comes from the clean-tree check further down. The mechanism is a second defect in its own right — the fixture's REPO_ROOT is the tmpdir's parent, not a git repository, so `git diff --quiet` fails with "not a git repository", `if ! …` reads that failure as truth, and release.sh announces "the tracked tree has uncommitted changes" about a tree it could not read. A failure to *ask* is turned into an assertion about the user's tree, which is CLAUDE.md's swallowed-failure rule arriving from the other side. The text half is no protection either: `block_containing(/8#077/)` stops at the first `^\s*fi\s*$`, which after the demotion is the nested one, so the unreachable `exit 1` is still inside the window. Fix: assert the refusal happens *at* that check (exit before any git call, or `expect(out).not_to include("uncommitted changes")`), and make the clean-tree condition distinguish "git says dirty" from "git could not answer".

**Reproduce:** Scratch mirror as above. Replace release.sh's `exit 1` on line 55 with ` if [ "${OVALLSP_STRICT_PAT_MODE:-0}" = "1" ]; then` / ` exit 1` / ` fi`, and change line 52's message to `warning -- $PAT_FILE is mode $PAT_MODE -- readable beyond its owner.` → 10 examples, 0 failures. Then run the fixture by hand: `mkdir -p fx/scripts; cp release.sh fx/scripts/; printf tok > fx/.vsce-pat.local; chmod 644 fx/.vsce-pat.local; fx/scripts/release.sh; echo $?` → prints the warning, then "release.sh: the tracked tree has uncommitted changes" and "fatal: not a git repository", exit 128.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.159 The measured-claim marker and the number a reader sees are separate strings, so the prose can say anything while the marker verifies

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.15
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, and the `matches what the tree actually says` example), `docs/design/docs/02-architecture.md` (threading section)

`claims` captures the integer inside `[measured marker for name]` and compares that to the deriver. The number in the sentence it annotates is an unrelated hand-typed string that nothing reads. So the guarantee as literally stated holds — the marker's value is re-derived every suite run — while the thing the guarantee exists for, the number a reader takes away, is free to rot, and rots invisibly because the marker beside it reads as proof that it was checked. This is the file's own stated failure mode, 'the check passes for a reason other than the one it states': `documented_counts_spec`, the precedent cited in this file's header, does not have this shape — `DocumentedCounts.stated(document)` (scripts/documented_counts.rb:42) compares against the number as written in the prose, which is the form that actually holds. The architecture document already shows the wider version: the same count is written three times in the threading section — line 269 「現在 31 箇所あり」, line 291 「上の 31 箇所のうちの1つ」, line 300 「上の 31 箇所に」 — and exactly one carries a marker; the other two are precisely the unmarked hand-typed numbers the marker mechanism was built to abolish, in the section whose stated purpose is that it stopped contradicting the code. Fix shape (from the finding): require the marker's value to appear in the prose it annotates, the way `DeferredFindings#documents?` (scripts/deferred_findings.rb:182) insists an anchor's line carry content in front of it — noting that here the marker sits on the line *after* the sentence it belongs to, so a same-line rule alone would not fit the one live instance.

**Reproduce:** From the repo root: `perl -i -pe 's/現在 31 箇所あり/現在 999 箇所あり/' docs/design/docs/02-architecture.md` (line 269; leaves the marker on line 270 at 31), then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures, with the threading section now reading 「`core/lib` には現在 999 箇所あり」. `git checkout -- docs/design/docs/02-architecture.md`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.160 Counts in 046 that describe this tree carry no basis, are not marked, and several are stale at HEAD

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md (lines 3-4, 25-30, 42, 131, 278, 295, 336, 421)

The file's header says "Measured at `6bc31b9`. Every count below was re-derived at that revision." The file contains zero `<!-- measured: -->` markers, nothing re-derives any of its numbers, and at HEAD several are wrong: (a) :25 "66 of its 88 resolved entries" — 90 at HEAD (88 was true only at 8f1d4f4..577704b, 74 at 6bc31b9); the 66 still holds; (b) :27 "Exactly one is cited from nowhere outside it" — three at HEAD (024.144, 024.146, 024.152); (c) :421 "fires on zero of 74 entries" — a second, different denominator for the same quantity in the same file; (d) :295 "+6,256 / -4,588 — a net increase of 1,668 lines" — true at 577704b, now +7,157/-4,731, net +2,426; (e) :42 "1,753 lines an agent must read at session start" — the plausible set sums to 1,514 and no set is defined; (f) :131 "249 edits across 41 files" — `0.3.0` occurs 151 times across 35 tracked files; (g) :30/:334/:336 "7 sentences repeat", "52.7% comment", "47% of the file" — no method stated for any; (h) :278 records make-final-review-bundle.sh at 918 while the ledger's own 3,975 total is only reachable using git's 919. Round 3 corrected six numbers in this file and introduced (a), (b) and (d) in doing so.

**Reproduce:** grep -c '<!-- measured: -->' on the file -> 0. ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); puts DeferredFindings.resolved(md).keys.length' -> 90 (74 at 6bc31b9, 88 at 577704b). git diff --shortstat main..HEAD -> 7157/4731. wc -l CLAUDE.md AGENTS.md README.md docs/design/docs/01-product-requirements.md docs/DOCUMENTATION_MAP.md -> 1514. git grep -c '0\.3\.0' -- . ':!core/vendor' ':!vscode/node_modules' -> 35 files / 151 lines. git show main:make-final-review-bundle.sh | grep -c '' -> 919 vs wc -l 918.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.161 046's round-3 correction states that the "4,000 lines of revert" phrase "is removed"; the phrase is still the file's closing sentence

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:302-303, :1405-1406

Round 3 corrected the deletion ledger and closed the correction with: "The closing phrase \"this change set is 4,000 lines of revert\" is not what the diff shows and is removed." The phrase was not removed. It is the last clause of the document (:1405-1406), under "Two rules over the whole thing": "...and this change set is 4,000 lines of revert." So the file now contains both a false statement about the change set and a statement that it was deleted — a correction that records work it did not do, in the release whose title is making the record true. The diff is +7,157/-4,731, a net increase of 2,426 lines.

**Reproduce:** grep -n '4,000 lines of revert' docs/design/tasks/046-0.2.14-making-the-record-true.md -> two hits: :303 (saying it is removed) and :1405 (the phrase itself). git diff --shortstat main..HEAD -> 105 files changed, 7157 insertions(+), 4731 deletions(-).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.162 046's recorded departure from the `drive` round rests on a false enumeration of the change set

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:497-502, :1381-1386

041 asks that one review round use `drive`. 046 records a departure justified by "This change set alters no engine answer — the only `core/lib` edits in the range are two comment rewrites and one deleted tombstone comment, and the corpus is not consulted by anything that changed". Both halves are false as stated. `core/lib` has 16 changed files (+38/-47): one comment rewrite (receiver_resolution.rb), one deleted tombstone (engine.rb), and thirteen one-line citation repoints plus query_service.rb. And the corpus consumer changed in this very change set: scripts/corpus_diagnostics.rb is +125/-4 with a new 119-line spec (C8), and 046's own C8 note records that building it exposed a live hole where a mistyped path became a corpus of one — exactly what a `drive` round would have exercised. The conclusion (no engine answer changed) survives: zero non-comment, non-blank changed lines in core/lib. The defect is that a departure from a mandatory cadence rule is recorded twice, restated "because it must be re-checked each round", and rests on an enumeration nobody re-checked.

**Reproduce:** git diff --numstat main..HEAD -- core/lib | wc -l -> 16. git diff main..HEAD -- core/lib | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-][[:space:]]*#' | grep -vE '^[+-][[:space:]]*$' | wc -l -> 0. git diff --numstat main..HEAD -- scripts/corpus_diagnostics.rb core/spec/meta/corpus_diagnostics_spec.rb -> 125/4 and 119/0.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.163 046's round-2 header asserts every attacker worked in a clean tree, and 046's own recorded findings say the tree was dirty and changing throughout

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:675-677, :762-764, :1378, :1384, :1386

The round-2 header states "Every attacker worked in a clone or reverted, and the tree was verified clean and at the same HEAD afterwards", and commit 54b7274's message repeats it. Four findings recorded in the same document say the opposite: a round-2 [medium] entry ("Concurrent agents left the working tree modified; the dirty set changed three times during one review round", naming a `continue-on-error: true` added to ci.yml's suites-ran job and RELEASE_CHECKLIST test filenames rewritten to files that do not exist, both later reverted, while an attacker was measuring), and three round-3 agents each reporting five modified tracked files at session end that were none of theirs. CLAUDE.md's measurement rule names this hazard explicitly ("Never run this hunk-by-hunk sweep while another agent is mutating the same working tree. Concurrent mutation invalidates both results. Sequence them."), and the round-2 finding says it made the hunk-level half of that reviewer's work unsafe to perform. The header is the sentence a later reader uses to decide how much round 2's results are worth.

**Reproduce:** sed -n '675,677p' docs/design/tasks/046-0.2.14-making-the-record-true.md against sed -n '762,764p' of the same file; grep -n 'Working tree was NOT clean\|dirty set changed three times\|already dirty when this session started' on the same file -> four hits contradicting the header.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.164 046 states finding totals whose stated dispositions do not account for them

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:10-13, :691-694, :1042-1380

Three places state a finding total and then fail to account for it. (1) The opening audit: "Nine auditors over disjoint areas produced 122 findings; each non-trivial one was then given to a second agent whose instructions were to refute it. 15 survived adversarial check, 9 were refuted, 28 low-severity carried forward" — 15+9+28 = 52, and the other 70 have no stated disposition anywhere. (2) Round 2: "15 are fixed in this release, named in the commits that fixed them. The remaining 55 are open under 024.151" — none of the 70 items carries a fixed/open marker, so the split is unverifiable from the record and a reader picking up 024.151 in 0.2.15 gets 70 items of which 15 are already done and no way to tell which. (3) Round 3: 63 findings in six subsections plus 37 incidental, with no disposition statement at all. 024.151 is the deferral that points here, so this is the cost paid by the release scoped against it.

**Reproduce:** sed -n '8,14p' docs/design/tasks/046-0.2.14-making-the-record-true.md and add the three figures -> 52 of 122. awk 'NR>=672 && NR<=1013' <same file> | grep -c '^- \*\*\[' -> 70, with no fixed/open marker or strike-through on any. awk 'NR>=1014' <same file> | grep '^#### ' -> six subsections summing to 63, none with a disposition line.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.165 046 keeps 138 acceptance boxes on the stated ground that no box has ever been ticked; 56 are ticked, 13 of them in a file this change set edited

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:319-321, docs/design/tasks/008.5-runtime-and-index-corrections.md:90-102

The "What is kept" section keeps all 138 unticked acceptance boxes in tasks 001-022 with: "No box has ever been ticked in this repository's history; they are stage milestones, not tracked obligations." The 138 re-derives exactly. The justification does not: 56 boxes are ticked across nine task files, and 13 of them are in docs/design/tasks/008.5-runtime-and-index-corrections.md under `## 完了基準` — inside the stated 001-022 range, and in one of the two files this change set edited. The other 43 are across eight 023.* files. Ticking is established practice, so the argument for keeping 138 empty boxes rests on a false fact. The decision may still be right; the reason given for it is not.

**Reproduce:** grep -rc -- '- [x]' docs/ | grep -v ':0$' -> 9 files, 56 total, 13 in 008.5. grep -h -- '- [ ]' docs/design/tasks/00*.md docs/design/tasks/01*.md docs/design/tasks/02[0-2]*.md | wc -l -> 138. sed -n '89,103p' docs/design/tasks/008.5-runtime-and-index-corrections.md shows the 13.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.166 Two rows of 046's checks table describe checks that were built differently, and the "changed shape" list omits one

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:365-366, :370-372, scripts/reindex_findings.rb:54-66, scripts/corpus_diagnostics.rb:81-89

The checks table is what a reader auditing the release compares the built checks against, and two of its nine rows do not describe what shipped. C4's row says "extract `DeferredFindings` into `scripts/`; delete `metadata_of` **and its false comment**" — `metadata_of` is still defined at scripts/reindex_findings.rb:54, called at :66, and asserted at core/spec/meta/deferred_findings_spec.rb:113-114; it was rewritten as a one-line delegation to `DeferredFindings.entries` and its comment replaced with a true one, which is a better outcome than deletion but is not the row. The section immediately below, "Four changed shape once built, and the changes are the part worth reading", lists C2, C6, C7 and C8 — C4 changed shape and is absent. C8's row says the check fails on "`026`'s three recorded false results" while the header comment this same change set added to scripts/corpus_diagnostics.rb says "`026-0.2.1-review-loop.md` lists five" and enumerates five; CLAUDE.md is consistent with five.

**Reproduce:** grep -rn 'metadata_of' scripts/ core/spec/ -> 4 hits, definition at scripts/reindex_findings.rb:54. sed -n '365,372p' docs/design/tasks/046-0.2.14-making-the-record-true.md against sed -n '81,89p' scripts/corpus_diagnostics.rb and CLAUDE.md's "A measurement is a claim" section.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.167 046's three review rounds record no per-place tracking, so CLAUDE.md's same-place rule cannot be applied and was not

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:490-1380

CLAUDE.md's "Two rounds in a row on the same place" rule requires tracking, per round, which code each finding is about, and — the first time a place is found twice in a row — a mechanical countermeasure of a different shape rather than a third hand-fix, with a rollback and a register entry if the place is found again after that. 046's review-rounds section records no per-place tracking and never invokes the rule; the only mentions in the file are at :38 (about 024.15/024.47 in CLAUDE.md, not this release) and inside one round-2 finding body at :940. At least two places qualify across three consecutive rounds. release.sh's clean-tree refusal: round 1 fixed C6's self-naming hole, round 2 filed three findings against the same `block_containing` decision (one noting the rule applies), round 3 confirms at :1042 that the whole refusal block is still deletable with release_script_guard_spec at 8 examples, 0 failures. scripts/check_doc_links.rb: round 1 (105 relative links outside the check, a rescue that reported nothing), round 2 (SKIP an unpinned constant), round 3 (the "all 19 dangling citations live in source comments" claim false, and the SHORTHAND count wrong).

**Reproduce:** grep -in 'same place\|same-place\|Two rounds in a row' docs/design/tasks/046-0.2.14-making-the-record-true.md -> three hits, none in the review-rounds section's own bookkeeping. Then read :940 and :1042 against round 1's release_gate_spec finding at :617, and the three rounds' check_doc_links.rb findings at :644, :724 and :1040.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.168 The ledger's reason for keeping 05-protocol.md's section numbering counts four source comments where one exists, and the claim was copied into the shipped document

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** docs/design/tasks/046-0.2.14-making-the-record-true.md:283, docs/design/docs/05-protocol.md:198

The deletion ledger's row for 05-protocol.md gives as its reason for rewriting §6/§8 in place rather than renumbering: "The file stays — four source comments lean on §7." Exactly one does. `core/lib` holds four citations of 05-protocol.md, and only agent_process_manager.rb:16 names a section; the other three (runtime_agent/agent.rb:9, :107, :165) cite the file generally and two of them name `agent/snapshot` and `agent/model`, which are §4 subsections. Read the other way, `core/lib` holds four occurrences of the string "section 7" and three of them name docs/03-semantic-engine.md §7.1/§7.3 — a different document whose numbering 05-protocol.md cannot break. Either way the count is one. The measurement is a grep over an undifferentiated string, which is the same mistake as C6's first version that this release records as "the mistake it audits", and the argument has since been copied into the shipped design document at 05-protocol.md:198 ("番号を詰めると `section 7` を指すソースコメントが壊れる"), so it now stands in two places.

**Reproduce:** grep -rn '05-protocol' core/lib -> 4 hits, one naming a section. grep -rn 'section 7' core/lib -> 4 hits, three naming docs/03-semantic-engine.md. sed -n '283p' docs/design/tasks/046-0.2.14-making-the-record-true.md and grep -n '番号を詰める' docs/design/docs/05-protocol.md.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.169 `check_doc_links.rb`'s CITATION comment describes anchor/punctuation stripping that no caller performs

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_doc_links.rb:79-80

The comment above the CITATION constant reads "What a documentation path looks like, inside backticks or a Markdown link. Anchors and trailing punctuation are stripped by the caller." Nothing strips anything. The two callers of the match are the scan loop (which takes `Regexp.last_match[:path]` verbatim) and `resolve`/`candidates_for`, neither of which touches the string; the effect the comment describes is produced by CITATION's own character class `[A-Za-z0-9._-]+\.md`, which simply stops before an anchor. The comment names a responsibility that lives somewhere it does not, in the file whose whole subject is that a stated guarantee has to be the guarantee. A maintainer acting on it would either add stripping that already happens or widen the class trusting a caller to clean up. (The neighbouring RELATIVE_LINK regex does consume an anchor, `(?:\#[^)]*)?`, which is likely where the belief came from — but that is the pattern, not the caller, and it is a different constant.)

**Reproduce:** sed -n '79,80p' scripts/check_doc_links.rb, then read the scan loop at :231-245 and `resolve`/`candidates_for` at :168-180 — no `sub`, `gsub`, `chomp`, `delete_suffix` or `split` on `raw` anywhere between the match and the file test.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.170 The doubled-entry check counts `**Area:**` lines, so a body duplicated anywhere below that line is invisible

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/deferred_findings_spec.rb` ("states each entry's Area exactly once, so a doubled body cannot pass"), `docs/design/tasks/024-deferred-review-findings.md`

The check exists because a scripted edit doubled 024.69's entire body and every other check stayed green. It detects that by counting `**Area:**` occurrences per entry — which detects duplication only when the duplicated slice happens to contain the Area line. The 024.140 incident's own diagnosis is "a `String#find` that returned -1 when its terminator was absent, so a slice meant to end at a paragraph ran to the end of the entry": a class of bug whose slice boundary is wherever the terminator search failed, which for a register entry is far more often somewhere in the body than above the Area line, since the Area line sits in the first few lines of every entry. The countermeasure is therefore roughly one line wide against a defect that can start anywhere in a 200-line entry, and `CLAUDE.md`'s rule is explicit that a regression test for the specific instance is not a countermeasure. A content-based test — no paragraph of an entry appearing twice, or a normalised-body hash — is the shape that matches the defect.

**Reproduce:** In a clone at aa1185f, take 024.13's block, find the newline after its `**Area:**` line, and append everything from there to the end of the block a second time (2,515 characters). Then `ruby scripts/reindex_findings.rb --check` → `current`, exit 0, and from `core/`: `bundle exec rspec spec/meta/deferred_findings_spec.rb` → 37 examples, 0 failures. Control: append from just after the *heading* instead, so the Area line falls inside the duplicated slice — the same run fails with `entries not stating exactly one Area: 024.13 (2 Area lines)`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.171 Three entries closed in 0.2.14 state as done something HEAD contradicts, two of them naming a countermeasure that was never built

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (024.139, 024.141, 024.143), `docs/design/tasks/008.5-runtime-and-index-corrections.md`, `docs/design/tasks/008.6-agent-and-index-hardening.md`, `docs/DOCUMENTATION_MAP.md`, `scripts/preflight.rb`

0.2.14 closed these three entries with a sentence about what is now true, and in each case HEAD says otherwise. (1) 024.139: "Both sections are deleted, and this entry is where they went" — `## 残課題` is still at 008.5:104 and `## 残っているKnown Issue` still at 008.6:89; their items were replaced by pointers to the register, which is a reasonable outcome but is not deletion. It then names its countermeasure — "046's C4 ... so a check can assert that `docs/design/tasks/*.md` other than 024 carry no findings section of their own" — and C4 as executed only moved `DeferredFindings` into `scripts/`; nothing anywhere asserts anything about other task documents, so a third task file growing its own findings section is still invisible. (2) 024.141: the instance is genuinely fixed, but its diagnosis is that the class is "a fix applied at the place that runs and not at the place that tells a person what to run", and it says `DOCUMENTATION_MAP` has no row for "the release procedure changed" and that 046's C6 is where that goes. C6 is a different check (every script in RELEASE_CHECKLIST's evidence column must be invoked by something), and the map still has no such row, so editing `vscode/scripts/release.sh` triggers no documentation obligation. (3) 024.143 lists as one of preflight's two needed properties "It asserts a non-zero example count rather than reading the exit status" — the exact assertion 024.148, released in the same release, records as unable to fail because a skipped example is still an example, and which preflight no longer uses for that check. A reader who lands on 024.143 is told the superseded rule is the shipped one. The common cause is that an entry's closing paragraph is prose nothing re-reads, and the countermeasures it names changed shape after it was written. The direction: closing an entry includes re-deriving the sentence that closes it, and a countermeasure named in an entry has to be pointed at by number or path so a reader can check it exists.

**Reproduce:** `grep -n '^## 残課題' docs/design/tasks/008.5-runtime-and-index-corrections.md` and `grep -n '^## 残っているKnown Issue' docs/design/tasks/008.6-agent-and-index-hardening.md` — both hit. `grep -rn 'findings section' core/spec/meta scripts` and `grep -rln '残課題' core/spec scripts` — no matches. `grep -n 'PUBLISHING' docs/DOCUMENTATION_MAP.md` — two hits, both about install steps and the site, none about the release procedure; read 046 line 365 for what C6 actually is. Read 024.143's first bullet beside 024.148's "a skipped example is still an example" paragraph, then `scripts/preflight.rb` lines 44-67 and 83-92: `SUITES_RAN` delegates to `CheckSuitesRan.complaints`, and `NON_EMPTY_SUITE` is attached only to the full-suite check.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.172 Four counts derived about this tree are wrong and unmarked, one of them inside the entry about a record that drifted

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `docs/design/tasks/024-deferred-review-findings.md` (024.141, 024.147, 024.150), `core/spec/meta/measured_claims_spec.rb`, and commit `dc9b044`'s message

`measured_claims_spec.rb` exists because "a number in a document that describes this tree is a claim about it", and it is opt-in by design — it "cannot know which numbers in prose are claims". Four numbers written during 0.2.14 fail re-derivation, and none carries a marker. (a) 024.147 opens "Ten checks — two scripts and eight specs — enumerated their input with `git ls-files`": at 23196a8^ there were nine such files, seven specs and two scripts; the eighth spec at HEAD, `untracked_visibility_spec.rb`, was created by that very commit and cannot have enumerated anything the old way. "Ten" survives as a count of *call sites* (release_gate_spec has two), which is also what makes the later "all ten sites use it" true — the breakdown is what is wrong, in the entry whose subject is checks answering a different question from the one they claim. (b) 024.141's "What makes this its own entry rather than a typo" paragraph rests on "kept the pre-fix command for eleven releases": the fix landed in e9d09d5 at version 0.1.3, and 25 releases were published between there and 0.2.13; eleven is the 0.1.x line alone. (c) 024.150 says "046 asserted that the paraphrase would shrink in 0.2.14. It grew by 15 words": AGENTS.md is 1463 words on main and 1562 at HEAD, a growth of 99. +15 was true at 8f1d4f4^ only, and the same commit that wrote the claim took the file to 1562 — a present-tense, undated, unmarked number in the entry that exists because a record drifted, in the release whose headline fix was to date 037's register count as `register-open-defects@f67e743e6eec`. (d) dc9b044's message opens "919 lines that RELEASE_CHECKLIST named as the enforcement for seven numbered gates": five numbered rows plus one prose line named it, and 046 line 278, fe05e3f and 0e84e1a all say five — the outlier is the commit whose whole argument is a gate-by-gate account of what still covers each row. That last one lives in an immutable commit message and can only be corrected by a note, which is a reason to record it rather than to drop it. The direction is not four corrections: it is that a count stated about this tree in the release record gets a `<!-- measured: -->` marker and a deriver, or a `@<rev>` date, and that a number in a commit message describing a count should be derived before the commit is written.

**Reproduce:** (a) `git grep -l 'ls-files' 23196a8^ -- 'scripts/*' 'core/spec/*' | wc -l` → 9; `git log --oneline --diff-filter=A -- core/spec/meta/untracked_visibility_spec.rb` → 23196a8. (b) `git log --format=%h -S packagePath -- vscode/scripts/release.sh | tail -1` → e9d09d5; `git show e9d09d5:vscode/package.json` → 0.1.3; count the published rows in `docs/RELEASE_ARTIFACTS.md` from 0.1.3 to 0.2.13 → 25 (0.1.14/0.1.15 appear only in the second table, which records that no VSIX was built for either). (c) `git show origin/main:AGENTS.md | wc -w` → 1463; `git show HEAD:AGENTS.md | wc -w` → 1562; `git show 8f1d4f4^:AGENTS.md | wc -w` → 1478. (d) `git show dc9b044^:docs/RELEASE_CHECKLIST.md | grep -n 'make-final-review-bundle'` → lines 33, 38, 39, 51, 53, 54 — one prose line and five numbered rows; `sed -n '278p' docs/design/tasks/046-0.2.14-making-the-record-true.md` → "five `RELEASE_CHECKLIST` rows".

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.173 The shipped-target guard sees only `kind: defect`, and `released-in:` is written by 16 entries and read by no check

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/deferred_findings.rb` (`#open_entries_targeting_a_shipped_release`, `#open_defects`, `KNOWN_KEYS`), `core/spec/meta/deferred_findings_spec.rb` ("has no open entry naming a release that has already shipped"), `docs/design/tasks/024-deferred-review-findings.md`

024.124 states the guard as failing "on an **open** entry whose target is in that table", and says the mechanism means "the next release cannot inherit the situation the way three have". The implementation is narrower in both directions. `open_entries_targeting_a_shipped_release` is built on `open_defects`, which additionally filters `kind == "defect"`, so an open `friction` or `roadmap` entry naming a shipped release passes silently — latent today, since the five open non-defect entries are all roadmap and none targets a published version, but it is exactly the state 024.124 was written to make unreachable. The mirror direction is unguarded outright: `released-in` sits in `KNOWN_KEYS` and its only reader anywhere is `reindex_findings.rb:69`, where it is a display fallback for the index's release column. Nothing validates it. Sixteen entries currently assert `released-in: 0.2.14` while `core/lib/ovallsp/version.rb` is still `0.2.13` and `docs/RELEASE_ARTIFACTS.md` has no 0.2.14 row — so if this branch ships under any other number, the register re-creates 024.124's situation in the key that was added to prevent it, and no check can say so. The fix is to run the shipped-release comparison over all open entries regardless of kind, and to give `released-in` a reader: it must name a version `RELEASE_ARTIFACTS.md` records as published.

**Reproduce:** Read `scripts/deferred_findings.rb:112-119` beside `#open_defects` at line 99. `grep -rn 'released-in' core/spec/meta scripts` → three hits: a prose comment in the spec, the `KNOWN_KEYS` list, and `reindex_findings.rb:69`. Then `ruby -r./scripts/deferred_findings -e 'md=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); e=DeferredFindings.entries(md); puts e.count{|_,f| f["released-in"]=="0.2.14"}'` → 16, against `grep VERSION core/lib/ovallsp/version.rb` → `0.2.13` and `grep -n '^| 0\.2\.1' docs/RELEASE_ARTIFACTS.md`, whose newest row is 0.2.13.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.174 A relative Markdown link beginning `docs/` is resolved against the repository root instead of the citing file's directory

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (line 249, the `next if raw.start_with?("docs/")` shortcut in the relative-link pass)

The relative-link pass, added in 0.2.14 round 1 precisely because relative links resolve against the citing file's own directory, hands every link whose text begins `docs/` back to the CITATION pass on the grounds that it is "already counted by the pass above". The CITATION pass resolves against ROOT. The two passes therefore agree only for Markdown at the repository root; for any nested document the checker validates a path the reader will never follow. `[roadmap](docs/ROADMAP.md)` written inside `docs/design/tasks/` really targets `docs/design/tasks/docs/ROADMAP.md`, and the checker reports it resolved. This is the failure the relative pass was built to close, reopened by the pass's own optimisation. Latent today: 0 live instances at HEAD (the two occurrences in 046 are inside inline backticks and do not render as links). It is the link a writer produces by copying a path out of `docs/DOCUMENTATION_MAP.md` into a task file.

**Reproduce:** In a scratch worktree at HEAD: `printf '[roadmap](docs/ROADMAP.md)\n' > <probe>.md; ruby scripts/check_doc_links.rb` -> prints "every documentation path resolves", exit 0, while `ls docs/design/tasks/docs` does not exist. Direction: drop the shortcut and treat a link as relative unless the citing file is at the repository root, or require one of the two interpretations to resolve and say which.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.175 Doc-link resolution goes through File.file?, so a case-only typo passes on macOS and fails on Linux and GitHub

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (`resolve`/`candidates_for`, lines 163-175), `scripts/preflight.rb` (line 101), `.github/workflows/ci.yml` (the doc-links job, ubuntu-latest)

Resolution is `File.file?(File.join(ROOT, target))`. On APFS that is case-insensitive, so `docs/roadmap.md` and `docs/design/tasks/024-DEFERRED-review-findings.md` both "resolve" and the check exits 0 — while both are dead links in a Linux checkout and in GitHub's web renderer. CI runs the identical script on ubuntu-latest, so `preflight.rb`, the gate whose entire purpose is to run *before* the commit, is strictly weaker than CI on this class of typo: the same local-green/CI-red asymmetry CLAUDE.md already records for the real-Rails and capability suites. It also makes the script disagree with itself: `ever_existed?` asks git, which is case-sensitive, so the resolver and the history query can answer differently about the same path.

**Reproduce:** On macOS, from the repository root: `ruby -e 'p File.file?("docs/ROADMAP.md"), File.file?("docs/roadmap.md")'` prints `true true`. Then `printf '# See docs/roadmap.md\n' > <probe>.rb; ruby scripts/check_doc_links.rb` -> "every documentation path resolves", exit 0. Direction: after `File.file?` succeeds, require the resolved path to appear verbatim in `RepoFiles.list`, which is byte-exact and already enumerated.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.176 The `[deletion marker]` marker admits a pointer to a renamed file, which the paragraph defining it says is still a failure

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (the marker paragraph, lines 141-153; `ever_existed?`, lines 189-195)

The marker's design paragraph ends: "A pointer to a *renamed* file is also still a failure, because the marker is a deliberate edit on the line that needs it rather than a mode the file is in." `ever_existed?` asks `git log --all -1 -- <path>`, which is true for a path git carried under its pre-rename name — so a marked citation of a file that was renamed away passes, and is counted in the "naming a deleted file on a line marked as recording the deletion" total. The stated reason does not support the stated claim either: per-line marking says nothing about renames. Renames are the common case for documents in this tree (046's own A4 table repoints five task filenames), so the exemption is widest exactly where it was meant to be narrowest, and the count the check prints is not the count it names.

**Reproduce:** In a tmpdir: `git init`; commit `<probe>.md`; `git mv `<probe>.md` `<probe>.md` and commit; commit `note.md` containing ``A pointer to `<probe>.md` [deletion marker]`` and ``A pointer to `<probe>.md` [deletion marker]``; run `CHECK_DOC_LINKS_ROOT=<tmpdir> ruby scripts/check_doc_links.rb`. Only NEVER_EXISTED_AT_ALL is reported; the output says "1 naming a deleted file". Either make the marker check that no commit's *current* tree still carries the content under another name, or correct the paragraph to say what the code does.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.177 check_doc_links names only an enumerated set of docs subdirectories, so a citation in any other one is silently unchecked

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (`CITATION`, line 93: `docs/(?:design/)?(?:tasks/|adrs/|docs/|schemas/)?[A-Za-z0-9._-]+\.md`)

Round 2's fix added the root and `vscode/` documents and added `schemas/` to the enumeration, which closed the reported instances. What it did not do is stop enumerating. The pattern can name a path only in the four listed leaf directories; `docs/guides/x.md`, or any subdirectory added tomorrow, is invisible, and the file's headline still says "Every documentation path named in tracked content must resolve to a file that exists." The scanner's scope is a hand-written list — the same shape `024.151` names in its third open bullet, one level in. Latent: 0 live instances at HEAD, because every docs subdirectory that exists today happens to be on the list. It becomes a false clean the first time someone adds one.

**Reproduce:** In a scratch worktree at HEAD: `printf '# See <probe>.md\n' > <probe>.rb; ruby scripts/check_doc_links.rb` -> "every documentation path resolves", exit 0. Add `<probe>.md` to the same probe and that one *is* reported, which is the contrast. Direction: match any `[A-Za-z0-9._/-]+\.md` token beginning with a real top-level directory of this repository rather than enumerating subdirectories; the coverage floor added in 0.2.14 pins how much of the tree is *read*, not how much of a path the pattern can *name*.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.178 check_doc_links' founding census is stated as living entirely in source comments; one of the nineteen was in a Markdown document

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (lines 25-27), `core/spec/meta/doc_links_spec.rb` (lines 8-12 and the failure message at line 65), `docs/design/tasks/046-0.2.14-making-the-record-true.md` (line 229)

Four tracked places assert that all 19 of the citations this check was built for lived in source comments, and draw a design conclusion from it — "a checker that read only Markdown would have reported this tree clean", which is the argument for scanning `.rb` at all. Re-running the A0-era checker against the pre-A0 tree reproduces the census exactly (19 citations, 5 never-committed names, 17 distinct files) and shows 18 in `.rb` comments and the nineteenth in `docs/design/plugin-sdk.md:5` — the "public SDK document" the immediately preceding sentence names in both the script and the spec. A Markdown-only checker would have found one of the nineteen, not zero. The conclusion survives at 18-of-19; the absolute quantifier that carries it does not, and one of the four places is an rspec failure message, so the false claim is what a future failure prints at the reader.

**Reproduce:** `git worktree add --detach /tmp/w6bc 6bc31b9; cd /tmp/w6bc; git show 26243e0:scripts/check_doc_links.rb > scripts/check_doc_links_a0.rb; ruby scripts/check_doc_links_a0.rb`. It prints "19 citation(s) resolve to nothing, naming 5 path(s)"; the last hit line is `docs/design/plugin-sdk.md:5`. Fix the sentence in all four places, not three — the spec's failure message at line 65 is easy to miss.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.179 Hand-typed counts in check_doc_links' header do not reproduce, and none carries a measured marker

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_doc_links.rb` (the SHORTHAND comment, lines 39-54; the CITATION root-document comment, lines 95-109), `docs/design/tasks/046-0.2.14-making-the-record-true.md` (lines 230-231)

Three numbers in this file are claims about this tree, each argued from, and none re-derives. (1) The shorthand census. It was "91 times across 39 files"; that figure is a raw grep of the short form, which also matches the *tail* of the fully-qualified form — the shape that is not a shorthand and needs no rewriting — so the cost side of "rewriting them costs more than it buys" was roughly doubled. Round 3 re-derived it to "45 times across 20 files", and that is wrong too: counted with the file's own SHORTHAND/CITATION/SKIP over `RepoFiles.list` it is 48 across 23 at HEAD *and* 48 across 23 at 6155cf4, the commit that wrote the sentence. 45/22 was true only at 54b7274, one commit earlier. (2) `046`:231` still carries the retracted "91 occurrences across 39 files", so the release record and the script now disagree. (3) The root-document comment says "twenty tracked Markdown files" and then enumerates fifteen, undercounting `vscode/` as six when it is eight and omitting the `.ja` halves of SECURITY, SUPPORT and CODE_OF_CONDUCT. That list is what a reader consults to decide whether the structural pattern still covers what it claims. None of the three carries a `<!-- measured: -->` marker, so `core/spec/meta/measured_claims_spec.rb` — the mechanism built in this same release for exactly this failure — never sees them.

**Reproduce:** Shorthand: eval the script's own `SHORTHAND`, `SKIP` and `CITATION` source lines, scan `RepoFiles.list(root)` minus SKIP line by line, count matches where the CITATION capture matches SHORTHAND -> 48 across 23 at HEAD; repeat in worktrees at 6155cf4 (48/23), 577704b (48/23), 54b7274 (45/22). Raw-grep reading at 6bc31b9: `git ls-files -z | xargs -0 /usr/bin/grep -oaE 'docs/[0-9]{2}-[a-z0-9-]+\.md' | wc -l` -> 91, `-laE ... | wc -l` -> 39. Root documents: `git ls-files | ruby -ne 'p=$_.chomp; puts p if p =~ %r{\A(?:vscode/)?[A-Z][A-Z0-9_]*(?:\.ja)?\.md\z}'` -> 20 files, 8 under vscode/. Direction: mark each with `<!-- measured: -->` and add its deriver, which is what the release's own mechanism is for.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.180 The citation guard reads nine file extensions, so the published site's register pointers are outside every check

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`scanned_files`, line 199-205), `site/index.html`, `site/security.html`, `site/ja/index.html`, `site/ja/security.html`

`scanned_files` takes `RepoFiles.list(TREE_ROOT)` — every tracked-or-untracked file — and then filters it with `/\.(rb|ts|js|md|json|yml|yaml|sh|erb)\z/`. That extension list is written directly beneath a comment explaining that the first version of this scanner used four globs, missed both changelogs, and that "a guard whose scope is a list somebody remembered has the defect it was built to catch": the fix replaced a list of directories with a list of extensions. At aa1185f the filter drops 38 of 561 files — all 11 `site/*.html` pages, every extensionless file (`LICENSE`, `.gitignore`, `core/.rspec`), 4 `.rbs`, `core/ovallsp.gemspec`, `vscode/resources/core-job.ps1`, `site/robots.txt`, `site/sitemap.xml`, `site/assets/css/site.css`, `.gitleaks.toml`, `core/Gemfile.lock`. Four of the dropped pages cite `024.55` today (`site/index.html:499`, `site/security.html:205`, `site/ja/index.html:462`, `site/ja/security.html:196`), and no other check in the tree looks at them: `scripts/check_site_links.rb` verifies links, anchors and assets and contains no `024.` handling; `scripts/check_doc_links.rb` verifies file paths; `deferred_findings_spec.rb` reads four named Markdown files. So deleting or renumbering `024.55` — the case the register's legend asks for a grep before — leaves four dangling pointers on the published site with the whole suite green. `024.151`'s remaining-work list names this class in one line ("several scanners' scopes are hand-written glob or extension lists"); this entry is the concrete instance, with the unchecked content named and a reproduction, which that entry does not carry.

**Reproduce:** In a scratch worktree at aa1185f: `printf '<!-- see 024.<n> -->\n' >> site/index.html` then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. `ruby scripts/check_site_links.rb` also exits 0. The identical line appended to any `.md` fails the example. Enumerate the blind region with `ruby -e 'require_relative "scripts/repo_files"; l=RepoFiles.list(Dir.pwd); puts (l - l.select{|p| p.match?(/\.(rb|ts|js|md|json|yml|yaml|sh|erb)\z/)})'`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.181 The measured-claim scanner reads four hand-written globs, so a marker anywhere else is inert

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, line 105-119)

`claims` scans `%w[docs/**/*.md core/lib/**/*.rb core/spec/**/*.rb vscode/src/**/*.ts]`, which is the pre-fix shape of the citation scanner ninety lines below it in the same file — the one whose comment says the four-glob version "missed both changelogs … A guard whose scope is a list somebody remembered has the defect it was built to catch." Both examples that read `claims` — "matches what the tree actually says" and "names a deriver for every claim, so none can be marked and left uncomputed" — are therefore blind outside those four globs, including to a marker naming a deriver that does not exist. Inert locations verified by probe: repo-root `.md` (`README.md`, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`), `vscode/**/*.md` (`vscode/CHANGELOG.md`, `vscode/README.md`), `scripts/**`, `site/**`, `.github/**`, `core/*.md`, and any non-`.md` file under `docs/`. The header's stated guarantee, "a claim cannot be marked and left uncomputed", is true only inside the four globs. Two further consequences of the same line: three of the four globs are asserted by nothing (no marker exists under `core/lib`, `core/spec` or `vscode/src`, so narrowing `patterns` to `%w[docs/**/*.md]` leaves all six examples green — an unpinned behavioural line, and this half is `024.151`'s class); and the file's positive control, "reads a claim out of a document and compares it", re-implements the scan inline against a tmpdir fixture and never calls `claims`, so nothing exercises the real scope. Fix by scanning `RepoFiles.list` filtered on text extensions, as the citation half already does — which dissolves the unpinned-glob half at the same time.

**Reproduce:** In a scratch worktree at aa1185f, write `probe [measured marker for no-such-deriver]` to each of `ZZ_probe_root.md`, `vscode/ZZ_probe.md`, `scripts/ZZ_probe.rb`, `site/ZZ_probe.html`, `.github/ZZ_probe.md`, `docs/design/ZZ_probe.txt`, `core/ZZ_probe.md`, and append `probe [measured marker for register-entries]` to `CLAUDE.md` and `vscode/CHANGELOG.md`; then `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. Separately, change line 106 to `patterns = %w[docs/**/*.md]` and rerun → 6 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.182 A sub-numbered register entry is invisible to the citation guard, and a citation of one truncates to its parent

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`CITATION` line 182, `register_numbers` line 187-191), `core/spec/meta/deferred_findings_spec.rb:143-144`

Sub-numbered entries are a supported shape — `DeferredFindings::ENTRY_HEADING` is `/^## (024\.[0-9R][0-9.]*) /` and `046`'s C4 made that module the single parser of the register — but two hand-rolled readers of the same headings survived that consolidation and neither can express a sub-number. `register_numbers` uses `/^## (024\.[0-9R]+) /`, which does not match `## 024.30.1`, so a sub-numbered entry is not in the guard's set of known numbers at all. `CITATION` is `/\b024\.(?<number>[0-9]+|R[0-9]+)\b/`, which matches `024.30.1` as `024.30`. The two failures compose in both directions: a pointer at `024.13.9` — an entry that was never written, or one renumbered away — passes because `024.13` exists, while `024.<n>.1` is reported dangling under the wrong number `024.<n>`. The consolidation comment at lines 76-88 of this file says round 1 removed a third and fourth reader for exactly this reason; these are the fifth and sixth. `deferred_findings_spec.rb`'s "indexes every entry" example carries the same regex on both sides asymmetrically (`/^## (024\.[0-9R]+)/` captures `024.30` from a sub-numbered heading, `/^\| \[`(024\.[0-9R]+)`\]/` captures nothing from its index row), so adding a sub-numbered entry would also fail that example spuriously.

**Reproduce:** Append `See 024.13.9 and 024.<n>.1 for the reasoning.` to any scanned `.md` (e.g. `docs/design/tasks/037-0.2.7-concurrency-foundations.md`) and run `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` — one failure, naming only `024.<n>`. For the reader divergence: `ruby -e 'require_relative "scripts/deferred_findings"; s="## 024.30.1 A sub entry\n"; p DeferredFindings.headings(s); p s.scan(/^## (024\\.[0-9R]+) /).flatten; p "see 024.30.1".scan(/\\b024\\.([0-9]+|R[0-9]+)\\b/).flatten'` → `["024.30.1"]`, `[]`, `["30"]`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.183 The citation guard skips the register itself, where most `024.N` cross-references are written

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`scanned_files`, line 202), `docs/design/tasks/024-deferred-review-findings.md`

`scanned_files` rejects `024-deferred-review-findings.md` outright, so a `see 024.NNN` typo inside an entry's body — the densest place `024.N` cross-references are written, and the place a reader most often follows one from — is unverifiable. The exclusion appears to exist so the entry headings and the index table do not match `CITATION` and report themselves; a scan that skips `^## ` headings and `^| [` index rows would keep the body prose in scope without that. Scanning the register's own body today finds four references that resolve to nothing — `024.61` at lines 85, 95 and 3998, and `024.<n>` at line 7092 — and all four are deliberate prose (the legend explains the vacated `024.61` at length; line 7092 records `046`'s C4 assembling a synthetic entry from parts because writing `024.<n>` tripped this very guard). None of them is a live defect, which is the point: a real typo would be indistinguishable from them by machine, because nothing looks.

**Reproduce:** Append `A stray pointer to 024.<n> for the reasoning.` to `docs/design/tasks/024-deferred-review-findings.md` and run `cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures. The scan that would have caught it: `ruby -rset -e 'reg=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); known=(reg.scan(/^## (024\\.[0-9R]+) /).flatten+reg.scan(/^\\| `(024\\.[0-9R]+)` \\|/).flatten).to_set; reg.lines.each_with_index{|l,i| l.scan(/\\b024\\.([0-9]+|R[0-9]+)\\b/).flatten.each{|n| puts "#{i+1}: 024.#{n}" unless known.include?("024.#{n}")}}'`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.184 A dated `@<rev>` claim is silently derived from the present tree unless the deriver happens to use the revision

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`DERIVERS["mutex-sites"]`, line 69-72; `MARKER`, line 61)

`MARKER` accepts `@<rev>` on any deriver, and the comment above it explains at length that this is what makes a historical document's number checkable rather than a promise to remember. `register-entries` and `register-open-defects` honour it — both pass `rev` into `register(rev)`, which shells out to `git show`. `mutex-sites` is `lambda { |_rev = nil| ... }`: it accepts the revision and discards it, the `_` prefix suppressing the lint that would say so, and globs the present `core/lib`. Nothing checks that a deriver invoked with a revision consumes it, so the guarantee is true for two derivers by construction and false for the third by accident. The consequence is inverted, which is what makes it worse than a missing check: a historical document that writes the **true** count at its revision goes red, and the failure message reads "Re-derive the number rather than editing the prose around it" — instructing the author to replace a correct dated number with a present-day one, in the file built to stop exactly that. The narrower structural fault is that a deriver's signature is what decides whether dating works, and nothing states or checks the contract.

**Reproduce:** In a scratch worktree at aa1185f, derive the truth first: `git ls-tree -r --name-only f67e743e6eec core/lib | /usr/bin/grep '\.rb$' | while read f; do git show "f67e743e6eec:$f"; done | /usr/bin/grep -c 'Mutex\.new'` → 29. Then `printf '\n[measured marker for mutex-sites]\n' >> docs/design/tasks/037-0.2.7-concurrency-foundations.md; cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → RED, "mutex-sites says 29, the tree has 31". Change 29 to 31 and rerun → 6 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.185 A second `<!-- measured: -->` marker on the same line is never parsed

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`claims`, line 113; positive control, line 158-166)

`claims` does `next unless (m = line.match(MARKER))`, and `String#match` returns the first `MatchData` only, so a second marker on the same line escapes both examples that read `claims` — "matches what the tree actually says" and "names a deriver for every claim, so none can be marked and left uncomputed". Two claims on one line is the natural shape, not an exotic one: the register's own marker line is "**152 entries below** [measured marker for register-entries]", and a sentence stating two counts ("152 entries, 57 of them open") puts both markers on one line. The file's positive control cannot see this, because it re-implements the scan inline against a tmpdir fixture (`File.read(path).lines.filter_map { |line| line.match(MARKER) }` — the same first-match-only call) instead of exercising `claims`. `line.scan(MARKER)`, as the citation half already does one screen below, is the fix.

**Reproduce:** In a scratch worktree at aa1185f: `printf '\nX [measured marker for mutex-sites] and Y [measured marker for register-entries]\n' >> docs/design/tasks/037-0.2.7-concurrency-foundations.md; cd core && bundle exec rspec spec/meta/measured_claims_spec.rb` → 6 examples, 0 failures, though the register has 152 entries. Repeat with `no-such-deriver = 1` as the second marker → also green. Control: the same `register-entries = 999` marker alone on its own line → RED, "register-entries says 999, the tree has 152".

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.186 `mutex-sites` counts the string `Mutex.new`, so a comment mentioning it inflates the documented lock count

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/measured_claims_spec.rb` (`DERIVERS["mutex-sites"]`), `docs/design/docs/02-architecture.md:270`, `core/lib/ovallsp/signatures/type_converter.rb:112`

The deriver is `File.read(f, encoding: "UTF-8").scan("Mutex.new").length` — a substring count over the whole file, comments and strings included. `core/lib/ovallsp/signatures/type_converter.rb:112` reads `# path -- \`Mutex.new\` says \`Thread::Mutex\`, which is what it is.`, a sentence about how RBS renders a type name, not a lock. So `core/lib` constructs 30 mutexes while the deriver answers 31, and `docs/design/docs/02-architecture.md:270` — the threading section whose stated purpose is that it stopped contradicting the code, and which was wrong about this same count on the release that introduced it — asserts 31 with a green guard behind it. The check is green because the deriver and the prose disagree about what is being counted, not because the count is right. The coupling also runs the wrong way: writing another comment that mentions `Mutex.new` would force the author to raise the documented number of locks, and deleting one would force lowering it.

**Reproduce:** `/usr/bin/grep -rn 'Mutex.new' core/lib --include='*.rb' | wc -l` → 31 (use `/usr/bin/grep`; the interactive shell's `grep` is a `ugrep` wrapper). `/usr/bin/grep -rn 'Mutex.new' core/lib --include='*.rb' | /usr/bin/grep -E ':[0-9]+:\s*#'` → the single comment at `core/lib/ovallsp/signatures/type_converter.rb:112`. Actual constructions: 30. `sed -n '268,272p' docs/design/docs/02-architecture.md` shows the claim and its marker, and `bundle exec rspec spec/meta/measured_claims_spec.rb` is green.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.187 A single NUL or invalid byte clears a whole file from the home-path scan, and no example can fail on it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

`offences_in_file` returns [] for the *entire* file when it contains one NUL byte or one invalid UTF-8 sequence (lines 101-110), including any real home path sitting in its plain-ASCII portion. The skip is deliberate for compiled artefacts — those are covered by `vscode/scripts/release.sh` against the packaged VSIX — but the rule is written as a property of the bytes, not of the file, so any text file that acquires a stray byte silently stops being checked. The compensating story, 'a skip is reported', is printed only by the CLI's no-offence branch; the tree scan that actually runs on every suite run is the spec, and the spec asserts nothing about which files were skipped or how many. Both examples that name the skip path are assertions that cannot fail: 'skips compiled payloads' (line 123) passes through the `File.file?` guard and never reaches the NUL branch, and 'reports what it skipped' (line 95) checks `be_an(Array)` against a memoised `[]` plus a set subtraction whose two symbols are the only ones any writer site produces. So the 0.2.5 fix — skips are announced rather than silent — is unpinned, and the skip set is free to grow to any size with the suite green. The skip set at HEAD is exactly two PNGs, which makes pinning it cheap.

**Reproduce:** In a scratch clone of HEAD (never the real tree): `printf 'built at $HOME/WorkSpace/secret\n\x00trailing\n' > `<probe>.md`, then `ruby -e 'require_relative "scripts/check_home_paths"; p HomePaths.tree_offences.size; p HomePaths.skipped_files'` => 0 offences, the file listed as `reason: :binary`. `cd core && bundle exec rspec spec/meta/home_path_guard_spec.rb` => 10 examples, 0 failures. Then, separately: delete the whole `if content.include?(NUL) ... end` block => still 10 examples, 0 failures; restore it and delete only the two `skipped_files << { ... }` lines (undoing 0.2.5) => still 10 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.188 The home-path scanner dereferences a symlink instead of reading the blob git commits

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb

For a symlink, git stores the target string as the blob's entire content — so `ln -s $HOME/... x && git add x` commits and pushes a real home path verbatim. `offences_in_file` never reads that blob: `File.file?` (line 92) and `File.binread` (line 94) both dereference. A broken link fails `File.file?` and returns [] with no `skipped_files` entry at all, so the 0.2.5 guarantee that a file the check could not clear says so does not cover it; a live link is worse than silent, because the scanner reads *the target's* bytes and can report an offence at a line number in a file that is not in the repository. The `File.file?` early return is in fact a third silent skip alongside the two the 0.2.5 fix addressed — it also swallows directories, unreadable files, and files that vanish between listing and read (now possible, since `RepoFiles.list` includes untracked files). Nothing else compensates: gitleaks' default ruleset has no home-path rule and `.gitleaks.toml` adds none, and `release.sh` inspects the packaged VSIX rather than the repository. Latent — the tree has no symlinks today (`git ls-files -s | grep -c ^120000` => 0).

**Reproduce:** In a scratch clone of HEAD: `ln -s $HOME/WorkSpace/secret/nope docs/leak_link && git add docs/leak_link && git cat-file -p :docs/leak_link` prints the real home path that would be pushed. Then `ruby -e 'require_relative "scripts/check_home_paths"; p HomePaths.tracked_files.grep(/leak_link/); p HomePaths.tree_offences.size; p HomePaths.skipped_files'` => the file is listed, 0 offences, and no skip entry. For the live-link half, symlink a file outside the repo and confirm `offences_in_file` reports on the target's content rather than the stored path.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.189 The home-path pattern matches one spelling, so every other spelling of the same real path passes

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

PATTERN (line 45) requires exactly one separator character immediately followed by an alphanumeric. Every other on-disk spelling of a real home path is therefore invisible: `C:\\Users\\name` as JSON, TypeScript or a pasted fenced block actually stores it; `"\/Users\/name"` (JSON escaped solidus); `/Users//name`; `<home>/name`; and the agent-scratchpad mangling `/private/tmp/claude-501/-Users-<name>-WorkSpace-Github-OvalLSP/...`, which discloses both username and directory layout and is the likeliest of the set here, given how much verbatim command output this repository's task documents quote — which is exactly how 0.2.3 leaked. The doubled-backslash case is sharpened by the file itself: line 31 writes that form and says it 'is caught', and the scanner does not flag its own line. The case-sensitivity decision beside it was argued and measured; this one was not considered at all, and the spec pins only the single-backslash Windows form.

**Reproduce:** At HEAD: `ruby -e 'require_relative "scripts/check_home_paths"; p HomePaths.names_in(File.readlines("scripts/check_home_paths.rb")[30]); p HomePaths.names_in(%q{/Users//alice/p}); p HomePaths.names_in(%q{<home>/alice/p}); p HomePaths.names_in(%q{"\/Users\/alice\/p"}); p HomePaths.names_in("/private/tmp/claude-501/-Users-alice-WorkSpace-Github-OvalLSP/x"); p HomePaths.names_in(%q{<home>/p})'` — the first five print [], the last prints ["alice"].

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.190 Annotated tag messages are a pushed public channel neither mode of the home-path check scans

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb, .github/workflows/ci.yml

`message_offences` runs `git log --all --format=...%B`, which prints commit messages only. This repository has 25 annotated tags whose bodies are hand-written at release time, pushed to the public remote, and are not commit messages — 8,005 bytes of prose that neither `--tree` (blob content) nor `--messages` (commit bodies) nor gitleaks (blob rules, and no home-path rule in `.gitleaks.toml`) ever reads. Release time is precisely the moment 0.2.3 pasted a build machine's home directory into a commit message, so this is the same class of channel the check exists for, left uncovered. No tag carries a home path today, so it is latent; a leak here is also harder to repair than a commit one, since republishing tags breaks the `buildCommit` SHAs the Marketplace artifacts reference.

**Reproduce:** At HEAD: `git for-each-ref refs/tags --format='%(objecttype)' | sort | uniq -c` => 25 tag, 4 commit. `git log --all --format='%B' | grep -cF "$(git for-each-ref refs/tags/v0.2.12 --format='%(contents:subject)')"` => 0. Scanning `git for-each-ref refs/tags --format='%(contents)'` through `HomePaths.names_in` finds nothing today, so the gap is in coverage, not in current content. Fix shape: iterate `git for-each-ref refs/tags --format='%(refname:short)%00%(contents)'` in `--messages` mode.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.191 as_utf8's comment describes a hazard the same file's utf8 require already removed

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb

Lines 67-72 justify `as_utf8` by saying backticks hand back a string in the shell's external encoding, US-ASCII when LANG is unset, so this repository's Japanese commit messages raise on the first `split` under a bare local shell while passing under CI's UTF-8 locale. That was true when it was written (4f19c67) and stopped being true in this release: 7c92b05 added `require_relative "utf8"` at line 4 of the same file, and `scripts/utf8.rb` sets `Encoding.default_external = Encoding::UTF_8` before any backtick runs. The described failure can no longer occur. `.scrub` still earns its place — a commit message can carry genuinely invalid bytes — so the method stays; the paragraph explains the wrong hazard, and a reader deleting the require would be reassured by a comment that no longer covers it. This is the shape CLAUDE.md's revert/documentation rule warns about: the prose was correct when written and nothing about the change announced that it invalidated it.

**Reproduce:** Read scripts/check_home_paths.rb line 4 and lines 67-74 together, then: `env LC_ALL=C LANG=C ruby -e 'require_relative "scripts/utf8"; p Encoding.default_external; p `git log -1 --format=%B`.encoding'` => UTF-8, UTF-8. Drop the require from the probe and the same command prints US-ASCII, US-ASCII. History: `git log -S"Backticks hand back a string tagged" -- scripts/check_home_paths.rb` => 4f19c67; `git log --diff-filter=A -- scripts/utf8.rb` => 7c92b05.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.192 The case-sensitivity decision is justified by a count of 37 that was never right

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/check_home_paths.rb, core/spec/meta/home_path_guard_spec.rb

Lines 34-44 record a deliberate decision — keep PATTERN case-sensitive — and rest it on a measurement: adding `/i` 'flags 37 lines in this repository ... A check that cries wolf 37 times is a check people switch off.' Re-derived with the file's own PATTERN plus `/i`, its own SYNTHETIC list, the same file set and the same skips: 35 at HEAD, 36 at 54104b4, the commit that wrote the sentence. Never 37. The number is repeated in the spec comment (home_path_guard_spec.rb:81), where it is the reason given for an example that pins the decision, and neither copy is a marked measured claim, so `measured_claims_spec.rb` never re-derives either. The decision itself is still correct and should stand; what is wrong is a claim about this tree that nobody ran, in a file whose neighbouring paragraph makes a point of saying the decision 'was measured rather than assumed'.

**Reproduce:** At HEAD: load scripts/check_home_paths.rb, scan `RepoFiles.list(ROOT)` with `Regexp.new(HomePaths::PATTERN.source, Regexp::IGNORECASE)`, reject `HomePaths::SYNTHETIC`, apply the same NUL/invalid-encoding skips, count lines with at least one hit => 35. Repeat in a clone checked out at 54104b4 using that revision's own `tracked_files` => 36. Fix shape: mark it as a measured claim with a deriver, or state the decision without a number.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.193 Existence is a suffix glob and any test: name passes unconditionally, so a citation naming a file that does not exist is accepted

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/release_gate_spec.rb (lines 111-112, the `exists` test)

Existence is `!RepoFiles.list(ROOT, "*#{base}").empty?` — a suffix glob on the basename, never compared against the cited path — and any citation starting `test:` skips the existence test entirely. Three consequences, all reproducible at HEAD: (1) a cited path whose basename is merely a suffix of a real file passes — `scripts/sbom.rb` and `tools/smoke.rb` exist nowhere in the tree yet both are accepted, matching scripts/generate_sbom.rb and vsix_semantic_smoke.rb respectively; (2) the cited path itself is never validated, so `../../../../etc/generate_sbom.rb` is accepted as gate 8's evidence; (3) a nonexistent npm script can never be reported missing — `test:integ` and `test:u` are accepted, and when the wiring half does catch a planted npm citation it reports the false message "exists but nothing invokes it". The practical cost: a script that is renamed or moved leaves its gate green whenever some other file's name ends with the old basename, and a typo in the checklist is indistinguishable from correct evidence.

**Reproduce:** In docs/RELEASE_CHECKLIST.md replace gate 11's `scripts/verify_sbom_against_vsix.rb` with `scripts/sbom.rb` `tools/smoke.rb`; `ls scripts/sbom.rb tools/smoke.rb` => No such file; `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 0 failures. Replace gate 8's `scripts/generate_sbom.rb` with `../../../../etc/generate_sbom.rb` => 0 failures. Replace gate 4's `test:unit`/`test:integration` with `test:integ`/`test:u`; `grep -c '"test:integ"' vscode/package.json` => 0; re-run => 0 failures. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.194 release_gate_spec's wiring corpus includes untracked files, so uncommitted local text satisfies a gate's "something invokes this"

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/release_gate_spec.rb (`haystack_excluding`, line 92), scripts/repo_files.rb

024.147 made RepoFiles list untracked-but-not-ignored files so that checks are not blind to a file being written before it is committed. That argument is about the files a check *inspects*. release_gate_spec applies it to the corpus it treats as *evidence of invocation*: every file of every extension under core/spec and scripts, tracked or not, is joined and searched. An uncommitted scratch file that merely names a script basename therefore flips a gate from 'nothing invokes this' to 'wired'. That consequence is nowhere argued — untracked_visibility_spec.rb and repo_files.rb both justify the inspection side only — and it means the check can pass for a reason that does not exist in any commit, which is the same failure the spec's own comment says round 1 caught. Distinct from the substring defect: requiring an invocation-shaped line would not fix it, since an untracked file can contain an invocation-shaped line.

**Reproduce:** First remove the three non-comment mentions of generate_sbom.rb (core/spec/meta/sbom_spec.rb:19, scripts/verify_sbom_against_vsix.rb:27, core/spec/meta/pinned_mutations.yml:179) so the check correctly reports "gate 8: scripts/generate_sbom.rb exists but nothing invokes it". Then create an untracked file `scripts/notes.txt` containing the single line `todo: look at generate_sbom.rb tomorrow` — `git check-ignore -v scripts/notes.txt` reports it is not ignored — and re-run `cd core && bundle exec rspec spec/meta/release_gate_spec.rb` => 0 failures. Delete the scratch file and revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.195 Every prose statement of what the preflight gate runs is stale, and nothing derives any of them

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/preflight.rb` (header, line 17), `CONTRIBUTING.md` + `.ja.md`, `docs/design/tasks/024-deferred-review-findings.md` (024.143)

`ruby scripts/preflight.rb --list` prints **8** checks naming **6** distinct scripts (`documented_counts.rb`, `check_home_paths.rb`, `check_doc_links.rb`, `reindex_findings.rb`, `check_swallowed_failures.rb`, `check_site_links.rb`) plus two `rspec` invocations. Four passages describe that gate and no two agree with it or with each other: `scripts/preflight.rb:17` says "the checks are in six places (the suite, three scripts, a git state, a derived number)" -- and **no check inspects git state at all**; `CONTRIBUTING.md:147` and `CONTRIBUTING.ja.md:140` say seven; `024.143` says "Seven things must be true" (:7731), "They live in seven places" (:7734) and "runs all seven" (:7746). `024.143` is stale in two further ways the same round already fixed in `CLAUDE.md` and left here: it says "the two real-Rails-backed suites" where there are three (`real_rails_spec`, `capabilities_spec`, `client_behaviour_spec`), and its second bullet still states the count-based rule -- "It asserts a non-zero example count rather than reading the exit status" -- which is precisely the arrangement `024.148` records as the defect and `8f1d4f4` replaced with `CheckSuitesRan.complaints`. So the register's own account of the gate instructs a reader to rely on the check the register elsewhere says could not fail. The eighth check was added by `024.145` inside this release, and every one of these statements drifted inside the release that added it. Root cause: these are hand-typed numbers about this tree, which `CLAUDE.md` says must be derived -- and the mechanism for that, `measured_claims_spec.rb`'s `<!-- measured: -->` markers, globs only `docs/**/*.md`, `core/lib/**/*.rb`, `core/spec/**/*.rb` and `vscode/src/**/*.ts`, so neither `CONTRIBUTING.md` nor anything under `scripts/` can carry a checked claim. A `preflight-checks` deriver plus widening that glob list closes the whole family.

**Reproduce:** `ruby scripts/preflight.rb --list | grep -c '^[a-z]'` -> 8. Then read `sed -n '13,20p' scripts/preflight.rb`, `sed -n '145,150p' CONTRIBUTING.md`, `sed -n '138,143p' CONTRIBUTING.ja.md`, and `sed -n '7729,7750p' docs/design/tasks/024-deferred-review-findings.md`. Confirm the absent git-state check with `ruby scripts/preflight.rb --list | grep -i git` (no output).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.196 The measurement that justifies reading per-example status is quoted three times, attributed to a different file each time, and matches none of them

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/preflight.rb:52-57`, `scripts/check_suites_ran.rb:17-23`, `CLAUDE.md:505-511`

The argument for `024.148`'s fix rests on one measurement -- what a fully skipped suite reports. It is quoted in three places as "45 examples, 0 failures, 41 pending", and at HEAD it belongs to none of them. `scripts/preflight.rb:54` attributes it to `spec/integration/real_rails_spec.rb`, which has **16** examples -- and `024.148`, the entry that comment cites as its authority, itself says "all 16 `real_rails` examples marked pending", so the comment contradicts its own citation. `scripts/check_suites_ran.rb:18-19` attributes it correctly to the e2e capability suite, but that suite now has **57**. `CLAUDE.md:509` repeats the figure with no file named at all, added by round 3 while it was fixing a different defect in the same paragraph -- so a round that existed to make the record true propagated a stale number into the operating document. A measurement is a claim (`CLAUDE.md`, "A measurement is a claim, and it needs the same care as a test"); this one is unpinned, misattributed, and now carried in three files that must agree about it -- the `042` D8 shape, a thing assembled three times.

**Reproduce:** From `core/`: `bundle exec rspec --dry-run spec/integration/real_rails_spec.rb` -> 16 examples; `bundle exec rspec --dry-run spec/e2e/capabilities_spec.rb` -> 57; `bundle exec rspec --dry-run spec/meta/client_behaviour_spec.rb` -> 7. Then `sed -n '52,58p' scripts/preflight.rb`, `sed -n '17,24p' scripts/check_suites_ran.rb`, `sed -n '505,512p' CLAUDE.md`, and `sed -n '8060,8066p' docs/design/tasks/024-deferred-review-findings.md` for 024.148's own "16".

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.197 0.2.14's review loop edited its own standard and added a capability between rounds, with no departure recorded

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `CLAUDE.md`, `docs/design/tasks/046-0.2.14-making-the-record-true.md`

`046:505` states that each round was given "`CLAUDE.md` and `AGENTS.md` ... as the standard to hold it to". `CLAUDE.md` was edited by three of the four commits in the range: `8f1d4f4` (round 1) softened the trusted-root paragraph; `54b7274` (round 2) added a new mandatory section, "Writing a check means writing bait for the other checks" (+29 lines); `6155cf4` (round 3) added another, "Promoting a finding is making a claim" (+39/-2), plus the preflight paragraph. Rounds 1, 2 and 3 were therefore each held to a different standard, and their finding counts (18 / 70 / 63) are not comparable in the way `CLAUDE.md`'s cadence rule assumes -- the same failure `024.36` records for 0.1.15, arriving through the standard rather than through the prompt. Separately, `e100388`, between rounds 2 and 3, extended `scripts/check_pinned_mutations.rb` to `scripts/` (+18 lines), added seven manifest entries and refactored `scripts/documented_counts.rb` to extract a pure function. `CLAUDE.md:50` says "During a review loop, fix; do not add ... every addition between rounds resets it", and `046:349` invokes that exact rule to decline an `AGENTS.md` restructure in the same release -- so the rule was applied to a documentation change and not to a change in the checking machinery the rounds are measured with. `CLAUDE.md` requires that "Departing from this rule is written down, where the release is recorded"; the only recorded departure in `046` is the one about the `drive` method. This one is written down nowhere, and the release shipped.

**Reproduce:** `git log --oneline main..HEAD -- CLAUDE.md` -> 7c92b05, 8f1d4f4, 54b7274, 6155cf4 (the last three are the round commits). `git show 54b7274 -- CLAUDE.md` and `git show 6155cf4 -- CLAUDE.md` show the two added mandatory sections; `git show 8f1d4f4 -- CLAUDE.md` shows the softened trusted-root paragraph. `git show --stat e100388 -- scripts/check_pinned_mutations.rb core/spec/meta/pinned_mutations.yml scripts/documented_counts.rb`. Then `grep -rn 'do not add' docs/ CLAUDE.md AGENTS.md CHANGELOG.md` -- the only recorded departure (`046:497`) is about the `drive` method, and `046:1299` is this finding still sitting untriaged in round 3's own list.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.198 The packaged-artifact inspection count is derived from the directory alone, so a grep aimed at the wrong pattern or with wider exclusions still reports a healthy count

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `vscode/scripts/release.sh` lines 165-193, `core/spec/meta/release_script_guard_spec.rb` (`"makes the artifact check say what it inspected…"`)

The INSPECTED countermeasure was added so that "aimed at nothing" becomes visible, and release.sh's own comment states the principle: "A count that is not derived from what was actually searched guards the variable rather than the search." It still guards the variable. `find "$INSPECT_ROOT"` and the grep share only `INSPECT_ROOT`; "aimed at nothing" has three dimensions — directory, pattern, exclusion set — and the count covers one. Changing the pattern to `"$HOME/.ovallsp-never-exists"`, or appending `--exclude='*.js' --exclude='*.json' --exclude='*.map' --exclude='*.rb'`, makes the check match nothing while the log still prints `PASS: packaged-artifact path inspection (N files inspected)` with the same four-figure N, and every text assertion stays true because the literal `grep -rlF --exclude` and `INSPECTED=` are untouched. This is a defect in the countermeasure that `024.151` holds up as direction #1 ("every check states its own coverage… this kills the whole narrow-the-input family at once"): coverage stated as a file count does not kill it. Recording it separately so that correction is not lost inside the class entry.

**Reproduce:** Scratch mirror as above. (a) Change line 174's pattern to `"$HOME/.ovallsp-never-exists"` → 10 examples, 0 failures. (b) Instead, append `--exclude='*.js' --exclude='*.json' --exclude='*.map' --exclude='*.rb'` to line 174 → 10 examples, 0 failures. Behaviour: build a fake artifact of 150 plain files plus one `.js` containing `$HOME`; the shipped grep lists the leaking file, both mutants match nothing, and all three print `PASS: packaged-artifact path inspection (151 files inspected)`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.199 The guard spec's absolute-grep pin is satisfied by the advisory grep, and its bare-grep scan cannot see an indented call

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/release_script_guard_spec.rb` lines 188-191, `vscode/scripts/release.sh` lines 174-181

Two holes in one example, `"calls the grep it means, not whatever the shell resolves"`. (a) `expect(code).to include("/usr/bin/grep -rlF")` is satisfied by line 179 — the *advisory* grep whose output goes to /dev/null and which only prints a note — so the hard-failure grep on line 174 need not be absolute at all. (b) The scan `/(?:^|[|&;(]\s*|\bif\s+|!\s*)grep\s/` requires `grep` at a line start with no leading whitespace, or immediately after `| & ; (`, `if `, or `!`. Any indented bare `grep` escapes, as do `; then grep`, a backticked grep and a continuation line after `&& \` — and almost every grep inside an `if` or a function body is indented, so the scan misses the common case. Together they let the release script's one credential-leak check fall back to whatever `grep` the shell resolves — which is the ugrep-wrapper failure mode 0.2.3 filed and withdrew a register entry over, and the reason release.sh calls `/usr/bin/grep` by absolute path in the first place.

**Reproduce:** Scratch mirror as above. Replace release.sh line 174 with: ``` artifact_carries_home_path() { grep -rlF --exclude='*.bundle' --exclude='*.so' --exclude='*.dylib' "$HOME" "$INSPECT_ROOT" } if artifact_carries_home_path; then ``` From `core/`, `bundle exec rspec <m>/core/spec/meta/release_script_guard_spec.rb` → 10 examples, 0 failures, with the hard-failure grep now shell-resolved.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.200 Nothing checks that release.sh parses, so a syntax error past the first refusal leaves every check green

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `vscode/scripts/release.sh`, `core/spec/meta/release_script_guard_spec.rb`, `.github/workflows/`

Nothing anywhere runs `bash -n` or shellcheck on release.sh — not the guard spec, not CI (there is no shell-syntax job in `.github/workflows`). Every non-executed assertion is a text match, and the three executed examples exit at line 55 or line 83, so bash's parser never reaches anything later. An unterminated `if` introduced anywhere past line 83 leaves the only publish path unrunnable while the suite is green, and it is discovered by the person attempting the release, at the moment they attempt it. One line fixes it: `expect(system("bash", "-n", SCRIPT)).to be(true)`. `vscode/scripts/verify-installed-extension.sh` has the same exposure and no spec at all.

**Reproduce:** Scratch mirror as above. Prefix `echo "-- SHA-256 --"` with `if [ -n "$VSIX_PATH" ]; then` and add no closing `fi`. `/bin/bash -n <m>/vscode/scripts/release.sh` → `line 255: syntax error: unexpected end of file`, exit 2. From `core/`, `bundle exec rspec <m>/core/spec/meta/release_script_guard_spec.rb` → 10 examples, 0 failures.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.201 The NOT YET escape hatch is guarded against a hand-copied two-suite list that has drifted from the three-suite table it covers

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/ci_skip_guard_spec.rb, scripts/check_suites_ran.rb, core/spec/meta/client_behaviour_spec.rb

`CheckSuitesRan::SUITES` names three spec files that skip themselves for want of an environment, and `ALLOWED_PENDING = "NOT YET"` exempts a pending example whose message says so. The example that stops that exemption swallowing the environment skip -- "does not exempt the environment skip it exists to catch" -- iterates a hand-written two-element array (real_rails_spec, capabilities_spec) instead of the three-element table it is meant to cover. `spec/meta/client_behaviour_spec.rb`, added to SUITES in the same release, is unguarded. So `skip("NOT YET -- vscode/node_modules is not installed")` leaves every check green, and check_suites_ran then prints its success line -- "all 7 client-behaviour examples ran." -- and exits 0 for a run in which the two examples docs/CLIENT_BEHAVIOUR.md marks **checked** never executed. The checker states the opposite of the truth in its own output, which is the failure 024.148 was written to close, reopened for the third file that entry's own table lists. Secondly, the loop cannot simply be extended: the scan is `/^\s*skip\s+"([^"]+)"/`, which requires the paren-less form; client_behaviour_spec writes `skip("...")`, so adding the path makes the example fail on `not_to be_empty` rather than check anything. The fix is one place iterating `CheckSuitesRan::SUITES` with a regex that accepts `skip(` -- the hand-copied list is the defect, not the missing element.

**Reproduce:** In a scratch worktree at HEAD: `sed -i '' 's/skip("vscode\/node_modules is not installed")/skip("NOT YET -- vscode\/node_modules is not installed")/' core/spec/meta/client_behaviour_spec.rb`, then `cd core && bundle exec rspec spec/meta` -> 192 examples, 0 failures. With `vscode/node_modules` absent, `bundle exec rspec spec/meta/client_behaviour_spec.rb --format json --out /tmp/cb.json`, then from the repo root `ruby -e 'require "./scripts/check_suites_ran"; require "json"; r=JSON.parse(File.read("/tmp/cb.json")); s={"client-behaviour"=>"spec/meta/client_behaviour_spec.rb"}; p CheckSuitesRan.complaints(r, suites: s)'` -> `[]`, while two of the seven examples are pending. For the second half, add `spec/meta/client_behaviour_spec.rb` to the array at ci_skip_guard_spec.rb:128 and run that file -> 13 examples, 1 failure, `expected [].empty? to be falsey`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.202 The release-tag accounting invariant runs nowhere continuous: the job that runs the suite checks out without tags

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/release_artifacts_spec.rb, .github/workflows/ci.yml, scripts/check_suites_ran.rb

release_artifacts_spec's two tag examples -- "accounts for every tag, in one table or the other" and "records no version that was never tagged" -- call `skip` when `git tag --list 'v*'` is empty. The core job, the only job that runs the suite, checks out with a bare `- uses: actions/checkout@v4` (ci.yml:23): no `fetch-depth`, no `fetch-tags`, so the checkout has no tags and both examples are pending on every CI run while rspec exits 0. Nothing watches those pendings. The file is not in `CheckSuitesRan::SUITES`, so the skip guard has no opinion on it, and ci.yml's "Fail if a documented-count check skipped" step reads only documented_counts_spec.rb. This is exactly the shape the skip guard exists to prevent -- a suite that skipped for want of an environment reported as a suite that passed -- occurring in a file the guard does not cover. The invariant is not entirely unenforced: preflight.rb runs the full suite before a commit, and a maintainer's checkout has tags, so it does execute there. But it is unenforced anywhere continuous, and it is the invariant written because 0.1.14 and 0.1.15 were tagged, never built, and noticed only by someone looking at the Marketplace by eye. A contributor's PR, and a reviewer reading a tarball or a `git archive` extraction, both get a vacuous pass. Candidate fixes, each with a cost the entry should weigh: give the core job's checkout `fetch-tags: true` and add the path to `CheckSuitesRan::SUITES` (but a tarball reviewer would then fail rather than skip); or move the two tag examples to a job that already fetches full history -- secret-scan checks out with `fetch-depth: 0`.

**Reproduce:** `sed -n '23,25p' .github/workflows/ci.yml` -> the core job's checkout takes no `with:` block. Then, with a stub that makes `git tag` return nothing: `mkdir -p $SCRATCH/stub && printf '#!/bin/sh\nfor a in "$@"; do case "$a" in tag) exit 0;; esac; done\nexec /usr/bin/git "$@"\n' > $SCRATCH/stub/git && chmod +x $SCRATCH/stub/git && cd core && PATH=$SCRATCH/stub:$PATH bundle exec rspec spec/meta/release_artifacts_spec.rb` -> 4 examples, 0 failures, 2 pending, exit 0. Without the stub the same command is 4 examples, 0 failures, which is why the gap is invisible locally (this checkout has 29 v* tags).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.203 suites_ran_spec's ci.yml link asserts a text substring, so it passes for a step that has been deleted, commented out, or disabled

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/suites_ran_spec.rb

The example "is what ci.yml runs, not a second implementation" reads the whole workflow file and asserts `include("scripts/check_suites_ran.rb")`. A commented-out step keeps that text, as does a step carrying `if: false` or `continue-on-error: true`, so the example passes under every mutation it appears to guard against. ci_skip_guard_spec.rb's header comment states precisely why that form is wrong -- 0.2.3 merge round 6, a text slice stays green when the step is commented out -- and that file does it correctly, locating the step in parsed YAML. So this example costs no coverage today: it is backstopped. What it costs is trust. It reads as an independent guard on the link 024.148 was written to establish, and a reader who relies on it gets nothing. Under CLAUDE.md's rule that an assertion which cannot fail in the case it names is not a test, it should either assert the parsed step the way its neighbour does, or be deleted with a pointer to the file that already checks this. Recorded separately from the `if`/`continue-on-error` entry because the reproduction and the consequence differ: that one is a real coverage gap, this one is a misleading guard over covered ground. A single fix -- one helper both files call -- would close both.

**Reproduce:** In a scratch worktree at HEAD, replace the two lines of the guard step in .github/workflows/ci.yml with commented-out copies (` # - name: Fail if the real-Rails or capability suites were skipped instead of run` / ` # run: ruby scripts/check_suites_ran.rb core/tmp/rspec.json`). Then `cd core && bundle exec rspec spec/meta/suites_ran_spec.rb` -> 6 examples, 0 failures; `bundle exec rspec spec/meta/ci_skip_guard_spec.rb` -> 1 failure on "still runs in the core job at all", which is the only thing that catches it. Revert.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.204 The `git ls-files` guard reads 49 files in two directories, so the enumeration it forbids is invisible everywhere else in the tree

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/untracked_visibility_spec.rb

The example is titled "is the only way this tree enumerates its own files" and its failure message says "these enumerate the repository the old way", but line 78 reads `scripts/*.rb` and `core/spec/meta/*.rb` — 49 files, against 340 tracked non-vendor `.rb` files. git's `*` does cross `/`, so the `scripts/` half is fine; `core/spec/meta/*.rb` reaches neither `core/spec/support/` (which already holds two shared helpers the meta specs depend on, so moving an enumeration there is an ordinary refactor) nor `core/spec/ovallsp/`, `core/spec/spec_helper.rb`, `core/spec/e2e/`, `core/spec/integration/`, `.github/workflows/`, `vscode/`, or `Rakefile`. Line 79 widens the same hole from the other side: `next if rel.end_with?("scripts/repo_files.rb")` is a suffix match, so `scripts/*/repo_files.rb` is silently exempt, when the one file that needs exempting has a known exact path. The scope decision is neither stated at the site nor asserted — the class round 2 fixed for `check_doc_links` by making per-root coverage an assertion. Latent rather than live at HEAD: I scanned all 544 tracked non-vendor, non-site files for a non-comment `git ls-files` and found no offender outside the guard's scope (the out-of-scope hits are prose in `docs/DOCUMENTATION_MAP{,.ja}.md`, `028`, `046`, and a quoted code line at `core/spec/meta/pinned_mutations.yml:156`).

**Reproduce:** From a clone at aa1185f: `printf '\nPLANTED = `git ls-files docs` if false\n' >> core/spec/ovallsp/cold_indexer_spec.rb`, then `cd core && bundle exec rspec spec/meta/untracked_visibility_spec.rb` -> 3 examples, 0 failures. Same result for `core/spec/support/unspellable.rb`. Control: the identical line in `core/spec/meta/spec_constants_spec.rb` -> 1 failure naming the file. For the exemption: `scripts/xscripts/repo_files.rb` containing a backtick `git ls-files docs` -> 3 examples, 0 failures; renamed to `scripts/xscripts/other.rb` -> 1 failure.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.205 The duplicate-heading check tracks a fence by its character and not its length, so a four-backtick block leaves the rest of the file unread

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb

`headings_in` (lines 37-51) stores `marker[0]` — the fence character, discarding the length. CommonMark closes a fence only on a marker of the same character AND at least the opener's length, so inside a ````-fenced block that quotes ```-fenced code (the markdown-in-markdown shape this repo writes constantly), the inner ``` is read as the closer and the real ```` closer then opens a fence that never closes. Every heading from that line to EOF is invisible, and nothing asserts the fence state is closed at EOF, so the check reports a file clean having examined none of it — `CLAUDE.md`'s named pattern, a check that cannot see the thing it checks reporting what a working check reports. Latent at HEAD (0 of 118 tracked Markdown files use a 4+ char fence, 0 end with an open fence), but this is the shape a fix for the h3/indentation gaps would make more likely, since quoting Markdown inside Markdown is how those documents are written. Direction: close only on a marker of the same character and >= the opener's length, and assert the fence state is closed at EOF for every file scanned (a structural coverage assertion, not a maintained number).

**Reproduce:** From a clone at aa1185f, write `<probe>.md` containing `# T`, a blank line, a ```` line, a ```ruby line, `x = 1`, a ```` line, a blank line, then `## Dup`, `a`, `## Dup`, `b`. `cd core && bundle exec rspec spec/meta/duplicate_headings_spec.rb` -> 3 examples, 0 failures. Control: the same file without the fence block -> 1 failure, "documents stating a heading more than once". Remove the file.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.206 The duplicate-heading check sees only unindented h1 and h2, while `024.140` records the guarantee as every heading

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb, docs/design/tasks/024-deferred-review-findings.md

The heading pattern is `/\A\#{1,2} \S/` — h1 and h2, column zero only. Two consequences and one record defect. (a) h3+ is never checked, and that is exactly the motivating incident: register entries and design documents carry `###` subsections routinely, so a scripted edit whose end boundary misses inside one pastes it back with the offender count unchanged. Five tracked files already state a heading twice at h3 and the check calls the tree clean: `docs/design/docs/08-implementation-plan.md` (`### Deliverables`, `### Exit criteria`), `docs/design/tasks/024-deferred-review-findings.md` (`### What was kept`), `docs/design/tasks/034-diagnostics-precision-review-gpt-5.6-sol.md` (`### Proposed correction`), `vscode/CHANGELOG.md` (`### Details`), `vscode/CHANGELOG.ja.md` (`### 詳細`). (b) A heading indented up to three spaces, or nested to a list item's content column, is a heading to every renderer and is not collected at all — while the fence regex in the same function is `/\A\s*.../` and does tolerate indentation. (c) The record: `024.140` states the guarantee as "**no tracked Markdown document states the same heading twice**" and the spec's own comment as "the same question asked of every tracked Markdown document". Both are false at HEAD, and nothing in either place records the h1/h2 scoping or argues for it. Direction: `/\A {0,3}\#{1,6} \S/`, normalise leading whitespace before tallying, and either raise the level or write the scoping down where the guarantee is stated.

**Reproduce:** From a clone at aa1185f: `<probe>.md` with `# I`, blank, `### Dup`, `a`, blank, `### Dup`, `b` -> `cd core && bundle exec rspec spec/meta/duplicate_headings_spec.rb` reports 3 examples, 0 failures. Repeat with ` ## Dup` (three leading spaces) twice -> 3 examples, 0 failures. Control: `## Dup` twice at column zero -> 1 failure. For the record half, no clone needed: run the spec's own `headings_in` with the level raised to 6 over `RepoFiles.list(root, "*.md")` and it names the five files above.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.207 Two decisions in the duplicate-heading fence parser have no fixture that can distinguish them

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** core/spec/meta/duplicate_headings_spec.rb

`CLAUDE.md`: a behavioural line that no test fails on when it is reverted is a defect regardless of whether the behaviour is correct. Two mutations of `headings_in` leave all three of the spec's examples green and produce zero offenders across all 118 tracked Markdown files: (1) replacing `elsif marker[0] == fence then fence = nil` with an unconditional `fence = fence.nil? ? marker[0] : nil`; (2) deleting the `~{3,}` alternative from the marker regex. Mutation (1) removes precisely the rule the comment above the method asserts — "a fence closes on the same marker -- so a ``` inside a ~~~ block is content, which is how this file's own examples stay quotable" — so the spec states a guarantee in prose that its own fixtures cannot tell the difference about. The spec's fixtures use only backtick fences and never nest one marker inside the other, which is why neither mutation is visible.

**Reproduce:** Extract `headings_in` verbatim and run it against these two fixtures. For (1): `# Doc` / blank / `~~~markdown` / ``` / `## Quoted` / ``` / `~~~` / blank / `## Real` / x / `## Real` / y — original returns ["# Doc","## Real","## Real"], the always-toggle mutant returns ["# Doc","## Quoted","## Real","## Real"]. Note this fixture does NOT distinguish (2). For (2) use `# Doc` / `~~~` / `## Quoted` / `~~~` / `## Real` / `## Real` — original ["# Doc","## Real","## Real"], no-tilde mutant ["# Doc","## Quoted","## Real","## Real"]. Both fixtures need adding as examples; a decision inside a spec cannot go in `pinned_mutations.yml` (024.151 records why the applier is unsafe for spec files).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.208 `Encoding.default_internal = nil` is the half of the locale fix that nothing pins

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** scripts/utf8.rb, core/spec/meta/script_encoding_spec.rb

`scripts/utf8.rb:32` can be deleted with `script_encoding_spec.rb` reporting 5 examples, 0 failures — nothing in the tree sets an internal encoding, so the probe cannot distinguish its presence from its absence, and `default_internal` appears nowhere else in `core/spec`, `core/lib` or `scripts`. Line 31 is pinned (deleting it fails the spec); line 32 is not. The line DOES earn its place, contrary to the doubt raised with the finding: with an internal encoding set, `File.read` transcodes and a UTF-8 needle no longer compares against it. So this is an unpinned correct line, which `CLAUDE.md` calls a defect in its own right — one refactor away from being an incorrect line with no test — and it has a cheap distinguishing fixture.

**Reproduce:** From a clone at aa1185f: `/usr/bin/sed -i '' '/^Encoding.default_internal = nil$/d' scripts/utf8.rb`, then `cd core && bundle exec rspec spec/meta/script_encoding_spec.rb` -> 5 examples, 0 failures. Control: deleting line 31 instead -> 1 failure. The pinning fixture: run the spec's existing probe with `RUBYOPT="-E UTF-8:EUC-JP"` added to its environment — with line 32 it prints `true,true,UTF-8,UTF-8`; without it, it raises `Encoding::CompatibilityError: incompatible character encodings: EUC-JP and UTF-8` at the `include?`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.209 The §5 status-bar comparison is set equality against a regex sample of clientPresentation.ts, not against the file's status strings — and two records state the stronger guarantee

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/design_doc_drift_spec.rb` (the `07 §5` example), `docs/DOCUMENTATION_MAP.md` (line 41, the command-id/setting/status-string row), `docs/design/docs/07-vscode-extension.md` §5, `docs/design/tasks/046-0.2.14-making-the-record-true.md` (C5 row, line 364)

The code side of §5 is `source.scan(/["'](\$\([a-z~-]+\)\s*)?(OvalLSP: [^"']+)["']/)`. 0.2.14 widened it to accept double quotes and to make the icon prefix optional, which closed the reported repro. Three conditions still gate candidacy, and each is a shape ordinary TypeScript takes: the literal must be delimited by `'` or `"`, so a template literal is invisible; an icon prefix, if written, must be `[a-z~-]` only, and a digit in a codicon name makes the whole literal unmatchable rather than partially matched, because the optional group fails and the label no longer abuts the opening quote; and the label must begin with the literal `OvalLSP: `. There is still no linter in the extension package — no eslint config anywhere in the tree, no lint script in vscode/package.json, no lint job in ci.yml — so none of these shapes is constrained. The consequence is one-directional and is the direction the records claim is closed: the file may define a status string the document does not list, with all six examples green. `docs/DOCUMENTATION_MAP.md:41` states "§3, §5, §6, §7 against `package.json` and `clientPresentation.ts` — set equality both ways" and closes "All five sections the row names are machine-checked"; `046`'s C5 row records the check as failing on "the exact drift measured". That is a record claiming a guarantee stronger than the mechanism delivers, sitting in the row written to prevent exactly that. The check is already blind to one string the shipped extension can produce: `statusPresentation`'s fallback `` `OvalLSP: ${outcome.state}` `` at clientPresentation.ts:109, which `clientPresentation.test.ts` deliberately pins ('renders an unrecognised state by name, not as an error') and which §5 does not mention while calling the file the 唯一の定義 of five strings. Two smaller things live in the same example: `.reject { |s| s.include?("\#{") }` tests for Ruby interpolation, which cannot occur in a TypeScript literal this regex can match — deleting the line leaves all six examples green, an unpinned behavioural line by this project's own definition; and the comparison reads only clientPresentation.ts, so a status string assigned anywhere else in `vscode/src` is outside it (today `extension.ts:620` is the only `statusBarItem.text =` and it takes `statusPresentation`'s value, but nothing asserts that). Note for whoever fixes this: the §7 half of the record's overstatement is already true — the documented-side charset is now `[A-Za-z0-9._-]` and a documented setting that does not exist goes red — so only the §5 half needs either a stronger extraction or a weaker sentence.

**Reproduce:** From the repo root, append to `vscode/src/clientPresentation.ts` either of: (a) ``export const STATUS_UNTRUSTED_TEXT = `$(lock) OvalLSP: Untrusted workspace`;`` (backticks) (b) `export const STATUS_X = '$(check-all2) OvalLSP: Done';` (digit in the icon name) Then `cd core && bundle exec rspec spec/meta/design_doc_drift_spec.rb` → 6 examples, 0 failures, while §5's fence lists five strings and the file now defines six. For contrast, the double-quoted form the finding was raised against — `export const STATUS_UNTRUSTED_TEXT = "$(lock) OvalLSP: Untrusted workspace";` — goes RED, which is the half that was fixed. For the inert reject: delete the `.reject { |s| s.include?("\#{") }` line from design_doc_drift_spec.rb → 6 examples, 0 failures. Restore with `git checkout -- vscode/src/clientPresentation.ts core/spec/meta/design_doc_drift_spec.rb`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.210 The plugin-sdk check asks whether a name is defined anywhere under core/lib/ovallsp/plugins, not whether it is callable on the receiver the document shows

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/design_doc_drift_spec.rb` (the `plugin-sdk.md names only registration methods that exist` example), `docs/design/plugin-sdk.md`

`named` is every `register_[a-z_]+` word anywhere in plugin-sdk.md; `defined` is every `^\s*def (register_[a-z_]+)` across `core/lib/ovallsp/plugins` and `plugins.rb`, flattened into a single set with no record of which object defines which name. Four receivers contribute: `Ovallsp::Plugins` singleton (`register_static`, `register_runtime`), `StaticContext` (`register_declarations`, `register_generic_rules`, `register_diagnostics`), `RuntimeContext` (`register_snapshot_section`, `register_reload_hook`). The document's entire purpose is to tell a plugin author what to call on the `context` its examples yield, and `named - defined` cannot tell such a call apart from a call on a different class in the same directory — nor from a module function, nor from a private method, since `^\s*def` matches under `private` just as well. So the document can instruct an author to write a line that raises `NoMethodError` at load time and the example stays green; that is the same class of falsehood the example was created for, since `06`'s five registration methods had been fictional. This is not just a stronger-assertion wish: the check answers a question about a directory while the example's own comment states the guarantee as "[e]very method it shows a plugin author calling must exist", which is a claim about a receiver. Fix shape: load the classes and compare against `StaticContext.public_instance_methods` / `RuntimeContext.public_instance_methods` / `Ovallsp::Plugins.singleton_methods`, attributing each name in the document to the receiver its fenced block yields.

**Reproduce:** In `docs/design/plugin-sdk.md`, inside the `Ovallsp::Plugins.register_static("ovallsp-my-plugin") do |context|` block, add `context.register_static("nested")` and `context.register_reload_hook { }` above the existing `context.register_declarations([`. Then `cd core && bundle exec rspec spec/meta/design_doc_drift_spec.rb` → 6 examples, 0 failures. Confirm both lines are false: `cd core && bundle exec ruby -e 'require "ovallsp/plugins/static_context"; c = Ovallsp::Plugins::StaticContext.new("x"); p c.respond_to?(:register_static); p c.respond_to?(:register_reload_hook); p c.respond_to?(:register_declarations)'` → `false`, `false`, `true`. `git checkout -- docs/design/plugin-sdk.md`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.211 `check_pinned_mutations.rb --verify-only` prints the applier's conclusion after applying nothing

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/check_pinned_mutations.rb`, `core/spec/meta/pinned_mutations_spec.rb`

In `--verify-only` every entry takes the `next` at line 105 after only a `rspec --dry-run` selection check: no file is written, no example is run to failure. Control still falls through to line 139, which prints `check-pinned-mutations: N mutation(s), every one caught by the example that names it.` and exits 0. `pinned_mutations_spec.rb` shells out in exactly this mode, so every ordinary suite run emits a sentence asserting a property that run did not establish -- the project's own "the answer that would be right if nothing had gone wrong" shape, in the checker built to detect it, and the shape the script's own header warns about ("a checker that cannot see the thing it checks reports the same 'not caught' as a checker that works"). The failure branch is wrong symmetrically: it warns `N of M mutation(s) not caught` for what in this mode can only be manifest-shape problems (an example selecting zero or two). The guarantee itself is genuinely held -- ci.yml's "Pinned mutations" job runs the real applier -- so what is defective is the claim the message makes, not the coverage. The fix is a mode-specific summary: `--verify-only` establishes that the manifest is well-formed and its examples still exist and select uniquely, and should say only that.

**Reproduce:** At HEAD: `time ruby scripts/check_pinned_mutations.rb --verify-only` -> prints "check-pinned-mutations: 21 mutation(s), every one caught by the example that names it." in about 9 seconds wall, with no per-entry `pinned <label>` line, while the real applier runs 21 full rspec invocations against mutated source. Read `scripts/check_pinned_mutations.rb:96-105` (the `verify_only` early `next`) against `:137-141` (the unconditional summary), and `core/spec/meta/pinned_mutations_spec.rb:16` (the suite's invocation, `--verify-only`).

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.212 pinned_mutations.yml's header documents the mechanism the applier abandoned, and a scope it no longer has

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/pinned_mutations.yml` (header, lines 16-30), `scripts/check_pinned_mutations.rb`

The manifest header says the script "applies each mutation to a throwaway copy of `core/lib` and runs the named example against it. The live tree is never modified: the copy goes first on the load path." That is the arrangement the script's own header records as tried and abandoned because it silently does not work -- the Gemfile's `gemspec` puts the real `core/lib` at the front of `$LOAD_PATH`, so the first version reported all four mutations uncaught -- and the code writes into the real file and restores it (`File.write(source, original.sub(...))`, `source = File.join(ROOT, entry["file"])`). The header states the *reverse* of the actual safety property, in the dangerous direction: a reader is told the applier cannot touch the tree, when it edits `core/lib` and `scripts/` in place and CLAUDE.md forbids running it while anything else mutates the tree. The same header also says `file` is "a path under `core/lib`", while seven of twenty-one entries name `scripts/`. Both halves went stale in one commit (e100388), which added the `scripts/` entries and left the header untouched -- the documentation-is-part-of-the-change failure, inside the apparatus 0.2.14 built to catch that failure elsewhere.

**Reproduce:** `sed -n '16,31p' core/spec/meta/pinned_mutations.yml` beside `sed -n '15,30p;105,125p' scripts/check_pinned_mutations.rb`. Then `grep -c '^ file: scripts/' core/spec/meta/pinned_mutations.yml` -> 7, against `grep -c '^- why:'` -> 21. `git show e100388 --stat` shows the yml gaining those entries with its header unchanged.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.213 A mutation entry's stated reason describes a mutation different from the one it encodes

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/pinned_mutations.yml` (the `check_doc_links`' SKIP entry, lines 142-147), `scripts/check_pinned_mutations.rb`

The entry's `why` reads "check_doc_links' SKIP -- widening it to exclude core/ drops inspection from 537 files to 117 ... which is round 2's break verbatim." None of its three claims derives. The encoded replacement `"|core/spec/fixtures/rails_real/" -> "|core/|"` splices an *empty alternative* into SKIP (`\A(core/vendor/|vscode/node_modules/|core/||(.*/)?...)`), so SKIP matches every path and the checker inspects 0 files, not 117. The `why`'s own literal description -- exclude `core/` -- gives 210. Round 2's actual regex, recorded verbatim in 046's `doc-links` section, gives 118. And the unmutated checker inspects 536, not 537. The pin works (the coverage floor fails on 0 inspected), so nothing catches the entry: `check_pinned_mutations.rb` validates that `from` matches exactly once and that `example` selects exactly one, and validates nothing that relates `why` to `from`/`to`. This is a claim about this tree that was typed rather than derived, sitting in the file whose own header says a comment claiming an example distinguishes something is a claim about this tree and must be derived. The countermeasure shape available: have the applier print what the mutation actually did (inspected-count, or the failing assertion) so a `why` carrying numbers can be checked against them -- or drop derived numbers from `why` and cite 046 for them.

**Reproduce:** At HEAD, without modifying the tree: `ruby -e 'require_relative "scripts/repo_files"; files = RepoFiles.list(Dir.pwd); src = File.read("scripts/check_doc_links.rb")[/^SKIP = %r\{(.*)\}$/, 1]; {"encoded" => src.sub("|core/spec/fixtures/rails_real/", "|core/|"), "why-as-written" => src.sub("core/spec/fixtures/rails_real/", "core/")}.each { |n, s| puts "#{n}: #{files.reject { |f| f.match?(Regexp.new(s)) }.length}" }'` -> `encoded: 0`, `why-as-written: 210`. `ruby scripts/check_doc_links.rb | head -1` -> "536 file(s) inspected". Round 2's four-root regex from docs/design/tasks/046-0.2.14-making-the-record-true.md:724, run the same way -> 118.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.214 generate_sbom.rb's header tells the reader a stale SBOM is caught by nobody, in the release that made a spec catch it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/generate_sbom.rb` (header, lines 17-20), `core/spec/meta/sbom_spec.rb`

The header ends "Run manually via `ruby scripts/generate_sbom.rb` whenever ... changes; not run automatically by CI/tests (RELEASE_CHECKLIST.md item 8)." The same change set added `core/spec/meta/sbom_spec.rb`, which runs `ruby scripts/generate_sbom.rb --check` on every suite run and a second time into a tmpdir with a planted divergence to prove `--check` is not inert -- and the `--check` block installed a few lines below in the same file carries the comment "046's C7", the same marker as the spec. So the file's own header contradicts the mechanism its own commit installed, in the direction that matters: it tells a contributor that a stale SBOM goes unnoticed until somebody remembers to run this by hand, which is precisely the state `sbom_spec.rb` was written to end (its own comment: "What enforced it before this existed: nothing").

**Reproduce:** `sed -n '14,21p' scripts/generate_sbom.rb` against `core/spec/meta/sbom_spec.rb`. `cd core && bundle exec rspec spec/meta/sbom_spec.rb` -> 2 examples, 0 failures (neither skipped nor pending), the first shelling out to `ruby scripts/generate_sbom.rb --check`. `git diff main..HEAD -- scripts/generate_sbom.rb` shows the `--check` path added and the header untouched in one diff.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.215 A scripted comment rewrite in corpus_diagnostics.rb cut a sentence mid-clause, and nothing in the tree can see it

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/corpus_diagnostics.rb` (lines 169-175)

The comment above the engine assembly reads "... That is not a smaller measurement, it is a measurement of something else, and it is why a" and the next line starts a new bolded sentence, "**Assembled, not wired here** (`042`'s D8)." The clause after "why a" was cut -- 024.140's class exactly, a scripted edit whose end boundary silently missed. It is byte-identical on `main`, so it predates the change set, and that is the point rather than a mitigation: 0.2.14 is a whole-repository audit whose subject is the record matching the tree, and the two checks that read prose (`duplicate_headings_spec`, `check_doc_links`) see structure and citations respectively -- neither can see a sentence that simply stops. Whether this is worth a mechanism or only a repair is the open question; a heuristic scan of every tracked .rb/.yml/.md for the same shape produced only this one genuine hit against a large volume of ordinary wrapped prose, which suggests a repair plus a note, not a checker.

**Reproduce:** `sed -n '169,176p' scripts/corpus_diagnostics.rb`. Confirm it is pre-existing rather than introduced by 0.2.14: `git show main:scripts/corpus_diagnostics.rb | sed -n '70,80p'` yields the identical text.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.216 The register's entry number is parsed by six readers with three grammars, so a sub-numbered entry is indexed as a duplicate of its parent

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `scripts/reindex_findings.rb` (`number_of`, `title_of`, `rebuild`'s split), `core/spec/meta/deferred_findings_spec.rb` (the "indexes every entry" scans, the Area-line split), `core/spec/meta/measured_claims_spec.rb` (`register_numbers`, `CITATION`), against `scripts/deferred_findings.rb` (`ENTRY_HEADING`, `METADATA_BLOCK`)

046's C4 unified the reading of an entry's *yaml block* into `DeferredFindings.entries`, and its comment and `measured_claims_spec`'s both now say `DeferredFindings` is "the single parser of this file". It is not the single parser of the *primary key*. The entry number is still read by six hand-rolled regexes in three incompatible grammars: `DeferredFindings::ENTRY_HEADING` = `/^## (024\.[0-9R][0-9.]*) /` (accepts sub-numbers), `ReindexFindings.number_of` = `/\A## (024\.[0-9R]+)/` (truncates, and needs no trailing space), `ReindexFindings.title_of` = `/\A## 024\.[0-9R]+ (.*)/` (fails outright), `ReindexFindings.rebuild`'s split `/^(?=## 024\.)/`, `deferred_findings_spec`'s two scans `/^## (024\.[0-9R]+)/` and its Area split `/^## (?=024\.[0-9R]+ )/`, `measured_claims_spec#register_numbers` = `/^## (024\.[0-9R]+) /` (matches nothing), and `measured_claims_spec::CITATION` = `/\b024\.([0-9]+|R[0-9]+)\b/` (truncates). A sub-numbered entry is a supported shape — `scripts/deferred_findings.rb:38` was widened for it deliberately and `core/spec/meta/deferred_findings_spec.rb:250` asserts "reads a sub-numbered entry as itself, in both readers" — so this is not an input nobody promised to handle. Two consequences, one latent and one live now: 1. **Latent.** Adding `## 024.13.1 A sub-numbered follow-up` makes `reindex_findings.rb` emit a second index row numbered `024.13`, with an empty title and the dead anchor `#02413-`, adjacent to the real `024.13`. `entry_key` gives both `[0, 13]`, and Ruby's `sort_by` is not stable, so which of the two comes first is unspecified. The check that exists to catch exactly this — "indexes every entry, so the table cannot silently omit one" — passes, because both of its scans truncate the same way and therefore agree while both are wrong. This is C4's own declared failure mode, recorded at `046` line 363 as the thing C4 was supposed to prevent. 2. **Live at HEAD, no register change needed.** `CITATION` cannot express a sub-number, so a citation of `024.13.9` — a sub-entry that has never existed — resolves to `024.13` and passes the dangling-pointer guard. The asymmetry is visible in one run: `024.<n>.1` is correctly reported dangling (because `024.<n>` does not exist) while `024.13.9` is accepted. The root cause is not any one regex. It is that the primary key has no single reader, and each reader is the only reader of its own result — the same shape `024.68` records for the metadata grammar, one layer down. Fix direction: route every number read through `DeferredFindings` (a `number_of`/`title_of` there, and a `CITATION` derived from `ENTRY_HEADING` rather than written independently), or delete sub-number support outright — widen nothing, narrow `ENTRY_HEADING` to `[0-9R]+`, and delete the spec at line 250 that promises it. Either is coherent; what is not coherent is one reader promising the shape and five others corrupting it.

**Reproduce:** At HEAD, from the repository root. The divergence, in one line: ruby -r./scripts/deferred_findings -r./scripts/reindex_findings -e 'h="## 024.13.1 X\n\n```yaml\nstatus: open\nkind: defect\n```\n"; p DeferredFindings.headings(h), ReindexFindings.number_of(h), ReindexFindings.title_of(h), h.scan(/^## (024\.[0-9R]+) /).flatten' prints `["024.13.1"]`, `"024.13"`, `""`, `[]`. The full round trip (do this on a scratch copy, or in memory — it rewrites the register). Insert a valid sub-numbered entry immediately before `## 024.14 `, with a yaml block and **no** `**Area:**` line: ## 024.13.1 A sub-numbered follow-up ```yaml status: open kind: friction target: unscheduled ``` prose. Bump the `register-entries` marker in the register from 152 to 153, run `ruby scripts/reindex_findings.rb`, then `cd core && bundle exec rspec spec/meta/deferred_findings_spec.rb spec/meta/measured_claims_spec.rb`. Both files are green, and the index carries | [`024.13`](#02413-) | open | unscheduled | | Note the variant matters: give the sub-entry an `**Area:**` line and `deferred_findings_spec`'s "states each entry's Area exactly once" fails with the misleading message `024.13 (2 Area lines)` — because its split truncates too, and merges the sub-entry's body into its parent's chunk. The suite is fully green only for the no-Area variant. The citation half needs nothing inserted: ruby -rset -e 'reg=File.read("docs/design/tasks/024-deferred-review-findings.md",encoding:"UTF-8"); known=(reg.scan(/^## (024\.[0-9R]+) /).flatten+reg.scan(/^\| `(024\.[0-9R]+)` \|/).flatten).to_set; ["024.13.9","024.<n>.1"].each{|c| n=c[/\b024\.([0-9]+|R[0-9]+)\b/,1]; puts "#{c} -> 024.#{n} known? #{known.include?("024.#{n}")}"}' prints `024.13.9 -> 024.13 known? true` and `024.<n>.1 -> 024.<n> known? false`.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

## 024.217 `rescue_verdicts.yml`'s header tells a reader the 98 arguments are unargued defaults, and names a verdict the checker rejects as the safe one

```yaml
status: open
kind: defect
user-visible: no
user-visible-note: >
  Internal. It is a defect in what this project uses to decide whether
  a change is sound, not in what the extension answers.
target: 0.2.16
```

**Area:** `core/spec/meta/rescue_verdicts.yml` (header, lines 3-16), `scripts/check_swallowed_failures.rb` (the no-verdict problem message)

The header of `rescue_verdicts.yml` describes a state of the file that ended in 0.2.13. It says the verdicts "are a *first pass*: every site whose handler raises or reports was marked `surfaces` mechanically, and the rest are marked `swallows` — which is the safe default and the honest one, since nothing has yet been argued. Moving one to `contained` is the review work `024.122` describes." Every clause of that is now false. No entry carries `swallows` — the only three occurrences of the word in the 158-entry file are in this header. All 98 non-`surfaces` sites carry `contained: <why>` with an argument written at the site, which is the review work the header calls outstanding; `024.122` is `status: fixed`, `released-in: 0.2.13`; and `CLAUDE.md`'s "Catching a failure and continuing is not the default" section records the enumeration as done, saying "Two verdicts are allowed". Worse than stale: it is an instruction that fails. `scripts/check_swallowed_failures.rb` rejects any `swallows` verdict (its own comment: "**The column is empty, and stays empty.** ... `swallows` remains spellable so that this message can name it, not so that a site can sit in it"). So an author who adds a new rescue site and follows the header's "safe default" fails the suite and the CI job. The checker's own no-verdict message points the same way — "Add one to core/spec/meta/rescue_verdicts.yml -- surfaces, contained, or swallows" — offering a verdict its very next branch refuses. The cost is not cosmetic. The 98 arguments are the only thing standing between this project and the class of defect the section exists for, and the file's header tells the next reader they are mechanical placeholders nobody has thought about — which is exactly the reason not to trust one, and exactly the reason not to bother reviewing one. `CLAUDE.md` already flags these arguments as "one author's, reviewed by nobody else yet"; the header makes that harder to act on rather than easier. Nothing checks that this header stays true.

**Reproduce:** At HEAD, from the repository root: sed -n '1,17p' core/spec/meta/rescue_verdicts.yml # the claim grep -n swallows core/spec/meta/rescue_verdicts.yml # lines 4, 9, 14 only — all header prose ruby scripts/check_swallowed_failures.rb # "158 rescue site(s) -- 60 surface, 98 contained, and none swallowing." ruby -ryaml -e 'v=YAML.safe_load_file("core/spec/meta/rescue_verdicts.yml"); puts v.count{|_,x| x.to_s.start_with?("swallows")}' # 0 Then, for the failing instruction: add a `rescue StandardError` to any file under `core/lib`, give it the verdict the header calls the safe default (`swallows`), and run `ruby scripts/check_swallowed_failures.rb` — it exits non-zero telling you `swallows` is not allowed. Revert. Cross-check the record: `024.122` in `docs/design/tasks/024-deferred-review-findings.md` reads `status: fixed` / `released-in: 0.2.13`, and `scripts/check_swallowed_failures.rb` lines 73-76 state the contrary of the header in the same repository.

*Raised in 0.2.14's review rounds; triaged into an entry after the round
closed, and confirmed live against HEAD rather than assumed.*

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


## 024.R3 Feature parity roadmap, measured against Pylance

```yaml
status: open
kind: roadmap
target: unscheduled
```

roadmap. Its three 0.2.0 rows are done; the table below carries a **shipped in** column so the entry can be read as a record rather than only as a plan. Two of the three shipped outright; whole-project diagnostics shipped without a capability row, because the E2E example written for it did not pass (024.14) -- README marks that row ⚠️ and both changelogs say so.

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
| Diagnostics across the whole project | Open files only | **0.2.0** | 0.2.0, no capability row (024.14) | The first thing a user noticed as missing. `publishDiagnostics` fires from `reindex`, which only runs for open buffers, so a mistake in a file you are not looking at is invisible. Needs a workspace-wide pass plus a budget, or LSP pull diagnostics. |
| Docstrings in hover and completion | Type, origin and definition location only | **0.2.0** | 0.2.0 | Ruby has RDoc/YARD comments directly above a `def`. Nothing reads them. Hover shows what a thing *is* but never what it is *for*, which is most of hover's value. |
| Semantic highlighting (semantic tokens) | None | **0.2.0** | 0.2.0 | Unusually valuable in Ruby, where `foo` alone is ambiguous between a local variable and a method call on self — the engine already knows which, and the editor currently does not. Covers ERB templates' Ruby regions too, which the shared extraction path now makes free. Distinct from shipping a TextMate grammar, which is a non-goal: VS Code already associates `.erb`, and another grammar would only collide. |
| Inlay hints (inferred types, parameter names) | None | **0.3.0** | — | The type engine's answers are only visible on hover today. Inlay hints put them where the code is, which is the difference between a feature people use and one they remember exists. |
| Code actions / quick fixes | None | **0.3.0** | — | Each existing diagnostic implies one: define the missing method, correct the route helper name, fix the argument count. A diagnostic that only complains is half a feature. |
| Go to type definition | Go to definition only | **0.3.0** | — | Cheap given `explainType` already resolves the type: jump from an expression to the class it evaluates to, rather than to the method being called. |
| Document highlight (occurrences in file) | None | **0.3.0** | — | Small and self-contained: the reference index already answers this workspace-wide, so scoping it to one file is nearly free. |
| Call hierarchy | Find references only | **0.3.0** | — | An incremental step on the same index. Callers/callees of a method, navigable, rather than a flat list. |
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

---


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
status: open
kind: roadmap
target: 0.3.0
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
status: open
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





