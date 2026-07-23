import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions
} from 'vscode-languageclient/node';
import { resolveServerConfig } from './serverConfig';

const clients = new Map<string, LanguageClient>();
const watchers = new Map<string, vscode.FileSystemWatcher>();

function startClientForFolder(
  folder: vscode.WorkspaceFolder,
  outputChannel: vscode.OutputChannel,
  context: vscode.ExtensionContext
): LanguageClient {
  const config = vscode.workspace.getConfiguration('rslsp', folder);
  const { command, args } = resolveServerConfig({
    rubyCommand: config.get<string | null>('ruby.command'),
    serverPath: config.get<string | null>('server.path'),
    extensionRoot: context.extensionPath
  });

  const serverOptions: ServerOptions = {
    run: { command, args, options: { cwd: folder.uri.fsPath } },
    debug: { command, args, options: { cwd: folder.uri.fsPath } }
  };

  // Forwarded to the server as workspace/didChangeWatchedFiles so files
  // edited or removed outside the open buffers (git checkout, another
  // editor, rm) still update the workspace index.
  const watcher = vscode.workspace.createFileSystemWatcher(
    new vscode.RelativePattern(folder, '**/*.{rb,erb}')
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
    synchronize: { fileEvents: watcher }
  };

  const client = new LanguageClient('rslsp', `RSLSP (${folder.name})`, serverOptions, clientOptions);
  client.start().then(undefined, (err) => outputChannel.appendLine(`failed to start Core Server: ${err}`));
  return client;
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
  const outputChannel = vscode.window.createOutputChannel('RSLSP');
  context.subscriptions.push(outputChannel);

  const config = vscode.workspace.getConfiguration('rslsp');
  if (config.get<boolean>('enabled') === false) {
    return;
  }

  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const key = folder.uri.toString();
    if (!clients.has(key)) {
      clients.set(key, startClientForFolder(folder, outputChannel, context));
    }
  }

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
