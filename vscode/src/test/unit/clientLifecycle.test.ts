import * as assert from 'assert';
import { ClientLifecycleManager, KeyedTransitionQueue } from '../../clientLifecycle';

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
