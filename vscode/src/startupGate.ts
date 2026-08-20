// Whether a Core Server may be started at all, decided before anything is
// spawned.
//
// `024.55`: four documents said this extension "stops before sending any
// feature request" on a mismatch and shows a diagnostic "instead of a
// degraded session". It did not stop. Both deciders logged, raised an
// error notification, and fell through to `client.start()` -- so a Core
// whose payload hash did not match served hover, completion and go to
// definition while the user was told they had been protected from
// exactly that.
//
// A function rather than an `if` inside the start callback, for the
// reason `024.55` gives for why this was not fixed sooner: refusing to
// start is a behaviour change with a real failure mode of its own, and a
// false positive locks the user out of the extension entirely. A decision
// that can lock someone out is one that gets its own name and its own
// tests; `extension.ts` needs VS Code to run and has none.
export interface PreStartProbe {
  readonly compatible: boolean;
  readonly reason?: string;
}

export interface PreStartVerdict {
  /** Whether `client.start()` may be called. */
  readonly start: boolean;
  /** Written to the output channel when the verdict refuses. */
  readonly logLine: string;
  /** Shown to the user, or undefined when there is nothing to say. */
  readonly notification?: string;
}

export function decidePreStart(probe: PreStartProbe, folderName: string): PreStartVerdict {
  if (probe.compatible) {
    return { start: true, logLine: `OvalLSP: bundled Core payload is loadable for ${folderName}.` };
  }

  // A refusal the user cannot act on is a dead end, and the probe is
  // allowed to be terse -- so the absence of a reason is stated rather
  // than left as an empty line.
  const reason = probe.reason && probe.reason.length > 0 ? probe.reason : 'no reason was reported';

  return {
    start: false,
    logLine: `OvalLSP: not starting the Core Server for ${folderName} -- ${reason}`,
    // "did not start" rather than "is incompatible": by the time this is
    // shown, the probe has established that the selected Ruby can load
    // neither the bundled payload nor its own `prism`/`rbs` -- including
    // on the path where the version query failed, which 0.2.10 made ask
    // the dependency probe before it becomes fatal. So the Core would
    // fail on `require`. Saying it did not start is both the true thing
    // and the actionable one.
    //
    // The reason is included: this used to name only the bundled
    // dependencies, which is categorically wrong for the query-failure
    // path and left the user nothing to act on.
    notification:
      `OvalLSP: the Core Server for ${folderName} did not start -- ${reason} ` +
      'See the OvalLSP output channel for details.'
  };
}
