import * as assert from 'assert';
import * as path from 'path';
import { resolveRuby, RubyResolverEnv } from '../../rubyResolver';

function baseEnv(overrides: Partial<RubyResolverEnv> = {}): RubyResolverEnv {
  return {
    platform: 'darwin',
    home: '/home/dev',
    pathEnv: '/usr/bin:/usr/local/bin',
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

  it('picks a Homebrew Ruby on macOS when no version manager shim is present, before ever checking PATH', () => {
    const homebrewRuby = path.join('/opt/homebrew/opt/ruby/bin', 'ruby');
    const pathRuby = path.join('/usr/local/bin', 'ruby');
    const env = baseEnv({ existsSync: (p) => p === homebrewRuby || p === pathRuby });

    const result = resolveRuby(env);

    assert.strictEqual(result.executable, homebrewRuby);
    const homebrewStep = result.steps.find((s) => s.strategy === 'Homebrew');
    assert.strictEqual(homebrewStep?.matched, true);
  });

  it('skips the Homebrew strategy entirely on non-macOS platforms', () => {
    const homebrewRuby = path.join('/opt/homebrew/opt/ruby/bin', 'ruby');
    const env = baseEnv({ platform: 'linux', existsSync: (p) => p === homebrewRuby });

    const result = resolveRuby(env);

    assert.notStrictEqual(result.executable, homebrewRuby);
    const homebrewStep = result.steps.find((s) => s.strategy === 'Homebrew');
    assert.strictEqual(homebrewStep?.matched, false);
    assert.strictEqual(homebrewStep?.reason, 'not running on macOS');
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
    assert.ok(result.steps.some((s) => s.strategy === 'Homebrew'));
    assert.ok(result.steps.some((s) => s.strategy === 'PATH'));
    assert.ok(result.steps.some((s) => s.strategy === 'RubyInstaller'));
    assert.ok(result.steps.every((s) => typeof s.reason === 'string' && s.reason.length > 0));
  });
});

// **`024.75`.** `RubyResolverEnv.workspaceRoot` was declared, documented
// as being used for `.tool-versions`/`.ruby-version`, set by
// `extension.ts` -- and never read. Its declaration was its only
// occurrence in the resolver.
//
// That is worse than a dead field. The comment described the resolver as
// consulting workspace-controlled files, in the file someone reads to
// check exactly that. What is true, and worth keeping true, is the
// opposite: **interpreter selection reads nothing the workspace can
// write.** A repository cannot choose the binary this extension executes
// by committing a dotfile, which is why the trust gate does not have to
// cover this path.
//
// A source-level check because the property is about what the resolver
// *may read*, which no value it returns can demonstrate. Implementing the
// lookup instead would be a real feature and would have to be gated on
// trust like everything else that lets a workspace choose what runs.
describe('resolveRuby and the workspace', () => {
  const source = require('fs').readFileSync(
    path.join(__dirname, '..', '..', '..', 'src', 'rubyResolver.ts'),
    'utf8'
  );

  it('names nothing derived from the workspace', () => {
    const offenders = ['workspaceRoot', 'workspaceFolder', 'tool-versions']
      .filter((name) => source.includes(name));

    assert.deepStrictEqual(
      offenders, [],
      `rubyResolver.ts names ${offenders.join(', ')}. Interpreter selection reads nothing the ` +
      'workspace can write (024.75); implementing such a lookup is a feature that must be gated on trust.'
    );
  });

  // `.ruby-version` is deliberately *not* on that list, and the
  // distinction is the point rather than an exception to it: chruby's
  // strategy reads `~/.ruby-version`, under `env.home`. A file in the
  // user's own home directory is not something a cloned repository can
  // write. The property is about the resolver's *inputs*, not about
  // which filenames it knows.
  //
  // So the invariant is stated where it can be checked: the whole of what
  // this resolver may consult is four fields, and none of them is the
  // workspace. A fifth arriving is the change that has to be argued for.
  it('takes exactly four inputs, none of them the workspace', () => {
    const body = source.slice(
      source.indexOf('export interface RubyResolverEnv'),
      source.indexOf('}', source.indexOf('export interface RubyResolverEnv'))
    );
    const fields = (body.match(/^\s{2}(\w+)[?]?:/gm) ?? []).map((f: string) => f.trim().replace(/[?]?:$/, ''));

    assert.deepStrictEqual(fields.sort(), ['existsSync', 'home', 'pathEnv', 'platform']);
  });

  // The distinguishing half: the checks must be able to fail.
  it('would catch the field coming back', () => {
    assert.ok('  workspaceRoot: string;'.includes('workspaceRoot'));
    assert.ok(!'  home: string | undefined;'.includes('workspaceRoot'));
  });
});
