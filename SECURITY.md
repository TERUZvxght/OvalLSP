# Security Policy

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
2. **Untrusted plugins** (third-party OvalLSP plugins) must not be able
   to hijack Core's internal state or the LSP protocol stream itself.
3. **Secret leakage via logs/error messages** must be minimized, since
   Core often logs a target Rails app's own exception text verbatim.

See [docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md) for the
full, itemized threat model and mitigations — summarized:

- The Rails Runtime Agent (which can execute a target application's own
  code) only starts once a workspace is explicitly marked **trusted** in
  VS Code — fail-closed on anything else (missing/`false`/absent trust
  signal).
- Plugins run in a genuinely OS-process-isolated fork with no access to
  Core's live LSP transport or internal index objects; only plain,
  Marshal-safe data crosses the process boundary.
- Runtime (highest-privilege) plugins never load at all in an untrusted
  workspace.
- Log output runs through a redaction pipeline (bearer tokens, basic
  auth, DB connection strings, known vendor key formats, labeled
  credentials) before being written anywhere.
- Agent↔Core and plugin↔Core each require an exact protocol-version
  match; a mismatch is refused rather than tolerated.

## Scope

This policy covers the OvalLSP Core Server (`core/`) and VS Code
extension (`vscode/`) in this repository. It does not cover
vulnerabilities in your own Rails application's code, or in third-party
plugins not maintained in this repository.
