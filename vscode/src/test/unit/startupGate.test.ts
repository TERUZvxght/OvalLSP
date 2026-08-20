import * as assert from 'assert';
import { decidePreStart } from '../../startupGate';

// `024.55`. Four documents said OvalLSP "stops before sending any feature
// request" on a version, protocol, build or platform mismatch, and shows
// a diagnostic "instead of a degraded session". It did not stop:
// `checkBundledCoreCompatibility` logged, raised a notification, and fell
// through to `client.start()`. `.stop(` appeared once in `extension.ts`
// and it was inside a comment.
//
// Only the *pre-start* half is decided here, which is the half that can
// honestly claim "before any feature request". By the time this verdict
// exists the probe has already established that the selected Ruby can
// load neither the bundled payload nor its own `prism`/`rbs` -- on every
// path, including the one where the version query merely timed out, which
// 0.2.10's review round found could refuse a working interpreter. The
// post-start handshake is a different decision with a different failure
// mode and is still open (`024.55`'s remaining half).
describe('pre-start compatibility gate', () => {
  it('refuses to start a Core the selected Ruby cannot load', () => {
    const verdict = decidePreStart({ compatible: false, reason: 'prism.bundle is for ruby 3.3' }, 'my-app');

    assert.strictEqual(verdict.start, false);
    assert.ok(verdict.logLine.includes('prism.bundle is for ruby 3.3'));
    assert.ok(verdict.notification?.includes('my-app'));
    // The point of the change: the user is told it did not start, not
    // that something was wrong while it starts anyway.
    assert.ok(verdict.notification?.includes('did not start'));
    // The reason travels into the notification: it used to name only the
    // bundled dependencies, which is the wrong reason on the path where
    // the version query failed.
    assert.ok(verdict.notification?.includes('prism.bundle is for ruby 3.3'));
  });

  it('starts when the probe is satisfied, and says nothing', () => {
    const verdict = decidePreStart({ compatible: true }, 'my-app');

    assert.strictEqual(verdict.start, true);
    assert.strictEqual(verdict.notification, undefined);
  });

  // The reason is what the user has to act on, so a verdict that refuses
  // without one is a dead end. An implementation that dropped the reason
  // would pass the first test's `start === false` and fail this.
  it('always carries a reason when it refuses', () => {
    const verdict = decidePreStart({ compatible: false }, 'my-app');

    assert.strictEqual(verdict.start, false);
    assert.ok(verdict.logLine.length > 0);
    assert.ok(verdict.logLine.includes('no reason was reported'));
  });
});
