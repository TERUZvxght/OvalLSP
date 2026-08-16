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

## Before opening a PR

1. Run the relevant test suites above.
2. If your change affects VSIX packaging, run `cd vscode && npm run
   package` and confirm it succeeds.
3. Describe what changed and why, and list the tests you ran.

## Reporting bugs / requesting features

See [SUPPORT.md](SUPPORT.md). For security issues, see
[SECURITY.md](SECURITY.md) instead of opening a public issue.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
