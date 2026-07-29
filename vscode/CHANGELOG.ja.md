# 変更履歴

[English version](CHANGELOG.md)

OvalLSP VS Code拡張機能の注目すべき変更をすべて記録しています。

## 0.1.7 — 再オープンされたgemクラス

`docs/PUBLISHING.ja.md`のバージョン規約におけるpatchリリースです。誤った
報告を1つ取り除くだけで、何も追加しません。

- ワークスペースが**再オープン**しているだけのクラスに対して、gem自身の
  メソッドが存在しないと報告することがなくなりました。`test/test_helper.rb`
  の`class ActiveSupport::TestCase`はすべてのRailsアプリケーションが持つ
  形で、その`parallelize`と`fixtures`の呼び出しが0.1.6の抱えていた最後の
  2件の誤検知でした。実際のアプリケーションでの実測: 修正前2件、修正後0件。

  クラスの再オープンは、そのクラスを定義するコードと構文上まったく同じ
  です。したがってファイルをいくら読んでも区別はできません — 代わりに
  Runtime Agentに問い合わせます。答えはそのクラスの実際の祖先で、同じ
  プロセス自身の`Object.ancestors`を基準に測るため、`Object`に何かを
  混ぜているアプリケーションが自分で基準を較正します。クラスがまだ
  読み込まれていない場合は、autoloadの登録元で答えます。アプリケーション
  自身のクラスならワークスペース配下の絶対パス、gemのクラスならgemが
  書いたままの素のrequireパスです。

  この問い合わせは、レシーバだけでなく継承チェーン上のワークスペースが
  宣言したクラスすべてに対して行います。これが最も多いケースに届くための
  条件です。`ActiveSupport::TestCase`を再オープンすると、その名前は
  ワークスペース自身のものになるため、`class FooTest < ActiveSupport::TestCase`
  はいずれも「完全に見える」継承チェーンを引き継ぎ、プロジェクト内の
  すべてのテストファイルがgemのAPI全体を未定義として報告していました。

  この判定のために何かを読み込むことはありません。Runtime Agentが存在
  しない場合 — 信頼されていないワークスペース、Railsアプリでない
  プロジェクト — の挙動は従来どおりです。

- 実装中に見つかった2件のテスト不具合も修正しました。いずれも、通っては
  いるが何も検査していない検査でした。ケイパビリティ・カバレッジの検査は
  IDを1桁の正規表現で照合していたため、`G10`以降がすべて`G1`に潰れ、
  どちらの方向にも突き合わされていませんでした。もう1件は一時ファイルの
  リーク検査で、プロセス全体のオープンfd数を数えていたため、スイート全体
  の実行では差分が負の値になっていました。

## 0.1.6 — 実際に発火する補完と診断

`docs/PUBLISHING.ja.md`のバージョン規約におけるminorリリースです。5つの
ケイパビリティが「未実装」から検証済みへ移りました。いずれも、拡張機能が
提供しているように見えて実際には提供していなかったものです。

- 定数の後の補完(`User.`、`Article.`、`JSON.`)が候補を返すようになりま
  した。裸の定数が不明な型と評価されていたため、Rubyで最もよく使われる
  補完のきっかけが、これまでのすべてのリリースで空のリストを返していました。
- クラスに対する補完が、そのクラス自身の`def self.`メソッドを提示します。
- Active Recordモデルに対する補完が、すでに提示していたカラムや関連に
  加えて、Active Record自身のAPI — インスタンスでは`save`・`update`・
  `destroy`、クラスでは`all`・`find`・`where`・`create` — を提示します。
  Runtime Agentがアプリケーションが実際に読み込んだクラスから報告するため、
  使用中のRailsのバージョンと一致します。
- Active Recordモデルに存在しないメソッドの呼び出しを報告するようになり
  ました。モデルの祖先はワークスペースの外にあるため、この検査はすべての
  モデルに対して黙って無効化されていました。`method_missing`を定義して
  いるモデルや、カラムを読めなかったモデルに対しては引き続き黙ります。
- 引数の個数が合わない呼び出しを報告するようになりました。対象は、splatも
  `*rest`も持たない単一の定義に解決できる呼び出しに限ります。それより
  確実でないものは何も報告しません。

- 補完を確定すると、名前だけでなく呼び出しの形が書き込まれるようになりま
  した。引数が既知のメソッドは`takes_two(first, second)`となり各引数が
  タブストップになります。Railsが形を公開していない引数を取るメソッド
  (`where(*, **, &)`)は`where()`となりカーソルが括弧の中に入ります。
  引数を取らないメソッドは名前のままです。`save()`はRubyの書き方では
  ないためです。
- メソッド呼び出しへのhoverが引数一覧を表示します。従来はsignature helpを
  起動するために`(`を打ち直す必要がありました。

このリリースのその他の変更:

