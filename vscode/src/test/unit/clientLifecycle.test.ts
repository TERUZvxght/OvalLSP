import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import {
  canSpawnCoreProcess,
  ClientLifecycleManager,
  CoreStartRejectedError,
  isCoreStartRejected,
  KeyedTransitionQueue,
  ShutdownBarrier
} from '../../clientLifecycle';

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

describe('ClientLifecycleManager', () => {
  it('takes the normal path: pending -> starting -> running', () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');

    assert.strictEqual(lifecycle.getState('folder-a'), 'pending');
    assert.strictEqual(lifecycle.markStarting('folder-a', generation), true);
    assert.strictEqual(lifecycle.getState('folder-a'), 'starting');
    assert.strictEqual(lifecycle.markRunning('folder-a', generation), true);
    assert.strictEqual(lifecycle.getState('folder-a'), 'running');
  });

  it('refuses to start once a stop was requested while the compatibility probe was still in flight', async () => {
    // Reproduces the exact race this module exists to close: a stop
    // (deactivate/workspace-removal/restart) arrives *before* the
    // asynchronous compatibility probe's own continuation gets a chance
    // to call markStarting -- deferred Promises make the ordering
    // explicit instead of hoping a fixed sleep lands the right way.
    const lifecycle = new ClientLifecycleManager();
    const probe = deferred<void>();
    const generation = lifecycle.beginStart('folder-a');

    let startWasCalled = false;
    const continuation = probe.promise.then(() => {
      if (lifecycle.markStarting('folder-a', generation)) {
        startWasCalled = true;
      }
    });

    lifecycle.requestStop('folder-a'); // the stop lands first...
    probe.resolve(); // ...then the probe finally resolves.
    await continuation;

    assert.strictEqual(startWasCalled, false, 'client.start() must never be called once a stop was already requested');
    assert.strictEqual(lifecycle.getState('folder-a'), 'stopping');
  });

  it('reports that client.start() must be stopped immediately when a stop raced in while start() itself was in flight', async () => {
    const lifecycle = new ClientLifecycleManager();
    const clientStart = deferred<void>();
    const generation = lifecycle.beginStart('folder-a');
    assert.strictEqual(lifecycle.markStarting('folder-a', generation), true);

    let stoppedImmediatelyAfterStart = false;
    const continuation = clientStart.promise.then(() => {
      if (!lifecycle.markRunning('folder-a', generation)) {
        stoppedImmediatelyAfterStart = true; // what extension.ts does: void client.stop()
      }
    });

    lifecycle.requestStop('folder-a'); // stop requested while client.start() itself is still resolving
    clientStart.resolve();
    await continuation;

    assert.strictEqual(stoppedImmediatelyAfterStart, true);
    assert.notStrictEqual(lifecycle.getState('folder-a'), 'running', 'must never be left running after a stop raced in');
  });

  it('a restart only ever lets the newest generation actually start -- the old generation\'s late probe is inert', async () => {
    const lifecycle = new ClientLifecycleManager();
    const oldProbe = deferred<void>();
    const oldGeneration = lifecycle.beginStart('folder-a');

    const oldContinuation = oldProbe.promise.then(() => lifecycle.markStarting('folder-a', oldGeneration));

    // A restart begins a second generation before the first's probe ever resolves.
    const newGeneration = lifecycle.beginStart('folder-a');
    assert.notStrictEqual(newGeneration, oldGeneration);

    oldProbe.resolve();
    const oldStarted = await oldContinuation;

    assert.strictEqual(oldStarted, false, 'the superseded generation must never be allowed to start');
    assert.strictEqual(lifecycle.markStarting('folder-a', newGeneration), true, 'the current generation starts normally');
  });

  it('workspace folder removal mid-probe behaves identically to any other stop request', async () => {
    const lifecycle = new ClientLifecycleManager();
    const probe = deferred<void>();
    const generation = lifecycle.beginStart('folder-a');

    const continuation = probe.promise.then(() => lifecycle.markStarting('folder-a', generation));

    lifecycle.requestStop('folder-a'); // onDidChangeWorkspaceFolders(event.removed) -> stopClient
    probe.resolve();

    assert.strictEqual(await continuation, false);
  });

  it('requestStop on a key that never started at all is a harmless no-op', () => {
    const lifecycle = new ClientLifecycleManager();
    assert.doesNotThrow(() => lifecycle.requestStop('never-started'));
    assert.strictEqual(lifecycle.getState('never-started'), undefined);
  });

  describe('stopWasRequested', () => {
    it('is false for a generation that is still starting or running', () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', generation);

      assert.strictEqual(lifecycle.stopWasRequested('folder-a', generation), false);

      lifecycle.markRunning('folder-a', generation);
      assert.strictEqual(lifecycle.stopWasRequested('folder-a', generation), false);
    });

    it('is true once a stop has been asked for, and stays true after it completes', () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', generation);

      lifecycle.requestStop('folder-a');
      assert.strictEqual(lifecycle.stopWasRequested('folder-a', generation), true);

      lifecycle.markStopped('folder-a', generation);
      assert.strictEqual(lifecycle.stopWasRequested('folder-a', generation), true);
    });

    // A superseded generation was necessarily stopped to make way for the
    // one that replaced it -- and its client can still report the closure
    // afterwards, which is exactly when this is asked.
    it('is true for a generation a later start has superseded', () => {
      const lifecycle = new ClientLifecycleManager();
      const first = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', first);
      const second = lifecycle.beginStart('folder-a');

      assert.strictEqual(lifecycle.stopWasRequested('folder-a', first), true);
      assert.strictEqual(lifecycle.stopWasRequested('folder-a', second), false);
    });

    it('is false for a key that never started at all', () => {
      const lifecycle = new ClientLifecycleManager();

      assert.strictEqual(lifecycle.stopWasRequested('never-started', 1), false);
    });
  });

  it('markStopped finalizes the state, and only for the generation it was called for', () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    lifecycle.requestStop('folder-a');
    lifecycle.markStopped('folder-a', generation);

    assert.strictEqual(lifecycle.getState('folder-a'), 'stopped');
  });

  it('markStopped is a no-op for a stale generation (a slow teardown from an already-superseded start)', () => {
    const lifecycle = new ClientLifecycleManager();
    const oldGeneration = lifecycle.beginStart('folder-a');
    const newGeneration = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', newGeneration);

    lifecycle.markStopped('folder-a', oldGeneration); // a straggler from the old generation

    assert.strictEqual(lifecycle.getState('folder-a'), 'starting', 'the current generation\'s state must be untouched');
  });

  it('markStarting is not idempotent -- calling it twice for the same generation only succeeds once', () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');

    assert.strictEqual(lifecycle.markStarting('folder-a', generation), true);
    assert.strictEqual(lifecycle.markStarting('folder-a', generation), false);
  });

  it('markRunning refuses to fire before markStarting ever happened', () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');

    assert.strictEqual(lifecycle.markRunning('folder-a', generation), false);
  });

  describe('requestStopAndStopIfRunning', () => {
    // A stub reproducing vscode-languageclient's own `LanguageClient.stop()`
    // (`shutdown()` internally) contract precisely enough to catch a
    // regression: it throws synchronously (inside the returned rejected
    // Promise -- `stopIfRunning` awaits `stopFn()`) unless the stub's own
    // `started` flag is true, mirroring the real library throwing whenever
    // its internal state isn't exactly `Running` (including while
    // `client.start()` is still in flight). This is exactly the shape of
    // the bug independent review found: `extension.ts`'s old `stopClient`
    // called a client's `.stop()` unconditionally, which threw in that
    // window and silently broke `OvalLSP: Restart Server`.
    function fakeLanguageClientStop(started: () => boolean) {
      return () =>
        started()
          ? Promise.resolve()
          : Promise.reject(new Error('Client is not running and can\'t be stopped.'));
    }

    it('does not call stopFn, and does not throw, when the generation never reached running (mirrors the real library rejecting mid-start)', async () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', generation); // client.start() is "in flight" -- not yet running
      lifecycle.requestStop('folder-a'); // a stop lands in that exact window

      let stopFnCalled = false;
      const stopFn = () => {
        stopFnCalled = true;
        return fakeLanguageClientStop(() => false)(); // the real library would reject here
      };

      const didStop = await lifecycle.requestStopAndStopIfRunning('folder-a', stopFn);

      assert.strictEqual(stopFnCalled, false, 'stopFn must never be called while this generation has not reached running');
      assert.strictEqual(didStop, false);
      assert.strictEqual(lifecycle.getState('folder-a'), 'stopping');
    });

    it('calls stopFn when the generation has actually reached running', async () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', generation);
      lifecycle.markRunning('folder-a', generation);

      let stopFnCalled = false;
      const stopFn = () => {
        stopFnCalled = true;
        return fakeLanguageClientStop(() => true)();
      };

      const didStop = await lifecycle.requestStopAndStopIfRunning('folder-a', stopFn);

      assert.strictEqual(stopFnCalled, true);
      assert.strictEqual(didStop, true);
      assert.strictEqual(lifecycle.getState('folder-a'), 'stopping');
    });

    it('does not call stopFn for a key that never started at all', async () => {
      const lifecycle = new ClientLifecycleManager();
      let stopFnCalled = false;

      const didStop = await lifecycle.requestStopAndStopIfRunning('never-started', () => {
        stopFnCalled = true;
        return Promise.resolve();
      });

      assert.strictEqual(stopFnCalled, false);
      assert.strictEqual(didStop, false);
    });

    it('regression: reproduces the exact real-world race -- a stop requested while a slow client.start() is still resolving must never throw', async () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      const probe = deferred<void>();

      // Mirrors startClientForFolder: the compatibility probe resolves,
      // markStarting succeeds (client.start() is about to be called)...
      const startContinuation = probe.promise.then(async () => {
        if (!lifecycle.markStarting('folder-a', generation)) {
          return;
        }
        // ...client.start() is now "in flight" (real library state: Starting).
      });

      probe.resolve();
      await startContinuation;

      // ...and a stop (workspace-folder removal, deactivate, restart) lands
      // in exactly this window, before client.start() has resolved.
      const stopFn = () => Promise.reject(new Error('Client is not running and can\'t be stopped.'));

      await assert.doesNotReject(
        lifecycle.requestStopAndStopIfRunning('folder-a', stopFn),
        'stopClient must never propagate the real library\'s reject/throw in this window'
      );
    });

    it('regression: the production ordering stops a running client instead of losing its pre-stop state', async () => {
      const lifecycle = new ClientLifecycleManager();
      const generation = lifecycle.beginStart('folder-a');
      lifecycle.markStarting('folder-a', generation);
      lifecycle.markRunning('folder-a', generation);

      let stopFnCalled = false;
      const didStop = await lifecycle.requestStopAndStopIfRunning('folder-a', async () => {
        stopFnCalled = true;
      });

      assert.strictEqual(stopFnCalled, true, 'a normally running Core process must be stopped during restart');
      assert.strictEqual(didStop, true);
    });
  });

  it('tracks multiple folders independently', () => {
    const lifecycle = new ClientLifecycleManager();
    const genA = lifecycle.beginStart('folder-a');
    const genB = lifecycle.beginStart('folder-b');

    lifecycle.requestStop('folder-a');

    assert.strictEqual(lifecycle.markStarting('folder-a', genA), false);
    assert.strictEqual(lifecycle.markStarting('folder-b', genB), true);
  });

  it('terminates a process registered after its generation was already stopped', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    lifecycle.requestStop('folder-a');

    let terminated = false;
    const registered = lifecycle.registerProcess('folder-a', generation, {
      terminate: async () => {
        terminated = true;
      }
    });
    await Promise.resolve();

    assert.strictEqual(registered, false);
    assert.strictEqual(terminated, true);
  });

  it('terminates the exact process owned by the current generation', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    let terminationCount = 0;
    lifecycle.registerProcess('folder-a', generation, {
      terminate: async () => {
        terminationCount += 1;
      }
    });

    await lifecycle.terminateProcess('folder-a', generation);
    await lifecycle.terminateProcess('folder-a', generation);

    assert.strictEqual(terminationCount, 1);
  });

  it('accepts vscode-languageclient automatic process replacement while running', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    let oldTerminations = 0;
    let newTerminations = 0;
    lifecycle.registerProcess('folder-a', generation, {
      terminate: async () => {
        oldTerminations += 1;
      }
    });
    lifecycle.markRunning('folder-a', generation);

    const registered = lifecycle.registerProcess('folder-a', generation, {
      terminate: async () => {
        newTerminations += 1;
      }
    });
    await Promise.resolve();

    assert.strictEqual(registered, true);
    assert.strictEqual(oldTerminations, 1);
    assert.strictEqual(newTerminations, 0);
    await lifecycle.terminateProcess('folder-a', generation);
    assert.strictEqual(newTerminations, 1);
  });

  it('awaits retirement of a replaced process during final termination', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    const oldTermination = deferred<void>();
    lifecycle.registerProcess('folder-a', generation, { terminate: () => oldTermination.promise });
    lifecycle.markRunning('folder-a', generation);
    lifecycle.registerProcess('folder-a', generation, { terminate: async () => undefined });

    let drained = false;
    const termination = lifecycle.terminateProcess('folder-a', generation).then(() => {
      drained = true;
    });
    await Promise.resolve();
    assert.strictEqual(drained, false);

    oldTermination.resolve();
    await termination;
    assert.strictEqual(drained, true);
  });

  it('awaits a stale registration retirement through the global drain', async () => {
    const lifecycle = new ClientLifecycleManager();
    const retirement = deferred<void>();
    lifecycle.registerProcess('missing', 1, { terminate: () => retirement.promise });

    let drained = false;
    const draining = lifecycle.drainRetirements().then(() => {
      drained = true;
    });
    await Promise.resolve();
    assert.strictEqual(drained, false);

    retirement.resolve();
    await draining;
    assert.strictEqual(drained, true);
  });

  // Regression guard: every production path stops the client first, and
  // that nulls `folder.process` -- so this is the last line of defence
  // for a handle that outlived its generation (a stop that threw, a
  // crash-recovery spawn landing after a restart began). Nothing else in
  // the suite would notice if it were dropped, and the process it owns
  // is a live Core plus whatever it spawned.
  it('retires a process still held by the previous generation when a new start begins', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    let terminated = false;
    lifecycle.registerProcess('folder-a', generation, {
      terminate: async () => {
        terminated = true;
      }
    });

    lifecycle.beginStart('folder-a');
    await lifecycle.drainRetirements();

    assert.strictEqual(terminated, true, 'expected the superseded generation\'s Core to be terminated');
  });

  // `terminateProcess` must not resolve until the Core it just handed to
  // `trackTermination` — and anything already retiring for this folder —
  // has actually finished terminating. `stopClient` awaits it, and
  // `deactivate` awaits `stopClient`, so resolving early lets VS Code
  // exit while a Core (and whatever Runtime Agent it spawned) is still
  // mid-teardown. Awaiting only the handle would also miss a retirement
  // from a previous crash-recovery replacement.
  it('does not resolve terminateProcess until every retirement for that folder has settled', async () => {
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    // The Core replaced by vscode-languageclient's crash recovery: still
    // retiring, and reachable only through `folder.retirements`.
    const crashed = deferred<void>();
    lifecycle.registerProcess('folder-a', generation, { terminate: () => crashed.promise });
    lifecycle.registerProcess('folder-a', generation, { terminate: async () => undefined });

    let finished = false;
    const termination = lifecycle.terminateProcess('folder-a', generation).then(() => {
      finished = true;
    });
    await new Promise((resolve) => setImmediate(resolve));
    assert.strictEqual(finished, false, 'expected the terminate to still be waiting on the replaced Core');

    crashed.resolve();
    await termination;

    assert.strictEqual(finished, true);
  });

  it('includes a retirement registered while a drain is already waiting', async () => {
    const lifecycle = new ClientLifecycleManager();
    const first = deferred<void>();
    const late = deferred<void>();
    lifecycle.registerProcess('missing', 1, { terminate: () => first.promise });

    let drained = false;
    const draining = lifecycle.drainRetirements().then(() => {
      drained = true;
    });
    lifecycle.registerProcess('also-missing', 1, { terminate: () => late.promise });
    first.resolve();
    // Two microtask ticks were not enough to make this assertion mean
    // anything: the retirement chain (`then -> catch -> finally`) had not
    // settled by then even in a single-pass drain, so `drained` was still
    // false for reasons unrelated to the re-check loop and the test
    // passed against the very implementation it exists to reject. A
    // macrotask boundary flushes the whole microtask queue, so reaching
    // here with `drained` still false is now evidence that the drain
    // genuinely looked again and saw the late retirement.
    await new Promise((resolve) => setImmediate(resolve));
    assert.strictEqual(drained, false);

    late.resolve();
    await draining;
    assert.strictEqual(drained, true);
  });
});

