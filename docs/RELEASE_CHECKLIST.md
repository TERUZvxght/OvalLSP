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
| 1 | all unit/component/integration tests green | ✅ 判定可能・green | `core/`: 2,469 examples, 0 failures(`bundle exec rspec --order random`)。`vscode/`: `test:unit` / `test:integration`(source Core)/ `test:integration:packaged`(packaged Core)、いずれも0 failures。**core側の数は `core/spec/meta/documented_counts_spec.rb` が実行中のスイートと突き合わせます** — 890/895/1,776/1,833 と三度陳腐化し、「毎回測り直すこと」と書いた行自体がまた陳腐化したため、覚えておくのをやめて検査させることにした。vscode側の数はここから消した。増える数字を2箇所に書く理由がない |
| 2 | compatibility matrix green or documented | ✅ 判定可能・文書化済み | `docs/SUPPORT_MATRIX.md`。実際に検証済みなのはmacOS(darwin-arm64) + Ruby 3.4(3.4.5/3.4.7/3.4.10) + Rails 8.1のみ — Ruby 3.3は`required_ruby_version >= 3.3`が拒否しないというだけで実際の動作確認実績ではないため、Task 023.1/023.4でsupported表から外した。VSIXのnative payloadはdarwin-arm64 + Ruby 3.4.x専用。それ以外では、0.2.1 以降は起動前に `prism`/`rbs` の有無を確認し、あればそちらで動かして Output に記録する。無ければ診断を出す(ADR-0005 と 0.2.1 の変更)。以前の版がRails 7.1を"supported"としていた誤りと、GitHub Actions未実行にもかかわらず"CIで実行"としていた誤りは修正済み |
| 3 | benchmark regression within threshold | ✅ 判定可能・report-only | `docs/design/tasks/021-persistent-cache-notes.md`。1k/5kファイル規模での実測は未実施(既知のギャップとして記録済み) |
| 4 | no known P0/P1 | ✅ 判定可能・green | Task 022.2(Bundler境界分離)は round 1-31 の独立レビューで収束、`docs/design/tasks/022.2-collector-tracepoint-state-machine.md`の最終release gateセクションに全不具合の重大度分類を記録。Packaging/Support Matrix整備(本ドキュメント更新の対象作業)自体の独立レビューは次アクション参照 |
| 5 | protocol schemas versioned | ✅ 判定可能 | Agent protocol: `RuntimeAgent::Agent::PROTOCOL_VERSION`固定値+不一致時拒否(Task 022)。Plugin protocol: `Plugins::CURRENT_PROTOCOL_VERSION`固定値+不一致時拒否(Task 018) |
| 6 | VSIX clean install smoke | ✅ 判定可能・green | `npm run package`(`copy-core.js` → `tsc` → `vsce package`)を実機で実行し`ovallsp-darwin-arm64-0.2.3.vsix`(1168 files, 3.76MB)を生成(0.2.3 の公開前ゲートで測り直した値。以前この欄は `ovallsp-0.0.1.vsix`(1148 files, 3.46MB)のままだった)。vendoring失敗はhard failureとなるよう修正済み(`copy-core.js`、以前はcatchして続行していた)。`code --install-extension`/`--uninstall-extension`で実機検証済み。加えて`scripts/vsix_semantic_smoke.rb`が、隔離したBundler環境・隔離したworkspaceで、実際のSemantic Hover(`"String"`)応答とclean shutdown・子プロセス残留なしまで検証(単なるinitialize/shutdown確認から拡張) |
| 7 | uninstall leaves no running process | ✅ 判定可能(コード側は実装済み)・⚠️ VS Codeプラットフォーム側の既知の制約あり | `vscode/src/extension.ts`の`deactivate()`は保持している全`LanguageClient`に対して`client.stop()`を呼ぶ。`code --uninstall-extension`をCLIから実行しても、既に起動中のVS Codeウィンドウはリロードされない限り`deactivate()`を呼ばない、というVS Code自体の制約は既知(前回検証時の記録通り) |
| 8 | licenses and third-party notices | ✅ 判定可能・green | `scripts/generate_sbom.rb`が`docs/SBOM.md`を生成。RubyGems: `ovallsp.gemspec`の直接runtime依存(prism, rbs)だけでなく、その推移依存(logger, tsort)まで含めた計4件(以前の版は2件のみで、実際にvendoringされる4件と一致していなかった不備を修正)。npm: 8件(vscode-languageclientの推移的production依存)。`scripts/verify_sbom_against_vsix.rb`で、実際にpackageしたVSIX内のvendor/bundle・node_modules(ネストしたものを含む)の実体集合とdocs/SBOM.mdの集合が一致することを検証済み(green)。プロジェクト自体のLICENSE(MIT、`core/ovallsp.gemspec`の宣言と一致)を追加し、`vsce package`の`--skip-license`を削除 |
| 9 | security checklist | ✅ 判定可能・文書化済み | `docs/SECURITY_CHECKLIST.md`として脅威モデルを体系化。既知の未対応ギャップも同文書内に明記 |
| 10 | npm audit (runtime vs. development) | ✅ 判定可能・文書化済み | `npm audit --omit=dev`: 1件 high(brace-expansion経由、`vscode-languageclient`が依存する`minimatch`が古いバージョンの`brace-expansion`を要求)。`npm audit`(dev含む): 7件(high 5・moderate 2)。**この2つの数はアドバイザリDB側の更新でも動きます** — 0.2.3 の公開前ゲートで測り直した時点では 3件/9件 から 1件/7件 へ減っており、ツリー側は何も変えていません。数を読む前に測り直すこと。修正には`vscode-languageclient`を9.x→10.xへ破壊的変更を伴う更新が必要なため、`npm audit fix --force`は実行していない(無条件のforce updateは禁止事項)。到達条件: `vscode-languageclient`内部が`minimatch`をfile-watcherパターン処理に使う経路のみで、攻撃者制御下の入力がその経路に到達するには悪意あるLSPサーバーへの差し替えが必要(Core自体を信頼する本プロジェクトの脅威モデル外)。影響: 攻撃可能な経路がない限りlow。回避策: 現状は許容し、`vscode-languageclient` 10.x系がリリースノートで破壊的変更点を明示した時点で計画的に追従する |

