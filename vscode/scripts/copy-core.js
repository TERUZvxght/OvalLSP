#!/usr/bin/env node
// ADR-0004: "VSIXはCoreのsource/gem payloadを同梱する" -- copies the
// monorepo's core/ (source only, never spec/ or the monorepo's own
// tmp/) into vscode/core/, then vendors Core's own runtime gem
// dependencies (prism, rbs) into vscode/core/vendor/bundle so a packaged
// VSIX can launch Core without the end user ever running `bundle
// install` themselves or even having Bundler installed at all
// ("repository checkoutなしでVSIXからCoreを起動できる").
//
// Run via `npm run package` (see package.json) before `vsce package` --
// never run automatically by `npm run compile`/`npm test`, since it
// needs network access (to fetch gems) and a working `bundle` on PATH,
// neither of which every dev/CI environment running the unit tests has.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const CORE_SOURCE = path.join(REPO_ROOT, 'core');
const CORE_DEST = path.join(__dirname, '..', 'core');
// Built in a staging directory and only ever `renameSync`d into place as
// `CORE_DEST` once the entire build (copy + vendor) succeeds -- found
// missing by an independent review of Task 020: the previous version
// copied files directly into `CORE_DEST` one at a time, so a process
// kill mid-copy (or, worse, mid-write of `core/bin/ovallsp` itself) could
// leave a *partially-written* `core/` behind that `serverConfig.ts`'s
// `existsSync(core/bin/ovallsp)` check would still treat as "the bundled
// Core is present and should be preferred", causing the extension to
// launch a broken server instead of falling back to the (working)
// monorepo-relative path. `fs.renameSync` between two siblings in the
// same directory is a same-filesystem rename, so the swap itself is
// atomic: `CORE_DEST` is always either the previous complete build or
// the new complete build, never a partial one.
const CORE_STAGING = `${CORE_DEST}.building-${process.pid}`;

// Only what bin/ovallsp actually needs at runtime -- never spec/ (test
// code, fixtures with their own throwaway Gemfiles that would confuse a
// packaged install), never tmp/ (local dev scratch state).
const INCLUDE = ['lib', 'bin', 'ovallsp.gemspec', 'Gemfile', 'Gemfile.lock'];

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dest, entry));
    }
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyCoreSourceIntoStaging() {
  if (!fs.existsSync(CORE_SOURCE)) {
    throw new Error(`copy-core: expected a sibling core/ directory at ${CORE_SOURCE}, but it doesn't exist`);
  }

  fs.rmSync(CORE_STAGING, { recursive: true, force: true });
  for (const entry of INCLUDE) {
    const src = path.join(CORE_SOURCE, entry);
    if (!fs.existsSync(src)) {
      continue; // Gemfile.lock, in particular, is optional in some checkouts.
    }
    copyRecursive(src, path.join(CORE_STAGING, entry));
  }
  console.log(`copy-core: staged ${INCLUDE.join(', ')} into ${CORE_STAGING}`);
}

// Best-effort: a packaging environment without network access or a
// working `bundle` still produces a usable (if degraded) VSIX -- bin/ovallsp
// only ever *adds* vendor/bundle to $LOAD_PATH when it exists (see its
// own bootstrap), so a missing vendor directory just means end users need
// prism/rbs already available in whatever Ruby resolveRuby picks for
// them, exactly the pre-Task-020 behavior. This must never make VSIX
// packaging itself fail outright.
function vendorGemDependenciesIntoStaging() {
  try {
    execFileSync('bundle', ['config', 'set', '--local', 'path', 'vendor/bundle'], { cwd: CORE_STAGING, stdio: 'inherit' });
    execFileSync('bundle', ['install', '--without', 'development'], { cwd: CORE_STAGING, stdio: 'inherit' });
    console.log('copy-core: vendored runtime gem dependencies into staging');
  } catch (err) {
    console.warn(
      `copy-core: could not vendor gem dependencies (${err.message}) -- packaged Core will rely on the ` +
        'end user\'s own Ruby environment already having prism/rbs installed'
    );
  }
}

function commitStaging() {
  fs.rmSync(CORE_DEST, { recursive: true, force: true });
  fs.renameSync(CORE_STAGING, CORE_DEST);
  console.log(`copy-core: committed staged build to ${CORE_DEST}`);
}

try {
  copyCoreSourceIntoStaging();
  vendorGemDependenciesIntoStaging();
  commitStaging();
} finally {
  // Only ever removes leftovers from *this run*'s own staging directory
  // (pid-suffixed) -- never touches CORE_DEST itself, which #commitStaging
  // has already either populated or left untouched.
  fs.rmSync(CORE_STAGING, { recursive: true, force: true });
}
