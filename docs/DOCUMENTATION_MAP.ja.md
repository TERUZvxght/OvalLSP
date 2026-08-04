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
| **ケイパビリティ**(ユーザーにできることが増えた・減った) | `docs/EXTENSION_CAPABILITIES.md` + `.ja.md`(行**と**そのE2E例の両方)、`README.md` + `README.ja.md` のマトリクス、`site/capabilities.html` + `site/ja/capabilities.html`、両CHANGELOG | `core/spec/e2e/capability_coverage_spec.rb`(行⇔E2E例)、`core/spec/meta/*_parity_spec.rb`(EN⇔JA) |
| **バージョン番号** | `core/lib/ovallsp/version.rb`、`core/Gemfile.lock`、`vscode/package.json`、`vscode/package-lock.json`(2箇所)、両CHANGELOG | `core/spec/meta/changelog_parity_spec.rb`、`vscode/src/test/unit/versionPairing.test.ts` |
| **ロードマップ項目**(提供開始・取り下げ・移動) | `docs/ROADMAP.md` + `.ja.md`、READMEのマトリクス、`site/roadmap.html` + `site/ja/roadmap.html`、`docs/design/tasks/024-deferred-review-findings.md` の対応する `024.R*` | `core/spec/meta/roadmap_parity_spec.rb`(README⇔ロードマップ) |
| **リリース途中で巻き戻した変更**(CLAUDE.md の2ラウンド規則を参照) | 根本原因と本来必要な方向を明記した `024.*` エントリ、既に箇条書きを書いていた場合は両CHANGELOG、その経験が示す `CLAUDE.md` の該当節 | — |
| **先送り項目**(`024.*`) | `docs/design/tasks/024-deferred-review-findings.md` の status 行。エントリの削除は、その番号を引用している箇所がツリーに1つも無くなってから——暦ではなく grep で判断する(同ファイルの凡例を参照) | — |
| **導入手順・前提条件・拡張機能ID** | `README.md` + `.ja.md`、`docs/PUBLISHING.md` + `.ja.md`、`site/getting-started.html` + `site/ja/getting-started.html` | — |
| **拡張機能が記録する・保持する・ディスクに書くもの** | `vscode/PRIVACY.md` + `.ja.md`(これが唯一の正)。`site/security.html` + `site/ja/security.html`。加えて、0.1.12 が「一覧またはキャッシュパスを書き写している」と特定した箇所すべて(この一覧は3度不足していた。信用せず、見つけたら追加すること)——`docs/design/docs/12-release-and-support.md`、`docs/design/tasks/019-runtime-observation.md`、`019-runtime-observation-notes.md`、`021-persistent-cache-notes.md`、`vscode/README.md` + `.ja.md` のキャッシュ段落、`docs/SECURITY_CHECKLIST.md` の観測節とキャッシュのデシリアライズ節、`core/lib/ovallsp/observation/store.rb` の `#invalidate_changed` の説明、`core/lib/ovallsp/observation/observed_signature.rb` の `code_fingerprint` の説明、そして**両CHANGELOG**(散文でディスクに関する記述を書き写しており、この行が名指ししていなかったために1ラウンド丸ごと PRIVACY と食い違ったまま残った)——は書き直さず PRIVACY を指すこと | `core/spec/meta/privacy_parity_spec.rb`(EN⇔JA: 節数・相互リンク・名指しした3つの主張・記録項目一覧の項目数) |
| **Runtime Agent・ワークスペースの信頼・拡張機能が実行するものに関すること** | `SECURITY.md` + `.ja.md`、`site/security.html` + `site/ja/security.html`、`docs/EXTENSION_CAPABILITIES.md` の「約束しないこと」節 | — |
| **既知の制限** | `docs/KNOWN_LIMITATIONS.md` + `.ja.md`、およびそれと反することを書いているサイトのページ | — |
| **進め方の取り決め**(構築・レビュー・リリースの方法) | `CLAUDE.md`、`AGENTS.md`、`CONTRIBUTING.md` + `.ja.md` | — |

## サイトもドキュメントです

`site/` は公開の顔であり、他と同じように古くなります。Markdownのドキュメント
から生成しているわけでは**ない**ため、自動で反映されるものは何もありません。
各ページを上の表の1行として扱ってください。

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

