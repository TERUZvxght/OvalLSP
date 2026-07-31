# OvalLSP (Preview)

[English README](README.md)

Ruby/Rails向けのセマンティック言語機能を、独立したCore Language Serverで
提供するVS Code拡張機能です。

> **Preview版です**: 現時点ではPre-Releaseの早期ビルドであり、
> **macOS(Apple Silicon限定、`darwin-arm64`)のみ**を対象としています。
> インストール前に下記[対応環境](#対応環境)を確認してください。

## OvalLSPができること

OvalLSPはRuby実装の言語サーバー(`ovallsp`)をVS Codeと並行して起動し、
以下を提供します。

- Hover、`textDocument/definition`、`documentSymbol`、`workspace/symbol`、
  find references、ガード付きrename — [Prism](https://github.com/ruby/prism)
  による実際の宣言抽出とワークスペース全体のインデックスに基づく
  (字句一致や正規表現の推測ではありません)。
- RBS/RBI signatureと連携したローカル型推論(`ovallsp/explainType`)。
- Rails向けのcompletion/signature help/definition
  (`*_path`/`*_url`ルートヘルパー、Active Recordのcolumn/association型、
  `enum`/`scope`/`delegate`等の一般的なRails DSL)。
- `.erb`テンプレートへのcontroller→viewのinstance variable伝播。
- バックグラウンドでRailsアプリ自身のroutes/modelを調査するRuntime Agent
  (**信頼されたworkspaceの場合のみ**起動 — [セキュリティモデル](#セキュリティモデル)参照)。
  調査できない場合は静的解析のみで継続します。
- Opt-inのruntime型観測(`OvalLSP: Run Tests with Type Observation`) —
  実際のテストで実行されたメソッド呼び出しの形状のみを記録します
  (引数・戻り値の**値**は一切記録しません、[PRIVACY.ja.md](PRIVACY.ja.md)参照)。
- 型エンジンを拡張するPlugin API(static/runtime) — OSプロセスレベルで
  隔離された環境で実行されます。

これはPreview版です。上記の機能一覧は「実際に実装・テスト済みのもの」
であり、将来のロードマップではありません。

## 対応環境

| | 状態 |
|---|---|
| macOS, Apple Silicon (`darwin-arm64`) | **対応** |
| macOS, Intel / Rosetta | このPreviewでは非対応 |
| Linux, Windows | このPreviewでは非対応 |
| Ruby 3.4.x | **対応**(3.4.5、3.4.7で動作確認済み) |
| Ruby 3.3.x, 3.5.x | 未検証(非対応として扱う) |
| Rails 8.1 | **対応**(実際の統合テストで確認済み) |
| Rails 7.x以下 | 未検証 |
| WSL / Dev Container / Remote SSH | このPreviewでは非対応 |

詳細は[docs/SUPPORT_MATRIX.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SUPPORT_MATRIX.ja.md)
と[既知の制限事項](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.ja.md)
を参照してください。

対応外のプラットフォーム/Rubyの組合せでは、OvalLSPは黙って劣化動作したり
推測したりせず、同梱されたnative依存の読み込みを拒否し、明確な診断を
表示します([バージョン・互換性エラー](#バージョン互換性エラー)参照)。

## 必要環境

- macOS(Apple Silicon)。
- Ruby 3.4.x — 以下のいずれかで検出可能であること: 明示的な
  `ovallsp.rubyExecutablePath`設定、[mise](https://mise.jdx.dev/)、
  [asdf](https://asdf-vm.com/)、[rbenv](https://github.com/rbenv/rbenv)、
  または[Homebrew](https://brew.sh/)(`/opt/homebrew`)。見つからない場合は
  [Ruby解決](#ruby解決)を参照。

`bundle install`もリポジトリのチェックアウトも、手動でのgemインストールも
不要です — Core Serverのruntime依存(Prism、RBS)は拡張機能自体に同梱
されています。

### 追加のセットアップなしでインストール直後から動作しますか?

**はい、ただし互換性のあるRubyが既にシステム上で見つかることが前提です。**
OvalLSPはRuby自体をインストールすることはできません — mise/asdf/rbenv/
Homebrew経由、または明示的な`ovallsp.rubyExecutablePath`で、Ruby 3.4.x
が既に何らかの形で存在している必要があります。その前提さえ満たせば、
実行に必要なそれ以外の全て(Core Server自体とそのruntime依存である
Prism・RBS)はVSIX自体に同梱されており、追加のダウンロード・
`bundle install`・リポジトリのチェックアウトは一切発生しません。

互換性のあるRubyが見つからない場合、または見つかったRubyがこのビルドの
native依存がコンパイルされた対象と一致しない場合、OvalLSPは黙って
劣化動作したり中途半端に起動したりせず、何が問題で何をすべきかを説明する
明確な診断を表示します([Ruby解決](#ruby解決)と
[バージョン・互換性エラー](#バージョン互換性エラー)を参照)。

## クイックスタート

1. 拡張機能をインストールする(Pre-Releaseチャンネル)。
2. RubyまたはRailsプロジェクトを開く。
3. 任意の`.rb`ファイルを開く — Core Serverが自動的に起動します。
4. プロンプトが出たらworkspaceを信頼する(Rails向け機能を有効にするため。
   Runtime Agentは信頼されていないworkspaceでは決して起動しません)。
5. `OvalLSP: Show Version Information`でExtensionとCore Serverの
   バージョンが互換であることを確認する。

## コマンド

| コマンド | 用途 |
|---|---|
| `OvalLSP: Show Version Information` | Extension/Coreのバージョン・protocol互換性・実際に使用中のRuby環境 |
| `OvalLSP: Restart Server` | 開いている全workspace folderのCore Serverを再起動 |
| `OvalLSP: Restart Rails Agent` | Runtime Agent(routes/model調査)のみ再起動 |
| `OvalLSP: Show Logs` | OvalLSPのoutput channelを開く |
| `OvalLSP: Show Environment Diagnostics` | どのRubyが、なぜ選ばれたか(mise/asdf/rbenv/Homebrew/PATH) |
| `OvalLSP: Re-index Workspace` | 強制的な全体再インデックス |
| `OvalLSP: Run Tests with Type Observation` | Opt-inのruntime型観測([PRIVACY.ja.md](PRIVACY.ja.md)参照) |
| `OvalLSP: Clear Observed Types` / `Show Type Evidence` | 観測データの管理 |

## 設定

| 設定キー | 用途 |
|---|---|
| `ovallsp.enabled` | 拡張機能全体の有効/無効 |
| `ovallsp.rubyExecutablePath` | 明示的なRuby実行系パス(自動検出をスキップ) |
| `ovallsp.server.path` | Core Serverのentrypointを明示指定(上級者向け、[カスタムCore Serverパス](#カスタムcore-serverパス)参照) |
| `ovallsp.observation.testCommand` | runtime型観測で使うコマンド(既定: `bundle exec rspec`) |

## Railsプロジェクトでの利用

workspace root直下に`bin/rails`があるRailsアプリの場合、workspaceが
信頼された時点でRuntime Agentがバックグラウンドで起動し、アプリ自身の
routes/modelを調査してcompletion/definition/型推論の精度を高めます。
調査できない場合(Railsでない、Agentがcrashした等)は、Agentを待たずに
静的解析のみで継続します。

## サーバー起動・更新モデル

Core Serverはこの拡張機能に**同梱**されています — 別途のダウンロードや
インストール手順、独立したバックグラウンド更新機構はありません。
Marketplace経由でこの拡張機能が更新されると、同梱されたCore Serverも
アトミックに更新されます。次にworkspaceがOvalLSPを起動する際は、必ず
その時点のExtensionバージョンに同梱されたCore Serverが使われます。
カスタムの`ovallsp.server.path`は自動更新されず、互換性チェックのみが
行われます。

## バージョン・互換性エラー

起動時、ExtensionとCore Serverはバージョン・protocol・build・Ruby/
platform情報を交換します。これらが一致しない場合(以前のExtension
バージョンの残留プロセス、正しくインストールされなかったpayload、
互換性のないカスタム`ovallsp.server.path`等)、OvalLSPは機能リクエストを
送る前に停止し、壊れた/劣化したセッションの代わりに診断を表示します。
`OvalLSP: Show Version Information`で検出内容と対処方法を確認できます。

## Ruby解決

OvalLSPは次の順序でRuby実行系を探します: 明示的な
`ovallsp.rubyExecutablePath`設定 → mise → asdf → rbenv →
Homebrew(Apple Silicon) → シェルの`PATH`。Dock/Spotlightから起動された
VS Codeは、通常のシェルが持つ`PATH`の追加分を持たないことがあります
— その場合は`ovallsp.rubyExecutablePath`を明示設定するか、
mise/asdf/rbenv/Homebrewのいずれか(`PATH`に依存せず検出可能)経由で
Rubyをインストールしてください。`OvalLSP: Show Environment Diagnostics`
で実際に何が試され、なぜそうなったかを確認できます。

## カスタムCore Serverパス

`ovallsp.server.path`を設定すると、同梱のCore Server以外(このリポジトリ
に対する開発時など)を指定できます。カスタムパスも同梱Coreと同様に
protocol互換性のチェックは行われますが、「標準の同梱Core」としては
扱われず(version/build/payloadの比較対象にならない)、自動更新も
されません。

## 他の拡張機能との既知の競合

OvalLSPは、他の全てのRuby関連拡張機能との組合せを検証しているわけでは
ありませんが、広く使われているものの一つ —
[Shopify製Ruby LSP](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp)
— を同一ウィンドウ内で同時に有効化した状態で実際に検証済みです。結果:
**クラッシュやインストール時の競合はありませんでした**が、結果の重複
という実際に確認された事象があります。両拡張機能は同じ`.rb`ドキュメント
に対してLSP provider(hover、completion、definition)を登録しており、
VS Codeはいずれか一つを選ぶのではなく、有効な全providerの結果を統合
します。具体的にこのテストでは: completionとgo-to-definitionのいずれも、
同じ位置で両方の拡張機能からの結果を合わせて返しました(go-to-definition
はOvalLSP単独では候補1件だったのに対し、両方有効化すると4件に増加) —
つまり、いずれの拡張機能も実際に誤動作しているわけではないものの、
重複または食い違うsuggestionや、複数の候補位置が同時に表示され、
混乱を招く可能性があります。

これはVS Codeのprovider modelのアーキテクチャ上の性質であり、Ruby LSP
固有の問題ではありません — インストールして有効化している他のRuby言語
サーバー拡張機能(Solargraph、Sorbet等)であれば同様に当てはまります。
Rubyプロジェクトに対してOvalLSP自身の結果のみを表示したい場合は、その
workspaceで他のRuby言語サーバー拡張機能を無効化してください。

## トラブルシューティング

1. `OvalLSP: Show Logs`で生のoutput channelを確認。
2. `OvalLSP: Show Environment Diagnostics`でRuby解決経緯を確認。
3. `OvalLSP: Show Version Information`でExtension/Core互換性を確認。
4. Rails向け機能が効かない場合は`OvalLSP: Restart Rails Agent`を試し、
   workspaceが信頼されているか確認。
5. ステータスバーで現在の状態(Indexing / Ready (static) /
   Ready (Rails) / Agent unavailable)を確認できる。
6. 永続キャッシュが壊れていると疑われる場合、`$XDG_CACHE_HOME/ovallsp/`
   (未設定または空なら `~/.cache/ovallsp/`)配下に
   workspace/Ruby/Prism/Gemfile.lock/RBSの組合せごとに分離されているため、
   該当ディレクトリを削除すれば強制的に再インデックスされる。

## プライバシー・テレメトリ

OvalLSPはテレメトリを収集せず、実行時にネットワーク経由で何も送信しません。
詳細は[PRIVACY.ja.md](PRIVACY.ja.md)を参照(opt-inのruntime型観測が何を
記録し、何を記録しないかを含む)。

## セキュリティ

脆弱性の報告方法とRails Agentのセキュリティモデルについては
[SECURITY.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SECURITY.ja.md)
を参照してください。

## サポート

[SUPPORT.ja.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.ja.md)を参照。

## ライセンス

MIT — [LICENSE](LICENSE)参照。サードパーティ依存のライセンスは
[THIRD_PARTY_NOTICES.ja.md](THIRD_PARTY_NOTICES.ja.md)を参照。

## 既知の制限事項

このPreviewの対応範囲については
[docs/KNOWN_LIMITATIONS.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/KNOWN_LIMITATIONS.ja.md)
を、静的解析自体の原理的な限界(既知のRails DSL以外の
`method_missing`/`define_method`、文字列引数による`class_eval`/
`instance_eval`、実行時にしか決まらないconstant解決は設計上scope外)に
ついては設計文書を参照してください。OvalLSPはRuby型チェッカーではなく、
LSP機能のための確信度付きヒューリスティックエンジンです。