describe('CoreStartRejectedError', () => {
  // vscode-languageclient reports every ServerOptions rejection through
  // `error(..., 'force')`, which forces a red popup -- so declining to
  // spawn during a normal deactivate/restart told users "Restarting
  // server failed" about the barrier working as designed. The rejection
  // is branded so exactly that case can be downgraded to a log line,
  // while genuine failures keep the library's louder handling.
  it('is recognizable after crossing a promise boundary that erases the class', async () => {
    const rejection = Promise.reject(new CoreStartRejectedError('rejected during shutdown'));

    const caught = await rejection.catch((error: unknown) => error);

    assert.strictEqual(isCoreStartRejected(caught), true);
  });

  it('does not claim unrelated failures, which must keep their visible error', () => {
    assert.strictEqual(isCoreStartRejected(new Error('ruby not found')), false);
    assert.strictEqual(isCoreStartRejected(undefined), false);
    assert.strictEqual(isCoreStartRejected(null), false);
    assert.strictEqual(isCoreStartRejected('rejected during shutdown'), false);
  });

  // Duck-typed rather than `instanceof`: the value crosses
  // vscode-languageclient's own plumbing, and a duplicated module
  // instance would break identity while the brand survives.
  it('recognizes the brand without depending on the class identity', () => {
    const structurallyIdentical = { ovallspReason: new CoreStartRejectedError('x').ovallspReason };

    assert.strictEqual(isCoreStartRejected(structurallyIdentical), true);
  });
});