## サイトはまだ未取り込みで、順序に意味があります

`site/` は `main` ではなく `claude/github-pages-official-site-fef0f5` に
あります。独立チェックの結果は「忠実」——機能マトリクスはREADMEの行単位の
写し、内部リンクはすべて解決、トラッカー・外部アセット・個人情報なし——
ですが、取り込む前に直すべき齟齬が短いリストとして出ています。

**合意した順序は、0.2.0 を公開し、そのあとサイトを修正し、それから取り込む
です。** 齟齬の1つはトップページが「ワークスペース内の全クラスの補完」を
掲げている点で、これは 0.1.x にはなく 0.2.0 にはあります。0.1.x に合わせて
直してから 0.2.0 のあとに直し直すと、1週間の間に正反対のことを言う2つの
編集になります。残りは順序に依存しません。

- `site/capabilities.html` と `site/ja/capabilities.html` が「参照検索・
  リネーム・ワークスペースシンボル」を無条件に書いたままになっている。
  0.1.15 でこれを狭めた(マクロが宣言したメソッドはリネームせず拒否する)
  ため、READMEの `[^rename]` 脚注と `docs/EXTENSION_CAPABILITIES.md` の
  W2/W4 行と食い違う;
- plain-Ruby列がREADMEの `⚠️` を落としており、サイト自身の凡例では
  「未実装」の意味になる(READMEは「たぶん動くが未検証」の意味);
- ロードマップページが「最初の3つ」と書きながら2・5・6番目を挙げている;
- `Preview 0.1.10` が両トップページにハードコードされている;
- hoverが「メソッドの戻り値」を表示すると書かれているが、裏づけとなる
  ケイパビリティ行がない;
- 「patchはユーザーに見える変化がない」が6箇所にあり、
  `docs/PUBLISHING.ja.md` はその表現を明示的に否定している;
- 前提条件に VS Code 1.85 以上の記載がない;
- `404.html` だけが issue tracker を案内している;
- **`site/security.html` と `site/ja/security.html` は 0.1.12 が撤回した
  主張を2つとも載せたままになっている**: parseキャッシュに「ソースコードの
  内容は含まれない」(実際にはメソッド本文とデフォルト式をそのまま保持
  している)という記述と、観測が記録する内容の説明でファイルダイジェスト・
  行番号・実行識別子・実行終了時刻が抜けている点。これらは他の項目と違って
  体裁の問題ではなく、このリリース自身の訂正が公開ページに反映されていない
  という問題。取り込み前に他と一緒に直し、この状態のままサイトを公開しない
  こと。同じページのparseキャッシュの段落は `~/.cache/ovallsp/` も直書きして
  いるが、0.1.12 はこれを
  `$XDG_CACHE_HOME/ovallsp/`(未設定または空なら `~/.cache`)へ他の6文書で
  訂正済み。

また、そのブランチの `vscode/package.json` の `homepage` は既に Pages の
URL を指しています。Pages を有効化してサイトが `main` に載るまでは404に
なるため、このリンクを含むVSIXを出す前にブランチを取り込む必要があります。

**取り込みと同時に機械化してください。** ブランチには既に
`scripts/check_site_links.rb` が入っており、デプロイはそこで止まります。
これに2つの照合——サイトのマトリクス⇔READMEのマトリクス、バージョンバッジ
⇔`vscode/package.json`——を教えるだけで、下の陳腐化リストのおよそ2/3が
「誰かが憶えていること」ではなく「CIが落ちること」になります。これは
`core/spec/e2e/capability_coverage_spec.rb` が
`EXTENSION_CAPABILITIES.md` に対して既に行っているのと同じ手であり、
次節に挙げた穴を塞ぐものでもあります。

## 検査が欠けている箇所

サイトには対応関係の検査がありません。`site/capabilities.html` と
`docs/EXTENSION_CAPABILITIES.md` を照合するものはなく、`site/` と
`site/ja/` を照合するものもありません。これがこの対応表に残る最大の穴です。
正直に理由を書けば、サイトがHTMLで元がMarkdownであるため、正規表現ではなく
本物の抽出器が必要になるからです。それができるまで、上のサイトの行は
このファイルを読むことによって守られます。
