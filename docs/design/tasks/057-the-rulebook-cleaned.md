# 057 — The rulebook, cleaned: one card, the documents behind it, and the contributor pages retired

**Branch:** `worktree-057-rulebook-cleanup`, merging into `main` by pull
request. Not a release: no version moves and no capability row moves.

**Scope:** what the maintainer asked for on 2026-09-03, after an inventory
of everything this repository designates as mandatory — about 1,800 lines
of rule prose across the documents this sentence names: the auto-loaded
`CLAUDE.md`, 803 lines and 46KB; `AGENTS.md`, 199; the contributing
guide and its translation, 530; `docs/DOCUMENTATION_MAP.md` and its
translation, 277. `docs/PUBLISHING.md`, `docs/RELEASE_CHECKLIST.md` and
the register's legend carry more and stay where they are:

1. Remove the documents written for external contributors, and mark their
   return as a 1.0.0 item.
2. Take the history out of the rule documents. It is recorded, and it is
   not read while working.
3. Restructure as a table of contents at the top, pointing at flat rule
   and memo documents, and stop keeping `AGENTS.md` and `CLAUDE.md` in
   step by hand.
4. Separate the project's norms from the maintainer's personal ones; the
   personal ones leave the repository.

## The `@AGENTS.md` import, verified

`CLAUDE.md` is now one import line and a note. What that rests on:

- **The documentation.** Claude Code's memory documentation
  (`https://code.claude.com/docs/en/memory`, "Import additional files")
  states that `@path/to/import` in a `CLAUDE.md` is expanded and loaded
  into context at launch, that a relative path resolves relative to the
  importing file, that imports nest to four hops, that code spans and
  fenced blocks are not parsed, and — as its own worked example — that a
  repository using `AGENTS.md` for other agents should "create a
  CLAUDE.md that imports it so both tools read the same instructions
  without duplicating them", with Claude-specific notes appended below
  the import. That is this file's shape exactly.
- **The installed binary.** The CLI on this machine was 2.1.229 when
  this was checked and had updated itself to 2.1.259 by the second
  review round. Both carry the approval prompt "This project's CLAUDE.md
  imports files outside the current working directory", twice in each;
  2.1.259, the one that will read this tree, also carries the dialog
  title "Allow external CLAUDE.md file imports?", the log line "Skipping
  non-text file in @include:", and guidance text that says to use
  "`@path/to/import` syntax" to inline a document. That shows the feature
  exists in the installed binary; it does not show it resolving
  `@AGENTS.md`. A first draft of this bullet cited two other strings, and
  a review round traced both to unrelated code. `@AGENTS.md` resolves
  inside the working directory, so the prompt does not apply to it.
- **A live session, run once the maintainer had logged the CLI in.**
  Claude Code 2.1.259, `claude -p` with `--model haiku --max-turns 1`,
  from a wrapper that unsets the parent session's nested-session guard.
  A scratch directory whose `CLAUDE.md` said only "Project note" answered
  `NONE` to "what is the secret word in your project instructions"; the
  same directory with an `@`-import of a note under `sub/` added to
  `CLAUDE.md`, and the note holding a sentinel, answered the sentinel.
  Then this worktree itself, asked to list the second-level headings of
  its project instructions
  and nothing else, printed the card's seven headings verbatim, from
  "Where the rules are" to "Branches, commits, releases": the content of
  `AGENTS.md`, reached through `CLAUDE.md`'s one line. Until then this
  bullet said the test had not been run, because the CLI was not logged
  in and logging it in is not something an agent does; the maintainer's
  own session could not stand in for it either, since a session loads
  its instructions once, at start, and that one had started on the old
  file.

The two Cowork restrictions the documentation lists apply to user-scope
files and to imports that resolve outside the working directory; a
project-level import of a sibling file is neither.

## What was removed, and where each thing went

