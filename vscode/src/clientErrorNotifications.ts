import { isCoreStartRejected } from './clientLifecycle';

export interface ClientErrorContext {
  /** The `data` vscode-languageclient passes with the error, if any. */
  data: unknown;
  /** What the library wants to do: `'force'` is a red popup. */
  showNotification?: boolean | 'force';
  /**
   * Whether the extension asked this client's generation to stop. True
   * means any closure the library is complaining about is one we caused.
   */
  stopWasRequested: boolean;
}

/**
 * Decides how loudly a `LanguageClient` error should be reported.
 *
 * vscode-languageclient treats every connection closure it did not
 * initiate as a crash, and after five in three minutes it gives up and
 * says so with `'force'` -- a red popup. Two kinds of closure are ours,
 * and the library cannot tell either from a real crash:
 *
 * - declining to spawn Core during deactivate/restart, which is the
 *   shutdown barrier working as intended. That one arrives as our own
 *   branded rejection, so it is recognisable from `data` alone.
 * - stopping a client that is still `starting`. `stopClient` deliberately
 *   does not call `client.stop()` in that state -- it terminates Core
 *   directly -- so the library sees a bare connection closure with no
 *   `data` at all. Five deliberate `OvalLSP: Restart Server` presses
 *   inside three minutes therefore produced "The OvalLSP server crashed 5
 *   times in the last 3 minutes", about five stops the user asked for
 *   (024.9).
 *
 * So the second case is decided on lifecycle state rather than on `data`:
 * if we asked this client's generation to stop, the closure is ours.
 * Everything else keeps the library's own, louder handling -- a client
 * nobody asked to stop is reported however it failed, which is what makes
 * this a suppression of our own noise rather than of bad news.
 *
 * Lives outside `extension.ts` so it can be tested at all: that module
 * imports `vscode`, which the unit suite cannot load (024.10).
 */
export function notificationLevelFor(context: ClientErrorContext): boolean | 'force' | undefined {
  if (isCoreStartRejected(context.data)) {
    return false;
  }
  if (context.stopWasRequested) {
    return false;
  }
  return context.showNotification;
}
