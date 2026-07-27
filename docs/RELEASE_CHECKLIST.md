# 1.0 Release Checklist

`docs/design/tasks/022-compatibility-resilience-and-release.md`の
"Release gates"に対応する。各項目は「判定可能」であること自体が
Task 022の受け入れ基準(「1.0 release checklistが全項目判定可能である
こと」)であり、ここでは各項目の**現時点での判定結果**を記録する
(1.0リリース作業そのものはこのタスクの範囲外)。テスト件数・artifact件数は
このドキュメント自体の直近の更新時点のもの — 固定値の手書きが古くなる
問題を繰り返さないよう、更新のたびに実際のテスト出力から転記すること。

| # | 項目 | 状態 | 根拠/備考 |
|---|---|---|---|
| 1 | all unit/component/integration tests green | ✅ 判定可能・green | `core/`: 890 examples, 0 failures(`bundle exec rspec --order random`)。`vscode/`: `test:unit` 27 examples / `test:integration` 5 examples(source Core) / `test:integration:packaged` 5 examples(packaged Core)、いずれも0 failures |
| 2 | compatibility matrix green or documented | ✅ 判定可能・文書化済み | `docs/SUPPORT_MATRIX.md`。実際に検証済みなのはmacOS(darwin-arm64) + Ruby 3.4(3.4.5/3.4.7) + Rails 8.1のみ — Ruby 3.3は`required_ruby_version >= 3.3`が拒否しないというだけで実際の動作確認実績ではないため、Task 023.1/023.4でsupported表から外した。VSIXのnative payloadはdarwin-arm64 + Ruby 3.4.x専用で、それ以外は起動前に検証・診断される(ADR-0005)。以前の版がRails 7.1を"supported"としていた誤りと、GitHub Actions未実行にもかかわらず"CIで実行"としていた誤りは修正済み |
| 3 | benchmark regression within threshold | ✅ 判定可能・report-only | `docs/design/tasks/021-persistent-cache-notes.md`。1k/5kファイル規模での実測は未実施(既知のギャップとして記録済み) |
| 4 | no known P0/P1 | ✅ 判定可能・green | Task 022.2(Bundler境界分離)は round 1-31 の独立レビューで収束、`docs/design/tasks/022.2-collector-tracepoint-state-machine.md`の最終release gateセクションに全不具合の重大度分類を記録。Packaging/Support Matrix整備(本ドキュメント更新の対象作業)自体の独立レビューは次アクション参照 |
| 5 | protocol schemas versioned | ✅ 判定可能 | Agent protocol: `RuntimeAgent::Agent::PROTOCOL_VERSION`固定値+不一致時拒否(Task 022)。Plugin protocol: `Plugins::CURRENT_PROTOCOL_VERSION`固定値+不一致時拒否(Task 018) |
| 6 | VSIX clean install smoke | ✅ 判定可能・green | `npm run package`(`copy-core.js` → `tsc` → `vsce package`)を実機で実行し`ovallsp-0.0.1.vsix`(1148 files, 3.46MB)を生成。vendoring失敗はhard failureとなるよう修正済み(`copy-core.js`、以前はcatchして続行していた)。`code --install-extension`/`--uninstall-extension`で実機検証済み。加えて`scripts/vsix_semantic_smoke.rb`が、隔離したBundler環境・隔離したworkspaceで、実際のSemantic Hover(`"String"`)応答とclean shutdown・子プロセス残留なしまで検証(単なるinitialize/shutdown確認から拡張) |
| 7 | uninstall leaves no running process | ✅ 判定可能(コード側は実装済み)・⚠️ VS Codeプラットフォーム側の既知の制約あり | `vscode/src/extension.ts`の`deactivate()`は保持している全`LanguageClient`に対して`client.stop()`を呼ぶ。`code --uninstall-extension`をCLIから実行しても、既に起動中のVS Codeウィンドウはリロードされない限り`deactivate()`を呼ばない、というVS Code自体の制約は既知(前回検証時の記録通り) |
| 8 | licenses and third-party notices | ✅ 判定可能・green | `scripts/generate_sbom.rb`が`docs/SBOM.md`を生成。RubyGems: `ovallsp.gemspec`の直接runtime依存(prism, rbs)だけでなく、その推移依存(logger, tsort)まで含めた計4件(以前の版は2件のみで、実際にvendoringされる4件と一致していなかった不備を修正)。npm: 8件(vscode-languageclientの推移的production依存)。`scripts/verify_sbom_against_vsix.rb`で、実際にpackageしたVSIX内のvendor/bundle・node_modules(ネストしたものを含む)の実体集合とdocs/SBOM.mdの集合が一致することを検証済み(green)。プロジェクト自体のLICENSE(MIT、`core/ovallsp.gemspec`の宣言と一致)を追加し、`vsce package`の`--skip-license`を削除 |
| 9 | security checklist | ✅ 判定可能・文書化済み | `docs/SECURITY_CHECKLIST.md`として脅威モデルを体系化。既知の未対応ギャップも同文書内に明記 |
| 10 | npm audit (runtime vs. development) | ✅ 判定可能・文書化済み | `npm audit --omit=dev`: 3件 high(brace-expansion経由、`vscode-languageclient`が依存する`minimatch`が古いバージョンの`brace-expansion`を要求)。`npm audit`(dev含む): 9件 high。修正には`vscode-languageclient`を9.x→10.xへ破壊的変更を伴う更新が必要なため、`npm audit fix --force`は実行していない(無条件のforce updateは禁止事項)。到達条件: `vscode-languageclient`内部が`minimatch`をfile-watcherパターン処理に使う経路のみで、攻撃者制御下の入力がその経路に到達するには悪意あるLSPサーバーへの差し替えが必要(Core自体を信頼する本プロジェクトの脅威モデル外)。影響: 攻撃可能な経路がない限りlow。回避策: 現状は許容し、`vscode-languageclient` 10.x系がリリースノートで破壊的変更点を明示した時点で計画的に追従する |

