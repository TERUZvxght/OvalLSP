import { ChildProcess, execFile } from 'child_process';

const DEFAULT_TERM_GRACE_MS = 1000;
const DEFAULT_KILL_GRACE_MS = 250;
const SNAPSHOT_TIMEOUT_MS = 1000;
const SNAPSHOT_MAX_BUFFER_BYTES = 32 * 1024 * 1024;

export interface CoreProcessHandle {
  terminate(): Promise<void>;
}

export interface ProcessIdentity {
  pid: number;
  ppid: number;
  pgid: number;
  sid: number;
  startedAt: string;
  command?: string;
}

export interface ProcessTreeInspector {
  snapshot(): Promise<ProcessIdentity[]>;
  signal(identity: ProcessIdentity, signal: NodeJS.Signals, options?: { group?: boolean }): Promise<void>;
  terminateWindowsTree(pid: number): Promise<void>;
}

export class SystemProcessTreeInspector implements ProcessTreeInspector {
  private inFlight?: Promise<ProcessIdentity[]>;

  constructor(private readonly platform: NodeJS.Platform) {}

  // Callers that overlap share one `ps`. `signal()` re-snapshots per
  // target and `signalAll` fires every target concurrently, twice per
  // terminate(), so a workspace with a couple of dozen tracked processes
  // otherwise launches that many simultaneous system-wide `ps` runs
  // against a 1s timeout -- and a timeout there is not a slow signal but
  // a *skipped* one, since the catch treats an unverifiable identity as
  // "do not signal". The same "quietly did nothing" failure the maxBuffer
  // cap exists to prevent, arriving by way of self-inflicted load.
  //
  // Sharing costs no freshness that matters: every sharer wants the
  // process table as of now, and they all asked at the same instant.
  snapshot(): Promise<ProcessIdentity[]> {
    if (this.platform === 'win32') {
      return Promise.resolve([]);
    }
    if (this.inFlight) {
      return this.inFlight;
    }
    const query = this.querySnapshot();
    this.inFlight = query;
    const clear = (): void => {
      if (this.inFlight === query) {
        this.inFlight = undefined;
      }
    };
    query.then(clear, clear);
    return query;
  }

  private querySnapshot(): Promise<ProcessIdentity[]> {
    return new Promise((resolve, reject) => {
      execFile(
        'ps',
        ['-axo', 'pid=,ppid=,pgid=,sess=,lstart=,command='],
        // `lstart` is formatted according to LC_TIME, and execFile
        // inherits the extension host's environment. Under any non-English
        // locale the column becomes e.g. "火  7/28 10:59:31 2026" or
        // "Di. 28 Juli ...", which the ASCII-only `\w{3}` pattern below
        // matches on zero rows -- so `ps` succeeded, every row was
        // discarded, and the owner concluded the machine had no processes
        // at all. Everything downstream then quietly did nothing: no root,
        // no descendants, no signals, and `waitForAllExit` returning true
        // immediately. Pinning LC_ALL makes the format we parse the format
        // we asked for, instead of whatever the user's locale renders.
        // `maxBuffer` is not a tuning knob here, it is a correctness
        // requirement. This is a system-wide `ps` carrying the full
        // `command=` column, and Node's 1 MiB default is a *hard failure*
        // (ERR_CHILD_PROCESS_STDIO_MAXBUFFER), not a truncation: a
        // developer with enough Electron/Chrome/JetBrains helpers running
        // crosses it and then every snapshot rejects forever, leaving the
        // owner permanently blind and leaking every Runtime Agent for the
        // rest of the login session. A real machine measured ~176 KB over
        // 606 rows with single rows near 6 KB, so the cap below is ~190x
        // observed and load-independent in practice.
        {
          timeout: SNAPSHOT_TIMEOUT_MS,
          maxBuffer: SNAPSHOT_MAX_BUFFER_BYTES,
          env: { ...process.env, LC_ALL: 'C' }
        },
        (error, stdout) => {
          if (error) {
            // A failed/slow ps query is not evidence that every tracked
            // process exited. Reject so the owner preserves its last
            // identity snapshot and retries.
            reject(error);
            return;
          }
          const rows = stdout.split('\n').flatMap((row) => {
            const match = row.trim().match(
              /^(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+\d+:\d+:\d+\s+\d{4})\s+(.*)$/
            );
            return match
              ? [{
                  pid: Number(match[1]),
                  ppid: Number(match[2]),
                  pgid: Number(match[3]),
                  sid: Number(match[4]),
                  startedAt: match[5],
                  command: match[6]
                }]
              : [];
          });
          if (rows.length === 0 && stdout.trim().length > 0) {
            // `ps` printed something we could not parse at all. That is a
            // parser/environment problem, never evidence that no process
            // exists -- and believing it would silently retire every
            // tracked process. Treated exactly like a failed query: keep
            // the last good snapshot and retry.
            reject(new Error('ps returned output that could not be parsed'));
            return;
          }
          resolve(rows);
        }
      );
    });
  }

