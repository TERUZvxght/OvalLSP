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

/**
 * Task 023.8: a vendored native extension (prism.bundle/rbs_extension.bundle,
 * ADR-0004) is compiled by whatever Ruby happened to run `bundle install`
 * at packaging time, and macOS' `rbenv`/`ruby-build`-compiled Rubies
 * record their own `libruby` dependency as an **absolute, non-relocatable**
 * path in the compiled binary's `LC_LOAD_DYLIB` (confirmed via `otool -L`/
 * `-l`: no `LC_RPATH` fallback entry exists at all). Reproduced directly:
 * a `prism.bundle` built under one Ruby 3.4.x installation raises
 * `LoadError: linked to incompatible .../libruby.3.4.dylib` under a
 * *different* Ruby 3.4.x installation at a different absolute path --
 * even though ADR-0005's own compatibility check (engine + major.minor +
 * platform only) reports them as compatible. Since a real end user's
 * Ruby is essentially guaranteed to live at a different absolute path
 * than whatever machine packaged this VSIX (a different username alone
 * is enough), this is not a rare edge case -- it's the common case.
 *
 * The fix is `DYLD_LIBRARY_PATH`: macOS' dynamic linker checks it, by
 * *leaf filename*, before ever consulting a dependent library's own
 * recorded path -- reproduced directly as well: setting
 * `DYLD_LIBRARY_PATH` to the *actually-running* Ruby's own `lib`
 * directory made the same otherwise-incompatible `prism.bundle` load
 * correctly. This function derives that directory from the resolved
 * Ruby executable's own path, using the universal `<prefix>/bin/ruby` +
 * `<prefix>/lib/libruby*` layout every version manager this project
 * supports (mise/asdf/rbenv/Homebrew) follows -- so it works
 * independent of *which* one actually resolved the running Ruby.
 *
 * Returns `undefined` when there's nothing useful to derive: any
 * platform other than darwin (this Preview's only target; Linux/Windows
 * use their own, different dynamic-linker environment variables and are
 * out of scope here), or a `rubyCommand` that isn't an absolute
 * filesystem path (a bare `"ruby"` resolved via `PATH` search at spawn
 * time, rather than a version manager's own absolute shim/install
 * path) -- there's no path to derive a sibling `lib/` directory from in
 * that case, and PATH-based resolution is no worse off than before this
 * fix existed.
 */
export function deriveNativeExtensionLibraryPath(rubyCommand: string, platform: NodeJS.Platform): string | undefined {
  if (platform !== 'darwin' || !path.isAbsolute(rubyCommand)) {
    return undefined;
  }
  // .../<prefix>/bin/ruby -> .../<prefix>/lib
  const prefix = path.dirname(path.dirname(rubyCommand));
  return path.join(prefix, 'lib');
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
