import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { CoreClassification } from './serverConfig';

// Task 023.2: the Extension/Core version-compatibility handshake. Mirrors
// `core/lib/ovallsp/protocol_version.rb`'s `Ovallsp::ProtocolVersion` --
// kept in sync by hand across the monorepo boundary (the same pattern
// `RuntimeAgent::Agent::PROTOCOL_VERSION`/`Plugins::CURRENT_PROTOCOL_VERSION`
// already use on the Core side, just for a different pair of processes).
export const CLIENT_PROTOCOL_VERSION = 1;
export const SUPPORTED_SERVER_PROTOCOL_RANGE = { minimum: 1, maximum: 1 };

export interface ServerProtocolInfo {
  current: number;
  minimumClient: number;
  maximumClient: number;
  minimumServer: number;
  maximumServer: number;
}

export interface ServerBuildInfo {
  commit: string | null;
  target: string | null;
  payloadSha256: string | null;
}

/** The `ovallspInfo` field of `InitializeResult` (`core/lib/ovallsp/server.rb#ovallsp_info`). */
export interface OvallspServerInfo {
  coreVersion: string;
  protocol: ServerProtocolInfo;
  ruby: { engine: string; version: string; platform: string };
  build: ServerBuildInfo | null;
}

/** `PLATFORM_MANIFEST.json`, as written by `vscode/scripts/copy-core.js`. */
export interface BuildManifest {
  rubyEngine: string;
  rubyVersionMajorMinor: string;
  rubyPlatform: string;
  extensionVersion: string;
  coreVersion: string;
  buildCommit: string;
  buildTarget: string;
  payloadSha256: string;
}

export interface ClientVersionInfo {
  extensionVersion: string;
  classification: CoreClassification;
  currentTarget: string;
  selectedCorePath: string;
  /** Only ever present for `classification === 'bundled'`. */
  manifest?: BuildManifest;
  /**
   * Recomputed live over the actual on-disk bundled `core/` directory --
   * only meaningful for `classification === 'bundled'`. Comparing this
   * against `manifest.payloadSha256` is what actually detects a
   * corrupted/tampered/partially-written vendor payload; the manifest
   * recording its own expected hash is not, by itself, proof the payload
   * on disk still matches it.
   */
  actualPayloadSha256?: string;
}

export interface VersionDiagnosticDetails {
  extensionVersion: string;
  coreVersion: string | null;
  clientProtocolVersion: number;
  serverProtocolCurrent: number | null;
  rubyRunning: string | null;
  rubyExpected: string | null;
  selectedCorePath: string;
  classification: CoreClassification;
}

export interface VersionDiagnostic {
  compatible: boolean;
  /** Empty when compatible. Each entry is a standalone, user-facing sentence. */
  reasons: string[];
  /** Always populated, so the diagnostic is useful even when compatible. */
  details: VersionDiagnosticDetails;
  /** Only set when incompatible -- what the user should actually do. */
  action?: string;
}

function rubyLabel(engine: string, version: string, platform: string): string {
  return `${engine} ${version} (${platform})`;
}

/**
 * Reads `<extensionRoot>/core/PLATFORM_MANIFEST.json` if it exists --
 * `undefined` for a monorepo dev checkout or a pre-023.2 VSIX missing the
 * extended fields, same permissive-by-default treatment
 * `platformCompatibility.ts`'s own `readManifest` already uses.
 */
export function readBuildManifest(extensionRoot: string): BuildManifest | undefined {
  const manifestPath = path.join(extensionRoot, 'core', 'PLATFORM_MANIFEST.json');
  if (!fs.existsSync(manifestPath)) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    if (typeof parsed.extensionVersion !== 'string' || typeof parsed.payloadSha256 !== 'string') {
      return undefined; // pre-023.2 manifest, missing the fields this handshake needs.
    }
    return parsed as BuildManifest;
  } catch {
    return undefined;
  }
}

