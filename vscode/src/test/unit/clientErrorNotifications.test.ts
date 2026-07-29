import * as assert from 'assert';
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
});
