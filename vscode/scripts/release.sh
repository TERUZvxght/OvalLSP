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
# without an explicit "yes" typed at the confirmation prompt below.
#
# The prompt is not skippable by a flag, and what it protects is that no
# publish happens without a decision behind it. It does *not* require the
# project owner's own keystroke, and for a **patch** the decision is
# already made: see docs/PUBLISHING.md's Publishing section, "A patch does
# not need the owner asked again", for the standing delegation and the
# privacy conditions it is conditional on. An agent answering this prompt
# under that delegation is within the rule; reaching it with no decision
# behind it, or deciding for oneself, is not.
#
# Usage: vscode/scripts/release.sh

set -euo pipefail

# This script decides which repository it is publishing from -- REPO_ROOT
# below -- and then asks git about it. Git will not agree unless these
# are unset: GIT_DIR and its family override the working directory, and
# `-C` does not. Inherited from a hook or a wrapper, they would point the
# clean-tree refusal below at a different repository, so a dirty tree
# could publish a VSIX whose baked-in commit SHA names content that does
# not exist. 024.157, and the same scrub RepoFiles applies in Ruby.
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE

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

# The header above tells you to `chmod 600` this file, and until 0.2.4
# nothing checked that you had. The file holds a Marketplace publish
# token; on a shared or backed-up machine, mode 644 hands it to every
# local account and to anything that walks $HOME. A documented
# precaution that is never verified is a precaution only for the person
# who remembers it, which is the class of defect this release is about.
# GNU first, BSD second, and the order is the whole point. GNU's `stat -f`
# means *file system* status and succeeds with output that is not a mode
# at all, so trying BSD's spelling first silently produced garbage on
# Linux -- `8#<garbage>` then made the arithmetic fail and the refusal
# never fire. BSD's `stat` rejects `-c` outright, so this order degrades
# correctly in both directions. Caught by CI, on a check whose whole
# purpose is refusing; it had only ever been exercised on macOS.
PAT_MODE="$(stat -c '%a' "$PAT_FILE" 2>/dev/null || stat -f '%Lp' "$PAT_FILE" 2>/dev/null || echo '')"
if [ -n "$PAT_MODE" ] && [ "$(( 8#$PAT_MODE & 8#077 ))" -ne 0 ]; then
  echo "release.sh: $PAT_FILE is mode $PAT_MODE -- readable beyond its owner." >&2
  echo "This file is a Marketplace publish token. Fix it and re-run:" >&2
  echo "  chmod 600 $PAT_FILE" >&2
  exit 1
fi

# Read into a variable, never into a shell option or anything that could
# land in a trace/log -- and this script never sets -x, deliberately.
VSCE_PAT="$(cat "$PAT_FILE")"
if [ -z "$VSCE_PAT" ]; then
  echo "release.sh: $PAT_FILE is empty." >&2
  exit 1
fi

# vscode/scripts/copy-core.js bakes `buildCommit: currentGitCommit()`
# into the packaged Core, so a VSIX built from a dirty tree claims a
# commit whose content it does not match -- and that SHA is what the
# installed extension reports and what a published artifact is checked
# against afterwards. Untracked files are not the concern (a stray
# .vsix or a scratch file changes nothing about what is packaged);
# modified tracked content is.
#
# RELEASE_CHECKLIST gate #1. It used to say `make-final-review-bundle.sh`
# enforced this, and nothing invoked that script -- so between its last
# hand-run and 0.2.14 the gate was enforced by nothing. Pinned by
# core/spec/meta/release_script_guard_spec.rb.
#
# `git diff --quiet` has three answers, not two: 0 clean, 1 dirty, and
# anything above 1 for "I cannot tell you" -- not a repository, an
# unreadable index, a broken object store. The `if ! git ...` form this
# replaces collapsed the third into the second, so a tree git could not
# read was announced to the operator as a tree with uncommitted changes:
# a failure to *ask*, turned into an assertion about their tree. Both
# still refuse, because publishing on an unanswered question is not an
# option -- but the reason printed is now the reason. 024.158.
TREE_STATUS=0
git -C "$REPO_ROOT" diff --quiet 2>/dev/null || TREE_STATUS=$?
if [ "$TREE_STATUS" -eq 0 ]; then
  git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null || TREE_STATUS=$?