- `docs/EXTENSION_CAPABILITIES.ja.md`が「何が動かなければならないか」を
  記述し、その各行を`core/spec/e2e/capabilities_spec.rb`が実在のRails
  アプリケーションに対してend-to-endで検証します(実際のCoreをstdioで
  駆動し、Runtime AgentとCold Indexの完了を待ってから問い合わせます)。
  `vscode/scripts/verify-installed-extension.sh`は別途、実際のVS Codeが
  パッケージ済み拡張機能をインストールし、起動し、実行すること、そして
  ウィンドウを閉じた後に何も残らないことを確認します。
- 同梱するCoreが拡張機能のバージョンを名乗るようになり、パッケージング時
  に強制されます。従来のCoreは、どのリリースに同梱されていても`0.0.1`と
  報告していました。
- Rails内部のコールバックメソッドが補完を埋め尽くすことがなくなりました。

既知の制限: gemのクラスを**再オープン**しているワークスペースのファイルは、
そのクラスを定義しているファイルと区別がつかないため、未定義メソッドの
検査は祖先が完全だと読んでしまいます。`test/test_helper.rb`の
`class ActiveSupport::TestCase`がすべてのRailsアプリケーションでまさに
この形をしており、その`parallelize`と`fixtures`の呼び出しが未定義として
報告されます。1プロジェクトあたり1ファイルで2件です。0.1.7で修正しました。

## 0.1.5 — ライフサイクルの信頼性と、より深いセマンティック対応

- 再起動時・非アクティブ化時・再起動コマンドの重複時・initialize
  ハング時に、Coreプロセスと、macOS/Linuxでは発見した子孫プロセス
  グループを停止し刈り取ります。
- 慣習的な`before_action`コールバックが代入するコントローラのビュー用
  インスタンス変数を推論します。継承、`skip_before_action`、リテラルの
  `only:`/`except:`セレクタ、コールバックからアクションへの型の流れを
  含みます。
- 参照とRailsの生成メソッドをCold Indexに取り込み、宣言が現れたり消えたり
  したときに参照を再解決します。
- ローカル推論でRBS/RBIのoverload戻り値型を使用し、プロジェクトの
  シグネチャ変更をライブリロードします。opt-inのruntime観測は、他に
  Unknownとなる戻り値に対する低優先度のフォールバックとしてのみ使用
  します。
- Union補完の条件フラグ、生成メソッドの再オープン時フォールバック、
  モデル依存のメソッドサマリの陳腐化、Cold Indexの重複実行、手動再起動後の
  自動Agent再試行の遅延を修正しました。

## 0.1.4 — 「Payload hash mismatch」の誤警告を実際に修正

v0.1.3はこの修正を試みて成功していませんでした。警告は起動のたびに出続けて
いました。下記のv0.1.3の診断(`vsce publish`が自身のprepublishフックを
再実行し、native extensionを再ビルドしていた)は実在の問題であり修正済みの
ままですが、この警告の原因では**ありませんでした**。

実際の原因: `scripts/copy-core.js`はステージングした`core/`ツリー(815
ファイル)に対してsha256を記録する一方、`.vscodeignore`が独立して
`core/vendor/bundle/ruby/*/cache/**` — 4つのBundlerの`.gem`アーカイブ —
をVSIXから除外していました。したがってインストール済みの拡張機能は常に
811ファイルであり、起動時に再ハッシュしても記録されたハッシュを再現できる
ことは、どのマシンでも決してありませんでした。「payloadとは何か」の定義が
2つ独立に存在し、静かに食い違っていたのです。実際にインストールされた
v0.1.3を再ハッシュし、ステージングツリーとパッケージ済みツリーを比較して
確認しました。

ハッシュ側にパッチを当てるのではなく構造的に修正しました。これらの
キャッシュアーカイブはステージング時に削除します(純粋なビルド副産物です。
`bin/ovallsp`は`$LOAD_PATH`に`**/gems/*/lib`しか追加せず`cache/`は決して
追加しませんし、出荷されたVSIXにはもともと存在していませんでした)。
これによりステージングツリー**そのもの**が出荷ツリーとなり、ハッシュを
取ることに意味が生まれます。`.vscodeignore`の該当ルールは削除し、
`core/**`をこれ以上除外しないよう注記を残しました。

この種の欠陥が二度と利用者に届かないための新しい検査:
`scripts/verify-packaged-payload-hash.js`が**パッケージ済み**VSIXを
再ハッシュし、そのVSIX自身のmanifestと比較します — 拡張機能が起動時に
実行するのと同じ検査を、ビルド時に実行します。`release.sh`(publishの
確認プロンプトの前)とCIのpackage-contentsジョブの両方に組み込んであり、
ハッシュ対象と出荷物が今後乖離すればビルドが失敗します。古い
`.vscodeignore`のルールを一度戻して検査が失敗する(exit 1)ことを確認し、
元に戻して通ることを確認済みです。

