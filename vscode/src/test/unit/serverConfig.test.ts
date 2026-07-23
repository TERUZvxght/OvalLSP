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
});
