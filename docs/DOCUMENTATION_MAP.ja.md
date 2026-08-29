# ドキュメント対応表

[English version](DOCUMENTATION_MAP.md)

製品が変わったときに合わせて変えなければならない文書と、それぞれが何に
よって古くなるかの一覧です。**ユーザーが気づきうる変更を仕上げる前に必ず
読み**、リリース前にもう一度読んでください。

これが存在するのは、そうしなかったやり方が繰り返し失敗したからです。同じ
事実が8箇所に散らばっており、修正を書いている最中に8箇所すべてを憶えて
いる人はおらず、その漏れは後になってレビューで見つかるか、見つからないまま
になります。一覧を確認するのは安い作業です。どのファイルが食い違っているか
を後から突き止めるのは安くありません。

ここに書かれている規則は、0.1.11 で費やしたものを散文に適用したもの
です——**複数箇所に書き写された事実は、そのうちどこかで誤っている。**
重複を消せるなら消してください。消せない場合——1つのケイパビリティを
3種類の読者に向けて説明する必要がある、など——は機械的な照合を用意すべき
で、いくつかは既に存在します。

## 引き金の表

変更したものを左の列から探してください。その右にあるものはすべて、
「あとで」ではなく同じ変更の中で更新します。

| 変更したもの | 更新するもの | 照合するテスト |
|---|---|---|
| **ケイパビリティ**(ユーザーにできることが増えた・減った) | `docs/EXTENSION_CAPABILITIES.md` + `.ja.md`(行**と**そのE2E例の両方)、`README.md` + `README.ja.md` のマトリクス、`site/capabilities.html` + `site/ja/capabilities.html`、両CHANGELOG | `core/spec/e2e/capability_coverage_spec.rb`(行⇔E2E例)、`core/spec/meta/*_parity_spec.rb`(EN⇔JA)。READMEの日英対はこの中に**ありません**(理由は024.25) |
| **バージョン番号** | `core/lib/ovallsp/version.rb`、`core/Gemfile.lock`、`vscode/package.json`、`vscode/package-lock.json`(2箇所)、`site/index.html` + `site/ja/index.html` のバージョンバッジ、両CHANGELOG。公開した後は `docs/RELEASE_ARTIFACTS.md` も | `core/spec/meta/changelog_parity_spec.rb`、`vscode/src/test/unit/versionPairing.test.ts`、`scripts/check_site_links.rb`(バッジ⇔`package.json`。ci.yml の site-consistency ジョブが実行し、デプロイのゲートでもある — この行は 0.2.3 までバッジを載せておらず、それが 0.2.2 のバッジずれの起き方だった)、`core/spec/meta/site_version_guard_spec.rb`(その配線自体)、`core/spec/meta/release_artifacts_spec.rb`(`v*` タグがすべて記載されていること) |
| **ロードマップ項目**(提供開始・取り下げ・移動) | `docs/ROADMAP.md` + `.ja.md`、READMEのマトリクス、`site/roadmap.html` + `site/ja/roadmap.html`、`docs/design/tasks/024-deferred-review-findings.md` の対応する `024.R*` | `core/spec/meta/roadmap_parity_spec.rb`(README⇔ロードマップ)と `scripts/check_site_links.rb`(ロードマップ⇔`site/roadmap.html` + `site/ja/roadmap.html`、バージョンごとの項目数で照合。0.2.3 で追加 — サイトが2項目について丸1リリース遅れていたため) |
| **リリース途中で巻き戻した変更**(CLAUDE.md の同一箇所規則を参照) | 根本原因と本来必要な方向を明記した `024.*` エントリ、既に箇条書きを書いていた場合は両CHANGELOG、その経験が示す `CLAUDE.md` の該当節 | — |
| **前ラウンドと同じ箇所を指摘したレビューラウンド** | 機械的な対策 — 実装の共有、値を作る場所へのルールの移動、見えていなかった入力をガードに与えること。その1件に対する回帰テストは対策ではなく、3度目の手当ても対策ではない | — |
| **先送り項目**(`024.*`) | `docs/design/tasks/024-deferred-review-findings.md` の `yaml` メタデータブロック(`status`、解決したら `released-in`)。エントリの削除は、その番号を引用している箇所がツリーに1つも無くなってから——暦ではなく grep で判断する(同ファイルの凡例を参照) | — |
| **導入手順・前提条件・拡張機能ID** | `README.md` + `.ja.md`、`docs/PUBLISHING.md` + `.ja.md`、`site/getting-started.html` + `site/ja/getting-started.html` | — |
| **拡張機能が記録する・保持する・ディスクに書くもの** | `vscode/PRIVACY.md` + `.ja.md`(これが唯一の正)。`site/security.html` + `site/ja/security.html`。加えて、0.1.12 が「一覧またはキャッシュパスを書き写している」と特定した箇所すべて(この一覧は3度不足していた。信用せず、見つけたら追加すること)——`docs/design/docs/12-release-and-support.md`、`docs/design/tasks/019-runtime-observation.md`、`019-runtime-observation-notes.md`、`021-persistent-cache-notes.md`、`vscode/README.md` + `.ja.md` のキャッシュ段落、`docs/SECURITY_CHECKLIST.md` の観測節とキャッシュのデシリアライズ節、`core/lib/ovallsp/observation/store.rb` の `#invalidate_changed` の説明、`core/lib/ovallsp/observation/observed_signature.rb` の `code_fingerprint` の説明、そして**両CHANGELOG**(散文でディスクに関する記述を書き写しており、この行が名指ししていなかったために1ラウンド丸ごと PRIVACY と食い違ったまま残った)——は書き直さず PRIVACY を指すこと | `core/spec/meta/privacy_parity_spec.rb`(EN⇔JA: 節数・相互リンク・名指しした3つの主張・記録項目一覧の項目数) |
| **Runtime Agent・ワークスペースの信頼・拡張機能が実行するものに関すること** | `SECURITY.md` + `.ja.md`、`site/security.html` + `site/ja/security.html`、`docs/EXTENSION_CAPABILITIES.md` の「約束しないこと」節 | — |
| **既知の制限** | `docs/KNOWN_LIMITATIONS.md` + `.ja.md`、およびそれと反することを書いているサイトのページ | `core/spec/meta/deferred_findings_spec.rb`(`user-visible: yes` の未解決 `024.*` 欠陥は両言語から参照されていること。`no` の場合は理由を書くこと) |
| **どのRuby・Rails・プラットフォームを受け入れるか**(`vscode/src/platformCompatibility.ts`・`versionInfo.ts`・`rubyResolver.ts` の変更を含む) | `docs/SUPPORT_MATRIX.md` + `.ja.md`(用のあった行だけでなく影響する全行)、`docs/KNOWN_LIMITATIONS.md` + `.ja.md`、**`vscode/README.md` + `.ja.md` — Marketplaceの説明文。散文と環境表の両方でこれを述べている**、`site/getting-started.html` + `site/ja/`、`site/index.html` + `site/ja/index.html` のプラットフォーム callout(0.2.3 の統合ラウンドでここに追加 — 誠実化パスがバッジと同じ形でこの callout を見落としたため)、両CHANGELOG、下限が動いたなら `core/ovallsp.gemspec` の `required_ruby_version` | — |
| **リリース作業の所在**(ブランチの作成・改名・再採番、ブランチ間の作業移動) | `main` 上のそのリリースの `NNN-*.md` がブランチ名を明記する。`AGENTS.md` の現行ループへのポインタも — 0.2.3 はこの行が無かったために並行して二度準備された(CLAUDE.md「Where a release's work lives」、028) | — |
| **どのスレッドが何を所有するか、どのロックが何を守るか** — 背景スレッドの追加、mutex の追加や順序変更、状態オブジェクトを可変/不変に変えること | `docs/design/docs/02-architecture.md` のスレッド節（所有関係とロック順序を一箇所で述べている）と、それを自身の根拠として引用している `core/lib/ovallsp/document_store.rb` の注記 | — |
| **このツリーの外の挙動への依存** — クライアント、VS Code、LSP 仕様、Marketplace | `docs/CLIENT_BEHAVIOUR.md` + `.ja.md`。この種の事実を述べる唯一の場所で、他は全てここを指す | `core/spec/meta/client_behaviour_spec.rb`（grep できる行を `vscode/node_modules` に照合し、他が言い直していないことも確認） |
| **Ruby自身の挙動についての主張** — コメント・spec・記録のどこであれ、インタプリタが何をするかを述べているもの | それを支える貼り付け済みセッション。`CLAUDE.md` が要求しているもので、0.2.16 から**実際に再実行される** — 主張だけ書き換えて走らせ直さなければ落ちる。例外を出すセッションは `rescue` で書き、要点をスタックトレースではなく出力として記録する | `core/spec/meta/interpreter_sessions_spec.rb` と `scripts/check_interpreter_sessions.rb`(ツリー内の全セッションを Ruby の出力と突き合わせる — `024.220`) |
| **進め方の取り決め**(構築・レビュー・リリースの方法) | `CLAUDE.md`、`AGENTS.md`、`CONTRIBUTING.md` + `.ja.md` | — |

## サイトもドキュメントです

`site/` は公開の顔であり、他と同じように古くなります。Markdownのドキュメント
から生成しているわけでは**ない**ため、自動で反映されるものは何もありません。
各ページを上の表の1行として扱ってください。

**このツリーに入っています。** 0.2.0 で取り込みました。引き金の表のサイト
関連の行はそのまま辿れます(`git ls-files site` に17ファイル)。0.2.1 まで、
この段落は逆のことを書いていました。サイトがまだブランチにあった時期に書かれ、
取り込んだときに2つ下の節だけを書き直して、この段落を読み返さなかったためです。
必読のチェックリストが自己矛盾しているのは、単に古いよりも悪いことです。この
段落を信じた人は5行を飛ばし、もう存在しない一覧へ持ち越そうとします。

| ページ | 対応する文書 |
|---|---|
| `site/index.html`、`site/ja/index.html` | README の要旨とケイパビリティ概要 |
| `site/capabilities.html`、`site/ja/capabilities.html` | `docs/EXTENSION_CAPABILITIES.md` と README のマトリクス |
| `site/roadmap.html`、`site/ja/roadmap.html` | `docs/ROADMAP.md` |
| `site/getting-started.html`、`site/ja/getting-started.html` | README の導入節、`docs/PUBLISHING.md` |
| `site/security.html`、`site/ja/security.html` | `SECURITY.md` |

すべてのページは日英の両方に存在します。`site/ja/` の対応ページなしに
`site/` へページを追加すると、サイトが中途半端に翻訳された状態になり、
ページがないことより悪い結果になります。

## リリース前に

1. リリースに含まれるすべてについて引き金の表をたどる。
2. `cd core && bundle exec rspec spec/meta spec/e2e/capability_coverage_spec.rb` — 対応関係と網羅性の検査。
3. 両CHANGELOG: 先頭に箇条書き、その下に詳細、日英が同じことを言っている
   こと。
4. `gitleaks detect --config .gitleaks.toml` を全履歴に対して実行。
5. 直前のバージョン番号でリポジトリ全体をgrepし、履歴以外でそれを名乗って
   いるものが残っていれば古い。

## サイトと、まだ検査されていないもの

`site/` は 0.2.0 の時点で `main` に入りました。この節がかつて抱えていた
一覧——ブランチを独立に読んだ人が見つけた11個の齟齬——は、全項目を修正した
ので無くなりました。うちケイパビリティ表に関する2つは、記憶ではなく
*機械*が検査します。`scripts/check_site_links.rb` がサイトの表とREADMEの表を
3列すべて突き合わせ、indexページが掲げるバージョンを `vscode/package.json`
と突き合わせます。デプロイはこれを通らなければ実行されません。

英語は機能名で、日本語は行の位置で比較します。サイトの日本語はREADME.ja.md
とは別に訳されていて、同じ意味の言い回しが食い違っています(`Coreが起動し`
と `Core が起動し` など)。同一の文面を要求すれば、検査は厳しくなりますが
文章は悪くなります。2つの写しが本当に共有しているのは表の順序です。

0.2.3 でロードマップのページも加わりました。`ROADMAP.md`・`ROADMAP.ja.md`
に対し、バージョンごとの項目数で照合します。追加したのは、サイトが**2件**の
移動について丸1リリース遅れていたからです。0.2.1 は `activeParameter` を
0.4.0 へ送り、`documentHighlight` と `@ivar` 補完を 0.3.0 へ戻しました。
そのたびに Markdown と README は更新され、サイトはどちらのときも更新されて
いませんでした。この検査は、書いた瞬間に両方を見つけました。

数えるだけに留めているのは意図的です。サイトの文章はサイトのために書かれて
おり、日英どちらも Markdown と一文ずつ対応していません。数を数えれば「届か
なかった項目」は捕まり、これまでに観測された失敗はすべてその形でした。

これらの検査が覆っていないもの、したがって依然として人が読む必要があるもの:
`capabilities.html`・ロードマップ・indexページ以外のすべてのページと、
覆っているページの中でも行や項目でない部分すべてです。セキュリティページの
撤回済み主張2件、動作要件の一覧、パッチの定義、404ページのイシュートラッカー
への言及——いずれも人が読んで見つけたもので、機械が捕まえるものは1つも
ありませんでした。バージョンバッジはかつてこの一覧にあり、いまは機械が
検査します。それでも 0.2.2 は古いバッジのまま出荷されました。検査がサイトの
ファイルが変わったときにしか走らなかったからで、バージョンバンプで発火する
配線は 0.2.3 で入り、`site_version_guard_spec.rb` が pin しています。

## 検査が欠けている箇所

`site/capabilities.html` と `docs/EXTENSION_CAPABILITIES.md` を照合するものは
ありません。行数は README のマトリクスに固定されていますが、*説明文*は何にも
固定されていません。`site/` と `site/ja/` を文書として照合するものもなく、
あるのは上の検査の内側だけです。正直に理由を書けば、サイトがHTMLで元が
Markdownであるため、散文の照合には正規表現ではなく本物の抽出器が必要になる
からです。

それができるまで、上のサイトの行はこのファイルを読むことによって守られます。
そして、いま存在する検査はどれも、レビュワーが実際のずれを見つけた*後*に
追加されたものです。次の1つをそうなる前に足すべき理由がそれです。
