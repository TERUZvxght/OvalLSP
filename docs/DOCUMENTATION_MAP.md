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
| **A capability** (anything a user can now do, or can no longer do) | `docs/EXTENSION_CAPABILITIES.md` + `.ja.md` (add/alter the row **and** its E2E example), README's matrix in `README.md` + `README.ja.md`, `site/capabilities.html` + `site/ja/capabilities.html`, both changelogs | `core/spec/e2e/capability_coverage_spec.rb` (row ⇔ E2E example), `core/spec/meta/*_parity_spec.rb` (EN ⇔ JA). README's own pair is **not** among them — see 024.25 |
| **A version number** | `core/lib/ovallsp/version.rb`, `core/Gemfile.lock`, `vscode/package.json`, `vscode/package-lock.json` (two places), both changelogs — and, once it is published, `docs/RELEASE_ARTIFACTS.md` | `core/spec/meta/changelog_parity_spec.rb`, `vscode/src/test/unit/versionPairing.test.ts`, `core/spec/meta/release_artifacts_spec.rb` (every `v*` tag is accounted for) |
| **A roadmap item** (shipped, dropped, moved) | `docs/ROADMAP.md` + `.ja.md`, README's matrix, `site/roadmap.html` + `site/ja/roadmap.html`, the matching `024.R*` entry in `docs/design/tasks/024-deferred-review-findings.md` | `core/spec/meta/roadmap_parity_spec.rb` (README ⇔ roadmap) |
| **A change reverted mid-release** (see CLAUDE.md's same-place rule) | a `024.*` entry naming the root cause and the direction actually needed, both changelogs if a bullet was already written for it, and the section of `CLAUDE.md` the episode informs | — |
| **A review round finding the same place the previous round did** | a mechanical countermeasure — a shared implementation, a rule moved to where the value is produced, a guard given the input it could not see — *not* a regression test for the one instance, and not a third hand fix | — |
| **A deferred finding** (`024.*`) | its `yaml` metadata block in `docs/design/tasks/024-deferred-review-findings.md` — `status`, and `released-in` once it is resolved; delete the entry once nothing in the tree still cites it by number — grep first, do not go by the calendar (see that file's own legend) | — |
| **Install steps, prerequisites, or the extension id** | `README.md` + `.ja.md`, `docs/PUBLISHING.md` + `.ja.md`, `site/getting-started.html` + `site/ja/getting-started.html` | — |
| **What the extension records, keeps, or writes to disk** | `vscode/PRIVACY.md` + `.ja.md` — the single source of truth for this; `site/security.html` + `site/ja/security.html`; and every place 0.1.12 found restating the list or the cache path, each of which must point at PRIVACY rather than copy it (this list has been short three times; add to it rather than trusting it): `docs/design/docs/12-release-and-support.md`, `docs/design/tasks/019-runtime-observation.md`, `019-runtime-observation-notes.md`, `021-persistent-cache-notes.md`, the cache paragraph in `vscode/README.md` + `.ja.md`, `docs/SECURITY_CHECKLIST.md`'s observation and cache-deserialisation sections, `core/lib/ovallsp/observation/store.rb`'s `#invalidate_changed` doc, `core/lib/ovallsp/observation/observed_signature.rb`'s `code_fingerprint` doc, and **both changelogs**, which restate the disk claim in prose and went stale against PRIVACY for a whole round because this row did not name them | `core/spec/meta/privacy_parity_spec.rb` (EN ⇔ JA: section count, cross-links, three named claims, and the length of the recorded-items list) |
| **Anything about the Runtime Agent, workspace trust, or what the extension executes** | `SECURITY.md` + `.ja.md`, `site/security.html` + `site/ja/security.html`, `docs/EXTENSION_CAPABILITIES.md`'s "does not promise" section | — |
| **A known limitation** | `docs/KNOWN_LIMITATIONS.md` + `.ja.md`, and the site page that claims the opposite, if any | `core/spec/meta/deferred_findings_spec.rb` (an open `024.*` defect declaring `user-visible: yes` carries one `<!-- documents: 024.N -->` marker, at the end of the line that documents it, in each language; one declaring `no` states why) |
| **A working agreement** (how this project is built, reviewed or released) | `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` + `.ja.md` | — |

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

What that check does *not* cover, and what therefore still has to be
read: every page that is not `capabilities.html` or an index page. The security page's
two retracted claims, the roadmap's mis-numbered sentence, the version
badge, the requirements list, the patch definition and the 404 page's
issue-tracker line were each found by a person reading, and nothing
would have caught them.

## Where a check is missing

The site has no parity guard: nothing compares `site/capabilities.html`
against `docs/EXTENSION_CAPABILITIES.md`, and nothing compares `site/` to
`site/ja/`. That is the largest remaining hole in this map, and the
honest reason it is a hole is that the site is HTML and the sources are
Markdown, so a comparison needs a real extractor rather than a regex.
Until one exists, the site rows above are enforced by reading this file.
