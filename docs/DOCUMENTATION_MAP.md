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
| **A change reverted mid-release** (see CLAUDE.md's two-rounds rule) | a `024.*` entry naming the root cause and the direction actually needed, both changelogs if a bullet was already written for it, and the section of `CLAUDE.md` the episode informs | — |
| **A deferred finding** (`024.*`) | its `yaml` metadata block in `docs/design/tasks/024-deferred-review-findings.md` — `status`, and `released-in` once it is resolved; delete the entry once nothing in the tree still cites it by number — grep first, do not go by the calendar (see that file's own legend) | — |
| **Install steps, prerequisites, or the extension id** | `README.md` + `.ja.md`, `docs/PUBLISHING.md` + `.ja.md`, `site/getting-started.html` + `site/ja/getting-started.html` | — |
| **What the extension records, keeps, or writes to disk** | `vscode/PRIVACY.md` + `.ja.md` — the single source of truth for this; `site/security.html` + `site/ja/security.html`; and every place 0.1.12 found restating the list or the cache path, each of which must point at PRIVACY rather than copy it (this list has been short three times; add to it rather than trusting it): `docs/design/docs/12-release-and-support.md`, `docs/design/tasks/019-runtime-observation.md`, `019-runtime-observation-notes.md`, `021-persistent-cache-notes.md`, the cache paragraph in `vscode/README.md` + `.ja.md`, `docs/SECURITY_CHECKLIST.md`'s observation and cache-deserialisation sections, `core/lib/ovallsp/observation/store.rb`'s `#invalidate_changed` doc, `core/lib/ovallsp/observation/observed_signature.rb`'s `code_fingerprint` doc, and **both changelogs**, which restate the disk claim in prose and went stale against PRIVACY for a whole round because this row did not name them | `core/spec/meta/privacy_parity_spec.rb` (EN ⇔ JA: section count, cross-links, three named claims, and the length of the recorded-items list) |
| **Anything about the Runtime Agent, workspace trust, or what the extension executes** | `SECURITY.md` + `.ja.md`, `site/security.html` + `site/ja/security.html`, `docs/EXTENSION_CAPABILITIES.md`'s "does not promise" section | — |
| **A known limitation** | `docs/KNOWN_LIMITATIONS.md` + `.ja.md`, and the site page that claims the opposite, if any | `core/spec/meta/deferred_findings_spec.rb` (an open `024.*` defect declaring `user-visible: yes` is cited in both languages; one declaring `no` states why) |
| **A working agreement** (how this project is built, reviewed or released) | `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` + `.ja.md` | — |

## The site is documentation

`site/` is the public face and goes stale the same way the rest does. It
is *not* generated from the Markdown docs, so nothing propagates on its
own. Treat every page as another row above.

**It is not in this tree.** `site/` lives on
`claude/github-pages-official-site-fef0f5` and has not been merged, so
the site rows in the trigger table cannot be followed from here — they
have to be *carried*, and the list two sections down is where they are
carried to. Anything a change makes stale on the site goes in that list
until the branch lands. A trigger you cannot follow is a trigger nobody
follows.

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

## The site is not yet merged, and the order matters

`site/` lives on `claude/github-pages-official-site-fef0f5`, not on
`main`. An independent check found it faithful — the capability matrix is
a row-for-row copy of README's, every internal link resolves, no
trackers, no external assets, no personal data — with a short list of
discrepancies to fix before adopting it.

**The agreed order is: publish 0.2.0 first, then fix the site, then merge
it.** One of the discrepancies is the front page claiming completion of
workspace class names, which 0.1.x does not have and 0.2.0 does — fixing
that against 0.1.x and then re-fixing it after 0.2.0 would be two edits
saying opposite things a week apart. The rest of the list is order-independent:

- **`site/roadmap.html` and `site/ja/roadmap.html` do not carry 0.3.0's
  two new items** — completion after `self.` and completion on an Active
  Record `Relation`, both added to `docs/ROADMAP.md` and to README's
  matrix while measuring 0.2.0 against a real application.
- **`site/capabilities.html` and `site/ja/capabilities.html` mark all six
  of 0.2.0's capabilities `planned`** — bare-prefix completion, the
  unassigned-`@ivar` check, argument types, project-wide diagnostics,
  documentation in hover, and semantic highlighting — and
  `site/roadmap.html` still carries the 0.2.0 section that
  `docs/ROADMAP.md` no longer has. On publication the project's own site
  would say six shipped features are still to come. This is the reason
  the front-page item below is order-dependent, and it is the same edit;
- `site/capabilities.html` **and `site/ja/capabilities.html`** still say
  "Find references, rename, workspace symbols" unqualified; 0.1.15
  narrowed that — a method a macro declared is refused rather than
  renamed — in README's `[^rename]` footnote and in
  `docs/EXTENSION_CAPABILITIES.md`'s W2/W4 rows;
- the plain-Ruby column drops README's `⚠️`, so its own legend reads those
  cells as "not built" where README means "probably works, unverified";
- the roadmap page says "the first three of these" and then names items
  2, 5 and 6;
- `Preview 0.1.10` is hard-coded in both index pages;
- hover is said to show "method returns", which no capability row backs;
- "a patch means nothing a user sees changed" appears six times, and
  `docs/PUBLISHING.md` explicitly rejects that phrasing;
- the requirements list omits the VS Code 1.85 floor;
- `404.html` alone advertises an issue tracker;
- **`site/security.html` and `site/ja/security.html` carry both claims
  0.1.12 retracted**: that the parse cache holds "not your source code's
  contents" (it holds method bodies and default expressions verbatim),
  and a description of what observation records that omits the file
  digest, the line number, the run identifier and the run-finish time.
  These are not cosmetic like the rest of this list — they are the
  release's own corrections, unmade on the public page. Fix them with
  the others before merging, and do not ship the site carrying them.
  The parse-cache paragraph on the same page also hard-codes
  `~/.cache/ovallsp/`, which 0.1.12
  corrected to `$XDG_CACHE_HOME/ovallsp/` (falling back to `~/.cache`
  when that is unset or empty) in six other documents.

Note also that `vscode/package.json`'s `homepage` on that branch already
points at the Pages URL, which 404s until Pages is switched on and the
site is on `main` — so that branch must land before a VSIX carrying the
link ships.

**Do the mechanical part while adopting it.** The branch already ships
`scripts/check_site_links.rb`, and the deploy already gates on it.
Teaching it two more comparisons — the site's matrix against README's,
and the version badge against `vscode/package.json` — turns roughly
two-thirds of the stale-point list below into CI failures instead of
things somebody has to remember. That is the same move
`core/spec/e2e/capability_coverage_spec.rb` already makes for
`EXTENSION_CAPABILITIES.md`, and it is what would close the hole named
in the next section.

## Where a check is missing

The site has no parity guard: nothing compares `site/capabilities.html`
against `docs/EXTENSION_CAPABILITIES.md`, and nothing compares `site/` to
`site/ja/`. That is the largest remaining hole in this map, and the
honest reason it is a hole is that the site is HTML and the sources are
Markdown, so a comparison needs a real extractor rather than a regex.
Until one exists, the site rows above are enforced by reading this file.
