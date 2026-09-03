# Security Policy

[日本語版](SECURITY.ja.md)

## Reporting a vulnerability

If you find a security vulnerability in OvalLSP, please report it
privately rather than opening a public issue. Use GitHub's private
vulnerability reporting for this repository (Security tab → "Report a
vulnerability"), or contact the maintainers directly if that isn't
available.

Please include:

- A description of the vulnerability and its potential impact.
- Steps to reproduce it (a minimal Ruby/Rails project fixture, if
  relevant).
- The OvalLSP extension version, Core Server version, and environment
  (`OvalLSP: Show Version Information` output is a good start).

We'll acknowledge reports as soon as possible and follow up with a
timeline once the issue is understood. Please don't publicly disclose a
vulnerability before we've had a chance to address it.

## Threat model

OvalLSP is a local development tool: a language server communicating
with VS Code over stdio, with no network listener of its own. The
threat model that actually matters here is not "a remote attacker
reaching the process over the network" — it's:

1. **Untrusted workspaces** (opening someone else's repository, checking
   out a malicious PR) must not let the Core process itself, or the
   developer's machine, be compromised just by opening the folder.
2. **Results read from another process** — the Rails Runtime Agent's
   answers, and the types a test run reports — must not be able to
   construct objects inside Core or hijack the LSP protocol stream.
3. **Secret leakage via logs/error messages** must be minimized, since
   Core often logs a target Rails app's own exception text verbatim.

See [docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md) (Japanese) for the
full, itemized threat model and mitigations — summarized:

- The Rails Runtime Agent (which can execute a target application's own
  code) only starts once a workspace is explicitly marked **trusted** in
  VS Code — fail-closed on anything else (missing/`false`/absent trust
  signal).
- What another process sends back — the Agent's answers, a test run's
  observed types — crosses the boundary as plain JSON. A payload cannot
  name a class, Core rebuilds typed values only from fields it has
  validated, and one malformed element discards the whole payload.
- Restarting the Agent asks the same trust question as starting it; the
  check sits where the process is spawned, not at each caller.
- Log output runs through a redaction pipeline (bearer tokens, basic
  auth, DB connection strings, known vendor key formats, labeled
  credentials) before being written anywhere.
- Agent↔Core requires an exact protocol-version match; a mismatch is
  refused, the child is stopped, and Core falls back to static-only
  answers.

## A past incident affecting source checkouts

**If you cloned or checked out this repository between 2026-08-05 and
2026-08-11 and ran the Core test suite, it deleted directories outside
the repository.** A cache-pruning example passed a fabricated absolute
path (`current: "/x"`) to code that removes directories. The sweep
resolved to the filesystem root, kept the most recently modified entry
and removed the rest, so on macOS `/Applications` was emptied of anything
not protected by SIP. It stopped when a protected path raised, which is
why some applications survived. Every error was swallowed by the method
under test, so the run reported success.

Affected commits are `28a041c` (2026-08-05) through the fix; tag `v0.2.1`
contains them. Reinstall from Time Machine or from the applications' own
installers — nothing here can recover them.

**The published extension was never affected.** `core/spec/**` is
excluded from the VSIX, and the one production caller derives both paths
from the same cache root, so the sweep could not leave it. Only running
this repository's test suite from a source checkout could reach it.

## Scope

This policy covers the OvalLSP Core Server (`core/`) and VS Code
extension (`vscode/`) in this repository. It does not cover
vulnerabilities in your own Rails application's code or in the gems it
loads.
