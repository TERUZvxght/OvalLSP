import * as path from 'path';

export interface RubyResolutionStep {
  /** Which strategy this entry represents, in priority order. */
  strategy: string;
  /** The candidate path this strategy would use, or null if it had nothing to try. */
  candidate: string | null;
  /** Whether `candidate` actually existed on disk and was picked. */
  matched: boolean;
  /** Human-readable explanation, shown verbatim in "Show Environment Diagnostics". */
  reason: string;
}

export interface RubyResolution {
  executable: string;
  /** Every strategy tried, in priority order, whether or not it matched — the
   * full trail "Ruby executable選択理由を診断画面で確認できる" needs. */
  steps: RubyResolutionStep[];
}

export interface RubyResolverEnv {
  platform: NodeJS.Platform;
  /** `process.env.HOME` (POSIX) or `process.env.USERPROFILE` (Windows). */
  home: string | undefined;
  /** `process.env.PATH`, using this platform's own separator already. */
  pathEnv: string | undefined;
  existsSync: (candidatePath: string) => boolean;
}

const WINDOWS_RUBY_INSTALLER_GLOBS = ['C:\\Ruby33-x64', 'C:\\Ruby32-x64', 'C:\\Ruby31-x64', 'C:\\Ruby30-x64'];

function exeName(name: string, env: RubyResolverEnv): string {
  return env.platform === 'win32' ? `${name}.exe` : name;
}

function pathEntries(env: RubyResolverEnv): string[] {
  const separator = env.platform === 'win32' ? ';' : ':';
  return (env.pathEnv ?? '').split(separator).filter((entry) => entry.length > 0);
}

/**
 * Resolves the Ruby executable to launch Core Server with, following
 * docs/design/tasks/020-vsix-packaging-and-ruby-environment-resolution.md's
 * priority order:
 *
 *   1. explicit `ovallsp.rubyExecutablePath`
 *   2. mise
 *   3. asdf
 *   4. rbenv
 *   5. chruby
 *   6. Homebrew (`/opt/homebrew`, macOS only -- Task 023, see its own docs)
 *   7. PATH
 *   8. Windows RubyInstaller locations
 *
 * "VS Code terminal/environment integration" (the design doc's own #2) is
 * deliberately not a separate strategy here: VS Code's extension host
 * process already inherits the user's resolved shell PATH on
 * macOS/Linux (its own internal "fix path on macOS" mechanism), so by the
 * time this function runs, `env.pathEnv` *is* that already-resolved
 * PATH — a second, separate shell-spawning strategy would just re-derive
 * the same PATH a second time. See ADR-0004.
 *
 * Pure and free of the `vscode` module (same reasoning as
 * `serverConfig.ts`) so it runs under plain Node in unit tests, with an
 * injectable `existsSync` so no test ever touches the real filesystem.
 * Never spawns a shell/subprocess itself — every version-manager
 * strategy here only reads well-known on-disk shim/version-directory
 * layouts, kept intentionally cheap and synchronous, since this may run
 * once per workspace folder at startup.
 */
export function resolveRuby(env: RubyResolverEnv): RubyResolution {
  const steps: RubyResolutionStep[] = [];

  const record = (strategy: string, candidate: string | null, reason: string): string | null => {
    const matched = candidate !== null && env.existsSync(candidate);
    steps.push({ strategy, candidate, matched, reason });
    return matched ? candidate : null;
  };

  return {
    executable: pickExecutable(env, record),
    steps
  };
}

function pickExecutable(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string {
  return (
    miseRuby(env, record) ??
    asdfRuby(env, record) ??
    rbenvRuby(env, record) ??
    chrubyRuby(env, record) ??
    homebrewRuby(env, record) ??
    pathRuby(env, record) ??
    windowsInstallerRuby(env, record) ??
    'ruby'
  );
}

/**
 * Tier 1 (explicit override) is handled by the caller
 * (`serverConfig.ts`'s `rubyCommand` input) *before* ever calling
 * `resolveRuby` at all — an explicit setting short-circuits every one of
 * these strategies outright, so it isn't one of `resolveRuby`'s own
 * `steps` (there'd be nothing left to explain).
 */
function miseRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (!env.home) {
    return record('mise', null, 'no HOME/USERPROFILE to locate ~/.local/share/mise');
  }
  const candidate = path.join(env.home, '.local', 'share', 'mise', 'shims', exeName('ruby', env));
  return record('mise', candidate, `mise shim at ${candidate}`);
}

function asdfRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (!env.home) {
    return record('asdf', null, 'no HOME/USERPROFILE to locate ~/.asdf');
  }
  const candidate = path.join(env.home, '.asdf', 'shims', exeName('ruby', env));
  return record('asdf', candidate, `asdf shim at ${candidate}`);
}

function rbenvRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (!env.home) {
    return record('rbenv', null, 'no HOME/USERPROFILE to locate ~/.rbenv');
  }
  const candidate = path.join(env.home, '.rbenv', 'shims', exeName('ruby', env));
  return record('rbenv', candidate, `rbenv shim at ${candidate}`);
}

/** chruby has no shim directory of its own -- it activates a Ruby
 * directly under `~/.rubies/<name>/bin/ruby`. Without a shell sourcing
 * chruby's own `.ruby-version` logic, the best this can do statically is
 * the version chruby itself defaults to when no per-project override is
 * active: whatever `~/.ruby-version` names, if anything. */
function chrubyRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (!env.home) {
    return record('chruby', null, 'no HOME/USERPROFILE to read ~/.ruby-version');
  }
  const versionFile = path.join(env.home, '.ruby-version');
  if (!env.existsSync(versionFile)) {
    return record('chruby', null, `no ${versionFile}`);
  }
  // The version file's own content isn't read here (that would need
  // fs.readFileSync, not just existsSync) -- chruby's actual directory
  // naming ("ruby-3.3.0" vs "3.3.0") varies by how it was installed, so
  // without shelling out to chruby itself there's no reliable static
  // mapping. Recorded as a *matched marker file* only, for diagnostics —
  // never picked as the actual executable.
  return record('chruby', null, `${versionFile} exists, but chruby's own ruby-<version> directory naming can't be resolved without shelling out to chruby itself`);
}

/**
 * Homebrew's own prefix, checked directly rather than relying on PATH
 * containing it -- found reviewing Apple Silicon readiness (Task 023).
 * A GUI-launched VS Code (Dock/Finder/Spotlight, not a terminal) gets
 * macOS' own minimal launchd-inherited PATH, which does not include
 * `/opt/homebrew/bin` unless something else already put it there; a
 * Homebrew-installed Ruby is otherwise invisible to `pathRuby` below in
 * exactly that (common) launch shape.
 *
 * Checked before the generic PATH scan, deliberately: a Homebrew Ruby is
 * a real, user-installed interpreter, while `pathRuby` below can easily
 * land on macOS' own restricted system `/usr/bin/ruby` first if PATH
 * happens to be minimal -- worse for this project's needs.
 *
 * Apple Silicon's prefix (`/opt/homebrew`) is checked, not Intel's
 * (`/usr/local`, still valid under Rosetta on an Apple Silicon Mac): this
 * Preview supports darwin-arm64 only, and picking an x86_64 Homebrew
 * Ruby here would silently hand `platformCompatibility.ts`'s own
 * architecture check a Rosetta-translated interpreter to reject *after*
 * spawning it, rather than simply not offering it as a candidate. That
 * check still exists as the authoritative backstop (this function only
 * decides what gets *tried*, not what's ultimately compatible).
 */
function homebrewRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (env.platform !== 'darwin') {
    return record('Homebrew', null, 'not running on macOS');
  }
  const candidate = path.join('/opt/homebrew/opt/ruby/bin', exeName('ruby', env));
  return record('Homebrew', candidate, `Homebrew (Apple Silicon prefix) Ruby at ${candidate}`);
}

function pathRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  const name = exeName('ruby', env);
  for (const dir of pathEntries(env)) {
    const candidate = path.join(dir, name);
    const found = record('PATH', candidate, `PATH entry ${dir}`);
    if (found) {
      return found;
    }
  }
  if (pathEntries(env).length === 0) {
    record('PATH', null, 'PATH is empty or unset');
  }
  return null;
}

function windowsInstallerRuby(
  env: RubyResolverEnv,
  record: (strategy: string, candidate: string | null, reason: string) => string | null
): string | null {
  if (env.platform !== 'win32') {
    return record('RubyInstaller', null, 'not running on Windows');
  }
  for (const dir of WINDOWS_RUBY_INSTALLER_GLOBS) {
    const candidate = path.join(dir, 'bin', 'ruby.exe');
    const found = record('RubyInstaller', candidate, `default RubyInstaller location ${dir}`);
    if (found) {
      return found;
    }
  }
  return null;
}
