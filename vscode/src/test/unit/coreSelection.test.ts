import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import { execFileSync } from 'child_process';
import { resolveServerConfig } from '../../serverConfig';

// Regression coverage for a real ambiguity found reviewing packaging/release
// readiness: `serverConfig.ts#defaultServerPath` picks between the packaged
// Core (`<extensionRoot>/core/bin/ovallsp`) and the monorepo-relative one
// (`<extensionRoot>/../core/bin/ovallsp`) purely based on whether
// `vscode/core/` happens to exist on disk. A `vscode/core/` a previous
// `npm run package` left behind therefore silently changes which Core a
// *later* `npm run test:integration` run actually talks to -- this test
// exercises the real filesystem (no injected `existsSync`) to prove that
// ambiguity is actually resolved deterministically, and that
// `scripts/ensure-core-absent.js` (the fix: run before the source-Core
// integration suite) actually removes the stale artifact rather than being
// a script nothing calls.
describe('Core selection is deterministic, not dependent on packaging history', () => {
  const extensionRoot = path.resolve(__dirname, '..', '..', '..');
  const packagedCoreDir = path.join(extensionRoot, 'core');
  const packagedCoreBin = path.join(packagedCoreDir, 'bin', 'ovallsp');
  const ensureCoreAbsentScript = path.join(extensionRoot, 'scripts', 'ensure-core-absent.js');

  function removePackagedCore(): void {
    execFileSync('node', [ensureCoreAbsentScript]);
  }

  afterEach(() => {
    removePackagedCore();
  });

  it('resolves the monorepo-relative Core once ensure-core-absent.js has run, even if a packaged one existed moments ago', () => {
    // Simulate the exact scenario this test guards against: a prior
    // `npm run package` left a real (if minimal) `vscode/core/bin/ovallsp`
    // on disk.
    fs.mkdirSync(path.dirname(packagedCoreBin), { recursive: true });
    fs.writeFileSync(packagedCoreBin, '#!/usr/bin/env ruby\n');
    assert.ok(fs.existsSync(packagedCoreBin), 'test setup: expected the simulated packaged core to exist');

    removePackagedCore();

    const result = resolveServerConfig({ extensionRoot });
    assert.strictEqual(result.args[0], path.join(extensionRoot, '..', 'core', 'bin', 'ovallsp'));
  });

  it('resolves the packaged Core when vscode/core/bin/ovallsp genuinely exists', () => {
    fs.mkdirSync(path.dirname(packagedCoreBin), { recursive: true });
    fs.writeFileSync(packagedCoreBin, '#!/usr/bin/env ruby\n');

    const result = resolveServerConfig({ extensionRoot });
    assert.strictEqual(result.args[0], packagedCoreBin);
  });

  it('ensure-core-absent.js is idempotent -- running it when nothing exists is a harmless no-op', () => {
    removePackagedCore();
    assert.doesNotThrow(() => removePackagedCore());
    assert.strictEqual(fs.existsSync(packagedCoreDir), false);
  });
});
