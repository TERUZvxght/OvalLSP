// The glob pattern used for the `FileSystemWatcher` each workspace folder's
// client registers, forwarded to the Core Server as
// `workspace/didChangeWatchedFiles` (see `startClientForFolder` in
// `extension.ts` for the full rationale, including why `Gemfile.lock` and
// `db/structure.sql` specifically are included). Extracted into its own
// exported constant so it can be exercised directly by a real
// `vscode.workspace.createFileSystemWatcher` in an integration test, not
// just asserted on as a string.
//
// **`.rake` was missing for three releases.** `ColdIndexer`'s
// `DEFAULT_INCLUDED_EXTENSIONS` is `%w[.rb .rake .erb]`, so a `.rake` file
// was read at startup and then never watched: an unopened one could be
// edited, added or deleted outside the editor and the index kept answering
// from the first read. `scripts/check_watched_extensions.rb` compares the
// two sets now, in both directions, because they had drifted silently.
// Found by the 2026-09-05 critical review, R12.
//
// The signature and schema entries are deliberately *not* in Core's
// indexing set -- they are watched for a different reason, and the check
// knows them as such.
export const WATCHED_FILES_GLOB = '**/{*.rb,*.rake,*.rbs,*.rbi,*.erb,Gemfile.lock,db/structure.sql}';
