#!/usr/bin/env bash
# Verifies the packaged extension in a real VS Code, end to end.
#
# The capability suite (core/spec/e2e) proves Core answers. This proves
# the thing users install actually reaches that Core: VS Code loads the
# extension, activates it, and it spawns Core and the Runtime Agent for a
# real Rails workspace. Those are different claims, and only the second
# one would have caught a release that was on disk but not registered
# with VS Code -- which is a state this project has actually been in,
# looking identical to "the extension does nothing".
#
# Runs in a throwaway user-data-dir and extensions-dir, so it never
# touches the developer's own editor state, and can run while VS Code is
# open.
#
# Usage: verify-installed-extension.sh <path-to.vsix> <path-to-rails-workspace>
set -euo pipefail

VSIX="${1:?usage: verify-installed-extension.sh <vsix> <rails-workspace>}"
WORKSPACE="${2:?usage: verify-installed-extension.sh <vsix> <rails-workspace>}"

CODE_BIN="${CODE_BIN:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
[ -x "$CODE_BIN" ] || { echo "verify-installed-extension: no VS Code CLI at $CODE_BIN" >&2; exit 1; }

SANDBOX="$(mktemp -d -t ovallsp-verify)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/data" "$SANDBOX/ext"

run_code() { "$CODE_BIN" --user-data-dir "$SANDBOX/data" --extensions-dir "$SANDBOX/ext" "$@"; }

echo "verify-installed-extension: installing $(basename "$VSIX")"
run_code --install-extension "$VSIX" >/dev/null 2>&1

run_code --list-extensions | grep -q "^teruz.ovallsp$" || {
  echo "verify-installed-extension: FAILED -- VS Code does not list the extension as installed" >&2
  exit 1
}
echo "verify-installed-extension: VS Code lists it as installed"

# A folder, not just a file: the extension starts one client per
# workspace folder, so a bare file activates it but gives it nothing to
# do -- a distinction that has already cost a debugging session.
run_code --disable-workspace-trust --new-window "$WORKSPACE" >/dev/null 2>&1

echo "verify-installed-extension: waiting for Core and the Runtime Agent"
deadline=$(( $(date +%s) + 120 ))
core=""
agent=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  core="$(pgrep -f "$SANDBOX/ext/.*core-session.rb" || true)"
  agent="$(pgrep -f "$SANDBOX/ext/.*runtime_agent/boot.rb" || true)"
  [ -n "$core" ] && [ -n "$agent" ] && break
  sleep 2
done

activated=$(grep -l "_doActivateExtension teruz.ovallsp" "$SANDBOX"/data/logs/*/window*/exthost/exthost.log 2>/dev/null | head -1 || true)
[ -n "$activated" ] || { echo "verify-installed-extension: FAILED -- extension never activated" >&2; exit 1; }
echo "verify-installed-extension: extension activated"

[ -n "$core" ] || { echo "verify-installed-extension: FAILED -- no Core process was spawned" >&2; exit 1; }
echo "verify-installed-extension: Core running (pid $core)"

[ -n "$agent" ] || { echo "verify-installed-extension: FAILED -- no Runtime Agent was spawned" >&2; exit 1; }
echo "verify-installed-extension: Runtime Agent running (pid $agent)"

# Close the window and confirm the owner reclaims what it spawned --
# capability B3, but through VS Code's own shutdown rather than a
# synthetic one.
pkill -f "$SANDBOX/data" >/dev/null 2>&1 || true
sleep 8
leftover="$(pgrep -f "$SANDBOX/ext/" || true)"
[ -z "$leftover" ] || {
  echo "verify-installed-extension: FAILED -- processes survived VS Code exiting: $leftover" >&2
  exit 1
}
echo "verify-installed-extension: nothing survived VS Code exiting"
echo "verify-installed-extension: PASS"