fi

if [ "$TREE_STATUS" -gt 1 ]; then
  echo "release.sh: cannot read the tracked tree at $REPO_ROOT (git exited $TREE_STATUS)." >&2
  echo "The packaged Core records the current commit as its buildCommit, and that cannot be" >&2
  echo "decided from a question git could not answer. Not publishing." >&2
  exit 1
fi

if [ "$TREE_STATUS" -ne 0 ]; then
  echo "release.sh: the tracked tree has uncommitted changes." >&2
  echo "The packaged Core records the current commit as its buildCommit, so publishing" >&2
  echo "now would ship an artifact naming a commit it does not match. Commit or stash:" >&2
  git -C "$REPO_ROOT" status --short >&2
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
# The $HOME check has never run against the artifact that actually
# ships. ci.yml greps an *ubuntu-built* VSIX, where $HOME is
# /home/runner and the vendored native extensions are different files
# entirely; apple-silicon-release.yml has no such step. So the only
# build a user installs was the one build nobody inspected -- and this
# script is the last point where the real thing exists on disk.
#
# Compiled extensions are excluded from the hard failure because their
# embedded path is a real dependency rather than a removable byproduct:
# prism.bundle and rbs_extension.bundle carry an absolute LC_LOAD_DYLIB
# reference to the building Ruby's libruby (confirmed with `otool -L`),
# and it is mitigated at spawn time by resolving the real interpreter's
# bindir/libdir rather than the rbenv shim -- see
# vscode/src/platformCompatibility.ts#queryRubyConfigPaths and
# RELEASE_CHECKLIST gate #15, which records how that mitigation was
# arrived at. This reason used to be deferred to
# make-final-review-bundle.sh, which 0.2.14 deleted.
# They are reported instead, so a reader of this log can see what is in
# there rather than inferring it from silence.
#
# /usr/bin/grep by absolute path, never bare `grep`: on a machine where
# the name resolves to a ugrep wrapper it skips binary files without -a
# and reports a clean artifact that is not. 0.2.3 filed and withdrew a
# register entry over exactly that.
echo "-- packaged-artifact path inspection --"
# One variable for the path, used by both the count and the grep. They
# were two expressions naming the same directory, which is not the same
# thing: a re-derivation round pointed the *grep* at a subdirectory that
# does not exist, and the count -- computed from `$UNPACK_DIR` -- stayed
# plausible, so the check inspected nothing and the guard reported a
# healthy number. A count that is not derived from what was actually
# searched guards the variable rather than the search.
INSPECT_ROOT="$UNPACK_DIR"
# The pattern and the exclusion set, once each, so that the count and
# the control below test the search this check actually performs.
#
# One list, not three copies: with the flags written out on each
# invocation, widening them on the *inspection* grep alone left both the
# count and the control untouched and healthy -- measured, and it ships a
# leaking artifact. Two expressions that must agree about the same thing
# is the defect this whole block is about, one level in.
#
# The control's *content* is written from `$HOME` -- the environment,
# not `INSPECT_PATTERN` -- so changing what is searched for cannot change
# what is planted, and the control goes red instead of following the
# mutation. 024.198.
INSPECT_PATTERN="$HOME"
INSPECT_EXCLUDE=(--exclude='*.bundle' --exclude='*.so' --exclude='*.dylib')
if /usr/bin/grep -rlF "${INSPECT_EXCLUDE[@]}" "$INSPECT_PATTERN" "$INSPECT_ROOT"; then
  echo "release.sh: the packaged VSIX contains this build machine's own absolute path (outside native extensions)." >&2
  echo "Refusing to publish." >&2
  exit 1
