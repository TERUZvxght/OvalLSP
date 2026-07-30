import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import {
  RESTART_AGENT_COMMAND,
  RESTART_COMMAND_MESSAGES,
  RESTART_SERVER_COMMAND,
  restartMessageFor,
  shouldStartAddedFolder,
  stopClient,
  stopSupersededClient
} from '../../clientTeardown';

interface Call {
  name: string;
  args: unknown[];
}

function fakeLifecycle(overrides: Partial<Record<string, unknown>> = {}) {
  const calls: Call[] = [];
  const record = (name: string) => (...args: unknown[]) => {
    calls.push({ name, args });
    return Promise.resolve();
  };
  const lifecycle = {
    calls,
    generation: undefined as number | undefined,
    getGeneration(): number | undefined {
      return lifecycle.generation;
    },
    requestStop: (...args: unknown[]) => {
      calls.push({ name: 'requestStop', args });
    },
    drainRetirements: record('drainRetirements') as () => Promise<void>,
    terminateProcess: record('terminateProcess') as (k: string, g: number) => Promise<void>,
    markStopped: (...args: unknown[]) => {
      calls.push({ name: 'markStopped', args });
    },
    async requestStopAndStopIfRunning(key: string, stopFn: () => Promise<void>): Promise<boolean> {
      calls.push({ name: 'requestStopAndStopIfRunning', args: [key] });
      await stopFn();
      return true;
    },
    ...overrides
  };
  return lifecycle;
}

function fakeRegistry() {
  const disposed: string[] = [];
  return {
    disposed,
    watchers: new Map<string, { dispose(): void }>(),
    versionDiagnostics: new Map<string, unknown>(),
    clients: new Map<string, { stop(): Promise<void> }>()
  };
}

describe('stopClient', () => {
  it('drains retirements when no generation is tracked for the key', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = undefined;
    const registry = fakeRegistry();

    await stopClient('folder-a', registry, lifecycle);

    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStop', 'drainRetirements']
    );
  });

  it('terminates and marks stopped when a generation is tracked but no client is', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = 7;
    const registry = fakeRegistry();

    await stopClient('folder-a', registry, lifecycle);

    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStop', 'terminateProcess', 'markStopped']
    );
    assert.deepStrictEqual(lifecycle.calls[1].args, ['folder-a', 7]);
  });

  it('disposes the watcher and forgets the client, watcher and version diagnostic', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = 1;
    const registry = fakeRegistry();
    let disposed = false;
    registry.watchers.set('folder-a', { dispose: () => { disposed = true; } });
    registry.versionDiagnostics.set('folder-a', {});
    registry.clients.set('folder-a', { stop: () => Promise.resolve() });

    await stopClient('folder-a', registry, lifecycle);

    assert.strictEqual(disposed, true);
    assert.strictEqual(registry.watchers.has('folder-a'), false);
    assert.strictEqual(registry.versionDiagnostics.has('folder-a'), false);
    assert.strictEqual(registry.clients.has('folder-a'), false);
  });

  it('waits for the client to finish stopping before terminating its process', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = 3;
    const registry = fakeRegistry();
    const order: string[] = [];
    let releaseStop!: () => void;
    const stopped = new Promise<void>((resolve) => {
      releaseStop = resolve;
    });
    registry.clients.set('folder-a', {
      stop: () => stopped.then(() => {
        order.push('client.stop resolved');
      })
    });

    const pending = stopClient('folder-a', registry, lifecycle).then(() => order.push('stopClient resolved'));
    // A macrotask, not a microtask turn: `stopClient`'s own promise chain
    // is several turns long, so a fire-and-forget `client.stop()` would
    // still let the fake stop settle first and satisfy an `order` check
    // alone. Asserting that *nothing past the stop* has run is what tells
    // the two apart.
    await new Promise((resolve) => setTimeout(resolve, 0));
    assert.deepStrictEqual(order, [], 'stopClient must not resolve while client.stop() is pending');
    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStopAndStopIfRunning'],
      'nothing past the stop may run while client.stop() is pending'
    );

    releaseStop();
    await pending;

    assert.deepStrictEqual(order, ['client.stop resolved', 'stopClient resolved']);
    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStopAndStopIfRunning', 'terminateProcess', 'markStopped']
    );
  });

  it('stops a tracked client with no tracked generation without terminating a process', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = undefined;
    const registry = fakeRegistry();
    registry.clients.set('folder-a', { stop: () => Promise.resolve() });

    await stopClient('folder-a', registry, lifecycle);

    // There is no generation to terminate or mark: doing it anyway would
    // pass `undefined` as a generation number to both.
    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStopAndStopIfRunning']
    );
  });

  it('still terminates the process when the client rejects while stopping', async () => {
    const lifecycle = fakeLifecycle();
    lifecycle.generation = 4;
    const registry = fakeRegistry();
    registry.clients.set('folder-a', { stop: () => Promise.reject(new Error('boom')) });

    await stopClient('folder-a', registry, lifecycle);

    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['requestStopAndStopIfRunning', 'terminateProcess', 'markStopped']
    );
  });
});

