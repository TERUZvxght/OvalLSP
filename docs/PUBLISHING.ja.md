# OvalLSPをVS Code Marketplaceへ公開する

[English version](PUBLISHING.md)

本文書はOvalLSPのpackaging・publishの方法を記述したものです。publishの
許可を与えるものではありません — 先にクリアすべきgateは
`docs/RELEASE_CHECKLIST.md`を、下記の明示的な承認事項も併せて参照して
ください。(最初のPreviewであるv0.1.1は既にこの手順に沿って公開済み
です。本文書は今後のリリースのための参照として残しています。)

## 最初のPreviewのスコープ

最初のリリースは**macOS Apple Silicon(`darwin-arm64`)のみ**を対象とし、
Marketplaceの**Pre-Release**チャンネルへ公開します。汎用でtarget指定の
ないVSIXとして公開することはありません — 単一targetビルドがこの段階で
正しい選択である理由はADR-0005・ADR-0006を、packaging scriptがこれを
どう強制しているかは
`docs/design/tasks/023.5-darwin-arm64-packaging-and-update-regression.md`
を参照。

## リリース成果物のビルド

必ず実機のApple Silicon Mac上で実行してください — x86_64マシンや
Linux CIランナーからのエミュレーション/クロスコンパイルは決して
行いません(他の環境でビルドされたnative gem extensionは、自身が
宣言するtargetと一致しないpayloadを生成してしまいます)。

```bash
cd vscode
npm run package
```

これは順に、`copy-core.js`(Core Serverのruntime gemをvendoringし、
`PLATFORM_MANIFEST.json`を書き出す)、`tsc`(拡張機能をコンパイル)、
`vsce package --target darwin-arm64 --allow-missing-repository`を実行
します。結果は`ovallsp-darwin-arm64-<version>.vsix`です。

`vscode/package.json`の`vscode:prepublish`スクリプトも、`npm run
package`を経由しない裸の呼び出しも含め、あらゆる`vsce package`/`vsce
publish`実行の直前に`copy-core`と`tsc`を自動実行します — これは
v0.1.0が、Core Serverを一切vendoringしないまま誤って公開されてしまった
(`npm run package`を経由せず、直接`vsce publish`が実行された)ことで
起動不能なVSIXが生成された経緯があるためです。それでも`npm run
package`はrelease candidateをビルドする推奨方法であり続けます —
packaging前に`tsc`自身のcompileステップをローカルで明示的に確認できる
ためです。

これをrelease candidateとして扱う前に:

1. `vsce ls --tree`を実行し、ファイル一覧全体を確認する — 絶対パス・
   ローカルのユーザー名・同梱すべきでないものが含まれていないか確認。
2. VSIXのSHA-256を計算し記録する。
3. packageされた成果物に対して
   `ruby scripts/vsix_semantic_smoke.rb <unpack済みVSIXへのパス>/extension`
   を実行する。
4. `docs/RELEASE_CHECKLIST.md`のgate項目が全て通ることを確認する。

## Publish

`vscode/scripts/release.sh`が一連の手順を自動化します: packageをビルド
し、`core/`が実際にvendoringされていること(v0.1.0で実際に壊れた点その
もの)を検証し、`vsce ls --tree`とpackage済みsemantic smokeを実行し、
SHA-256を計算した上で、最後に`yes`の入力を求めてから初めて`vsce publish
--target darwin-arm64 --pre-release`を実行します。PATは毎回入力する
代わりに`vscode/.vsce-pat.local`(gitignore対象、下記Credentials参照)
から読み込みます。

```bash
vscode/scripts/release.sh
```

最後の確認プロンプトは意図的なもので、フラグでスキップすることは
できません: 初回に限らず、publishのたびに「今この瞬間にpublishして
よい」という人間の意思表示が必要であり、それを省略するscriptはこの
ゲート自体の意味を無くしてしまいます。このscript経由であれ、`vsce
publish`を直接実行するのであれ、**以下の全てが真になるまで実行しては
いけません:**

- Marketplace publisher IDがプロジェクトオーナーによって確認済みで
  あること(リリース準備者が推測・仮定したものではない — publisher ID
  はMarketplace上の恒久的な識別子)。`package.json`のExtension`name`
  (これも恒久的)も同様。
- Marketplace publish用のcredentialが用意・設定済みであること(下記
  Credentials参照)。
- release candidateのversionがプロジェクトオーナーによって確認済みで
  あること。
- `docs/RELEASE_CHECKLIST.md`のgateが完全にgreenであること。
- プロジェクトオーナーが「publishしてよい」と明示的に述べていること。

初回publish、および将来の大きなscope拡大を伴う再publish(別platform
targetの追加等)は、同じ承認手順に従います — checklistがgreenであること
は「確認を求めるための前提条件」であり、「確認そのものの代替」では
ありません。

## Credentials

- Personal Access Token(PAT)やその他のcredentialは、いかなる形でも
  (ファイル・commit message・CIログ)このリポジトリへcommitしません。
- `vsce publish`を直接使う場合、単発のpublish実行のための一時的な環境
  変数(`VSCE_PAT`)経由、またはrelease workflowが消費するGitHub Actions
  secretとしてのみ提供し、tracked fileへ書き込むことはありません。
- `vscode/scripts/release.sh`はPATを`vscode/.vsce-pat.local`(token本体
  のみを1行、`.gitignore`自身のコメント参照)から読み込みます。これは
  繰り返しpublishする際のローカルな利便性のためのものであり、上記の
  ルールを緩めるものではありません: このファイルはあなたのマシンから
  一切外に出ず、scriptはその内容を出力・ログに残しません。適切な
  ファイル権限を設定し、管理下にない共有・バックアップ先へ同期しない
  など、他のローカルcredentialと同様の保護はあなた自身の責任です。
- `vsce login`はローカルマシンのcredential storeにcredentialを保存する
  ため、共有マシンで使う前にそのスコープを理解しておく必要があります。
- Marketplace publisherの登録自体(publisherアカウントの作成・検証)は
  Microsoft/Azure DevOps/Marketplace UI上の手動手順であり、この
  リポジトリのtooling範囲外です。publisherアカウントの所有者が直接
  行うものであり、本文書はアカウント作成を自動化しようとはしません。

### 将来の方向性: Microsoft Entra ID

VS Code MarketplaceのPATベースのpublishingモデルは、Microsoft Entra
IDベースの認証へ段階的に移行される予定です。このプロジェクトの最初の
Previewでは、現実的な選択としてPATベースのpublishing(またはMarketplace
のWeb UI経由の手動アップロード)を使用しており、この廃止が発効する前に
Entra IDベースのpublishingへ移行すべきです。この移行は、Preview公開後の
別作業(non-blocking)として追跡されています。

## 本文書がカバーしないこと

- リポジトリをpublicにすること — これは別途、明示的にgateされた判断
  です(それに先立つGitHub公開準備については
  `docs/design/tasks/023.7-*.md`を参照)。このリポジトリは既にpublicに
  なっていますが、これはどのリポジトリであっても意図的に判断すべき
  ことであり、publish自体が暗黙に行うべきことではありません。
- 上記手順のCI/CD自動化 — 何が既に存在し、何が現時点で手動のみかは
  `docs/design/tasks/023.7-*.md`を参照。
- 追加のplatform target(Linux、Windows、Intel Mac)へのpublishing —
  このPreviewのscope外です。ADR-0005のRejected alternativesと、
  Preview公開後のissue一覧を参照。
