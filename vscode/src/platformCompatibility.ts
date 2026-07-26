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

export type RubyIdentityQuery = (rubyCommand: string) => Promise<RubyIdentity>;

/** The real implementation; injectable so unit tests never spawn a process. */
export function queryRubyIdentity(rubyCommand: string): Promise<RubyIdentity> {
  return new Promise((resolve, reject) => {
    execFile(
      rubyCommand,
      ['-e', 'print [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM].join("|")'],
      { timeout: 5000 },
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
  queryIdentity: RubyIdentityQuery = queryRubyIdentity
): Promise<CompatibilityResult> {
  const manifest = readManifest(extensionRoot);
  if (!manifest) {
    return { compatible: true };
  }

  let identity: RubyIdentity;
  try {
    identity = await queryIdentity(rubyCommand);
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
