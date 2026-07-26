import * as assert from 'assert';
import * as path from 'path';
import * as vscode from 'vscode';

// Task 013 replaced the Core Server's original Task-001-era placeholder
// hover ("OvalLSP connected", a fixed string with no semantic content) with
// a real, type-engine-backed hover. This suite verifies that actual
// behavior end to end through a real Extension Development Host -- it must
// fail against a server that doesn't infer real types/origins, and it must
// not pass merely because *some* non-empty hover came back.
describe('OvalLSP extension (Extension Development Host)', () => {
  let workspaceFolder: vscode.WorkspaceFolder;
  let fileUri: vscode.Uri;

  before(async function () {
    this.timeout(30000);

    // Extension activation is itself asynchronous (Core Server spawn, LSP
    // initialize handshake); waiting on the extension's own activation
    // Promise -- rather than a fixed delay -- is what makes the polling
    // below bounded rather than a guess at how long that takes.
    const extension = vscode.extensions.getExtension('ovallsp.ovallsp');
    assert.ok(extension, 'expected the ovallsp.ovallsp extension to be installed in the test host');
    await extension!.activate();

    workspaceFolder = vscode.workspace.workspaceFolders?.[0]!;
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    fileUri = vscode.Uri.file(path.join(workspaceFolder.uri.fsPath, 'app.rb'));
    const document = await vscode.workspace.openTextDocument(fileUri);
    await vscode.window.showTextDocument(document);
  });

  // Deadline-bounded polling, never a fixed sleep: a hover provider isn't
  // registered until the Core Server's own `initialize` response comes
  // back, and `vscode.executeHoverProvider` simply returns an empty array
  // (not an error) until then, or when the query genuinely resolves to
  // nothing -- both need to be told apart from "hasn't started yet",
  // which only polling with a deadline can do.
  async function pollForHover(position: vscode.Position, deadlineMs: number): Promise<vscode.Hover[] | undefined> {
    const deadline = Date.now() + deadlineMs;
    let hovers: vscode.Hover[] | undefined;
    while (Date.now() < deadline) {
      hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
        'vscode.executeHoverProvider',
        fileUri,
        position
      );
      if (hovers && hovers.length > 0) {
        return hovers;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    return hovers;
  }

  function hoverText(hovers: vscode.Hover[]): string {
    return hovers[0].contents
      .map((c) => (typeof c === 'string' ? c : (c as vscode.MarkdownString).value))
      .join('\n');
  }

  it('infers the real type of a local variable assigned a String literal', async function () {
    this.timeout(30000);

    // `name = "ok"` on line 5 (1-indexed), then a bare reference to `name`
    // on line 6 -- hovering the reference must resolve to the type flowing
    // from its own assignment, not a placeholder.
    const hovers = await pollForHover(new vscode.Position(5, 4), 10000);

    assert.ok(hovers && hovers.length > 0, 'expected at least one hover result for the local variable reference');
    assert.strictEqual(hoverText(hovers!), 'String');
  });

  it('resolves a receiver-qualified call to its real declaration (Origin/Defined)', async function () {
    this.timeout(30000);

    // `App.new.call` on line 10 (1-indexed); `call` starts at character 8.
    // This exercises the same receiver-type-before-dot path Hover and
    // Completion share (Task 013), so the origin/definition lines only
    // appear when the Core Server has actually resolved `App.new`'s type
    // and looked up `#call` on it -- never coincidentally.
    const hovers = await pollForHover(new vscode.Position(9, 8), 10000);

    assert.ok(hovers && hovers.length > 0, 'expected at least one hover result for the receiver-qualified call');
    const content = hoverText(hovers!);
    // VS Code's Markdown renderer substitutes `&nbsp;` for a literal space
    // in hover content; a plain `assert.strictEqual`/space-only regex would
    // pass on the raw LSP payload but fail on what the editor actually
    // renders (the same trap the original, since-removed placeholder
    // assertion was worked around for).
    const escapedUri = fileUri.toString().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(content, /Origin:(?:\s|&nbsp;)source(?:\s|&nbsp;)declaration/);
    assert.match(content, new RegExp(`Defined:(?:\\s|&nbsp;)${escapedUri}:4`));
  });
});
