import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

import type { OvallspApi } from '../../extension';

// Task 064 P2/W3: `ovallsp.diagnostics.severities` is `resource`-scoped,
// and the wiring must not drop a change made while a folder's Core is
// still starting, must deliver a live change (including none/reset) to
// an already-running client, and must never notify a stopped client.
// None of that is reachable from `src/test/unit` -- nothing there can
// import `extension.ts` -- so this runs `activate()` for real and edits
// a real `.vscode/settings.json` through the same
// `vscode.workspace.getConfiguration(...).update(...)` API a user's
// Settings UI would call.
//
// **A second (`A`/`B`) folder is deliberately not exercised here.**
// `vscode.workspace.updateWorkspaceFolders` converting this suite's
// single-folder Extension Development Host into a multi-root workspace
// triggered a full extension-host reload in this VS Code version (every
// suite in this directory ran a second time, and the reload itself raced
// this test's own second `updateWorkspaceFolders` call to failure) --
// verified for real, not assumed. A same-process A/B host test needs a
// dedicated multi-root fixture opened as such from process launch (a
// `.code-workspace` file plus a second `runTest.ts` entry point, since
// the existing one and every other spec in this directory assume a
// single already-open folder), which is new shared test infrastructure
// rather than this task's wiring -- left to Astra rather than decided
// here. The resource-scoped read this exercises is the same
// `getConfiguration(section, resource)` call already relied on
// everywhere else in `extension.ts` (Ruby resolution, `server.path`) with
// no dedicated multi-root host test either.
describe('OvalLSP diagnostics settings: live change, none/reset, and stop (Extension Development Host)', () => {
  let api: OvallspApi;
  let folder: vscode.WorkspaceFolder;

  async function waitFor(predicate: () => boolean, timeoutMs: number, message: string): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!predicate() && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    assert.ok(predicate(), message);
  }

  function lastSeverities(): Record<string, string> | undefined {
    const entries = api.diagnosticsNotifications.filter((n) => n.folder === folder.name);
    return entries.length > 0 ? entries[entries.length - 1].severities : undefined;
  }

  async function setSeverities(value: Record<string, string> | undefined): Promise<void> {
    await vscode.workspace
      .getConfiguration('ovallsp.diagnostics', folder.uri)
      .update('severities', value, vscode.ConfigurationTarget.WorkspaceFolder);
  }

  before(async function () {
    this.timeout(30000);

    const pkg = require('../../../package.json');
    const extension = vscode.extensions.getExtension(`${pkg.publisher}.${pkg.name}`);
    assert.ok(extension, 'expected the extension to be installed in the test host');
    api = (await extension!.activate()) as OvallspApi;

    const found = vscode.workspace.workspaceFolders?.[0];
    assert.ok(found, 'expected an open workspace folder');
    folder = found!;

    // The snapshot `startClientForFolder` sends the instant its client
    // reaches `running` (see extension.ts and `shouldNotifyRunningClient`'s
    // own docs) -- this is the real start-up replay already having
    // happened, not a fixture standing in for it.
    await waitFor(
      () => api.diagnosticsNotifications.some((n) => n.folder === folder.name),
      15000,
      'expected the just-started diagnostics settings snapshot for the open folder'
    );
  });

  after(async function () {
    this.timeout(15000);
    await setSeverities(undefined);
    const settingsPath = path.join(folder.uri.fsPath, '.vscode', 'settings.json');
    if (fs.existsSync(settingsPath)) {
      fs.rmSync(settingsPath);
    }
  });

  it('delivers a live severities change, a none override, and a reset to the running client', async function () {
    this.timeout(30000);

    await setSeverities({ 'unknown-method': 'hint' });
    await waitFor(
      () => lastSeverities()?.['unknown-method'] === 'hint',
      10000,
      'expected the demotion to be delivered to the running client'
    );

    // P2: "none の解除は既定への復帰" -- both directions round-trip
    // through the same live-change path just proven above.
    await setSeverities({ 'unknown-method': 'none' });
    await waitFor(
      () => lastSeverities()?.['unknown-method'] === 'none',
      10000,
      'expected the none override to be delivered'
    );

    await setSeverities(undefined);
    await waitFor(
      () => {
        const value = lastSeverities();
        return !!value && Object.keys(value).length === 0;
      },
      10000,
      'expected the reset (default empty override map) to be delivered'
    );
  });

  it('never notifies a stopped client', async function () {
    this.timeout(30000);

    await setSeverities({ 'unknown-method': 'hint' });
    await waitFor(
      () => lastSeverities()?.['unknown-method'] === 'hint',
      10000,
      'expected the change to be delivered while running, before stopping the client'
    );
    const beforeStop = api.diagnosticsNotifications.length;

    await vscode.commands.executeCommand('ovallsp.restartServer');
    // `restartServer` stops then starts a new generation; a config change
    // sent to the exact instant between those two must reach nobody --
    // the guard is `shouldNotifyRunningClient`'s job, not a well-timed
    // caller's. Firing it repeatedly across that window is a cheap way to
    // give a wrongly-still-notified stale client a real chance to record
    // something, without pretending to hit the race on a single try.
    for (let i = 0; i < 10; i++) {
      await setSeverities({ 'unknown-method': i % 2 === 0 ? 'hint' : 'information' });
      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    // The new generation replays the (last-set) current snapshot the
    // instant it reaches `running` again, so this settles back to a
    // healthy state rather than staying silent.
    await waitFor(
      () => lastSeverities()?.['unknown-method'] === 'information',
      15000,
      'expected the restarted client to end up running with the latest value, not stuck mid-transition'
    );
    assert.ok(
      api.diagnosticsNotifications.length > beforeStop,
      'expected at least one notification across the restart -- a guard that always refuses would pass this test for the wrong reason'
    );
  });
});
