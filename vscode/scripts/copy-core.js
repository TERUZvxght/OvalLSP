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
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const { assertBundledVersionsAgree } = require('./version-pairing');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const CORE_SOURCE = path.join(REPO_ROOT, 'core');
const CORE_DEST = path.join(__dirname, '..', 'core');
const EXTENSION_PACKAGE_JSON = path.join(__dirname, '..', 'package.json');
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
const IDENTITY_PROBE = 'print [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM].join("|")';

function parseIdentity(raw) {
  const [engine, version, platform] = raw.split('|');
  const [major, minor] = version.split('.');
  return { engine, versionMajorMinor: `${major}.${minor}`, fullVersion: version, platform };
}

function currentRubyIdentity() {
  return parseIdentity(execFileSync('ruby', ['-e', IDENTITY_PROBE], { encoding: 'utf8' }));
}

// What `bundle exec ruby` itself resolves to, run from *inside* the
// staging directory bundle install just populated -- not necessarily the
// same interpreter `ruby` resolves to bare. Task 023.4's own requirement:
// Ruby identity "must be queried against the actual Ruby executable that
// will run, not assumed" -- `bundle install` above already ran under
// whatever `bundle` itself picked, and if that differs from the bare
// `ruby` this script otherwise queries (a stale `BUNDLE_GEMFILE`, a
// version-manager shim mismatch between the two commands, ...), the
// native extensions it just vendored were built for a *different*
// interpreter than the one `core/bin/ovallsp`'s own `$LOAD_PATH`
// manipulation will later run under.
function bundleRubyIdentity() {
  return parseIdentity(
    execFileSync('bundle', ['exec', 'ruby', '-e', IDENTITY_PROBE], { cwd: CORE_STAGING, encoding: 'utf8' })
  );
}

// Hard-fails packaging (never merely warns) if `ruby` and `bundle exec
// ruby` disagree on engine/version/platform -- Section 4's own
// requirement. Returns the agreed-upon identity so callers don't need a
// third `ruby -e` round-trip.
function verifyRubyAndBundleAgree() {
  const rubyIdentity = currentRubyIdentity();
  const bundleIdentity = bundleRubyIdentity();

  if (
    rubyIdentity.engine !== bundleIdentity.engine ||
    rubyIdentity.versionMajorMinor !== bundleIdentity.versionMajorMinor ||
    rubyIdentity.platform !== bundleIdentity.platform
  ) {
    throw new Error(
      `'ruby' resolves to ${rubyIdentity.engine} ${rubyIdentity.fullVersion} (${rubyIdentity.platform}), but ` +
        `'bundle exec ruby' resolves to ${bundleIdentity.engine} ${bundleIdentity.fullVersion} ` +
        `(${bundleIdentity.platform}) -- these must be the same interpreter, or the native extensions 'bundle ` +
        "install' just vendored won't match what 'ruby' itself will actually load them into at runtime. Check for " +
        'a stale BUNDLE_GEMFILE, or a version-manager shim mismatch between the two commands.'
    );
  }

  return rubyIdentity;
}

// The commit this VSIX was built from -- Task 023.2's build manifest
// needs *a* build identity distinguishable across otherwise-same-SemVer
// builds, and the git SHA is the one this monorepo already has without
// inventing a separate build-counter. `"unknown"` (never a thrown error)
// when there's no `.git` to ask (a tarball checkout, say) -- this is a
// diagnostic field, not something correctness depends on.
function currentGitCommit() {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO_ROOT, encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

// Matches `vsce package --target <target>`'s own naming
// (`darwin-arm64`, `linux-x64`, ...) so the manifest's recorded target
// and the actual packaging command's target can be compared directly by
// Task 023.5's packaging script.
function currentBuildTarget() {
  return `${process.platform}-${process.arch}`;
}

function extensionVersion() {
  return JSON.parse(fs.readFileSync(EXTENSION_PACKAGE_JSON, 'utf8')).version;
}

// core/lib/ovallsp/version.rb is a one-line `VERSION = "x.y.z"` constant
// -- read as text rather than shelling out to Ruby a second time (this
// script already has one `ruby -e` round-trip in `currentRubyIdentity`);
// simpler and avoids a dependency on Ruby understanding
// `require_relative` from an arbitrary cwd during packaging.
function coreVersionFromStaging() {
  const source = fs.readFileSync(path.join(CORE_STAGING, 'lib', 'ovallsp', 'version.rb'), 'utf8');
  const match = source.match(/VERSION\s*=\s*"([^"]+)"/);
  if (!match) {
    throw new Error(`copy-core: could not find VERSION constant in ${path.join(CORE_STAGING, 'lib', 'ovallsp', 'version.rb')}`);
  }
  return match[1];
}

