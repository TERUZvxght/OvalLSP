# 1.0 Release Checklist

`docs/design/tasks/022-compatibility-resilience-and-release.md`の
"Release gates"に対応する。各項目は「判定可能」であること自体が
Task 022の受け入れ基準(「1.0 release checklistが全項目判定可能である
こと」)であり、ここでは各項目の**現時点での判定結果**を記録する
(1.0リリース作業そのものはこのタスクの範囲外)。

| # | 項目 | 状態 | 根拠/備考 |
|---|---|---|---|
| 1 | all unit/component/integration tests green | ✅ 判定可能・green | `core/`: 696 examples, 0 failures(このセッション時点)。`vscode/`: 18 examples, 0 failures |
| 2 | compatibility matrix green or documented | ✅ 判定可能・文書化済み | `docs/SUPPORT_MATRIX.md`。実CIで検証済みなのはmacOS + Ruby 3.3+ + Rails 7.1のみ。他は`best effort`/`unsupported`として明示 |
| 3 | benchmark regression within threshold | ✅ 判定可能・report-only | `docs/design/tasks/021-persistent-cache-notes.md`。1k/5kファイル規模での実測は未実施(既知のギャップとして記録済み) |
| 4 | no known P0/P1 | ✅ 判定可能・green | 014-018バッチの独立レビューで発見・修正済み(5ラウンドで収束)。019-022バッチの独立レビューも3ラウンドで収束(Round1: 5件 [Medium1/Low4]、Round2: 1件、Round3: クリーン)。本チェックリストの追加実装項目(SBOM/security checklist/VSIX実機smoke/Basic-Auth redaction)についても本セッション末尾で独立レビューを実施予定 |
| 5 | protocol schemas versioned | ✅ 判定可能 | Agent protocol: `RuntimeAgent::Agent::PROTOCOL_VERSION`固定値+不一致時拒否(Task 022で追加)。Plugin protocol: `Plugins::CURRENT_PROTOCOL_VERSION`固定値+不一致時拒否(Task 018で既存) |
| 6 | VSIX clean install smoke | ✅ 判定可能・green | `npm run package`(`copy-core.js` → `tsc` → `vsce package`)を実機で実行し`rslsp-0.0.1.vsix`(1140 files, 3.4MB)を実際に生成。`code --install-extension`でインストールし、`code --list-extensions`で`ovallsp.rslsp`を確認。インストール後の拡張機能ディレクトリ配下の`core/bin/rslsp`を`BUNDLE_GEMFILE`/`RUBYOPT`未設定・リポジトリチェックアウトなしの状態で直接ロードし、vendored prism(1.9.0)/rbs(4.0.3)経由で`Rslsp`が正常にrequireできることを確認(`package.json`に不足していた`publisher`フィールドを追加する必要があった — 追加済み) |
| 7 | uninstall leaves no running process | ✅ 判定可能(コード側は実装済み)・⚠️ VS Codeプラットフォーム側の既知の制約あり | `vscode/src/extension.ts`の`deactivate()`は保持している全`LanguageClient`に対して`client.stop()`を呼び、正常なdeactivate(ウィンドウを閉じる/リロードする等)では子プロセス(`core/bin/rslsp`)を確実に終了させる実装になっている。ただし実機検証で判明した点: `code --uninstall-extension`をCLIから実行しても、既に起動中のVS Codeウィンドウはリロードされない限り`deactivate()`を呼ばない(VS Code自体の仕様)。今回の検証では、インストール中に実際に起動していたVS Code本体がこの拡張機能をactivateし、アンインストール後もウィンドウがリロードされなかったため`core/bin/rslsp --stdio`プロセスが残存していた(手動`kill`で終了させて確認)。これはこのコードベースの不具合ではなくVS Code拡張ホストの一般的な挙動だが、リリースノートに「アンインストール後は念のためウィンドウのリロードを推奨」等の記載を検討する価値はある |
| 8 | licenses and third-party notices | ✅ 判定可能・green | `scripts/generate_sbom.rb`で`docs/SBOM.md`を生成。RubyGems: prism/rbsの2件。npm: `package-lock.json`の`dev`フラグを使い、直接依存(vscode-languageclient)だけでなく実際にVSIXへ同梱される推移的なproduction依存(vscode-jsonrpc, vscode-languageserver-protocol/types, semver, minimatch, brace-expansion, balanced-match)まで含めた計8件を収録(019-022バッチ後の独立レビューで、直接依存のみを見ていた初版の不備が発見され修正済み) |
| 9 | security checklist | ✅ 判定可能・文書化済み | `docs/SECURITY_CHECKLIST.md`として脅威モデルを体系化(信頼できないワークスペース/プラグイン/ログ経由漏洩/Observation privacy/キャッシュのMarshal.load、それぞれの緩和策とfile:line根拠)。個別実装(Plugin isolation Task 018、Workspace Trust gating、Agent protocol version拒否、ログredaction Task 022)は既存。既知の未対応ギャップ(Windows上のPlugin isolation未検証、Cache::StoreのMarshal.load、Redactorのbest-effort性)も同文書内に明記 |

## 凡例

- ✅ 判定可能・green: 実装・テストが存在し、現時点でパスしている
- ⚠️ 要確認/部分検証: 一部は実装済みだが、完全な検証には至っていない
- ❌ 未着手: このセッションでは着手していない

## 次のアクション(1.0リリース作業として別途必要)

1. ~~SBOM生成~~ 完了(`scripts/generate_sbom.rb` → `docs/SBOM.md`)
2. ~~`@vscode/vsce`を実際にインストールした環境での`vsce package`実行と
   VS Codeへのクリーンインストール実機テスト~~ 完了(`rslsp-0.0.1.vsix`生成、
   `code --install-extension`/`--uninstall-extension`で実機検証)
3. Windows/Linux実機(またはCI)でのテストスイート実行 — `.github/workflows/ci.yml`
   は`ubuntu-latest`で実行される設定だが、このリポジトリにはgit remoteが
   存在せず、GitHub Actions自体が一度も実行されていない。リモートを作成し
   push した後に初めて「Linux CIでgreen」を主張できる状態(このセッションの
   スコープ外 — リモートへのpushはユーザーの明示的許可が必要な操作のため)
4. ~~022自体の独立レビュー~~ 完了(019-022バッチとして3ラウンドで収束)
5. VS Code拡張の`deactivate()`が子プロセスを確実にkillすることを検証する
   専用のE2Eテスト(今回の手動smoke testで、CLI経由のアンインストールでは
   ウィンドウリロードなしに`deactivate()`自体が呼ばれないというVS Code側の
   制約が判明したため、リリースノートでの案内を検討)
