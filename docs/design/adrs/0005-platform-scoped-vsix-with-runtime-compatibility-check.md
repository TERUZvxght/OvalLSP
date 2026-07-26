# ADR-0005: VSIXはビルド環境のRuby ABI/OS/CPUに紐づく単一ターゲットとして扱い、起動前に検証する

- Status: Accepted
- Date: 2026-07-26

## Context

ADR-0004はVSIXへCoreのsource一式と、Coreのruntime gem依存(prism/rbs、および両者の推移依存であるlogger/tsort)を`vendor/bundle`へvendoringする方式を採用した。しかし`bundle install`が生成するのは**vendoringを実行したマシンのRuby ABI/OS/CPUに固有のネイティブ拡張**であり(`prism.bundle`/`rbs_extension.bundle`等)、`core/bin/ovallsp`自身はこれをまったく検証せず、vendor配下の全gemの`lib`を無条件に`$LOAD_PATH`へ追加する。

VS Code拡張側は`rubyResolver.ts`でユーザー環境のRubyを解決するため、ビルド環境と異なるRuby/OS/CPUでも同じvendored payloadを読み込んでしまう。独立検証で再現:

```text
Linux x86_64, Ruby 3.3.8
ruby <unpacked-vsix>/extension/core/bin/ovallsp --stdio
=> TypeError: superclass mismatch for class Prism::ParseResult
   exit 1
```

これは診断不能な形で失敗する(利用者には何が起きたか分からない)。"Universal VSIX"を名乗ったまま単一環境ビルドのnative gemを同梱することはできない。

## Decision

4つの選択肢を検討した:

1. OS/CPU/Ruby minor別にVSIXを生成する(複数artifact)
2. Ruby runtime自体をplatform別に同梱する
3. Core gemを対象Ruby環境へ導入する方式に変更する(vendoringをやめる)
4. 当面の私的リリースをビルド環境(darwin-arm64 + Ruby 3.4.x)へ限定し、target付きVSIX・実行時互換性検証・明確な診断を追加する

**4を採用する。** 理由: 1と2は複数OS/CPUのビルド環境(CI matrix、クロスコンパイル済みRuby配布)を必要とし、このプロジェクトは現時点でgit remoteすら持たない私的リリース段階にある(`docs/RELEASE_CHECKLIST.md`)。3はADR-0004が明示的に採用しなかった設計(初回セットアップの摩擦、"repository checkoutなしで起動できる"という受け入れ基準に反する)への回帰であり、再検討する理由がない。4は将来1または2へ拡張する際の土台(manifest記録・起動前検証の仕組み)をそのまま流用でき、かつ**今アプリが壊れずに動く組合せ以外では「クリアな理由とともに動かない」**という誠実な状態を今すぐ実現できる。

### 実装

1. **`vscode/scripts/copy-core.js`**がvendoring成功後、ビルドに使った`ruby`の`RUBY_ENGINE`/`RUBY_VERSION`(major.minor)/`RUBY_PLATFORM`を`core/vendor/PLATFORM_MANIFEST.json`へ記録する。
2. **`core/bin/ovallsp`**はvendor libを`$LOAD_PATH`へ追加する前に、manifestが存在すれば現在実行中のRubyのengine/version(major.minor)/platformと比較する。不一致ならvendor libを一切追加せず、`$stderr`へ利用者が対処可能な具体的診断(期待した組合せ・実際の組合せ・対処方法)を出力する。manifestが存在しない場合(未packaging開発チェックアウト)は従来通り無条件にvendor libを追加する(vendor自体が存在しないため実質no-op)。
3. **`vscode/src/platformCompatibility.ts`**(新規)がVS Code拡張側でも同じmanifestを読み、Core起動前に選択されたRubyの実際のengine/version/platformを`ruby -e`で問い合わせて比較する。不一致ならCore Serverを起動せず、OutputChannelとエラー通知に具体的な診断(期待/実際の組合せ、対処方法)を表示する。
4. VSIXパッケージ名/manifestに対象ターゲットを明示する(`ovallsp-<version>-darwin-arm64-ruby3.4.vsix`のような命名、または`docs/SUPPORT_MATRIX.md`での明示)。

## Consequences

### Positive

- 非対応環境での「原因不明のクラッシュ」が「対処可能な診断メッセージ」に置き換わる。
- Support Matrixが実際にテスト・動作確認された組合せだけを"supported"と宣言できるようになる。
- 将来、選択肢1(複数ターゲットビルド)や2(Ruby runtime同梱)へ拡張する際、manifest記録・起動前検証の仕組みをそのまま再利用できる。

### Negative

- 私的リリースの対象は当面 darwin-arm64 + Ruby 3.4.x のみ。他の組合せのユーザーは、vendor payloadを使わず自分のRuby環境へ`prism`/`rbs`を別途インストールする必要がある(Core自体はvendor libが読み込まれなければ従来通りシステムgemにフォールバックする — ADR-0004以前の挙動)。
- 起動前検証のため、Core Server起動のたびに`ruby -e`による軽量なプローブが1回増える(数十ms程度、初回起動時のみ)。

## Rejected alternatives

- 1(複数ターゲットビルド): 複数OS/CPUのビルド環境が必要で、このリポジトリの現状のCI(git remoteなし、GitHub Actions未実行)では実現できない。将来の拡張先として本ADRのmanifest機構を流用可能。
- 2(Ruby runtime同梱): VSIXサイズの大幅増加、複数OS/CPU分のRuby runtime取得元の確保が必要で、1と同じ理由で現時点では非現実的。
- 3(project Gemfile統合への回帰): ADR-0004が明示的に不採用とした設計であり、今回の問題(native ABI不一致)の根本原因はvendoringの検証不足であって、vendoring方式そのものの問題ではない。
