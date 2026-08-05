#!/usr/bin/env bash
# Packages and publishes OvalLSP to the VS Code Marketplace.
#
# Reads the publish PAT from vscode/.vsce-pat.local (one line, the token
# itself, nothing else) -- gitignored, never committed, never echoed or
# logged by this script. Create it yourself:
#
#   printf '%s' 'your-pat-here' > vscode/.vsce-pat.local
#   chmod 600 vscode/.vsce-pat.local
#
# See docs/PUBLISHING.md's Credentials section for how to obtain a PAT.
#
# This script builds the release candidate, runs the packaged semantic
# smoke test, and shows the package contents -- but it does NOT publish
# without an explicit "yes" typed at the confirmation prompt below. That
# prompt is the one part of this script intentionally not automated away:
# initial publish and every later publish are supposed to need a human
# saying "yes, publish this" at the moment it actually happens, not a
# standing approval baked into a script that runs unattended.
#
# Usage: vscode/scripts/release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VSCODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$VSCODE_DIR/.." && pwd)"
PAT_FILE="$VSCODE_DIR/.vsce-pat.local"

if [ ! -f "$PAT_FILE" ]; then
  echo "release.sh: $PAT_FILE does not exist." >&2
  echo "Create it with your Marketplace PAT (see docs/PUBLISHING.md's Credentials section):" >&2
  echo "  printf '%s' 'your-pat-here' > $PAT_FILE && chmod 600 $PAT_FILE" >&2
  exit 1
fi

# Read into a variable, never into a shell option or anything that could
# land in a trace/log -- and this script never sets -x, deliberately.
VSCE_PAT="$(cat "$PAT_FILE")"
if [ -z "$VSCE_PAT" ]; then
  echo "release.sh: $PAT_FILE is empty." >&2
  exit 1
fi

VERSION="$(node -p "require('$VSCODE_DIR/package.json').version")"
PUBLISHER="$(node -p "require('$VSCODE_DIR/package.json').publisher")"
NAME="$(node -p "require('$VSCODE_DIR/package.json').name")"

echo "== release.sh: building $PUBLISHER.$NAME v$VERSION (darwin-arm64) =="

cd "$VSCODE_DIR"

echo "-- npm ci --"
npm ci

echo "-- npm run package (copy-core -> tsc -> vsce package --target darwin-arm64) --"
npm run package

VSIX_PATH="$VSCODE_DIR/ovallsp-darwin-arm64-$VERSION.vsix"
if [ ! -f "$VSIX_PATH" ]; then
  echo "release.sh: expected $VSIX_PATH to exist after 'npm run package' but it doesn't." >&2
  exit 1
fi

echo "-- vsce ls --tree (full package contents) --"
npx @vscode/vsce ls --tree

echo "-- unpacking for semantic smoke and a core/ sanity check --"
UNPACK_DIR="$(mktemp -d)"
trap 'rm -rf "$UNPACK_DIR"' EXIT
unzip -q "$VSIX_PATH" -d "$UNPACK_DIR"

if [ ! -d "$UNPACK_DIR/extension/core/vendor/bundle" ]; then
  echo "release.sh: packaged VSIX has no extension/core/vendor/bundle -- Core Server was not vendored." >&2
  echo "This is the exact failure that broke v0.1.0; refusing to publish." >&2
  exit 1
fi

# Found by actually inspecting a real run's `vsce ls --tree` output:
# .vscodeignore not excluding .vsce-pat.local let vsce package bundle the
# PAT file itself straight into the VSIX. .vscodeignore now excludes it
# too, but this check exists so a future .vscodeignore regression (or any
# other stray credential-shaped file landing at the package root) fails
# loudly here, before ever reaching the publish prompt, rather than
# silently shipping inside a public VSIX.
if [ -f "$UNPACK_DIR/extension/.vsce-pat.local" ]; then
  echo "release.sh: the packaged VSIX contains .vsce-pat.local -- the Marketplace PAT itself would ship inside it." >&2
  echo "Check vscode/.vscodeignore excludes it, then rebuild. Refusing to publish." >&2
  exit 1
fi

# Runs the *runtime* payload-hash check against the packaged artifact,
# here, rather than letting every user discover it at activation. v0.1.2
# and v0.1.3 both shipped with a manifest that could never match the
# installed tree (`.vscodeignore` stripped four already-hashed
# `vendor/bundle/**/cache/*.gem` archives), so every install showed a
# false "may be corrupted" warning -- and nothing in this script noticed,
# because everything before this point only ever inspected the staged
# tree or the file list, never the shipped payload's own hash.
echo "-- node scripts/verify-packaged-payload-hash.js --"
node "$VSCODE_DIR/scripts/verify-packaged-payload-hash.js" "$UNPACK_DIR/extension"

echo "-- ruby scripts/vsix_semantic_smoke.rb --"
ruby "$REPO_ROOT/scripts/vsix_semantic_smoke.rb" "$UNPACK_DIR/extension"

echo "-- SHA-256 --"
SHA256="$(shasum -a 256 "$VSIX_PATH" | awk '{print $1}')"
echo "$SHA256  $(basename "$VSIX_PATH")"

echo
echo "About to publish $PUBLISHER.$NAME v$VERSION (darwin-arm64) to the Marketplace Pre-Release channel."
echo "VSIX: $VSIX_PATH"
echo "SHA-256: $SHA256"
read -r -p "Publish now? Type 'yes' to proceed, anything else to abort: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "release.sh: aborted -- not published."
  exit 1
fi

# Publishes the EXACT file just built, smoke-tested, and hashed above --
# never `vsce publish --target ... --pre-release` on its own. Found by
# directly reproducing a real, live bug: `vsce publish` runs its own
# `vscode:prepublish` (copy-core -> tsc) independently, on top of the one
# `npm run package` already ran, silently rebuilding Core's vendored
# native extensions from scratch a second time. Since native-extension
# compilation isn't byte-reproducible run to run, this produced a
# genuinely different binary than the one this script had just verified
# -- and the manifest embedded in that second, unverified build didn't
# match its own payload hash by the time it reached the Marketplace
# (confirmed by downloading the actual published v0.1.2 VSIX and finding
# its own PLATFORM_MANIFEST.json didn't match a live rehash of its own
# core/ directory -- exactly the false "Payload hash mismatch... may be
# corrupted" warning reported from a real install). `--packagePath`
# uploads this exact file as-is, so nothing rebuilds between "verified"
# and "published" ever again.
echo "-- vsce publish --packagePath \"$VSIX_PATH\" --pre-release --"
VSCE_PAT="$VSCE_PAT" npx @vscode/vsce publish --packagePath "$VSIX_PATH" --pre-release

echo "== release.sh: published $PUBLISHER.$NAME v$VERSION =="

# The hash is worth nothing unmatched against anything later, and
# `docs/PUBLISHING.md` has asked for it to be "recorded" since the first
# Preview without ever saying where -- so for sixteen tags it was printed
# and lost. Printed here in the exact shape the table takes, as the last
# thing on screen, so recording it is a paste rather than a task.
echo
echo "Add this row to the Published table in docs/RELEASE_ARTIFACTS.md, then commit:"
echo
echo "| $VERSION | \`$SHA256\` | Pre-Release |"
echo
echo "core/spec/meta/release_artifacts_spec.rb fails until every tag is accounted for."