  // `group` decides whether the process *group* may be signalled
  // (`kill(-pgid)`) or only this single pid. It is never inferred here:
  // a pgid is safe to negate only once the caller has proven the group
  // is one it created, and only the caller knows that. Defaults to
  // single-pid, the option that cannot harm a bystander.
  async signal(
    identity: ProcessIdentity,
    signal: NodeJS.Signals,
    { group = false }: { group?: boolean } = {}
  ): Promise<void> {
    // Verify start identity immediately before signalling. A numeric PID
    // may have been recycled since an earlier descendant snapshot.
    try {
      const current = (await this.snapshot()).find((entry) => entry.pid === identity.pid);
      // sameTrackedIdentity, matching what refreshDescendantsOnce uses to
      // keep a process tracked: it tolerates the ppid becoming 1 when the
      // parent dies. Insisting on sameIdentity here meant that a survivor
      // reparented *between* the snapshot and this signal -- which the
      // concurrent group/pid signalling below makes routine -- failed
      // revalidation and was skipped for the whole pass.
      if (!current || !sameTrackedIdentity(current, identity)) {
        return;
      }
    } catch {
      // A stale PID/PGID can be reused after the original process exits.
      // Without a fresh identity snapshot, signalling it would risk
      // terminating an unrelated process group.
      return;
    }
    if (!group) {
      try {
        process.kill(identity.pid, signal);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== 'ESRCH') {
          throw error;
        }
      }
      return;
    }
    try {
      process.kill(-identity.pgid, signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ESRCH') {
        return;
      }
      try {
        process.kill(identity.pid, signal);
      } catch (fallbackError) {
        if ((fallbackError as NodeJS.ErrnoException).code !== 'ESRCH') {
          throw fallbackError;
        }
      }
    }
  }

  terminateWindowsTree(pid: number): Promise<void> {
    return new Promise((resolve, reject) => {
      execFile(
        'taskkill',
        ['/PID', String(pid), '/T', '/F'],
        { timeout: SNAPSHOT_TIMEOUT_MS, windowsHide: true },
        (error) => (error ? reject(error) : resolve())
      );
    });
  }
}

// `command` is deliberately NOT compared, here or in sameRootProcess.
// It looks like a free extra check and is in fact the opposite: the
// COMMAND column is not invariant over a process's life. It changes on
// exec() -- every version-manager shim (mise/asdf/rbenv) is a shell
// script that execs the real ruby, so the argv `ps` reports a moment
// after spawn is not the argv it reports later -- and it changes to
// "<defunct>" while a process sits reaped-pending, a window `ps` samples
// routinely during teardown. Both were read as "this pid now belongs to
// someone else", which drops session and group ownership permanently
// (the captured identity is never refreshed on that branch, so every
// later snapshot mismatches too). Measured with a real rbenv shim: the
// owner tracked *nothing*, not even the live root, and the in-session
// survivor was still running after terminate().
//
// pid + start time is the identity, and the remaining fields below are
// what make a recycled pid detectable: a stranger would have to match
// our ppid, pgid, sid and start second exactly.
function sameIdentity(left: ProcessIdentity, right: ProcessIdentity): boolean {
  return (
    left.pid === right.pid &&
    left.ppid === right.ppid &&
    left.pgid === right.pgid &&
    left.sid === right.sid &&
    left.startedAt === right.startedAt
  );
}

