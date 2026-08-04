# Apple Silicon Marketplace Preview — 既知の制限事項

[English version](KNOWN_LIMITATIONS.md)

本文書は、最初のMarketplace Pre-Releaseにおいて意図的にscope外として
いる事項の一覧です(バグとは区別する)。実際の検証結果に基づく
supported/unsupportedの一覧は
[docs/SUPPORT_MATRIX.ja.md](SUPPORT_MATRIX.ja.md)を参照してください。

## Platformのscope

- **macOS Apple Silicon(`darwin-arm64`)のみを対象としています。**
  VSIXは`vsce package --target darwin-arm64`でビルドされ、その
  platform向けにコンパイルされたnative extension(Prism、RBS)を
  同梱しています([ADR-0005](design/adrs/0005-platform-scoped-vsix-with-runtime-compatibility-check.md)参照)。
  それ以外のOS/CPUでは、同梱されたnative依存は単純にロードされず、
  劣化動作や推測での実行を試みる代わりに、OvalLSPはその理由を説明する
  診断を表示します。
- **Rosetta 2変換下も含め、Intel Macはこのpreviewでは非対応です。**
  x86_64のRuby(Apple Silicon Mac上にIntel Homebrew経由でnativeに
  インストールされたものも含む)は、同じ理由で同じplatform互換性
  チェックによって拒否されます。
- **同梱されたnative extensionには、packagingを行ったマシン自身の
  絶対Rubyインストールパスが埋め込まれており、Extension側の起動時
  対応で緩和しています。** packageされた`prism.bundle`/
  `rbs_extension.bundle`に対する`otool -L`は、*packagingを行った
  マシン自身の*rbenv `libruby`パスへの絶対`LC_LOAD_DYLIB`参照
  (例: `/Users/<packager>/.rbenv/versions/3.4.7/lib/libruby.3.4.dylib`)
  を示しており、再配置可能な`@rpath`参照ではありません — これは
  macOS上の標準的な`rbenv`/`ruby-build`の`--enable-shared`の挙動です。
  直接再現済み: あるRuby 3.4.xインストール下でビルドされた
  `prism.bundle`が、*別の*絶対パスにある異なるRuby 3.4.xインストール
  下でrequireされると`LoadError: linked to incompatible
  .../libruby.3.4.dylib`が発生する — これは実質的にほぼ全ての実際の
  利用者に影響しうる問題で(ユーザー名が違うだけで発生する)、
  ADR-0005自体のengine/version/platform互換性チェックでは捕捉できない
  種類の不一致です。**修正済み**: Core Server起動前に、Extensionは
  解決済みRubyの`RbConfig::CONFIG["bindir"]`/`["libdir"]`を問い合わせ
  (`platformCompatibility.ts`の`queryRubyConfigPaths`)、version
  manager shim(mise/asdf/rbenvはいずれもshim scriptに解決される)を
  完全に迂回して*実体の*`<bindir>/ruby`バイナリを直接起動します —
  その際、その実体バイナリ自身の`libdir`を`DYLD_LIBRARY_PATH`/
  `DYLD_FALLBACK_LIBRARY_PATH`に設定します。この問い合わせ自体は
  *workspace folder自身の*working directoryで実行され、省略しては
  いません — version manager shimは、現在のworking directory自身の
  `.ruby-version`/`.tool-versions`に基づいて実際に実行するRuby
  versionを解決するため、`cwd`を省略すると、workspaceの固定version
  ではなく*extension host自身の*ambientなworking directoryが解決する
  Rubyを暗黙に問い合わせ(そして起動)てしまいます。実体バイナリの
  直接起動と`cwd`を指定した問い合わせの両方が必要です: 起動される
  コマンドがshim scriptのままであれば、環境変数を設定するだけでは
  何も効果がありません — macOSは`/bin/bash`を経由して起動される
  あらゆるプロセスから`DYLD_*`環境変数を除去するためです(直接
  確認済み — rbenvのshimに限った話ではなく、system shellを経由する
  あらゆるものに対するmacOSの一般的な挙動です)。実際にvendored
  payloadをビルドしたものとは異なるRuby versionへ強制されたrbenv
  shimを通して、この失敗を実際に再現し、同一の開発マシン上に既に
  存在する2つのRuby 3.4.xインストールを使って修正がend-to-endで
  解決することを確認済み(`docs/design/tasks/023.8-*.md`参照)。この
  緩和策はdarwinでのみ適用されます — 問い合わせ自体が失敗した場合
  (異常に古いRuby、spawnエラー)は、この修正が存在する前と同様、
  元々解決されていたコマンドのままCore Serverを起動します。
- **Linux・Windowsはこのpreviewでは非対応です。** Ruby resolverには
  Windows RubyInstaller検出ロジックが実装されており、Core Server
  自体もplatformに依存しないRubyコードですが、このpreviewの
  packaging・testing・supportの範囲はまだいずれのOSもカバーして
  いません。
- **WSL・Dev Container・Remote SSHはこのpreviewでは非対応です** —
  単に未文書化なのではなく、未検証です。

## Rubyバージョンのscope

Ruby 3.4.xのみ対応、具体的にはこのプロジェクト自身のテスト実行で
実際に検証されたpatch version(3.4.5、3.4.7)のみです —
`core/ovallsp.gemspec`の`required_ruby_version >= 3.3`が技術的に
インストールを許すversion全体ではありません。このgemspecの制約は
「拒否しない」という意味であり、「検証済み」という意味ではありません
— Ruby 3.3.xおよび3.5.xは、このプロジェクトのテストスイートで実際に
検証されるまでunsupportedとして扱います。

