// The glob pattern used for the `FileSystemWatcher` each workspace folder's
// client registers, forwarded to the Core Server as
// `workspace/didChangeWatchedFiles` (see `startClientForFolder` in
// `extension.ts` for the full rationale, including why `Gemfile.lock` and
// `db/structure.sql` specifically are included). Extracted into its own
// exported constant so it can be exercised directly by a real
// `vscode.workspace.createFileSystemWatcher` in an integration test, not
// just asserted on as a string.
export const WATCHED_FILES_GLOB = '**/{*.rb,*.erb,Gemfile.lock,db/structure.sql}';