// The root is identified by the two fields that do not legitimately
// change during its life: pid and start time. Its ppid changes when the
// parent goes away, and its pgid changes the moment `core-session.rb`
// calls setsid -- so comparing those, as sameIdentity does, would reject
// our own process precisely when it became interesting. `command` is
// excluded for the reason above; `rootObservedAbsent` is what covers a
// pid recycled too fast for `lstart`'s one-second resolution to show.
function sameRootProcess(current: ProcessIdentity, captured: ProcessIdentity): boolean {
  return current.pid === captured.pid && current.startedAt === captured.startedAt;
}

function sameTrackedIdentity(current: ProcessIdentity, tracked: ProcessIdentity): boolean {
  if (sameIdentity(current, tracked)) {
    return true;
  }
  return current.ppid === 1 && sameIdentity({ ...current, ppid: tracked.ppid }, tracked);
}

/**
 * Owns the Core process independently of vscode-languageclient.
 *
 * POSIX descendants are tracked by PID plus process start identity, not
 * PID alone. This preserves separately-grouped Runtime Agent/Runner
 * processes without risking an unrelated process after PID reuse.
 */
export class SpawnedCoreProcess implements CoreProcessHandle {
  private termination?: Promise<void>;
  private readonly known = new Map<number, ProcessIdentity>();
  private ownedSessionId?: number;
  // The root's identity as captured while it was still alive. Every
  // later lookup of the root row is validated against it, so a recycled
  // pid can never be mistaken for our Core -- `byPid.get(child.pid)`
  // matches on the number alone, and this handle can outlive the process
  // by a long way.
  private rootIdentity?: ProcessIdentity;
  // Set by any *successful* snapshot that did not list our pid. That is
  // positive evidence the number was free at a known moment, so a row
  // appearing at it afterwards can only be a different process.
  private rootObservedAbsent = false;
  // The process group our own Core leads, recorded once setsid has been
  // observed on a *validated* root. Kept after the root dies so its
  // survivors stay owned, and dropped if our pid turns out to have been
  // recycled.
  private ownedGroupId?: number;
  private descendantMonitor?: NodeJS.Timeout;
  private refreshInFlight?: Promise<void>;

  static forDedicatedSession(
    child: ChildProcess,
    platform: NodeJS.Platform = process.platform
  ): SpawnedCoreProcess {
    return new SpawnedCoreProcess(
      child, platform, DEFAULT_TERM_GRACE_MS, DEFAULT_KILL_GRACE_MS,
      new SystemProcessTreeInspector(platform), true
    );
  }

  constructor(
    private readonly child: ChildProcess,
    private readonly platform: NodeJS.Platform = process.platform,
    private readonly termGraceMs: number = DEFAULT_TERM_GRACE_MS,
    private readonly killGraceMs: number = DEFAULT_KILL_GRACE_MS,
    private readonly inspector: ProcessTreeInspector = new SystemProcessTreeInspector(platform),
    dedicatedSession = false
  ) {
    if (platform !== 'win32') {
      // core-session.rb calls setsid before loading any server code, so
      // its session id is structurally the spawned PID. Record that fact
      // synchronously: even if Core exits before the first `ps` snapshot,
      // a surviving Runtime Agent/runner in that session remains owned.
      if (dedicatedSession && child.pid !== undefined) {
        this.ownedSessionId = child.pid;
      }
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

      const rootPid = this.child.pid;
      if (this.platform === 'win32') {
        if (rootPid !== undefined && !this.exited()) {
          try {
            await this.inspector.terminateWindowsTree(rootPid);
          } catch {
            if (!this.exited()) {
              this.child.kill('SIGKILL');
            }
          }
        }
        return;
      }

      await this.signalAll('SIGTERM');
      if (await this.waitForAllExit(this.termGraceMs)) {
        return;
      }

      // Re-snapshot after TERM: descendants can fork or move into a new
      // process group while shutdown handlers are running.
      await this.refreshDescendants();
      await this.signalAll('SIGKILL');
      await this.waitForAllExit(this.killGraceMs);
    } catch {
      // Teardown remains best-effort and idempotent.
    }
  }