// A single sha256 over every file's relative path and contents under
// `dir`, walked in a stable (sorted) order -- so the same payload always
// hashes the same way regardless of directory-listing order, and any
// change to file contents *or* the file set itself changes the hash.
// This is what Task 023.5's payload-corruption regression test (and the
// Extension's own runtime re-check, Task 023.2) compares against to
// detect a tampered or partially-written vendor payload.
function computeDirectorySha256(dir) {
  const hash = crypto.createHash('sha256');

  function walk(current, relativePrefix) {
    for (const entry of fs.readdirSync(current).sort()) {
      const fullPath = path.join(current, entry);
      const relativePath = path.join(relativePrefix, entry);
      const stat = fs.statSync(fullPath);
      if (stat.isDirectory()) {
        walk(fullPath, relativePath);
      } else if (stat.isFile()) {
        hash.update(relativePath.split(path.sep).join('/'));
        hash.update('\0');
        hash.update(fs.readFileSync(fullPath));
      }
    }
  }

  walk(dir, '');
  return hash.digest('hex');
}

function writePlatformManifest(identity) {
  const manifest = {
    rubyEngine: identity.engine,
    rubyVersionMajorMinor: identity.versionMajorMinor,
    rubyFullVersion: identity.fullVersion,
    rubyPlatform: identity.platform,
    generatedAt: new Date().toISOString(),
    // Task 023.2's build manifest -- additive fields alongside the
    // ADR-0005 ruby* fields above, which `Ovallsp::VendorCompatibility`
    // and `platformCompatibility.ts` keep reading unchanged.
    extensionVersion: extensionVersion(),
    coreVersion: coreVersionFromStaging(),
    buildCommit: currentGitCommit(),
    buildTarget: currentBuildTarget(),
    // Computed over the staged tree *before* this manifest file itself
    // exists within it (see call site in the packaging pipeline below) --
    // a manifest cannot include a hash of itself.
    payloadSha256: computeDirectorySha256(CORE_STAGING)
  };
  fs.writeFileSync(path.join(CORE_STAGING, 'PLATFORM_MANIFEST.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `copy-core: recorded platform manifest (${manifest.rubyEngine} ${manifest.rubyFullVersion}, ` +
      `${manifest.rubyPlatform}, extension ${manifest.extensionVersion}, core ${manifest.coreVersion}, ` +
      `target ${manifest.buildTarget}) -- see ADR-0005, ADR-0006, Task 023.2`
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

// Native-extension gems' own build process (`extconf.rb`/`make`) leaves
// build-log byproducts behind under `ext/` and `extensions/` --
// `mkmf.log`, `gem_make.out`, and `Makefile` -- none of which are ever
// loaded at runtime (only the compiled `.bundle`/`.so` itself is). Found
// reviewing package contents for Marketplace readiness (Task 023.6): all
// three files embed the absolute path of whatever machine ran `bundle
// install` (this machine's own username/home directory, verbatim, inside
// `mkmf.log` and `Makefile` in particular) -- exactly the "no local
// absolute paths/usernames in the package" requirement a packaged VSIX
// must satisfy before Marketplace publication. Removed unconditionally
// (never gated behind ALLOW_MISSING_VENDOR), since a release build must
// never ship these regardless of how vendoring itself was invoked.
const NATIVE_BUILD_ARTIFACT_NAMES = ['mkmf.log', 'gem_make.out', 'Makefile'];

function removeNativeBuildArtifacts(vendorRoot) {
  if (!fs.existsSync(vendorRoot)) {
    return;
  }
  let removed = 0;
  for (const entry of fs.readdirSync(vendorRoot, { recursive: true })) {
    if (!NATIVE_BUILD_ARTIFACT_NAMES.includes(path.basename(entry.toString()))) {
      continue;
    }
    const fullPath = path.join(vendorRoot, entry.toString());
    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()) {
      fs.rmSync(fullPath);
      removed += 1;
    }
  }
  console.log(`copy-core: removed ${removed} native-extension build-log artifact(s) (mkmf.log/gem_make.out/Makefile) -- these embed this build machine's own absolute paths and must never ship in the VSIX`);
}

// Bundler keeps the original downloaded `.gem` archives under
// `vendor/bundle/ruby/<abi>/cache/` after extracting them into `gems/`.
// Nothing ever loads them: `bin/ovallsp` only ever adds
// `<engine>/<abi>/gems/*/lib` to `$LOAD_PATH`, never `cache/`.
//
// They must be deleted *here*, from the staged tree, rather than merely
// excluded from the VSIX by `.vscodeignore` -- which is exactly what the
// previous version did, and exactly why every single v0.1.2/v0.1.3
// install showed a false "Payload hash mismatch ... may be corrupted"
// diagnostic on activation. `writePlatformManifest` hashes *this staged
// directory*, while `.vscodeignore` decided what actually shipped: two
// independent notions of "the payload" that silently disagreed by these
// four files, so the runtime rehash (over the installed, 811-file tree)
// could never match the manifest (recorded over the staged, 815-file
// tree) on any machine, ever. Found by directly rehashing a real
// installed extension and diffing the staged tree against the packaged
// one.
//
// The invariant this restores, and which `assertPackagedPayloadMatchesManifest`
// (see release.sh and the CI package-contents job) now verifies for real:
// **the staged `core/` tree is byte-for-byte what ships**, so hashing it
// is meaningful. Anything that must not ship gets deleted here, never
// filtered downstream.
function removeBundlerGemCache(vendorRoot) {
  if (!fs.existsSync(vendorRoot)) {
    return;
  }
  const cacheDirs = fs
    .readdirSync(vendorRoot, { recursive: true })
    .map((entry) => entry.toString())
    .filter((entry) => path.basename(entry) === 'cache')
    .map((entry) => path.join(vendorRoot, entry))
    .filter((full) => fs.existsSync(full) && fs.statSync(full).isDirectory());

  let removed = 0;
  for (const dir of cacheDirs) {
    removed += fs.readdirSync(dir).length;
    fs.rmSync(dir, { recursive: true, force: true });
  }
  console.log(
    `copy-core: removed ${removed} Bundler gem-cache archive(s) (vendor/bundle/**/cache/*.gem) -- never loaded at runtime, and keeping them staged would desync the payload hash from what actually ships`
  );
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

  verifyVendoredGemVersionsSatisfyGemspec(specDirs);

  console.log(`copy-core: verified ${REQUIRED_VENDORED_GEMS.join(', ')} are vendored with their native extensions`);
}

// Bundler's own dependency resolution already enforces
// `ovallsp.gemspec`'s `add_dependency` constraints when `bundle install`
// runs -- this check exists as an explicit, independently-verifiable
// invariant on top of that implicit guarantee (Section 4: "verify runtime
// dependency version/API requirements before requiring Core"), not
// because a successful `bundle install` could actually violate it in
// practice. A lockfile edited by hand, or a `bundle install` run against
// a stale `Gemfile.lock` with `--local`, are the realistic ways this
// could still drift; this makes packaging fail loudly instead of only
// discovering the drift as a runtime API mismatch inside an end user's
// Core Server process.
function parseGemspecDependencyConstraints() {
  const source = fs.readFileSync(path.join(CORE_STAGING, 'ovallsp.gemspec'), 'utf8');
  const constraints = {};
  for (const match of source.matchAll(/add_dependency\s+["']([^"']+)["'],\s*["']>=\s*([0-9.]+)["']/g)) {
    constraints[match[1]] = match[2];
  }
  return constraints;
}

function compareVersionStrings(a, b) {
  const partsA = a.split('.').map(Number);
  const partsB = b.split('.').map(Number);
  for (let i = 0; i < Math.max(partsA.length, partsB.length); i += 1) {
    const diff = (partsA[i] ?? 0) - (partsB[i] ?? 0);
    if (diff !== 0) {
      return diff;
    }
  }
  return 0;
}

function verifyVendoredGemVersionsSatisfyGemspec(specDirs) {
  const constraints = parseGemspecDependencyConstraints();
  const gemBasenames = specDirs.map((entry) => path.basename(entry));

  for (const [gemName, minimumVersion] of Object.entries(constraints)) {
    const match = gemBasenames.find((base) => base.startsWith(`${gemName}-`));
    if (!match) {
      continue; // already a hard failure above (REQUIRED_VENDORED_GEMS), nothing new to report here.
    }
    const actualVersion = match.slice(gemName.length + 1);
    if (compareVersionStrings(actualVersion, minimumVersion) < 0) {
      throw new Error(
        `copy-core: vendored '${gemName}' is version ${actualVersion}, but ovallsp.gemspec declares ` +
          `'>= ${minimumVersion}' as a runtime dependency requirement -- the vendored payload does not satisfy ` +
          "Core's own declared API requirement."
      );
    }
  }
}

function commitStaging() {
  fs.rmSync(CORE_DEST, { recursive: true, force: true });
  fs.renameSync(CORE_STAGING, CORE_DEST);
  console.log(`copy-core: committed staged build to ${CORE_DEST}`);
}

try {
  copyCoreSourceIntoStaging();
  // A precondition of the whole build, not a detail of manifest
  // writing, and deliberately outside the try below: inside it a
  // mismatch is reported as "vendoring runtime gem dependencies
  // failed" -- the wrong cause -- and --allow-missing-vendor
  // downgrades it to a warning and builds anyway. See ./version-pairing.js.
  assertBundledVersionsAgree({
    extensionVersion: extensionVersion(),
    coreVersion: coreVersionFromStaging()
  });
  try {
    vendorGemDependenciesIntoStaging();
    removeNativeBuildArtifacts(path.join(CORE_STAGING, 'vendor', 'bundle'));
    removeBundlerGemCache(path.join(CORE_STAGING, 'vendor', 'bundle'));
    const identity = verifyRubyAndBundleAgree();
    verifyVendoredGems();
    writePlatformManifest(identity);
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
