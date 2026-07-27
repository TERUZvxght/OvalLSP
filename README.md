# OvalLSP — Ruby Semantic LSP

[日本語版 README](README.ja.md)

> **This project is under active development.** The developer is
> currently investigating and fixing things in this codebase, so
> **external issue proposals and pull requests are not currently being
> accepted** — reviewing them would be deprioritized against that
> ongoing work, risking overlap with changes already in progress. See
> [CONTRIBUTING.md](CONTRIBUTING.md) for details.

A monorepo for a semantic Ruby/Rails language server. Design background
and overall direction are documented in
[`docs/design/README.md`](docs/design/README.md) (Japanese, internal
design docs) and
[`docs/design/START_HERE.md`](docs/design/START_HERE.md) (same).

## Layout

- `core/` — the Ruby Core Language Server (`ovallsp`), implementing LSP
  3.17 over stdio/Content-Length framing.
- `vscode/` — the VS Code extension (TypeScript), a thin LSP client that
  launches `core/bin/ovallsp --stdio` per workspace folder.
- `docs/design/` — design documents (PRD, architecture, ADRs,
  implementation task notes; Japanese only, an internal engineering log
  from implementation).
- `docs/design/docs/12-release-and-support.md` — user-facing release
  documentation (Installation, Security model, Configuration,
  Troubleshooting; Japanese).
- `docs/SUPPORT_MATRIX.md` / `docs/RELEASE_CHECKLIST.md` — supported
  environments and the 1.0 release checklist (the latter is Japanese
  only).

## Status

`docs/design/tasks/001-*.md` through `023.8-*.md` are implemented (an
Apple Silicon Marketplace Preview has been published). See
`docs/RELEASE_CHECKLIST.md` (Japanese) and `docs/SUPPORT_MATRIX.md` for
details.

- LSP transport, didOpen/didChange/didClose, Hover/completion/signature
  help
- Prism-based declaration extraction and documentSymbol, with a
  persistent cache for warm starts
- Workspace indexing, definition, workspace/symbol, find references,
  rename
- Local type inference (`ovallsp/explainType`), RBS/RBI integration
- Runtime Agent process management (hello/status/snapshot/model/reload/
  shutdown) with exponential-backoff auto-restart and crash-loop
  protection
- Rails routes-derived `*_path`/`*_url` completion, signature help,
  definition
- Active Record model column/association type inference, Rails DSLs
  (enum/scope/delegate)
- Controller → view instance-variable propagation (ERB)
- Plugin API (static/runtime), process-isolated plugin execution
- Opt-in runtime type observation (Task 019)
- VSIX packaging, automatic Ruby environment resolution (mise/asdf/
  rbenv/Homebrew/PATH)
- Log redaction, protocol version negotiation
- Extension/Core version and protocol handshake, LanguageClient
  lifecycle management (Task 023)

When `core/bin/ovallsp` detects a Rails app (a `bin/rails` directly under
the workspace root), it starts the Runtime Agent on a background thread,
fetches route/model snapshots, and feeds them into completion/definition/
type inference (falling back to static-only features if there's no
Rails app, or the Agent fails to start).

For end-user information about the VS Code extension itself (install,
settings, troubleshooting), see
[`vscode/README.md`](vscode/README.md).

## Development

```bash
# Core Server
cd core
bundle install
bundle exec rspec

# VS Code Extension
cd vscode
npm install
npm run test:unit         # vscode-API-independent unit tests
npm run test:integration  # real Extension Development Host tests (downloads a VS Code binary)
```

## Contributing / Security / Support

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