  private exited(): boolean {
    return this.child.exitCode !== null || this.child.signalCode !== null;
  }

  private refreshDescendants(): Promise<void> {
    if (this.platform === 'win32') {
      return Promise.resolve();
    }
    if (this.refreshInFlight) {
      return this.refreshInFlight;
    }
    const refresh = this.refreshDescendantsOnce().finally(() => {
      if (this.refreshInFlight === refresh) {
        this.refreshInFlight = undefined;
      }
    });
    this.refreshInFlight = refresh;
    return refresh;
  }

  private async refreshDescendantsOnce(): Promise<void> {
    const snapshot = await this.inspector.snapshot().catch(() => undefined);
    if (!snapshot) {
      return;
    }
    const byPid = new Map(snapshot.map((entry) => [entry.pid, entry]));
    const rootPid = this.child.pid;
    const rootRow = rootPid === undefined ? undefined : byPid.get(rootPid);
    // A row for our pid is only *our* root if it matches the identity we
    // captured while the process was alive. Without that check, a pid
    // recycled after Core exited -- this handle keeps polling, and its own
    // `ps` calls accelerate pid wraparound toward its own number -- would
    // be adopted as the root, and any group that process happened to lead
    // would be adopted with it and killed on the next terminate().
    let root: ProcessIdentity | undefined;
    // Recorded at the END of this pass, deliberately: everything below
    // asks "did a snapshot *before* this one show the pid free", and
    // setting it here would answer yes for the very snapshot that first
    // reveals our exited root -- the one pass that still has to adopt the
    // survivors it left behind.
    const rootAbsentNow = !rootRow;
    if (rootRow) {
      if (!this.rootIdentity && this.rootObservedAbsent) {
        // We never captured an identity to compare against, and we have
        // watched this pid be *unoccupied*. Whatever holds it now is not
        // our Core, and adopting it would hand `signalAll` a stranger's
        // pgid to negate -- the recycled-pid defence below cannot fire,
        // because it needs a captured identity it never got.
        //
        // Reachable exactly in the case dedicated-session ownership was
        // added for: Core crashes inside the ~30-50ms before the first
        // `ps` returns, the client exhausts its restart budget, and the
        // handle sits in `folder.process` until deactivate hours later,
        // by which time the pid has been recycled by any group leader --
        // a login shell, an sshd session leader, another editor's server.
        this.ownedSessionId = undefined;
        this.ownedGroupId = undefined;
      } else if (!this.rootIdentity) {
        // Genuine first observation: no snapshot has yet shown this pid
        // free, so the row can only be the process we spawned. Captured
        // even if it has already exited -- a crash that fast is exactly
        // what session ownership exists to cover.
        this.rootIdentity = rootRow;
        root = rootRow;
      } else if (sameRootProcess(rootRow, this.rootIdentity)) {
        // Still our process. Refresh the captured copy so a post-setsid
        // pgid change is picked up rather than treated as an impostor.
        this.rootIdentity = rootRow;
        root = rootRow;
      } else {
        // Positive evidence that our pid now belongs to someone else.
        // Ownership derived from that number is worthless from here on,
        // and acting on it would kill a stranger's process group.
        this.ownedSessionId = undefined;
        this.ownedGroupId = undefined;
      }
    }
    if (root && root.sid === root.pid) {
      this.ownedSessionId = root.sid;
    }
    // setsid makes the leader its own process-group leader. Observing
    // that on our validated root is what proves the group is ours; before
    // it, the root is still in the extension host's group.
    if (root && root.pgid === root.pid) {
      this.ownedGroupId = root.pgid;
    }
    // Ownership is the UNION of every signal this platform can actually
    // report -- never one of them short-circuiting the others.
    //
    // An earlier version returned here as soon as `ownedSessionId` was
    // set, keeping only `entry.sid === ownedSessionId` matches. On macOS
    // -- the only target this Preview ships -- that silently owned
    // *nothing*: `ps -o sess=` reports the session as `0` for every
    // process (verified: 0 of 578 rows on a real machine report a
    // non-zero `sess`, while Ruby's own `Process.getsid` reports the real
    // sid for those same processes). `ownedSessionId` is the spawned PID,
    // so no row ever matched, `known` was cleared on every refresh, and
    // the PPID walk below -- whose own comment already documents this
    // exact Darwin behaviour -- became unreachable. The result was
    // strictly worse than having no session tracking at all: a Runtime
    // Agent that outlived a killed Core was never signalled and leaked
    // for the rest of the login session.
    //
    // `setsid` makes the leader's pid, pgid and sid all equal, so on
    // Darwin the process *group* carries exactly the membership the
    // session was supposed to identify, and `ps` does report pgid
    // correctly. Matching either field keeps Linux (real sids) and macOS
    // (pgid only) working through the same code path, and the PPID walk
    // still catches a descendant that left the group via its own
    // setsid/setpgid.
    for (const [pid, identity] of this.known) {
      const current = byPid.get(pid);
      if (!current || !sameTrackedIdentity(current, identity)) {
        this.known.delete(pid);
      } else {
        this.known.set(pid, current);
      }
    }
    // Ownership derived from our pid may EXPAND only while no earlier
    // snapshot has shown that pid free. Once one has, the number is no
    // longer evidence of anything: a stranger can have taken it, led a
    // new group, and exited, leaving its children behind with our old
    // pgid and *no row at the pid itself* -- so neither identity check
    // above can fire, and the union below would adopt those children and
    // `kill(-pgid)` them on the next terminate(). Verified: two unrelated
    // user processes SIGTERMed then SIGKILLed by a handle whose Core had
    // been gone for hours.
    //
    // Already-tracked members are unaffected (the prune loop above keeps
    // revalidating them) and the PPID walk below still follows anything
    // they spawn, so a live survivor's own descendants are still reached.
    // The one pass that matters for adoption -- the first one that sees
    // our root gone -- still runs this, because the flag records only
    // *earlier* passes.
    if (this.ownedSessionId !== undefined && !this.rootObservedAbsent) {
      snapshot.forEach((entry) => {
        // `sid` is a real session id where the platform reports one, so
        // it identifies our session on its own. `pgid` only does so once
        // setsid has been *observed* -- before that it is still the
        // extension host's group, and every process in it would be
        // adopted as ours.
        const bySession = entry.sid === this.ownedSessionId;
        // `ownedSessionId` is our own child's pid, recorded synchronously
        // at spawn, so a group led by it can only be the one setsid
        // created for us: the extension host's group leader predates that
        // pid and still holds it, so the two can never collide.
        //
        // Matching against `ownedGroupId` instead left the comment above
        // true only on Linux. `ownedGroupId` is assigned solely from a
        // *validated root row*, so when Core exited before any snapshot
        // caught it, it stayed undefined -- and on Darwin, where every
        // `sess` is 0, `bySession` never matches either. The net effect on
        // the one platform this Preview ships was that nothing was owned
        // at all and an in-group survivor leaked: exactly the failure the
        // comment claims was designed out. Recycled-pid safety comes from
        // the root identity check above, which drops `ownedSessionId` the
        // moment our pid is shown to belong to someone else.
        const byGroup = entry.pgid === this.ownedSessionId;
        if (bySession || byGroup) {
          this.known.set(entry.pid, entry);
        }
      });
    }
    if (root && !this.exited()) {
      this.known.set(root.pid, root);
    }
    const children = new Map<number, ProcessIdentity[]>();
    snapshot.forEach((entry) => {
      const values = children.get(entry.ppid) ?? [];
      values.push(entry);
      children.set(entry.ppid, values);
    });
    const queue = [...this.known.values()];
    while (queue.length > 0) {
      const parent = queue.shift()!;
      for (const child of children.get(parent.pid) ?? []) {
        if (!this.known.has(child.pid)) {
          this.known.set(child.pid, child);
          queue.push(child);
        }
      }
    }

    // Nothing left to own: the Core process is gone and no descendant
    // survived it. Polling on past this point serves no purpose and is
    // actively harmful -- a handle can outlive its process by a long
    // time (vscode-languageclient exhausting its restart budget, a
    // client kept until deactivate), and every 200ms tick is another
    // chance for our old pid to have been recycled by an unrelated
    // process. Each tick also spawns a `ps`, which itself consumes pids
    // and hurries that wraparound along.
    if (this.exited() && this.known.size === 0) {
      // Retire the pid-derived authority along with the polling: with
      // nothing of ours left, our old pid grants nothing. The expansion
      // gate above is what actually closes the stranger-adoption defect
      // (and is what the two regression tests pin); this states the same
      // invariant at the other end so the fields cannot outlive their
      // meaning.
      this.ownedSessionId = undefined;
      this.ownedGroupId = undefined;
      if (this.descendantMonitor) {
        clearInterval(this.descendantMonitor);
        this.descendantMonitor = undefined;
      }
    }
    if (rootAbsentNow) {
      this.rootObservedAbsent = true;
    }
  }