## 配布・更新モデル

- Core ServerはExtensionの**内部**に同梱され、Marketplace自身の
  Extension更新機構を通じてExtensionと同時にアトミックに更新されます
  — [ADR-0006](design/adrs/0006-marketplace-bundled-core-update-atomicity.md)
  を参照。独立したCore Serverのダウンロードや、独立したバックグラウンド
  self-updaterはありません。将来このモデルが変わる場合(例えば、
  Extensionのリリースとは独立したCore更新をサポートする場合)は、
  それはこのpreviewが暗黙に行うことではなく、新たに明示的に設計される
  機能になります。
- カスタムの`ovallsp.server.path`はprotocol互換性のみチェックされ、
  自動更新されることは決してなく、同梱Core自身のversion/build/payload
  の期待値と比較されることもありません。

## 静的解析の限界(Apple Silicon固有ではないが、previewとして改めて記載)

OvalLSPはRuby型チェッカーではなく、LSP機能のための確信度付き
ヒューリスティックエンジンです。設計上、以下は追跡しません:

- 既に認識している特定のRails DSL(`enum`、`scope`、`delegate`)以外の
  `method_missing`/`define_method`ベースの動的メソッド定義。
- 文字列引数による`class_eval`/`instance_eval`のコード生成。
- 実行時にのみ解決されるconstant解決(動的引数を伴う`const_get`等)。
- opt-inのruntime型観測に関して、テスト実行で一度も実行されなかった
  コードパス(実際に実行された経路にのみevidenceが存在します)。

3点目の帰結は、0.1.6まではすべてのRailsアプリケーションで目に見えていましたが、
0.1.7で修正しました。ワークスペースが定義していないクラスの再オープンは、
そのクラスを定義するコードと構文上まったく同じであるため、
`test/test_helper.rb` の `class ActiveSupport::TestCase` はgemの親を持たない
素のクラスとして読まれ、`parallelize` と `fixtures` の呼び出しが未定義メソッド
として報告されていました。現在は静的な読みを信用せず、動作中のアプリケーションに
確認します(`docs/design/tasks/024-deferred-review-findings.md`、024.R5)。
したがって、動作中のアプリケーションが判断できない場合には引き続き当てはまります。
問い合わせ先が存在しない場合(信頼されていないワークスペース、Railsアプリでない
プロジェクト)、Agentのプロセスが読み込んでいないgemの場合(Agentは `development`
で起動するため `group :test` のgemはそもそも存在しません)、そして何もmixinせずに
再オープンされたgemクラスの場合(祖先がどちらの証拠も持ちません)です。
各ケースは024.R5に列挙しています。

もう3つ、知っておく価値のある形があります。いずれも本リリースより古く、
本リリースで直してもいません。

- **ブロックの中に書かれた宣言は、そのブロックを書いたクラスのものになります。**
  ブロックの本当のレシーバが何であってもです。`class Outer` の中の
  `Struct.new(:x) do attr_reader :label end` は `Outer` に対して `label` を
  補完に出し、定義ジャンプはブロックの中に着地します。`def setup;
  attr_accessor :never_real; end` は `never_real` を記録するので、その呼び出しは
  報告されません。しかもRubyはこれをどの経路でも定義できません。`attr_accessor`
  は `Module` のメソッドで、インスタンスメソッドの中の `self` はモジュールでは
  ないためです。字句的に帰属
  させるのは `def` が以前からしていることで、`attr_*` だけを賢くしようとした
  3度の試みは、いずれも誤報告を生みました(024.31)。
- **`def Foo.bar` はインスタンスメソッドとして記録されます。** そのため
  `Foo.bar` が未定義と報告され、`Foo.new.bar` は通ります — 両方が逆です。
  Ruby自身の標準ライブラリの報告のうち**56件**がこれです(024.32)。
- **`K.instance_eval { attr_accessor :x }` は報告されます。**
  `K.class_eval { attr_accessor :x }` は報告されず、どちらも同じメソッドを
  定義するにもかかわらずです。この規則自体は `object.instance_eval` に対して
  正しく、そのために書かれたものです(024.33)。


## 他の拡張機能との競合

検証済みの内容は
[vscode/README.ja.md](../vscode/README.ja.md#他の拡張機能との既知の競合)
を参照: OvalLSPをShopify製Ruby LSPと同時に有効化すると、LSP結果が
(クラッシュではなく)重複します — completion/definitionの結果を、VS
Codeのprovider modelがいずれか一つを選ぶのではなく両方まとめて表示する
ためです。これは特定の拡張機能固有の問題ではなく、有効化されている他の
Ruby言語サーバー拡張機能全般に当てはまると考えられます。

## Preview公開後の別作業として追跡している事項

このPreviewのscopeを超える拡張(追加のOS/CPUターゲット、Ruby/Railsの
バージョンマトリクス、self-hostedのApple Silicon releaseランナー、
Entra IDベースのMarketplace publishing、Extension JSのbundling、
stable releaseの受け入れ基準)は、このPreviewをblockしない後続作業
として記録されています — 全体のタスク分解は
[docs/design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md](design/tasks/023.1-marketplace-preview-investigation-and-distribution-model.md)
以降を参照。このリポジトリは現在外部からのissueを受け付けていない
ため([CONTRIBUTING.ja.md](../CONTRIBUTING.ja.md)参照)、これらの作業は
公開issue trackerではなく内部で追跡しています。
