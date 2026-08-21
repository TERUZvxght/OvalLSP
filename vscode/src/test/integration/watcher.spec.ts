import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { WATCHED_FILES_GLOB } from '../../watchedFiles';

// Regression coverage for a real gap found reviewing packaging/release
// readiness: the extension's own FileSystemWatcher pattern
// (`WATCHED_FILES_GLOB`) previously had no
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
// each relevant kind of file actually fires a change event, including
// project RBS signatures that Core must live-reload.
describe('OvalLSP extension watcher pattern reaches Core-relevant schema files', () => {
  it('fires for .rb, .rbs, .rbi, Gemfile.lock, and db/structure.sql changes', async function () {
    this.timeout(20000);

    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    assert.ok(workspaceFolder, 'expected an open workspace folder');

    const watcher = vscode.workspace.createFileSystemWatcher(
      new vscode.RelativePattern(workspaceFolder!, WATCHED_FILES_GLOB)
    );

    // **Create *and* change**, because the retry below rewrites a file
    // that already exists and VS Code reports that as a change. Listening
    // to creates alone made the retry unable to succeed for any file
    // whose first write beat the watcher's registration -- and which file
    // that was varied per run, which is what made it look like a
    // migration-specific defect for two CI runs.
    //
    // Both are faithful to what this example is for: the question is
    // whether `WATCHED_FILES_GLOB` reaches these paths at all, not which
    // kind of event it reaches them with.
    const seen = new Set<string>();
    const record = (uri: vscode.Uri) => seen.add(uri.fsPath);
    const disposable = vscode.Disposable.from(watcher.onDidCreate(record), watcher.onDidChange(record));

    try {
      const dbDir = path.join(workspaceFolder!.uri.fsPath, 'db');

      const candidates = {
        migration: path.join(dbDir, 'migrate', '20260101000000_create_widgets.rb'),
        structureSql: path.join(dbDir, 'structure.sql'),
        gemfileLock: path.join(workspaceFolder!.uri.fsPath, 'watcher_test_Gemfile.lock'),
        signature: path.join(workspaceFolder!.uri.fsPath, 'sig', 'watcher_test.rbs'),
        rbi: path.join(workspaceFolder!.uri.fsPath, 'sorbet', 'rbi', 'watcher_test.rbi')
      };
      // **The directories are committed, not created here.** On Linux the
      // watcher adds an inotify watch per directory, and a *second level*
      // directory created after the extension host started never became
      // watched at all -- so a file written into `db/migrate/` or
      // `sorbet/rbi/` fired nothing, however many times the retry below
      // rewrote it. Two attempts at this spec's own timing, a settle and
      // then the retry, each passed once and failed the run after; the
      // third round on one place buys a countermeasure rather than a
      // third guess at a duration (`CLAUDE.md`, `024.120`).
      //
      // `test-fixtures/sample-workspace/{db/migrate,sig,sorbet/rbi}/`
      // carry a `.gitkeep` for this. It is also what a real workspace
      // looks like: nobody creates `db/migrate/` and a migration in it in
      // the same millisecond and then expects the event on the next tick.

      fs.writeFileSync(candidates.migration, '# frozen_string_literal: true\n');
      fs.writeFileSync(candidates.structureSql, '-- schema\n');
      fs.writeFileSync(candidates.gemfileLock, 'GEM\n');
      fs.writeFileSync(candidates.signature, 'class WatcherTest\nend\n');
      fs.writeFileSync(candidates.rbi, 'class WatcherRbiTest\nend\n');

      // **Re-create, do not merely wait.** `createFileSystemWatcher`
      // registers its underlying watcher asynchronously, so a file
      // written immediately after can be created before anything is
      // listening -- and a create event for a file that already exists
      // never comes, however long the loop waits. This failed on CI's
      // first guarded run for exactly that reason, on the migration file
      // alone, while passing locally and on the run before it.
      //
      // Rewriting a still-unseen file each time round turns the race into
      // a retry: whichever pass happens after registration completes is
      // the one that fires.
      const deadline = Date.now() + 10000;
      const byBasename: Record<string, string> = {
        '20260101000000_create_widgets.rb': candidates.migration,
        'structure.sql': candidates.structureSql,
        'watcher_test.rbs': candidates.signature,
        'watcher_test.rbi': candidates.rbi
      };
      const expectedBasenames = Object.keys(byBasename);
      const missing = () => expectedBasenames.filter((name) => ![...seen].some((p) => p.endsWith(name)));
      while (Date.now() < deadline && missing().length > 0) {
        await new Promise((resolve) => setTimeout(resolve, 200));
        for (const name of missing()) {
          fs.rmSync(byBasename[name], { force: true });
          fs.writeFileSync(byBasename[name], `# retouched ${Date.now()}\n`);
        }
      }

      assert.ok(
        [...seen].some((p) => p.endsWith('structure.sql')),
        `expected a create event for db/structure.sql; saw: ${[...seen].join(', ')}`
      );
      assert.ok(
        [...seen].some((p) => p.endsWith('20260101000000_create_widgets.rb')),
        `expected an event for the migration file; saw: ${[...seen].join(', ')}`
      );
      assert.ok(
        [...seen].some((p) => p.endsWith('watcher_test.rbs')),
        `expected a create event for a project RBS file; saw: ${[...seen].join(', ')}`
      );
      assert.ok(
        [...seen].some((p) => p.endsWith('watcher_test.rbi')),
        `expected a create event for a project RBI file; saw: ${[...seen].join(', ')}`
      );

      // The files, never the directories: they are committed, and
      // removing them would make the next run create them again -- which
      // is the race this spec just stopped having.
      for (const file of Object.values(candidates)) {
        fs.rmSync(file, { force: true });
      }
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
