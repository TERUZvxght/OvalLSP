import * as fs from 'fs';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions
} from 'vscode-languageclient/node';
import { resolveServerConfig } from './serverConfig';
import { resolveRuby, RubyResolution } from './rubyResolver';

const clients = new Map<string, LanguageClient>();
const watchers = new Map<string, vscode.FileSystemWatcher>();
// The Ruby resolution actually used to launch each folder's client — kept
// around purely so `OvalLSP: Show Environment Diagnostics` can show *why*
// that Ruby was picked without re-running the search (020's "Ruby
// executable選択理由を診断画面で確認できる").
const rubyResolutions = new Map<string, RubyResolution>();

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

  const { command, args } = resolveServerConfig({
    rubyCommand: resolvedRubyCommand,
    serverPath: config.get<string | null>('server.path'),
    extensionRoot: context.extensionPath
  });

  const serverOptions: ServerOptions = {
    run: { command, args, options: { cwd: folder.uri.fsPath } },
    debug: { command, args, options: { cwd: folder.uri.fsPath } }
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
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(folder, '**/{*.rb,*.erb,Gemfile.lock}')
  );
  watchers.set(folder.uri.toString(), watcher);

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'ruby', pattern: `${folder.uri.fsPath}/**/*` },
      // Matched by extension, not language id: VS Code doesn't assign a
      // built-in language id to .erb, and requiring another extension to
      // register one first would make Task 008's view support silently
      // unreachable (docs/design/tasks/008-controller-view-propagation.md).
      { scheme: 'file', pattern: `${folder.uri.fsPath}/**/*.erb` }
    ],
    workspaceFolder: folder,
    outputChannel,
    synchronize: { fileEvents: watcher },
    // There's no standard LSP field for workspace trust, so it's passed
    // through here — the Core Server must not launch the Runtime Agent
    // (Rails/Bundler code execution) in an untrusted workspace
    // (docs/design/docs/02-architecture.md section 11).
    initializationOptions: { workspaceTrusted: vscode.workspace.isTrusted }
  };

  const client = new LanguageClient('ovallsp', `OvalLSP (${folder.name})`, serverOptions, clientOptions);
  client.start().then(undefined, (err) => outputChannel.appendLine(`failed to start Core Server: ${err}`));
  return client;
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
const STATUS_LABELS: Record<string, string> = {
  indexing: '$(sync~spin) OvalLSP: Indexing',
  'ready-static': '$(check) OvalLSP: Ready (static)',
  'ready-rails': '$(check) OvalLSP: Ready (Rails)',
  'agent-unavailable': '$(warning) OvalLSP: Agent unavailable'
};

function startStatusPolling(statusBarItem: vscode.StatusBarItem): vscode.Disposable {
  const interval = setInterval(() => {
    void (async () => {
      const uri = vscode.window.activeTextEditor?.document.uri;
      const folder = uri ? vscode.workspace.getWorkspaceFolder(uri) : vscode.workspace.workspaceFolders?.[0];
      const client = folder ? clients.get(folder.uri.toString()) : undefined;
      if (!client) {
        statusBarItem.hide();
        return;
      }

      try {
        const result = await client.sendRequest<{ state: string }>('ovallsp/status', {});
        statusBarItem.text = STATUS_LABELS[result.state] ?? `OvalLSP: ${result.state}`;
        statusBarItem.show();
      } catch {
        statusBarItem.text = '$(error) OvalLSP: Configuration error';
        statusBarItem.show();
      }
    })();
  }, 2000);

  return new vscode.Disposable(() => clearInterval(interval));
}

function registerEnvironmentCommands(
  context: vscode.ExtensionContext,
  outputChannel: vscode.OutputChannel
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.restartServer', async () => {
      for (const folder of vscode.workspace.workspaceFolders ?? []) {
        const key = folder.uri.toString();
        await stopClient(key);
        clients.set(key, startClientForFolder(folder, outputChannel, context));
      }
      void vscode.window.showInformationMessage('OvalLSP: Core Server restarted.');
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('ovallsp.restartAgent', async () => {
      const client = clientForActiveEditor(outputChannel);
      if (!client) {
        return;
      }
      await client.sendRequest('ovallsp/restartAgent', {});
      void vscode.window.showInformationMessage('OvalLSP: Runtime Agent restart requested.');
    })
  );

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
}

function stopClient(key: string): Thenable<void> {
  watchers.get(key)?.dispose();
  watchers.delete(key);

  const client = clients.get(key);
  if (!client) {
    return Promise.resolve();
  }
  clients.delete(key);
  return client.stop();
}

export function activate(context: vscode.ExtensionContext): void {
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
        const key = folder.uri.toString();
        void stopClient(key).then(() => {
          clients.set(key, startClientForFolder(folder, outputChannel, context));
        });
      }
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders((event) => {
      for (const folder of event.added) {
        const key = folder.uri.toString();
        if (!clients.has(key)) {
          clients.set(key, startClientForFolder(folder, outputChannel, context));
        }
      }
      for (const folder of event.removed) {
        void stopClient(folder.uri.toString());
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
  await Promise.all(Array.from(clients.keys()).map((key) => stopClient(key)));
}