| Removed | Where it went |
|---|---|
| `CONTRIBUTING.md`, `CONTRIBUTING.ja.md` | the internal half — setup, the suites that skip, preflight, branches, the kept-branch rule, the commit rules — to `docs/DEVELOPMENT.md`; the `/Applications` disclosure to `SECURITY.md` and `SECURITY.ja.md`, which stay bilingual because a user reads them; the "not accepting contributions" statement to `README.md`'s opening note and to `024.R10` <!-- deleted --> |
| `CODE_OF_CONDUCT.md`, `CODE_OF_CONDUCT.ja.md`, `SUPPORT.md`, `SUPPORT.ja.md` | nowhere: written for a contributor who cannot yet arrive. `024.R10` brings them back at 1.0.0 <!-- deleted --> |
| `docs/DOCUMENTATION_MAP.ja.md`, `docs/PUBLISHING.ja.md`, `docs/CLIENT_BEHAVIOUR.ja.md` | nowhere: internal process documents are one language, as `docs/RELEASE_CHECKLIST.md` and `docs/RELEASE_ARTIFACTS.md` already were. The translation pairs the inventory found with no machine check were these, the contributing guide, the code of conduct and the support page — and `vscode/THIRD_PARTY_NOTICES.md`'s, which ships in the VSIX and stays <!-- deleted --> |
| `CLAUDE.md`'s 803 lines | the rules to `AGENTS.md`, one line each; the how-to to the four documents below; the history to the register entries and task documents each paragraph already cited (the next section lists what had no other record) |
| `AGENTS.md`'s 199 lines | the card: one line under its budget of 120 after the third round, so a new line has to pay for itself |
| `agents_restates_spec.rb`, `agents_pointer_spec.rb` | `agents_card_spec.rb`: the card fits its budget, `CLAUDE.md` is exactly the import and its note, the card names no release or branch in any spelling this project has used and no task file beyond the two it sends a reader to, and every document the card's index names declares a card section that exists |
| `client_behaviour_spec.rb`'s Japanese-edition examples | retired with the translation they compared. They held a row for every English row, translated rather than copied, with the same rows marked checked |
| `docs/DOCUMENTATION_MAP.md`'s "Before a release" | its manual steps to `docs/RELEASE_CHECKLIST.md`, beside the `--targeting` step; the other two were already what preflight's full suite and CI's secret-scan job run |
| `AGENTS.md`'s "read 045 when a session opens" | nowhere: 045 scoped 0.3.0, which has shipped |

Citations of the removed files: 43 rewritten to where the content went,
11 more in the Japanese changelog rewritten to `docs/PUBLISHING.md`, 20
footer links removed from the site's ten pages, and 29 lines in task
records and the resolved register marked as recording a deletion — the
marker `scripts/check_doc_links.rb` provides for a record that names
something gone. Every edit was one script that validated every anchor
before writing anything — the replayable form `docs/DEVELOPMENT.md` asks
of a scripted edit; the script is not in the tree because it names the
deleted files at every anchor.

A second script of the same shape repointed every comment — in library
code, specs, scripts, the CI workflow and one TypeScript test — that told
a reader to see a `CLAUDE.md` section now name the
document the section moved to. Three sentences those pointers relied on
and the new documents lacked were added first: the two backgrounding
false results and the "checker that cannot see what it checks" rule in
`docs/MEASURING.md`, and the note that `contained` verdicts are one
author's in `docs/CODE_DISCIPLINE.md`. What still says `CLAUDE.md` outside
the records is deliberate: two coverage assertions that the file is
scanned, one history line, the card spec, the documentation map's row
describing the import, and `.gitignore`.

## What preflight said

Run in the worktree before the review rounds: 2 of 13 checks failed,
both on one fact. A local release branch for the next version — checked
out in another session's worktree, not on the remote — exists that no
task document names, and `release_pointers_spec` inside the full suite
and the script check of the same name both report it. The record that
names that branch is that release's to write. This paragraph does not
spell the branch, deliberately: the check accepts any mention of the name
as naming it, and a first draft of this paragraph satisfied the check by
quoting the complaint. `docs/ISSUES.md`'s intake carries that weakness.

