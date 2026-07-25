import * as assert from 'assert';
import * as path from 'path';
import { resolveRuby, RubyResolverEnv } from '../../rubyResolver';

function baseEnv(overrides: Partial<RubyResolverEnv> = {}): RubyResolverEnv {
  return {
    platform: 'darwin',
    home: '/home/dev',
    pathEnv: '/usr/bin:/usr/local/bin',
    workspaceRoot: '/workspace',
    existsSync: () => false,
    ...overrides
  };
}

describe('resolveRuby', () => {
  it('picks a mise shim when it exists, before ever checking asdf/rbenv/PATH', () => {
    const miseShim = path.join('/home/dev', '.local', 'share', 'mise', 'shims', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === miseShim });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, miseShim);
    const miseStep = result.steps.find((s) => s.strategy === 'mise');
    assert.strictEqual(miseStep?.matched, true);
  });

  it('falls through to asdf when mise is not present', () => {
    const asdfShim = path.join('/home/dev', '.asdf', 'shims', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === asdfShim });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, asdfShim);
  });

  it('falls through to rbenv when neither mise nor asdf is present', () => {
    const rbenvShim = path.join('/home/dev', '.rbenv', 'shims', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === rbenvShim });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, rbenvShim);
  });

  it('falls through to PATH when no version manager shim is present', () => {
    const pathRuby = path.join('/usr/local/bin', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === pathRuby });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, pathRuby);
  });

  it('checks PATH entries in order, picking the first that exists', () => {
    const first = path.join('/usr/bin', 'ruby');
    const second = path.join('/usr/local/bin', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === first || p === second });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, first);
  });

  it('falls back to the bare "ruby" command when nothing at all was found', () => {
    const env = baseEnv({ existsSync: () => false });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, 'ruby');
    assert.ok(result.steps.length > 0, 'still records a full diagnostic trail even when nothing matched');
    assert.ok(result.steps.every((s) => !s.matched));
  });

  it('checks Windows RubyInstaller locations only on win32', () => {
    const posixEnv = baseEnv({ platform: 'darwin', existsSync: () => false });
    const posixResult = resolveRuby(posixEnv);
    const rubyInstallerStep = posixResult.steps.find((s) => s.strategy === 'RubyInstaller');
    assert.strictEqual(rubyInstallerStep?.matched, false);
    assert.strictEqual(rubyInstallerStep?.reason, 'not running on Windows');
  });

  it('picks a Windows RubyInstaller location on win32 when nothing earlier matched', () => {
    const installerPath = path.join('C:\\Ruby33-x64', 'bin', 'ruby.exe');
    const env = baseEnv({
      platform: 'win32',
      home: undefined,
      pathEnv: '',
      existsSync: (p) => p === installerPath
    });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, installerPath);
  });

  it('never touches the real filesystem -- existsSync is fully injected', () => {
    let callCount = 0;
    const env = baseEnv({
      existsSync: () => {
        callCount += 1;
        return false;
      }
    });

    resolveRuby(env);

    assert.ok(callCount > 0, 'the resolver actually called the injected existsSync');
  });

  it('gracefully handles a missing HOME/USERPROFILE without throwing', () => {
    const env = baseEnv({ home: undefined });

    assert.doesNotThrow(() => resolveRuby(env));
  });

  it('records a full step-by-step trail usable for environment diagnostics', () => {
    const env = baseEnv();

    const result = resolveRuby(env);

    assert.ok(result.steps.some((s) => s.strategy === 'mise'));
    assert.ok(result.steps.some((s) => s.strategy === 'asdf'));
    assert.ok(result.steps.some((s) => s.strategy === 'rbenv'));
    assert.ok(result.steps.some((s) => s.strategy === 'chruby'));
    assert.ok(result.steps.some((s) => s.strategy === 'PATH'));
    assert.ok(result.steps.some((s) => s.strategy === 'RubyInstaller'));
    assert.ok(result.steps.every((s) => typeof s.reason === 'string' && s.reason.length > 0));
  });
});
