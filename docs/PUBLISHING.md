# Publishing OvalLSP to the VS Code Marketplace

[日本語版](PUBLISHING.ja.md)

This document describes how OvalLSP is packaged and published. It is a
process document, not an authorization to publish — see
[docs/RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) (Japanese) for the
gate that must pass first, and note the explicit approvals required
below. (The first Preview, v0.1.1, has already been published following
this process; this document remains the reference for any future
release.)

## Scope of the first Preview

The first release targets **macOS on Apple Silicon (`darwin-arm64`)
only**, published to the Marketplace's **Pre-Release** channel. It is
never published as a generic, targetless VSIX — see ADR-0005 and
ADR-0006 for why a single-target build is the right choice for this
stage, and `docs/design/tasks/023.5-darwin-arm64-packaging-and-update-regression.md`
for how the packaging script enforces this.

## Versioning: the bundled Core carries the extension's version

The gem version in `core/lib/ovallsp/version.rb` and the extension
version in `vscode/package.json` are one number for a bundled build. A
bundled Core is produced by this extension's own packaging step, ships
inside the VSIX, and is reported to users as "Core x.y.z" by
`OvalLSP: Show Version Information` — so a Core version that no release
ever had makes a bug report impossible to map back to a build.

**Bump `Ovallsp::VERSION` together with `package.json`, even for a
release that changed no Ruby code.** That is the case that forgets, so it
is not left to procedure: `copy-core.js` refuses to write a platform
manifest when the two disagree, and `npm run package` fails with both
versions named. There is nothing to remember — a mismatched build cannot
be produced.

A Core the extension did *not* build is deliberately exempt:

| Core | Version rule | Judged on |
|---|---|---|
| Bundled (shipped in the VSIX) | must equal the extension version | protocol range, plus the manifest checks — build commit, payload hash, target, Ruby engine/version |
| Monorepo checkout (development) | may differ | protocol range only |
| User-supplied `ovallsp.rubyExecutablePath` / custom Core path | may differ | protocol range only |

The two lower rows are ADR-0006's guarantee #9: a Core the user chose is
judged only on whether it can actually talk to this extension, never
flagged as wrong merely for differing from a manifest that was never
meant to describe it. Compatibility itself is always decided on the
protocol range, never by comparing version strings — so an older Core
that still speaks the same protocol keeps working.

## Building the release artifact

Must be run on a real Apple Silicon Mac — never emulated/cross-compiled
from an x86_64 machine or a Linux CI runner (a native gem extension built
elsewhere would produce a payload that doesn't match its own declared
target).

```bash
cd vscode
npm run package
```

This runs, in order: `copy-core.js` (vendors Core Server's runtime gems,
writes `PLATFORM_MANIFEST.json`), `tsc` (compiles the extension), then
`vsce package --target darwin-arm64 --allow-missing-repository`. The
result is `ovallsp-darwin-arm64-<version>.vsix`.

`vscode/package.json`'s `vscode:prepublish` script also runs `copy-core`
and `tsc` automatically before *any* `vsce package`/`vsce publish`
invocation, even a bare one that skips `npm run package` entirely — this
exists because v0.1.0 was accidentally published without Core Server
vendored at all (`vsce publish` was run directly, bypassing `npm run
package`), producing a VSIX that couldn't start. `npm run package`
remains the recommended way to build a release candidate regardless,
since it also runs `tsc`'s own compile step explicitly for local
inspection before packaging.

Before treating this as a release candidate:

1. Run `vsce ls --tree` and review the full file list — check for
   absolute paths, local usernames, or anything not meant to ship.
2. Compute and record the VSIX's SHA-256.
3. Run `ruby scripts/vsix_semantic_smoke.rb <path-to-unpacked-vsix>/extension`
   against the packaged output.
4. Confirm `docs/RELEASE_CHECKLIST.md`'s gate items all pass.

## Publishing

`vscode/scripts/release.sh` automates the full pipeline: builds the
package, verifies `core/` was actually vendored (the exact thing that
broke in v0.1.0), runs `vsce ls --tree` and the packaged semantic smoke
test, computes the SHA-256, and only then prompts for a typed `yes`
before running `vsce publish --target darwin-arm64 --pre-release`. It
reads the PAT from `vscode/.vsce-pat.local` (gitignored — see
Credentials below) rather than requiring it typed in each time.

```bash
vscode/scripts/release.sh
```

The prompt at the end is deliberate and not skippable by a flag: every
publish, not just the first, needs a human saying "yes, publish this" at
the moment it happens — a script that removed that step would undo the
whole point of gating it. Whether run via this script or the bare `vsce
publish` command directly, **this must not happen until all of the
following are true:**

- The Marketplace publisher ID has been confirmed by the project owner
  (not guessed or assumed by whoever is preparing the release — a
  publisher ID is a permanent Marketplace identifier), and the Extension
  `name` in `package.json` (also permanent) likewise.
- Marketplace publish credentials are available and configured (see
  Credentials below).
- The release candidate version has been confirmed by the project owner.
- `docs/RELEASE_CHECKLIST.md`'s gate is fully green.
- The project owner has explicitly said the release may be published.

Initial publish, and any later republishing under a new major scope
(e.g. adding another platform target), follow this same approval
sequence — a green checklist is a precondition for asking, not a
substitute for asking.

## Credentials

- Never commit a Personal Access Token (PAT) or any other credential to
  this repository, in any form (files, commit messages, CI logs).
- If using a PAT directly with `vsce publish`, provide it only via an
  ephemeral environment variable (`VSCE_PAT`) for a single publish
  invocation, or as a GitHub Actions secret consumed by a release
  workflow — never written to a tracked file.
- `vscode/scripts/release.sh` reads the PAT from `vscode/.vsce-pat.local`
  — a single line containing only the token, gitignored (see
  `.gitignore`'s own comment on that entry) so it's never committed. This
  is a local convenience for repeated publishing, not a relaxation of the
  rule above: the file never leaves your machine, the script never
  prints or logs its contents, and it's still your responsibility to
  protect it the same way as any other local credential (correct file
  permissions, not syncing it to a shared or backed-up location you don't
  control).
- `vsce login` stores a credential in your local machine's credential
  store; understand that scope before using it on a shared machine.
- Marketplace publisher registration itself (creating the publisher
  account, verifying it) is a manual step in the Microsoft/Azure
  DevOps/Marketplace UI, outside this repository's tooling. Whoever owns
  the publisher account performs this directly; this document doesn't
  attempt to automate account creation.

### Future direction: Microsoft Entra ID

The VS Code Marketplace's PAT-based publishing model is expected to be
phased out in favor of Microsoft Entra ID-based authentication. This
project's first Preview uses PAT-based publishing (or manual upload
through the Marketplace web UI) as the pragmatic choice for now, and
should migrate to Entra ID-based publishing before that deprecation
takes effect. This migration is tracked as separate, post-Preview,
non-blocking work.

## What this document does not cover

- Making this repository public — a separate, explicitly-gated decision
  (see `docs/design/tasks/023.7-*.md`, Japanese, for the GitHub public-
  readiness prep that preceded it). This repository is now public, but
  this remains a decision to make deliberately for any repository, not
  something a publish should do implicitly.
- CI/CD automation of the steps above — see
  `docs/design/tasks/023.7-*.md` (Japanese) for what exists and what's
  manual-only for now.
- Publishing additional platform targets (Linux, Windows, Intel Mac) —
  out of scope for this Preview; see ADR-0005's rejected alternatives
  and the post-Preview issue list.
