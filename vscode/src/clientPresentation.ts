/**
 * Two decisions from `extension.ts`, kept free of any `vscode` import so
 * they can be unit-tested (024.17, the same move 024.10 made for
 * `clientTeardown.ts`).
 *
 * `extension.ts` imports `vscode`, which the unit suite cannot load, so
 * anything living there is covered only by the integration suite — which
 * runs in no workflow. These two are the ones a user notices and neither
 * needs `vscode`: which files the language client attaches to, and what
 * the status bar says.
 */

export interface DocumentFilter {
  scheme: string;
  language?: string;
  pattern: string;
}

/**
 * Which documents the language client attaches to, for one workspace
 * folder.
 *
 * Two filters, not one. Ruby is matched by *language id*, because VS Code
 * assigns one and a user may have `.rake`/`Gemfile` mapped to it. ERB is
 * matched by *extension*, because VS Code assigns no built-in language id
 * to `.erb` — requiring another extension to register one first would
 * make controller-to-view propagation silently unreachable in a plain
 * install (docs/design/tasks/008-controller-view-propagation.md).
 *
 * Both are scoped to the folder's own path: a multi-root workspace runs
 * one client per folder, and an unscoped selector would make every client
 * answer for every folder's files.
 */
export function documentSelectorFor(folderPath: string): DocumentFilter[] {
  return [
    { scheme: 'file', language: 'ruby', pattern: `${folderPath}/**/*` },
    { scheme: 'file', pattern: `${folderPath}/**/*.erb` }
  ];
}

export interface StatusPresentation {
  visible: boolean;
  text?: string;
}

/**
 * The four states `ovallsp/status` reports, in the words the status bar
 * shows. Kept as a table so a state added on the server side that nobody
 * mapped here is visible as a raw name rather than as nothing at all.
 */
export const STATUS_LABELS: Record<string, string> = {
  indexing: '$(sync~spin) OvalLSP: Indexing',
  'ready-static': '$(check) OvalLSP: Ready (static)',
  'ready-rails': '$(check) OvalLSP: Ready (Rails)',
  'agent-unavailable': '$(warning) OvalLSP: Agent unavailable'
};

export const STATUS_ERROR_TEXT = '$(error) OvalLSP: Configuration error';

/**
 * What the status bar should show, given what the poll found.
 *
 * Three outcomes, and the distinction between the last two is the point:
 * no client for the active editor's folder means OvalLSP is not running
 * *here*, which is not a problem to report — the item hides. A client
 * that failed to answer is a problem, and says so rather than hiding,
 * because a silently absent status bar reads as "fine".
 *
 * An unrecognised state renders its own name rather than falling back to
 * the error text: the server said something, and reporting a
 * configuration error for it would be a lie.
 */
export function statusPresentation(outcome: {
  hasClient: boolean;
  state?: string;
  failed?: boolean;
}): StatusPresentation {
  if (!outcome.hasClient) {
    return { visible: false };
  }
  if (outcome.failed || outcome.state === undefined) {
    return { visible: true, text: STATUS_ERROR_TEXT };
  }
  return { visible: true, text: STATUS_LABELS[outcome.state] ?? `OvalLSP: ${outcome.state}` };
}
