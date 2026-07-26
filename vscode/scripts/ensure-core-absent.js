#!/usr/bin/env node
// Removes vscode/core/ if it exists -- a plain `rm -rf` in an npm script
// isn't portable to Windows without a shell that understands it, and
// `fs.rmSync` is.
//
// Run before the *source-Core* integration suite (`npm run
// test:integration`), so a `vscode/core/` a previous `npm run package`
// left on disk can never silently make that run resolve
// `serverConfig.ts#defaultServerPath`'s *packaged*-Core branch instead of
// the monorepo-relative one it's meant to exercise -- found reviewing
// packaging/release readiness: whichever branch `defaultServerPath` picks
// depends entirely on whether this directory happens to exist, so which
// Core an integration run actually talks to silently depended on
// whatever a developer's machine had done to it most recently, not on
// which npm script they typed.

const fs = require('fs');
const path = require('path');

const CORE_DEST = path.join(__dirname, '..', 'core');

if (fs.existsSync(CORE_DEST)) {
  fs.rmSync(CORE_DEST, { recursive: true, force: true });
  console.log(`ensure-core-absent: removed stale ${CORE_DEST} so this run exercises the monorepo-relative Core`);
} else {
  console.log(`ensure-core-absent: ${CORE_DEST} does not exist -- already exercising the monorepo-relative Core`);
}