Run again after round 1: the same, plus the documented example count,
stale by one after the card spec grew an example, and re-derived with
`scripts/documented_counts.rb` to 3,109. Run a third time after round 2,
before round 3: 3,109 examples, one failure, and that failure and the
script check are the same external branch; the other eleven checks
passed. Run a fourth time on the tree that ships, after round 3: 3,108
examples (the card spec lost an example in the rewrite), the same one
failure and the same script check, the other eleven green. The three
environment-dependent suites ran 118 examples each time, none skipped. Every later commit on
the branch ran it again — after the live import test, and after the
alignment pass below — with the same result each time, until the last
run added a second external fact of the same kind: the other session's
release was tagged, and `release_artifacts_spec` asks for a row in
`docs/RELEASE_ARTIFACTS.md` that only that release can write. This
branch is based on `main` before that release; bringing it up to date at
merge time carries the row in.

## The documents behind the card

| Document | What it carries, from where |
|---|---|
| `docs/DEVELOPMENT.md` | layout, setup, the skipping suites, running tests, preflight, the two sweeps, branches and pull requests, the public-repository rules, edits that lose work — from the contributing guide and from `CLAUDE.md`'s preflight, branch, privacy and working-practice sections |
| `docs/CODE_DISCIPLINE.md` | test-first and the source of an expectation, unpinned behaviour, code that deletes, rescue verdicts, the simplest thing, design not symptom, the self-scanning trap — from `CLAUDE.md`'s six mandatory sections on writing code |
| `docs/MEASURING.md` | the rules and the false results behind them — from `CLAUDE.md`'s measurement section |
| `docs/REVIEW_LOOP.md` | cadence, the bound, fix-don't-add, the same-place rule, how to ask, what a round leaves behind — from `CLAUDE.md`'s three review sections and its promotion rule |

Each keeps the rule, the check that enforces it and the number of the
record; the narrative is gone. Where the narrative was the only record of
something, this is now the record:

- `CLAUDE.md`'s "Unpinned behaviour" section recorded that rounds 9–12 of
  the 0.1.5 review found four of their last six findings to be lines
  revertable with the suite green, one a qualified-name guard whose
  removal would have shown a view another controller's inferred types,
  and that a `reset_budget: false` argument inside a whole-method hunk
  survived the sweep untested. `docs/CODE_DISCIPLINE.md` keeps the blind
  spot; this line keeps the instances.
- Its "Promoting a finding" section recorded the 0.2.14 split of `024.90`
  into nine entries without running one: `024.130` did not reproduce, and
  `024.131` reproduced backwards. Both entries carry it.
- Its "Two working-practice traps" section recorded a ten-hour wait on a
  truncated output file, and a `preflight` reported complete while still
  running because of a trailing `&`. Both are about the harness rather
  than the repository, and are on the personal side now (below).
- Everything else it carried cites the entry or task document that
  records it: `024.15`, `024.36`, `024.47`, `024.109`, `024.122`,
  `024.126`, `024.130`, `024.131`, `024.150`, `024.195`, `024.196`,
  `024.220`, `024.223`, `024.225`, `024.231`, `024.284`, and the task
  documents 026, 027, 028, 033, 038, 046 and 048.

## Project norms and personal ones

The maintainer's direction: what exists only in the agent's memory is the
maintainer's own convenience, not a rule for a contributor, and the two
are better kept apart. So the card carries the project's norms only. What
left the repository for the memory side, because it is about one machine
or one harness rather than this tree: a shell whose `grep` is a `ugrep`
wrapper, `zsh` not splitting a variable, a `cd` that persists between
harness commands, a heredoc that aborts half-applied, waiting on a
background command by polling its output, detaching a command with a
trailing `&`, and the constraints on how sub-agents may be spawned and on
which model. `docs/MEASURING.md` keeps the general form of the ones about
a measurement — print the working directory, invoke the implementation by
absolute path — because those are true on any machine.

## What this did not do, and why

