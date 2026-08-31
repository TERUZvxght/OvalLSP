# Documentation map

[日本語版](DOCUMENTATION_MAP.ja.md)

Every document that has to change when the product does, and what makes
each one go stale. **Read this before finishing any change that a user
could notice**, and again before a release.

It exists because the alternative kept failing: the same facts live in
eight places, nobody remembers all eight while writing a fix, and the gap
is found later by a reviewer — or not at all. Checking a list is cheap.
Rediscovering which files disagree is not.

The rule this encodes is the one 0.1.11 was spent on, applied to prose
instead of code: **a fact restated in several places will be wrong in one
of them.** Where the duplication can be removed, remove it. Where it
cannot — a capability is genuinely described for three audiences — a
machine check should compare the copies, and several already do.

## The trigger table

Find what you changed in the left column. Everything to its right must be
updated in the same change, not "later".

| If you changed… | Update | Checked by |
|---|---|---|
| **A capability** (anything a user can now do, or can no longer do) | `docs/EXTENSION_CAPABILITIES.md` + `.ja.md` (add/alter the row **and** its E2E example), README's matrix in `README.md` + `README.ja.md`, `site/capabilities.html` + `site/ja/capabilities.html`, both changelogs | `core/spec/e2e/capability_coverage_spec.rb` (row ⇔ E2E example), `core/spec/meta/*_parity_spec.rb` (EN ⇔ JA). README's own pair is checked by `core/spec/meta/readme_parity_spec.rb` as of 0.2.12 — by the *shape* of the matrix, not its prose, which is what a translation may not change (024.25) |
| **A version number** | `core/lib/ovallsp/version.rb`, `core/Gemfile.lock`, `vscode/package.json`, `vscode/package-lock.json` (two places), the version badge on `site/index.html` + `site/ja/index.html`, both changelogs — and, once it is published, `docs/RELEASE_ARTIFACTS.md` | `core/spec/meta/changelog_parity_spec.rb`, `vscode/src/test/unit/versionPairing.test.ts`, `scripts/check_site_links.rb` (badge ⇔ `package.json`; run by ci.yml's site-consistency job and gating the deploy — this row omitted the badge until 0.2.3, which is how 0.2.2's drift happened), `core/spec/meta/site_version_guard_spec.rb` (that wiring itself), `core/spec/meta/release_artifacts_spec.rb` (every `v*` tag is accounted for) |
| **A roadmap item** (shipped, dropped, moved) | `docs/ROADMAP.md` + `.ja.md`, README's matrix, `site/roadmap.html` + `site/ja/roadmap.html`, the matching `024.R*` entry in `docs/design/tasks/024-deferred-review-findings.md` | `core/spec/meta/roadmap_parity_spec.rb` (README ⇔ roadmap) and `scripts/check_site_links.rb` (roadmap ⇔ `site/roadmap.html` + `site/ja/roadmap.html`, by item count per version — added in 0.2.3 after the site sat a whole release behind on two of them) |
| **The release procedure** — anything in `vscode/scripts/release.sh`, `scripts/preflight.rb`, or the gates either invokes | `docs/PUBLISHING.md`, `docs/RELEASE_CHECKLIST.md` (the evidence column names the script, and a renamed or removed one leaves a row citing nothing), `CONTRIBUTING.md` + `.ja.md` where they describe running it, and `CLAUDE.md`'s preflight paragraph — which is why that paragraph now points at `--list` instead of enumerating (`024.195`) | `core/spec/meta/release_script_guard_spec.rb`, and `046`'s C6 for the narrower claim that every script an evidence column cites is invoked by something. **Neither fires on an edit to `release.sh` itself**, which is what `024.171` records: a fix applied where the procedure runs and not where a person is told what to run |
| **A change reverted mid-release** (see CLAUDE.md's same-place rule) | a `024.*` entry naming the root cause and the direction actually needed, both changelogs if a bullet was already written for it, and the section of `CLAUDE.md` the episode informs | — |
| **A review round finding the same place the previous round did** | a mechanical countermeasure — a shared implementation, a rule moved to where the value is produced, a guard given the input it could not see — *not* a regression test for the one instance, and not a third hand fix | — |
| **A deferred finding** (`024.*`) | its `yaml` metadata block in `docs/design/tasks/024-deferred-review-findings.md` — `status`, and `released-in` once it is resolved; delete the entry once nothing in the tree still cites it by number — grep first, do not go by the calendar (see that file's own legend). Entries go in numeric order and the index at the head is generated: run `ruby scripts/reindex_findings.rb` rather than editing it | `core/spec/meta/deferred_findings_spec.rb` (status/kind/note/both-language anchors, **and that the order and index are current**) |
| **Install steps, prerequisites, or the extension id** | `README.md` + `.ja.md`, `docs/PUBLISHING.md` + `.ja.md`, `site/getting-started.html` + `site/ja/getting-started.html` | — |
| **What the extension records, keeps, or writes to disk** | `vscode/PRIVACY.md` + `.ja.md` — the single source of truth for this; `site/security.html` + `site/ja/security.html`; and every place 0.1.12 found restating the list or the cache path, each of which must point at PRIVACY rather than copy it (this list has been short three times; add to it rather than trusting it): `docs/design/docs/12-release-and-support.md`, `docs/design/tasks/019-runtime-observation.md`, `019-runtime-observation-notes.md`, `021-persistent-cache-notes.md`, the cache paragraph in `vscode/README.md` + `.ja.md`, `docs/SECURITY_CHECKLIST.md`'s observation and cache-deserialisation sections, `core/lib/ovallsp/observation/store.rb`'s `#invalidate_changed` doc, `core/lib/ovallsp/observation/observed_signature.rb`'s `code_fingerprint` doc, and **both changelogs**, which restate the disk claim in prose and went stale against PRIVACY for a whole round because this row did not name them | `core/spec/meta/privacy_parity_spec.rb` (EN ⇔ JA: section count, cross-links, three named claims, and the length of the recorded-items list) |
| **Anything about the Runtime Agent, workspace trust, or what the extension executes** | `SECURITY.md` + `.ja.md`, `site/security.html` + `site/ja/security.html`, `docs/EXTENSION_CAPABILITIES.md`'s "does not promise" section | — |
| **A known limitation** | `docs/KNOWN_LIMITATIONS.md` + `.ja.md`, and the site page that claims the opposite, if any | `core/spec/meta/deferred_findings_spec.rb` (an open `024.*` defect declaring `user-visible: yes` carries one `<!-- documents: 024.N -->` marker, at the end of the line that documents it, in each language; one declaring `no` states why) |
| **Which Ruby, Rails or platform the product accepts** — including anything in `vscode/src/platformCompatibility.ts`, `versionInfo.ts` or `rubyResolver.ts` | `docs/SUPPORT_MATRIX.md` + `.ja.md` (every affected row, not only the one you came for), `docs/KNOWN_LIMITATIONS.md` + `.ja.md`, **`vscode/README.md` + `.ja.md` — the Marketplace description, which states this in prose *and* in an environment table**, `site/getting-started.html` + `site/ja/`, the platform callout on `site/index.html` + `site/ja/index.html` (named here in 0.2.3's merge round, after the honesty pass missed it the same way this table once missed the badge), both changelogs, `core/ovallsp.gemspec`'s `required_ruby_version` if the floor moved | — |
| **Where a release's work lives** (a branch created, renamed, renumbered, or work moved between branches) | the release's `NNN-*.md` on `main` names the branch; `AGENTS.md`'s current-loop pointer; `CONTRIBUTING.md` + `.ja.md`'s "Branches and pull requests" — 0.2.3 was prepared twice in parallel because this row did not exist (CLAUDE.md "Where a release's work lives", 028). **The convention is one branch per version merged by pull request** (`release/<version>`), set 2026-09-01; a change to it lands in all four | — |
| **Which thread owns what, or which lock guards what** — a new background thread, a mutex added or reordered, a state object made mutable or immutable | `docs/design/docs/02-architecture.md`'s threading section, which states the ownership map and the lock order in one place, and `core/lib/ovallsp/document_store.rb`'s own note, which cites it | — |
| **A behaviour relied on from outside this tree** — the client, VS Code, the LSP spec, the Marketplace | `docs/CLIENT_BEHAVIOUR.md` + `.ja.md`, which is the only place such a fact is stated; everything else points at it | `core/spec/meta/client_behaviour_spec.rb` (the greppable rows against `vscode/node_modules`, and that nothing else restates one) |
| **A claim about Ruby's own semantics** — anywhere a comment, spec or record says what the interpreter does | the pasted session that carries it, which `CLAUDE.md` requires and which is now **re-run**, so editing the claim without re-running it fails; a session that raises is written with a `rescue` so its point is output rather than a stack trace | `core/spec/meta/interpreter_sessions_spec.rb` and `scripts/check_interpreter_sessions.rb` (every session in the tree, compared against what Ruby prints — `024.220`) |
| **A command id, setting, activation event, status-bar string, or workspace-trust declaration** | `vscode/package.json` is the source of truth; `docs/design/docs/07-vscode-extension.md`'s §3, §5, §6, §7 and §8 restate it and must be re-derived from it, not edited beside it | `core/spec/meta/design_doc_drift_spec.rb` (§3, §6, §7 against `package.json`, and §5 against `clientPresentation.ts` — set equality both ways, plus one example asserting nothing else assigns the status bar's text) and `vscode/src/test/unit/workspaceTrust.test.ts` (§8's trust manifest, fail-closed). Each of the five sections has a named check; they are not all the same check, and this cell says which is which because until 0.2.16 it did not — §5's comparison was a regex sample of one file that a template literal or a digit in a codicon name slipped past, and this row asserted the stronger guarantee (`024.209`) |
| **The Core↔Agent protocol** — a request, a notification, a limit, or cancellation | `docs/design/docs/05-protocol.md`. **A section describing something unimplemented says so in the section**, rather than reading as a specification somebody may implement | — |
| **A working agreement** (how this project is built, reviewed or released) | `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` + `.ja.md` | — |
| **A `rescue` added to `core/lib`, or one removed** | `core/spec/meta/rescue_verdicts.yml` — a verdict, and for `contained` the argument at the site as well | `core/spec/meta/swallowed_failures_spec.rb` and ci.yml's rescue-verdicts job, which fail on a site with no verdict, a verdict with no site, and any verdict of `swallows` (`024.122`) |

## The site is documentation

`site/` is the public face and goes stale the same way the rest does. It
is *not* generated from the Markdown docs, so nothing propagates on its
own. Treat every page as another row above.

**It is in this tree**, as of 0.2.0, and the trigger table's site rows
are followable directly — `git ls-files site` lists seventeen files.
This paragraph said the opposite until 0.2.1, because the sentence was
written while the site was still on a branch and the section two below
was rewritten when it landed without anyone re-reading this one. A
mandatory checklist that contradicts itself is worse than one that is
merely stale: a contributor who believes this paragraph skips five rows
and defers them to a list that no longer exists.

| Page | Mirrors |
|---|---|
| `site/index.html`, `site/ja/index.html` | README's pitch and capability summary |
| `site/capabilities.html`, `site/ja/capabilities.html` | `docs/EXTENSION_CAPABILITIES.md` + README's matrix |
| `site/roadmap.html`, `site/ja/roadmap.html` | `docs/ROADMAP.md` |
| `site/getting-started.html`, `site/ja/getting-started.html` | README's install section, `docs/PUBLISHING.md` |
| `site/security.html`, `site/ja/security.html` | `SECURITY.md` |

Every page exists in both languages. Adding one to `site/` without its
`site/ja/` counterpart leaves the site half-translated, which is worse
than not having the page.

## Before a release

1. Walk the trigger table for everything in the release.
2. `cd core && bundle exec rspec spec/meta spec/e2e/capability_coverage_spec.rb` — the parity and coverage guards.
3. Both changelogs: bullets first, details below, EN and JA saying the
   same thing.
4. `gitleaks detect --config .gitleaks.toml` over the full history.
5. Grep the previous version number across the repo; anything still
   naming it that is not history is stale.

## The site, and what still is not checked

`site/` is on `main` as of 0.2.0. The list this section used to carry --
eleven discrepancies found by an independent read of the branch -- is
gone because every item on it is fixed, and the two that were about the
capability matrix are now *machine*-checked rather than remembered:
`scripts/check_site_links.rb` compares the site's matrix against
README's, all three columns, on `capabilities.html` and on both index
pages, and the version the index pages advertise against
`vscode/package.json`. The deploy gates on it.

English is compared by feature name, against the README. Japanese is
compared *positionally* — `ja/capabilities.html` against `README.ja.md`,
and `ja/index.html` against `index.html`, which is itself checked by
name. The site's Japanese was translated independently of `README.ja.md`
and the two disagree about wording that means the same thing
(`Coreが起動し` against `Core が起動し`), so demanding identical prose
would buy a stricter check by making the prose worse. What both copies
really share is the order of the table.

That `ja/index.html` clause is 0.2.1's correction and worth the sentence
it costs: comparing it by name meant comparing it to nothing at all,
because no row name matches (`ホバー: リテラル…` against
`Hover: リテラル…`), and every row fell into a branch that was skipped
for Japanese pages. Eight rows, none checked, on the Japanese landing
page — while this document said the matrix was machine-checked. The
mutation test that caught the English half was never run against the
Japanese one; it is now, in both directions.

The roadmap pages joined that list in 0.2.3, by item count per version
against `ROADMAP.md` and `ROADMAP.ja.md`. It was added because the site
had been a whole release behind on *two* separate moves — 0.2.1 sent
`activeParameter` to 0.4.0 and brought `documentHighlight` and `@ivar`
completion back to 0.3.0, and updated the Markdown and README each time
and the site neither time. The check found both the moment it was
written, which is the only endorsement it needs.

Counting is deliberately all it does. The site's prose is written for the
site and does not match the Markdown sentence for sentence, in either
language; a count catches an item that never arrived, which is the whole
failure mode observed so far.

What these checks do *not* cover, and what therefore still has to be
read: every page that is not `capabilities.html`, a roadmap page or an
index page — and, on the pages they do cover, everything that is not a
row or an item. The security page's two retracted claims, the
requirements list, the patch definition and the 404 page's issue-tracker
line were each found by a person reading, and nothing would have caught
them. The version badge used to be on this list; it is machine-checked
now, and 0.2.2 still shipped a stale one, because the check ran only when
a site file changed — the wiring that lets it fire on a version bump
arrived in 0.2.3, pinned by `site_version_guard_spec.rb`.

## Where a check is missing

Nothing compares `site/capabilities.html` against
`docs/EXTENSION_CAPABILITIES.md` — the row counts are pinned to README's
matrix, and the *descriptions* to nothing. Nothing compares `site/` to
`site/ja/` as documents, only within the checks above. The honest reason
is that the site is HTML and the sources are Markdown, so a comparison of
prose needs a real extractor rather than a regex.

Until one exists, the site rows above are enforced by reading this file —
and every check that does exist was added *after* a reviewer found the
drift it now catches, which is the argument for adding the next one
before that happens again.
