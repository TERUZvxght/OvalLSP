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

ワークスペースが*コア*クラスを再オープンする場合、同じ問題が1段外側で
起こります(024.13)。`lib/core_ext/array.rb` はRailsでは定型的な書き方
ですが、`Array` を再オープンすると祖先鎖(`Array`・`Object`・`Kernel`・
`BasicObject`)がすべて既知の状態になるため、未定義メソッド検査は
レシーバを「閉じている」と判断します。gemは `Array` に追加し続けるのに、
です。Runtime Agentが接続されていれば実際の祖先を報告して解決しますが、
問い合わせ先がない場合(信頼されていないワークスペース、Railsアプリでない
プロジェクト)は判断できません。

ただし実際に届く範囲は語感より狭く、しかも**利用者が最初に試すであろう
呼び出しは、再現しない側**なので、正確に書いておきます。エンジンがコンテナ
として推論するレシーバ(`[1, 2, 3]` や、それを代入したローカル変数)は
未定義メソッド検査の対象外です。したがって `[1, 2, 3].second` も
`a = [1, 2, 3]; a.second` も報告されません。報告されるのは、レシーバが
素のクラスそのものである呼び出し — 再オープンの内側にあるレシーバなしの
呼び出しです。

```ruby
class Array
  def to_sentence_ish
    second        # 報告される: "Array has no method named `second`"
  end
end
```

**ブロックの内側は型が付きません。** 例外は、エンジンがコンテナとして
モデル化しているレシーバ — `Array`、Active Recordの `Relation`、
`CollectionProxy`、およびそこから `map`・`select`・`find`・`each`・
`reduce` が渡すもの — だけです。`Hash` は*含まれません*。したがって
`hash.each do |k, v|` の内側には何も型が付かず、自分で定義したクラスを
レシーバにしたブロックの内側も同様です。ホバーは推測せずに何も答えず、
診断はすべて判断を控えます。**0.2.0でここが変わったので、気づくかも
しれません。** 0.1.13までは、この位置は*外側の呼び出し*の型を答えて
いました。つまりホバーは何かを言っていた — 多くの場合まちがったことを、
です。今は何も言いません。これは意図的な取引です。代案は仮定ではなく
実測して退けており、どちらもより悪いものでした。*外側の呼び出し*の型を
答えると `opts.on("-x") do` の中の
文字列リテラルを `OptionParser` として報告してしまい、ブロックのボディを
読みに行くと、潜在的なオフセット誤解決が表面化してRuby標準ライブラリ全体で
未定義メソッドの報告が230件増えました。3つのうちどの検査も動かないのは
Unknownだけです。前者2つが依存しているオフセットの規則は独立して修正中で
(024.20、未解決)、それができればボディを読めるようになります。

## 現在まちがっている報告

このエンジンの基準は一貫して「誤った報告は見逃しより悪い」です。以下は
現時点で事実でないことを言っている箇所です。1つを除いて診断として、残る1つは
色としてです。いずれも記録済みで、0.2.0では修正しておらず、しかもごく普通の
コードで目に見えます。自分で見つけてもらうのではなく、ここに挙げておきます。

このリストがかつて抱えていた最大のものは無くなりました。クラスボディの
マクロ(`private`・`attr_reader` など)が未定義メソッドとして報告される件と、
それらのDSLが定義する属性リーダーの件です。このプロジェクト自身のソースで
**62件中49件**、Rubyの標準ライブラリ全体では12,134件を占めていましたが、
本リリースに持ち込まず0.1.14として修正・公開しました(024.23)。

- **ワークスペースが宣言していない `*_path`/`*_url` の呼び出しは、ルートが
  1つも読み込まれていないときに「存在しないルート」として報告されます**
  (024.24)。信頼されていないワークスペース、およびRailsでないプロジェクトが
  これに当たります。空のルート表が「知らない」ではなく「そんなルートはない」
  と答えるためです。Ruby 3.4.7 の標準ライブラリでの計測は**8件、すべて誤り**
  でした(bundler自身の `settings.rb` の `system_path`・`explicit_path` は
  ごく普通のメソッドです)。この数は0.1.14が `attr_reader` の宣言を索引に
  教えるまでは48件で、prism 1.9.0の12件は0件になりました。ただし原因には
  手が入っておらず、ワークスペースが宣言していない名前は引き続き報告され
  ます。Railsプロジェクトで Workspace Trust を拒否した場合にルートヘルパーが
  下線になるのは、これが理由です。