## 0.1.3 — 修正: `vsce publish`が検証済みビルドを公開せず拡張機能を再ビルドしていた

**訂正:** このリリースは「Payload hash mismatch」の誤警告を修正したと
考えて公開されました。実際には修正できていません — 実際の原因は上記の
0.1.4を参照してください。以下に記述しているのは、このリリースが確かに
修正した、別個の実在するパッケージング欠陥であり、その修正は維持されて
います。

修正内容: `vscode/scripts/release.sh`(およびそれ以前は、別途ビルドした
後の裸の`vsce publish`)が`vsce publish --target darwin-arm64
--pre-release`を直接呼んでいました。`vsce publish`は、先行する
`npm run package`とは独立に自身の`vscode:prepublish`フックを実行します —
つまりCoreのvendoring済みnative extension(Prism、RBS)を静かにもう一度
ゼロから再ビルドします。native extensionのコンパイルは実行ごとにバイト
単位で再現可能ではないため、実際にMarketplaceへ届いていたのは、直前に
ビルドしsmoke testしハッシュを取った成果物では決してありませんでした —
毎回、検証されていないビルドが公開されていたのです。

`vsce publish`に独自の再ビルドをさせるのではなく、すでにビルド済みで
smoke test済みのVSIXファイルを`vsce publish --packagePath <file>
--pre-release`で公開することで修正しました。end-to-endで検証済みです。
この変更後は、ビルドのディスク上のpayloadハッシュがpublish手順によって
変化しないことを証明できます(再ビルドし、ハッシュを取り、publishを試み、
再ハッシュ — 両者は同一)。変更前は同じ手順で2つの異なるハッシュが
生成されていました。

## 0.1.2 — ドキュメント更新

コードおよび実行時の挙動に変更はありません。これまで文書化されておらず、
現在は検証済みとなった2つの事実をREADME(両言語版)に追記します。

- 互換性のあるRuby(3.4.x)がシステム上ですでに到達可能であれば、拡張機能を
  インストールするだけで実行できます — それ以外に別途のダウンロードや
  `bundle install`は不要です。
- 実在の、検証済みの競合: 他のRuby language server拡張機能(Shopify製
  Ruby LSPで検証)と同時に有効化すると、補完・定義の結果が重複します。
  VS Codeは有効なプロバイダすべての結果をマージし、どれか1つを選ぶわけ
  ではないためです。READMEの「他の拡張機能との既知の競合」を参照して
  ください。

## 0.1.1 — 修正: 公開されたVSIXに同梱Core Serverが入っていなかった

0.1.0は`vsce publish`を直接実行して公開されましたが、このコマンドは本
プロジェクト独自の`npm run package`ラッパー経由でない限りCore Serverの
vendoring(`vscode/scripts/copy-core.js`)を自動では行いません — 公開
された0.1.0のVSIXには`core/`ディレクトリがそもそも存在せず、Core Serverを
起動できませんでした。`vscode:prepublish`のnpmスクリプトを追加することで
構造的に修正しました。これは`vsce package`/`vsce publish`のどちらも、
どのように呼び出されてもパッケージング前に自動実行します — この失敗は
どの呼び出し経路からも起こり得なくなりました。

## 0.1.0 — Apple Silicon Marketplace Preview

最初のMarketplace Pre-Releaseです。macOS Apple Silicon(`darwin-arm64`)と
Ruby 3.4.xに限定しています。何が検証済みかは
[docs/SUPPORT_MATRIX.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SUPPORT_MATRIX.ja.md)
を、このPreviewで意図的に対象外としているものは
[docs/KNOWN_LIMITATIONS.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.ja.md)
を参照してください。

主な内容:

- hover、定義へ移動、documentSymbol、workspace/symbol、参照検索、
  ガード付きリネーム、そして実際のPrismベースのパースとワークスペース
  全体のインデックスに支えられた補完・signature help。
- opt-in trustのRuntime Agent経由での、ルートとActive Recordモデルに
  対するRailsを理解した補完・定義へ移動。
- RBS/RBIシグネチャ連携と、opt-inのruntime型観測。
- 拡張機能と同梱Core Serverの間のバージョン互換ハンドシェイク
  (`OvalLSP: Show Version Information`)。互換性のない、あるいは破損した
  Core Serverのビルドを、黙って、あるいは部分的に失敗させるのではなく
  明確に報告します。
- mise・asdf・rbenv・Homebrewを横断するRubyインタプリタの自動検出と、
  見つからない場合の明確な診断(`OvalLSP: Show Environment Diagnostics`)。
- Core Serverは拡張機能自体に同梱されます — 別途のインストール手順は
  不要で、拡張機能と一体で更新されます。

これはPreviewリリースです。外部からのフィードバック・issue受付の現状は
[SUPPORT.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.ja.md)
を参照してください。
