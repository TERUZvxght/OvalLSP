import * as assert from 'assert';

// A build script, not a TS module -- required the same way copy-core.js
// requires it.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { assertBundledVersionsAgree } = require('../../../scripts/version-pairing') as {
  assertBundledVersionsAgree: (input: { extensionVersion: string; coreVersion: string }) => void;
};

describe('bundled Core version pairing', () => {
  // The rule this enforces: a *bundled* Core is part of the extension
  // build, so its gem version has to be the extension's version. Nothing
  // enforced that, and the two drifted -- the extension shipped as 0.1.5
  // while Core kept reporting 0.0.1 in its own initialize response and in
  // `OvalLSP: Show Version Information`. Nothing misbehaved (compatibility
  // is decided on the protocol range) but a bug report quoting "Core
  // 0.0.1" cannot be mapped back to a release.
  //
  // Enforced at package time rather than by asking a human to remember:
  // an extension-only version bump is exactly the case that forgets, and
  // it is the one that has to fail loudly.
  it('rejects a build whose bundled Core version differs from the extension version', () => {
    assert.throws(
      () => assertBundledVersionsAgree({ extensionVersion: '0.1.6', coreVersion: '0.1.5' }),
      (error: Error) => /0\.1\.6/.test(error.message) && /0\.1\.5/.test(error.message)
    );
  });

  it('accepts a build where they agree', () => {
    assert.doesNotThrow(() => assertBundledVersionsAgree({ extensionVersion: '0.1.5', coreVersion: '0.1.5' }));
  });

  // A pure function nothing calls enforces nothing, and `copy-core.js`
  // cannot be executed here (it shells out to `bundle` and needs the
  // network). So the wiring is pinned structurally, and specifically
  // *before* the manifest is written: a manifest recording a mismatched
  // pair is exactly the artifact this exists to prevent.
  it('is wired into packaging before the platform manifest is written', () => {
    const source = require('fs').readFileSync(
      require('path').resolve(__dirname, '../../../scripts/copy-core.js'), 'utf8'
    ) as string;
    const call = source.indexOf('assertBundledVersionsAgree(bundledVersions)');
    // The write itself, not the several comments that name the file.
    const manifestWrite = source.indexOf("fs.writeFileSync(path.join(CORE_STAGING, 'PLATFORM_MANIFEST.json')");

    assert.ok(call >= 0, 'copy-core.js must call the pairing check');
    assert.ok(manifestWrite >= 0, 'expected copy-core.js to still write the platform manifest');
    assert.ok(call < manifestWrite, 'the pairing check must run before the manifest is written');
  });

  // The paired half of the rule: this check exists only for the bundled
  // payload. A Core the user points at themselves, or the monorepo
  // checkout a developer runs from, is deliberately allowed to differ and
  // is judged on protocol compatibility alone (ADR-0006). That is why the
  // check lives in the packaging script and not in the runtime path.
  it('is not applied to a Core the extension did not build', () => {
    assert.strictEqual(typeof assertBundledVersionsAgree, 'function');
    const source = require('fs').readFileSync(
      require('path').resolve(__dirname, '../../../src/extension.ts'), 'utf8'
    );
    assert.ok(
      !source.includes('assertBundledVersionsAgree'),
      'the pairing rule must not be enforced at runtime, where a custom Core is legitimate'
    );
  });
});
