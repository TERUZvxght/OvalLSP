# Support

OvalLSP is currently in **Preview** (Pre-Release), scoped to macOS on
Apple Silicon with Ruby 3.4.x. See
[docs/SUPPORT_MATRIX.md](docs/SUPPORT_MATRIX.md) for exactly what's
verified, and [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) for
what's intentionally out of scope right now.

## Before reporting an issue

1. Run `OvalLSP: Show Version Information` and `OvalLSP: Show
   Environment Diagnostics` — most reports need this output.
2. Check [docs/SUPPORT_MATRIX.md](docs/SUPPORT_MATRIX.md) to confirm
   your platform/Ruby/Rails combination is one this Preview actually
   targets.
3. Check the [vscode/README.md](vscode/README.md) Troubleshooting
   section for common cases (Ruby not found, Rails features not
   working, cache issues).

## Reporting a bug

Open a GitHub issue with:

- What you expected vs. what happened.
- The `OvalLSP: Show Version Information` and `OvalLSP: Show Environment
  Diagnostics` output.
- A minimal reproduction if possible (a small Ruby/Rails project
  fixture).
- Whether it reproduces with `ovallsp.server.path` unset (the bundled
  Core Server) — reports against a custom Core Server build are still
  welcome, but please say so.

## Security issues

Do not open a public issue for a security vulnerability — see
[SECURITY.md](SECURITY.md) for private reporting.

## Feature requests / feedback on the Preview scope

This Preview intentionally targets a single platform first. If you'd
like to see another OS/CPU/Ruby/Rails combination supported, feel free
to open an issue — the roadmap for expanding beyond Apple Silicon is
tracked separately (see [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)
and this repository's issue tracker for post-Preview work).
