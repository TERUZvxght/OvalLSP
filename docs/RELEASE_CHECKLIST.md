# 1.0 Release Checklist

`docs/design/tasks/022-compatibility-resilience-and-release.md`の
"Release gates"に対応する。各項目は「判定可能」であること自体が
Task 022の受け入れ基準(「1.0 release checklistが全項目判定可能である
こと」)であり、ここでは各項目の**現時点での判定結果**を記録する
(1.0リリース作業そのものはこのタスクの範囲外)。

| # | 項目 | 状態 | 根拠/備考 |
|---|---|---|---|
| 1 | all unit/component/integration tests green | ✅ 判定可能・green | `core/`: 686 examples, 0 failures(このセッション時点)。`vscode/`: 18 examples, 0 failures |
| 2 | compatibility matrix green or documented | ✅ 判定可能・文書化済み | `docs/SUPPORT_MATRIX.md`。実CIで検証済みなのはmacOS + Ruby 3.3+ + Rails 7.1のみ。他は`best effort`/`unsupported`として明示 |
| 3 | benchmark regression within threshold | ✅ 判定可能・report-only | `docs/design/tasks/021-persistent-cache-notes.md`。1k/5kファイル規模での実測は未実施(既知のギャップとして記録済み) |
| 4 | no known P0/P1 | ⚠️ 要確認 | このセッション内での既知の重大バグは014-018バッチの独立レビューで発見・修正済み(5ラウンドで収束)。022自体の独立レビューは未実施(このタスク完了後に実施予定) |
| 5 | protocol schemas versioned | ✅ 判定可能 | Agent protocol: `RuntimeAgent::Agent::PROTOCOL_VERSION`固定値+不一致時拒否(Task 022で追加)。Plugin protocol: `Plugins::CURRENT_PROTOCOL_VERSION`固定値+不一致時拒否(Task 018で既存) |
| 6 | VSIX clean install smoke | ⚠️ 部分検証 | `vscode/scripts/copy-core.js`によるvendoring+`BUNDLE_GEMFILE`/`RUBYOPT`なしでの起動を直接検証済み(Task 020)。実際の`vsce package`によるVSIX生成→VS Codeへのインストール→実機動作は未実施(`@vscode/vsce`はこの環境にインストールされていない) |
| 7 | uninstall leaves no running process | ⚠️ 未検証 | `AgentProcessManager#stop`/Plugin loaderのプロセス隔離は個別にテスト済みだが、VS Code拡張機能の`deactivate()`→実際のアンインストールフローでの実機確認は未実施 |
| 8 | licenses and third-party notices | ❌ 未着手 | `core/rslsp.gemspec`は`license = "MIT"`を宣言しているが、SBOM(依存gem一覧: prism, rbs)とその各ライセンス表記の同梱は未実施 |
| 9 | security checklist | ⚠️ 部分実施 | Plugin isolation(Task 018、5ラウンドの独立レビューで収束)、Workspace Trust gating、Agent protocol version拒否、ログredaction(Task 022)は実装・テスト済み。正式な"security checklist"としての体系だった文書化(脅威モデル一覧等)は未作成 |

## 凡例

- ✅ 判定可能・green: 実装・テストが存在し、現時点でパスしている
- ⚠️ 要確認/部分検証: 一部は実装済みだが、完全な検証には至っていない
- ❌ 未着手: このセッションでは着手していない

## 次のアクション(1.0リリース作業として別途必要)

1. SBOM生成(`core/rslsp.gemspec`の依存関係から自動生成できるはず)
2. `@vscode/vsce`を実際にインストールした環境での`vsce package`実行と
   VS Codeへのクリーンインストール実機テスト
3. Windows/Linux実機(またはCI)でのテストスイート実行
4. 022自体の独立レビュー(CLAUDE.mdのレビューカデンスに従い、019-022
   バッチとして実施予定)
