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

### What each number means

The extension and the bundled Core share one version, so this is the
meaning of both.

| Position | Changes when | Examples |
|---|---|---|
| patch (`0.1.**7**`) | Nothing new is announced — the release makes the extension do what the previous one already claimed | Bug fixes, performance, refactoring, documentation. **A capability row may be added or turned ✅** when it names something the previous release was already understood to do and did not: 0.2.1 added `G17` this way, for a capability 0.2.0 shipped without a row. What it must not do is announce a capability nobody was promised — 0.2.1 added three such rows during its review loop and moved all three back to the roadmap before shipping |
| minor (`0.**1**.5`) | A capability is added | A new row in the capability matrix, a `NOT YET` becoming ✅, a new setting or command |
| major (`**0**.1.5`) | Something a user already relies on stops working | A setting or command removed or renamed, a supported environment tier dropped, an older protocol version no longer accepted, a ✅ row removed |

Note what the patch row does **not** say: that nothing a user sees
changes. A bug fix changes what a user sees — that is the whole point of
it — and a rule reading otherwise would have no patch releases in it at
all. 0.1.7 is the worked example: two false diagnostics stop appearing in
every Rails project, which every user sees, and it is still a patch
because the extension gained no capability it did not already claim.

"Capability" means a row of
[`docs/EXTENSION_CAPABILITIES.md`](EXTENSION_CAPABILITIES.md), which is
also what README's matrix summarises. That is deliberate: the version
number and the capability list move together, so "what changed" is
answerable from the two of them without reading the diff.

It follows that a planned capability names a minor release exactly —
`0.2.0`, not `0.2.x`. A range spelt with `x` puts the unknown in the
patch position, which says the capability might arrive in a patch, and
nothing ever does. Several capabilities may share one minor and ship
together, as 0.1.6's five did.

A row that records what the extension must **not** report is a regression
guard, not a capability, and adding one is a patch. `docs/EXTENSION_CAPABILITIES.md`
carries both kinds — G10 through G14 all read "nothing", because the way
to state "this false positive does not come back" is to give it a row and
an E2E example. Reading the rule mechanically as "any new row is a minor"
would make every bug fix a minor release, which is the opposite of what
the table above means by "a capability is added". The test is whether a
user can do something they could not do before, not whether the document
grew a line. (Written down after 0.1.7, whose whole content was removing
one wrong report, needed the question settled.)

The protocol version in the Extension/Core handshake is a separate
integer and is not derived from this version string. Dropping an old
protocol version from the accepted range is a major change; adding a new
one is not.

### 0.x, and what 1.0.0 requires

While the major version is 0, everything above still applies except that
a breaking change may ship in a minor release rather than forcing a major
one — the usual pre-1.0 convention.

**These are the environment half, and they are necessary rather than
sufficient.** What 1.0.0 is *for* — the foundation being solid enough that
a Ruby/Rails engineer is measurably better off, with Pylance as the
reference — is stated in
[`docs/design/docs/01-product-requirements.md`](design/docs/01-product-requirements.md)
section 0, and that document is the one to read first. A 1.0.0 that met
only the two conditions below would be an insufficient product that runs
everywhere. **This framing is this project's inference, not a maintainer ruling** —
written during 0.2.4 after a session took the two conditions below to
*be* the definition of finished. What is theirs is section 0's
definition itself.

1.0.0 is reserved for the point where the two "not yet" qualifications in
README's capability matrix are gone:

1. **Every environment we publish for is guaranteed, not just Apple
   Silicon.** Today one VSIX is published, `darwin-arm64`, and it is the
   only environment any capability is verified in. 1.0.0 requires
   published, verified artifacts for the other targets as well
   (`darwin-x64`, `win32-x64`, `linux-x64`) — see
   `docs/design/tasks/024-deferred-review-findings.md` 024.R4.
2. **A plain Ruby project is guaranteed, not only a Rails one.** Today
   the Rails conventions have no explicit boundary and nothing specifies
   or verifies what a non-Rails project should expect — 024.R1.

Both are about the *environment* axis rather than the feature axis. New
features arrive in minor releases and do not bring 1.0.0 closer; removing
the asterisks from the environments does.

One process change rides along with 1.0.0 rather than gating it: from
that release every tag gets a GitHub Release. See "GitHub Releases: none
until 1.0.0" below for why not before.

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
2. Compute the VSIX's SHA-256 and record it in
   [`docs/RELEASE_ARTIFACTS.md`](RELEASE_ARTIFACTS.md). `release.sh` prints
   the row to paste. This step existed without a destination from the
   first Preview until 0.2.0, which is why fourteen releases have a hash
   nobody kept.
3. Run `ruby scripts/vsix_semantic_smoke.rb <path-to-unpacked-vsix>/extension`
   against the packaged output.
