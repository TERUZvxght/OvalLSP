#!/usr/bin/env node
// Verifies that a packaged VSIX's own `core/PLATFORM_MANIFEST.json`
// payload hash matches a rehash of that same VSIX's `core/` directory --
// i.e. exactly the check `versionInfo.ts` performs at activation on the
// installed extension, run here at build time instead of on a user's
// machine after publishing.
//
// This exists because that runtime check failed for every single
// v0.1.2/v0.1.3 install ("Payload hash mismatch ... may be corrupted"),
// and nothing in the build pipeline could have caught it: copy-core.js
// verified only the *staged* tree (which was self-consistent), while
// `.vscodeignore` independently stripped four already-hashed
// `vendor/bundle/**/cache/*.gem` archives on the way into the VSIX. Two
// sources of truth for "the payload", no check that they agreed.
//
// Deliberately hashes the *unpacked VSIX*, never the staging directory:
// the whole class of bug here is "what we hashed" drifting from "what we
// shipped", so this must measure the shipped artifact or it re-creates
// the same blind spot.
//
// Usage: node scripts/verify-packaged-payload-hash.js <unpacked-vsix>/extension

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const extensionDir = process.argv[2];
if (!extensionDir) {
  console.error('usage: verify-packaged-payload-hash.js <unpacked-vsix-extension-dir>');
  process.exit(1);
}

const coreDir = path.join(extensionDir, 'core');
const manifestPath = path.join(coreDir, 'PLATFORM_MANIFEST.json');

if (!fs.existsSync(manifestPath)) {
  console.error(`verify-payload-hash: FAILED: no ${manifestPath} -- was this VSIX packaged with a vendored Core?`);
  process.exit(1);
}

// Same algorithm as copy-core.js's computeDirectorySha256 and
// versionInfo.ts's computeBundledPayloadSha256, skipping the manifest
// itself (it cannot contain a hash of itself).
function computePayloadSha256(dir) {
  const hash = crypto.createHash('sha256');
  function walk(current, relativePrefix) {
    for (const entry of fs.readdirSync(current).sort()) {
      if (relativePrefix === '' && entry === 'PLATFORM_MANIFEST.json') {
        continue;
      }
      const fullPath = path.join(current, entry);
      const relativePath = relativePrefix === '' ? entry : path.join(relativePrefix, entry);
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

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const actual = computePayloadSha256(coreDir);

if (manifest.payloadSha256 !== actual) {
  console.error('verify-payload-hash: FAILED: the packaged VSIX does not match its own recorded payload hash.');
  console.error(`  manifest.payloadSha256: ${manifest.payloadSha256}`);
  console.error(`  rehash of packaged core/: ${actual}`);
  console.error('');
  console.error('Every install of this build would show a false "Payload hash mismatch -- it may be');
  console.error('corrupted" diagnostic at activation. Something staged into core/ by copy-core.js is');
  console.error('not reaching the VSIX (check vscode/.vscodeignore for a core/** rule), or core/ was');
  console.error('rebuilt after its manifest was written.');
  process.exit(1);
}

const fileCount = (function count(dir) {
  return fs.readdirSync(dir).reduce((n, entry) => {
    const full = path.join(dir, entry);
    return n + (fs.statSync(full).isDirectory() ? count(full) : 1);
  }, 0);
})(coreDir);

console.log(`verify-payload-hash: PASS (packaged core/ = ${fileCount} files, sha256 ${actual})`);
