import * as assert from 'assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
  CLIENT_PROTOCOL_VERSION,
  ClientVersionInfo,
  OvallspServerInfo,
  compareVersionInfo,
  computeBundledPayloadSha256,
  gatherClientVersionInfo
} from '../../versionInfo';

function baseServer(overrides: Partial<OvallspServerInfo> = {}): OvallspServerInfo {
  return {
    coreVersion: '0.1.0',
    protocol: { current: 1, minimumClient: 1, maximumClient: 1, minimumServer: 1, maximumServer: 1 },
    ruby: { engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25' },
    build: { commit: 'abc123', target: 'darwin-arm64', payloadSha256: 'deadbeef' },
    ...overrides
  };
}

function bundledClient(overrides: Partial<ClientVersionInfo> = {}): ClientVersionInfo {
  return {
    extensionVersion: '0.1.0',
    classification: 'bundled',
    currentTarget: 'darwin-arm64',
    selectedCorePath: '/ext/core/bin/ovallsp',
    manifest: {
      rubyEngine: 'ruby',
      rubyVersionMajorMinor: '3.4',
      rubyPlatform: 'arm64-darwin25',
      extensionVersion: '0.1.0',
      coreVersion: '0.1.0',
      buildCommit: 'abc123',
      buildTarget: 'darwin-arm64',
      payloadSha256: 'deadbeef'
    },
    actualPayloadSha256: 'deadbeef',
    ...overrides
  };
}

describe('compareVersionInfo', () => {
  it('is compatible when everything matches', () => {
    const result = compareVersionInfo(bundledClient(), baseServer());
    assert.strictEqual(result.compatible, true);
    assert.deepStrictEqual(result.reasons, []);
  });

  it('is incompatible when Core reports no version info at all', () => {
    const result = compareVersionInfo(bundledClient(), undefined);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons[0].includes('did not report version information'));
  });

  it('detects a protocol range that does not intersect', () => {
    const server = baseServer({ protocol: { current: 2, minimumClient: 2, maximumClient: 2, minimumServer: 2, maximumServer: 2 } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Protocol version mismatch')));
  });

  it('detects a Core version mismatch against the bundled manifest', () => {
    const server = baseServer({ coreVersion: '0.2.0' });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Core version mismatch')));
  });

  it('detects a build commit mismatch against the bundled manifest', () => {
    const server = baseServer({ build: { commit: 'zzz999', target: 'darwin-arm64', payloadSha256: 'deadbeef' } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Build identity mismatch')));
  });

  it('detects a payload hash mismatch (corrupted/tampered bundled Core)', () => {
    const client = bundledClient({ actualPayloadSha256: 'corrupted-hash' });
    const result = compareVersionInfo(client, baseServer());
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Payload hash mismatch')));
  });

  it('detects a platform mismatch against the bundled manifest', () => {
    const client = bundledClient({ currentTarget: 'darwin-x64' });
    const result = compareVersionInfo(client, baseServer());
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Platform mismatch')));
  });

  it('detects a Ruby engine mismatch', () => {
    const server = baseServer({ ruby: { engine: 'jruby', version: '9.4.5', platform: 'arm64-darwin25' } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Ruby engine mismatch')));
  });

  // 0.2.1 changed what a Ruby the payload was not built for *means*:
  // `platformCompatibility` asks whether that Ruby carries prism and rbs
  // and, if it does, runs against them and says so in the Output channel.
  // This second check was not changed with it, and `extension.ts` shows a
  // red error toast for anything it calls incompatible -- so the toast
  // 0.2.1 removed was still shown, on every window, worded differently.
  //
  // A Ruby the Core is *running under* is by definition one it can run
  // under. The mismatch is worth saying; it is not an incompatibility,
  // and only one of these two functions gets to decide that.
  it('notes a Ruby major.minor difference without calling the Core incompatible', () => {
    const server = baseServer({ ruby: { engine: 'ruby', version: '3.3.9', platform: 'arm64-darwin25' } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, true);
    assert.ok(result.notes.some((n) => n.includes('Ruby version differs')));
  });

  // The engine is a different question: a Core running under JRuby is not
  // one this VSIX's payload can serve at all.
  it('still detects a Ruby engine mismatch as incompatible', () => {
    const server = baseServer({ ruby: { engine: 'jruby', version: '3.4.7', platform: 'arm64-darwin25' } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Ruby engine mismatch')));
  });

  it('does not flag a patch-version-only difference as a mismatch', () => {
    const server = baseServer({ ruby: { engine: 'ruby', version: '3.4.5', platform: 'arm64-darwin25' } });
    const result = compareVersionInfo(bundledClient(), server);
    assert.strictEqual(result.compatible, true);
  });

  it('never compares coreVersion/build/payload/platform/ruby against a bundled manifest for a custom Core path', () => {
    const client: ClientVersionInfo = {
      extensionVersion: '0.1.0',
      classification: 'custom',
      currentTarget: 'darwin-x64', // deliberately "wrong" vs. what a bundled manifest would say
      selectedCorePath: '/some/custom/ovallsp'
      // no manifest at all -- a custom path is never compared against one
    };
    const server = baseServer({ coreVersion: '9.9.9', ruby: { engine: 'jruby', version: '9.9.9', platform: 'anything' } });

    const result = compareVersionInfo(client, server);

    assert.strictEqual(result.compatible, true, 'only the protocol check should apply to a custom Core path');
  });

  it('still enforces the protocol check for a custom Core path (mode 8)', () => {
    const client: ClientVersionInfo = {
      extensionVersion: '0.1.0',
      classification: 'custom',
      currentTarget: 'darwin-arm64',
      selectedCorePath: '/some/custom/ovallsp'
    };
    const server = baseServer({ protocol: { current: 5, minimumClient: 5, maximumClient: 5, minimumServer: 5, maximumServer: 5 } });

    const result = compareVersionInfo(client, server);

    assert.strictEqual(result.compatible, false);
    assert.ok(result.reasons.some((r) => r.includes('Protocol version mismatch')));
    assert.ok(result.action?.includes('custom'));
  });

  it('always populates diagnostic details, even when compatible', () => {
    const result = compareVersionInfo(bundledClient(), baseServer());
    assert.strictEqual(result.details.extensionVersion, '0.1.0');
    assert.strictEqual(result.details.coreVersion, '0.1.0');
    assert.strictEqual(result.details.clientProtocolVersion, CLIENT_PROTOCOL_VERSION);
    assert.strictEqual(result.details.selectedCorePath, '/ext/core/bin/ovallsp');
    assert.strictEqual(result.details.classification, 'bundled');
  });
});

describe('computeBundledPayloadSha256', () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-payload-hash-'));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('produces the same hash regardless of directory-listing order', () => {
    fs.mkdirSync(path.join(dir, 'lib'));
    fs.writeFileSync(path.join(dir, 'lib', 'a.rb'), 'a');
    fs.writeFileSync(path.join(dir, 'lib', 'b.rb'), 'b');

    const first = computeBundledPayloadSha256(dir);
    const second = computeBundledPayloadSha256(dir);

    assert.strictEqual(first, second);
  });

  it('changes when file contents change', () => {
    fs.writeFileSync(path.join(dir, 'a.rb'), 'original');
    const before = computeBundledPayloadSha256(dir);

    fs.writeFileSync(path.join(dir, 'a.rb'), 'tampered');
    const after = computeBundledPayloadSha256(dir);

    assert.notStrictEqual(before, after);
  });

  it('ignores PLATFORM_MANIFEST.json itself at the root, since the manifest cannot hash itself', () => {
    fs.writeFileSync(path.join(dir, 'a.rb'), 'content');
    const withoutManifest = computeBundledPayloadSha256(dir);

    fs.writeFileSync(path.join(dir, 'PLATFORM_MANIFEST.json'), '{"anything": "goes"}');
    const withManifest = computeBundledPayloadSha256(dir);

    assert.strictEqual(withoutManifest, withManifest);
  });
});

describe('gatherClientVersionInfo', () => {
  let extensionRoot: string;

  beforeEach(() => {
    extensionRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-gather-'));
  });

  afterEach(() => {
    fs.rmSync(extensionRoot, { recursive: true, force: true });
  });

  it('reads no manifest and computes no hash for a monorepo dev checkout', () => {
    const info = gatherClientVersionInfo({
      extensionRoot,
      extensionVersion: '0.1.0',
      classification: 'monorepo',
      selectedCorePath: '/monorepo/core/bin/ovallsp',
      currentTarget: 'darwin-arm64'
    });

    assert.strictEqual(info.manifest, undefined);
    assert.strictEqual(info.actualPayloadSha256, undefined);
  });

  it('reads no manifest and computes no hash for a custom Core path', () => {
    const info = gatherClientVersionInfo({
      extensionRoot,
      extensionVersion: '0.1.0',
      classification: 'custom',
      selectedCorePath: '/custom/ovallsp',
      currentTarget: 'darwin-arm64'
    });

    assert.strictEqual(info.manifest, undefined);
    assert.strictEqual(info.actualPayloadSha256, undefined);
  });

  it('reads the manifest and computes the live payload hash for a bundled Core', () => {
    fs.mkdirSync(path.join(extensionRoot, 'core'), { recursive: true });
    fs.writeFileSync(path.join(extensionRoot, 'core', 'a.rb'), 'content');
    fs.writeFileSync(
      path.join(extensionRoot, 'core', 'PLATFORM_MANIFEST.json'),
      JSON.stringify({
        rubyEngine: 'ruby',
        rubyVersionMajorMinor: '3.4',
        rubyPlatform: 'arm64-darwin25',
        extensionVersion: '0.1.0',
        coreVersion: '0.1.0',
        buildCommit: 'abc123',
        buildTarget: 'darwin-arm64',
        payloadSha256: computeBundledPayloadSha256(path.join(extensionRoot, 'core'))
      })
    );

    const info = gatherClientVersionInfo({
      extensionRoot,
      extensionVersion: '0.1.0',
      classification: 'bundled',
      selectedCorePath: path.join(extensionRoot, 'core', 'bin', 'ovallsp'),
      currentTarget: 'darwin-arm64'
    });

    assert.ok(info.manifest);
    assert.strictEqual(info.actualPayloadSha256, info.manifest?.payloadSha256);
  });

  function writeBundledCore(root: string, coreVersion: string, extensionVer: string, commit: string): void {
    fs.mkdirSync(path.join(root, 'core'), { recursive: true });
    fs.writeFileSync(path.join(root, 'core', 'server.rb'), `# core ${coreVersion}`);
    fs.writeFileSync(
      path.join(root, 'core', 'PLATFORM_MANIFEST.json'),
      JSON.stringify({
        rubyEngine: 'ruby',
        rubyVersionMajorMinor: '3.4',
        rubyPlatform: 'arm64-darwin25',
        extensionVersion: extensionVer,
        coreVersion,
        buildCommit: commit,
        buildTarget: 'darwin-arm64',
        payloadSha256: computeBundledPayloadSha256(path.join(root, 'core'))
      })
    );
  }

  // Task 023.5, regression scenario B: a Marketplace update replaces the
  // Extension's *entire* install directory (VS Code's own mechanism, not
  // this codebase's -- ADR-0006). What this codebase is responsible for
  // is never caching stale build info across that swap: every call here
  // reads straight from disk, so "E1/C1 running, then the directory
  // becomes E2/C2" must be reflected on the very next call with no
  // leftover state from the old manifest.
  it('never mixes E1/C1 and E2/C2 -- a second gatherClientVersionInfo call after a simulated Marketplace update sees only the new build', () => {
    writeBundledCore(extensionRoot, '0.1.0', '0.1.0', 'commit-e1c1');
    const beforeUpdate = gatherClientVersionInfo({
      extensionRoot,
      extensionVersion: '0.1.0',
      classification: 'bundled',
      selectedCorePath: path.join(extensionRoot, 'core', 'bin', 'ovallsp'),
      currentTarget: 'darwin-arm64'
    });
    assert.strictEqual(beforeUpdate.manifest?.coreVersion, '0.1.0');

    // Simulate the Marketplace update: VS Code replaces the whole
    // directory tree in place (same extensionRoot, new contents).
    writeBundledCore(extensionRoot, '0.2.0', '0.2.0', 'commit-e2c2');
    const afterUpdate = gatherClientVersionInfo({
      extensionRoot,
      extensionVersion: '0.2.0',
      classification: 'bundled',
      selectedCorePath: path.join(extensionRoot, 'core', 'bin', 'ovallsp'),
      currentTarget: 'darwin-arm64'
    });

    assert.strictEqual(afterUpdate.manifest?.coreVersion, '0.2.0');
    assert.strictEqual(afterUpdate.manifest?.buildCommit, 'commit-e2c2');
    assert.notStrictEqual(
      afterUpdate.actualPayloadSha256,
      beforeUpdate.actualPayloadSha256,
      'the recomputed payload hash must reflect the new build, not the one cached from before the update'
    );

    // compareVersionInfo against a server that (correctly) reports the
    // new Core: compatible. Against a server that somehow still reports
    // the *old* Core (E2's Extension accidentally launched C1 -- exactly
    // what ADR-0006's guarantee #2/#4 rules out): flagged incompatible.
    const serverReportingNewCore = {
      coreVersion: '0.2.0',
      protocol: { current: 1, minimumClient: 1, maximumClient: 1, minimumServer: 1, maximumServer: 1 },
      ruby: { engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25' },
      build: { commit: 'commit-e2c2', target: 'darwin-arm64', payloadSha256: afterUpdate.manifest!.payloadSha256 }
    };
    assert.strictEqual(compareVersionInfo(afterUpdate, serverReportingNewCore).compatible, true);

    const serverStillReportingOldCore = {
      coreVersion: '0.1.0',
      protocol: { current: 1, minimumClient: 1, maximumClient: 1, minimumServer: 1, maximumServer: 1 },
      ruby: { engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25' },
      build: { commit: 'commit-e1c1', target: 'darwin-arm64', payloadSha256: beforeUpdate.manifest!.payloadSha256 }
    };
    const staleResult = compareVersionInfo(afterUpdate, serverStillReportingOldCore);
    assert.strictEqual(staleResult.compatible, false, 'a leftover C1 process running after an E2 update must be flagged');
    assert.ok(staleResult.reasons.some((r) => r.includes('Core version mismatch')));
  });
});
