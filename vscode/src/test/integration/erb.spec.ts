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
    //
    // **The position is `name` inside `<%= name.upcase %>`, and that is
    // the whole repair.** This asked at (0, 0) against a fixture of
    // `<h1><%= @title %></h1>`, so it asked about the `<` of an HTML tag
    // in a file whose only Ruby was an ivar nothing in the workspace
    // assigns. The engine answers nothing at either — correctly, since it
    // cannot say what `@title` is — so the assertion could not pass
    // without the product asserting something it does not know, which is
    // the failure section 0 ranks worst. It failed on CI from 2026-08-24
    // and locally against both the source and the packaged Core.
    //
    // Driven before rewriting it: hover on this `name` answers `String`,
    // and on `upcase` answers `upcase() -> String`, so `.erb` really does
    // reach the Core and the old fixture was the only thing in the way.
    let hovers: vscode.Hover[] | undefined;
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
        'vscode.executeHoverProvider',
        fileUri,
        new vscode.Position(1, 8)
      );
      if (hovers && hovers.length > 0) {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    assert.ok(hovers && hovers.length > 0, 'expected the Core Server to answer hover for a .erb file');

    // And that the answer is the Core's, not an empty hover from some
    // other provider that happens to be registered. Without this the
    // example is satisfied by anything at all appearing.
    const text = hovers!
      .flatMap((hover) => hover.contents)
      .map((content) => (typeof content === 'string' ? content : content.value))
      .join('\n');
    assert.ok(
      text.includes('String'),
      `expected the Core Server's own answer for a String local, got: ${text}`
    );
  });
});
