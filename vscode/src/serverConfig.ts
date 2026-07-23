import * as path from 'path';

export interface ServerLaunchConfig {
  command: string;
  args: string[];
}

export interface ResolveServerConfigInput {
  /** `rslsp.ruby.command` setting, or null/undefined to use the default. */
  rubyCommand?: string | null;
  /** `rslsp.server.path` setting, or null/undefined to use the bundled core. */
  serverPath?: string | null;
  /** Absolute path to this extension's install directory (`context.extensionPath`). */
  extensionRoot: string;
}

const DEFAULT_RUBY_COMMAND = 'ruby';

/**
 * Resolves the command used to spawn the Core Server for one workspace
 * folder. Kept free of the `vscode` module so it can run under plain Node
 * in unit tests, per docs/07-vscode-extension.md's "独立moduleにする" guidance
 * for environment resolution.
 */
export function resolveServerConfig(input: ResolveServerConfigInput): ServerLaunchConfig {
  const rubyCommand =
    input.rubyCommand && input.rubyCommand.trim().length > 0 ? input.rubyCommand : DEFAULT_RUBY_COMMAND;

  const serverPath =
    input.serverPath && input.serverPath.trim().length > 0
      ? input.serverPath
      : path.join(input.extensionRoot, '..', 'core', 'bin', 'rslsp');

  return {
    command: rubyCommand,
    args: [serverPath, '--stdio']
  };
}