- **修飾されたconstantは、前半だけが色付けされます**(024.21)。
  `Ovallsp::Server` では `Ovallsp` にセマンティックな色が付き、`Server`
  はエディタの文法由来の色のままなので、1つの名前の前半と後半で色が
  揃いません。同じモジュールが、宣言側ではnamespace、参照側ではclassとして
  色付けされる不一致もあります。

さらに6つ、本リリースより古く、本リリースが手を付けていない形があります。

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
- **ワークスペースが `Object` に足した `def self.` には届きません。** そのため
  すべてのクラスが本当に持っているメソッドについて `Widget.foo` が報告されます。
  0.1.14 がこれを報告しなかったのは、`class Object; def blank?; end` という
  はるかに一般的な形を動くコードに対して誤報告していたのと同じ、種類の取り違えの
  副作用でした。0.1.15 はその偶然を手放して修正を取っています。本リリースが
  0.1.14 より*悪くなる*唯一の形です(024.26)。
- **ワークスペースが読んでいないモジュールを include したクラスでは、クラス
  レベルのマクロが報告されます。** `include SomeGem::Model` に続く
  `validate :ensure_ok` は、Concern が `validate` を入れるにもかかわらず報告
  されます。0.1.14 で入り、本リリースでは直していません(024.35)。
- **`K.instance_eval { attr_accessor :x }` は報告されます。**
  `K.class_eval { attr_accessor :x }` は報告されず、どちらも同じメソッドを
  定義するにもかかわらずです。この規則自体は `object.instance_eval` に対して
  正しく、そのために書かれたものです(024.33)。
- **`class << self` の中の `def` の中に書かれた `attr_accessor` は、クラス
  レベルのメソッドを宣言するものとして記録されます。** Rubyが定義するのは
  インスタンスメソッドです。このマクロが走るのはそのメソッドが*呼ばれた*
  ときで、そのとき `self` はクラスだからです。結果として、その属性を
  インスタンスメソッドから読むと未定義として報告されます。実在するコードに
  この形があります。ActiveRecord の `has_and_belongs_to_many` ビルダー、
  `csv/parser.rb`、`cgi/core.rb`、Devise(024.34)。

## 0.2.0で追加した検査が意図的に見ないもの

0.2.0が追加する診断はどちらも「誤った報告は見逃しより悪い」を基準に
しているため、意図的に狭くしてあります。その代償は次のとおりです。

- **引数の型**は、入力がすべて*宣言されている*場合にだけ検査します。
  期待される型がRBS/RBIの宣言由来であること(Rubyのソースは引数の型を
  宣言しません)、オーバーロードがちょうど1つであること、宣言側も引数側
  も素のクラスであること。判断できない呼び出しは推測せずに通すので、
  union・interface・ジェネリクス・複数オーバーロードの中にある本物の
  不一致は報告しません。

  「黙る」ではなく「誤る」形が1つ残ります(024.19)。ワークスペースが
  宣言していないconstant(`::Vendor::Gadgets::Widget` など)は、索引の
  「最後の1区切りで一致させる」フォールバックに到達し、その名前を共有する
  無関係なクラスが返ります。引数検査は*そのクラス*のシグネチャに対して
  判断するため、レシーバではないクラスを基準にした不一致を報告しえます。
  これを見分けるための併発シグナルはありません。constant検査は、同じ
  フォールバックが解決した名前をスキップするからです。つまり誤判定が
  起きているまさにそのときに限って、constant解決不能の報告は*出ません*。
  手がかりになるのは、レシーバの名前空間と無関係なところから来た型名が
  メッセージに現れることです。
