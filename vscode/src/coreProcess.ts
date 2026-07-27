import { ChildProcess, execFile } from 'child_process';

const DEFAULT_TERM_GRACE_MS = 1000;
const DEFAULT_KILL_GRACE_MS = 250;

export interface CoreProcessHandle {
  terminate(): Promise<void>;
}

/**
 * Owns the Core process independently of vscode-languageclient. The
 * library cannot stop a client while initialize is still pending, so the
 * Extension must retain this handle to make restart/deactivation bounded.
 *
 * POSIX descendants are tracked and each process group is signalled, so
 * a Runtime Agent/Runner that deliberately creates another group is
 * reclaimed as well.
 */
export class SpawnedCoreProcess implements CoreProcessHandle {
  private termination?: Promise<void>;
  private readonly knownPids = new Set<number>();
  private readonly descendantMonitor?: NodeJS.Timeout;

  constructor(
    private readonly child: ChildProcess,
    private readonly platform: NodeJS.Platform = process.platform,
    private readonly termGraceMs: number = DEFAULT_TERM_GRACE_MS,
    private readonly killGraceMs: number = DEFAULT_KILL_GRACE_MS
  ) {
    if (child.pid !== undefined) {
      this.knownPids.add(child.pid);
    }
    if (platform !== 'win32') {
      this.descendantMonitor = setInterval(() => void this.refreshDescendants(), 200);
      this.descendantMonitor.unref();
      void this.refreshDescendants();
    }
  }

  terminate(): Promise<void> {
    this.termination ??= this.terminateOnce();
    return this.termination;
  }

  private async terminateOnce(): Promise<void> {
    try {
      if (this.descendantMonitor) {
        clearInterval(this.descendantMonitor);
      }
      await this.refreshDescendants();

      this.signalAll('SIGTERM');
      if (await this.waitForAllExit(this.termGraceMs)) {
        return;
      }

      this.signalAll('SIGKILL');
      await this.waitForAllExit(this.killGraceMs);
    } catch {
      // Teardown is best-effort and idempotent. A process that exited
      // between the liveness check and signal delivery, or one the OS no
      // longer permits us to signal, must not turn deactivation into an
      // unhandled rejection.
    }
  }

  private exited(): boolean {
    return this.child.exitCode !== null || this.child.signalCode !== null;
  }

  private signalAll(signal: NodeJS.Signals): void {
    if (this.platform !== 'win32') {
      // Descendants may deliberately start their own process group (the
      // observation Runner does). Signal every discovered group, deepest
      // processes first, then the Core group itself.
      [...this.knownPids].reverse().forEach((pid) => this.signalPid(pid, signal));
      return;
    }
    if (!this.exited()) {
      this.child.kill(signal);
    }
  }

  private signalPid(pid: number, signal: NodeJS.Signals): void {
    if (pid <= 0 || !this.processAlive(pid)) {
      return;
    }
    try {
      process.kill(-pid, signal);
      return;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ESRCH') {
        // The pid may not be a process-group leader. Fall through to
        // signalling that individual process.
      }
    }

    try {
      process.kill(pid, signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ESRCH') {
        throw error;
      }
    }
  }

  private async refreshDescendants(): Promise<void> {
    if (this.platform === 'win32' || this.knownPids.size === 0) {
      return;
    }
    const rows = await new Promise<string>((resolve) => {
      execFile('ps', ['-axo', 'pid=,ppid='], (error, stdout) => resolve(error ? '' : stdout));
    });
    const children = new Map<number, number[]>();
    rows.split('\n').forEach((row) => {
      const match = row.trim().match(/^(\d+)\s+(\d+)$/);
      if (!match) {
        return;
      }
      const pid = Number(match[1]);
      const ppid = Number(match[2]);
      const entries = children.get(ppid) ?? [];
      entries.push(pid);
      children.set(ppid, entries);
    });
    const queue = [...this.knownPids];
    while (queue.length > 0) {
      const parent = queue.shift()!;
      for (const child of children.get(parent) ?? []) {
        if (!this.knownPids.has(child)) {
          this.knownPids.add(child);
          queue.push(child);
        }
      }
    }
  }

  private processAlive(pid: number): boolean {
    try {
      process.kill(pid, 0);
      return true;
    } catch (error) {
      return (error as NodeJS.ErrnoException).code !== 'ESRCH';
    }
  }

  private waitForAllExit(timeoutMs: number): Promise<boolean> {
    const allExited = () => [...this.knownPids].every((pid) => !this.processAlive(pid));
    if (allExited()) {
      return Promise.resolve(true);
    }

    return new Promise((resolve) => {
      const deadline = Date.now() + timeoutMs;
      const poll = () => {
        if (allExited()) {
          resolve(true);
        } else if (Date.now() >= deadline) {
          resolve(false);
        } else {
          setTimeout(poll, 10);
        }
      };
      poll();
    });
  }

}
