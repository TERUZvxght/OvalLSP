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

## 診断

| 依存している挙動 | 根拠 | |
|---|---|---|
| **クライアントは `publishDiagnostics` の `params.version` を無視します。** `params.diagnostics` を uri ごとにキューへ入れ、最後に届いた publish が、どの版数を持っていようとパネルに出るものになります。 | `vscode/node_modules/vscode-languageclient/lib/common/client.js` の `handleDiagnostics` | checked |
| したがって**順序付けはサーバの仕事**であってクライアントの仕事ではありません。`Server#publish_findings` が唯一の書き手で、全ての publish を自分で順序付けます。版数はクライアントへ情報として渡るだけで、クライアントがそれに基づいて動くことはありません。 | `core/lib/ovallsp/server.rb` | |
| `diagnostics` が空配列の publish は、その uri のパネルをクリアします。プロトコルに独立した「クリア」メッセージはありません。 | LSP 仕様、`textDocument/publishDiagnostics` | |
| 誰も publish しなくなった uri は、最後に渡されたものをセッションの間ずっと保持します。 | 同上 — publish 済みの一覧を失効させるものは無い | |

## 文書

| 依存している挙動 | 根拠 | |
|---|---|---|
| `didChange` は1打鍵につき1回届き、その都度版数が増えます。クライアント側で束ねるものはありません。 | LSP 仕様。0.2.7 の drive ラウンドで、22打鍵に対し 22 publish を実測 | |
| ファイルを閉じて開き直すと、**版数 1 の新しい文書**になります。古い採番の続きではありません。閉じたバッファからの古い publish が、開き直したバッファに出せるどの版数より新しく見えたのはこれが理由です（`037`）。 | **VS Code の挙動であって、プロトコルの保証ではありません。** 仕様は `TextDocumentItem.version` を「変更ごとに増える」と定めるだけで、開き直しで 1 に戻るとは書いていません。レビューラウンドが確認するまで仕様として引用していました — 各行が根拠を挙げることを契約としている文書で、funnel の最新の規則が乗っている行で、です。実地確認: `core/spec/e2e/` で開いて閉じて開き直すと、その `didOpen` は版数 1 を持ちます。 | |
| `didChange` は複数の変更を順に適用する形で届くことがあります。 | LSP 仕様 | |

## ワークスペースと信頼

| 依存している挙動 | 根拠 | |
|---|---|---|
| **Workspace Trust は VS Code の概念で、LSP のフィールドはありません。** 拡張機能が `initializationOptions` で渡し、Core はリテラルの `true` 以外を全て untrusted として扱います。 | `vscode/package.json` の `capabilities.untrustedWorkspaces`、`core/lib/ovallsp/server.rb` の `#workspace_trusted?` | |
| `restrictedConfigurations` が、信頼していないワークスペースに実行するバイナリを選ばせないための仕組みです。ここに挙がっていない設定は、信頼していないフォルダからも読まれます。 | `vscode/package.json`。`vscode/src/test/unit/workspaceTrust.test.ts` がバイナリを名指しする設定は全て挙がっていることを検査 | checked |
| **Windows では libuv が `PATH` より先に cwd を探索します。** ワークスペースフォルダを cwd にして裸のコマンド名を spawn すると、ワークスペースが置いたバイナリが動きます。POSIX の `execvp` は cwd を探索しません。 | Node/libuv のプロセス起動。`vscode/src/platformCompatibility.ts` の `spawnCwd` がその防御 | |
| `code --uninstall-extension` は、既に起動中のウィンドウでは `deactivate()` を呼びません。 | VS Code 自体の拡張機能ライフサイクル — `docs/RELEASE_CHECKLIST.md` #7 に記録 | |

## 言語機能

| 依存している挙動 | 根拠 | |
|---|---|---|
| **答えるものが無いリクエストは、空の結果オブジェクトではなく `null` を返す。** `textDocument/hover` は `Hover \| null` と宣言されているので、`{contents: {value: ""}}` は「存在して中身が空の hover」であり、クライアントが枠を描いてよい。 | `vscode/node_modules/vscode-languageserver-protocol/lib/common/protocol.d.ts` の `HoverRequest`: `ProtocolRequestType<HoverParams, Hover \| null, …>` | checked |
| **`DocumentSymbol#selectionRange` は識別子であって、シンボル全体の範囲ではない。** 型定義はこれを「そのシンボルが選ばれたときに選択され表示されるべき範囲。例えば関数の名前」と説明し、`range` に含まれていることを要求している。宣言全体を両方のフィールドに書くのは規約違反ではないが、このフィールドの意味を失わせる — アウトラインでクラスを選ぶと本体全体が選択されてしまう。 | `vscode/node_modules/vscode-languageserver-types/lib/esm/main.d.ts` の `DocumentSymbol` | checked |
| **`workspace/symbol` は `query` が空で届くことがあり、プロトコルはそれを「全シンボル」と定めています。** 型定義は、クライアントが全シンボルを要求するために空文字列を送っても*よい*と述べています。したがってサーバは、特定のクライアントがどうであれ空クエリに対して速くなければなりません。`vscode-languageclient` はエディタのクエリをそのまま転送し、何もフィルタしません。VS Code のピッカーが開いた瞬間に空クエリを送るかどうかは**ここでは確認していません** — レビューラウンドが、確認済みであるかのように公開されていたその主張を見つけました。エンジンが実際に依拠しているのは上記の「許可」の方です。 | `vscode/node_modules/vscode-languageserver-protocol/lib/common/protocol.d.ts` の `WorkspaceSymbolParams.query`、`vscode/node_modules/vscode-languageclient/lib/common/workspaceSymbol.js` の `provideWorkspaceSymbols` | checked |

## 起動

| 依存している挙動 | 根拠 | |
|---|---|---|
| 起動時、復元される全エディタについて `didOpen` が続けて届きます。 | 実測。`core/lib/ovallsp/server.rb` の束ね処理の箇所に記載 | |
| `initialize` に応答するまでクライアントは他を送らないので、応答前に重い処理を走らせてはいけません。`core/spec/ovallsp/server_cold_index_spec.rb` が順序を固定しています。 | LSP 仕様 | |

## Marketplace

| 依存している挙動 | 根拠 | |
|---|---|---|
| 公開された VSIX はアップロードしたものとバイト単位で同一に配信されるので、公開後に SHA-256 を照合できます。 | 各リリースで gallery API に対して検証。`docs/RELEASE_ARTIFACTS.md` にハッシュを記録 | |
| 現在 `vsce publish` が使うのは PAT 方式です。 | `docs/PUBLISHING.md` の Credentials 節 | |