describe('stopSupersededClient', () => {
  it('awaits the stop before terminating and marking stopped', async () => {
    const lifecycle = fakeLifecycle();
    const order: string[] = [];
    let releaseStop!: () => void;
    const stopped = new Promise<void>((resolve) => {
      releaseStop = resolve;
    });
    const client = {
      stop: () => stopped.then(() => {
        order.push('client.stop resolved');
      })
    };

    const pending = stopSupersededClient(client, 'folder-a', 2, lifecycle);
    await Promise.resolve();
    assert.strictEqual(lifecycle.calls.length, 0, 'nothing may run before client.stop() settles');

    releaseStop();
    await pending;

    assert.deepStrictEqual(order, ['client.stop resolved']);
    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['terminateProcess', 'markStopped']
    );
    assert.deepStrictEqual(lifecycle.calls[0].args, ['folder-a', 2]);
  });

  it('terminates and marks stopped even when the stop rejects', async () => {
    const lifecycle = fakeLifecycle();

    await stopSupersededClient({ stop: () => Promise.reject(new Error('boom')) }, 'folder-a', 5, lifecycle);

    assert.deepStrictEqual(
      lifecycle.calls.map((c) => c.name),
      ['terminateProcess', 'markStopped']
    );
  });
});

describe('shouldStartAddedFolder', () => {
  it('starts only when the barrier permits it and the folder is not already tracked', () => {
    assert.strictEqual(shouldStartAddedFolder(true, false), true);
  });

  it('refuses while the shutdown barrier is closed', () => {
    assert.strictEqual(shouldStartAddedFolder(false, false), false);
  });

  it('refuses when a client for the folder already exists', () => {
    assert.strictEqual(shouldStartAddedFolder(true, true), false);
  });
});

describe('restartMessageFor', () => {
  it('confirms a Core Server restart', () => {
    assert.strictEqual(
      restartMessageFor(RESTART_SERVER_COMMAND),
      'OvalLSP: Core Server restart requested.'
    );
  });

  it('confirms a Runtime Agent restart', () => {
    assert.strictEqual(
      restartMessageFor(RESTART_AGENT_COMMAND),
      'OvalLSP: Runtime Agent restart requested.'
    );
  });

  it('never tells the user the wrong one restarted', () => {
    assert.notStrictEqual(restartMessageFor(RESTART_SERVER_COMMAND), restartMessageFor(RESTART_AGENT_COMMAND));
  });

  // The lookup is keyed by command id, so an id that does not exist in
  // the manifest would silently produce no confirmation at all.
  it('keys every message by a command the extension actually contributes', () => {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(__dirname, '..', '..', '..', 'package.json'), 'utf8')
    ) as { contributes: { commands: Array<{ command: string }> } };
    const contributed = new Set(manifest.contributes.commands.map((entry) => entry.command));

    for (const commandId of Object.keys(RESTART_COMMAND_MESSAGES)) {
      assert.ok(contributed.has(commandId), `${commandId} is not a contributed command`);
    }
  });
});