/**
 * The same sha256-over-sorted-relative-paths algorithm
 * `copy-core.js`'s `computeDirectorySha256` uses, deliberately kept in
 * lockstep with it (see that function's own comment) -- except this walk
 * always skips `PLATFORM_MANIFEST.json` at the root, because the
 * manifest's own recorded hash was computed *before* that file existed in
 * the staged tree (a manifest cannot hash itself).
 */
export function computeBundledPayloadSha256(coreDir: string): string {
  const hash = crypto.createHash('sha256');

  function walk(current: string, relativePrefix: string): void {
    for (const entry of fs.readdirSync(current).sort()) {
      if (relativePrefix === '' && entry === 'PLATFORM_MANIFEST.json') {
        continue;
      }
      const fullPath = path.join(current, entry);
      const relativePath = relativePrefix === '' ? entry : path.join(relativePrefix, entry);
      const stat = fs.statSync(fullPath);
      if (stat.isDirectory()) {
        walk(fullPath, relativePath);
      } else if (stat.isFile()) {
        hash.update(relativePath.split(path.sep).join('/'));
        hash.update('\0');
        hash.update(fs.readFileSync(fullPath));
      }
    }
  }

  walk(coreDir, '');
  return hash.digest('hex');
}

/**
 * Gathers what the client itself knows/expects, before ever hearing back
 * from Core's `initialize` response. Recomputing the payload hash is
 * skipped entirely for non-bundled classifications -- there's no bundled
 * manifest to compare it against, and hashing an arbitrary monorepo/custom
 * Core directory on every activation would be pure overhead with no
 * corresponding check to use it for.
 */
export function gatherClientVersionInfo(input: {
  extensionRoot: string;
  extensionVersion: string;
  classification: CoreClassification;
  selectedCorePath: string;
  currentTarget: string;
}): ClientVersionInfo {
  const manifest = input.classification === 'bundled' ? readBuildManifest(input.extensionRoot) : undefined;
  const actualPayloadSha256 =
    input.classification === 'bundled' && manifest
      ? computeBundledPayloadSha256(path.join(input.extensionRoot, 'core'))
      : undefined;

  return {
    extensionVersion: input.extensionVersion,
    classification: input.classification,
    currentTarget: input.currentTarget,
    selectedCorePath: input.selectedCorePath,
    manifest,
    actualPayloadSha256
  };
}

function majorMinor(version: string): string {
  const [major, minor] = version.split('.');
  return `${major}.${minor}`;
}

/**
 * The single source of truth for "is this Extension/Core pair safe to
 * keep talking to" (Task 023 Section 2). Covers all 8 mismatch modes the
 * task specifies:
 *
 *   1. protocol ranges don't intersect
 *   2. Extension's expected Core version/build doesn't match the
 *      standard bundled Core          (bundled only)
 *   3. payload hash mismatch          (bundled only)
 *   4. platform mismatch              (bundled only)
 *   5. Ruby engine mismatch           (bundled only)
 *   6. Ruby major.minor mismatch      (bundled only)
 *   7. Core version info unobtainable (any classification)
 *   8. custom Core's protocol is incompatible (custom -- protocol check
 *      applies uniformly; see the guard below for why 2-6 never fire for
 *      a custom Core)
 *
 * 2-6 are deliberately skipped outright for `monorepo`/`custom`
 * classifications: there is no "standard bundled Core" for either of
 * those to match against, and guarantee #9 (ADR-0006) requires a custom
 * server path to be judged *only* on compatibility, never flagged as
 * wrong merely for differing from a bundled manifest that was never
 * meant to describe it.
 */
