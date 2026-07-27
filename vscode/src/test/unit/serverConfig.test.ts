import * as assert from 'assert';
import * as path from 'path';
import { resolveServerConfig, deriveNativeExtensionLibraryPath } from '../../serverConfig';

describe('resolveServerConfig', () => {
  const extensionRoot = '/ext/ovallsp-vscode';

  it('defaults to the system ruby and the bundled core script', () => {
    const result = resolveServerConfig({ extensionRoot });

    assert.strictEqual(result.command, 'ruby');
    assert.strictEqual(result.args[0], path.join(extensionRoot, '..', 'core', 'bin', 'ovallsp'));
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
    const result = resolveServerConfig({ serverPath: '/custom/ovallsp', extensionRoot });

    assert.deepStrictEqual(result.args, ['/custom/ovallsp', '--stdio']);
  });

  it('prefers a Core bundled inside the extension own install directory over the monorepo-relative sibling path', () => {
    const bundled = path.join(extensionRoot, 'core', 'bin', 'ovallsp');
    const result = resolveServerConfig({ extensionRoot, existsSync: (p) => p === bundled });

    assert.strictEqual(result.args[0], bundled);
  });

  it('falls back to the monorepo-relative sibling path when nothing is bundled (local F5 development)', () => {
    const result = resolveServerConfig({ extensionRoot, existsSync: () => false });

    assert.strictEqual(result.args[0], path.join(extensionRoot, '..', 'core', 'bin', 'ovallsp'));
  });

  it('passes a path containing spaces and non-ASCII characters through unescaped -- spawn() takes args as an array, never a shell string', () => {
    const trickyRoot = '/Users/開発者/My OvalLSP Extension';
    const result = resolveServerConfig({ extensionRoot: trickyRoot, existsSync: () => false });

    assert.strictEqual(result.args[0], path.join(trickyRoot, '..', 'core', 'bin', 'ovallsp'));
    assert.ok(!result.args[0].includes('\\'), 'no manual shell-escaping was applied');
  });
});

describe('deriveNativeExtensionLibraryPath', () => {
  // Task 023.8: reproduced directly on this project's own dev machine --
  // a prism.bundle vendored under one rbenv Ruby 3.4.x raises
  // `LoadError: linked to incompatible .../libruby.3.4.dylib` when
  // required under a *different* Ruby 3.4.x install (a different
  // absolute path, same major.minor -- so ADR-0005's own compatibility
  // check would call them compatible). Setting DYLD_LIBRARY_PATH to the
  // actually-running Ruby's own lib/ directory (exactly what this
  // function derives) was verified to fix that exact reproduction.
  it('derives the sibling lib/ directory from an absolute rbenv-style ruby path, on darwin', () => {
    const result = deriveNativeExtensionLibraryPath('/Users/dev/.rbenv/versions/3.4.7/bin/ruby', 'darwin');

    assert.strictEqual(result, path.join('/Users/dev/.rbenv/versions/3.4.7', 'lib'));
  });

  it('derives the sibling lib/ directory from an absolute Homebrew-style ruby path, on darwin', () => {
    const result = deriveNativeExtensionLibraryPath('/opt/homebrew/opt/ruby/bin/ruby', 'darwin');

    assert.strictEqual(result, path.join('/opt/homebrew/opt/ruby', 'lib'));
  });

  it('returns undefined on any platform other than darwin -- this Preview only targets darwin-arm64', () => {
    assert.strictEqual(deriveNativeExtensionLibraryPath('/Users/dev/.rbenv/versions/3.4.7/bin/ruby', 'linux'), undefined);
    assert.strictEqual(deriveNativeExtensionLibraryPath('/Users/dev/.rbenv/versions/3.4.7/bin/ruby', 'win32'), undefined);
  });

  it('returns undefined for a bare PATH-resolved command with no absolute path to derive a sibling lib/ from', () => {
    assert.strictEqual(deriveNativeExtensionLibraryPath('ruby', 'darwin'), undefined);
  });
});
