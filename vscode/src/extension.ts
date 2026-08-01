import * as fs from 'fs';
import * as path from 'path';
import { documentSelectorFor, resolveStatus, statusPresentation } from './clientPresentation';
import { spawn } from 'child_process';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions
} from 'vscode-languageclient/node';
import { resolveServerConfig, classifyServerSelection } from './serverConfig';
import { resolveRuby, RubyResolution } from './rubyResolver';
import { checkBundledCoreCompatibility, queryRubyConfigPaths, RubyConfigPaths } from './platformCompatibility';
import { WATCHED_FILES_GLOB } from './watchedFiles';
import {
  CLIENT_PROTOCOL_VERSION,
  OvallspServerInfo,
  VersionDiagnostic,
  compareVersionInfo,
  gatherClientVersionInfo
} from './versionInfo';
import {
  canSpawnCoreProcess,
  ClientLifecycleManager,
  CoreStartRejectedError,
  KeyedTransitionQueue,
  ShutdownBarrier
} from './clientLifecycle';
import { notificationLevelFor } from './clientErrorNotifications';
import { SpawnedCoreProcess } from './coreProcess';
import {
  ClientRegistry,
  RESTART_AGENT_COMMAND,
  RESTART_SERVER_COMMAND,
  restartMessageFor,
  shouldStartAddedFolder,
  stopClient as stopClientWith,
  stopSupersededClient
} from './clientTeardown';

/**
 * Exists solely to keep our own deliberate teardowns out of the user's
 * face. vscode-languageclient reports every connection closure it did not
 * initiate as an error, and `'force'` means a red popup -- so both
 * declining to spawn Core during deactivate/restart and stopping a client
 * that is still `starting` were reported to the user as failures, when
 * both are the extension working as intended.
 *
 * The decision itself lives in `clientErrorNotifications`, which does not
 * import `vscode` and so can actually be tested (024.9, 024.10).
 */
class OvalLspLanguageClient extends LanguageClient {
  constructor(
    id: string,
    name: string,
    serverOptions: ServerOptions,
    clientOptions: LanguageClientOptions,
    private readonly stopWasRequested: () => boolean
  ) {
    super(id, name, serverOptions, clientOptions);
  }

  error(message: string, data?: unknown, showNotification?: boolean | 'force'): void {
    super.error(
      message,
      data,
      notificationLevelFor({ data, showNotification, stopWasRequested: this.stopWasRequested() })
    );
  }
}

const clients = new Map<string, LanguageClient>();
const watchers = new Map<string, vscode.FileSystemWatcher>();
// Task 023.3: the single owner of "is it still valid to call
// client.start() for this folder right now" -- see clientLifecycle.ts's
// own docs for the exact race this closes.
const lifecycle = new ClientLifecycleManager();
const startAttempts = new Set<Promise<void>>();
// The Ruby resolution actually used to launch each folder's client — kept
// around purely so `OvalLSP: Show Environment Diagnostics` can show *why*
// that Ruby was picked without re-running the search (020's "Ruby
// executable選択理由を診断画面で確認できる").
const rubyResolutions = new Map<string, RubyResolution>();
// Task 023.2: the version-compatibility diagnostic computed for each
// folder's client, once it has actually started and reported
// `ovallspInfo` -- kept purely so `OvalLSP: Show Version Information`
// can display it without re-running the comparison.
const versionDiagnostics = new Map<string, VersionDiagnostic>();
// Every folder's stop->start replacement is serialized through this
// chain. Without it, two Restart Server commands can interleave so the
// first command overwrites the second command's already-running client,
// leaving that process unreachable from `clients`.
const clientTransitions = new KeyedTransitionQueue();
// The maps clientTeardown.ts operates on, bundled once so teardown reads
// the same state `activate` writes.
const registry: ClientRegistry = { clients, watchers, versionDiagnostics };
const shutdownBarrier = new ShutdownBarrier();

