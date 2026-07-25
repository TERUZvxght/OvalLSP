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

// Only what bin/rslsp actually needs at runtime -- never spec/ (test
// code, fixtures with their own throwaway Gemfiles that would confuse a
// packaged install), never tmp/ (local dev scratch state).
const INCLUDE = ['lib', 'bin', 'rslsp.gemspec', 'Gemfile', 'Gemfile.lock'];

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

function copyCoreSource() {
  if (!fs.existsSync(CORE_SOURCE)) {
    throw new Error(`copy-core: expected a sibling core/ directory at ${CORE_SOURCE}, but it doesn't exist`);
  }

  fs.rmSync(CORE_DEST, { recursive: true, force: true });
  for (const entry of INCLUDE) {
    const src = path.join(CORE_SOURCE, entry);
    if (!fs.existsSync(src)) {
      continue; // Gemfile.lock, in particular, is optional in some checkouts.
    }
    copyRecursive(src, path.join(CORE_DEST, entry));
  }
  console.log(`copy-core: copied ${INCLUDE.join(', ')} into ${CORE_DEST}`);
}

// Best-effort: a packaging environment without network access or a
// working `bundle` still produces a usable (if degraded) VSIX -- bin/rslsp
// only ever *adds* vendor/bundle to $LOAD_PATH when it exists (see its
// own bootstrap), so a missing vendor directory just means end users need
// prism/rbs already available in whatever Ruby resolveRuby picks for
// them, exactly the pre-Task-020 behavior. This must never make VSIX
// packaging itself fail outright.
function vendorGemDependencies() {
  try {
    execFileSync('bundle', ['config', 'set', '--local', 'path', 'vendor/bundle'], { cwd: CORE_DEST, stdio: 'inherit' });
    execFileSync('bundle', ['install', '--without', 'development'], { cwd: CORE_DEST, stdio: 'inherit' });
    console.log('copy-core: vendored runtime gem dependencies into core/vendor/bundle');
  } catch (err) {
    console.warn(
      `copy-core: could not vendor gem dependencies (${err.message}) -- packaged Core will rely on the ` +
        'end user\'s own Ruby environment already having prism/rbs installed'
    );
  }
}

copyCoreSource();
vendorGemDependencies();
