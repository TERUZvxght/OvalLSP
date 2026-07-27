# Changelog

All notable changes to the OvalLSP VS Code extension are documented here.

## 0.1.3 — Fix: v0.1.2 always showed a false "Payload hash mismatch" warning

Every activation of v0.1.2 showed a false-positive diagnostic:
"Payload hash mismatch: the bundled Core on disk does not match this
Extension's recorded payload hash -- it may be corrupted or was
partially/incorrectly installed", suggesting a reinstall. The Core
Server itself worked fine despite the warning.

Root cause: `vscode/scripts/release.sh` (and, before it existed, a bare
`vsce publish` after a separate build) called `vsce publish
--target darwin-arm64 --pre-release` directly. `vsce publish` runs its
own `vscode:prepublish` hook independently of any earlier `npm run
package` -- silently rebuilding Core's vendored native extensions
(Prism, RBS) from scratch a second time. Native-extension compilation
isn't byte-reproducible run to run, so the actually-uploaded build
differed from whatever had just been verified, and the manifest
embedded in that unverified rebuild didn't match its own payload hash
by the time it reached the Marketplace. Confirmed by downloading the
actual published v0.1.2 VSIX from the Marketplace CDN and finding its
own `PLATFORM_MANIFEST.json` didn't match a live rehash of its own
`core/` directory.

Fixed by publishing the exact already-built, already-smoke-tested VSIX
file via `vsce publish --packagePath <file> --pre-release` instead of
letting `vsce publish` rebuild on its own. Verified end to end: after
this change, a build's on-disk payload hash is provably unchanged by
the publish step (rebuilt once, hashed, attempted publish, rehashed --
identical both times), where before the same sequence produced two
different hashes.

## 0.1.2 — Documentation update

No code or runtime behavior changes. Updates the README (both language
versions) with two previously-undocumented, now-verified facts:

- Installing the extension alone is sufficient to run it, provided a
  compatible Ruby (3.4.x) is already reachable on the system — no
  separate download or `bundle install` beyond that.
- A real, verified conflict: running alongside another active Ruby
  language server extension (tested against Shopify's Ruby LSP) produces
  overlapping completion/definition results, since VS Code merges
  results from every active provider rather than picking one. See
  "Known conflicts with other extensions" in the README.

## 0.1.1 — Fix: published VSIX was missing the bundled Core Server

0.1.0 was published by running `vsce publish` directly, which does not
automatically vendor the Core Server (`vscode/scripts/copy-core.js`)
unless invoked through this project's own `npm run package` wrapper --
the published 0.1.0 VSIX shipped without a `core/` directory at all, and
could not start the Core Server. Fixed structurally by adding a
`vscode:prepublish` npm script, which `vsce package`/`vsce publish` both
run automatically before packaging regardless of how they're invoked --
this failure mode can no longer happen from any invocation path.

## 0.1.0 — Apple Silicon Marketplace Preview

First Marketplace Pre-Release, scoped to macOS on Apple Silicon
(`darwin-arm64`) with Ruby 3.4.x. See
[docs/SUPPORT_MATRIX.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SUPPORT_MATRIX.md)
for exactly what's been verified, and
[docs/KNOWN_LIMITATIONS.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.md)
for what's intentionally out of scope in this Preview.

Highlights:

- Hover, definition, documentSymbol, workspace/symbol, find references,
  guarded rename, and completion/signature help backed by real
  Prism-based parsing and a workspace-wide index.
- Rails-aware completion/definition for routes and Active Record
  models, via an opt-in-trust Runtime Agent.
- RBS/RBI signature integration and opt-in runtime type observation.
- A version-compatibility handshake between the Extension and its
  bundled Core Server (`OvalLSP: Show Version Information`), so an
  incompatible or corrupted Core Server build is reported clearly
  instead of failing silently or partially.
- Automatic Ruby interpreter discovery across mise, asdf, rbenv, and
  Homebrew, with clear diagnostics (`OvalLSP: Show Environment
  Diagnostics`) when none can be found.
- The Core Server ships inside the extension itself — no separate
  install step, and it updates atomically with the Extension.

This is a Preview release. See
[SUPPORT.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.md)
for the current state of external feedback/issue intake.