// Task 020's priority order: an explicit path setting always wins outright
// (never even runs the version-manager search); everything below that is
// `rubyResolver.resolveRuby`'s job. `ovallsp.rubyExecutablePath` is this
// task's own setting name; `ovallsp.ruby.command` (pre-existing) is kept
// working as a synonym at the same priority, for anyone already using it.
function resolveRubyForFolder(folder: vscode.WorkspaceFolder): { command: string; resolution: RubyResolution | null } {
  const config = vscode.workspace.getConfiguration('ovallsp', folder);
  const explicit = config.get<string | null>('rubyExecutablePath') ?? config.get<string | null>('ruby.command');
  if (explicit && explicit.trim().length > 0) {
    return { command: explicit, resolution: null };
  }

  const resolution = resolveRuby({
    platform: process.platform,
    home: process.env.HOME ?? process.env.USERPROFILE,
    pathEnv: process.env.PATH,
    workspaceRoot: folder.uri.fsPath,
    existsSync: fs.existsSync
  });
  return { command: resolution.executable, resolution };
}

function startClientForFolder(
  folder: vscode.WorkspaceFolder,
  outputChannel: vscode.OutputChannel,
  context: vscode.ExtensionContext
): LanguageClient {
  const config = vscode.workspace.getConfiguration('ovallsp', folder);
  const { command: resolvedRubyCommand, resolution } = resolveRubyForFolder(folder);
  if (resolution) {
    rubyResolutions.set(folder.uri.toString(), resolution);
  } else {
    rubyResolutions.delete(folder.uri.toString());
  }

  const serverConfigInput = {
    rubyCommand: resolvedRubyCommand,
    serverPath: config.get<string | null>('server.path'),
    extensionRoot: context.extensionPath
  };
  const { command, args } = resolveServerConfig(serverConfigInput);
  const classification = classifyServerSelection(serverConfigInput);

  // Task 023.8: the vendored native extensions' own absolute libruby
  // reference is specific to the machine that packaged this VSIX, not
  // to whichever Ruby actually resolves for this workspace. Fixed below
  // by spawning the *real* ruby binary directly (bypassing a version-
  // manager shim entirely, when the resolved command is one) with
  // DYLD_LIBRARY_PATH set to that real binary's own libdir -- see
  // `queryRubyConfigPaths`'s own docs for why both parts are necessary
  // (setting the env var alone does nothing when the spawned command is
  // still a shim script, since macOS strips DYLD_* env vars for any
  // process launched through /bin/bash).
  //
  // `execTarget` is a single mutable object shared by both `run`/`debug`
  // below (vscode-languageclient reads `this._serverOptions` -- and the
  // `command`/`options` reached through it -- fresh at actual spawn
  // time, not a frozen snapshot from `new LanguageClient(...)`, so
  // mutating `command`/`options.env` here later, right before
  // `client.start()`, is picked up correctly); starts as the originally
  // resolved command/args, replaced only if the async query below
  // succeeds.
  const execTarget: { command: string; args: string[]; options: { cwd: string; env?: NodeJS.ProcessEnv } } = {
    command,
    args,
    options: { cwd: folder.uri.fsPath }
  };

  // Forwarded to the server as workspace/didChangeWatchedFiles so files
  // edited or removed outside the open buffers (git checkout, another
  // editor, rm) still update the workspace index — and, for Gemfile.lock
  // specifically, tell the server to restart the Runtime Agent (a changed
  // lockfile can mean different gem versions or a different Rails
  // version entirely; docs/design/docs/04-runtime-agent.md section 9:
  // "Gemfile.lock -> Core/Agent full restart"). Without this pattern
  // covering it, that server-side restart logic would exist but never
  // actually run.
  //
  // `db/structure.sql` is included alongside `Gemfile.lock` for the same
  // reason: Server#server.rb already treats it (and `db/schema.rb`,
  // matched by the `*.rb` glob above) as a schema-wide change that
  // invalidates every Active Record model's column/association facts
  // (see its own "db/schema.rb/structure.sql -> refresh_all_models"
  // comment) — but a Rails app configured for the SQL schema-dump format
  // (`config.active_record.schema_format = :sql`) never touches
  // `schema.rb` at all, so without this entry here, an external change to
  // `structure.sql` (a migration run outside the editor, a branch switch)
  // never reached the server, and that whole invalidation path was
  // silently dead for every such app.
  const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(folder, WATCHED_FILES_GLOB));
  watchers.set(folder.uri.toString(), watcher);

  const clientOptions: LanguageClientOptions = {
    // Built in `clientPresentation.ts`, which imports no `vscode` and so
    // can be unit-tested -- including the "ERB by extension, not language
    // id" decision this used to state only in a comment here (024.17).
    documentSelector: documentSelectorFor(folder.uri.fsPath),
    workspaceFolder: folder,
    outputChannel,
    synchronize: { fileEvents: watcher },
    // There's no standard LSP field for workspace trust, so it's passed
    // through here — the Core Server must not launch the Runtime Agent
    // (Rails/Bundler code execution) in an untrusted workspace
    // (docs/design/docs/02-architecture.md section 11). `ovallspClient`
    // is Task 023.2's own addition -- Core doesn't consume it yet (the
    // handshake today is entirely client-side, comparing what Core
    // reports in `ovallspInfo` against what this Extension expects), but
    // sending it now means a future Core-side check has real data to read
    // instead of needing every already-shipped Extension to add it later.
    initializationOptions: {
      workspaceTrusted: vscode.workspace.isTrusted,
      ovallspClient: {
        extensionVersion: context.extension.packageJSON.version,
        protocolVersion: CLIENT_PROTOCOL_VERSION
      }
    }
  };

  const key = folder.uri.toString();
  const generation = lifecycle.beginStart(key);
  const serverOptions: ServerOptions = () => {
    // vscode-languageclient can invoke ServerOptions again for its own
    // crash recovery. Reject stale clients before spawning anything:
    // registerProcess is intentionally a second line of defense, not the
    // first point at which shutdown/stale-generation state is noticed.
    if (!canSpawnCoreProcess(shutdownBarrier, lifecycle, key, generation)) {
      return Promise.reject(
        new CoreStartRejectedError('OvalLSP Core start rejected during shutdown or after generation replacement')
      );
    }
    const windowsJobWrapper = path.join(context.extensionPath, 'resources', 'core-job.ps1');
    const posixSessionWrapper = path.join(context.extensionPath, 'resources', 'core-session.rb');
    const command = process.platform === 'win32' ? 'powershell.exe' : execTarget.command;
    const args =
      process.platform === 'win32'
        ? [
            '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', windowsJobWrapper, '-ChildCommand', execTarget.command,
            '-ChildArguments', quoteWindowsCommandLine(execTarget.args)
          ]
        : [posixSessionWrapper, ...execTarget.args];
    const child = spawn(command, args, {
      ...execTarget.options,
      detached: false,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    lifecycle.registerProcess(
      key,
      generation,
      process.platform === 'win32' ? new SpawnedCoreProcess(child) : SpawnedCoreProcess.forDedicatedSession(child)
    );
    // `detached` on the *descriptor* is unrelated to the `spawn` option
    // above (which must stay false, so `core-session.rb` is what creates
    // the session). It is vscode-languageclient's own switch for its
    // fallback killer: `stop()` otherwise schedules a `process.kill(pid,
    // 0)` 2s later and, if that pid is alive, runs `terminateProcess.sh`
    // to `kill -9` its whole tree by pid -- a blind pid-keyed kill on a
    // number we may no longer own, racing the identity-validated teardown
    // SpawnedCoreProcess performs. Declaring detached says the owner
    // registered above is responsible for this process.
    //
    // Documentation of intent more than a live fix: that killer is
    // already unreachable for a ServerOptions function returning
    // ChildProcessInfo, because that branch never assigns the
    // `_serverProcess` field `stop()` gates on (vscode-languageclient
    // 9.x, lib/node/main.js -- assignments exist only on the
    // Executable/NodeModule branches). Stated here so a future library
    // upgrade that closes that gap cannot silently re-arm it.
    return Promise.resolve({ process: child, detached: true });
  };

  // The generation is captured, not looked up: by the time the library
  // reports a closure this client's generation may already have been
  // superseded, and it is precisely that client's own fate we are asking
  // about.
  const client = new OvalLspLanguageClient(
    'ovallsp',
    `OvalLSP (${folder.name})`,
    serverOptions,
    clientOptions,
    () => lifecycle.stopWasRequested(key, generation)
  );

  // ADR-0005: checked *before* Core is actually spawned, not after --
  // `core/bin/ovallsp` itself already refuses to load an incompatible
  // vendor/bundle (Ovallsp::VendorCompatibility), but running the same
  // check here first means an incompatible Ruby/VSIX combination is
  // reported as a clear message in this extension's own OutputChannel
  // and an error notification, rather than only surfacing however Core
  // happens to degrade (working via system gems, or failing to load
  // prism/rbs at all) after the fact. Still starts Core regardless of the
  // outcome -- Core's own check is what actually decides whether the
  // vendor payload gets used, and a Ruby with its own separately-installed
  // prism/rbs is a legitimate, fully-working combination this check has
  // no way to rule out in advance.
  // Task 023.8: queried in parallel with the compatibility probe below,
  // and only on darwin (this Preview's only target; Linux/Windows use
  // their own different dynamic-linker environment variables and shim
  // implementations, out of scope for this fix). A query failure (Ruby
  // too old to know RbConfig, spawn error, ...) is not fatal here -- it
  // just means `execTarget` stays at the originally resolved command,
  // same as before this fix existed, rather than blocking Core from
  // starting at all over a diagnostic-only lookup.
  // `folder.uri.fsPath` as `cwd` matters here, not just for `execFile`
  // hygiene -- found by independent review (a second re-review round):
  // rbenv/asdf/mise shims resolve *which installed Ruby version* to run
  // based on the current working directory's own `.ruby-version`/
  // `.tool-versions`. Querying from the extension host's own ambient cwd
  // (i.e. omitting this) would silently resolve a different project's
  // pinned version than this workspace folder's own, in a multi-root or
  // per-project-Ruby-version setup -- reproduced directly against this
  // machine's real rbenv shim.
  const configPathsPromise: Promise<RubyConfigPaths | undefined> =
    process.platform === 'darwin'
      ? queryRubyConfigPaths(resolvedRubyCommand, folder.uri.fsPath).catch(() => undefined)
      : Promise.resolve(undefined);

  const startAttempt = Promise.all([
    checkBundledCoreCompatibility(context.extensionPath, resolvedRubyCommand, undefined, folder.uri.fsPath),
    configPathsPromise
  ]).then(([compatibility, configPaths]) => {
      if (!compatibility.compatible) {
        outputChannel.appendLine(`OvalLSP: ${compatibility.reason}`);
        void vscode.window.showErrorMessage(
          `OvalLSP: the Ruby interpreter selected for ${folder.name} is incompatible with this VSIX's bundled ` +
            'native dependencies. See the OvalLSP output channel for details.'
        );
      }

      if (configPaths) {
        // Spawn the real binary directly -- bypassing `resolvedRubyCommand`
        // entirely when it was a version-manager shim -- since setting
        // DYLD_LIBRARY_PATH on a shim's own spawn environment never
        // reaches the real ruby process it eventually execs (see
        // queryRubyConfigPaths's own docs for why).
        execTarget.command = path.join(configPaths.bindir, 'ruby');
        execTarget.options.env = {
          ...process.env,
          DYLD_LIBRARY_PATH: [configPaths.libdir, process.env.DYLD_LIBRARY_PATH].filter(Boolean).join(':'),
          DYLD_FALLBACK_LIBRARY_PATH: [configPaths.libdir, process.env.DYLD_FALLBACK_LIBRARY_PATH]
            .filter(Boolean)
            .join(':')
        };
      }

      // Task 023.3: this probe may resolve long after a stop was already
      // requested for this exact generation (deactivate, workspace-folder
      // removal, a restart that began a newer generation). `markStarting`
      // is the single gate that decides whether calling `client.start()`
      // below is still valid at all -- refusing here is what stops an
      // orphaned Core child process from ever being spawned in the first
      // place, rather than trying to clean one up after the fact.
      if (!lifecycle.markStarting(key, generation)) {
        outputChannel.appendLine(
          `OvalLSP: skipping Core Server start for ${folder.name} -- superseded by a stop or a newer restart.`
        );
        return;
      }

      return client.start().then(async () => {
        // A stop can also race in *during* `client.start()` itself (it's
        // not instantaneous -- it spawns a process and waits for
        // `initialize` to complete). `markRunning` returning false means
        // exactly that happened; this client is now running but nothing
        // else will ever call `.stop()` on it (stopClient already ran
        // against a generation that, at the time, had nothing to actually
        // stop), so this is the one place responsible for tearing it down.
        if (!lifecycle.markRunning(key, generation)) {
          outputChannel.appendLine(
            `OvalLSP: Core Server for ${folder.name} finished starting after a stop was requested -- stopping it immediately.`
          );
          await stopSupersededClient(client, key, generation, lifecycle);
          return;
        }
        runVersionHandshake(folder, client, context, classification, outputChannel);
      }, async (err) => {
        await lifecycle.terminateProcess(key, generation).then(() => {
          lifecycle.markStopped(key, generation);
          if (lifecycle.isCurrentGeneration(key, generation) && clients.get(key) === client) {
            clients.delete(key);
            watchers.get(key)?.dispose();
            watchers.delete(key);
            versionDiagnostics.delete(key);
          }
        });
        outputChannel.appendLine(`failed to start Core Server: ${err}`);
      });
    }
  ).catch((error) => {
    outputChannel.appendLine(`failed during Core Server startup: ${error}`);
  });
  startAttempts.add(startAttempt);
  void startAttempt.then(
    () => startAttempts.delete(startAttempt),
    () => startAttempts.delete(startAttempt)
  );

  return client;
}

function quoteWindowsCommandLine(argumentsList: string[]): string {
  return argumentsList.map((argument) => {
    if (argument.length > 0 && !/[\s"]/u.test(argument)) {
      return argument;
    }
    return `"${argument.replace(/(\\*)"/gu, '$1$1\\"').replace(/(\\+)$/u, '$1$1')}"`;
  }).join(' ');
}

// Task 023.2: once Core has actually started and answered `initialize`,
// compare what it reported (`ovallspInfo`) against what this Extension
// expects. Deliberately *after* `client.start()` resolves rather than
// woven into the pre-start compatibility probe above — that probe only
// ever checks the Ruby interpreter (ADR-0005) and must not block Core
// from starting at all (a Ruby with its own separately-installed prism/rbs
// is a legitimate combination it can't rule out in advance); this
// handshake instead reads Core's own self-report of what actually
// launched, which only exists once `initialize` has actually completed.
function runVersionHandshake(
  folder: vscode.WorkspaceFolder,
  client: LanguageClient,
  context: vscode.ExtensionContext,
  classification: ReturnType<typeof classifyServerSelection>,
  outputChannel: vscode.OutputChannel
): void {
  const key = folder.uri.toString();
  const serverConfigInput = {
    serverPath: vscode.workspace.getConfiguration('ovallsp', folder).get<string | null>('server.path'),
    extensionRoot: context.extensionPath
  };
  const clientInfo = gatherClientVersionInfo({
    extensionRoot: context.extensionPath,
    extensionVersion: context.extension.packageJSON.version,
    classification,
    selectedCorePath: resolveServerConfig(serverConfigInput).args[0],
    currentTarget: `${process.platform}-${process.arch}`
  });

  const ovallspInfo = client.initializeResult?.ovallspInfo as OvallspServerInfo | undefined;
  const diagnostic = compareVersionInfo(clientInfo, ovallspInfo);
  versionDiagnostics.set(key, diagnostic);

  if (!diagnostic.compatible) {
    outputChannel.appendLine(`--- OvalLSP version compatibility (${folder.name}) ---`);
    for (const reason of diagnostic.reasons) {
      outputChannel.appendLine(`  ✗ ${reason}`);
    }
    if (diagnostic.action) {
      outputChannel.appendLine(`  Action: ${diagnostic.action}`);
    }
    void vscode.window.showErrorMessage(
      `OvalLSP: the Core Server for ${folder.name} is not version-compatible with this Extension. ` +
        'See the OvalLSP output channel for details.'
    );
  }
}

// Task 019: opt-in runtime type observation. Every command here resolves
// the client from the *active editor's* workspace folder — there's no
// single "the" client once multiple folders are open — and each request
// is entirely a no-op server-side unless the user explicitly invoked one
// of these commands first ("opt-in時だけ観測runnerが起動する").
function clientForActiveEditor(outputChannel: vscode.OutputChannel): LanguageClient | undefined {
  const uri = vscode.window.activeTextEditor?.document.uri;
  const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    void vscode.window.showWarningMessage('OvalLSP: no workspace folder is open.');
    return undefined;
  }

  const client = clients.get(folder.uri.toString());
  if (!client) {
    outputChannel.appendLine(`OvalLSP: no running Core Server for ${folder.name}.`);
  }
  return client;
}

function registerObservationCommands(context: vscode.ExtensionContext, outputChannel: vscode.OutputChannel): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.observation.runTests', async () => {
      const client = clientForActiveEditor(outputChannel);
      if (!client) {
        return;
      }

      const testCommand = vscode.workspace.getConfiguration('ovallsp').get<string[] | null>('observation.testCommand');
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: 'OvalLSP: running tests with type observation…' },
        async () => {
          try {
            const result = await client.sendRequest<{ sampleCount: number; methodCount: number }>(
              'ovallsp/runObservedTests',
              testCommand && testCommand.length > 0 ? { testCommand } : {}
            );
            void vscode.window.showInformationMessage(
              `OvalLSP: observed ${result.methodCount} method(s) across ${result.sampleCount} call(s).`
            );
          } catch (err) {
            void vscode.window.showErrorMessage(`OvalLSP: observation run failed: ${err}`);
          }
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.observation.clearTypes', async () => {
      const client = clientForActiveEditor(outputChannel);
      if (!client) {
        return;
      }

      await client.sendRequest('ovallsp/clearObservedTypes', {});
      void vscode.window.showInformationMessage('OvalLSP: cleared observed types.');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.observation.showEvidence', async () => {
      const client = clientForActiveEditor(outputChannel);
      const editor = vscode.window.activeTextEditor;
      if (!client || !editor) {
        return;
      }

      const params = {
        textDocument: { uri: client.code2ProtocolConverter.asUri(editor.document.uri) },
        position: client.code2ProtocolConverter.asPosition(editor.selection.active)
      };
      const evidence = await client.sendRequest<{
        parameterTypes: string[];
        returnType: string;
        samples: number;
        confidence: string;
      } | null>('ovallsp/showTypeEvidence', params);

      if (!evidence) {
        void vscode.window.showInformationMessage('OvalLSP: no observed type evidence at this position.');
        return;
      }

      void vscode.window.showInformationMessage(
        `OvalLSP (${evidence.confidence} confidence, ${evidence.samples} sample(s)): ` +
          `(${evidence.parameterTypes.join(', ')}) -> ${evidence.returnType}`
      );
    })
  );
}

