# Support Matrix

[English version](SUPPORT_MATRIX.md)

`docs/design/tasks/022-compatibility-resilience-and-release.md`の方針に
従い、**実際に実行・検証できている組合せのみ**を`supported`とする。設計文書の
暫定値をそのまま宣言しない。

各組合せは次の3区分のいずれかに分類する。

- **supported**: 実機/このリポジトリのテストスイートで実際に実行され、green。
- **best effort**: 手動での動作確認はあるが、継続的な自動検証はまだない。
- **unsupported**: 未検証、または既知の非互換がある。

## VSIXが対象とするnative dependencyの組合せ (ADR-0005)

`vscode/core/vendor/bundle`はビルド環境固有のnative extension
(prism/rbs、共にRuby ABI/OS/CPU依存)を含む。`core/bin/ovallsp`と
`vscode/src/platformCompatibility.ts`が起動前にこれを検証し、不一致時は
vendor payloadを読み込まず、対処可能な診断を出す(ADR-0005)。

| 組合せ | 区分 | 根拠 |
|---|---|---|
| darwin-arm64 + Ruby 3.4.x (このVSIXのビルド環境) | supported | `core/PLATFORM_MANIFEST.json`が記録する組合せそのもの。`scripts/vsix_semantic_smoke.rb`で実際のVSIX上でのSemantic Hoverまで検証済み |
| 上記以外のRuby engine/version/platform | unsupported (vendor payload不使用) | vendor payloadは読み込まれず、利用者自身のRuby環境にprism/rbsが別途インストールされていれば動作する可能性はあるが未検証。診断メッセージで案内 |

将来複数ターゲットのVSIXを配布する場合は、ADR-0005の"Rejected
alternatives"に記載の拡張方針(選択肢1: 複数ビルド、2: Ruby runtime同梱)を
検討する。

## Ruby (Core自体の`required_ruby_version`)

| バージョン | 区分 | 根拠 |
|---|---|---|
| 3.4(3.4.5、3.4.7で実行確認) | supported | 実際に`core/`のテストスイート(1,936 examples。`core/spec/meta/documented_counts_spec.rb` がこの数を実行中のスイートと突き合わせます。895 が六リリース、次に枝の途中で採った 1,776、次に2コミットを残して採った 1,833、と三度陳腐化したためです)をこのマシンで3.4.7(主要)および3.4.5(rbenv経由)で実行しgreenを確認 |
| 3.3 | unsupported(未検証) | Core自体のテストスイートは3.3でも走る(`.github/workflows/ci.yml` が `["3.3", "3.4"]` のマトリクスで実行)。この行はライブラリの話ではない。利用者が入れるVSIXの同梱native extensionは単一Rubyバージョン向けなので、ここでは使われない。0.2.1 から拡張機能は**拒否しない** — その Ruby が `prism` と `rbs` を持っているかを確認し、3.3 はどちらも同梱しているので起動する。つまり未検証の組み合わせで動く。この行はラウンド27まで「起動を断る」と書いていた。0.2.1 が取り除いた挙動で、新しい挙動を説明している 4.0 の行のすぐ隣に残っていた |
| 4.0(4.0.6で実行確認) | best effort | `core/`のスイートは4.0.6でgreenです。ただし実Railsの統合例は、このマシンの4.0.6にRailsとsqlite3が入っていないためpendingになります。**VSIXがこの上で何をするか**: 同梱のnative extensionは単一Rubyバージョン向けなのでここでは使われません。拡張機能は*利用者自身の*Rubyが `prism` と `rbs` を持っているかを確認し、持っていればそちらで動きます。持っていればOutputチャンネルへの1行、持っていなければ `gem install prism rbs` を示すエラーです。0.2.1 まではどちらでもエラーで、それは同梱物の事情を利用者の状況として伝えていました。4.0 に対する継続的な検証はありません — `.github/workflows/ci.yml` が回しているのは `["3.3", "3.4"]` です |
| 3.5 | unsupported(未検証) | 同上。リリース時点でstableな3.5系での実行実績がない |
| 3.2以下 | unsupported | `required_ruby_version`で明示的に拒否 |

