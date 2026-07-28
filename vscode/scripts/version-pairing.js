#!/usr/bin/env node
// The version rule for the *bundled* Core payload.
//
// A bundled Core is built by this extension's own packaging step, so it
// is part of the extension build and carries the extension's version.
// Anything else -- a monorepo checkout a developer runs from, or a Core
// the user points `ovallsp.corePath` at -- is deliberately allowed to
// carry a different version and is judged only on protocol
// compatibility (ADR-0006). That is why this lives in the packaging
// script and is never consulted at runtime: at runtime a differing
// version is legitimate, at build time it is a mistake.
//
// It exists because the two drifted: the extension shipped as 0.1.5
// while `Ovallsp::VERSION` stayed 0.0.1, so Core's own initialize
// response and `OvalLSP: Show Version Information` both reported a
// version no release ever had. Nothing misbehaved -- compatibility is
// decided on the protocol range, not on these strings -- but a bug
// report quoting "Core 0.0.1" could not be mapped back to a release.
//
// Enforced mechanically rather than by procedure, because the case that
// forgets is precisely the common one: bumping the extension's version
// for a release that changed no Ruby code.

function assertBundledVersionsAgree({ extensionVersion, coreVersion }) {
  if (extensionVersion === coreVersion) {
    return;
  }
  throw new Error(
    `copy-core: the bundled Core's version (${coreVersion}, from core/lib/ovallsp/version.rb) does not match the ` +
      `extension's version (${extensionVersion}, from vscode/package.json). A bundled Core ships as part of this ` +
      'extension and must carry its version -- bump Ovallsp::VERSION to match, even when no Ruby code changed. ' +
      '(A monorepo or user-supplied Core is exempt: those are judged on protocol compatibility alone, see ADR-0006.)'
  );
}

module.exports = { assertBundledVersionsAgree };