- **`preflight` still runs the three environment-dependent suites twice**:
  once inside the full suite without a JSON report, once on their own
  with one. Merging them is a change to the release procedure and to two
  specs, and this change set is already large; it is a following pull
  request.
- **The required status checks on `main` are the owner's setting.** The
  inventory found `Packaged Core (darwin-arm64)`, added in 0.3.2, not
  among the ten required checks, and the Ruby 3.3 job required while
  `docs/SUPPORT_MATRIX.md` calls that version unsupported. Neither is
  repository state, so neither is in this change.
- **`docs/DOCUMENTATION_MAP.md`'s trigger table is still walked by
  hand.** Turning it into data a preflight check reads is the
  mechanisation the card's "Documents and the record" line would then
  cite. Not started here, so that this change stays a deletion and a
  restructuring.

## Review rounds

Recorded per round, method first, as `docs/REVIEW_LOOP.md` asks.

### Round 1 — `diff`

An independent reviewer, given the change set and told what a defect is
and what had been measured. Seventeen findings, every one verified
against the tree before it was reported, and one process note that
stands above them: **the tree moved while the round read it.** The
comment-pointer sweep above ran during the round, and the reviewer saw
54 files change under it. By this project's own cadence a round reviews
a fixed thing, so this round closes nothing; its findings are fixed and
the next round is the one that can close.

| # | Finding | Disposition |
|---|---|---|
| 1 | `docs/DOCUMENTATION_MAP.md`'s install row still required updating `docs/PUBLISHING.md`'s deleted translation | fixed |
| 2 | Its client-behaviour row still named `docs/CLIENT_BEHAVIOUR.md`'s deleted translation | fixed |
| 3 | `docs/DEVELOPMENT.md` said both sweeps refuse a dirty tree; only the hunk sweep does | fixed: the sentence says which |
| 4 | `docs/REVIEW_LOOP.md` typed "three of eight" against `024.109`, which records four examples with two never written down | fixed: the number is gone |
| 5 | The card's test-first line cited `024.15`, the same-place entry | fixed: cites 038 and this record |
| 6 | Retiring `agents_pointer_spec` dropped its "names no task file by number" guard | fixed: carried into `agents_card_spec`, fenced to the session-start bullet, with its planted control |
| 7 | The compaction-and-handoff line was lost, in the arrangement that makes it most load-bearing | fixed: restored, naming `.claude/` |
| 8 | `docs/DEVELOPMENT.md` said every CI job is a required check; ten are, and the record of the two exceptions, the zero-review reason and the GH006 verification was gone | fixed: all four restored |
| 9 | The shipped changelog, both languages, said the `/Applications` incident wrote three rules into `CLAUDE.md`, which now holds none | fixed: points at `docs/CODE_DISCIPLINE.md` |
| 10 | `docs/DEVELOPMENT.md` said the register is edited through `scripts/issues.rb`; entries are written by hand and the index generated | fixed |
| 11 | `engines.vscode` was cited as a Node.js version | fixed: Node 20 is what CI installs |
| 12 | The ADR rule from the contributing guide was lost | fixed: `docs/CODE_DISCIPLINE.md` and the card |
| 13 | The card spec's comment said 117 lines; the card was 116 | fixed: no number |
| 14 | Four deletion markers sat after a table row's closing pipe | fixed: inside the last cell. 046's own rows keep the older form |
| 15 | The card no longer pointed at `docs/ROADMAP.md` | fixed: in the index, beside 036 |
| 16 | "Adding a line costs a line" was marked *check* against a budget with slack; the intake line was marked *check* with nothing checking the order | fixed: both reworded |
| 17 | Retiring `agents_restates_spec` removed `024.150`'s declared relationship between the card and what it condenses, and findings 3 and 5 were that drift on day one | fixed: each document behind the card declares the section it stands behind, and the spec holds that section to existing |

### Round 2 — `reproduce`

