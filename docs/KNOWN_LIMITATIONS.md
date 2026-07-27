# Apple Silicon Marketplace Preview — Known Limitations

This document lists what's intentionally out of scope for the first
Marketplace Pre-Release, as distinct from bugs. See
[docs/SUPPORT_MATRIX.md](SUPPORT_MATRIX.md) for the exact,
evidence-based supported/unsupported table this summarizes.

## Platform scope

- **Only macOS on Apple Silicon (`darwin-arm64`) is targeted.** The VSIX
  is built with `vsce package --target darwin-arm64` and bundles native
  extensions (Prism, RBS) compiled specifically for that platform (see
  [ADR-0005](design/adrs/0005-platform-scoped-vsix-with-runtime-compatibility-check.md)).
  On any other OS/CPU, the bundled native dependencies simply aren't
  loaded, and OvalLSP shows a diagnostic explaining why rather than
  attempting to run in a degraded or guessed configuration.
- **Intel Macs, including under Rosetta 2 translation, are not
  supported in this Preview.** An x86_64 Ruby (even one installed
  natively on an Apple Silicon Mac via Intel Homebrew) is rejected by the
  same platform-compatibility check for the same reason.
- **Linux and Windows are not supported in this Preview.** The Ruby
  resolver includes Windows RubyInstaller detection logic and the Core
  Server itself is platform-agnostic Ruby, but this Preview's packaging,
  testing, and support commitment don't yet cover either OS.
- **WSL, Dev Containers, and Remote SSH are not supported in this
  Preview** — untested, not merely undocumented.

## Ruby version scope

Only Ruby 3.4.x is supported, specifically the patch versions actually
exercised in this project's own test runs (3.4.5, 3.4.7) — not the full
range `core/ovallsp.gemspec`'s `required_ruby_version >= 3.3` would
technically allow to install. That gemspec constraint means "not
rejected," not "verified" — Ruby 3.3.x and 3.5.x are treated as
unsupported until they're actually exercised by this project's test
suite.

## Distribution and update model

- The Core Server ships **inside** the extension and updates atomically
  with it via the Marketplace's own extension update mechanism — see
  [ADR-0006](design/adrs/0006-marketplace-bundled-core-update-atomicity.md).
  There is no separate Core Server download, and no independent
  background self-updater. If that model changes in the future (for
  example, to support Core updates independent of Extension releases),
  it will be a new, explicitly-designed feature, not something this
  Preview does implicitly.
- A custom `ovallsp.server.path` is checked for protocol compatibility
  but is never automatically updated, and is never compared against the
  bundled Core's own version/build/payload expectations.

## Static analysis limitations (not Apple-Silicon-specific, but worth
restating for a Preview)

OvalLSP is a confidence-aware heuristic engine for LSP features, not a
Ruby type checker. By design, it does not track:

- `method_missing`/`define_method`-based dynamic method definition,
  outside the specific Rails DSLs it already recognizes (`enum`,
  `scope`, `delegate`).
- `class_eval`/`instance_eval` with string-argument code generation.
- Constant resolution that only resolves at runtime (e.g. `const_get`
  with a dynamic argument).
- Code paths never exercised by a test run, for opt-in runtime type
  observation specifically (evidence only exists for what actually ran).

## What's tracked as separate, post-Preview work

Expanding beyond this Preview's scope (additional OS/CPU targets, a
Ruby/Rails version matrix, a self-hosted Apple Silicon release runner,
Entra ID-based Marketplace publishing, Extension JS bundling, and a
stable-release readiness bar) is tracked as separate GitHub issues, not
blocking this Preview — see
[docs/design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md](design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md)
and onward for the full task breakdown.
