/**
 * The client-teardown half of `extension.ts`, kept free of any `vscode`
 * import so it can be unit-tested (024.10).
 *
 * `extension.ts` imports `vscode`, which the unit suite cannot load, so
 * anything living there is covered only by manual verification. The
 * decisions below are exactly the ones that were in that position:
 * awaiting `client.stop()` instead of firing it off, draining retirements
 * when a key has no tracked generation, the shutdown-barrier check on an
 * added workspace folder, and which confirmation each restart command
 * shows. None of them need `vscode` -- they need the lifecycle manager,
 * the registry maps, or nothing at all -- so those are parameters here
 * rather than module state.
 */

export interface StoppableClient {
  stop(): Thenable<void>;
}

export interface Disposable {
  dispose(): void;
}

/** The `ClientLifecycleManager` surface teardown actually uses. */
export interface TeardownLifecycle {
  getGeneration(key: string): number | undefined;
  requestStop(key: string): void;
  drainRetirements(): Promise<void>;
  terminateProcess(key: string, generation: number): Promise<void>;
  markStopped(key: string, generation: number): void;
  requestStopAndStopIfRunning(key: string, stopFn: () => Promise<void>): Promise<boolean>;
}

/** The per-folder maps `extension.ts` owns. */
export interface ClientRegistry {
  clients: Map<string, StoppableClient>;
  watchers: Map<string, Disposable>;
  versionDiagnostics: Map<string, unknown>;
}

/**
 * Which notification each restart command confirms with, keyed by the
 * command id VS Code dispatches.
 *
 * The *pairing* is the decision worth pinning, not the two strings: a
 * user who restarts the Core Server and is told the Runtime Agent
 * restarted has been told something false. Exporting two constants for
 * `extension.ts` to pick between at each call site would have pinned only
 * the wording and left the pairing free to be swapped silently -- which
 * is exactly what an earlier attempt at this did. Keying the table by
 * command id is only half the answer: `extension.ts` registers each
 * command through a helper that names the id once and looks the
 * confirmation up from that same id, so there is no pairing decision left
 * at a call site to get wrong.
 */
export const RESTART_SERVER_COMMAND = 'ovallsp.restartServer';
export const RESTART_AGENT_COMMAND = 'ovallsp.restartAgent';

export const RESTART_COMMAND_MESSAGES: Readonly<Record<string, string>> = Object.freeze({
  [RESTART_SERVER_COMMAND]: 'OvalLSP: Core Server restart requested.',
  [RESTART_AGENT_COMMAND]: 'OvalLSP: Runtime Agent restart requested.'
});

/** The confirmation for `commandId`, or undefined if it has none. */
export function restartMessageFor(commandId: string): string | undefined {
  return RESTART_COMMAND_MESSAGES[commandId];
}

/**
 * Whether an added workspace folder should get a Core Server. The barrier
 * check is the point: `activate` and `onDidChangeWorkspaceFolders` can
 * both fire against a host that is already shutting down, and a start
 * permitted then leaves a Core child nothing will ever stop.
 */
export function shouldStartAddedFolder(permitsStart: boolean, alreadyTracked: boolean): boolean {
  return permitsStart && !alreadyTracked;
}

/**
 * Tear down the client whose generation was superseded *while it was
 * starting*. `client.stop()` is awaited rather than fired off: terminating
 * the process underneath a client still shutting down is what produced
 * orphaned children, so the order (stop, then terminate, then mark) is the
 * behaviour, not an incidental detail. A rejected stop still has to reach
 * `terminateProcess` -- a client that failed to stop cleanly is precisely
 * the one whose process needs killing.
 */
export async function stopSupersededClient(
  client: StoppableClient,
  key: string,
  generation: number,
  lifecycle: TeardownLifecycle
): Promise<void> {
  await Promise.resolve(client.stop()).catch(() => undefined);
  await lifecycle.terminateProcess(key, generation);
  lifecycle.markStopped(key, generation);
}

/**
 * Stop the client for `key`, if there is one, and retire its process.
 *
 * With no client tracked, the key may still have a generation (a start
 * that never reached `clients`), in which case that generation's process
 * is terminated. With neither, `drainRetirements` is the only thing that
 * can still be owed -- a process retired by an earlier generation whose
 * termination has not been awaited yet. Skipping that drain is what let
 * `deactivate` return while a Core child was still alive.
 *
 * Recording the stop intent and deciding whether `client.stop()` is
 * currently safe are one atomic lifecycle operation. Splitting them
 * previously changed `running` to `stopping` before testing for
 * `running`, so a normal restart never stopped its old Core process.
 */
export function stopClient(
  key: string,
  registry: ClientRegistry,
  lifecycle: TeardownLifecycle
): Promise<void> {
  const generation = lifecycle.getGeneration(key);

  registry.watchers.get(key)?.dispose();
  registry.watchers.delete(key);
  registry.versionDiagnostics.delete(key);

  const client = registry.clients.get(key);
  if (!client) {
    lifecycle.requestStop(key);
    return generation === undefined
      ? lifecycle.drainRetirements()
      : lifecycle.terminateProcess(key, generation).then(() => lifecycle.markStopped(key, generation));
  }
  registry.clients.delete(key);

  return lifecycle
    .requestStopAndStopIfRunning(key, () => Promise.resolve(client.stop()).then(() => undefined))
    .catch(() => false)
    .then(async () => {
      if (generation !== undefined) {
        await lifecycle.terminateProcess(key, generation);
        lifecycle.markStopped(key, generation);
      }
    });
}