// Task 020's required status set. Polled (see #startStatusPolling) rather
// than pushed, matching Server's own `ovallsp/status`'s own design ("polled
// by the client rather than pushed as notifications").
function startStatusPolling(statusBarItem: vscode.StatusBarItem): vscode.Disposable {
  const interval = setInterval(() => {
    void (async () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
      const client = folder ? clients.get(folder.uri.toString()) : undefined;

      const shown = statusPresentation(await resolveStatus(client));
      if (!shown.visible) {
        statusBarItem.hide();
        return;
      }
      statusBarItem.text = shown.text as string;
      statusBarItem.show();
    })();
  }, 2000);

  return new vscode.Disposable(() => clearInterval(interval));
}

function registerEnvironmentCommands(
  context: vscode.ExtensionContext,
  outputChannel: vscode.OutputChannel
): void {
  // Each restart command names its id exactly once, and its confirmation
  // is looked up from that same id -- so no call site can pair a command
  // with the wrong message, which a table plus two hand-written
  // `showInformationMessage` calls would still have allowed (024.10).
  // What each command *does* is still the two bodies below, which need
  // `vscode` and are verified by hand.
  const registerRestartCommand = (commandId: string, run: () => Promise<boolean>): void => {
    context.subscriptions.push(
      vscode.commands.registerCommand(commandId, async () => {
        if (await run()) {
          void vscode.window.showInformationMessage(restartMessageFor(commandId)!);
        }
      })
    );
  };

  registerRestartCommand(RESTART_SERVER_COMMAND, async () => {
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
      await restartClientForFolder(folder, outputChannel, context);
    }
    return true;
  });

  registerRestartCommand(RESTART_AGENT_COMMAND, async () => {
    const client = clientForActiveEditor(outputChannel);
    if (!client) {
      return false;
    }
    await client.sendRequest('ovallsp/restartAgent', {});
    return true;
  });

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.showLogs', () => outputChannel.show())
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.reindexWorkspace', async () => {
      const client = clientForActiveEditor(outputChannel);
      if (!client) {
        return;
      }
      await client.sendRequest('ovallsp/reindexWorkspace', {});
      void vscode.window.showInformationMessage('OvalLSP: re-indexing workspace.');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.showEnvironmentDiagnostics', () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
      if (!folder) {
        void vscode.window.showWarningMessage('OvalLSP: no workspace folder is open.');
        return;
      }

      outputChannel.appendLine(`--- OvalLSP environment diagnostics: ${folder.name} ---`);
      const resolution = rubyResolutions.get(folder.uri.toString());
      if (!resolution) {
        outputChannel.appendLine('Ruby executable: explicitly configured (ovallsp.rubyExecutablePath/ovallsp.ruby.command) -- version-manager search was skipped.');
      } else {
        outputChannel.appendLine(`Ruby executable chosen: ${resolution.executable}`);
        for (const step of resolution.steps) {
          const mark = step.matched ? '✓' : ' ';
          outputChannel.appendLine(`  [${mark}] ${step.strategy}: ${step.reason}`);
        }
      }
      outputChannel.show();
    })
  );

  // Task 023 Section 2: deliberately never shows an absolute path in the
  // information popup itself (only the OutputChannel, which the user must
  // explicitly open) -- `selectedCorePath` in particular can reveal local
  // usernames/directory layout, which has no business appearing in a
  // notification toast the user didn't ask to expand.
  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.showVersionInformation', () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
      if (!folder) {
        void vscode.window.showWarningMessage('OvalLSP: no workspace folder is open.');
        return;
      }

      const diagnostic = versionDiagnostics.get(folder.uri.toString());
      outputChannel.appendLine(`--- OvalLSP version information: ${folder.name} ---`);
      if (!diagnostic) {
        outputChannel.appendLine('No version information yet -- the Core Server for this folder has not finished starting.');
        outputChannel.show();
        return;
      }

      const d = diagnostic.details;
      outputChannel.appendLine(`Compatible: ${diagnostic.compatible ? 'yes' : 'NO'}`);
      outputChannel.appendLine(`Extension version: ${d.extensionVersion}`);
      outputChannel.appendLine(`Core version: ${d.coreVersion ?? '(unknown)'}`);
      outputChannel.appendLine(`Client protocol version: ${d.clientProtocolVersion}`);
      outputChannel.appendLine(`Server protocol version: ${d.serverProtocolCurrent ?? '(unknown)'}`);
      outputChannel.appendLine(`Ruby running: ${d.rubyRunning ?? '(unknown)'}`);
      outputChannel.appendLine(`Ruby expected: ${d.rubyExpected ?? '(no bundled manifest -- monorepo/custom Core)'}`);
      outputChannel.appendLine(`Core selection: ${d.classification}`);
      outputChannel.appendLine(`Selected Core path: ${d.selectedCorePath}`);
      for (const reason of diagnostic.reasons) {
        outputChannel.appendLine(`  ✗ ${reason}`);
      }
      if (diagnostic.action) {
        outputChannel.appendLine(`Action: ${diagnostic.action}`);
      }
      outputChannel.show();

      void vscode.window.showInformationMessage(
        diagnostic.compatible
          ? `OvalLSP: Extension ${d.extensionVersion} / Core ${d.coreVersion ?? '(unknown)'} -- compatible. See the OvalLSP output channel for details.`
          : `OvalLSP: version incompatibility detected for ${folder.name}. See the OvalLSP output channel for details.`
      );
    })
  );
}

