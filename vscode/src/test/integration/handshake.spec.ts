import * as assert from 'assert';
import * as vscode from 'vscode';

import type { OvallspApi } from '../../extension';

// `024.64`. Three review rounds in a row found the start-up handshake's
// call site in `extension.ts` deletable with the whole unit suite green,
// and each countermeasure moved code *out of* that file. That pins the
// code and never the wiring: nothing in `src/test/unit` can import
// `extension.ts`, so the question "is this line still called, and on
// which branch" was unaskable there. Round 37 moved the call inside
// `if (!diagnostic.compatible)` -- restoring `024.49`'s symptom exactly,
// a Ruby the payload was not built for getting no Output-channel note --
// and 186 tests passed.
//
// This suite runs `activate()` for real, and runs in CI as of `024.69`.
// So the assertion the three countermeasures could not make is available
// here: the handshake happened for a folder whose Core *is* compatible.
describe('the start-up version handshake (Extension Development Host)', () => {
  let api: OvallspApi;

  before(async function () {
    this.timeout(30000);

    const pkg = require('../../../package.json');
    const extension = vscode.extensions.getExtension(`${pkg.publisher}.${pkg.name}`);
    assert.ok(extension, 'expected the extension to be installed in the test host');
    api = (await extension!.activate()) as OvallspApi;

    // The handshake runs after `client.start()` resolves, which the
    // activation promise does not wait for. Deadline-bounded, never a
    // fixed sleep.
    const deadline = Date.now() + 25000;
    while (api.handshakes.length === 0 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  });

  it('writes a note for a folder whose Core is compatible', () => {
    assert.ok(
      api.handshakes.length > 0,
      'no start-up handshake was recorded. The call site in extension.ts is not being reached, ' +
        'which is 024.64 exactly: the notes are written on the compatible path too, and moving ' +
        'the call under `if (!compatible)` makes this fixture silent.'
    );
    assert.ok(
      api.handshakes.some((h) => h.compatible),
      'every recorded handshake was for an incompatible Core, so this fixture cannot tell a ' +
        'call site that runs on both branches from one that runs only on the incompatible one.'
    );
  });
});
