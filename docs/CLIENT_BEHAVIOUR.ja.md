# エディタとそのクライアントに依存している挙動

[English](CLIENT_BEHAVIOUR.md)

OvalLSP が**このツリーの外**（VS Code、`vscode-languageclient`、LSP 仕様）に
依存している挙動を、その根拠となる場所とともに全て挙げます。ツリーの他の場所は
ここを指すだけで、内容を書き直しません。

## この文書が存在する理由

0.2.7 は「新しい版数を持つ背後からの publish は、クライアントの陳腐化フィルタが
それを受理してしまうから危険だ」という一文を3ファイルに出荷しました。**これは
この製品のクライアントについては事実ではありません。** `vscode-languageclient`
の `handleDiagnostics` は `params.version` を完全に無視し、`params.diagnostics`
を uri ごとにキューへ入れます — 文字どおり後勝ちです。この主張は2リリース前の
スコープ文書から来て、検証されないままコードのコメントとタスク記録へ引用され、
ツリー内の何かではなくレビューラウンドによって発見されました。

**ツリーは既に知っていました。** `core/spec/ovallsp/server_publish_invariant_spec.rb`
は「VS Code は version で診断を捨てないので、その代償は誰も読まないフィールドを
買っただけだった」とずっと書いていて、一度も変わっていません。1つのツリーの中の
2ファイルが1つの外部事実について反対のことを主張していて、誰も気付けませんでした
— VS Code についての主張が、自分たちのコードについての主張と同じ声で書かれ、
どちらにも印が無いからです。

なので1箇所にまとめます。各項目には根拠を添えます。`vscode/PRIVACY.md` が
ディスクに書くものについて既に取っている形と同じで、理由も同じです — 複数の
場所に書かれた事実は、そのうちのどこかで間違います。

## 新しい項目を足すとき

**依存する前に**、根拠となるファイルと行を添えて行を足してください。「VS Code は
確かこうだったはず」がこの文書の対象とする失敗です。`vscode/node_modules` の中で
grep できる主張については、`core/spec/meta/client_behaviour_spec.rb` が該当ファイル
が今もそう言っているかを確認します（**checked** と印の付いた行）。

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
| Closing and reopening a file gives a **new document at version 1**, not a continuation of the old numbering. This is what made a stale publish from the closed buffer look newer than everything the reopened one could produce (`037`). | LSP specification, `textDocument/didOpen` | |
| A `didChange` may carry several changes, applied in order. | LSP specification | |

## Workspace and trust

| what we rely on | shown by | |
|---|---|---|
| **Workspace Trust is a VS Code concept with no LSP field.** The extension passes it through `initializationOptions`, and Core treats anything but a literal `true` as untrusted. | `vscode/package.json`'s `capabilities.untrustedWorkspaces`; `core/lib/ovallsp/server.rb`'s `#workspace_trusted?` | |
| `restrictedConfigurations` is what stops an untrusted workspace choosing which binary the extension runs. Settings not listed there are readable from an untrusted folder. | `vscode/package.json`; `vscode/src/test/unit/workspaceTrust.test.ts` checks every setting naming a binary is listed | checked |
| **On Windows, libuv searches the cwd before `PATH`.** A bare command name spawned with the workspace folder as cwd would run a binary the workspace supplied. POSIX `execvp` does not search the cwd. | Node/libuv process spawning; `vscode/src/platformCompatibility.ts`'s `spawnCwd` is the guard | |
| `code --uninstall-extension` does not call `deactivate()` in an already-running window. | VS Code's own extension lifecycle — recorded in `docs/RELEASE_CHECKLIST.md` #7 | |

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