describe('ShutdownBarrier', () => {
  it('rejects new starts for the rest of the shutdown once deactivation begins', () => {
    const barrier = new ShutdownBarrier();

    assert.strictEqual(barrier.permitsStart(), true);
    barrier.beginShutdown();
    assert.strictEqual(barrier.permitsStart(), false);
    barrier.beginShutdown();
    assert.strictEqual(barrier.permitsStart(), false);
  });

  // Regression: the barrier is module state and outlives deactivate() in
  // a surviving extension host, so disable-then-enable (no window
  // reload) re-entered activate() with the barrier still closed. Every
  // client start and every added workspace folder was then refused, and
  // the refusal is branded precisely so it does *not* raise a popup --
  // the extension was silently, permanently dead with no error shown.
  it('reopens for a fresh activation after a completed shutdown', () => {
    const barrier = new ShutdownBarrier();
    barrier.beginShutdown();

    barrier.reset();

    assert.strictEqual(barrier.permitsStart(), true);
  });

  // The test above covers the class; the *bug* was that `activate()`
  // never called it. `extension.ts` imports `vscode` and so cannot be
  // loaded here, which is exactly why deleting the call left the whole
  // suite green -- so this reads the source instead. A structural guard,
  // deliberately: it costs nothing and pins the one line whose absence
  // silently kills the extension after a disable/enable.
  it('is reopened by activate() before anything can ask to spawn Core', () => {
    const source = fs.readFileSync(path.join(__dirname, '../../../src/extension.ts'), 'utf8');
    const activateBody = source.slice(source.indexOf('export function activate('));

    assert.ok(
      activateBody.indexOf('shutdownBarrier.reset()') >= 0 &&
        activateBody.indexOf('shutdownBarrier.reset()') < activateBody.indexOf('startClientForFolder('),
      'expected activate() to reset the shutdown barrier before starting any client'
    );
  });

  // The state half of the predicate, which the generation/barrier test
  // below cannot see. `stopClient` moves the folder to `stopping`
  // synchronously and only then awaits `client.stop()`; inside that
  // window vscode-languageclient still considers itself Running, so a
  // Core connection closing there takes its error handler's Restart
  // branch straight back into ServerOptions. The shutdown barrier is
  // open (this is a Restart Server or a removed folder, not a
  // deactivate), so nothing else refuses: without the state check a real
  // Core is spawned during its own shutdown, and only `registerProcess`
  // tears it back down afterwards.
  it('refuses to spawn for a generation that is already stopping', () => {
    const barrier = new ShutdownBarrier();
    const lifecycle = new ClientLifecycleManager();
    const generation = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', generation);
    lifecycle.markRunning('folder-a', generation);
    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', generation), true);

    lifecycle.requestStop('folder-a');

    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', generation), false);
  });

  it('rejects an old client auto-restart before spawn after shutdown or generation replacement', () => {
    const barrier = new ShutdownBarrier();
    const lifecycle = new ClientLifecycleManager();
    const oldGeneration = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', oldGeneration);
    lifecycle.markRunning('folder-a', oldGeneration);
    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', oldGeneration), true);

    const newGeneration = lifecycle.beginStart('folder-a');
    lifecycle.markStarting('folder-a', newGeneration);
    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', oldGeneration), false);
    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', newGeneration), true);

    barrier.beginShutdown();
    assert.strictEqual(canSpawnCoreProcess(barrier, lifecycle, 'folder-a', newGeneration), false);
  });
});

describe('KeyedTransitionQueue', () => {
  it('serializes overlapping restarts for the same folder', async () => {
    const queue = new KeyedTransitionQueue();
    const firstStop = deferred<void>();
    const firstEntered = deferred<void>();
    const order: string[] = [];

    const first = queue.enqueue('folder-a', async () => {
      order.push('first-stop-started');
      firstEntered.resolve();
      await firstStop.promise;
      order.push('first-start');
    });
    const second = queue.enqueue('folder-a', async () => {
      order.push('second-stop');
      order.push('second-start');
    });

    await firstEntered.promise;
    assert.deepStrictEqual(order, ['first-stop-started']);
    firstStop.resolve();
    await Promise.all([first, second]);

    assert.deepStrictEqual(order, ['first-stop-started', 'first-start', 'second-stop', 'second-start']);
  });

  it('continues with the next transition after an earlier one rejects', async () => {
    const queue = new KeyedTransitionQueue();
    const first = queue.enqueue('folder-a', async () => {
      throw new Error('failed');
    });
    let secondRan = false;
    const second = queue.enqueue('folder-a', async () => {
      secondRan = true;
    });

    await assert.rejects(first);
    await second;

    assert.strictEqual(secondRan, true);
  });
});
