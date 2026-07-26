# Support Matrix

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
| 3.3, 3.4 | supported | `core/ovallsp.gemspec`の`required_ruby_version >= 3.3`。このセッションでは3.4.7(主要)および3.4.5(このマシンのrbenv経由)で`core/`のテストスイート実行を確認 |
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
| Linux | unsupported (未検証) | `.github/workflows/ci.yml`は`ubuntu-latest`向けに定義されているが、**このリポジトリにはgit remoteが存在せず、GitHub Actions自体が一度も実行されていない**("CI green"という主張はできない — 以前の版はこの点を誤って"CIで実行"と記載していた)。VSIXのnative payloadはdarwin-arm64専用(上表)であり、Linux上ではvendor payloadなしでの動作(利用者自身のRuby環境にprism/rbsが必要)になる |
| Windows | unsupported | `rubyResolver.ts`にWindows RubyInstaller検出ロジックは実装済みだが、実機での動作確認は未実施 |

## VS Code

| バージョン | 区分 | 根拠 |
|---|---|---|
| 1.130.0 (このマシンの`@vscode/test-electron`が取得した安定版) | best effort | `vscode/package.json`の`engines.vscode: ^1.85.0`で宣言。実機でのインストール(`vsce package`→`code --install-extension`→`--uninstall-extension`)、および統合テスト(`npm run test:integration`/`test:integration:packaged`)をこのバージョンに対して実行・green。Marketplaceへの実際の公開・そこ経由でのインストールは未実施 |
| その他の安定版 | 未検証 | — |

## Remote/リモート環境

| 環境 | 区分 | 根拠 |
|---|---|---|
| WSL | unsupported | 未検証 |
| Dev Container | unsupported | 未検証 |
| Remote SSH | unsupported | 未検証 |

## 既知のギャップ

このセッション内で実施したのは主にmacOS(darwin-arm64)上でのRubyテスト
スイート(`core/`)、TypeScript単体・統合テスト(`vscode/`)、実際にpackage
した VSIX(darwin-arm64 + Ruby 3.4.7ビルド)上でのSemantic Hover smokeの
実行のみ。Windows/Linux実機、複数バージョンのVS Code、WSL/Dev Container/
Remote SSH経由での起動確認、GitHub Actions自体の実行はいずれも未実施。
git remoteを作成しpushした後に初めて「Linux CIでgreen」を主張できる状態。
