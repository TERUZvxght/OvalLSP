import * as fs from 'fs';
import * as path from 'path';
import { execFile } from 'child_process';

// ADR-0005: a packaged VSIX's bundled `core/vendor/bundle` (ADR-0004)
// contains native extensions specific to whatever Ruby engine/version/OS/CPU
// ran `bundle install` at packaging time (`vscode/scripts/copy-core.js`,
// which writes `core/PLATFORM_MANIFEST.json`). `core/bin/ovallsp` itself
// already refuses to load an incompatible vendor directory
// (`Ovallsp::VendorCompatibility`) -- this module is the same check run
// *before* even spawning Core, so an incompatible combination shows up as a
// clear VS Code error/Output message instead of Core silently degrading (or,
// pre-ADR-0005, crashing undiagnosably) after the fact.

export interface PlatformManifest {
  rubyEngine: string;
  rubyVersionMajorMinor: string;
  rubyPlatform: string;
}

export interface CompatibilityResult {
  compatible: boolean;
  reason?: string;
}

function readManifest(extensionRoot: string): PlatformManifest | undefined {
  const manifestPath = path.join(extensionRoot, 'core', 'PLATFORM_MANIFEST.json');
  if (!fs.existsSync(manifestPath)) {
    return undefined;
  }
  try {
    return JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as PlatformManifest;
  } catch {
    return undefined;
  }
}

export interface RubyIdentity {
  engine: string;
  version: string;
  platform: string;
}

export type RubyIdentityQuery = (rubyCommand: string, cwd?: string) => Promise<RubyIdentity>;

/**
 * The real implementation; injectable so unit tests never spawn a
 * process. `cwd` matters, not just as a nicety: rbenv/asdf/mise version-
 * manager shims pick *which* installed Ruby version to actually run
 * based on the current working directory's own `.ruby-version`/
 * `.tool-versions` (absent an env var override) -- found by independent
 * review (Task 023.8, a second re-review round) that omitting it here
 * silently queries whatever Ruby the *extension host's own* ambient cwd
 * happens to resolve to, not the workspace folder's pinned version.
 * Reproduced directly: the same `~/.rbenv/shims/ruby` reports a
 * genuinely different `RbConfig::CONFIG["bindir"]` depending solely on
 * which directory it's invoked from, when different workspace folders
 * pin different Ruby versions via their own `.ruby-version`.
 */
export function queryRubyIdentity(rubyCommand: string, cwd?: string): Promise<RubyIdentity> {
  return new Promise((resolve, reject) => {
    execFile(
      rubyCommand,
      ['-e', 'print [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM].join("|")'],
      { timeout: 5000, cwd },
      (err, stdout) => {
        if (err) {
          reject(err);
          return;
        }
        const [engine, version, platform] = stdout.trim().split('|');
        resolve({ engine, version, platform });
      }
    );
  });
}

export interface RubyConfigPaths {
  /** `RbConfig::CONFIG["bindir"]` -- the directory containing the *real* ruby binary. */
  bindir: string;
  /** `RbConfig::CONFIG["libdir"]` -- the directory containing the real `libruby`. */
  libdir: string;
}

/**
 * Fixes a real, reproduced bug (Task 023.8, found by independent
 * review): a vendored native extension (prism.bundle/rbs_extension.bundle,
 * ADR-0004) records an absolute, non-relocatable `libruby` dependency
 * path baked in at packaging time (standard rbenv/ruby-build
 * `--enable-shared` behavior on macOS, confirmed via `otool -L`/`-l`: no
 * `LC_RPATH` fallback), which fails to load under any *other* Ruby
 * installation -- even one just as compatible by ADR-0005's own
 * engine/version/platform check. Reproduced directly: a `prism.bundle`
 * vendored under one Ruby 3.4.x raises `LoadError: linked to
 * incompatible .../libruby.3.4.dylib` under a different Ruby 3.4.x
 * install at a different absolute path.
 *
 * This went through two failed designs before landing here, both found
 * by directly reproducing the fix rather than trusting it in the
 * abstract:
 *
 * 1. Deriving `<prefix>/lib` from `rubyCommand`'s own path shape
 *    (`<prefix>/bin/ruby`) -- wrong for mise/asdf/rbenv, whose
 *    `rubyResolver.ts` strategies all resolve to a *shim* script (e.g.
 *    `~/.rbenv/shims/ruby`), not a real per-version binary, so the
 *    derived directory never actually contained `libruby` for exactly
 *    the highest-priority, most common resolution paths.
 * 2. Querying `RbConfig::CONFIG["libdir"]` from the resolved command
 *    (correctly shim-agnostic) and setting `DYLD_LIBRARY_PATH` on the
 *    spawned child's environment -- but still spawning the *shim*
 *    itself as the command. Reproduced directly that this silently does
 *    nothing: macOS strips `DYLD_*` environment variables for any
 *    process launched through `/bin/bash` (confirmed directly -- even a
 *    trivial `#!/bin/bash` script loses `DYLD_LIBRARY_PATH` before its
 *    own body runs, let alone whatever it execs afterward), and rbenv's/
 *    asdf's/mise's shims are themselves bash scripts that ultimately
 *    `exec` the real interpreter through one or more further bash hops
 *    (rbenv's shim execs `rbenv exec`, itself a bash script).
 *    `DYLD_LIBRARY_PATH` set on the *shim's* spawn environment never
 *    survives to reach the real `ruby` process at all.
 *
 * The fix that actually works, verified the same way: query
 * `RbConfig::CONFIG["bindir"]` *alongside* `libdir` from the resolved
 * (possibly-shim) command, then spawn `<bindir>/ruby` -- the real
 * binary -- directly for the long-running Core Server process, bypassing
 * the shim (and its bash hops) entirely, with `DYLD_LIBRARY_PATH` set to
 * `libdir`. Since the real binary is what dyld loads directly (no
 * intervening bash process to strip the environment), the env var is
 * honored. The one-time shim invocation to ask this question is the
 * only place the shim script itself still runs.
 */
