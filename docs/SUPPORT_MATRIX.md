# Support Matrix

[日本語版](SUPPORT_MATRIX.ja.md)

Following `docs/design/tasks/022-compatibility-resilience-and-release.md`'s
policy, only combinations **actually run and verified** are declared
`supported` — design-document placeholder values are never declared as-is.

Each combination is classified into one of three tiers:

- **supported**: actually run on real hardware or this repository's own
  test suite, and green.
- **best effort**: manually confirmed to work, but no continuous
  automated verification yet.
- **unsupported**: unverified, or has a known incompatibility.

## Native dependency combinations the VSIX targets (ADR-0005)

`vscode/core/vendor/bundle` contains native extensions specific to the
build environment (prism/rbs, both Ruby-ABI/OS/CPU-dependent).
`core/bin/ovallsp` and `vscode/src/platformCompatibility.ts` verify this
before startup, and refuse to load the vendor payload on a mismatch,
showing an actionable diagnostic instead (ADR-0005).

| Combination | Tier | Basis |
|---|---|---|
| darwin-arm64 + Ruby 3.4.x (this VSIX's build environment) | supported | Exactly the combination `core/PLATFORM_MANIFEST.json` records. Verified through actual Semantic Hover on the real VSIX via `scripts/vsix_semantic_smoke.rb` |
| Any other Ruby engine/version/platform | unsupported (vendor payload not used) | The vendor payload is never loaded; it may still work if the user's own Ruby environment has prism/rbs installed separately, but this is unverified. Explained via a diagnostic message |

If multiple-target VSIX distribution is pursued in the future, see
ADR-0005's "Rejected alternatives" for the extension path (option 1:
multiple builds, option 2: bundling the Ruby runtime itself).

## Ruby (Core's own `required_ruby_version`)

| Version | Tier | Basis |
|---|---|---|
| 3.4 (run under 3.4.5 and 3.4.7) | supported | `core/`'s test suite (1,929 examples — `core/spec/meta/documented_counts_spec.rb` compares this number against the running suite, because the figure was 895 for six releases, then 1,776 taken mid-branch, then 1,833 with two commits still to come) actually run and green on this machine under both 3.4.7 (primary) and 3.4.5 (via rbenv) |
| 3.3 | unsupported (unverified) | The Core's own suite runs under 3.3 — `.github/workflows/ci.yml` runs the matrix `["3.3", "3.4"]` — so this row is not about the library. What a user installs is a VSIX whose bundled native extensions are built for one Ruby version and are therefore unused here. As of 0.2.1 the extension does **not** refuse: it asks whether that Ruby carries `prism` and `rbs` itself, and 3.3 ships both, so it starts — against an unverified combination. This row said "declines to start" until round 27, which was the behaviour 0.2.1 removed and was left standing beside the 4.0 row that describes the new one |
| 4.0 (run under 4.0.6) | best effort | `core/`'s suite is green under 4.0.6, with the real-Rails integration examples pending because Rails and sqlite3 are not installed for that Ruby on this machine. **What the VSIX does on it**: the bundled native extensions are built for one Ruby version, so they are not used here — the extension checks whether *your* Ruby carries `prism` and `rbs` itself, and runs against those. If it does, that is an Output-channel line; if it does not, it is an error naming `gem install prism rbs`. Until 0.2.1 it was an error either way, which described the payload rather than the situation. Nothing continuously verifies 4.0 — `.github/workflows/ci.yml` runs `["3.3", "3.4"]` |
| 3.5 | unsupported (unverified) | Same reasoning — no run under a stable 3.5.x at release time |
| 3.2 and below | unsupported | Explicitly rejected by `required_ruby_version` |

## Rails (Runtime Agent)

| Version | Tier | Basis |
|---|---|---|
| 8.1 | supported | `core/spec/integration/real_rails_spec.rb`'s (real Rails integration test) actual fixture pins `gem "rails", "~> 8.1"` (currently resolves to 8.1.3). `.github/workflows/ci.yml` also installs this exact version explicitly |
| 7.0 / 7.1 | unsupported (unverified) | Only Rails 8.1 is actually tested. An earlier version of this table incorrectly declared 7.1 "supported," which didn't match the real fixture (corrected) |
| 6.x and below | unsupported | Unverified. Some functionality since `docs/design/tasks/008.5-*` (e.g. `belongs_to_required_by_default`) assumes Rails 7.1+'s default behavior |

A workspace that doesn't use Rails at all (a plain Ruby gem/library) never
starts the Runtime Agent and runs on static analysis alone — this is not
"unsupported," it's simply a case the Agent doesn't apply to at all.

## OS

| OS | Tier | Basis |
|---|---|---|
| macOS (arm64) | supported | This development environment is itself macOS arm64; the full test suite, VSIX packaging, and VSIX semantic smoke all run here, green |
| Linux | unsupported (CI is green; not verified on real hardware) | `.github/workflows/ci.yml` runs `core`'s full RSpec suite and `vscode`'s TypeScript unit tests on `ubuntu-latest`, actually green (GitHub Actions was run and confirmed for the first time as part of Marketplace publishing prep). This verifies the Core Server/extension's own logic runs on Linux — but the Apple-Silicon-targeted VSIX's native payload is darwin-arm64-only (table above), so on Linux it would run without the vendor payload (requiring prism/rbs installed in the user's own Ruby environment). Real-hardware VSIX install has not been verified |
| Windows | unsupported | `rubyResolver.ts` has Windows RubyInstaller detection logic implemented, but real-hardware verification hasn't been done |

## VS Code

| Version | Tier | Basis |
|---|---|---|
| 1.130.0 (the stable version this machine's `@vscode/test-electron` fetched) | best effort | Declared via `vscode/package.json`'s `engines.vscode: ^1.85.0`. Real-hardware install (`vsce package` → `code --install-extension` → `--uninstall-extension`) and integration tests (`npm run test:integration`/`test:integration:packaged`) were run against this version, green. Actually published to the Marketplace (Pre-Release channel) as v0.1.1 |
| Other stable versions | unverified | — |

## Remote environments

| Environment | Tier | Basis |
|---|---|---|
| WSL | unsupported | Unverified |
| Dev Container | unsupported | Unverified |
| Remote SSH | unsupported | Unverified |

## Known gaps

What's actually been verified: the Ruby test suite (`core/`) and
TypeScript unit/integration tests (`vscode/`) on macOS (darwin-arm64);
Semantic Hover/documentSymbol/definition smoke on an actually-packaged
VSIX (darwin-arm64 + Ruby 3.4.7 build); CI runs of the Core/VS Code test
suites on GitHub Actions (`ubuntu-latest`); and an actual Marketplace
publish (v0.1.1, Pre-Release channel). Real-hardware VSIX install on
Windows/Linux, multiple VS Code versions, and startup via WSL/Dev
Container/Remote SSH have not been done.
