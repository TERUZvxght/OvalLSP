import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';

// The extension declares `untrustedWorkspaces.supported: "limited"` and
// tells the user, in its own manifest, that the Runtime Agent "only
// starts once the workspace is trusted". Until 0.2.4 it did not also
// declare `restrictedConfigurations`, and that omission made the promise
// false rather than merely incomplete.
//
// VS Code's own settings resolution (1.132.0,
// `workbench.desktop.main.js`) is:
//
//     restrictedProperties = supported === 'limited'
//       ? capabilities.untrustedWorkspaces.restrictedConfigurations
//       : undefined
//     shouldInclude = ... skipRestricted && property.restricted
//     skipRestricted = isUntrusted()
//
// With no `restrictedConfigurations`, no property is ever flagged
// `restricted`, so nothing is dropped in Restricted Mode and a
// workspace's own `.vscode/settings.json` supplies these values
// verbatim. `extension.ts` reads them and spawns the result during
// `activate`, before any trust check -- which was demonstrated against
// the published 0.2.3 artifact: opening an untrusted folder carrying a
// hostile settings file executed its script about two seconds later.
//
// This guard fails closed. Every configuration key must be either
// declared restricted or listed below as safe with a reason, so a
// setting added later cannot quietly become a new execution vector the
// way these four did.
describe('workspace trust: untrusted workspaces cannot choose what we execute', () => {
  const manifestPath = path.resolve(__dirname, '../../../package.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

  const untrusted = manifest.capabilities?.untrustedWorkspaces;
  const properties: Record<string, unknown> = manifest.contributes?.configuration?.properties ?? {};

  // Safe only because it cannot name anything to run: a boolean whose
  // only effect is to switch the extension off. Adding to this list is a
  // deliberate act that has to argue the key cannot influence execution.
  const SAFE_IN_UNTRUSTED = new Set(['ovallsp.enabled']);

  it('declares limited support, which is what makes restrictedConfigurations load-bearing', () => {
    assert.strictEqual(untrusted?.supported, 'limited');
  });

  it('restricts every setting that is not explicitly argued safe', () => {
    const restricted = new Set<string>(untrusted?.restrictedConfigurations ?? []);
    const missing = Object.keys(properties).filter(
      (key) => !SAFE_IN_UNTRUSTED.has(key) && !restricted.has(key)
    );

    assert.deepStrictEqual(
      missing,
      [],
      `these settings are honoured from a workspace's own .vscode/settings.json in an ` +
        `untrusted window: ${missing.join(', ')}. Add them to ` +
        `capabilities.untrustedWorkspaces.restrictedConfigurations, or to SAFE_IN_UNTRUSTED ` +
        `in this spec with a reason they cannot influence what is executed.`
    );
  });

  it('restricts the four keys that name a binary or a command, by name', () => {
    const restricted = new Set<string>(untrusted?.restrictedConfigurations ?? []);

    // Named individually as well as by the fail-closed rule above: these
    // are the ones reproduced as an execution vector, and a future edit
    // that widened SAFE_IN_UNTRUSTED would otherwise silently pass.
    for (const key of [
      'ovallsp.rubyExecutablePath',
      'ovallsp.ruby.command',
      'ovallsp.server.path',
      'ovallsp.observation.testCommand'
    ]) {
      assert.ok(restricted.has(key), `${key} must be restricted in untrusted workspaces`);
    }
  });

  it('lists nothing that is not a real setting, so the list cannot rot', () => {
    const declared = new Set(Object.keys(properties));
    const strays = (untrusted?.restrictedConfigurations ?? []).filter((key: string) => !declared.has(key));

    assert.deepStrictEqual(strays, [], `restrictedConfigurations names settings that do not exist: ${strays.join(', ')}`);
  });
});
