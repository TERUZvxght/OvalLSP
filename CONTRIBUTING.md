# Contributing

[日本語版](CONTRIBUTING.ja.md)

**This project is currently not accepting external issues or pull
requests.** The developer is actively investigating and fixing things
in this codebase right now, and reviewing external PRs would be
deprioritized against that ongoing work — meaning a submitted PR could
easily end up overlapping or conflicting with changes already in
progress on the developer's own side, with no timely review to catch
that. Issues are disabled on this repository for the same reason.

This is expected to change once the codebase reaches a more stable
point; this document will be updated when it does. In the meantime,
feel free to fork and experiment locally.

Thanks for your interest in OvalLSP. This project is in active Preview
development; the notes below reflect how the repository actually works
today.

## Repository layout

- `core/` — the Ruby Core Language Server (`ovallsp`), implementing LSP
  3.17 over stdio.
- `vscode/` — the VS Code extension (TypeScript), a thin LSP client that
  launches `core/bin/ovallsp --stdio` per workspace folder.
- `docs/design/` — design documents, ADRs, and per-task implementation
  notes (`docs/design/tasks/*.md`).
- `docs/` — user/release-facing documents (Support Matrix, Release
  Checklist, SBOM, Security Checklist).

## Development setup

Requires Ruby 3.4.x and Node.js (see `vscode/package.json`'s
`engines.vscode` for the VS Code API version targeted).

```bash
cd core && bundle install
cd ../vscode && npm install
```

Two Core suites drive a real Rails application rather than a fake, and
they need `rails ~> 8.1` and `sqlite3` resolvable as **local** gems —
`core/spec/fixtures/rails_real` is bundled with `--local`, so a network
that could fetch them is not enough:

```bash
gem install rails -v "~> 8.1" && gem install sqlite3
```

Without them, `spec/e2e/capabilities_spec.rb` and
`spec/integration/real_rails_spec.rb` skip **in full** and `rspec` still
exits 0 — so a local run reports green while the suite that decides
whether a capability row is true did not run at all. CI's "Fail if the
real-Rails or capability suites were skipped instead of run" step is
what catches this, which means it bites locally and nowhere else. If
your run reports any pending example whose message does not say
`NOT YET`, that is this.

## Running tests

> **If you cloned or checked out this repository between 2026-08-05 and
> 2026-08-11 and ran the Core test suite, it deleted directories outside
> the repository.**
>
> A cache-pruning example passed a fabricated absolute path
> (`current: "/x"`) to code that removes directories. The sweep resolved
> to the filesystem root, kept the most recently modified entry and
> removed the rest, so on macOS `/Applications` was emptied of anything
> not protected by SIP. It stopped when a protected path raised, which is
> why some applications survived. Every error was swallowed by the method
> under test, so the run reported success.
>
> Affected commits are `28a041c` (2026-08-05) through the fix; tag
> `v0.2.1` contains them. Reinstall from Time Machine or from the
> applications' own installers — nothing here can recover them.
>
> **The published extension was never affected.** `core/spec/**` is
> excluded from the VSIX, and the one production caller derives both
> paths from the same cache root, so the sweep could not leave it. Only
> running this repository's test suite from a source checkout could
> reach it.

```bash
# Core Server (Ruby)
cd core && bundle exec rspec

# VS Code extension (TypeScript unit tests)
cd vscode && npm run test:unit

# VS Code extension (integration tests, real Extension Development Host)
cd vscode && npm run test:integration
```

`npm run test:integration` exercises the extension against the
monorepo-relative Core Server (no packaging step needed). `npm run
test:integration:packaged` additionally runs `copy-core.js` first, to
test against a packaged-Core layout instead — useful when working on
anything in `vscode/scripts/copy-core.js` or the VSIX packaging path
itself.

## Code discipline this project follows

- Every bug fix ships with a regression test that actually fails without
  the fix (verified by temporarily reverting the fix and confirming the
  test fails, then restoring it) — not just a test that happens to pass.
- Fixes address the underlying design, not just the reported symptom —
  if a review finding implies "the architecture allows this class of
  bug," the architecture is what gets fixed.
- New features and fixes are expected to include their own tests; PRs
  without test coverage for the behavior they change are unlikely to be
  merged as-is.
- A claim about behaviour is checked, not accepted — against the Ruby
  interpreter for a semantics question, and against real code for a
  question of how often something happens. A review finding is verified
  before it is acted on, and so is the reasoning for calling something
  deliberate.
- Design decisions with real trade-offs (not obvious implementation
  details) are recorded as ADRs under `docs/design/adrs/`.
- New code is the simplest construction that satisfies the requirement in
  front of it; the next requirement is allowed to change the shape. What
  counts as simpler is the number of places that must agree about one
  fact, not the number of lines. This governs code as it is written — a
  simplification of code that already works is an ordinary change, needs
  a test watched failing and a corpus driven, and this project's record
  on retrospective simplifications is 0 for 8.

## Branches and pull requests