export function compareVersionInfo(client: ClientVersionInfo, server: OvallspServerInfo | undefined): VersionDiagnostic {
  const reasons: string[] = [];
  const details: VersionDiagnosticDetails = {
    extensionVersion: client.extensionVersion,
    coreVersion: server?.coreVersion ?? null,
    clientProtocolVersion: CLIENT_PROTOCOL_VERSION,
    serverProtocolCurrent: server?.protocol.current ?? null,
    rubyRunning: server ? rubyLabel(server.ruby.engine, server.ruby.version, server.ruby.platform) : null,
    rubyExpected: client.manifest
      ? `${client.manifest.rubyEngine} ${client.manifest.rubyVersionMajorMinor} (${client.manifest.rubyPlatform})`
      : null,
    selectedCorePath: client.selectedCorePath,
    classification: client.classification
  };

  if (!server) {
    return {
      compatible: false,
      reasons: ['Core did not report version information in its initialize response (ovallspInfo missing or malformed).'],
      details,
      action:
        'Restart the Core Server (OvalLSP: Restart Server) and check the OvalLSP output channel. If this persists, ' +
        'the selected Core may be an older build that predates this Extension\'s version handshake -- update it.'
    };
  }

  // Mode 1 / 8: protocol range intersection, checked for every
  // classification (bundled, monorepo, and custom alike).
  const clientAcceptsServer =
    server.protocol.current >= SUPPORTED_SERVER_PROTOCOL_RANGE.minimum &&
    server.protocol.current <= SUPPORTED_SERVER_PROTOCOL_RANGE.maximum;
  const serverAcceptsClient =
    CLIENT_PROTOCOL_VERSION >= server.protocol.minimumClient && CLIENT_PROTOCOL_VERSION <= server.protocol.maximumClient;
  if (!clientAcceptsServer || !serverAcceptsClient) {
    reasons.push(
      `Protocol version mismatch: this Extension supports Core protocol ${SUPPORTED_SERVER_PROTOCOL_RANGE.minimum}-` +
        `${SUPPORTED_SERVER_PROTOCOL_RANGE.maximum}, Core reports ${server.protocol.current} (accepting client ` +
        `${server.protocol.minimumClient}-${server.protocol.maximumClient}); this Extension is client protocol ` +
        `${CLIENT_PROTOCOL_VERSION}. These ranges do not intersect.`
    );
  }

  if (client.classification === 'bundled' && client.manifest) {
    const manifest = client.manifest;

    if (manifest.coreVersion !== server.coreVersion) {
      reasons.push(
        `Core version mismatch: this Extension expects its bundled Core to be version ${manifest.coreVersion}, ` +
          `but the running Core reports ${server.coreVersion}.`
      );
    }

    if (server.build && manifest.buildCommit !== server.build.commit) {
      reasons.push(
        `Build identity mismatch: this Extension's bundled Core was built from commit ${manifest.buildCommit}, ` +
          `but the running Core reports build commit ${server.build.commit ?? '(unknown)'}.`
      );
    }

    if (client.actualPayloadSha256 && client.actualPayloadSha256 !== manifest.payloadSha256) {
      reasons.push(
        'Payload hash mismatch: the bundled Core on disk does not match this Extension\'s recorded payload hash -- ' +
          'it may be corrupted or was partially/incorrectly installed.'
      );
    }

    if (manifest.buildTarget !== client.currentTarget) {
      reasons.push(
        `Platform mismatch: this Extension's bundled Core was built for ${manifest.buildTarget}, but this machine ` +
          `is ${client.currentTarget}.`
      );
    }

    if (manifest.rubyEngine !== server.ruby.engine) {
      reasons.push(
        `Ruby engine mismatch: this Extension's bundled Core expects ${manifest.rubyEngine}, but the running Core ` +
          `is ${server.ruby.engine}.`
      );
    } else if (manifest.rubyVersionMajorMinor !== majorMinor(server.ruby.version)) {
      reasons.push(
        `Ruby version mismatch: this Extension's bundled Core expects Ruby ${manifest.rubyVersionMajorMinor}, but ` +
          `the running Core is Ruby ${majorMinor(server.ruby.version)}.`
      );
    }
  }

  if (reasons.length === 0) {
    return { compatible: true, reasons: [], details };
  }

  return {
    compatible: false,
    reasons,
    details,
    action:
      client.classification === 'custom'
        ? 'This is a custom "ovallsp.server.path". Point it at a Core build with a compatible protocol version, or ' +
          'unset it to use the Extension\'s own bundled Core.'
        : 'Reinstall or update the OvalLSP extension from the Marketplace so its bundled Core matches this build.'
  };
}