## 凡例

- ✅ 判定可能・green: 実装・テストが存在し、現時点でパスしている
- ⚠️ 要確認/部分検証: 一部は実装済みだが、完全な検証には至っていない
- ❌ 未着手: このセッションでは着手していない

## リリースを切る前に: そのリリースを target にしているエントリの再現を走らせる

```bash
ruby scripts/deferred_findings.rb --targeting <version>
```

`024` の open エントリのうち、そのバージョンを `target:` にしているもの
を Area 付きで列挙します。**列挙されたエントリの再現手順を、切ろうと
している tree に対して実際に走らせ、結果をエントリへ書き戻すこと。**

`046` の C3b。`024.41` の再現は15リリースにわたって引用され続け、記録
されていた6ケースのうち2つが逆方向に動いていました — 1つはもうその欠陥
ではなくなり、1つはエントリが主張していたより**広い**欠陥になっていた。
誰も走らせ直さなかったのは、どのエントリを走らせ直すべきかを言うものが
無かったからです。

## Apple Silicon Marketplace Preview Release Gate (Task 023)

上記の1.0リリースチェックリストとは別に、Task 023(Apple Silicon向け
Marketplace Preview公開)固有の22項目のゲートを設ける。各項目の「根拠」欄
には、**それを実際に実行するもの**を書く — CIのジョブ名、spec、あるいは
`release.sh` のステップ。手動確認のみの項目は状態欄にその旨を記す。

