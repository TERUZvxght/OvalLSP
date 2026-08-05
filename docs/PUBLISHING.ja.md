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

## バージョン: 同梱するCoreは拡張機能のバージョンを名乗る

`core/lib/ovallsp/version.rb`のgemバージョンと`vscode/package.json`の
拡張機能バージョンは、同梱ビルドにおいては1つの番号です。同梱Coreは
この拡張機能自身のパッケージング手順で生成されVSIXに入り、
`OvalLSP: Show Version Information`が利用者に「Core x.y.z」として
表示します。どのリリースにも存在しないCoreバージョンが表示されると、
バグ報告をビルドに対応付けられなくなります。

**Rubyコードを一切変更していないリリースであっても、`package.json`と
同時に`Ovallsp::VERSION`を上げてください。** 忘れるのはまさにその
ケースなので、手順の記憶に頼らせません。両者が食い違う場合、
`copy-core.js`はplatform manifestの書き出しを拒否し、
`npm run package`が両方のバージョンを示して失敗します。覚えておくべき
ことはありません — 食い違ったビルドは生成できません。

### 各数字の意味

拡張機能と同梱Coreはバージョンを共有するため、これは両方の意味です。

| 位置 | 変わるとき | 例 |
|---|---|---|
| patch (`0.1.**7**`) | 新しく告知するものが無い。前のリリースがすでに主張していたことを、実際にできるようにするリリース | 不具合修正、性能改善、リファクタリング、文書修正。**ケイパビリティ行の追加や ✅ 化はあり得る** — 前のリリースが当然やっていると理解されていて実際にはやっていなかったことを指す行であれば。0.2.1 は `S4`・`G17`・`C14`・`W5` をこの形で追加した。やってはいけないのは、誰にも約束していないケイパビリティを告知すること |
| minor (`0.**1**.5`) | ケイパビリティが増える | マトリクスへの行の追加、`NOT YET`が✅になる、設定やコマンドの追加 |
| major (`**0**.1.5`) | 利用者が既に依存しているものが動かなくなる | 設定やコマンドの削除・改名、対応環境tierの引き下げ、古いプロトコル版を受け付けなくする、✅の行の削除 |

patch の行が言っていないことに注意してください。「利用者から見て何も
変わらない」とは言っていません。不具合修正は利用者から見た振る舞いを
変えます——それが修正の目的そのものです——ので、そう読む規則のもとでは
patch リリースは1つも存在しなくなります。0.1.7 がその実例です。すべての
Railsプロジェクトで2件の誤検知が出なくなり、これは全利用者に見えます。
それでも patch なのは、拡張機能がすでに主張していなかったケイパビリティを
1つも得ていないためです。

ここでいう「ケイパビリティ」は
[`docs/EXTENSION_CAPABILITIES.ja.md`](EXTENSION_CAPABILITIES.ja.md)
の各行であり、READMEのマトリクスが要約しているものと同じです。これは意図的で、
バージョン番号とケイパビリティ一覧が連動するため、「何が変わったか」を差分を
読まずにその2つから答えられます。

したがって、実装予定のケイパビリティは minor リリースを正確に名指しします
(`0.2.0` であって `0.2.x` ではありません)。`x` を使った範囲表記は不明な部分を
patch の位置に置くため「ケイパビリティが patch で届くかもしれない」と読めますが、
そういうことは決して起きません。複数のケイパビリティが1つの minor を共有し、
0.1.6 の5つのようにまとめて出ることはあります。

**何を報告してはいけないか**を記録する行は、ケイパビリティではなく退行防止の
検査であり、その追加は patch です。`docs/EXTENSION_CAPABILITIES.ja.md` には
両方の種類が載っています。G10〜G14 はいずれも「何も出さない」行で、「この誤検知は
二度と起きない」と述べる方法が、行を1つ与えてE2Eのexampleを付けることだから
です。規則を機械的に「行が増えたら minor」と読むと**あらゆる不具合修正が minor
になり**、上表の「ケイパビリティが増える」が意味するものと正反対になります。
判断基準は「利用者が以前できなかったことをできるようになったか」であって、
文書が1行増えたかどうかではありません。(0.1.7——内容が誤った報告を1つ取り除く
ことだけだったリリース——でこの問いに決着が必要になり、明文化しました。)

拡張機能とCoreのハンドシェイクで使うプロトコル版数は別の整数で、このバージョン
文字列から導かれるものではありません。受理範囲から古いプロトコル版を落とすことは
major、新しい版を足すことはmajorではありません。

