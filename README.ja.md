# OvalLSP — Ruby Semantic LSP

[English README](README.md) ·
[公式サイト](https://teruzvxght.github.io/OvalLSP/ja/)

> **開発途中のプロジェクトです。** 現在、開発者自身が調査・修正作業を
> 継続的に行っている段階のため、**外部からのissue提案・Pull Requestは
> 現在受け付けていません**。PRチェックが後回しになり、開発者側で
> 進行中の修正と内容が重複してしまう可能性があるためです。詳細は
> [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md)を参照してください。

Ruby/Rails向けセマンティック言語サーバーのmonorepo。設計の背景と全体方針は
[`docs/design/README.md`](docs/design/README.md)(日本語、内部設計文書) と
[`docs/design/START_HERE.md`](docs/design/START_HERE.md)(同上) を参照。

## Layout

- `core/` — Ruby製Core Language Server (`ovallsp`)。LSP 3.17をstdio/Content-Length framingで実装。
- `vscode/` — VS Code拡張 (TypeScript)。workspace folderごとに `core/bin/ovallsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書一式（PRD、architecture、ADR、実装タスク。日本語のみ、実装時の内部設計ログ）。
- `docs/design/docs/12-release-and-support.md` — 利用者向けリリースドキュメント
  (Installation、Security model、Configuration、Troubleshooting等。日本語)。
- `docs/SUPPORT_MATRIX.ja.md` / `docs/RELEASE_CHECKLIST.md` — 対応環境と1.0
  リリースチェックリスト。

## 機能・環境マトリクス

「どの機能か」と「どの環境か」の2軸です。

| | 意味 |
|---|---|
| ✅ | その環境でend-to-endに検証済み。壊れればテストが落ちる |
| ⚠️ | 動く可能性は高い(エンジンの多くは環境非依存)が、検証していないため何も保証しない |
| バージョン | 未実装。実装予定のリリース。⚠️と併記されている場合は、そのリリースで実装予定だが、その環境では依然として未検証という意味 |

以下はすべて公開している成果物、すなわち **darwin-arm64 のみ**が前提です。
Windows・Linux・Intel macOS 向けのVSIXは公開していません。それらをプラット
フォームごとに検証して公開することが、1.0.0の条件です(024.R4)。

| 機能 | Rails・信頼済み | Rails・未信頼 | 素のRuby(Railsなし) |
|---|---|---|---|
| Coreが起動し、ready状態に到達する | ✅ | ⚠️ | ⚠️ 1.0.0 |
| ウィンドウを閉じた後にプロセスが残らない | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Hover: リテラル・コンストラクタ・ローカル変数 | ✅ | ⚠️ | ⚠️ 1.0.0 |
| Hover: Active Recordのファインダ | ✅ | ―(Runtime Agentなし) | ― |
| Hover: ビュー内の`@ivar`(アクション由来) | ✅ | ⚠️ | ― |
| 補完: 標準ライブラリ(RBS) | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 補完: ワークスペースのインスタンスメソッド | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 補完: ワークスペースのシングルトンメソッド | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 補完: モデルのカラム・関連 | ✅ | ―(Runtime Agentなし) | ― |
| 補完: Active Recordのインスタンスapi | ✅ | ―(Runtime Agentなし) | ― |
| 補完: Active Recordのクラスapi | ✅ | ―(Runtime Agentなし) | ― |
| 補完: ルートヘルパー | ✅ | ―(Runtime Agentなし) | ― |
| 識別子を打ち始めた時点での補完 — 宣言済みクラス、スコープ内のローカル変数、その位置で呼べるメソッド | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 補完がタブストップ付きの呼び出し雛形を挿入する | ✅ | ⚠️ | ⚠️ 1.0.0 |
| メソッドのhoverに引数を表示する | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 定義へ移動: ワークスペースのメソッド | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 定義へ移動: モデルのカラム・関連 | ✅ | ―(Runtime Agentなし) | ― |
| 定義へ移動: 標準ライブラリ(RBSへ) | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 診断: 構文エラー | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 診断: ワークスペースクラスの未定義メソッド | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 診断: モデルの未定義メソッド | ✅ | ―(Runtime Agentなし) | ― |
| 診断: 未定義のルートヘルパー | ✅ | ―(Runtime Agentなし) | ― |
| 診断: 引数の個数違い | ⚠️ [^argcount] | ⚠️ | ⚠️ 1.0.0 |
| 診断: gemを継承したクラスでの未定義メソッド・変数 | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| 診断: 一度も代入されない `@ivar` の読み取り | ⚠️ [^ivar] | ⚠️ | ― |
| シグネチャヘルプ: ワークスペース・標準ライブラリ・ルートヘルパー | ✅ | ⚠️(ルートヘルパーは―) | ⚠️ 1.0.0 |
| 参照検索・リネーム [^rename]・シンボル検索 | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 診断: 引数の**型**違い | ⚠️ [^argtype] | ⚠️ | ⚠️ 1.0.0 |
| 診断: 開いているファイルだけでなくプロジェクト全体 | ⚠️ [^ws] | ⚠️ | ⚠️ 1.0.0 |
| hover・補完でのドキュメント(RDoc/YARD)表示 [^doc] | ✅ | ⚠️ | ⚠️ 1.0.0 |
| セマンティックハイライト(ローカル変数とメソッド呼び出しの区別)。`.rb` とERBテンプレートのRuby領域の両方 | ✅ | ⚠️ | ⚠️ 1.0.0 |
| 補完: Active Record の `Relation` API(`where`・`order`・`limit`) | 0.3.0 | ―(Runtime Agentなし) | ― |
| 補完: `self.` の後 | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| インレイヒント(推論した型・引数名) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| 各診断に対応するコードアクション/クイックフィックス | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| 型定義へ移動 | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| ドキュメント内ハイライト(ファイル内の出現箇所) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| コールヒエラルキー(呼び出し元・呼び出し先) | 0.3.0 | ⚠️ 0.3.0 | ⚠️ 1.0.0 |
| 検査ごとの診断severity設定 | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |
| `require` の自動挿入 | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |
| シグネチャヘルプ: 活性引数のハイライト | 0.4.0 | ⚠️ 0.4.0 | ⚠️ 1.0.0 |

[^argcount]: 壊れたら落ちるテストで検証しており、実際に発火もします。ただし
    Rubyの標準ライブラリ・Railsの5つのgem・minitest に対して出す15件は、
    すべて誤りです。原因はいずれも記録済みで、`def Const.method` が
    インスタンスメソッドとして記録される件(15件中10件)、ブロックの `self` が
    外側のクラスとして読まれる件、レシーバが名前の衝突で解決される件です。
    gemのコーパスは最悪に近い条件です — 依存先が存在しないため名前が置き換えで
    解決されます — 実アプリケーションでの精度は未計測です(024.40)。

[^argtype]: 壊れたら落ちるテストで検証してはいますが、実物のRubyに対して
    一度も発火していません。Rubyの標準ライブラリ・Railsの5つのgem・minitest の
    2,042ファイルに対して**0件**、prismに自身のRBSを読ませても0件でした。
    0.2.0の最後のレビューラウンド以前にこの検査が出した報告はすべて誤りで、
    それを直した結果0件になりました。報告するのは、RBS/RBIが引数の型を宣言して
    いて、オーバーロードがちょうど1つで `*rest` が無く、宣言側も引数側も素の
    クラスである場合に限られます(024.37)。

[^ivar]: ✅ は「その環境で壊れたらテストが落ちる」という意味ですが、E2Eの例が
    通るのは手書きの空の `ApplicationController` に対してであり、それは
    `rails new` が生成しない形です。Railties 7.2・8.0・8.1 はいずれも
    `allow_browser versions: :modern` を呼ぶ `ApplicationController` を生成し、
    モデル化していないクラスボディの呼び出しが1つでもあると、その下の全ビューで
    検査が黙ります。つまり既定のRailsアプリケーションでは、この検査は一度も
    発火しません(024.22)。

[^rename]: マクロが宣言したメソッド(`attr_accessor :name`、
    `delegate :title, to: :author` など)はリネームせず拒否します。書き換える
    識別子トークンが無く、呼び出し箇所だけを編集すると宣言が取り残されて
    ファイルが動かなくなるためです(024.28)。

[^ws]: ⚠️ が約束する以上、✅ が要求する以下です。ワークスペース全体のパスは
    Serverレベルのspecとユニットspecで覆われていますが、
    `docs/EXTENSION_CAPABILITIES.ja.md` にE2Eの行がありません。そのために
    書いた例 — 実物のRailsフィクスチャに置いた、一度も開かれないプローブ
    ファイル — が45秒経っても診断を出さなかったためです。024.14として記録、
    未解決。

[^doc]: レシーバを書いた場合に限ります。hoverでは `widget.charge` の形
    です。`def` 自体、レシーバなしの呼び出し、ERBテンプレート内のいずれを
    hoverしても、型は出ますがドキュメントは出ません。補完では `.` が出した
    一覧に限られ、本リリースで追加した前置きだけの一覧にドキュメントは
    付きません。`completionItem/resolve` がコメントを探すのに必要な情報を
    付けているのが、レシーバ経由の経路だけだからです。

バージョンが入っている行は、どの環境でもまだ実装していません。数値は実装予定の
リリースで、利用者が早く気づくものから並べています。いずれも **minor** リリースを
正確に名指ししており、`0.2.x` のような範囲表記は使いません。ケイパビリティは
minorでしか増えない——それがここでのminorの定義——ためで、patchが行を増やすことは
ありません。同じバージョンを共有する行は、0.1.6が5つ同時に出したように、その
リリースでまとめて出ます。

上の表の3行はPylance(動的型付け言語の言語サーバとして最も知られた基準)との比較
によるもので、0.2.0では2つをそのまま出しています。hoverでのドキュメント表示
(以前のhoverは「それが何か」しか言わず「何のためか」を言いませんでした)と、
セマンティックハイライト(Rubyの`foo`はローカル変数かメソッド呼び出しか曖昧で、
エンジンは判別できているのにエディタが知りませんでした)です。残る1つ、
プロジェクト全体の診断(以前は開いていないファイルの誤りが見えませんでした)は、
表の但し書きつきで出しています。まだバージョンが入っている行も同じ
基準で測っています。各項目の根拠と、Pylanceの機能の
うち意図的に**予定しない**ものは
[`docs/design/tasks/024-deferred-review-findings.md`](docs/design/tasks/024-deferred-review-findings.md)
(英語、024.R3)に記載しています。同じ計画をリリース単位で、「何ができるように
なるか」の形にまとめたものが [`docs/ROADMAP.ja.md`](docs/ROADMAP.ja.md) です。

このプロジェクトに変更を加える方は
[`docs/DOCUMENTATION_MAP.ja.md`](docs/DOCUMENTATION_MAP.ja.md) も参照して
ください。どの種類の変更がどの文書——`site/` 以下のページを含む——を古く
するか、そしてそのうちどの対応関係が既にテストで検査されているかを示して
います。

未定義メソッドの2行は、祖先がすべて既知のレシーバでのみ発火します。ワークスペースの
クラスか、Runtime Agentがメソッドを報告するActive Recordモデルです。gemを継承した
クラス(`ApplicationController`、したがって大半のコントローラやジョブ)では、意図的に
黙ります。そこで報告することは推測を意味するためです。gemが実際に定義しているものを
インデックスすることがこの制約を解くもので、上の行が0.3.0である理由です。

逆の事象——gemのクラスを**再オープン**しているワークスペースのファイルは、
そのクラスを定義しているファイルと見分けがつかない——は0.1.6まで誤検知でしたが、
0.1.7で修正済みです。すべてのRailsアプリケーションが持つ `test/test_helper.rb` の
`class ActiveSupport::TestCase` がこれにあたります。そのクラスが実際にどこから
来ているのかをRuntime Agentに問い合わせるため、静的な継承チェーンの「完全である」
という主張は、信用されるのではなく検証されます
([024.R5](docs/design/tasks/024-deferred-review-findings.md))。Runtime Agentが
いない場合(信頼されていないワークスペース、Railsアプリでない場合)は問い合わせ先が
存在しないため、従来どおりの読みになります。

未定義の**変数**は独立した行にしていません。Rubyではローカル変数でない裸の識別子は
self上の呼び出しとしてパースされるため、変数のタイポは同じ検査が同じ制約のもとで
報告します。未代入の `@ivar` は事情が異なり(Rubyは例外ではなく `nil` を返す)、
独自の行を持ちます。

「―」は、その環境では成り立ちようがない機能です。多くはRuntime Agentしか
供給できないRails由来のデータに依存するためで、未信頼のワークスペースでは
Agentを意図的に起動せず、Railsアプリでなければ報告する対象がありません。
`@ivar` の2行だけは理由が異なります。Railsのコントローラ/ビュー規約で辿れる
ERBビューに限定した機能なので、素のRubyプロジェクトにはその前提がありません。
いずれにせよ、壊れているのではなく設計上存在しません。

「―」の行に1つだけ、かつて「存在しないより悪い」ものがありました。ルートが
1つも読み込まれていないと、`*_path`/`*_url` の呼び出しが放置されずに存在
しないルートとして報告される件です。0.2.0で修正しました。空のルート表を答えと
読まず、ルート表が実際に届くまで検査を待つようにしています
([024.24](docs/KNOWN_LIMITATIONS.ja.md#現在まちがっている報告))。

素のRubyの列の⚠️は「動かない」という推測ではありません。現時点でもほとんどは
動作するはずです。1.0.0と併記しているのは、それを保証すること — Rails規約に
明示的な境界を設け、Railsでないプロジェクトで何を期待してよいかを規定すること
(`docs/design/tasks/024-deferred-review-findings.md` の024.R1) — が1.0.0に予約された
2条件の一方だからです。もう一方は残りのプラットフォームを検証して公開すること
です。それまでこの列は何も保証しません。

この表のバージョンの読み方は、patchが「利用者から見た振る舞いが変わらない」、
minorが「ケイパビリティが増えた」、majorが「利用者が依存していたものが動かなく
なった」です。正式な定義は [`docs/PUBLISHING.ja.md`](docs/PUBLISHING.ja.md)
にあります。

各✅は [`docs/EXTENSION_CAPABILITIES.ja.md`](docs/EXTENSION_CAPABILITIES.ja.md)
の各行に対応します。同文書は「利用者が何をして、何が起きなければならないか」
を記述し、`core/spec/e2e/capabilities_spec.rb` が検証します。ただしこの
スイートがCIで走るのはLinux上で、対象はCoreのソースです。各行が記述して
いるのはdarwin-arm64と同梱Coreであり、そこで走らせているワークフローは
ありません。`vscode/scripts/verify-installed-extension.sh` はインストール済み
拡張機能をend-to-endで確認しますが、手動実行です。呼び出しているワークフローは
ありません。

## Status

`docs/design/tasks/001-*.md` 〜 `023.8-*.md` を実装済み(Apple Silicon向け
Marketplace Preview公開済み)。詳細は`docs/RELEASE_CHECKLIST.md`と
`docs/SUPPORT_MATRIX.ja.md`を参照。

- LSP transport、didOpen/didChange/didClose、Hover/completion/signature help
- Prismによる宣言抽出とdocumentSymbol、永続キャッシュによるwarm start
- ワークスペース索引・definition・workspace/symbol・find references・rename
- ローカル型推論(`ovallsp/explainType`)、RBS/RBI連携
- Runtime Agentプロセス管理(hello/status/snapshot/model/reload/shutdown)、
  exponential backoff付き自動再起動とcrash loop保護
- Rails routesからの`*_path`/`*_url`補完・signature help・definition
- Active Recordモデルのcolumn/association型推論、Rails DSL(enum/scope/delegate)
- controller→viewへのinstance variable伝播(ERB)
- Plugin API(static/runtime)、プロセス隔離されたplugin実行
- opt-inのruntime型観測(Task 019)
- VSIXパッケージング、Ruby環境の自動解決(mise/asdf/rbenv/Homebrew/PATH)
- ログredaction、protocol version negotiation
- Extension/Core version・protocol handshake、LanguageClient lifecycle管理(Task 023)

`core/bin/ovallsp`はワークスペースroot直下に`bin/rails`があるRailsアプリを検出すると、
バックグラウンドスレッドでRuntime Agentを起動し、routesとmodelのsnapshotを取得して
補完・definition・型推論に反映する（Railsが無い/起動失敗時は静的機能のみで継続）。

VS Code拡張自体の利用者向け情報(インストール方法・設定・トラブル
シューティング等)は[`vscode/README.ja.md`](vscode/README.ja.md)を参照。

## Development

```bash
# Core Server
cd core
bundle install
bundle exec rspec

# VS Code Extension
cd vscode
npm install
npm run test:unit         # vscode API非依存の単体テスト
npm run test:integration  # Extension Development Hostでの実機テスト（VS Codeバイナリをダウンロードします）
```

## Contributing / Security / Support

- [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md)
- [SECURITY.ja.md](SECURITY.ja.md)
- [SUPPORT.ja.md](SUPPORT.ja.md)
- [CODE_OF_CONDUCT.ja.md](CODE_OF_CONDUCT.ja.md)