> **0.2.14 で書き換えた。** それまで7項目が
> `make-final-review-bundle.sh` を根拠に挙げていたが、このスクリプトは
> CI からも `release.sh` からも suite からも呼ばれておらず、最後に手で
> 走らせて以降なにも実行していなかった。ゲートが「書いてあるが誰も
> 走らせない」状態だったということで、これは 046 が扱っている失敗その
> ものである。スクリプトは削除し、各項目を実際の実行者に付け替えた。
> 唯一どこにも無かった SBOM 再生成の決定性は
> `core/spec/meta/sbom_spec.rb` に、clean tree 検査は `release.sh` に
> 移した。

| # | 項目 | 状態 | 根拠 |
|---|---|---|---|
| 1 | git tracked tree clean | ✅ `vscode/scripts/release.sh` が `git diff --quiet` / `git diff --cached --quiet` で publish を拒否する。`copy-core.js` が `buildCommit` を成果物へ焼き込むため、dirty tree からの publish は「実在しない内容を指す commit SHA」を名乗る VSIX になる。`core/spec/meta/release_script_guard_spec.rb` がこのブロックの存在を pin する(`if false` へ書き換えると落ちることを実測確認済み) |
| 2 | Core full RSpec failure/pending 0 | ✅ CI の `core` ジョブ(`bundle exec rspec --order random`)。0 failures(件数は `documented_counts_spec.rb` が上の行と突き合わせる) |
| 3 | Real Rails integration failure/pending 0 | ✅ CI の `core` ジョブ + 同ジョブの "Fail if the real-Rails or capability suites were skipped instead of run" ステップ。gem が無いと両 suite は丸ごと skip して `rspec` は 0 で終わるため、**走ったこと自体**を別に検査している |
| 4 | VS Code unit/integration failure 0 | ✅ `test:unit`・`test:integration` |
| 5 | packaged integration failure 0 | ✅ `test:integration:packaged`(既存)+本タスクで追加した`vsix_semantic_smoke.rb`のdocumentSymbol/definition検証 |
| 6 | Apple Silicon semantic smoke PASS | ✅ `scripts/vsix_semantic_smoke.rb`(hover/documentSymbol/definition/stderr allowlist、Task 023.4で拡張) |
| 7 | Extension/Core version handshake PASS | ✅ `vscode/src/versionInfo.ts#compareVersionInfo`のテスト(Task 023.2、8種の不一致モード全て) |
| 8 | update E1/C1→E2/C2 PASS | ✅ `versionInfo.test.ts`の"never mixes E1/C1 and E2/C2"(Task 023.5) |
| 9 | delayed-start race test PASS | ✅ `clientLifecycle.test.ts`(Task 023.3、独立レビューでの追加P0修正込み) |
| 10 | payload hash verification PASS | ✅ `computeBundledPayloadSha256`のテスト+`versionInfo.test.ts`の"detects a payload hash mismatch" |
| 11 | SBOM name/version match PASS | ✅ `scripts/verify_sbom_against_vsix.rb`(既存、Task 022由来、本タスクでは変更なし) |
| 12 | LICENSE/Third Party Notice match PASS | ✅ `vscode/LICENSE`(既存)+本タスクで追加した`vscode/THIRD_PARTY_NOTICES.md`が`docs/SBOM.md`と一致することを目視確認済み |
| 13 | Privacy doc matches actual code | ✅ `vscode/PRIVACY.md`の記述を`grep`でtelemetry/network呼び出しの不在を確認してから作成(Task 023.6) |
| 14 | secret scan PASS | ✅ CI の `secret-scan` ジョブ(`gitleaks-action`、`fetch-depth: 0` で全履歴、`.gitleaks.toml` でテストフィクスチャのみ許可リスト化)+ 同ジョブの `check_home_paths.rb --messages`(commit message は tree scan からは見えない) |
| 14.1 | 出荷する artifact 自身へのパス検査 | ✅ 0.2.5 で追加 | `release.sh` が unpack 後の実 artifact に `$HOME` 検査を掛け、native 拡張以外に一致があれば publish を拒否する。**それまで CI は ubuntu ビルドしか見ておらず**（`$HOME` が `/home/runner`、vendoring される native 拡張も別物）、実際に配布する darwin-arm64 成果物は一度も検査されていなかった。`grep` はシェルが解決する名前ではなく `/usr/bin/grep` を絶対パスで呼ぶ — ugrep ラッパーはバイナリを無言で飛ばす。`core/spec/meta/release_script_guard_spec.rb` がこのステップの存在を pin する(コメントアウトでも落ちることを実測確認済み) |
| 15 | `vsce ls --tree`内容検査PASS | ✅ CI の `package-contents-inspection` ジョブ + `release.sh` の `vsce ls --tree` でmkmf.log等のテキストベースのリーク(Task 023.6で修正済み)はhard failで検出する。`prism.bundle`/`rbs_extension.bundle`自体がこのビルドマシンのrbenv libruby絶対パスを`LC_LOAD_DYLIB`として埋め込んでいる件(`otool -L`で確認)は、独立レビュー(Review B)で「別マシンでの動的リンク解決を壊す可能性が高い」と指摘され、実際にこのマシン上の異なるRuby 3.4.xインストール間で`LoadError`を再現して確認した。1回目の修正案(`DYLD_LIBRARY_PATH`を設定するがrbenv shim自体をそのまま起動)は同じレビューで「macOSは`/bin/bash`を経由するプロセスに対し`DYLD_*`環境変数を無効化するため効果がない」と再度指摘され、実際にrbenv shim経由で無効化されることを確認した。最終的に、解決されたRubyの`RbConfig::CONFIG["bindir"]`/`["libdir"]`を問い合わせ、shimではなく実体の`<bindir>/ruby`を直接起動する方式(`vscode/src/platformCompatibility.ts#queryRubyConfigPaths`、Task 023.8)へ修正し、実際のrbenv shim経由での再現・修正確認まで完了した。埋め込みパス自体は残るがwarningとして報告し続け、機能的な影響は解消済み |
| 16 | darwin-arm64 target確認 | ✅ `vscode/package.json` の `package` スクリプト自体が `--target darwin-arm64` 固定 + `release.sh` が生成された VSIX のファイル名を検証する |
| 17 | clean install/update/uninstall PASS | ⚠️ 手動確認のみ — `vscode/scripts/verify-installed-extension.sh` を手で走らせる。0.2.14 以前は `make-final-review-bundle.sh` の "VS Code isolated install" ステップに数えられていたが、そのスクリプトも呼ばれていなかったので実態は当時から手動である(`024.125` の隣にある同種のギャップ) | <!-- unwired -->
| 18 | no process leftover | ✅ `scripts/vsix_semantic_smoke.rb`のprocess group kill(0)確認+`clientLifecycle.test.ts`のlifecycle race修正 |
| 19 | README/Support Matrix/CHANGELOG整合性 | ✅ 目視確認(Task 023.6、Ruby 3.3の扱いをSUPPORT_MATRIX.md/RELEASE_CHECKLIST.md/README.md/KNOWN_LIMITATIONS.mdで統一) |
| 19.1 | Workspace Trust: an untrusted folder cannot choose what is executed | ✅ 0.2.4 で追加・実機検証済み | `vscode/src/test/unit/workspaceTrust.test.ts` が manifest 側を fail-closed で固定(設定が増えたら restricted 宣言か「実行に影響し得ない」論証のどちらかを強制)。実機手順は下の節を参照 — **対照(公開版で再現すること)を必ず取る**。0.2.3 は約2秒後に7回実行、0.2.4 は0回、信頼済みでは7回(正当な機能が生きていること)|
| 20 | Marketplace preflight PASS | ⚠️ 手動確認のみ — 実際のMarketplace publisher登録・アップロードUIでのpreflightはpublish実行時まで発生しない(Task 023.8で確認事項として提示) |
| 21 | repository visibility change is deliberate, not implicit | ✅ Task 023.8完了時点では`gh repo view`で`PRIVATE`のまま変更していないことを都度確認していた。その後、ユーザーの明示的な指示によりpublic化(git履歴の実メールアドレス除去・リポジトリ作り直し・Issues無効化を経た上で)— visibility変更自体がpublish処理の副作用として暗黙に起きたことは一度もない |
| 22 | awaiting user approval before actual publish | ✅ 0.2.3 で充足 — オーナーの明示的な指示のもとでのみ `release.sh` が実行され、`vsce publish` へ到達した。ゲートが要求するのは打鍵者が誰かではなく、判断が人間のものであること(`docs/PUBLISHING.md`「Publishing」節を 0.2.3 で書き直し) |