## 凡例

- ✅ 判定可能・green: 実装・テストが存在し、現時点でパスしている
- ⚠️ 要確認/部分検証: 一部は実装済みだが、完全な検証には至っていない
- ❌ 未着手: このセッションでは着手していない

## Public distributionの状態

このリポジトリは`private: true`(`vscode/package.json`)のまま、git remote
も持たない私的リリース段階にある。VS Code Marketplace等への公開・
第三者への配布は**未完了**。第三者配布を行う場合は追加で以下が必要:

- `--allow-missing-repository`を外せるよう、実際のrepository URLを
  `package.json`へ追加する(存在しないURLを先回りして追加してはならない)。
- Marketplace公開ポリシー(publisher検証等)への対応。
- 本チェックリストの#2(Support Matrix)を、実際にCIが実行される状態
  (git remote作成・push)にしてから再評価する。

## 次のアクション(1.0リリース作業として別途必要)

1. ~~SBOM生成~~ 完了、推移依存の完全化・VSIX実体との照合テストも完了
2. ~~VSIXクリーンインストールの実機テスト~~ 完了、Semantic Hoverまで検証する
   smokeへ拡張済み
3. Windows/Linux実機(またはCI)でのテストスイート実行 — `.github/workflows/ci.yml`
   は`ubuntu-latest`で実行される設定だが、このリポジトリにはgit remoteが
   存在せず、GitHub Actions自体が一度も実行されていない。リモートを作成し
   push した後に初めて「Linux CIでgreen」を主張できる状態(リモートへの
   pushはユーザーの明示的許可が必要な操作のため、このセッションのスコープ外)
4. ~~Bundler境界分離(Task 022.2)の独立レビュー~~ 完了(round 1-31で収束)
5. VS Code拡張の`deactivate()`が子プロセスを確実にkillすることを検証する
   専用のE2Eテスト(CLI経由のアンインストールでは、ウィンドウリロードなしに
   `deactivate()`自体が呼ばれないというVS Code側の制約が既知のため、
   リリースノートでの案内を検討)
6. 複数OS/CPU向けVSIX配布(ADR-0005で採用しなかった選択肢1/2)を将来
   検討する場合は、`PLATFORM_MANIFEST.json`記録・起動前検証の仕組みを
   そのまま拡張して使う
7. `vscode-languageclient`の破壊的メジャーアップデート(9.x→10.x、npm audit
   の残存3件を解消する)の計画的な追従