- **何も代入されない `@ivar` の読み出し**はERBビューだけが対象で、
  代入の集合を完全に列挙できる場合に限ります。これは高い水準であり、
  次のどれか1つでも該当すればそのビューでは検査自体が黙ります。直近の
  親クラスが読めていない、`instance_variable_set` を使っている、
  モジュールをmix-inしている、モデル化していないコールバック形式がある、
  **継承鎖のいずれかのクラスのボディが `private`/`protected`/`public`・
  `before_action`・`skip_before_action` 以外を呼んでいる**(鎖全体が対象なので、
  `ApplicationController` のボディがその下の全ビューについてこれを決めます。
  `after_action`・`around_action`・`prepend_before_action` も黙らせる側です)(gemのマクロ —`load_and_authorize_resource`・
  `expose`・Devise・ActiveAdmin— はすべてここに該当します。何を仕込むかは
  024.R7で索引が帰属を持つまで見えないためです)、**ビューが何かを
  renderしている**、**継承鎖のいずれかのクラスが複数ファイルに分かれて
  宣言されている**(祖先1つにつき1ファイルしか解決しないため、クラスを
  再オープンする2つ目のファイルは読まれません)。兄弟アクションでの代入も、意図的に黙らせます。

  **`rails new` が生成するアプリケーションでは、この検査は一度も発火
  しません**(024.22)。Railties 7.2・8.0・8.1はいずれも、ボディで
  `allow_browser versions: :modern` を呼ぶ `ApplicationController` を
  生成します。この呼び出しはモデル化済みの5つに含まれず、規則は継承鎖
  全体に及ぶため、既定のRailsアプリケーションでは全ビューが黙ります。
  G16の能力行が通っているのは、手書きの空の `ApplicationController` に
  対してであり、それは `rails new` が生成する形ではありません。

  結果として報告されるのは、素のRubyで書かれたコントローラと、partialを
  renderしないビューです。「黙る」ではなく「誤る」形が2つ残ります。どちらも024.18に記録済みです。
  *別の*コントローラのアクションが描画するビュー(`render "users/show"`)
  では自分のコントローラのivarしか見ていません。また継承が3段以上あり、
  最上位のワークスペースクラスがまだ読めていない場合、防護は1段目にしか
  効きません。
- **開いていないファイルの診断**は1回のパスで2,000ファイルまでで止まります。
  それを超えるワークスペースでは残りに診断が出ません。パスはソート順に歩くので、
  出ないのは保存のたびに変わるのではなく常に同じ末尾です。上限に達したことは
  Coreがログに出します。ここでの「ファイル」は診断を発行したファイルのことで、
  開いているファイル・存在しないファイル・例外になったファイルは数に入りません。また、
  実物のRailsアプリに対するE2E検証がありません。そのために書いた例が45秒経っても
  何も出しませんでした。原因は特定済みで、修正は独立したタスクに切って
  あります(024.14)。READMEの表でこの行が✅ではなく⚠️なのはそのためです。

## マクロが宣言したメソッドに対するエディタ機能の振る舞い

`attr_accessor :name`、`delegate :title, to: :author`、`enum`、`scope` は、
識別子トークンではなく*シンボル引数*の位置でメソッドを宣言します。エディタが
指し示せる名前がソースに無いため、2つの機能にそれが現れます。

- **リネームは編集せず拒否します**(024.28)。この宣言を通してリネームすると、
  呼び出し箇所をすべて書き換えたうえで宣言だけを書き換えられず、動かない
  ファイルが残ります。0.1.14 は実際にそうなっていて、0.1.15 で拒否に
  変えました。VS Code は自前の「名前を変更できません」を出します。理由が
  届くのはCoreのログだけです。
- **アウトラインは宣言された名前の数だけ項目を並べます**(024.27)。
  `attr_accessor :a, :b, :c` は1行で6つのメソッドを宣言するので、
  アウトラインには同じ範囲を持つ子が6つ並びます。名前はどれも正しく、
  どれも本当にメソッドですが、同じ範囲が6つ並ぶ様子はバグに見えます。

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
