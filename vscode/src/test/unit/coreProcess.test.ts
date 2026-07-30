import * as assert from 'assert';
import { ChildProcess, spawn } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
  ProcessIdentity,
  ProcessTreeInspector,
  SpawnedCoreProcess,
  SystemProcessTreeInspector
} from '../../coreProcess';

function processAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code !== 'ESRCH';
  }
}

describe('SpawnedCoreProcess', () => {
  it('creates the Windows Core suspended, assigns its Job, then resumes it', () => {
    const wrapper = fs.readFileSync(
      path.resolve(__dirname, '../../../resources/core-job.ps1'),
      'utf8'
    );
    const runBody = wrapper.slice(wrapper.indexOf('public static int Run'));
    const create = runBody.indexOf('if (!CreateProcess(');
    const assign = runBody.indexOf('if (!AssignProcessToJobObject(');
    const resume = runBody.indexOf('if (ResumeThread(');

    assert.ok(create >= 0);
    assert.ok(create < assign);
    assert.ok(assign < resume);
    assert.ok(runBody.includes('const uint CREATE_SUSPENDED'));
  });

  it('establishes the Core session before loading the server entrypoint', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }
    const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'ovallsp-session-'));
    const entrypoint = path.join(temporaryDirectory, 'entrypoint.rb');
    fs.writeFileSync(entrypoint, 'puts "#{Process.pid}:#{Process.getsid(0)}"');
    const wrapper = path.resolve(__dirname, '../../../resources/core-session.rb');
    try {
      const child = spawn('ruby', [wrapper, entrypoint], { stdio: ['ignore', 'pipe', 'pipe'] });
      const output = await new Promise<string>((resolve, reject) => {
        let stdout = '';
        let stderr = '';
        child.stdout!.on('data', (chunk) => { stdout += chunk.toString(); });
        child.stderr!.on('data', (chunk) => { stderr += chunk.toString(); });
        child.once('error', reject);
        child.once('close', (code) => {
          code === 0 ? resolve(stdout.trim()) : reject(new Error(stderr));
        });
      });
      const [pid, session] = output.split(':').map(Number);
      assert.strictEqual(session, pid);
    } finally {
      fs.rmSync(temporaryDirectory, { recursive: true, force: true });
    }
  });

  it('does not blindly signal a previously seen process group when ps becomes unavailable', async () => {
    const inspector = new SystemProcessTreeInspector('linux');
    inspector.snapshot = async () => {
      throw new Error('ps unavailable');
    };
    const calls: Array<{ pid: number; signal?: NodeJS.Signals | number }> = [];
    const originalKill = process.kill;
    process.kill = ((pid: number, signal?: NodeJS.Signals | number) => {
      calls.push({ pid, signal });
      return true;
    }) as typeof process.kill;
    try {
      await inspector.signal(
        { pid: 200, ppid: 1, pgid: 200, sid: 100, startedAt: 'runner' },
        'SIGTERM'
      );
    } finally {
      process.kill = originalKill;
    }

    assert.deepStrictEqual(calls, []);
  });

  it('terminates a real detached process and is idempotent', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }

    const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
      detached: true,
      stdio: 'ignore'
    });
    assert.ok(child.pid);
    const pid = child.pid;
    const owner = new SpawnedCoreProcess(child, process.platform, 100, 100);

    await owner.terminate();
    await owner.terminate();

    assert.strictEqual(processAlive(pid), false);
  });

  it('terminates descendants in the detached Core process group', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }

    const script =
      "const {spawn}=require('child_process');" +
      "const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{detached:true,stdio:'ignore'});" +
      "process.stdout.write(String(child.pid)+'\\n');setInterval(()=>{},1000);";
    const core = spawn(process.execPath, ['-e', script], {
      detached: true,
      stdio: ['ignore', 'pipe', 'ignore']
    });
    assert.ok(core.pid);
    const childPid = await new Promise<number>((resolve, reject) => {
      let output = '';
      core.stdout!.on('data', (chunk) => {
        output += chunk.toString();
        const line = output.split('\n')[0];
        if (line.length > 0) {
          resolve(Number(line));
        }
      });
      core.once('error', reject);
    });
    const owner = new SpawnedCoreProcess(core, process.platform, 100, 100);

    await owner.terminate();

    assert.strictEqual(processAlive(core.pid), false);
    assert.strictEqual(processAlive(childPid), false);
  });

  it('does not signal a PID whose start identity was reused', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'root-a' },
      { pid: 200, ppid: 100, pgid: 200, sid: 100, startedAt: 'child-a' }
    ];
    const signalled: ProcessIdentity[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;
    const owner = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector);
    await new Promise((resolve) => setTimeout(resolve, 0));

    // PID 200 now belongs to an unrelated process with a different
    // start identity and parent.
    entries[1] = { pid: 200, ppid: 999, pgid: 200, sid: 999, startedAt: 'child-b' };
    await owner.terminate();

    assert.ok(signalled.some((identity) => identity.pid === 100));
    assert.ok(!signalled.some((identity) => identity.pid === 200));
  });

  it('uses Windows tree termination instead of killing only the Core child', async () => {
    const treeKills: number[] = [];
    let directKills = 0;
    const inspector: ProcessTreeInspector = {
      snapshot: async () => [],
      signal: async () => undefined,
      terminateWindowsTree: async (pid) => {
        treeKills.push(pid);
      }
    };
    const fakeChild = {
      pid: 321,
      exitCode: null,
      signalCode: null,
      kill: () => {
        directKills += 1;
        return true;
      }
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'win32', 1, 1, inspector).terminate();

    assert.deepStrictEqual(treeKills, [321]);
    assert.strictEqual(directKills, 0, 'a successful taskkill must not signal a potentially recycled PID afterward');
  });

  it('does not taskkill a recycled Windows PID after the owned child already exited', async () => {
    let treeKills = 0;
    const inspector: ProcessTreeInspector = {
      snapshot: async () => [],
      signal: async () => undefined,
      terminateWindowsTree: async () => {
        treeKills += 1;
      }
    };
    const fakeChild = {
      pid: 321,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'win32', 1, 1, inspector).terminate();

    assert.strictEqual(treeKills, 0);
  });

  it('falls back to killing the owned child when Windows tree termination fails', async () => {
    let directKills = 0;
    const inspector: ProcessTreeInspector = {
      snapshot: async () => [],
      signal: async () => undefined,
      terminateWindowsTree: async () => {
        throw new Error('taskkill failed');
      }
    };
    const fakeChild = {
      pid: 321,
      exitCode: null,
      signalCode: null,
      kill: () => {
        directKills += 1;
        return true;
      }
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'win32', 1, 1, inspector).terminate();

    assert.strictEqual(directKills, 1);
  });

  it('directly signals the owned child when process snapshots remain unavailable', async () => {
    const directSignals: NodeJS.Signals[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => {
        throw new Error('ps unavailable');
      },
      signal: async () => undefined,
      terminateWindowsTree: async () => undefined
    };
    let signalCode: NodeJS.Signals | null = null;
    const fakeChild = {
      pid: 100,
      exitCode: null,
      get signalCode() {
        return signalCode;
      },
      kill: (signal: NodeJS.Signals) => {
        directSignals.push(signal);
        if (signal === 'SIGKILL') {
          signalCode = signal;
        }
        return true;
      }
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector).terminate();

    assert.deepStrictEqual(directSignals, ['SIGTERM', 'SIGKILL']);
  });

  it('waits for an in-flight descendant snapshot before terminating', async () => {
    let releaseSnapshot!: (entries: ProcessIdentity[]) => void;
    let first = true;
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'root' },
      { pid: 200, ppid: 100, pgid: 200, sid: 100, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: () => {
        if (first) {
          first = false;
          return new Promise((resolve) => {
            releaseSnapshot = resolve;
          });
        }
        return Promise.resolve(entries.map((entry) => ({ ...entry })));
      },
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;
    const owner = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector);

    const termination = owner.terminate();
    releaseSnapshot(entries);
    await termination;

    assert.ok(signalled.includes(100));
    assert.ok(signalled.includes(200));
  });

  it('keeps ownership of a detached runner by session after the Core root crashes', async () => {
    let snapshots = 0;
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'root' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => {
        snapshots += 1;
        if (snapshots > 1) {
          entries = [{ pid: 200, ppid: 1, pgid: 200, sid: 100, startedAt: 'runner' }];
        }
        return entries.map((entry) => ({ ...entry }));
      },
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector).terminate();

    assert.ok(signalled.includes(200));
  });

  // Regression (024.8): `refreshDescendants` used to retire
  // `ownedSessionId`/`ownedGroupId` whenever it found the root exited and
  // nothing tracked. That was justified as unreachable-in-effect, on the
  // grounds that reaching it means the root was absent and the expansion
  // gate is already closed. It isn't: `rootObservedAbsent` is assigned at
  // the *end* of the pass, and a root row can be present and still not be
  // tracked, because `known` only takes the root while the child has not
  // exited. On Darwin that is the ordinary pre-`setsid` shape -- `sid` is
  // 0 for every row and `pgid` is still the host's, so neither ownership
  // test matches the root either -- and a Core that dies inside the
  // ~57ms setsid window lands there exactly.
  //
  // Retiring ownership then was permanent, and later passes do exist:
  // `terminateOnce` and `waitForAllExit` both refresh after the interval
  // is cleared. So the runner that appears in the *next* snapshot, in the
  // group our child's pid leads, was never adopted and never signalled --
  // the same leak the Darwin test below was written about, reached by a
  // different route.
  it('adopts a runner that only appears after the Core root died pre-setsid on Darwin', async () => {
    let snapshots = 0;
    let entries: ProcessIdentity[] = [
      // Pre-setsid: still in the host's group (pgid 7), and Darwin
      // reports sess=0, so nothing here identifies the row as ours.
      { pid: 100, ppid: 1, pgid: 7, sid: 0, startedAt: 'our-core' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => {
        snapshots += 1;
        if (snapshots > 1) {
          // setsid completed before the crash after all: the runner is in
          // the group led by our child's pid.
          entries = [{ pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'runner' }];
        }
        return entries.map((entry) => ({ ...entry }));
      },
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const owner = new SpawnedCoreProcess(fakeChild, 'darwin', 1, 1, inspector, true);
    // Let the first pass -- the one that sees an exited root and owns
    // nothing -- complete before terminating.
    await new Promise((resolve) => setTimeout(resolve, 0));
    await owner.terminate();

    assert.ok(
      signalled.includes(200),
      'expected the runner to still be adoptable after a pass that owned nothing'
    );
  });

  // Regression: every other session test here hands the owner a snapshot
  // whose `sid` is a real session id. macOS never produces that -- `ps -o
  // sess=` reports 0 for every process on Darwin (verified on a real
  // machine: 0 of 578 rows non-zero), even though `Process.getsid` inside
  // those same processes returns a real sid. Modelling the platform
  // truthfully is the whole point of this test: with `sid` pinned to 0
  // and only `pgid` carrying the setsid grouping, the previous
  // implementation owned nothing at all, cleared `known` on every
  // refresh, skipped its own PPID fallback, and left a surviving Runtime
  // Agent unsignalled -- on the only platform this Preview ships.
  it('still owns a surviving runner on Darwin, where ps reports sess=0 for every process', async () => {
    let entries: ProcessIdentity[] = [
      // Real macOS shape: sid always 0; setsid is observable only as
      // pgid === pid on the session leader, inherited by its children.
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core' },
      { pid: 200, ppid: 100, pgid: 100, sid: 0, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    // Core itself already died -- exactly the case dedicated-session
    // ownership exists to cover.
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'darwin', 1, 1, inspector, true).terminate();

    assert.ok(
      signalled.length > 0,
      'expected the surviving runner to be signalled, but nothing was owned at all'
    );
    assert.ok(signalled.includes(200) || signalled.includes(100), 'expected the setsid process group to be signalled');
  });

  // Regression, and the most dangerous defect found in this whole
  // effort: `core-session.rb` only becomes its own group leader once it
  // reaches `Process.setsid`. Spawned with `detached: false`, the Core
  // root sits in the *extension host's* process group until then --
  // measured at ~57ms on a real machine, easily hit by a stop during
  // activation, a double restart, or deactivate racing startup. Owning
  // that pgid and issuing `kill(-pgid)` terminates VS Code's own process
  // group, i.e. the editor. The invariant that prevents it: a group is
  // only ever negated when its pgid is our own child's pid, which the
  // host's group can never be (the host's group leader predates that pid
  // and still holds it).
  // Regression: `ps -o lstart=` is rendered per LC_TIME and execFile
  // inherits the extension host's environment, so under ja_JP/de_DE/etc.
  // every row failed the ASCII-only parse. `ps` exited 0 with zero rows
  // parsed, which read as "this machine has no processes": no root, no
  // descendants, no signals, waitForAllExit returning true immediately --
  // the whole mechanism silently inert for anyone not running an English
  // locale, which for a project shipping Japanese docs is a large share
  // of its users.
  // Regression: this `ps` is system-wide and carries the whole `command=`
  // column, and Node's default 1 MiB execFile buffer is a hard failure
  // rather than a truncation. A developer with enough Electron/Chrome/
  // JetBrains helpers running crosses it, and from that moment *every*
  // snapshot rejects: no root, no descendants, nothing signalled, and the
  // monitor polling forever because its shutdown condition is downstream
  // of the early return. Load-conditional and permanent -- strictly worse
  // than the locale bug above, which at least depended on a setting.
  it('survives a ps snapshot larger than the default execFile buffer', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'oval-ps-'));
    const previousPath = process.env.PATH;
    try {
      // Emits ~1.5 MiB of well-formed rows in the LC_ALL=C format the
      // parser expects, so the only thing under test is the buffer cap.
      const script = [
        '#!/bin/sh',
        'i=1000',
        'pad=$(printf "%0.sx" $(seq 1 400))',
        'while [ $i -lt 4200 ]; do',
        '  echo "$i 1 $i 0 Mon Jul 28 10:59:31 2026 /usr/bin/helper-$i $pad"',
        '  i=$((i + 1))',
        'done'
      ].join('\n');
      fs.writeFileSync(path.join(dir, 'ps'), script, { mode: 0o755 });
      process.env.PATH = `${dir}:${previousPath ?? ''}`;

      const rows = await new SystemProcessTreeInspector(process.platform).snapshot();

      assert.strictEqual(rows.length, 3200, 'expected every row of an oversized ps snapshot');
    } finally {
      process.env.PATH = previousPath;
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // Regression: the guard behind the locale fix. `ps` exiting 0 with
  // output we cannot parse is a parser/environment problem, never
  // evidence that the machine has no processes -- but read as an empty
  // snapshot it retires every tracked process at once and reports every
  // survivor as already gone. The locale test above only exercises the
  // repaired path; this pins the fallback for the next format surprise.
  it('rejects a ps snapshot whose output cannot be parsed at all', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'oval-ps-'));
    const previousPath = process.env.PATH;
    try {
      fs.writeFileSync(
        path.join(dir, 'ps'),
        '#!/bin/sh\necho "PID PPID PGID SESS STARTED COMMAND"\necho "not a row we can read"\n',
        { mode: 0o755 }
      );
      process.env.PATH = `${dir}:${previousPath ?? ''}`;

      await assert.rejects(
        () => new SystemProcessTreeInspector(process.platform).snapshot(),
        /could not be parsed/,
        'expected unparseable output to be rejected, not read as an empty process table'
      );
    } finally {
      process.env.PATH = previousPath;
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  // Regression: `signal()` re-snapshots per target and `signalAll` fires
  // every target at once, twice per terminate(), so each tracked process
  // used to launch its own system-wide `ps` simultaneously. Against a 1s
  // timeout that is self-inflicted load whose failure mode is a *skipped*
  // signal, not a slow one.
  it('shares one ps run between overlapping snapshot callers', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'oval-ps-'));
    const previousPath = process.env.PATH;
    const runs = path.join(dir, 'runs');
    try {
      fs.writeFileSync(
        path.join(dir, 'ps'),
        `#!/bin/sh\necho x >> ${runs}\necho "1000 1 1000 0 Mon Jul 28 10:59:31 2026 /usr/bin/helper"\n`,
        { mode: 0o755 }
      );
      process.env.PATH = `${dir}:${previousPath ?? ''}`;
      const inspector = new SystemProcessTreeInspector(process.platform);

      const results = await Promise.all([inspector.snapshot(), inspector.snapshot(), inspector.snapshot()]);

      assert.strictEqual(fs.readFileSync(runs, 'utf8').trim().split('\n').length, 1, 'expected a single ps run');
      results.forEach((rows) => assert.strictEqual(rows.length, 1));
      // A later caller still gets a fresh run, not a cached table.
      await inspector.snapshot();
      assert.strictEqual(fs.readFileSync(runs, 'utf8').trim().split('\n').length, 2);
    } finally {
      process.env.PATH = previousPath;
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('parses ps output regardless of the user locale', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }
    const previous = process.env.LC_ALL;
    process.env.LC_ALL = 'ja_JP.UTF-8';
    try {
      const rows = await new SystemProcessTreeInspector(process.platform).snapshot();

      assert.ok(rows.length > 0, 'expected ps to yield parseable rows under a non-English locale');
      assert.ok(rows.some((row) => row.pid === process.pid), 'expected this very process among them');
    } finally {
      previous === undefined ? delete process.env.LC_ALL : (process.env.LC_ALL = previous);
    }
  });

  // Regression: the root row was looked up by pid number alone. A handle
  // can outlive its process for a long time (vscode-languageclient
  // exhausting its restart budget, a client held until deactivate), and
  // its own polling spawns `ps` processes that hurry pid wraparound
  // along. Once the pid was recycled by any process that leads a group,
  // that entire foreign group was adopted and killed by the next
  // terminate() -- the same class as the host-group defect above.
  it('does not adopt a foreign process group after its own pid was recycled', async () => {
    const recycled: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'unrelated-later', command: 'someone else' },
      { pid: 101, ppid: 100, pgid: 100, sid: 100, startedAt: 'unrelated-later', command: 'their child' }
    ];
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'our-core', command: 'ruby core-session.rb' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;
    const owner = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    // First snapshot captures our real Core's identity.
    await new Promise((resolve) => setTimeout(resolve, 0));

    // Our Core exits; the pid is recycled by an unrelated group leader.
    (fakeChild as unknown as { exitCode: number | null }).exitCode = 0;
    entries = recycled;
    await owner.terminate();

    assert.deepStrictEqual(
      signalled,
      [],
      `expected nothing to be signalled after the pid was recycled, but signalled ${signalled.join(', ')}`
    );
  });

  // Regression: signalAll used Promise.all, and the inspector rethrows
  // anything that is not ESRCH (EPERM is reachable for a descendant that
  // changed uid). One such rejection propagated out of the SIGTERM pass,
  // skipping child.kill and the entire waitForAllExit/SIGKILL escalation,
  // and was swallowed by terminate()'s outer catch -- so terminate()
  // resolved as if it had succeeded while the tree was still alive.
  it('still escalates to SIGKILL when signalling one descendant throws', async () => {
    const entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'core' },
      { pid: 300, ppid: 100, pgid: 100, sid: 100, startedAt: 'privileged' }
    ];
    const delivered: string[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity, signal) => {
        if (identity.pid === 300) {
          const error = new Error('operation not permitted') as NodeJS.ErrnoException;
          error.code = 'EPERM';
          throw error;
        }
        delivered.push(`${signal}:${identity.pid}`);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true).terminate();

    assert.ok(
      delivered.some((entry) => entry.startsWith('SIGKILL')),
      `expected SIGKILL escalation despite the EPERM, but only delivered ${delivered.join(', ') || '(nothing)'}`
    );
  });

  it('only ever negates the process group its own Core leads, never the host\'s', async () => {
    const hostPgid = 500; // the extension host's group -- must never be negated
    const entries: ProcessIdentity[] = [
      // Pre-setsid shape: the root's pgid is still the host's.
      { pid: 100, ppid: 500, pgid: hostPgid, sid: 0, startedAt: 'core' }
    ];
    const groupSignals: number[] = [];
    const pidSignals: number[] = [];
    const negatedGroups: number[] = groupSignals;
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity, _signal, options) => {
        if (options?.group) {
          groupSignals.push(identity.pgid);
        } else {
          pidSignals.push(identity.pid);
        }
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'darwin', 1, 1, inspector, true).terminate();

    assert.strictEqual(
      negatedGroups.length,
      0,
      `expected no group signal before setsid was observed, but signalled group(s) ${negatedGroups.join(', ')}`
    );
    assert.ok(!negatedGroups.includes(hostPgid), 'must never negate the extension host\'s own process group');
    // The Core process itself must still be signalled -- by pid.
    assert.ok(pidSignals.includes(100));
  });

  it('owns the dedicated session even when the Core root exits before the first snapshot', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 200, ppid: 1, pgid: 200, sid: 100, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true).terminate();

    assert.ok(signalled.includes(200));
  });

  // Regression: the test above asserts that guarantee on the one platform
  // where it already held. Ownership of an in-session survivor was
  // matched against `ownedGroupId`, which is only ever assigned from a
  // *validated root row* -- so with the root already gone it stayed
  // undefined, and on Darwin (`sess` is 0 for every process) the session
  // match could not stand in for it. Both halves failing at once meant
  // nothing was owned at all and the runner leaked, on the only platform
  // this Preview ships. Ownership now matches the pid recorded
  // synchronously at spawn, which needs no snapshot to have succeeded.
  it('owns the dedicated session on Darwin even when the Core root exits before the first snapshot', async () => {
    let entries: ProcessIdentity[] = [
      // Real macOS shape: sid 0, and the setsid grouping visible only as
      // pgid inherited from the (already departed) session leader.
      { pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
        entries = entries.filter((entry) => entry.pgid !== identity.pgid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'darwin', 1, 1, inspector, true).terminate();

    assert.ok(
      signalled.includes(200),
      'expected the in-session survivor to be signalled, but nothing was owned at all'
    );
  });

  // The root's pgid and sid MUST be excluded from its identity check,
  // and that omission needs pinning as much as the `command` one does.
  // Spawned with `detached: false`, the Core root sits in the extension
  // host's process group until `core-session.rb` reaches setsid (~57ms
  // on a real machine), so its pgid and sid *both* change during the
  // window between the constructor's snapshot and the next one. Comparing
  // them treats our own process as an impostor at exactly the moment it
  // became interesting: ownership is cleared, the captured identity is
  // never refreshed (so every later snapshot mismatches too), the root is
  // pruned, the union is gated off, and the PPID walk starts from an
  // empty set -- nothing is signalled at all, not even the live root.
  it('keeps the root identified across the setsid transition that changes its pgid and sid', async () => {
    const hostPgid = 42;
    let entries: ProcessIdentity[] = [
      // Pre-setsid: still in the extension host's group and session.
      { pid: 100, ppid: 1, pgid: hostPgid, sid: hostPgid, startedAt: 'core' }
    ];
    const groupSignals: number[] = [];
    const pidSignals: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity, _signal, options) => {
        (options?.group ? groupSignals : pidSignals).push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    // setsid lands: the same process now leads its own group and session,
    // and has spawned a Runtime Agent inside it.
    entries = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'core' },
      { pid: 200, ppid: 100, pgid: 100, sid: 100, startedAt: 'agent' }
    ];

    await core.terminate();

    assert.ok(pidSignals.includes(100), 'expected our own root to still be recognised after setsid');
    assert.ok(pidSignals.includes(200), 'expected the agent spawned into the new session to be owned');
    assert.deepStrictEqual(groupSignals, [100, 100], 'expected the setsid group to be negated on TERM and KILL');
  });

  // Regression: pid-derived ownership was only ever retired on positive
  // evidence -- a row *at* our pid that mismatched. An unoccupied pid
  // produces no row to mismatch, so after Core and its whole session
  // exited, `ownedSessionId`/`ownedGroupId` kept our old pid forever
  // while the handle sat in `folder.process` (a VS Code window open for
  // days is ordinary). If a stranger then took the pid, led a group and
  // exited, its orphans carried our old pgid with no row at the pid
  // itself: nothing could fire, the union adopted them, and terminate()
  // SIGTERMed and SIGKILLed an unrelated user's process group.
  it('never negates a group inherited from our recycled pid once a snapshot showed it free', async () => {
    let entries: ProcessIdentity[] = [{ pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core' }];
    const groupSignals: number[] = [];
    const pidSignals: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity, _signal, options) => {
        (options?.group ? groupSignals : pidSignals).push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    // Core and its entire session exit; a poll sees the pid free.
    (fakeChild as { exitCode: number | null }).exitCode = 0;
    entries = [];
    await new Promise((resolve) => setTimeout(resolve, 400));
    // Much later: a stranger took pid 100, led a group, and exited --
    // leaving orphans that carry our old pgid, with no row at pid 100.
    entries = [
      { pid: 777, ppid: 1, pgid: 100, sid: 0, startedAt: 'stranger-a' },
      { pid: 778, ppid: 1, pgid: 100, sid: 0, startedAt: 'stranger-b' }
    ];

    await core.terminate();

    assert.deepStrictEqual(groupSignals, [], 'must never negate a process group inherited from our recycled pid');
    assert.deepStrictEqual(pidSignals, [], 'must not signal unrelated processes that inherited our old pgid');
  });

  // The same defect with our own survivor still alive, so `known` never
  // empties. (The example above reaches the same safety by the same
  // mechanism -- `rootObservedAbsent` closing the expansion gate -- not by
  // any retirement of the pid-derived fields: 024.8 deleted that, and this
  // pair of examples passes either way.) Ownership
  // must stop *expanding* by pid once a snapshot has shown that pid free,
  // while everything already tracked stays tracked.
  it('stops adopting new group members once a snapshot has shown our pid free', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core' },
      { pid: 200, ppid: 100, pgid: 100, sid: 0, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    // Core exits; our runner survives and keeps `known` non-empty.
    (fakeChild as { exitCode: number | null }).exitCode = 0;
    entries = [{ pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'runner' }];
    await new Promise((resolve) => setTimeout(resolve, 400));
    // A stranger now takes the freed pid and leads a group with our old number.
    entries = [
      { pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'runner' },
      { pid: 900, ppid: 1, pgid: 100, sid: 0, startedAt: 'stranger' }
    ];

    await core.terminate();

    assert.ok(signalled.includes(200), 'our own survivor must still be signalled');
    assert.ok(!signalled.includes(900), 'a stranger joining our old pgid afterwards must not be adopted');
  });

  // Regression: the COMMAND column is not invariant over a process's
  // life, so comparing it was not a free extra check -- it was a
  // deterministic false "this pid belongs to someone else". Every
  // version-manager shim (mise/asdf/rbenv) is a shell script that execs
  // the real ruby, and `extension.ts` only re-points at the real binary
  // on darwin when its config query succeeds, so on Linux, on a failed
  // query, or with an explicit shim in `ovallsp.rubyExecutablePath`, the
  // argv changes right after the first snapshot. The mismatch branch
  // never refreshes the captured identity, so ownership was dropped
  // permanently: measured against a real rbenv shim, the owner tracked
  // nothing at all -- not even the live root -- and the in-session
  // survivor was still running after terminate().
  it('keeps ownership when the root execs and its ps command line changes', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core', command: 'bash /shims/ruby core-session.rb' },
      { pid: 200, ppid: 100, pgid: 100, sid: 0, startedAt: 'runner', command: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    // The shim execs the real ruby: same pid, same start time, new argv.
    entries = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core', command: '/versions/3.4.7/bin/ruby core-session.rb' },
      { pid: 200, ppid: 100, pgid: 100, sid: 0, startedAt: 'runner', command: 'runner' }
    ];

    await core.terminate();

    assert.ok(signalled.includes(100), 'expected the root to still be recognised after exec');
    assert.ok(signalled.includes(200), 'expected descendants to stay owned after the root execs');
  });

  // The same non-invariance, on the darwin happy path: `ps` prints
  // "<defunct>" for a reaped-pending child while preserving its lstart,
  // and Node reaps asynchronously, so teardown samples that window
  // routinely. Read as an impostor, it dropped the session at exactly the
  // moment a surviving Runtime Agent needed to be signalled.
  it('keeps ownership when the root shows up as <defunct> before it is reaped', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core', command: 'ruby core-session.rb' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    (fakeChild as { exitCode: number | null }).exitCode = 0;
    entries = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'core', command: '<defunct>' },
      // The Runtime Agent becomes visible in the same refresh.
      { pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'agent', command: 'rails runner' }
    ];

    await core.terminate();

    assert.ok(signalled.includes(200), 'expected the surviving agent to be signalled despite the <defunct> root row');
  });

  // Regression, and the same catastrophe class as the pre-setsid pgid
  // bug: the recycled-pid defence compares a row against the identity
  // captured while the process was alive, so it cannot fire when that
  // capture never happened. A Core that crashed before the very first
  // `ps` returned left `rootIdentity` undefined forever, and the next row
  // to ever appear at our pid was adopted as the root unconditionally --
  // taking its session and, worse, its process *group* with it, which
  // terminate() then negates with kill(-pgid). A handle can sit unused
  // for hours before deactivate, which is ample time for the pid to be
  // recycled by a login shell or an sshd session leader.
  it('never adopts a stranger at our pid after a snapshot showed the pid free', async () => {
    let entries: ProcessIdentity[] = [];
    const groupSignals: number[] = [];
    const pidSignals: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity, _signal, options) => {
        (options?.group ? groupSignals : pidSignals).push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    // Core crashed before the first snapshot could see it.
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    await new Promise((resolve) => setImmediate(resolve));
    // Our pid is recycled by an unrelated session/group leader.
    entries = [
      { pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'sshd', command: 'sshd: someone' },
      { pid: 900, ppid: 100, pgid: 100, sid: 100, startedAt: 'login-shell', command: '-zsh' }
    ];

    await core.terminate();

    assert.deepStrictEqual(groupSignals, [], 'must never negate a process group we only inferred from a recycled pid');
    assert.deepStrictEqual(pidSignals, [], 'must not signal an unrelated process that merely reused our pid');
  });

  // Regression: a handle can outlive its process by a long time (the
  // client exhausting its restart budget, a client kept until
  // deactivate), and every 200ms tick spawns another `ps` -- which itself
  // consumes pids and hurries the wraparound that could hand our old
  // number to a stranger. The stop condition needs both halves pinned:
  // it must not stop while a survivor is still owned, and it must stop
  // once nothing is.
  it('keeps polling while a descendant survives and stops once nothing is owned', async function () {
    // Real timers against a 200ms monitor. Three windows plus terminate()
    // ran at 1503ms against mocha's 2000ms default, so a modest overshoot
    // under CI load would fail it for no reason.
    this.timeout(10000);
    let entries: ProcessIdentity[] = [
      { pid: 200, ppid: 1, pgid: 100, sid: 0, startedAt: 'runner' }
    ];
    let snapshots = 0;
    const inspector: ProcessTreeInspector = {
      snapshot: async () => {
        snapshots += 1;
        return entries.map((entry) => ({ ...entry }));
      },
      signal: async () => undefined,
      terminateWindowsTree: async () => undefined
    };
    // Core is already gone; only the in-session survivor keeps the
    // monitor alive.
    const fakeChild = {
      pid: 100,
      exitCode: 1,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector, true);
    try {
      await new Promise((resolve) => setTimeout(resolve, 700));
      assert.ok(snapshots >= 2, `expected polling to continue while a survivor is owned, saw ${snapshots}`);

      entries = [];
      await new Promise((resolve) => setTimeout(resolve, 500));
      const afterLastOwned = snapshots;
      await new Promise((resolve) => setTimeout(resolve, 500));

      assert.strictEqual(snapshots, afterLastOwned, 'expected the monitor to stop once nothing was owned');
    } finally {
      await core.terminate();
    }
  });

  // Regression: a tracked descendant is re-validated on every refresh,
  // and losing its parent is the *expected* fate of a survivor -- the
  // kernel reparents it to init, changing the one field a strict identity
  // comparison insists on. Comparing with sameIdentity dropped exactly
  // the processes this owner exists to clean up, at the moment they
  // became orphans. The group/session adoption cannot paper over it: a
  // descendant that made its own process group is only ever reachable
  // through the PPID walk and this tracked set.
  it('keeps tracking a descendant that is reparented to init when the Core root dies', async () => {
    let entries: ProcessIdentity[] = [
      { pid: 100, ppid: 1, pgid: 100, sid: 0, startedAt: 'root' },
      // Its own process group, so ownership can only come from tracking.
      { pid: 200, ppid: 100, pgid: 300, sid: 0, startedAt: 'runner' }
    ];
    const signalled: number[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => entries.map((entry) => ({ ...entry })),
      signal: async (identity) => {
        signalled.push(identity.pid);
      },
      terminateWindowsTree: async () => undefined
    };
    const fakeChild = {
      pid: 100,
      exitCode: null,
      signalCode: null,
      kill: () => true
    } as unknown as ChildProcess;

    const core = new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector);
    // Let the constructor's first refresh discover 200 through the root.
    await new Promise((resolve) => setImmediate(resolve));
    // The root exits; the kernel reparents its child to init.
    (fakeChild as { exitCode: number | null }).exitCode = 0;
    entries = [{ pid: 200, ppid: 1, pgid: 300, sid: 0, startedAt: 'runner' }];

    await core.terminate();

    assert.ok(
      signalled.includes(200),
      'expected the orphaned descendant to stay tracked across reparenting'
    );
  });

  // Regression: the same tolerance is needed immediately before
  // signalling, where the identity is re-checked against a fresh `ps`.
  // Group and single-pid signals are issued concurrently, so a survivor
  // routinely loses its parent between the snapshot and this check --
  // strict comparison then skipped it for the whole pass.
  it('signals a tracked process whose parent died between the snapshot and the signal', async () => {
    const inspector = new SystemProcessTreeInspector('linux');
    const live = { pid: 4242, ppid: 1, pgid: 4242, sid: 0, startedAt: 'Mon Jul 28 10:59:31 2026', command: 'core' };
    (inspector as unknown as { snapshot: () => Promise<ProcessIdentity[]> }).snapshot = async () => [{ ...live }];
    // What we recorded while its parent was still alive.
    const tracked: ProcessIdentity = { ...live, ppid: 999 };

    const originalKill = process.kill;
    const killed: number[] = [];
    (process as unknown as { kill: (pid: number, signal?: string | number) => true }).kill = (pid) => {
      killed.push(pid);
      return true;
    };
    try {
      await inspector.signal(tracked, 'SIGTERM');
    } finally {
      (process as unknown as { kill: typeof originalKill }).kill = originalKill;
    }

    assert.deepStrictEqual(killed, [4242], 'expected the reparented process to still be signalled');
  });

  // The negative direction at the real inspector -- the only place in
  // this file that reaches an actual `process.kill`. Every other test of
  // the pre-signal revalidation pins the *positive* direction (ps threw,
  // reparented, argv changed -> still signal), and the recycled-pid test
  // above drives a fake inspector, so it never executes this code at all.
  // Without this, dropping the identity comparison here is invisible: a
  // stranger holding our old pid gets SIGKILLed and its whole group
  // negated.
  it('never signals a real process whose start identity does not match what we tracked', async () => {
    const inspector = new SystemProcessTreeInspector('linux');
    // Same pid, different process: started later, different parent/session.
    (inspector as unknown as { snapshot: () => Promise<ProcessIdentity[]> }).snapshot = async () => [
      { pid: 4244, ppid: 1, pgid: 4244, sid: 4244, startedAt: 'Tue Jul 29 08:00:00 2026', command: 'sshd' }
    ];
    const tracked: ProcessIdentity = {
      pid: 4244, ppid: 999, pgid: 4244, sid: 0, startedAt: 'Mon Jul 28 10:59:31 2026', command: 'core'
    };

    const originalKill = process.kill;
    const killed: number[] = [];
    (process as unknown as { kill: (pid: number, signal?: string | number) => true }).kill = (pid) => {
      killed.push(pid);
      return true;
    };
    try {
      await inspector.signal(tracked, 'SIGKILL');
      await inspector.signal(tracked, 'SIGKILL', { group: true });
    } finally {
      (process as unknown as { kill: typeof originalKill }).kill = originalKill;
    }

    assert.deepStrictEqual(killed, [], 'must not signal a pid, or negate its group, on a recycled identity');
  });

  // The exec case again, at the one call site with no group-union
  // backstop: `signal()` re-validates a tracked identity against a fresh
  // `ps` immediately before signalling, and a failed match there is a
  // silently skipped signal. Every other test of command non-invariance
  // is satisfied by re-adoption through the session union, so without
  // this one, putting `command` back into `sameIdentity` would ship green.
  it('signals a tracked process whose ps command line changed since it was tracked', async () => {
    const inspector = new SystemProcessTreeInspector('linux');
    const live = { pid: 4243, ppid: 1, pgid: 4243, sid: 0, startedAt: 'Mon Jul 28 10:59:31 2026', command: '/versions/3.4.7/bin/ruby core-session.rb' };
    (inspector as unknown as { snapshot: () => Promise<ProcessIdentity[]> }).snapshot = async () => [{ ...live }];
    // Captured before the shim exec'd: identical but for the argv.
    const tracked: ProcessIdentity = { ...live, command: 'bash /shims/ruby core-session.rb' };

    const originalKill = process.kill;
    const killed: number[] = [];
    (process as unknown as { kill: (pid: number, signal?: string | number) => true }).kill = (pid) => {
      killed.push(pid);
      return true;
    };
    try {
      await inspector.signal(tracked, 'SIGTERM');
    } finally {
      (process as unknown as { kill: typeof originalKill }).kill = originalKill;
    }

    assert.deepStrictEqual(killed, [4243], 'expected the process to be signalled despite its argv changing');
  });

  it('directly signals the owned Core when identity revalidation starts failing after discovery', async () => {
    let snapshots = 0;
    const directSignals: NodeJS.Signals[] = [];
    const inspector: ProcessTreeInspector = {
      snapshot: async () => {
        snapshots += 1;
        if (snapshots === 1) {
          return [{ pid: 100, ppid: 1, pgid: 100, sid: 100, startedAt: 'root' }];
        }
        throw new Error('ps failed');
      },
      signal: async () => undefined,
      terminateWindowsTree: async () => undefined
    };
    let signalCode: NodeJS.Signals | null = null;
    const fakeChild = {
      pid: 100,
      exitCode: null,
      get signalCode() {
        return signalCode;
      },
      kill: (signal: NodeJS.Signals) => {
        directSignals.push(signal);
        if (signal === 'SIGKILL') {
          signalCode = signal;
        }
        return true;
      }
    } as unknown as ChildProcess;

    await new SpawnedCoreProcess(fakeChild, 'linux', 1, 1, inspector).terminate();

    assert.deepStrictEqual(directSignals, ['SIGTERM', 'SIGKILL']);
  });
});
