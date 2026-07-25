import * as assert from 'assert';
import * as path from 'path';
import { resolveServerConfig } from '../../serverConfig';

describe('resolveServerConfig', () => {
  const extensionRoot = '/ext/rslsp-vscode';

  it('defaults to the system ruby and the bundled core script', () => {
    const result = resolveServerConfig({ extensionRoot });

    assert.strictEqual(result.command, 'ruby');
    assert.strictEqual(result.args[0], path.join(extensionRoot, '..', 'core', 'bin', 'rslsp'));
    assert.strictEqual(result.args[1], '--stdio');
  });

  it('treats null and empty-string settings the same as unset', () => {
    const withNulls = resolveServerConfig({ rubyCommand: null, serverPath: null, extensionRoot });
    const withEmpty = resolveServerConfig({ rubyCommand: '', serverPath: '  ', extensionRoot });

    assert.deepStrictEqual(withNulls, withEmpty);
    assert.strictEqual(withNulls.command, 'ruby');
  });

  it('honors an explicit ruby command override', () => {
    const result = resolveServerConfig({ rubyCommand: '/opt/rubies/3.3/bin/ruby', extensionRoot });

    assert.strictEqual(result.command, '/opt/rubies/3.3/bin/ruby');
  });

  it('honors an explicit server path override', () => {
    const result = resolveServerConfig({ serverPath: '/custom/rslsp', extensionRoot });

    assert.deepStrictEqual(result.args, ['/custom/rslsp', '--stdio']);
  });

  it('prefers a Core bundled inside the extension own install directory over the monorepo-relative sibling path', () => {
    const bundled = path.join(extensionRoot, 'core', 'bin', 'rslsp');
    const result = resolveServerConfig({ extensionRoot, existsSync: (p) => p === bundled });

    assert.strictEqual(result.args[0], bundled);
  });

  it('falls back to the monorepo-relative sibling path when nothing is bundled (local F5 development)', () => {
    const result = resolveServerConfig({ extensionRoot, existsSync: () => false });

    assert.strictEqual(result.args[0], path.join(extensionRoot, '..', 'core', 'bin', 'rslsp'));
  });

  it('passes a path containing spaces and non-ASCII characters through unescaped -- spawn() takes args as an array, never a shell string', () => {
    const trickyRoot = '/Users/開発者/My RSLSP Extension';
    const result = resolveServerConfig({ extensionRoot: trickyRoot, existsSync: () => false });

    assert.strictEqual(result.args[0], path.join(trickyRoot, '..', 'core', 'bin', 'rslsp'));
    assert.ok(!result.args[0].includes('\\'), 'no manual shell-escaping was applied');
  });
});