### 0.x と、1.0.0 の条件

majorが0の間は上記がすべて適用されますが、破壊的変更をmajorではなくminorで
出してよい点だけが異なります(1.0以前の慣習どおり)。

1.0.0は、READMEのマトリクスにある2つの「まだ保証していない」但し書きが
消える時点のために予約します。

1. **Apple Siliconだけでなく、公開するすべての環境を保証する。** 現在公開して
   いるVSIXは`darwin-arm64`の1つだけで、いずれのケイパビリティもこの環境でしか
   検証していません。1.0.0には他ターゲット(`darwin-x64`、`win32-x64`、
   `linux-x64`)についても公開済みかつ検証済みの成果物が必要です
   (`docs/design/tasks/024-deferred-review-findings.md` の024.R4)。
2. **Railsだけでなく、素のRubyプロジェクトを保証する。** 現在はRails規約に
   明示的な境界がなく、Railsでないプロジェクトで何を期待してよいかを規定も検証も
   していません(024.R1)。

どちらも機能軸ではなく**環境軸**の話です。新機能はminorで届きますが1.0.0を
近づけません。環境の但し書きを消すことが近づけます。

1.0.0 の条件そのものではありませんが、1つだけ手順の変更が同時に始まります。
そのリリース以降、すべてのタグに GitHub Release を作ります。それ以前に
作らない理由は下の「GitHub Releases: 1.0.0 までは作らない」にあります。

拡張機能がビルドしていないCoreは、意図的に対象外です。

| Core | バージョン規則 | 判定基準 |
|---|---|---|
| 同梱(VSIX内) | 拡張機能のバージョンと一致必須 | プロトコル範囲 + manifest検査(build commit、payload hash、target、Rubyのengine/version) |
| monorepoチェックアウト(開発時) | 相違可 | プロトコル範囲のみ |
| 利用者指定の`ovallsp.rubyExecutablePath`/カスタムCoreパス | 相違可 | プロトコル範囲のみ |

下2行はADR-0006の保証#9です。利用者が選んだCoreは「この拡張機能と実際に
通信できるか」だけで判定し、そのCoreを説明するために書かれたわけでもない
manifestと違うというだけで不正扱いにはしません。互換性判定は常に
プロトコル範囲で行い、バージョン文字列の比較では行いません — 同じ
プロトコルを話す古いCoreは動作し続けます。

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
2. VSIXのSHA-256を計算し、[`docs/RELEASE_ARTIFACTS.md`](RELEASE_ARTIFACTS.md)
   へ記録する(英語のみ。ハッシュの表は運用データであり、翻訳した写しは
   桁が食い違いうる場所が増えるだけです)。貼り付ける行は`release.sh`が
   最後に出力します。この手順は最初のPreviewから0.2.0まで記録先が
   書かれておらず、そのため14個のタグについてハッシュは計算されては
   捨てられていました。
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

## GitHub Releases: 1.0.0 までは作らない

どのタグにも GitHub Release はありません。0.x の間は作りません。これは
見落としではなく決定です。0.2.0 の公開時に気づいたうえで、意図してこのまま
にしています。

リリースノートの実体は両方の CHANGELOG です。リポジトリにあり、VSIX の
*中に*同梱され、Marketplace は拡張機能のページで `CHANGELOG.md` を描画
します。GitHub Release は同じ文面の3つ目の写しになります。`docs/DOCUMENTATION_MAP.md`
が冒頭で掲げているこのプロジェクト自身の規則は「複数箇所に書かれた事実は、
そのうちのどこかで間違う」です。0.x の間は、3つ目の写しの代償を払うだけの
利用者がいません。

**1.0.0 からは、すべてのタグに GitHub Release を作ります。** 1.0.0 で変わる
のは文章の量ではなく、誰がどこから来るかです。1.0.0 はプラットフォームの
検証と素の Ruby プロジェクトの保証を行うリリースであり(024.R1・024.R4)、
Marketplace の外からタグに辿り着く人が出てきます。リンク、依存関係スキャナ、
特定バージョンについてのセキュリティ上の問い合わせ。そうした人は、何も
インストールせずに、そのバージョンの内容と成果物のハッシュを見たいはずです。
Release はそのためのもので、そのときには3つ目の写しに見合います。

始めるときは、本文で CHANGELOG を繰り返さずそちらを指し、SHA-256 は
[`docs/RELEASE_ARTIFACTS.md`](RELEASE_ARTIFACTS.md) から載せてください。

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
