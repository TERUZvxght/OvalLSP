# 12. Release Documentation (Task 022)

利用者向けドキュメント一式。`docs/design/tasks/022-compatibility-resilience-and-release.md`
の"Release documentation"に列挙された各項目に対応する。実装の背景・設計判断は
`docs/design/docs/01`〜`11`および各`docs/design/tasks/*.md`を参照。ここでは
「実際に使うときに必要な情報」だけを利用者目線でまとめる。

## Installation

VS Code Marketplace(公開後)またはVSIXファイルから導入する。

```bash
code --install-extension ovallsp-<version>.vsix
```

VSIXにはCore Server本体(`core/`)と、そのRuntime依存gem(prism/rbs)が同梱されている
(ADR-0004)。**リポジトリのチェックアウトは不要**で、VS Codeが起動している
ワークスペースのRubyインタプリタさえ見つかれば動作する。詳細は
`docs/design/adrs/0004-vsix-bundles-core-with-dual-run-mode.md`。

## Supported environments

`docs/SUPPORT_MATRIX.md`を参照。実際にCIで検証された組合せのみを"supported"と
宣言する方針(暫定値をそのまま宣言しない)。

## Rails Agent security model

- Runtime Agent(対象RailsアプリのBundler contextで動くコード実行プロセス)は、
  **workspaceがtrustedと明示された場合のみ**起動する(`docs/02-architecture.md`
  section 11、Workspace Trust節参照)。
- Agentは対象アプリ自身のプロセスであり、Core Server自身の依存とは完全に分離
  される(`core_version`/`protocolVersion`のhandshakeのみを共有)。
- Agent↔Core間のprotocol version不一致は**接続を拒否**し、static-onlyへ
  fallbackする(`AgentProcessManager#compatible_protocol_version?`)。
- Agent crash後は自動でexponential backoff付きの再起動を試みるが、
  上限(既定5回)を超えると自動再起動を諦め、static-onlyを維持する
  (`AgentSupervisor`)。手動での`OvalLSP: Restart Rails Agent`コマンドは
  この上限に関係なく常に試行できる。
- Plugin(Task 018)のstatic entrypointは`Process.fork`による本物のOSプロセス
  隔離下で実行され、Core自身のプロセス空間・fd・グローバル状態を一切
  侵害できない(`core/lib/ovallsp/plugins/loader.rb`のコメントに詳細)。
- Runtime plugin(untrusted workspaceでは一切ロードしない)は、trusted
  workspaceに限り、対象RailsアプリそのものLと同等のコード実行権限を持つ
  ことを明示する。

## Workspace Trust

VS CodeのWorkspace Trust APIをそのまま利用する。`initializationOptions.workspaceTrusted`
としてCore Serverへ伝達され、`false`/未設定/未送信の場合は**フェイルクローズ**で
Runtime Agentを起動しない(静的解析のみで継続)。Trustが後から付与された場合は
拡張機能がクライアントを再起動して`initialize`をやり直す。

## Configuration

`vscode/package.json`の`contributes.configuration`が正本。主な設定:

| 設定キー | 用途 |
|---|---|
| `ovallsp.enabled` | 拡張機能全体の有効/無効 |
| `ovallsp.rubyExecutablePath` | 明示的なRuby実行系パス(未設定時はmise→asdf→rbenv→chruby→PATH→Windows RubyInstallerの順で自動解決) |
| `ovallsp.ruby.command` | `rubyExecutablePath`の旧名(互換のため維持) |
| `ovallsp.server.path` | Core Serverのentrypointを明示指定(未設定時はVSIX同梱→monorepo相対の順) |
| `ovallsp.observation.testCommand` | Task 019のobservation実行時のテストコマンド(既定: `bundle exec rspec`) |

## Features and limitations

**できること**: 宣言抽出/hover/definition/completion/signature help/find
references/rename、Rails DSL(routes/ActiveRecord column・association/
enum・scope・delegate)の型推論、RBS/RBI連携、opt-inのruntime型観測、
永続キャッシュによるwarm start。

**できないこと(意図的にscope外)**:
- 完全なRuby型システム(dry-run型チェッカーではない、あくまでLSP機能の
  ための"確信度付きヒューリスティック")
