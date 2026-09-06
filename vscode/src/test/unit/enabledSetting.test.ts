import * as assert from 'assert';
import { decideEnabledTransition } from '../../enabledSetting';

// `024.343`. `ovallsp.enabled` was read once, in `activate`, and a `false`
// returned before `onDidChangeConfiguration` was ever registered -- so
// neither direction of a live change reached anything. Off-to-on needed a
// window reload; on-to-off left Core, and on a trusted Rails workspace the
// Runtime Agent, running against code the user had asked it to leave alone.
//
// The decision is separated from the host so the part that is easy to get
// wrong can be asserted directly: acting on a non-edge starts a second
// Core, and VS Code fires `onDidChangeConfiguration` for changes that do
// not change this value at all.
describe('the enabled setting', () => {
  it('starts when it goes from off to on', () => {
    assert.strictEqual(decideEnabledTransition(false, true), 'start');
  });

  it('stops when it goes from on to off', () => {
    assert.strictEqual(decideEnabledTransition(true, false), 'stop');
  });

  // The controls. Without them a rule that always started, or always
  // stopped, would pass both examples above.
  it('does nothing when the value did not change', () => {
    assert.strictEqual(decideEnabledTransition(true, true), 'none');
    assert.strictEqual(decideEnabledTransition(false, false), 'none');
  });
});