## Public distributionの状態

**公開済み。** このリポジトリは https://github.com/TERUZvxght/OvalLSP
として public(公開前に実メールアドレスの履歴除去とリポジトリ作り直しを
実施 — 上の Task 023 ゲート #21)。`vscode/package.json` は repository
URL を持ち(`private: true` フィールド自体は残っているが、これは npm
への誤 publish を防ぐものであって Marketplace 公開とは無関係)、拡張
機能は VS Code Marketplace の Pre-Release チャンネルへ公開済み — 公開の
都度 `docs/RELEASE_ARTIFACTS.md` へ SHA-256 を記録する。GitHub Actions
はすべての pull request と `main` への push で実行され、その初回実行と
green は `docs/SUPPORT_MATRIX.md` の OS 行が記録している。

この節は 0.2.2 まで「private のまま・git remote なし・公開未完了」と
書いていた — 書かれた時点では真で、公開後に誰も読み直さなかった。
0.2.3 のレビューループが SUPPORT_MATRIX との直接矛盾として検出し、
現状へ書き直した。

## 次のアクション(1.0リリース作業として別途必要)

1. ~~SBOM生成~~ 完了、推移依存の完全化・VSIX実体との照合テストも完了
2. ~~VSIXクリーンインストールの実機テスト~~ 完了、Semantic Hoverまで検証する
   smokeへ拡張済み
3. ~~Linux CI でのテストスイート実行~~ 完了 — `.github/workflows/ci.yml`
   が `ubuntu-latest` で全 pull request と `main` への push のたびに実行され
   green(`docs/SUPPORT_MATRIX.md` OS 行が記録)。残るのは Windows/Linux
   **実機**での VSIX インストール検証(SUPPORT_MATRIX の既知のギャップ節の
   まま)
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

## Workspace Trust の実機検証手順(0.2.4)

`restrictedConfigurations` は manifest の宣言なので、spec は「宣言されて
いること」しか固定できません。**実際に無視されるか**は VS Code 本体の挙動で、
実機でしか確かめられません。0.2.4 の検証で判明した落とし穴を含めて記録します。

1. `--user-data-dir` は**短いパスにする**(例 `/tmp/ovt/u_x`)。VS Code は
   そこへ `1.13-main.sock` を作るため、約103文字を超えると `listen EINVAL`
   でウィンドウが存在する前にメインプロセスが死ぬ。この場合マーカーは当然
   出ないので、**修正が効いたように見える**。0.2.4 の準備で実際に踏んだ。
2. 起動は `code` CLI ではなく
   `/Applications/Visual Studio Code.app/Contents/MacOS/Code` を使う。
   CLI は `--install-extension` には使えるがウィンドウを保持しない。
3. **マーカーが出ないことを、そのまま結論にしない。** ウィンドウが開いたことを
   `<udd>/logs/*/window1/exthost/**/1-OvalLSP.log` の存在で、Core が起動した
   ことを `ps` で確認する(陽性対照)。
4. **公開済みの版で対照を取る。** 再現しない装置で修正版を試しても何も言えない。
5. 未信頼であることは共有 trust store(`content.trust.model.key`)を印字して
   確認する。プロンプトの設定だけに頼らない。
6. `.vscode/settings.json` だけでなく **`.code-workspace` の settings ブロック**
   でも試す。0.2.3 ではこちらでも7回実行された。

**未検証:** Windows / Linux(macOS のみ実施)。セッション中に信頼を付与した
場合の再適用。
