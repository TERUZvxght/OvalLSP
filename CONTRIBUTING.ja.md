# Contributing

[English version](CONTRIBUTING.md)

**現在、外部からのissue・Pull Requestは受け付けていません。** 開発者
自身が現在このコードベースの調査・修正作業を継続的に行っており、外部PR
のレビューはその作業より後回しになります — つまり、提出されたPRが
開発者側で進行中の変更と重複・衝突してしまう可能性があり、それを
タイムリーに検知できません。同じ理由でこのリポジトリのIssuesは
無効化されています。

コードベースがより安定した段階に達したら変更される予定で、その際は
本文書を更新します。それまでの間、forkして手元で試すことは自由に
行っていただけます。

OvalLSPへの関心をありがとうございます。このプロジェクトは現在
active PreviewとしてContributingしています。以下はリポジトリの
実際の運用方法を反映しています。

## リポジトリ構成

- `core/` — Ruby製Core Language Server (`ovallsp`)。LSP 3.17をstdio上で実装。
- `vscode/` — VS Code拡張(TypeScript)。workspace folderごとに
  `core/bin/ovallsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書・ADR・タスクごとの実装ノート
  (`docs/design/tasks/*.md`)。
- `docs/` — 利用者・リリース向け文書(Support Matrix、Release
  Checklist、SBOM、Security Checklist)。

## 開発環境セットアップ

Ruby 3.4.xとNode.jsが必要です(対象のVS Code APIバージョンは
`vscode/package.json`の`engines.vscode`を参照)。

```bash
cd core && bundle install
cd ../vscode && npm install
```

Coreのスイートのうち2つは、fakeではなく実際のRailsアプリケーションを
動かすため、`rails ~> 8.1`と`sqlite3`が**ローカル**gemとして解決できる
必要があります。`core/spec/fixtures/rails_real`は`--local`でbundleされる
ので、取得可能なネットワークがあるだけでは足りません:

```bash
gem install rails -v "~> 8.1" && gem install sqlite3
```

これらが無いと`spec/e2e/capabilities_spec.rb`と
`spec/integration/real_rails_spec.rb`は**まるごと**skipされ、それでも
`rspec`は0で終了します — つまりローカルの実行はgreenと報告する一方で、
capability行が真かどうかを決めるスイートは1つも走っていません。これを
捕まえているのはCIの"Fail if the real-Rails or capability suites were
skipped instead of run"ステップだけであり、したがってこの問題はローカル
でのみ牙を剥きます。実行結果に`NOT YET`と書かれていないpending例が1つでも
あれば、それがこれです。

## テストの実行

> **2026-08-05から2026-08-11の間にこのリポジトリをcloneまたはcheckoutし、
> Coreのテストスイートを実行した場合、リポジトリ外のディレクトリが削除されて
> います。**
>
> キャッシュ削除のテスト例が、ディレクトリを削除するコードへ捏造した絶対パス
> (`current: "/x"`)を渡していました。掃除対象がファイルシステムのルートに解決
> され、最終更新が最も新しい1つを残して他を削除したため、macOSでは
> `/Applications`がSIP保護されていないものを失いました。保護パスで例外が出た
> 時点で停止したので、一部のアプリだけが生き残ります。テスト対象のメソッドが
> すべての例外を握り潰すため、実行結果はgreenと報告されていました。
>
> 該当コミットは`28a041c`(2026-08-05)から修正までで、タグ`v0.2.1`はこれを
> 含みます。Time Machineか各アプリのインストーラから入れ直してください ——
> このリポジトリ側で復旧できるものはありません。
>
> **公開済みの拡張機能は影響を受けていません。** `core/spec/**`はVSIXから
> 除外されており、本番の唯一の呼び出し元は2つのパスを同じキャッシュrootから
> 導出するため、掃除がそこから出ることはできません。到達しうるのは、ソース
> checkoutからこのリポジトリのテストスイートを走らせた場合だけです。

```bash
# Core Server (Ruby)
cd core && bundle exec rspec

# VS Code extension (TypeScript単体テスト)
cd vscode && npm run test:unit

# VS Code extension (統合テスト、実際のExtension Development Host)
cd vscode && npm run test:integration
```

`npm run test:integration`はmonorepo相対のCore Serverに対して拡張機能を
テストします(packagingステップ不要)。`npm run test:integration:packaged`
はさらに先に`copy-core.js`を実行し、packaging済みのCore配置に対して
テストします — `vscode/scripts/copy-core.js`やVSIX packaging自体を
変更する際に有用です。

## このプロジェクトが守っているコード規律

- すべてのバグ修正には、その修正がなければ実際に失敗するregression
  テストを付ける(修正を一時的に戻してテストが失敗することを確認した後、
  修正を復元する形で検証済み) — たまたま通るテストではなく。
- 修正は報告された症状だけでなく根本的な設計に対処する — レビューでの
  発見が「このアーキテクチャがこの種のバグを許容している」ことを示唆
  する場合、修正すべきはアーキテクチャ自体である。
- 新機能・修正には自身のテストが含まれることが期待される。変更する
  挙動に対するテストカバレッジのないPRは、そのままマージされる可能性は
  低い。
- 振る舞いに関する主張は、受け入れるのではなく確かめる。意味論の問いは
  Rubyインタプリタに対して、「どれくらい起きるか」の問いは実際のコードに
  対して。レビューの指摘も、何かを「意図的」と呼ぶ根拠も、行動に移す前に
  検証する。
- 本当のtrade-offを伴う設計判断(自明な実装詳細ではなく)は
  `docs/design/adrs/`配下にADRとして記録する。
- 新しく書くコードは、目の前の要求を満たす最も単純な構成にする。次の
  要求が形を変えることは許容する。「単純」の尺度は行数ではなく、
  ひとつの事実について**同期させ続けねばならない箇所の数**である。
  これは書くときの規律であって、既に動いているコードの単純化は通常の
  変更と同じ扱い — 失敗を確認したテストとコーパス実測を要する。本
  プロジェクトの後付け単純化の戦績は 8 件中 0 件である。

## ブランチとプルリクエスト

**1バージョンにつき1ブランチ、`main`へのマージはプルリクエストで。**
ブランチ名は`release/<version>` — `release/0.3.0` — で、そのリリースの
コミットはすべてそこに載せます。

```bash
git switch -c release/0.3.0
```

`main`は「出荷済みのもの」です。リリースは自分のブランチで組み立てられ、
1本のプルリクエストとして到着します。それがレビュアーの読む単位です:
0.2.15から0.2.18は`main`の上で直接作られたため、各リリースの変更集合は
「誰かが再構成しなければならないコミット範囲」としてしか存在しませんでした。

名前に`feat/`や`fix/`は付けません。それは作業を始める前にリリースの中身に
ついて主張することだからです — 0.2.17はfixと名付けられて capability を
出荷しました。1バージョン1つの名前なら、その推測は要りません。
**`main`は直接pushを拒否します。これはこの段落ではなくGitHub側で強制
されています。** 2026-09-01設定。有効な内容:

- プルリクエスト必須。**承認レビューは0件**です — GitHubは自分自身の
  プルリクエストを承認させないため、1人のメンテナだと自分のリポジトリ
  から締め出されてしまいます;
- **必須ステータスチェック10件** — `Core Server (Ruby 4.0, informational)`
  を除く全CIジョブ。これはプレビュー版で、落ちることが想定されています;
- マージ前に`main`に追随していること;
- **管理者にも適用**されます。ここに書かれた規則が「一部の人だけが従う
  もの」にならないようにするためです;
- force pushとブランチ削除は拒否されます。

実際に試して確認しました: `main`への直接pushは
`GH006: Protected branch update failed` — 「変更はプルリクエスト経由で
行う必要があります」「必須ステータスチェック10件のうち10件が要求されて
います」と返ります。

オーナーはリポジトリのSettings → Branchesで変更・解除できます。この
リポジトリの中身からは変更できません。それが要点です。


リリースではない作業 — 記録の訂正、チェックの修正 — は、それ自身の短命な
ブランチと、同じプルリクエストを使います。`docs/design/tasks/`のうち
そのリリースの最も番号の大きいファイルがブランチ名を記録しているので、
`main`から始まったセッションでも辿れます。

### マージ済みのリリースブランチは残します

**`main`はsquashマージなので、リリースの個々のコミットはそのブランチに
しか存在しません。** `release/0.3.0`には`main`から到達できないコミットが
21個、`fix/0.2.3`には25個あります。失われるのは*コード*ではありません —
`main`はそのいずれよりも先行しています — 失われるのは各変更の理由です。

「`PROTOCOL_VERSION`はいつ2になったか」を訊くと:

```
main                  3183588  2026-09-02  0.3.0 — the first release that may add capability (#25)
origin/release/0.3.0  19058c3  2026-09-01  0.3.0: 024.R7's first half — the Agent reports what the gems define
```

`main`はリリースを答えます。ブランチは変更そのものを答え、なぜそうしたかを
述べます。

これは趣味の考古学ではありません。0.3.1のレビューは、公開済みのサイズの
数字が「フィールドが2回追加される前の値」であることを
`git log -S "938 KB" release/0.3.0` で特定しました。squash後の履歴では
答えられない問いです。このプロジェクトの記録は「なぜ」でできており、
squashのメッセージはその21件を1件に圧縮します。

残す費用はゼロです。リモートのrefは`git branch`には現れず、何も遅くせず、
`scripts/check_release_pointers.rb`はそれらがあっても通ります。古い`feat/`
・`fix/`のブランチは上の命名規則より前のものですが、同じ理由で残します。

**消すことは、片付けではなく書き留めるべき決定です。** マージ済みプル
リクエストの「Restore branch」はベストエフォートであって保証ではないため、
ローカルブランチのようには元に戻せません。*ローカル*のブランチやworktreeの
整理は普通の作業で、儀式は要りません。記録なのはリモートのrefの方です。

## commitの前に: `preflight`

```bash
ruby scripts/preflight.rb
```

commit前に真であるべきものを全て実行し、それぞれが何を実行したかを
出力するので、commit messageには記憶ではなく実行結果を引用できます。

```bash
ruby scripts/preflight.rb --list
```

で一覧が出ます。**この段落では意図的に列挙しません** — このゲートを
説明する散文は、チェックが1つ増えたリリースの時点でリポジトリ内の
どれもが古くなっていました(`024.195`)。リストは、走る場所に1つだけ
置き、記憶ではなく問い合わせます。

一覧からは見えない性質を1つだけ書いておきます。環境依存の3つのsuiteは
ローカルに`rails`/`sqlite3`/`vscode/node_modules`が無いと**丸ごと**skip
し、それでも`rspec`は0で終了します。そのため preflight はexample数では
なく各exampleの**status**を読みます — skipされたexampleもexampleなので、
数に基づく検査は「丸ごとskipされたファイル」と「通ったファイル」を
区別できません。
判定のあとに、preflightは`ci:`から始まる1行を出します。ブランチについて
CIが最後に何と言ったかです。**10個目のcheckではなく、結果を変えません** —
ネットワークが要るうえ、GitHubに届いても`gh`が無くてもタイムアウトしても
0で終了します。どれもツリーについて何も言っていないからです。これがある
のは、preflightが緑でもそれはCoreについての言明だからです — `vscode/`配下
は何も走らせず、部分的なツリーを拒む`spec/meta`のexampleも見えないので、
ローカルの信号が全て「問題なし」と言い続ける裏でCIが1週間赤いままだった
ことがあります(`024.284`)。

git hookとして1度だけ入れる場合:

```bash
ruby scripts/preflight.rb --install
```

`PREFLIGHT_SKIP=1 git commit …` で1回分スキップできます。

これがあるのは、「全部走らせたか?」を記憶で答えていたからです。ある
セッションでは2度その答えが間違っていました — 作業していたディレクトリ
だけスイートを走らせてgreenを見て commit し、後からのフル実行が
greenではなかった。検査は複数箇所に散っており、リストを繋いでいたのは人間
だけでした。

## PRを開く前に

1. `ruby scripts/preflight.rb` を実行する。
2. VSIX packagingに影響する変更の場合、`cd vscode && npm run package`
   を実行し成功することを確認する。
3. 何を・なぜ変更したか、実行したテストを記載する。

## バグ報告・機能要望

[SUPPORT.ja.md](SUPPORT.ja.md)を参照。セキュリティ関連の問題は、公開
issueではなく[SECURITY.ja.md](SECURITY.ja.md)を参照してください。

## Code of Conduct

このプロジェクトは[Code of Conduct](CODE_OF_CONDUCT.ja.md)に従います。