**One branch per version, merged into `main` by pull request.** The
branch is `release/<version>` — `release/0.3.0` — and every commit for
that release goes on it.

```bash
git switch -c release/0.3.0
```

`main` is what has shipped. A release is assembled on its branch and
arrives as one pull request, which is the unit a reviewer reads: 0.2.15
through 0.2.18 were built directly on `main`, and the change set for
each of them existed only as a commit range somebody had to
reconstruct.

The name carries no `feat/` or `fix/` prefix, because that is a claim
about the release's contents made before the work starts — 0.2.17 was
named a fix and shipped a capability. One name per version needs no
such guess.
**`main` refuses a direct push, and this is enforced by GitHub rather
than by this paragraph.** Set 2026-09-01. What is on:

- a pull request is required; **0 approving reviews**, because GitHub
  does not let anyone approve their own pull request and a solo
  maintainer would otherwise be locked out of their own repository;
- **ten required status checks** — every CI job except
  `Core Server (Ruby 4.0, informational)`, which is a preview version
  and is expected to fail;
- the branch must be up to date with `main` before merging;
- the rules **apply to administrators too**, so nothing here is a rule
  only some contributors follow;
- force pushes and branch deletion are refused.

Verified by trying it: a direct push to `main` came back
`GH006: Protected branch update failed` — "Changes must be made through
a pull request", "10 of 10 required status checks are expected".

The owner can change or lift this in the repository's Settings →
Branches. Nothing in this repository can, which is the point.


Work that is not a release — a correction to the record, a fix to a
check — takes a short-lived branch of its own and the same pull
request. `docs/design/tasks/`'s highest-numbered file for a release
names its branch, so a session that starts from `main` can find it.

### A merged release branch is kept

**`main` squash-merges, so a release's individual commits exist only on
its branch.** `release/0.3.0` holds 21 commits `main` cannot reach;
`fix/0.2.3` holds 25. No *code* is at stake — `main` is strictly ahead
of every one of them — but the reason for each change is.

Asked when `PROTOCOL_VERSION` became 2:

```
main                  3183588  2026-09-02  0.3.0 — the first release that may add capability (#25)
origin/release/0.3.0  19058c3  2026-09-01  0.3.0: 024.R7's first half — the Agent reports what the gems define
```

`main` answers with the release. The branch answers with the change,
and says why it was made.

That is not archaeology for its own sake: 0.3.1's review established
that a published size figure was two field-additions stale by running
`git log -S "938 KB" release/0.3.0`, which the squashed history cannot
answer. This project's record is built out of "why", and a squash
message compresses twenty-one of them into one.

Keeping them costs nothing. A remote ref does not appear in
`git branch`, slows nothing, and `scripts/check_release_pointers.rb`
passes with them present. The older `feat/` and `fix/` branches predate
the naming above and are kept for the same reason.

**Deleting one is a decision to write down, not tidying.** GitHub's
"Restore branch" on a merged pull request is best-effort and not a
guarantee, so it is not reversible in the way a local branch is.
Cleaning up *local* branches and worktrees is ordinary and needs no
ceremony; the remote refs are the record.

## Before committing: `preflight`

```bash
ruby scripts/preflight.rb
```

Runs everything that has to be true before a commit, and prints what each
one ran, so a commit message can quote a run rather than a recollection.

```bash
ruby scripts/preflight.rb --list
```

names them. **This paragraph deliberately does not enumerate them**: every
prose description of this gate in the repository had gone stale by the
release that added a check to it (`024.195`), so the list lives in one
place that runs and is asked rather than remembered.

One property is worth stating here because it is not visible from the
list: the three environment-dependent suites skip *in full* without local
`rails`, `sqlite3` or `vscode/node_modules` while `rspec` still exits 0,
so preflight reads each example's **status** rather than the count — a
skipped example is still an example, and a count-based check cannot tell
a fully skipped file from a passing one.
After its verdict, preflight prints one `ci:` line saying what CI last
said about your branch. **It is not a tenth check and cannot change the
result** — it needs the network, and it exits 0 whether it reaches
GitHub, finds no `gh`, or times out, because none of those say anything
about your tree. It is there because a green preflight is a statement
about the Core: it runs nothing under `vscode/`, and it cannot see the
`spec/meta` examples that refuse a partial tree, so two CI failures once
stayed red for a week while every local signal said the tree was fine
(`024.284`).

Install it as a git hook once:

```bash
ruby scripts/preflight.rb --install
```

`PREFLIGHT_SKIP=1 git commit …` skips it for one commit.

It exists because "did I run it all?" was being answered from memory,
and twice in one session the answer was wrong: the suite had been run
for a single directory, was green, and the full run afterwards was not.
The checks live in seven places, and nothing but a person was holding
the list together.

## Before opening a PR

1. Run `ruby scripts/preflight.rb`.
2. If your change affects VSIX packaging, run `cd vscode && npm run
   package` and confirm it succeeds.
3. Describe what changed and why, and list the tests you ran.

## Reporting bugs / requesting features

See [SUPPORT.md](SUPPORT.md). For security issues, see
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