A second independent reviewer, told nothing about round 1, re-derived
the change set's own claims: every number, every "moved to", every
citation, every rule of the old documents, the import evidence, and the
preflight account. Twelve findings, and the same process note as round
1: **the tree moved again** — the documented example count was
re-derived while the round was reading. Two consecutive rounds have now
read a moving tree. That is a defect in how this change set was
reviewed rather than in the change set, and the cure is procedural:
round 3 runs on a tree nothing touches until it reports. This round
closes nothing.

| # | Finding | Disposition |
|---|---|---|
| 1 | "116 lines, under a budget of 120": the card was 120 after round 1's additions | fixed |
| 2 | The card spec's comment said the budget sat above the card; it sits at it | fixed: the comment says so |
| 3 | This record said 3,108 examples; the suite had 3,109, and the documented-count check was failing on the staged tree when the round began | fixed: re-derived during the round, which is the tree moving, and the account above says what happened |
| 4 | Spelling the other session's branch in this record satisfied `check_release_pointers.rb`, whose test is any mention of the name | fixed: the name is gone from this record; the check's weakness is an intake item in `docs/ISSUES.md` |
| 5 | The CLI had updated itself from 2.1.229 to 2.1.259 during the session, and the record named only the first | fixed: both named, both checked |
| 6 | Two of the three binary strings cited as import evidence belong to unrelated code | fixed: only the import-specific approval string is cited, and the bullet says what that shows and does not show |
| 7 | "every rule, one line each": four rules live only in the documents behind the card | fixed: the card says it holds the rules to keep in mind, and that the documents carry the rest |
| 8 | `client_behaviour_spec`'s comment pointed at a record of the retired guard's properties that this document did not hold | fixed: in the removal table |
| 9 | `024.150` describes the retired specs in the present tense, and the card spec sent the reader there for the new shape | fixed: a dated postscript on the entry, and the spec comment says which shape the entry describes |
| 10 | "the unchecked translation pairs were exactly these": the code of conduct, the support page and `vscode/THIRD_PARTY_NOTICES.md`'s pair were unchecked too | fixed: named; the notices pair ships in the VSIX and stays |
| 11 | "about 3,000 lines" for documents totalling 1,809 | fixed: 1,800, with the components |
| 12 | "73 places in 54 files" counted the five sentences added to the documents; the repoints are 68 in 51 files | fixed |

One imprecision the reviewer noted without numbering — the
documentation map said the card spec keeps a task file out of the card,
where the spec fences that to the session-start bullet — is fixed in the
row.

### Round 3 — `attack`

A third reviewer, given the guarantees the change set makes and told to
make each false with every check green. Thirteen findings, and the tree
did not move under this round. Three rounds have now found defects, so
by the cadence this change set ships with the open findings recorded
rather than looping further.

| # | Finding | Disposition |
|---|---|---|
| 1 | `CLAUDE.md` could regrow a rulebook as prose, or as `* ` or `1. ` items; the spec counted only `- ` lines | fixed: the spec pins the whole file |
| 2 | The stale-claim pattern was three backticked prefixes; a branch outside backticks, a two-part version, or this change set's own `worktree-` branch passed | fixed: the pattern covers those spellings, and "in preparation" and "being prepared" |
| 3 | The task-file guard was fenced to one bullet; a number one bullet away, or without `.md`, passed | fixed for the `.md` forms: the whole card is scanned, with the two reference documents allowed. A bare "task 057" still passes, because record numbers are cited legitimately |
| 4 | The declared-relationship check read four hardcoded documents, and did not check that the declared section was the right one | fixed in part: the list is read from the card's index, so a new document is asked by default, and five more documents declare. Whether a declaration names the *right* section is not checked, and the spec says so |
| 5 | The shipped changelog's new pointer named "Code that deletes" for a rule that lives under "Unpinned behaviour is a defect" | fixed: the pointer names the document and no section |
| 6 | `SECURITY.md` gained a section that `site/security.html` does not mirror | fixed after the rounds: the maintainer asked for every contradiction to be aligned to the correct side, and the map says the page mirrors the policy, so both languages of the page carry the section now |
| 7 | The release-checklist sentence said CI's secret-scan job does the full-history gitleaks scan every time; the job scans a pull request's own commits on a pull request | fixed: the full-history scan is back as a manual pre-release step, and the sentence says what the job scans on a push and on a pull request |
| 8 | The record's list of what still says `CLAUDE.md` omitted the documentation map and `.gitignore` | fixed |
| 9 | "68 places in 51 files" did not reproduce from the diff, and its deriver is not in the tree | fixed: the counts are gone, and the sentence names the areas |
| 10 | The purpose paragraph, section 0.4's triage rule and "not a licence to run on" were dropped from the auto-loaded file, and the record did not name them as dropped | fixed: restored to the card's opening paragraph, paid for by two lines the documents behind the card already hold |
| 11 | The register sentence had landed inside the `String#sub` bullet, and called `docs/ISSUES.md` generated when only its lower half is | fixed: a section of its own, and "the generated half" |
| 12 | "per `docs/DEVELOPMENT.md`" cited a rule that document does not state | fixed |
| 13 | The deletion marker is not restricted to records: on a live document's line it admits a citation of a deleted file | open: pre-existing, and an intake item in `docs/ISSUES.md` |

