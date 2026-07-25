import * as assert from 'assert';
import * as path from 'path';
import * as vscode from 'vscode';

describe('OvalLSP extension (Extension Development Host)', () => {
  it('starts the Core Server and shows the fixed hover for a Ruby file', async function () {
    this.timeout(30000);

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    const fileUri = vscode.Uri.file(path.join(workspaceFolder!.uri.fsPath, 'app.rb'));
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document);

    // Poll instead of a fixed sleep: the Core Server process needs to spawn,
    // complete the LSP initialize handshake, and register the hover
    // provider before requests will return anything.
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

    assert.ok(hovers && hovers.length > 0, 'expected at least one hover result');
    const content = hovers![0].contents
      .map((c) => (typeof c === 'string' ? c : (c as vscode.MarkdownString).value))
      .join('\n');
    assert.match(content, /OvalLSP(?:\s|&nbsp;)connected/);
  });
});
