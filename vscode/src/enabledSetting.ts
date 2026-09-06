/**
 * What a change to `ovallsp.enabled` should do to a running extension.
 *
 * **The setting was read once, at activation, and never again.** When it
 * was `false`, `activate` returned before registering anything -- commands,
 * the status poller, and `onDidChangeConfiguration` itself -- so turning it
 * back on did nothing until the window was reloaded. Turning it *off* in a
 * running window did nothing either: there was no subscription to notice,
 * and no path that stops the clients. A user who disables the extension to
 * stop it analysing their code keeps a Core Server, and on a trusted Rails
 * workspace a Runtime Agent, running against it. Found by the 2026-09-05
 * critical review, R13.
 *
 * The decision is a pure function so it can be exercised without a host,
 * the way `startupGate.ts` and `shouldStartAddedFolder` already are: the
 * part that is easy to get wrong is *which* transitions act, and a
 * transition that acts when nothing changed starts a second Core.
 */
export type EnabledTransition = 'start' | 'stop' | 'none';

/**
 * `previous` and `next` are the setting's value before and after the
 * change event. Only an actual edge acts: a configuration change that
 * touches `ovallsp.enabled` without changing it -- a folder-level value
 * set to what the window already had -- must not restart anything.
 */
export function decideEnabledTransition(previous: boolean, next: boolean): EnabledTransition {
  if (previous === next) {
    return 'none';
  }
  return next ? 'start' : 'stop';
}