function stopClient(key: string): Thenable<void> {
  return stopClientWith(key, registry, lifecycle);
}

function queueClientTransition(key: string, transition: () => Promise<void>): Promise<void> {
  return clientTransitions.enqueue(key, transition);
}

function restartClientForFolder(
  folder: vscode.WorkspaceFolder,
  outputChannel: vscode.OutputChannel,
  context: vscode.ExtensionContext
): Promise<void> {
  if (!shutdownBarrier.permitsStart()) {
    return Promise.resolve();
  }
  const key = folder.uri.toString();
  return queueClientTransition(key, async () => {
    await stopClient(key);
    if (shutdownBarrier.permitsStart()) {
      clients.set(key, startClientForFolder(folder, outputChannel, context));
    }
  });
}

export function activate(context: vscode.ExtensionContext): void {
  // Module state survives deactivate() inside a live extension host, and
  // a closed barrier refuses every start. Reopen it before anything can
  // ask to spawn Core.
  shutdownBarrier.reset();
  const outputChannel = vscode.window.createOutputChannel('OvalLSP');
  context.subscriptions.push(outputChannel);

  const config = vscode.workspace.getConfiguration('ovallsp');
  if (config.get<boolean>('enabled') === false) {
    return;
  }

  registerObservationCommands(context, outputChannel);
  registerEnvironmentCommands(context, outputChannel);

  const statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  context.subscriptions.push(statusBarItem);
  context.subscriptions.push(startStatusPolling(statusBarItem));

  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const key = folder.uri.toString();
    if (!clients.has(key)) {
      clients.set(key, startClientForFolder(folder, outputChannel, context));
    }
  }

  // Workspace Trust can only go from untrusted to trusted while a window
  // stays open (never the reverse), and Server decided whether to start
  // the Runtime Agent once, at its own `initialize` time. Restarting each
  // client here re-sends `initialize` with `workspaceTrusted: true`, which
  // is simpler and more robust than adding a custom notification just for
  // this rare, one-time event.
  context.subscriptions.push(
    vscode.workspace.onDidGrantWorkspaceTrust(() => {
      for (const folder of vscode.workspace.workspaceFolders ?? []) {
        void restartClientForFolder(folder, outputChannel, context);
      }
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders((event) => {
      for (const folder of event.added) {
        const key = folder.uri.toString();
        if (shouldStartAddedFolder(shutdownBarrier.permitsStart(), clients.has(key))) {
          clients.set(key, startClientForFolder(folder, outputChannel, context));
        }
      }
      for (const folder of event.removed) {
        const key = folder.uri.toString();
        void queueClientTransition(key, () => Promise.resolve(stopClient(key)));
      }
    })
  );

  context.subscriptions.push(
    new vscode.Disposable(() => {
      for (const key of Array.from(clients.keys())) {
        void stopClient(key);
      }
    })
  );
}

export async function deactivate(): Promise<void> {
  shutdownBarrier.beginShutdown();
  const keys = new Set([...clients.keys(), ...clientTransitions.keys(), ...lifecycle.keys()]);
  await Promise.all(
    Array.from(keys).map((key) =>
      queueClientTransition(key, () => Promise.resolve(stopClient(key)))
    )
  );
  while (startAttempts.size > 0) {
    await Promise.all([...startAttempts]);
  }
  await lifecycle.drainRetirements();
}
