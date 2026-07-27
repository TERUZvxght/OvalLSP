# ADR-0006: Marketplace Extension更新をCore更新の唯一の経路とし、独立したnetwork self-updateを持たない

- Status: Accepted
- Date: 2026-07-27

## Context

Task 023(Apple Silicon向けMarketplace Preview公開準備)にあたり、Core Server
のバージョンをどう更新するかを決める必要がある。ADR-0004はVSIXへCoreのsource
一式とvendored gemを同梱する方式(bundled Core)を、ADR-0005はビルド環境の
Ruby ABI/OS/CPUに対する起動前互換性検証を、それぞれ採用済み。しかしCore自体を
「後から」更新する仕組みはまだ存在しない。

考えられる選択肢:

1. Extension起動時にGitHub Releases等の外部ネットワーク先からCoreの新版を
   ダウンロードし、globalStorage等へ展開する独立したself-updateの仕組みを作る
2. Marketplace Extension自体の更新(VS Code自身のExtension自動更新機構)に
   Coreの更新を完全に委ねる。Extension単体がVersion Eのときは常にCore
   Version Cが同梱されている、という1対1対応を保証し、それ以上のことをしない

## Decision

**2を採用する。** 独立したnetwork self-updaterは今回のApple Silicon向け
Previewでは作らない。

理由:

- Marketplaceの自動更新は、Extension本体とそこに同梱されたCoreを**同一
  トランザクションで**入れ替える。ExtensionとCoreのバージョンドリフト
  (Extensionだけ新しい/Coreだけ古い、のような状態)がそもそも発生しない。
- 配布物が単一のVSIXアーティファクトのままで済む。ダウンロード元の署名検証・
  provenance・改竄検知・部分ダウンロード失敗時のロールバック・ダウンロード
  自体のプライバシー影響(何をどこへ問い合わせるか)を、今回のPreviewの
  スコープに一切持ち込まずに済む。
- Apple Silicon限定・Pre-Releaseチャンネル限定の最初のPreviewとしては、
  自動更新の複雑さそのものが本質的に不要 — VS Code自身がすでに持っている
  Extension更新機構をそのまま使えば要件を満たせる。

この方式が成立する前提: **VSIXに同梱されたCoreをExtensionは常に自分自身の
インストールディレクトリ配下から起動する**(`vscode/scripts/copy-core.js`が
`vsce package`時にCoreを`vscode/core/`へvendoringし、そのまま`.vsix`へ
含まれる、というADR-0004の既存方式)。globalStorageなどVSIXの外側へCoreを
展開する追加の仕組みは、今回のPreviewでは導入しない — 導入する必要のない
機能を先回りして作らない。

### 保証する10項目(ユーザー指示の原文に対応)

1. **Extension version EはCore version Cを同梱する**: `vscode/scripts/copy-core.js`
   が`vsce package`実行のたびにCoreのsourceとvendored gemを`vscode/core/`へ
   コピーし、そのVSIXへ含める(ADR-0004)。同梱されるCoreのバージョンは
   `core/lib/ovallsp/version.rb`の`Ovallsp::VERSION`そのものであり、
   手動で同期する値ではない — Task 023.2のbuild manifestがpackage時に
   この値を機械的に読み取って記録する。
2. **Extensionは自分自身が同梱するCoreのみを標準として起動する**:
   `vscode/src/serverConfig.ts`の`resolveServerConfig`は、`ovallsp.server.path`
   が明示されない限り、Extension自身のインストールディレクトリ配下
   (`context.extensionPath`基準)の`core/bin/ovallsp`を解決する。
   globalStorageや外部キャッシュを経由しない。
3. **Marketplace更新後、次のactivationでは新Coreが使われる**:
   VS CodeのExtension自動更新はディスク上のExtensionディレクトリ自体を
   新バージョンへ入れ替える(旧バージョンのディレクトリは削除される)ため、
   次にExtensionがactivateされた時点で`context.extensionPath`はすでに
   新バージョンのディレクトリを指す。追加の実装は不要 — VS Code自身の
   Extension更新機構がこの保証を提供する。
