import * as assert from 'assert';
import * as path from 'path';
import * as vscode from 'vscode';

describe('OvalLSP extension .erb support (Extension Development Host)', () => {
  it('forwards a .erb file to the Core Server (documentSelector actually matches it)', async function () {
    this.timeout(30000);

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    const fileUri = vscode.Uri.file(path.join(workspaceFolder!.uri.fsPath, 'view.html.erb'));
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document);

    // If the .erb documentSelector entry didn't match, no hover provider
    // would ever be registered for this file and this stays empty forever
    // regardless of how long we poll — it would time out below.
    let hovers: vscode.Hover[] | undefined;
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
        'vscode.executeHoverProvider',
        fileUri,
        new vscode.Position(0, 0)
      );
      if (hovers && hovers.length > 0) {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    assert.ok(hovers && hovers.length > 0, 'expected the Core Server to answer hover for a .erb file');
  });
});
