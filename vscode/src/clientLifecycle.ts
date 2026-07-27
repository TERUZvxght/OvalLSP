// Task 023.3: the previously-identified-by-independent-review Extension
// lifecycle race. `startClientForFolder` (extension.ts) runs an
// asynchronous compatibility probe (ADR-0005's `checkBundledCoreCompatibility`)
// *before* ever calling `client.start()`. If `stopClient` (deactivate,
// workspace-folder removal, `OvalLSP: Restart Server`) runs while that
// probe is still in flight, the probe's own `.then()` continuation --
// which has no idea a stop happened -- goes on to call `client.start()`
// anyway, on a client this extension has already forgotten about (deleted
// from `clients`). That spawns a real Core child process nothing will
// ever call `.stop()` on: a permanent, unmanaged leak, not merely a
// logical inconsistency.
//
// This module is the single owner of "is it still valid to call
// client.start() for this folder right now" -- a plain boolean flag isn't
// enough on its own, because a *second* start (a later `activate`/restart
// for the same folder) must not be confused with the *first* start's own
// late-arriving probe. Each `beginStart` call gets its own generation
// number; only the continuation holding the current generation is ever
// allowed to actually start (or run) a client. Pure and free of
// `vscode-languageclient`/`vscode` themselves, so the state machine can be
// exercised with deferred Promises instead of a real LanguageClient or
// fixed `setTimeout`s.

import { CoreProcessHandle } from './coreProcess';

export type LifecycleState = 'pending' | 'starting' | 'running' | 'stopping' | 'stopped';

interface FolderState {
  generation: number;
  state: LifecycleState;
  process?: CoreProcessHandle;
}

export class ClientLifecycleManager {
  private readonly folders = new Map<string, FolderState>();

  /**
   * Begins a new generation for `key`, superseding any prior one
   * outright -- even if the prior generation's own probe/start is still
   * in flight, its continuations will find `isCurrent`/`markStarting`/
   * `markRunning` all refuse to act on its now-stale generation number.
   */
  beginStart(key: string): number {
    const generation = (this.folders.get(key)?.generation ?? 0) + 1;
    this.folders.set(key, { generation, state: 'pending' });
    return generation;
  }

  /** Whether `generation` is still the current one for `key`, in any state. */
  isCurrentGeneration(key: string, generation: number): boolean {
    return this.folders.get(key)?.generation === generation;
  }

  /**
   * Called once the pre-start compatibility probe resolves, right before
   * actually calling `client.start()`. Returns `false` when this
   * generation must not start at all -- either superseded by a newer
   * `beginStart`, or a stop was requested for this same generation while
   * the probe was still running (`requestStop` already moved it to
   * `stopping`/`stopped`).
   */
  markStarting(key: string, generation: number): boolean {
    const folder = this.folders.get(key);
    if (!folder || folder.generation !== generation || folder.state !== 'pending') {
      return false;
    }
    folder.state = 'starting';
    return true;
  }

  /**
   * Called once `client.start()` itself resolves. Returns `false` when a
   * stop raced in *during* the start (the folder moved to
   * `stopping`/`stopped`, or a newer generation began) -- the caller must
   * then immediately stop the client it just finished starting, since
   * nothing else will ever do so once this returns `false` (this manager
   * only tracks intent, it never touches the client itself).
   */
  markRunning(key: string, generation: number): boolean {
    const folder = this.folders.get(key);
    if (!folder || folder.generation !== generation || folder.state !== 'starting') {
      return false;
    }
    folder.state = 'running';
    return true;
  }

  /**
   * Registers the OS process as soon as it is spawned. A stop can land
   * between `client.start()` and the server-options callback; if this
   * generation is already stale/stopping, terminate it immediately.
   */
  registerProcess(key: string, generation: number, process: CoreProcessHandle): boolean {
    const folder = this.folders.get(key);
    if (!folder || folder.generation !== generation || folder.state !== 'starting') {
      void process.terminate();
      return false;
    }
    folder.process = process;
    return true;
  }

  async terminateProcess(key: string, generation: number): Promise<void> {
    const folder = this.folders.get(key);
    if (!folder || folder.generation !== generation) {
      return;
    }
    const process = folder.process;
    folder.process = undefined;
    await process?.terminate();
  }

  /**
   * Called synchronously by `stopClient`, before it does anything else
   * (in particular, before awaiting `client.stop()`) -- so a probe or
   * start-in-flight for the *current* generation observes the stop
   * immediately on its next check, however long its own async work still
   * has left to run. A stop against a key with no tracked generation at
   * all (nothing ever started) is a harmless no-op.
   */
  requestStop(key: string): void {
    const folder = this.folders.get(key);
    if (!folder) {
      return;
    }
    folder.state = folder.state === 'stopped' ? 'stopped' : 'stopping';
  }

  /** Called once the underlying `client.stop()` (or an equivalent teardown) actually completes. */
  markStopped(key: string, generation: number): void {
    const folder = this.folders.get(key);
    if (folder && folder.generation === generation) {
      folder.state = 'stopped';
    }
  }

  getState(key: string): LifecycleState | undefined {
    return this.folders.get(key)?.state;
  }

  /** Test/diagnostic helper -- not used by production wiring. */
  getGeneration(key: string): number | undefined {
    return this.folders.get(key)?.generation;
  }

  /**
   * Atomically records the stop request and captures whether the client
   * had already reached `running`. These two operations must not be
   * separate: `requestStop` changes `running` to `stopping`, so checking
   * for `running` afterward would always skip `stopFn` and leave every
   * normally-running Core process behind on restart/deactivation.
   *
   * A pending/starting client is not stopped here because
   * vscode-languageclient rejects `stop()` until startup completes. Its
   * own `markRunning`-false continuation remains responsible for stopping
   * it immediately after startup.
   */
  async requestStopAndStopIfRunning(key: string, stopFn: () => Promise<void>): Promise<boolean> {
    const folder = this.folders.get(key);
    if (!folder) {
      return false;
    }

    const shouldStop = folder.state === 'running';
    folder.state = folder.state === 'stopped' ? 'stopped' : 'stopping';
    if (!shouldStop) {
      return false;
    }

    await stopFn();
    return true;
  }
}

/**
 * Serializes asynchronous lifecycle replacements independently per key.
 * A rejected transition does not poison later work for that folder.
 */
export class KeyedTransitionQueue {
  private readonly chains = new Map<string, Promise<void>>();

  enqueue(key: string, transition: () => Promise<void>): Promise<void> {
    const previous = this.chains.get(key) ?? Promise.resolve();
    const next = previous.catch(() => undefined).then(transition);
    this.chains.set(key, next);
    const cleanup = () => {
      if (this.chains.get(key) === next) {
        this.chains.delete(key);
      }
    };
    void next.then(cleanup, cleanup);
    return next;
  }

  keys(): IterableIterator<string> {
    return this.chains.keys();
  }
}