4. **古いExtensionの残留Coreは起動されない**: 3と同じ理由により、旧
   Extensionディレクトリ自体がVS Codeによって削除されるため、旧Coreを
   指す`extensionPath`は存在しなくなる。ただし、旧Extensionが起動した
   Core子プロセスが**プロセスとして生き残ったまま**になるケースは別問題
   であり、Task 023.3(LanguageClient lifecycle)のスコープ。
5. **globalStorageへの展開が必要になった場合の要件**(将来、選択肢1へ
   拡張する場合の設計メモ、今回は実装しない): version-tagged directory
   (`<globalStorage>/core-<version>-<sha256-prefix>/`)+ 展開後にhash検証 +
   検証成功後のatomic rename、という手順を踏むこと。中間状態のディレクトリを
   直接参照させない。
6. **更新失敗時に現在動いているCoreを破壊しない**: 今回の方式では
   Core自体をExtensionの外へ展開しないため、この懸念は原理的に発生しない
   (VS Code自身のExtension更新が失敗すれば、Extensionは単に旧バージョンの
   まま動き続ける — VS Code自身のExtension更新機構の責務であり、OvalLSP
   側の実装は関与しない)。
7. **新Core起動確認後の旧Core安全削除**: 6と同じ理由で今回は不要
   (VS Code自身が旧Extensionディレクトリの削除を管理する)。
8. **custom server pathは自動更新されない**: `ovallsp.server.path`が
   明示設定されている場合、`resolveServerConfig`はその値をそのまま使い、
   Extension更新の影響を受けない(そもそも同梱Coreを参照しないため)。
9. **custom server pathは互換性チェックのみ行い、不一致時は明確に拒否する**:
   `platformCompatibility.ts`のcompatibility checkは、custom server path
   使用時も実行される(Task 023.2で、bundled/monorepo/customの分類を
   診断出力へ明示する形へ拡張する — 詳細はTask 023.2の設計文書)。
10. **展開なしでExtensionディレクトリから直接起動する場合、不要な展開/
    ダウンロード機構を追加しない**: 上記の通り、これが採用した方式そのもの。
    「Marketplace更新がCoreの更新でもある」ことをテストと文書で保証する
    (Task 023.5の更新regressionテストA-G、本ADRの`Consequences`)。

## Consequences

### Positive

- 配布・更新モデルがVS Code自身のExtension更新機構に完全に委譲され、
  OvalLSP側で新たに検証・保守すべき「独自の更新パイプライン」が存在しない。
- ExtensionとCoreのバージョンドリフトが構造的に発生しない(同一VSIX内の
  同一バージョンとしてのみ存在する)。
- 署名検証・provenance・tampering対策は、Marketplace自体のExtension配布
  セキュリティモデルにそのまま乗る形になる。

### Negative

- Coreだけを単体で更新する(Extension全体を再インストールせずにCoreだけ
  差し替える)ことはできない。将来的にCore単体の頻繁な更新が必要になった
  場合は、選択肢1(独立したnetwork self-update)を再検討する必要がある。
- Marketplace自体がoutageの場合、Coreの更新もExtensionの更新と運命を共にする
  (ただしこれはExtension自体の更新が届かないことと同義であり、Preview
  段階で許容できるリスクと判断する)。

## Rejected alternatives

- 1(独立したnetwork self-update): 署名検証・provenance・改竄検知・
  部分失敗時のロールバック・プライバシー影響の全てを、今回のApple Silicon
  限定Previewのスコープに持ち込むことになり、公開準備を不必要に遅らせる。
  Coreの更新頻度がExtension自体の更新頻度と乖離しない限り、再検討する
  理由がない。

## 関連

- ADR-0004(VSIXへのCore同梱、dual-run-mode)
- ADR-0005(platform-scoped VSIXと起動前互換性検証)
- Task 023.2(Extension/Core version・protocol manifest・handshake — bundled/
  monorepo/customの分類判定と診断出力の拡張)
- Task 023.5(darwin-arm64 targetパッケージングと、E1/C1→E2/C2更新regression
  テストA-G)
