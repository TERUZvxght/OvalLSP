import * as fs from 'fs';
import * as path from 'path';

export interface ServerLaunchConfig {
  command: string;
  args: string[];
}

export interface ResolveServerConfigInput {
  /** `ovallsp.ruby.command` setting, or null/undefined to use the default. */
  rubyCommand?: string | null;
  /** `ovallsp.server.path` setting, or null/undefined to use the bundled core. */
  serverPath?: string | null;
  /** Absolute path to this extension's install directory (`context.extensionPath`). */
  extensionRoot: string;
  /** Injectable for tests; defaults to the real filesystem. */
  existsSync?: (candidatePath: string) => boolean;
}

const DEFAULT_RUBY_COMMAND = 'ruby';

/**
 * Resolves the command used to spawn the Core Server for one workspace
 * folder. Kept free of the `vscode` module so it can run under plain Node
 * in unit tests, per docs/07-vscode-extension.md's "独立moduleにする" guidance
 * for environment resolution.
 *
 * `rubyCommand` is expected to already be the caller's own fully-resolved
 * choice (an explicit `ovallsp.ruby.command`/`ovallsp.rubyExecutablePath`
 * setting, or the result of `rubyResolver.resolveRuby` — see
 * `extension.ts`) — this function itself only ever falls back to the bare
 * `ruby` command, it doesn't run the version-manager search itself.
 */
export function resolveServerConfig(input: ResolveServerConfigInput): ServerLaunchConfig {
  const existsSync = input.existsSync ?? fs.existsSync;
  const rubyCommand =
    input.rubyCommand && input.rubyCommand.trim().length > 0 ? input.rubyCommand : DEFAULT_RUBY_COMMAND;

  const serverPath =
    input.serverPath && input.serverPath.trim().length > 0
      ? input.serverPath
      : defaultServerPath(input.extensionRoot, existsSync);

  return {
    command: rubyCommand,
    args: [serverPath, '--stdio']
  };
}

export type CoreClassification = 'bundled' | 'monorepo' | 'custom';

/**
 * Which of the three Core-selection cases this config resolved to --
 * shared by `versionInfo.ts`'s compatibility diagnostic (Task 023.2) and
 * `OvalLSP: Show Version Information`, so both agree with what
 * `resolveServerConfig` itself actually picked instead of re-deriving the
 * same bundled-vs-monorepo check a second, potentially-diverging way.
 */
export function classifyServerSelection(input: ResolveServerConfigInput): CoreClassification {
  if (input.serverPath && input.serverPath.trim().length > 0) {
    return 'custom';
  }
  const existsSync = input.existsSync ?? fs.existsSync;
  return existsSync(path.join(input.extensionRoot, 'core', 'bin', 'ovallsp')) ? 'bundled' : 'monorepo';
}

// A packaged VSIX has `core/` copied inside its own install directory
// (ADR-0004, "VSIXはCoreのsource/gem payloadを同梱する") -- checked
// first so a real end user, who never checked out this monorepo at all,
// gets a working Core Server out of the box ("repository checkoutなしで
// VSIXからCoreを起動できる"). Falls back to the monorepo-relative
// sibling path (the pre-Task-020 default) so `F5`-launched local
// development against this repo's own `core/` keeps working without
// requiring the packaging step first.
function defaultServerPath(extensionRoot: string, existsSync: (candidatePath: string) => boolean): string {
  const bundled = path.join(extensionRoot, 'core', 'bin', 'ovallsp');
  if (existsSync(bundled)) {
    return bundled;
  }
  return path.join(extensionRoot, '..', 'core', 'bin', 'ovallsp');
}
