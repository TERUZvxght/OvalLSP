import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { WATCHED_FILES_GLOB } from '../../watchedFiles';

// Regression coverage for a real gap found reviewing packaging/release
// readiness: the extension's own FileSystemWatcher pattern
// (`**/{*.rb,*.erb,Gemfile.lock,db/structure.sql}`) previously had no
// `db/structure.sql` entry at all, so a Rails app configured for the SQL
// schema-dump format (`config.active_record.schema_format = :sql`) never
// had an external change to that file reach Core's own
// `workspace/didChangeWatchedFiles` handler -- the schema-wide model
// invalidation `Server` already implements for `db/schema.rb` was silently
// unreachable for any such app.
//
// Creates a *real* `vscode.workspace.createFileSystemWatcher` with the
// same exported glob the extension itself uses, and proves — through the
// real VS Code glob-matching implementation, not a hand-rolled one — that
// each of the four kinds of file this pattern exists for actually fires a
// change event: an ordinary `.rb` file, a migration-style `.rb` file, a
// Zeitwerk/Bundler `Gemfile.lock`, and `db/structure.sql` itself.
describe('OvalLSP extension watcher pattern reaches Core-relevant schema files', () => {
  it('fires for .rb, Gemfile.lock, and db/structure.sql changes, not only *.rb/*.erb', async function () {
    this.timeout(20000);

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceFolder!, WATCHED_FILES_GLOB)
    );

    const seen = new Set<string>();
    const disposable = watcher.onDidCreate((uri) => seen.add(uri.fsPath));

    try {
      const dbDir = path.join(workspaceFolder!.uri.fsPath, 'db');
      fs.mkdirSync(dbDir, { recursive: true });

      const candidates = {
        migration: path.join(dbDir, 'migrate', '20260101000000_create_widgets.rb'),
        structureSql: path.join(dbDir, 'structure.sql'),
        gemfileLock: path.join(workspaceFolder!.uri.fsPath, 'watcher_test_Gemfile.lock')
      };
      fs.mkdirSync(path.dirname(candidates.migration), { recursive: true });
      fs.writeFileSync(candidates.migration, '# frozen_string_literal: true\n');
      fs.writeFileSync(candidates.structureSql, '-- schema\n');
      fs.writeFileSync(candidates.gemfileLock, 'GEM\n');

      const deadline = Date.now() + 10000;
      const expectedBasenames = ['20260101000000_create_widgets.rb', 'structure.sql'];
      while (Date.now() < deadline && !expectedBasenames.every((name) => [...seen].some((p) => p.endsWith(name)))) {
        await new Promise((resolve) => setTimeout(resolve, 200));
      }

      assert.ok(
        [...seen].some((p) => p.endsWith('structure.sql')),
        `expected a create event for db/structure.sql; saw: ${[...seen].join(', ')}`
      );
      assert.ok(
        [...seen].some((p) => p.endsWith('20260101000000_create_widgets.rb')),
        `expected a create event for the migration file (matched by *.rb, not the new entry); saw: ${[...seen].join(', ')}`
      );

      fs.rmSync(dbDir, { recursive: true, force: true });
      fs.rmSync(candidates.gemfileLock, { force: true });
    } finally {
      disposable.dispose();
      watcher.dispose();
    }
  });

  it('does NOT match an unrelated file outside the watched set (sanity check on the pattern itself)', async function () {
    this.timeout(20000);

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceFolder!, WATCHED_FILES_GLOB)
    );

    const seen = new Set<string>();
    const disposable = watcher.onDidCreate((uri) => seen.add(uri.fsPath));

    try {
      const unrelated = path.join(workspaceFolder!.uri.fsPath, 'watcher_test_notes.txt');
      fs.writeFileSync(unrelated, 'not a Ruby/schema file');

      await new Promise((resolve) => setTimeout(resolve, 1500));

      assert.ok(![...seen].some((p) => p.endsWith('notes.txt')), 'the pattern must not match an unrelated .txt file');

      fs.rmSync(unrelated, { force: true });
    } finally {
      disposable.dispose();
      watcher.dispose();
    }
  });
});
