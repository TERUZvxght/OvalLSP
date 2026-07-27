# Changelog

All notable changes to the OvalLSP VS Code extension are documented here.

## 0.1.5 — Lifecycle reliability and deeper semantic coverage

- Stops and reaps the Core process and, on macOS/Linux, its discovered
  descendant process groups during restart, deactivation, overlapping
  restart commands, and initialize hangs.
- Infers controller view instance variables assigned by conventional
  `before_action` callbacks, including inheritance, `skip_before_action`,
  literal `only:` / `except:` selectors, and callback-to-action type flow.
- Cold-indexes references and Rails generated methods, and re-resolves
  references when declarations arrive or disappear.
- Uses RBS/RBI overload return types in local inference, live-reloads
  project signature changes, and uses opt-in runtime observations only as
  a low-authority fallback for otherwise-Unknown returns.
- Fixes Union completion conditional flags, generated-method reopening
  fallback, stale model-dependent method summaries, duplicate Cold Index
  runs, and delayed automatic Agent retries after a manual restart.

## 0.1.4 — Actually fixes the false "Payload hash mismatch" warning

v0.1.3 attempted this fix and did not succeed: the warning still
appeared on every activation. The v0.1.3 diagnosis below (`vsce publish`
re-running its own prepublish hook and rebuilding native extensions) was
a real problem and remains fixed, but it was **not** the cause of this
warning.

The actual cause: `scripts/copy-core.js` recorded a sha256 over the
staged `core/` tree (815 files), while `.vscodeignore` independently
excluded `core/vendor/bundle/ruby/*/cache/**` — four Bundler `.gem`
archives — from the VSIX. The installed extension therefore always had
811 files, and rehashing it at activation could never reproduce the
recorded hash, on any machine, ever. Two independent definitions of
"the payload" that silently disagreed. Confirmed by rehashing a real
installed v0.1.3 and diffing the staged tree against the packaged one.

Fixed structurally rather than by patching the hash: those cache
archives are now deleted during staging (they are pure build
byproducts — `bin/ovallsp` only ever adds `**/gems/*/lib` to
`$LOAD_PATH`, never `cache/`, and they were already absent from every
shipped VSIX), so the staged tree *is* the shipped tree and hashing it
is meaningful. The `.vscodeignore` rule is gone, with a note against
adding any further `core/**` exclusion there.

New guard so this class of defect cannot reach users again:
`scripts/verify-packaged-payload-hash.js` rehashes the *packaged* VSIX
and compares it against that VSIX's own manifest — the same check the
extension runs at activation, now run at build time. It is wired into
both `release.sh` (before the publish prompt) and CI's package-contents
job, so any future divergence between what is hashed and what ships
fails the build. Verified by reintroducing the old `.vscodeignore` rule
and confirming the guard fails (exit 1), then restoring it and
confirming it passes.

## 0.1.3 — Fix: `vsce publish` rebuilt the extension instead of publishing the verified build

**Correction:** this release was published believing it fixed the false
"Payload hash mismatch" warning. It did not — see 0.1.4 above for the
actual cause. What is described below is a genuine, separate packaging
defect that this release did fix, and the fix is retained.

Fixes: `vscode/scripts/release.sh` (and, before it existed, a bare
`vsce publish` after a separate build) called `vsce publish
--target darwin-arm64 --pre-release` directly. `vsce publish` runs its
own `vscode:prepublish` hook independently of any earlier `npm run
package` -- silently rebuilding Core's vendored native extensions
(Prism, RBS) from scratch a second time. Native-extension compilation
isn't byte-reproducible run to run, so what actually reached the
Marketplace was never the artifact that had just been built,
smoke-tested and hashed — an unverified build was published every time.

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