  private async signalAll(signal: NodeJS.Signals): Promise<void> {
    const identities = [...this.known.values()].reverse();
    // A process group is negated only when it is the one setsid created
    // for us, and only once that was actually observed. Everything else
    // -- including our own root during the window before setsid runs, when
    // its pgid is still the extension host's -- is signalled by pid.
    // Getting this wrong is not a leak but a catastrophe: `kill(-pgid)`
    // on the host's group terminates VS Code itself.
    const ownedGroup = this.ownedGroupId;
    const groupRepresentatives = new Map<number, ProcessIdentity>();
    identities.forEach((identity) => {
      if (ownedGroup !== undefined && identity.pgid === ownedGroup) {
        groupRepresentatives.set(identity.pgid, identity);
      }
    });

    // allSettled, not all: SystemProcessTreeInspector#signal deliberately
    // rethrows anything that is not ESRCH (EPERM is reachable for a
    // descendant that changed uid). With Promise.all, one such rejection
    // propagated out of the SIGTERM pass, skipping this.child.kill and the
    // entire waitForAllExit/SIGKILL escalation below -- terminate() then
    // resolved as though it had succeeded, with the tree still alive.
    await Promise.allSettled([
      ...[...groupRepresentatives.values()].map(
        (identity) => this.inspector.signal(identity, signal, { group: true })
      ),
      // Every member is also signalled directly. The group signal above
      // is issued through a single representative, and if that one
      // process happens to exit between the snapshot and the inspector's
      // own re-verification the whole group would otherwise be skipped
      // for this pass, leaving survivors unsignalled.
      ...identities.map((identity) => this.inspector.signal(identity, signal, { group: false }))
    ]);
    if (!this.exited()) {
      this.child.kill(signal);
    }
  }

  private async waitForAllExit(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    do {
      await this.refreshDescendants();
      if (this.exited() && this.known.size === 0) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, 25));
    } while (Date.now() < deadline);
    return false;
  }
}