- 動的に生成されるクラス/メソッド全般の追跡(下記"Dynamic Ruby limitations"参照)
- production環境へのAgent接続、リモートRailsアプリへの接続
- workspace外のGemの内部実装の型推論(RBS signatureがあれば利用可)

## Dynamic Ruby limitations

以下は静的解析の原理的な限界であり、意図的にscope外としている
(各tasksの設計文書に明記済み):

- `method_missing`/`define_method`による動的メソッド定義は、Task 017が
  対応する`enum`/`scope`/`delegate`など既知のRails DSL以外は認識しない。
- `class_eval`/`instance_eval`with文字列引数によるコード生成は追跡しない。
- 実行時にしか決まらないconstant解決(`const_get`with動的引数など)は
  対象外。
- Task 019のruntime observationは、実際にテストを実行した経路でしか
  型を観測できない(未実行のコードパスには evidence が付かない)。

## Troubleshooting

1. `OvalLSP: Show Logs`でOutput channelを確認する。
2. `OvalLSP: Show Environment Diagnostics`でRuby実行系の解決経緯
   (mise/asdf/rbenv/chruby/PATH のどれが、なぜ選ばれたか)を確認する。
3. Rails機能(routes補完等)が効かない場合は、`OvalLSP: Restart Rails Agent`
   を試す。それでも直らない場合はWorkspace Trustが付与されているか確認する。
4. ステータスバーの表示(`Indexing`/`Ready (static)`/`Ready (Rails)`/
   `Agent unavailable`)で現在の状態を確認できる。
5. キャッシュが壊れていると疑われる場合、キャッシュは
   `$XDG_CACHE_HOME/ovallsp/`(未設定または空なら`~/.cache/ovallsp/`)
   以下にworkspace/Ruby/Prism/Gemfile.lock/RBSの組合せごとに分離されて
   いるため、該当ディレクトリを削除すれば強制的にcold re-indexされる。

## Performance tuning

- `docs/design/tasks/021-persistent-cache-notes.md`に実測値と既知の
  ギャップを記録している。
- 大規模workspaceでは`.gitignore`相当の除外設定(Cold Indexの既定除外
  ディレクトリ: `.git`, `node_modules`, `vendor`, `tmp`, `log`,
  `coverage`, `storage`)が効いているか確認する。
- 永続キャッシュ(Task 021)はCore Serverの2回目以降の起動を高速化する。
  初回起動(cold)は必ずフルパースが走る。

## Plugin author guide

`docs/design/plugin-sdk.md`を参照。要点:

- static entrypointはCore process外の隔離されたforkで実行され、Ruby
  Data値(SymbolId/Types)のみをMarshalで受け渡しする。
- `Ovallsp::Plugins.register_static("plugin-name") { |context| ... }`で
  登録し、`context.register_declarations([...])`でmethodをCoreへ伝える。
- protocol_versionの不一致は明示的にログへ出て、そのpluginだけが
  スキップされる(他のplugin/Core自体には影響しない)。

## Privacy of observation

`docs/design/tasks/019-runtime-observation-notes.md`を参照。要点:

- 明示的なコマンド実行時のみ動作する(既定で無効)。
- 保存される内容の唯一の正は `vscode/PRIVACY.ja.md` とする。ここで一覧を
  書き写すと、そちらだけが更新されて食い違う(0.1.12 で実際にそうなった)。
  実際の引数値・戻り値・文字列内容・SQL・環境変数・ファイル内容を一切
  保存しないという保証は変わらない(`Observation::TypeNormalizer`は
  `#inspect`/`#to_s`を一切呼ばない)。ただしこの保証は OvalLSP が*抽出して
  保持するもの*についてであり、観測実行中に一時ファイルへリダイレクトされる
  テストコマンド自身の出力は対象外である点も `PRIVACY.ja.md` に明記した。
- Observationはあくまで低authorityな補助証拠であり、明示的なRBS
  signatureを上書きしない。

## Changelog / migration guide

このプロジェクトは現時点で1.0未リリース。`docs/RELEASE_CHECKLIST.md`の
全項目が判定可能になった時点で1.0候補とする。1.0以降のCHANGELOGは
`CHANGELOG.md`(リリース準備の一環として新設予定)で管理する。