## Rails (Runtime Agent)

| バージョン | 区分 | 根拠 |
|---|---|---|
| 8.1 | supported | `core/spec/integration/real_rails_spec.rb`(実Rails統合テスト)の実fixtureが`gem "rails", "~> 8.1"`(現在の解決先: 8.1.3)。`.github/workflows/ci.yml`も同バージョンを明示的にインストール |
| 7.0 / 7.1 | unsupported (未検証) | 実際にテストされているのはRails 8.1のみ。以前の版でこの表が7.1を"supported"としていたのは誤りで、実fixtureと一致していなかった(このセッションで修正) |
| 6.x以下 | unsupported | 未検証。`docs/design/tasks/008.5-*`以降の一部機能(belongs_to_required_by_default等)はRails 7.1以降のデフォルト挙動を前提にしている箇所がある |

Rails自体を使わない(純粋なRuby gem/ライブラリの)workspaceでは、Runtime
Agentは起動せず静的解析のみで動作する — これは"unsupported"ではなく、
そもそもAgentが対象外のケースとして扱う。

## OS

| OS | 区分 | 根拠 |
|---|---|---|
| macOS (arm64) | supported | この開発環境自体がmacOS arm64であり、全テストスイート・VSIX packaging・VSIX semantic smokeがここで実行・green |
| Linux | unsupported (CIはgreen、実機未検証) | `.github/workflows/ci.yml`が`ubuntu-latest`上で`core`のRSpec全件・`vscode`のTypeScript単体テストを実行し、実際にgreen(Marketplace公開作業の一環でGitHub Actionsを初めて実行・確認済み)。ただしこれは「Core Server/拡張機能のロジック自体がLinux上でも動く」ことの検証であり、Apple Silicon向けVSIXのnative payloadはdarwin-arm64専用(上表)のため、Linux上ではvendor payloadなしでの動作(利用者自身のRuby環境にprism/rbsが必要)になる。実機でのVSIXインストール確認はまだ行っていない |
| Windows | unsupported | `rubyResolver.ts`にWindows RubyInstaller検出ロジックは実装済みだが、実機での動作確認は未実施 |

## VS Code

| バージョン | 区分 | 根拠 |
|---|---|---|
| 1.130.0 (このマシンの`@vscode/test-electron`が取得した安定版) | best effort | `vscode/package.json`の`engines.vscode: ^1.85.0`で宣言。実機でのインストール(`vsce package`→`code --install-extension`→`--uninstall-extension`)、および統合テスト(`npm run test:integration`/`test:integration:packaged`)をこのバージョンに対して実行・green。v0.1.1としてMarketplace(Pre-Releaseチャンネル)へ実際に公開済み |
| その他の安定版 | 未検証 | — |

## Remote/リモート環境

| 環境 | 区分 | 根拠 |
|---|---|---|
| WSL | unsupported | 未検証 |
| Dev Container | unsupported | 未検証 |
| Remote SSH | unsupported | 未検証 |

## 既知のギャップ

実際に検証済みなのは、macOS(darwin-arm64)上でのRubyテストスイート
(`core/`)、TypeScript単体・統合テスト(`vscode/`)、実際にpackageした
VSIX(darwin-arm64 + Ruby 3.4.7ビルド)上でのSemantic Hover/documentSymbol/
definition smoke、GitHub Actions上(`ubuntu-latest`)でのCore/VS Code
テストスイートのCI実行、そしてMarketplaceへの実際の公開(v0.1.1、
Pre-Releaseチャンネル)。Windows/Linux実機でのVSIXインストール確認、
複数バージョンのVS Code、WSL/Dev Container/Remote SSH経由での起動確認は
いずれも未実施。
