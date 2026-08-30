# What this project relies on the editor and its client to do

[日本語版](CLIENT_BEHAVIOUR.ja.md)

Every behaviour OvalLSP depends on from **outside this tree** — VS Code,
`vscode-languageclient`, the LSP specification — with the place that
shows it. Nothing else in the tree restates one of these; they point
here.

## Why this file exists

0.2.7 shipped a sentence in three files saying that a background publish
carrying a new version number is dangerous "because the client's
staleness filter accepts it". **That is not true of this product's
client.** `vscode-languageclient`'s `handleDiagnostics` ignores
`params.version` entirely and queues `params.diagnostics` by uri — last
write wins, literally. The claim came from a scope document written two
releases earlier, was quoted into code comments and a task record without
being checked, and was found by a review round rather than by anything in
the tree.

The tree already knew. `core/spec/ovallsp/server_publish_invariant_spec.rb`
had said "VS Code does not discard diagnostics on version, so the price
bought a field nobody reads" the whole time, unchanged. Two files in one
tree asserted opposite things about one external fact, and nothing could
notice, because a claim about VS Code is written in the same voice as a
claim about our own code and neither is marked.

So: one place, each entry naming what shows it. The same arrangement
`vscode/PRIVACY.md` already has for what is written to disk, and for the
same reason — a fact restated in several places will be wrong in one of
them.

## What to do with a new one

Add a row before relying on it, with the file and line that shows it.
"I remember that VS Code…" is the failure mode this file is for. Where a
claim is greppable in `vscode/node_modules`,
`core/spec/meta/client_behaviour_spec.rb` checks the named file still
says it — those rows are marked **checked**.

## Diagnostics

| what we rely on | shown by | |
|---|---|---|
| **The client ignores `params.version` on `publishDiagnostics`.** It queues `params.diagnostics` by uri; the last publish to arrive is what the panel shows, whatever version it carries. | `vscode/node_modules/vscode-languageclient/lib/common/client.js`, `handleDiagnostics` | checked |
| So **ordering is the server's job**, not the client's. `Server#publish_findings` is the only writer and orders every publish itself. A version travels to the client as information, not as something it acts on. | `core/lib/ovallsp/server.rb` | |
| A publish with an empty `diagnostics` array clears the panel for that uri. There is no separate "clear" message in the protocol. | LSP specification, `textDocument/publishDiagnostics` | |
| A uri nobody publishes to again keeps whatever it was last given, for the lifetime of the session. | the same — nothing expires a published list | |

## Documents

| what we rely on | shown by | |
|---|---|---|
| `didChange` arrives once per keystroke, with the version incremented each time. Nothing coalesces on the client side. | LSP specification; measured directly in 0.2.7's drive round at 22 publishes for 22 keystrokes | |
| Closing and reopening a file gives a **new document at version 1**, not a continuation of the old numbering. This is what made a stale publish from the closed buffer look newer than everything the reopened one could produce (`037`). | **VS Code behaviour, not a protocol guarantee.** The specification defines `TextDocumentItem.version` as increasing per change and says nothing about a reopen restarting it. Cited as the spec until a review round checked — in the one document whose contract is that each row names what shows it, and on the row the funnel's newest rule rests on. Driven directly: `core/spec/e2e/` opens, closes and reopens a file and the reopened `didOpen` carries version 1. | |
| A `didChange` may carry several changes, applied in order. | LSP specification | |

## Workspace and trust

| what we rely on | shown by | |
|---|---|---|
| **Workspace Trust is a VS Code concept with no LSP field.** The extension passes it through `initializationOptions`, and Core treats anything but a literal `true` as untrusted. | `vscode/package.json`'s `capabilities.untrustedWorkspaces`; `core/lib/ovallsp/server.rb`'s `#workspace_trusted?` | |
| `restrictedConfigurations` is what stops an untrusted workspace choosing which binary the extension runs. Settings not listed there are readable from an untrusted folder. | `vscode/package.json`; `vscode/src/test/unit/workspaceTrust.test.ts` checks every setting naming a binary is listed | checked |
| **On Windows, libuv searches the cwd before `PATH`.** A bare command name spawned with the workspace folder as cwd would run a binary the workspace supplied. POSIX `execvp` does not search the cwd. | Node/libuv process spawning; `vscode/src/platformCompatibility.ts`'s `spawnCwd` is the guard | |
| `code --uninstall-extension` does not call `deactivate()` in an already-running window. | VS Code's own extension lifecycle — recorded in `docs/RELEASE_CHECKLIST.md` #7 | |

## Language features

| what we rely on | shown by | |
|---|---|---|
| **A request that has nothing to answer returns `null`, not an empty result object.** `textDocument/hover` is declared `Hover \| null`, so `{contents: {value: ""}}` is a hover that *exists* and happens to be blank — a client is entitled to render a frame for it. | `vscode/node_modules/vscode-languageserver-protocol/lib/common/protocol.d.ts`, `HoverRequest`: `ProtocolRequestType<HoverParams, Hover \| null, …>` | checked |
| **`DocumentSymbol#selectionRange` is the identifier, not the symbol's whole range.** The types call it "the range that should be selected and revealed when this symbol is being picked, e.g the name of a function", and require it to be contained by `range`. Writing the whole declaration into both fields is legal and defeats the field: picking a class in the outline selects its entire body. | `vscode/node_modules/vscode-languageserver-types/lib/esm/main.d.ts`, `DocumentSymbol` | checked |
| **`workspace/symbol` may arrive with an empty `query`, and the protocol defines that as "all symbols".** The types say a client *may* send an empty string to request every symbol, so the server has to be fast on it whatever any one client does; `vscode-languageclient` forwards the editor's query unchanged and filters nothing. Whether VS Code's picker sends one the moment it opens is **not checked here** — a review round found that claim published as though it were, and the permission above is what the engine actually rests on. | `vscode/node_modules/vscode-languageserver-protocol/lib/common/protocol.d.ts`, `WorkspaceSymbolParams.query`; `vscode/node_modules/vscode-languageclient/lib/common/workspaceSymbol.js`, `provideWorkspaceSymbols` | checked |
| **A `null` answer to `textDocument/prepareRename` means renaming at that position is not valid**, and prepare is the gate in front of `textDocument/rename`: a client that declares `prepareSupport` asks it first, and the specification's own wording for the null answer is that the rename is not valid there. That is what `Server#prepare_rename_result` answering `nil` is for, and what its deliberate cold refusal rests on. **Not marked checked**: `vscode/node_modules` was not installed when this row was written, so nothing here has read whether VS Code's rename box opens anyway — the engine relies on the protocol's meaning, not on one editor's UI, and the row says so rather than implying it was verified. | LSP specification, `textDocument/prepareRename` (`Range \| { range, placeholder } \| { defaultBehavior } \| null`) and the client capability `rename.prepareSupport` | |

## Startup

| what we rely on | shown by | |
|---|---|---|
| The client sends `didOpen` for every restored editor back to back at startup. | measured; `core/lib/ovallsp/server.rb` notes it at the batching site | |
| `initialize` must be answered before the client will send anything else, so nothing slow may run before the reply. `core/spec/ovallsp/server_cold_index_spec.rb` pins the ordering. | LSP specification | |

## Marketplace

| what we rely on | shown by | |
|---|---|---|
| A published VSIX is served byte-identical to what was uploaded, so its SHA-256 can be verified after publishing. | verified each release against the gallery API; `docs/RELEASE_ARTIFACTS.md` records the hashes | |
| PAT-based publishing is what `vsce publish` uses today. | `docs/PUBLISHING.md`'s Credentials section | |
