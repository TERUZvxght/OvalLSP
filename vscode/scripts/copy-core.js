#!/usr/bin/env node
// ADR-0004: "VSIXはCoreのsource/gem payloadを同梱する" -- copies the
// monorepo's core/ (source only, never spec/ or the monorepo's own
// tmp/) into vscode/core/, then vendors Core's own runtime gem
// dependencies (prism, rbs, and their own transitive runtime
// dependencies logger/tsort) into vscode/core/vendor/bundle so a
// packaged VSIX can launch Core without the end user ever running
// `bundle install` themselves or even having Bundler installed at all
// ("repository checkoutなしでVSIXからCoreを起動できる").
//
// Run via `npm run package` (see package.json) before `vsce package` --
// never run automatically by `npm run compile`/`npm test`, since it
// needs network access (to fetch gems) and a working `bundle` on PATH,
// neither of which every dev/CI environment running the unit tests has.
//
// ADR-0005: vendoring produces *native* extensions (prism.bundle,
// rbs_extension.bundle) specific to the Ruby engine/version/OS/CPU that
// ran `bundle install` here -- `core/bin/ovallsp` doesn't add them to
// $LOAD_PATH unconditionally any more; it checks them against
// PLATFORM_MANIFEST.json, written here, before doing so. See that file's
// own docs and ADR-0005 for why an unconditional load produced an
// undiagnosable cross-ABI crash instead of a clear error.
//
// Vendoring failure is a **hard** failure for this, the release-facing
// `npm run package` entry point -- ADR-0004's guarantee is "a packaged
// VSIX can launch Core with no further setup", and a VSIX silently
// missing its own vendored dependencies breaks that guarantee for every
// user whose Ruby doesn't already happen to have prism/rbs installed,
// with no indication anything is wrong until Core fails to start. A
// dependency-free build for local iteration (no network, no `bundle` on
// PATH) is still available, but only via the explicit
// `copy-core:allow-missing-vendor` script -- never the default path.

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

// Whether a missing/failed vendoring step is tolerated. Only ever true
// via the explicit `copy-core:allow-missing-vendor` script (see
// package.json) -- `npm run package`'s own `copy-core` step never sets
// this, so the release build path always hard-fails on a vendoring
// problem rather than silently shipping an incomplete VSIX.
const ALLOW_MISSING_VENDOR = process.argv.includes('--allow-missing-vendor');

// Only what bin/ovallsp actually needs at runtime -- never spec/ (test
// code, fixtures with their own throwaway Gemfiles that would confuse a
// packaged install), never tmp/ (local dev scratch state).
const INCLUDE = ['lib', 'bin', 'ovallsp.gemspec', 'Gemfile', 'Gemfile.lock'];

// The runtime gems a vendored install must actually contain -- both of
// ovallsp.gemspec's own direct runtime dependencies (prism, rbs) and
// their own transitive runtime dependencies (rbs depends on logger and
// tsort; see core/Gemfile.lock), since those are exactly as real a part
// of what ships and loads as the direct ones. Checked post-install so a
// `bundle install` that silently resolved to the wrong set (a stale
// lockfile, a corrupted local gem cache) fails loudly here rather than
// producing a VSIX that fails to `require "ovallsp"` only when an end
// user actually launches it.
const REQUIRED_VENDORED_GEMS = ['prism', 'rbs', 'logger', 'tsort'];

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

// The Ruby that will actually run `bundle install` below -- resolved via
// the same `bundle`/`ruby` PATH lookup the shelled-out commands
// themselves use, so the manifest describes the interpreter that really
// built these native extensions, not merely "whatever `ruby` happens to
// mean when this Node script runs" (the two are the same process'
// resolution in practice, but asking Ruby itself rather than assuming it
// keeps this correct if that ever changes).
function currentRubyIdentity() {
  const raw = execFileSync('ruby', ['-e', 'print [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM].join("|")'], {
    encoding: 'utf8'
  });
  const [engine, version, platform] = raw.split('|');
  const [major, minor] = version.split('.');
  return { engine, versionMajorMinor: `${major}.${minor}`, fullVersion: version, platform };
}