4. Confirm `docs/RELEASE_CHECKLIST.md`'s gate items all pass.

## Publishing

`vscode/scripts/release.sh` automates the full pipeline: builds the
package, verifies `core/` was actually vendored (the exact thing that
broke in v0.1.0), runs `vsce ls --tree` and the packaged semantic smoke
test, computes the SHA-256, and only then prompts for a typed `yes`
before running:

```
vsce publish --packagePath <the vsix it just verified> --pre-release
```

**`--packagePath`, never `--target`**, and the difference is the whole
point of the step. `vsce publish --target ...` runs `vscode:prepublish`
(`copy-core` → `tsc`) *again*, on top of the run `npm run package`
already did, rebuilding Core's vendored native extensions from scratch a
second time. Native-extension compilation is not byte-reproducible run
to run, so what reaches the Marketplace is a different binary from the
one that was just smoke-tested and hashed — which is exactly how v0.1.2
shipped a `PLATFORM_MANIFEST.json` that did not match its own payload,
and users saw a "Payload hash mismatch… may be corrupted" warning that
was true. `--packagePath` uploads the verified file as-is.

*This paragraph documented the `--target` form until 0.2.14 — the one
`release.sh`'s own comment says must never be used. Anyone publishing by
hand from this document would have reproduced v0.1.2.*

It reads the PAT from `vscode/.vsce-pat.local` (gitignored — see
Credentials below) rather than requiring it typed in each time.

```bash
vscode/scripts/release.sh
```

The prompt at the end is deliberate and not skippable by a flag. What it
protects is that **no publish happens without the project owner deciding
that this release should ship** — every publish, not just the first. A
standing approval baked into a script that runs unattended is what it
exists to prevent.

It does *not* require the owner's own fingers on the keystroke. 0.2.3
was published by an agent driving this script under the owner's explicit
instruction, and that is within the rule as the owner restated it: the
human gives the go-ahead, and the publish is then carried out reliably
and safely; an agent in between is fine, and is better placed to read the
build and smoke output for anomalies than a person scrolling it. What is
*not* within the rule is a script — or an agent — reaching this prompt
without a decision behind it, or reaching it and deciding for itself.

**A patch does not need the owner asked again.** Their standing position,
given during 0.2.4: for a *patch* — no capability row moves, by the table
above — the go-ahead is already granted, **provided the secret and privacy
checks have actually been run and have passed**. Concretely that means
`release.sh` reached its publish step, which refuses a `.vsce-pat.local`
readable beyond its owner; the token appears nowhere in the run's output;
gitleaks is clean over the outgoing range; and
`scripts/check_home_paths.rb` is clean in both modes. A minor or major
release still asks, and so does a patch where any of those did not run.

That is the whole of the delegation; it is not a general licence. It
exists because this class of change fixes what was already promised and
adds nothing, so the decision can honestly be made in advance — and it is
written here because a permission carried only in a conversation is one
compaction away from being either forgotten or assumed larger than it is.

So the obligation transfers rather than disappears. Whoever answers the
prompt on the owner's behalf must have read what the script printed
before it — the vendored-core check, the payload hash, `vsce ls --tree`,
the semantic smoke, the SHA-256 — and must say what it found. 0.2.3's run
is recorded in `docs/design/tasks/028-0.2.3-review-loop.md`, including
the one thing worth reporting from it (nine `EBADENGINE` warnings, all
`devDependencies` of `@vscode/vsce` and one of the test harness, none of
them shipped). Whether run via this script or the bare `vsce
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

## GitHub Releases: none until 1.0.0

There is no GitHub Release for any tag, and through 0.x there will not
be. That is a decision, not an oversight — it was noticed while 0.2.0 was
being published and left as it is deliberately.

Both changelogs are the release note. They live in the repository, they
ship *inside* the VSIX, and the Marketplace renders `CHANGELOG.md` on the
extension's own page. A GitHub Release would be a third copy of the same
text, and this project's own rule — the one `docs/DOCUMENTATION_MAP.md`
opens with — is that a fact restated in several places will be wrong in
one of them. Through 0.x nobody is served well enough by the third copy
to pay that.

**From 1.0.0 onward, every tag gets a GitHub Release.** What changes at
1.0.0 is not the amount of text but who arrives and from where. 1.0.0 is
where the platform matrix is verified and a plain Ruby project is
guaranteed (024.R1, 024.R4), so people will reach a tag from outside the
Marketplace — a link, a dependency scanner, a security question about a
specific version — and expect to see what that version contains and what
its artifact hashes to without installing anything first. That is what a
Release is for, and it is worth the third copy then.

When that starts, the body should point at the changelog entry rather
than restate it, and carry the SHA-256 from
[`docs/RELEASE_ARTIFACTS.md`](RELEASE_ARTIFACTS.md).

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