fi
if /usr/bin/grep -rlF "$HOME" "$INSPECT_ROOT" --include='*.bundle' --include='*.so' --include='*.dylib' >/dev/null; then
  echo "note: compiled native extension(s) embed this machine's Ruby install path (expected; mitigated at spawn -- see 023.8)."
fi
# Prints what it looked at, not only that it passed. A text pin cannot
# see a semantic mutation -- negating the condition, or aiming the check
# at a directory that does not exist -- and an attack round demonstrated
# both.
#
# "Aimed at nothing" has three dimensions -- the directory, the pattern,
# and the exclusion set -- and until 0.2.16 the count covered one badly.
# It was `find "$INSPECT_ROOT" -type f | wc -l`, which shares only the
# variable with the grep above; measured on a 151-file fake artifact
# holding one leak, the shipped check, a check whose pattern matched
# nothing, and a check with four more `--exclude` flags all printed the
# same 151. `024.198`. A count that is not derived from what was
# actually searched guards the variable rather than the search -- which
# this file's own comment already said, while doing it.
#
# **Two derivations, because one does not reach.** The count below is
# `grep -L` with the identical flags: the files that same invocation
# read and cleared, so an unreachable directory collapses it. But a
# pattern that matches nothing, or a wider exclusion set, still leaves a
# healthy-looking number -- measured: 151 and 150 against the shipped
# 150. What catches those is a positive control: a scratch directory of
# files that certainly contain the pattern, in the extensions an
# exclusion could be widened to cover, which the same command with the
# same flags must find all of.
INSPECTED="$( { /usr/bin/grep -rLF "${INSPECT_EXCLUDE[@]}" "$INSPECT_PATTERN" "$INSPECT_ROOT" || true; } | wc -l | tr -d ' ')"
echo "PASS: packaged-artifact path inspection (${INSPECTED} files inspected)"
if [ "$INSPECTED" -lt 100 ]; then
  echo "release.sh: only ${INSPECTED} files were inspected -- the artifact should have over a thousand." >&2
  echo "The check is looking at the wrong place. Refusing to publish." >&2
  exit 1
fi

# The control. Scratch files, removed immediately; nothing here is ever
# tracked, and the grep's output is discarded so the path itself is not
# echoed into a log.
CONTROL_DIR="$(mktemp -d)"
for ext in js json map rb txt; do
  printf '%s/probe\n' "$HOME" > "$CONTROL_DIR/control.$ext"
done
CONTROL_FOUND="$( { /usr/bin/grep -rlF "${INSPECT_EXCLUDE[@]}" "$INSPECT_PATTERN" "$CONTROL_DIR" || true; } | wc -l | tr -d ' ')"
rm -rf "$CONTROL_DIR"
if [ "$CONTROL_FOUND" -ne 5 ]; then
  echo "release.sh: the path inspection found ${CONTROL_FOUND} of 5 control files that certainly match." >&2
  echo "Its pattern or its exclusion set is wrong, so a clean result above means nothing." >&2
  echo "Refusing to publish." >&2
  exit 1
fi
echo "PASS: packaged-artifact path inspection control (5 of 5 planted matches found)"

echo "-- node scripts/verify-packaged-payload-hash.js --"
node "$VSCODE_DIR/scripts/verify-packaged-payload-hash.js" "$UNPACK_DIR/extension"

echo "-- ruby scripts/vsix_semantic_smoke.rb --"
ruby "$REPO_ROOT/scripts/vsix_semantic_smoke.rb" "$UNPACK_DIR/extension"

# RELEASE_CHECKLIST gates 8 and 11 cite this script as their evidence,
# and until 0.2.14 nothing ran it -- the SBOM was checked against the
# lockfiles by the suite and against the shipped artifact by nobody.
# This is the only point where the real artifact exists on disk.
echo "-- ruby scripts/verify_sbom_against_vsix.rb --"
ruby "$REPO_ROOT/scripts/verify_sbom_against_vsix.rb" "$UNPACK_DIR/extension"

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