function writePlatformManifest() {
  const identity = currentRubyIdentity();
  const manifest = {
    rubyEngine: identity.engine,
    rubyVersionMajorMinor: identity.versionMajorMinor,
    rubyFullVersion: identity.fullVersion,
    rubyPlatform: identity.platform,
    generatedAt: new Date().toISOString()
  };
  fs.writeFileSync(path.join(CORE_STAGING, 'PLATFORM_MANIFEST.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `copy-core: recorded platform manifest (${manifest.rubyEngine} ${manifest.rubyFullVersion}, ` +
      `${manifest.rubyPlatform}) -- see ADR-0005`
  );
  return manifest;
}

// Vendors Core's runtime gem dependencies into CORE_STAGING/vendor/bundle.
// Throws on any failure; the caller decides whether that's tolerated
// (ALLOW_MISSING_VENDOR) or fatal (the default, release-facing path).
function vendorGemDependenciesIntoStaging() {
  // `bundle install --without development` is deprecated in favor of a
  // persisted local config -- `bundle config set --local without
  // development` writes CORE_STAGING/.bundle/config, then a plain
  // `bundle install` picks it up, which is the non-deprecated
  // equivalent and (unlike the CLI flag) survives being invoked again
  // (e.g. by the verification step below, or by hand while debugging a
  // packaging failure).
  execFileSync('bundle', ['config', 'set', '--local', 'path', 'vendor/bundle'], { cwd: CORE_STAGING, stdio: 'inherit' });
  execFileSync('bundle', ['config', 'set', '--local', 'without', 'development'], {
    cwd: CORE_STAGING,
    stdio: 'inherit'
  });
  execFileSync('bundle', ['install'], { cwd: CORE_STAGING, stdio: 'inherit' });
  console.log('copy-core: vendored runtime gem dependencies into staging');
}

// Confirms the staged vendor install actually contains what bin/ovallsp
// needs to run, and that the gems with native extensions actually built
// one -- catching a `bundle install` that "succeeded" (exit 0) but left
// a gem's C extension unbuilt (a missing system toolchain dependency,
// say), which would otherwise only surface as a runtime LoadError deep
// inside an end user's Core Server process.
function verifyVendoredGems() {
  const vendorRoot = path.join(CORE_STAGING, 'vendor', 'bundle');
  if (!fs.existsSync(vendorRoot)) {
    throw new Error(`copy-core: vendor/bundle does not exist at ${vendorRoot} after 'bundle install'`);
  }

  const gemDirs = fs.readdirSync(vendorRoot, { recursive: true }).map((entry) => entry.toString());
  const specDirs = gemDirs.filter((entry) => entry.endsWith('.gemspec') || /gems[\\/][^\\/]+$/.test(entry));

  for (const gemName of REQUIRED_VENDORED_GEMS) {
    const present = specDirs.some((entry) => path.basename(entry).startsWith(`${gemName}-`));
    if (!present) {
      throw new Error(
        `copy-core: expected '${gemName}' to be vendored under ${vendorRoot}, but no matching gem directory was found`
      );
    }
  }

  // Native-extension gems (prism, rbs' own rbs_extension) must have
  // actually built their shared object for this platform -- a `.bundle`
  // (macOS)/`.so` (Linux)/`.dll` (Windows) somewhere under that gem's own
  // directory tree. A gem directory existing with only its Ruby source
  // and no compiled extension is exactly the "succeeded but didn't
  // really work" shape this check exists to catch.
  const nativeExtensionMarkers = ['.bundle', '.so', '.dll'];
  const hasNativeExtension = (gemName) =>
    gemDirs.some(
      (entry) => path.basename(entry).startsWith(`${gemName}`) && nativeExtensionMarkers.some((ext) => entry.endsWith(ext))
    );

  for (const gemName of ['prism', 'rbs_extension']) {
    if (!hasNativeExtension(gemName)) {
      throw new Error(
        `copy-core: expected a compiled native extension for '${gemName}' under ${vendorRoot}, but none was found -- ` +
          "the gem's own C extension likely failed to build (check the 'bundle install' output above)"
      );
    }
  }

  console.log(`copy-core: verified ${REQUIRED_VENDORED_GEMS.join(', ')} are vendored with their native extensions`);
}

function commitStaging() {
  fs.rmSync(CORE_DEST, { recursive: true, force: true });
  fs.renameSync(CORE_STAGING, CORE_DEST);
  console.log(`copy-core: committed staged build to ${CORE_DEST}`);
}

try {
  copyCoreSourceIntoStaging();
  try {
    vendorGemDependenciesIntoStaging();
    writePlatformManifest();
    verifyVendoredGems();
  } catch (err) {
    if (!ALLOW_MISSING_VENDOR) {
      throw new Error(
        `copy-core: vendoring runtime gem dependencies failed (${err.message}). This is a hard failure for ` +
          "'npm run package' -- ADR-0004's guarantee is that a packaged VSIX needs no further setup, and shipping " +
          'one without its own vendored dependencies silently breaks that for any user whose Ruby lacks prism/rbs ' +
          "already. Use 'npm run copy-core:allow-missing-vendor' explicitly for a dependency-free development " +
          'build instead.'
      );
    }
    console.warn(
      `copy-core: could not vendor gem dependencies (${err.message}) -- proceeding anyway because ` +
        '--allow-missing-vendor was passed. The packaged Core will rely on the end user\'s own Ruby environment ' +
        'already having prism/rbs installed; this build must never be distributed as a release artifact.'
    );
  }
  commitStaging();
} finally {
  // Only ever removes leftovers from *this run*'s own staging directory
  // (pid-suffixed) -- never touches CORE_DEST itself, which #commitStaging
  // has already either populated or left untouched.
  fs.rmSync(CORE_STAGING, { recursive: true, force: true });
}
