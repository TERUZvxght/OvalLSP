import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import { notificationLevelFor } from '../../clientErrorNotifications';
import { CoreStartRejectedError } from '../../clientLifecycle';

// vscode-languageclient reports every connection closure it did not ask
// for as an error, and after five in three minutes it gives up and says
// so with `'force'` -- a red popup. Some of those closures are ours: the
// extension terminates Core directly when it stops a client that is still
// `starting`, because calling `client.stop()` in that state is unsafe.
// The library cannot tell the difference. This function is where we do.
describe('notificationLevelFor', () => {
  it('passes an ordinary error through untouched', () => {
    assert.strictEqual(
      notificationLevelFor({ data: new Error('boom'), showNotification: true, stopWasRequested: false }),
      true
    );
  });

  it('leaves a forced notification forced when nothing of ours caused it', () => {
    assert.strictEqual(
      notificationLevelFor({ data: undefined, showNotification: 'force', stopWasRequested: false }),
      'force'
    );
  });

  it('preserves an absent showNotification rather than inventing one', () => {
    assert.strictEqual(
      notificationLevelFor({ data: undefined, showNotification: undefined, stopWasRequested: false }),
      undefined
    );
  });

  it('silences our own branded start refusal', () => {
    assert.strictEqual(
      notificationLevelFor({ data: new CoreStartRejectedError('declined'), showNotification: 'force', stopWasRequested: false }),
      false
    );
  });

  // The case 024.9 is about. The crash-count notice arrives with no `data`
  // at all, so the branded-rejection test above cannot see it: five
  // deliberate `OvalLSP: Restart Server` presses inside three minutes
  // produced "The OvalLSP server crashed 5 times in the last 3 minutes",
  // about five stops the user themselves asked for.
  it('silences a forced notification about a client we asked to stop', () => {
    assert.strictEqual(
      notificationLevelFor({ data: undefined, showNotification: 'force', stopWasRequested: true }),
      false
    );
  });

  it('silences an ordinary notification about a client we asked to stop', () => {
    assert.strictEqual(
      notificationLevelFor({ data: new Error('connection closed'), showNotification: true, stopWasRequested: true }),
      false
    );
  });

  // A genuine crash must still be reported, and "we asked it to stop" is
  // the only thing that suppresses one. A client nobody asked to stop is
  // reported however it failed.
  it('reports a real crash of a client nobody asked to stop', () => {
    assert.strictEqual(
      notificationLevelFor({ data: new Error('server exited'), showNotification: 'force', stopWasRequested: false }),
      'force'
    );
  });

  // Everything above covers the decision; the connection to a real client
  // is one line in `extension.ts`, which imports `vscode` and so cannot be
  // loaded here. Passing `() => false` there undoes 024.9 completely and
  // leaves every test in this file green -- verified. So this reads the
  // source instead, the same structural guard `clientLifecycle.test.ts`
  // already uses for `shutdownBarrier.reset()`, and for the same reason.
  it('is wired to the real lifecycle, not to a constant', () => {
    const source = fs.readFileSync(path.join(__dirname, '../../../src/extension.ts'), 'utf8');
    const construction = source.slice(source.indexOf('new OvalLspLanguageClient('));
    const argumentList = construction.slice(0, construction.indexOf(');'));

    assert.ok(
      /lifecycle\.stopWasRequested\(\s*key\s*,\s*generation\s*\)/.test(argumentList),
      'expected the client to ask the lifecycle about its own generation, not a fixed value'
    );
  });

  it('asks about the generation captured at construction, not whichever is current', () => {
    const source = fs.readFileSync(path.join(__dirname, '../../../src/extension.ts'), 'utf8');
    const startBody = source.slice(source.indexOf('function startClientForFolder('));
    const captured = startBody.indexOf('const generation = lifecycle.beginStart(key)');
    const construction = startBody.indexOf('new OvalLspLanguageClient(');

    // Both indices are asserted present first. `indexOf` answers -1 when
    // the needle is gone, and -1 is less than any real index, so comparing
    // the two directly would pass with nothing found at all -- a guard
    // that survives the very edit it exists to catch.
    assert.ok(captured >= 0, 'expected startClientForFolder to capture a generation');
    assert.ok(construction >= 0, 'expected startClientForFolder to construct the client');
    assert.ok(
      captured < construction,
      'expected the generation to be captured before the client that reports against it'
    );
  });
});
