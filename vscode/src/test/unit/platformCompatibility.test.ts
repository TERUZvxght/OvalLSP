import * as assert from 'assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { checkBundledCoreCompatibility, queryRubyConfigPaths, RubyIdentity } from '../../platformCompatibility';
import { installExecutableFixture } from '../support/executableFixture';

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

  it('forwards cwd through to the identity query -- rbenv/asdf/mise shims pick the active Ruby version based on cwd, not just the command string', async () => {
    // Task 023.8 (second re-review round): omitting `cwd` here silently
    // queries whatever Ruby the *extension host's own* ambient working
    // directory resolves to via a version-manager shim, not the
    // workspace folder actually being checked -- reproduced directly
    // against a real rbenv shim, where the same shim path returns a
    // different Ruby version depending solely on which directory it's
    // invoked from.
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });
    let receivedCwd: string | undefined;
    const queryIdentity = async (_rubyCommand: string, cwd?: string) => {
      receivedCwd = cwd;
      return { engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25' };
    };

    await checkBundledCoreCompatibility(extensionRoot, 'ruby', queryIdentity, '/workspace/project-a');

    assert.strictEqual(receivedCwd, '/workspace/project-a');
  });

  // A Ruby the bundled payload was not built for is not automatically a
  // Ruby OvalLSP cannot run under. The payload is a convenience -- the
  // Core needs `prism` and `rbs`, and a developer whose own Ruby has them
  // is exactly the "may still work if the user's own Ruby environment has
  // prism/rbs installed separately" case `SUPPORT_MATRIX` already
  // describes for every non-build combination.
  //
  // It became worth distinguishing when 0.2.1 declared Ruby 4.0 best
  // effort: the suite is green there, so telling that user their
  // interpreter is "incompatible" -- in a red toast -- describes the
  // payload rather than their situation.
  it('is compatible on a Ruby the payload was not built for, when that Ruby has prism and rbs itself', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(
      extensionRoot, 'ruby',
      stubIdentity({ engine: 'ruby', version: '4.0.6', platform: 'arm64-darwin27' }),
      undefined,
      async () => true
    );

    assert.strictEqual(result.compatible, true);
    assert.ok(result.note && result.note.includes('4.0'), `expected a note naming the Ruby, got ${result.note}`);
  });

  // Engine is not gated here, and the direction matters: 0.2.3 briefly
  // gated it to make this function agree with `compareVersionInfo`, and
  // that turned one red toast into two -- this one advising
  // `gem install prism rbs` without having asked, on a Core that already
  // has them. Reverted; the split is 024.65 and belongs to whichever
  // decider owns the *notification*.
  //
  // Both halves asserted, because `compatible: true` alone would pass on
  // a build that skips the probe and assumes.
  it('probes a different engine rather than refusing it unasked', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });
    let asked = false;

    const result = await checkBundledCoreCompatibility(
      extensionRoot, 'jruby',
      stubIdentity({ engine: 'jruby', version: '3.4.7', platform: 'universal-java-21' }),
      undefined,
      async () => { asked = true; return true; }
    );

    assert.strictEqual(result.compatible, true);
    assert.strictEqual(asked, true, 'an engine difference is asked about, not assumed');
  });

  it('is incompatible on a Ruby that has neither the payload nor its own prism and rbs', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(
      extensionRoot, 'ruby',
      stubIdentity({ engine: 'ruby', version: '4.0.6', platform: 'arm64-darwin27' }),
      undefined,
      async () => false
    );

    assert.strictEqual(result.compatible, false);
    assert.ok(result.reason && result.reason.includes('gem install prism rbs'));
  });

  it('does not spend a process asking about the runtime when the payload already matches', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });
    let asked = false;

    const result = await checkBundledCoreCompatibility(
      extensionRoot, 'ruby',
      stubIdentity({ engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25' }),
      undefined,
      async () => { asked = true; return true; }
    );

    assert.strictEqual(result.compatible, true);
    assert.strictEqual(asked, false);
  });

  it('is compatible when there is no bundled manifest at all (a dev checkout)', async () => {
    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25'
    }), undefined, async () => false);

    assert.strictEqual(result.compatible, true);
  });

  it('is compatible when the manifest matches the queried Ruby exactly', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.7', platform: 'arm64-darwin25'
    }), undefined, async () => false);

    assert.strictEqual(result.compatible, true);
  });

  it('compares only the major.minor version, ignoring the patch version', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.4.0', platform: 'arm64-darwin25'
    }), undefined, async () => false);

    assert.strictEqual(result.compatible, true);
  });

  // Each of these passes a probe that says the interpreter has no prism
  // or rbs of its own -- otherwise they would be asserting about
  // whatever gems happen to be installed on the machine running the
  // suite, and on a developer's own machine that is usually "yes",
  // which is the *other* branch.
  it('is incompatible when the platform differs, with an actionable reason', async () => {
    writeManifest({ rubyEngine: 'ruby', rubyVersionMajorMinor: '3.4', rubyPlatform: 'arm64-darwin25' });

    const result = await checkBundledCoreCompatibility(extensionRoot, 'ruby', stubIdentity({
      engine: 'ruby', version: '3.3.8', platform: 'x86_64-linux'
    }), undefined, async () => false);

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

  it('actually runs the query in the given cwd, not the caller\'s own ambient working directory', async function () {
    // See `installExecutableFixture`: the fixture below is a file this
    // machine has never executed, and the first run of one is the slow
    // one. This test timed out at mocha's 2 s default while passing in
    // 186 ms when run alone.
    this.timeout(30000);
    // Task 023.8 (second re-review round): this is the regression the
    // previous version of this test suite couldn't have caught -- it
    // only asserted on stdout parsing, never on *which directory* the
    // query itself ran in. A real rbenv/asdf/mise shim resolves its
    // active Ruby version from cwd; querying from the wrong directory
    // silently returns a different (wrong) interpreter's bindir/libdir
    // entirely. Proven here with a fake "ruby" that only ever reports
    // its own actual working directory -- no real Ruby version manager
    // needed for this assertion to be meaningful or portable to CI.
    const fakeRubyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-fake-ruby-'));
    const fakeRubyPath = installExecutableFixture(
      path.join(fakeRubyDir, 'fake-ruby.sh'),
      '#!/bin/sh\necho "$(pwd)|$(pwd)"\n'
    );

    const targetCwd = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-target-cwd-'));
    try {
      const result = await queryRubyConfigPaths(fakeRubyPath, targetCwd);

      // Resolve both sides through realpath -- macOS' /tmp is itself a
      // symlink to /private/tmp, and `pwd` inside the fake script
      // reports the resolved path, not necessarily byte-identical to
      // the un-resolved mkdtempSync result.
      assert.strictEqual(fs.realpathSync(result.bindir), fs.realpathSync(targetCwd));
    } finally {
      fs.rmSync(fakeRubyDir, { recursive: true, force: true });
      fs.rmSync(targetCwd, { recursive: true, force: true });
    }
  });
});
