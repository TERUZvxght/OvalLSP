# Support Matrix

`docs/design/tasks/022-compatibility-resilience-and-release.md`の方針に
従い、**実際にCIで検証できている組合せのみ**を`supported`とする。設計文書の
暫定値をそのまま宣言しない。

各組合せは次の3区分のいずれかに分類する。

- **supported**: このリポジトリのCIで自動テストが実行され、green。
- **best effort**: 手動での動作確認はあるが、CIでの継続的検証はまだない。
- **unsupported**: 未検証、または既知の非互換がある。

## Ruby

| バージョン | 区分 | 根拠 |
|---|---|---|
| 3.3+ | supported | `core/ovallsp.gemspec`の`required_ruby_version >= 3.3`、CIで実行 |
| 3.2以下 | unsupported | `required_ruby_version`で明示的に拒否 |

## Rails

| バージョン | 区分 | 根拠 |
|---|---|---|
| 7.1 | supported | `core/spec/integration/real_rails_spec.rb`(実Rails統合テスト)で検証 |
| 7.0 | best effort | 明示的なCI検証なし。Runtime Agent protocolはRails固有APIに強く依存しないため動作する可能性が高いが未検証 |
| 6.x以下 | unsupported | 未検証。`docs/design/tasks/008.5-*`以降の一部機能(belongs_to_required_by_default等)はRails 7.1のデフォルト挙動を前提にしている箇所がある |

Rails自体を使わない(純粋なRuby gem/ライブラリの)workspaceでは、Runtime
Agentは起動せず静的解析のみで動作する — これは"unsupported"ではなく、
そもそもAgentが対象外のケースとして扱う。

## OS

| OS | 区分 | 根拠 |
|---|---|---|
| macOS | supported | この開発環境自体がmacOSであり、全テストスイートがここで実行・green |
| Linux | best effort | CIでの明示的なLinux実行環境の検証はこのセッションでは未実施。`Process.fork`/POSIX前提のコード(Plugin isolation、Agent管理)はLinuxでも同様に動作するはずだが未検証 |
| Windows | unsupported | `rubyResolver.ts`にWindows RubyInstaller検出ロジックは実装済みだが、実機での動作確認は未実施。`Process.fork`に依存するPlugin isolation(Task 018)はWindowsのRubyでは動作しない可能性が高い(要調査) |

## VS Code

| バージョン | 区分 | 根拠 |
|---|---|---|
| stable current | best effort | `vscode/package.json`の`engines.vscode: ^1.85.0`で宣言。実機でのインストール(`vsce package`→`code --install-extension`→`--uninstall-extension`)は検証済み(このマシンにインストール済みのVS Codeビルドに対してのみ)。Marketplaceへの実際の公開・そこ経由でのインストールは未実施 |
| stable previous | 未検証 | — |

## Remote/リモート環境

| 環境 | 区分 | 根拠 |
|---|---|---|
| WSL | unsupported | 未検証。VS CodeのRemote-WSL拡張がremote extension host側でCoreを起動する設計だが実機検証なし |
| Dev Container | unsupported | 未検証 |
| Remote SSH | unsupported | 未検証 |

## 既知のギャップ

このセッション内で実施したのは主にmacOS上でのRubyテストスイート
(`core/`)とTypeScript単体テスト(`vscode/`)の実行のみ。Windows/Linux上での
実機検証、複数バージョンのVS Codeでの動作確認、WSL/Dev Container/Remote SSH
経由での起動確認はいずれも未実施であり、1.0リリース前にCIパイプラインで
明示的に検証するか、この表を更新して"unsupported"のまま出荷するかを
判断する必要がある。
