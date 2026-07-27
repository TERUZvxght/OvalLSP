import * as assert from 'assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { checkBundledCoreCompatibility, queryRubyConfigPaths, RubyIdentity } from '../../platformCompatibility';

describe('checkBundledCoreCompatibility', () => {
  let extensionRoot: string;

  beforeEach(() => {
    extensionRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-platform-compat-'));
  });

  afterEach(() => {
    fs.rmSync(extensionRoot, { recursive: true, force: true });
  });

  function writeManifest(manifest: { rubyEngine: string; rubyVersionMajorMinor: string; rubyPlatform: string }): void {
    fs.mkdirSync(path.join(extensionRoot, 'core'), { recursive: true });
    fs.writeFileSync(path.join(extensionRoot, 'core', 'PLATFORM_MANIFEST.json'), JSON.stringify(manifest));
  }

  function stubIdentity(identity: RubyIdentity) {
    return async (_rubyCommand: string) => identity;
  }

  it('is compatible when there is no bundled manifest at all (a dev checkout)', async () => {
    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25'
    }));

    assert.strictEqual(result.compatible, true);
  });

  it('is compatible when the manifest matches the queried Ruby exactly', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25'
    }));

    assert.strictEqual(result.compatible, true);
  });

  it('compares only the major.minor version, ignoring the patch version', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.0', platform: 'arm64-darwin25'
    }));

    assert.strictEqual(result.compatible, true);
  });

  it('is incompatible when the platform differs, with an actionable reason', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.3.8', platform: 'x86_64-linux'
    }));

    assert.strictEqual(result.compatible, false);
    assert.ok(result.reason?.includes('ruby 3.4 (arm64-darwin25)'));
    assert.ok(result.reason?.includes('ruby 3.3 (x86_64-linux)'));
    assert.ok(result.reason?.includes('ovallsp.rubyExecutablePath'));
  });

  it('is incompatible when an Apple Silicon-built VSIX is run under a Rosetta-translated (x86_64) Ruby (Task 023.4)', async () => {
    // Apple Silicon's Homebrew installs under /opt/homebrew, Intel's under
    // /usr/local -- both remain valid, separately-installed Ruby builds on
    // the same Apple Silicon Mac (Rosetta 2 can still run the x86_64 one).
    // `rubyResolver.ts`'s own Homebrew strategy only ever *tries*
    // `/opt/homebrew/opt/ruby/bin/ruby` (Task 023.1's ADR-0006 note on why
    // that prefix specifically), but nothing stops a user from setting
    // `ovallsp.rubyExecutablePath` to an Intel Homebrew Ruby by hand -- this
    // check is the actual backstop that must reject that combination
    // outright, since RUBY_PLATFORM differs (`arm64-darwin25` vs.
    // `x86_64-darwin25`) even though RUBY_ENGINE/RUBY_VERSION could
    // otherwise coincidentally match.
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, '/usr/local/opt/ruby/bin/ruby', stubIdentity({
      engine: 'ruby', version: '3.4.7', platform: 'x86_64-darwin25'
    }));

    assert.strictEqual(result.compatible, false);
    assert.ok(result.reason?.includes('arm64-darwin25'));
    assert.ok(result.reason?.includes('x86_64-darwin25'));
  });

  it('is incompatible when the Ruby query itself fails (not on PATH, or does not understand -e)', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'nonexistent-ruby', async () => {
      throw new Error('spawn nonexistent-ruby ENOENT');
    });

    assert.strictEqual(result.compatible, false);
    assert.ok(result.reason?.includes('could not determine the version'));
  });

  it('actually spawns the real Ruby interpreter and reports it compatible with a manifest matching this machine', async function () {
    // The one test that exercises the real, non-injected queryRubyIdentity
    // implementation end to end, so the injectable seam above isn't hiding a
    // real process-spawning bug (wrong flag, wrong separator parsing, ...).
    this.timeout(10000);
    const identityScript = "print [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM].join('|')";
    const { execFileSync } = await import('child_process');
    const [engine, version, platform] = execFileSync('ruby', ['-e', identityScript], { encoding: 'utf8' }).split('|');
    const [major, minor] = version.split('.');

    writeManifest({ rubyEngine: engine, rubyVersionMajorMinor: `${major}.${minor}`, rubyPlatform: platform });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby');

    assert.strictEqual(result.compatible, true);
  });
});

describe('queryRubyConfigPaths', () => {
  // Task 023.8: this went through two failed designs (see the function's
  // own docs) before landing on querying both bindir and libdir so Core
  // can be spawned via the *real* ruby binary directly, bypassing any
  // version-manager shim -- proven here against this machine's own real
  // `ruby` resolution, not just synthetic paths.
  it('actually spawns the real Ruby interpreter and returns its own RbConfig bindir/libdir', async function () {
    this.timeout(10000);
    const { execFileSync } = await import('child_process');
    const [expectedBindir, expectedLibdir] = execFileSync(
      'ruby',
      ['-e', 'print [RbConfig::CONFIG["bindir"], RbConfig::CONFIG["libdir"]].join("|")'],
      { encoding: 'utf8' }
    )
      .trim()
      .split('|');

    const result = await queryRubyConfigPaths('ruby');

    assert.strictEqual(result.bindir, expectedBindir);
    assert.strictEqual(result.libdir, expectedLibdir);
    assert.ok(fs.existsSync(result.bindir), `expected ${result.bindir} to actually exist on disk`);
    assert.ok(fs.existsSync(result.libdir), `expected ${result.libdir} to actually exist on disk`);
  });

  it('rejects when the given command cannot be spawned at all', async () => {
    await assert.rejects(queryRubyConfigPaths('nonexistent-ruby-command'));
  });
});