Same place, consecutive rounds: the card and its spec (round 1's 6 and
17, round 3's 1 to 4) and the changelog pointer (round 1's 9, round 3's
5). For the first the countermeasure is the widened spec; for the second
— a pointer at a document section, which no check can see — the
countermeasure is not built here and is an intake item.

**Open after three rounds:** the "right section" half of finding 4,
finding 13, and a check for section citations. None is user-visible, so
each is an intake item rather than a `KNOWN_LIMITATIONS` paragraph.

### After the rounds — the maintainer's own audit

Asked which documents contradict each other and which side of each was
written later, the tree answered with nine, and the maintainer had all of
them aligned to the side that is true of it. In every case but one the
older text had been left behind by a later change; the exception is the
review loop's shipping rule, where the newer rule — intake first — was
right and the new document had copied the older one.

| Contradiction | Later side | Aligned to |
|---|---|---|
| `SECURITY.md` and its translation described plugins deleted in 0.2.16 | the deletion (0.2.16) | the threat model as `docs/SECURITY_CHECKLIST.md` states it: results read from another process, a JSON wire, the restart path |
| `docs/EXTENSION_CAPABILITIES.md` (both languages) and `docs/RELEASE_CHECKLIST.md` gate 5 called darwin-arm64 verification manual | the `Packaged Core (darwin-arm64)` job (0.3.2) | what CI runs on every push |
| `docs/REVIEW_LOOP.md` and `docs/ISSUES.md` disagreed on where an open finding goes | `docs/ISSUES.md`'s intake rule (0.3.0) | intake first, the register once driven, in both |
| `docs/RELEASE_CHECKLIST.md` gate 14 called the CI secret scan a full-history scan unconditionally | gate 14 (046) overstated what the workflow (0.2.0) does | full history on a push to `main`, the pull request's commits on a pull request |
| `scripts/preflight.rb` and `scripts/ci_status.rb` said the CI line is "not a tenth check", with thirteen checks | the checks added in 0.3.0 and 0.3.1 | no number |
| `docs/design/docs/12-release-and-support.md` said the changelog was still to be created | `vscode/CHANGELOG.md`, two days after the sentence | where the changelogs are and what they are for |
| `docs/DOCUMENTATION_MAP.md` said to read it "again before a release" after this change moved the release steps out | this change | it points at `docs/RELEASE_CHECKLIST.md` |
| `site/security.html` did not mirror `SECURITY.md`'s new section | this change | both languages of the page carry it |
| This record's preflight account stopped at the fourth run | this change | it says every later commit ran it |

Ruby 3.3 — a required CI job for a version `docs/SUPPORT_MATRIX.md`
calls unsupported — is a GitHub setting rather than a contradiction
between documents, and stays with the owner.

## 残課題

未処理の指摘はこの文書ではなく `024` に書く。