// `cwd` must be the *workspace folder's* own directory, not omitted --
// found by independent review (a second re-review round on this same
// fix): rbenv/asdf/mise shims resolve which installed Ruby version to
// actually run based on the current working directory's own
// `.ruby-version`/`.tool-versions`, so querying without `cwd` silently
// asks whatever Ruby the *extension host's own* ambient working
// directory resolves to -- a different, wrong interpreter entirely (not
// merely a DYLD/native-extension problem) whenever a workspace folder
// pins a different Ruby version than that ambient default. Reproduced
// directly: the same shim path returns a different `bindir`/`libdir`
// pair depending solely on which directory it's invoked from.
export function queryRubyConfigPaths(rubyCommand: string, cwd?: string): Promise<RubyConfigPaths> {
  return new Promise((resolve, reject) => {
    execFile(
      rubyCommand,
      ['-e', 'print [RbConfig::CONFIG["bindir"], RbConfig::CONFIG["libdir"]].join("|")'],
      { timeout: 5000, cwd },
      (err, stdout) => {
        if (err) {
          reject(err);
          return;
        }
        const [bindir, libdir] = stdout.trim().split('|');
        resolve({ bindir, libdir });
      }
    );
  });
}

/**
 * Checks whether `rubyCommand` is compatible with the extension's own
 * bundled `core/vendor/bundle`, if any. Compatible whenever:
 *  - there's no bundled `core/PLATFORM_MANIFEST.json` at all (a
 *    monorepo-relative dev checkout, or an older pre-ADR-0005 VSIX — see
 *    `Ovallsp::VendorCompatibility`'s own docs for why this direction is
 *    deliberately permissive), or
 *  - the manifest's engine/major.minor-version/platform all match what
 *    `rubyCommand` actually reports.
 *
 * A `rubyCommand` that can't even be queried (not on PATH, doesn't
 * understand `-e`) is reported as *incompatible* with a reason describing
 * the query failure — this function's whole job is "is it safe to hand
 * this Ruby the bundled vendor payload", and a Ruby that can't answer a
 * basic version query isn't something that should be treated as a match by
 * default.
 */
export async function checkBundledCoreCompatibility(
  extensionRoot: string,
  rubyCommand: string,
  queryIdentity: RubyIdentityQuery = queryRubyIdentity,
  cwd?: string
): Promise<CompatibilityResult> {
  const manifest = readManifest(extensionRoot);
  if (!manifest) {
    return { compatible: true };
  }

  let identity: RubyIdentity;
  try {
    identity = await queryIdentity(rubyCommand, cwd);
  } catch (err) {
    return {
      compatible: false,
      reason:
        `could not determine the version of the Ruby interpreter "${rubyCommand}" (${err}) -- ` +
        'cannot verify it is compatible with the bundled native dependencies.'
    };
  }

  const [major, minor] = identity.version.split('.');
  const actualMajorMinor = `${major}.${minor}`;

  if (
    manifest.rubyEngine === identity.engine &&
    manifest.rubyVersionMajorMinor === actualMajorMinor &&
    manifest.rubyPlatform === identity.platform
  ) {
    return { compatible: true };
  }

  const expected = `${manifest.rubyEngine} ${manifest.rubyVersionMajorMinor} (${manifest.rubyPlatform})`;
  const actual = `${identity.engine} ${actualMajorMinor} (${identity.platform})`;
  return {
    compatible: false,
    reason:
      `This VSIX's bundled native dependencies were built for ${expected}, but "${rubyCommand}" is ${actual}. ` +
      'These are incompatible.\n\n' +
      'To use OvalLSP, either:\n' +
      '  - install ovallsp\'s own runtime dependencies for this Ruby yourself (gem install prism rbs), or\n' +
      `  - set "ovallsp.rubyExecutablePath" to a ${expected} interpreter matching this VSIX build.\n\n` +
      'See docs/design/adrs/0005-platform-scoped-vsix-with-runtime-compatibility-check.md for details.'
  };
}
