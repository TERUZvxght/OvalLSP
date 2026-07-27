# Changelog

All notable changes to the OvalLSP VS Code extension are documented here.

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

This is a Preview release. Feedback on the above, and on this Preview's
Apple-Silicon-only scope, is welcome via
[SUPPORT.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.md).
