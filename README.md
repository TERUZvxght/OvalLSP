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

## Capability matrix

Two axes: what the feature is, and which environment it runs in.

| | Meaning |
|---|---|
| ✅ | Verified end to end in that environment, by a test that fails if it breaks |
| ⚠️ | May well work — much of the engine is environment-independent — but nothing verifies it, so nothing is promised |
| version | Not built yet; the release it is planned for. A version alongside ⚠️ means it is planned for that release but will still be unverified in that environment |

Everything below assumes the published artifact, which is **darwin-arm64
only**. No VSIX is published for Windows, Linux, or Intel macOS; doing so,
verified per platform, is what 1.0.0 requires (024.R4).

| Feature | Rails, trusted workspace | Rails, untrusted workspace | Plain Ruby (no Rails) |
|---|---|---|---|
| Core starts, reaches a ready state | ✅ | ⚠️ | ⚠️ 1.0.0 |
| No process survives closing the window | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Hover: literals, constructors, locals | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Hover: Active Record finders | ✅ | — (no Runtime Agent) | — |
| Hover: `@ivar` in a view, from its action | ✅ | ⚠️ | — |
| Completion: stdlib methods (RBS) | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Completion: workspace class instance methods | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Completion: workspace class singleton methods | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Completion: model columns and associations | ✅ | — (no Runtime Agent) | — |
| Completion: Active Record instance API | ✅ | — (no Runtime Agent) | — |
| Completion: Active Record class API | ✅ | — (no Runtime Agent) | — |
| Completion: route helpers | ✅ | — (no Runtime Agent) | — |
| Completion inserts a call template with tab stops | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Hover on a method shows its parameters | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Go to definition: workspace methods | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Go to definition: model columns/associations | ✅ | — (no Runtime Agent) | — |
| Go to definition: stdlib (into RBS) | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Diagnostics: syntax errors | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Diagnostics: unknown method on a workspace class | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Diagnostics: unknown method on a model | ✅ | — (no Runtime Agent) | — |
| Diagnostics: unknown route helper | ✅ | — (no Runtime Agent) | — |
| Diagnostics: wrong number of arguments | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Diagnostics: unknown method or variable on a class inheriting from a gem | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Diagnostics: reading an `@ivar` that is never assigned | 0.2.0 | ⚠️ 0.2.0 | ⚠️ 1.0.0 |
| Signature help: workspace, stdlib, route helpers | ✅ | ⚠️ (route helpers: —) | ⚠️ 1.0.0 |
| Find references, rename, workspace symbols | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Diagnostics: wrong argument *type* | 0.2.0 | ⚠️ 0.2.0 | ⚠️ 1.0.0 |
| Diagnostics across the whole project, not just open files | 0.2.0 | ⚠️ 0.2.0 | ⚠️ 1.0.0 |
| Documentation (RDoc/YARD) in hover and completion | 0.2.0 | ⚠️ 0.2.0 | ⚠️ 1.0.0 |
| Semantic highlighting (local variable vs. method call), in `.rb` and in an ERB template's Ruby regions | 0.2.0 | ⚠️ 0.2.0 | ⚠️ 1.0.0 |
| Inlay hints (inferred types, parameter names) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Code actions / quick fixes for each diagnostic | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Go to type definition | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Document highlight (occurrences within a file) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Call hierarchy (callers and callees) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| Per-check diagnostic severity settings | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |
| Auto-`require` insertion | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |
| Signature help: active parameter highlighting | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |

Rows carrying a version are not built anywhere yet; the version is the
release they are planned for, ordered by what a user notices soonest.
Each names a **minor** release exactly, never a `0.2.x`-style range,
because a capability can only ever arrive in a minor one — that is what
minor means here. A patch never adds a row. Several rows sharing a
version ship together in that release, the way 0.1.6 shipped five. The
first three are measured against Pylance, the closest well-known
reference point for a language server in a dynamically typed language:
project-wide diagnostics (today a mistake in a file you are not looking
at is invisible), documentation in hover (hover says what a thing is,
never what it is for), and semantic highlighting (Ruby's `foo` is
ambiguous between a local variable and a method call — the engine already
knows which, the editor does not). Rationale for each, and for the
Pylance features deliberately *not* planned, is in
[`docs/design/tasks/024-deferred-review-findings.md`](docs/design/tasks/024-deferred-review-findings.md)
(024.R3). [`docs/ROADMAP.md`](docs/ROADMAP.md) states the same plan
release by release, in terms of what each one lets you do.

The two unknown-method rows above fire only on a receiver whose whole
ancestry is known — a workspace class, or an Active Record model, whose
methods the Runtime Agent reports. A class inheriting from a gem
(`ApplicationController`, and so most controllers and jobs) is silent
instead, deliberately: reporting there would mean guessing. Indexing what
the gems actually define is what lifts that, and is why the row above
carries 0.3.0.

The inverse case — a workspace file that *reopens* a gem class, which
looks identical to one that defines it — was a false positive through
0.1.6, and is fixed as of 0.1.7. `test/test_helper.rb`'s
`class ActiveSupport::TestCase` is the one every Rails application has.
The Runtime Agent is asked where the class really comes from, so the
static chain's claim to be complete is checked rather than trusted
([024.R5](docs/design/tasks/024-deferred-review-findings.md)). Without a
Runtime Agent — an untrusted workspace, or no Rails app — there is
nothing to ask, and the old reading stands.

An undefined *variable* is not a separate row. In Ruby a bare identifier
that is not a local variable parses as a call on self, so a typo'd
variable is reported by the same check, under the same limitation. An
unassigned `@ivar` is genuinely different — Ruby returns `nil` rather
than raising — and has its own row.

A dash means the capability is defined by Rails data that only the
Runtime Agent can supply. In an untrusted workspace the Agent
deliberately does not start, and outside a Rails app there is nothing for
it to report — so these are absent by design, not broken.

The ⚠️ column for plain Ruby is not a guess that it fails. Most of it
almost certainly works today. It carries 1.0.0 because guaranteeing it —
giving the Rails conventions an explicit boundary and specifying what a
non-Rails project should expect (`docs/design/tasks/024-deferred-review-findings.md`,
024.R1) — is one of the two things 1.0.0 is reserved for. The other is
publishing and verifying the remaining platforms. Until then, nothing in
that column is promised.

Versions in this table are read as: patch means nothing a user sees
changed, minor means a capability was added, major means something a user
relied on stopped working. The full statement is in
[`docs/PUBLISHING.md`](docs/PUBLISHING.md).

Each ✅ corresponds to a row of [`docs/EXTENSION_CAPABILITIES.md`](docs/EXTENSION_CAPABILITIES.md),
which describes what the user does and what must happen, and is verified
by `core/spec/e2e/capabilities_spec.rb` plus
`vscode/scripts/verify-installed-extension.sh`.

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
