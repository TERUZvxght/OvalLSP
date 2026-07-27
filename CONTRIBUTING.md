# Contributing

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

## Running tests

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
