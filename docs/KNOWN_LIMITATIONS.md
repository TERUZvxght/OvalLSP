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
- **The bundled native extensions embed the packaging machine's own
  absolute Ruby install path, mitigated by the Extension at launch
  time.** `otool -L` on the packaged `prism.bundle`/`rbs_extension.bundle`
  shows an absolute `LC_LOAD_DYLIB` reference to the *packaging
  machine's own* rbenv `libruby` path (e.g.
  `/Users/<packager>/.rbenv/versions/3.4.7/lib/libruby.3.4.dylib`), not a
  relocatable `@rpath` reference -- standard `rbenv`/`ruby-build`
  `--enable-shared` behavior on macOS. Reproduced directly: a
  `prism.bundle` built under one Ruby 3.4.x install raised `LoadError:
  linked to incompatible .../libruby.3.4.dylib` when required under a
  *different* Ruby 3.4.x install at a different absolute path -- which
  would otherwise affect essentially every real end user, since a
  different username alone is enough to trigger it, and this is not
  something ADR-0005's own engine/version/platform compatibility check
  catches. **Fixed**: the Extension sets `DYLD_LIBRARY_PATH`/
  `DYLD_FALLBACK_LIBRARY_PATH` to the actually-resolved Ruby's own `lib`
  directory when spawning Core Server (`serverConfig.ts`'s
  `deriveNativeExtensionLibraryPath`) -- macOS' dynamic linker checks
  that variable, by leaf filename, before ever consulting a dependent
  library's own recorded absolute path. Verified by reproducing the
  exact failure and confirming the fix resolves it, using two different
  Ruby 3.4.x installations already present on the same development
  machine (see `docs/design/tasks/023.8-*.md`). This mitigation only
  applies when the resolved Ruby command is an absolute path (any
  version-manager-resolved Ruby is); a bare `ruby` resolved via `PATH`
  search has no sibling directory to derive and is unaffected by this
  fix either way.
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
