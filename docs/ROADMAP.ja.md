# ロードマップ

[English version](ROADMAP.md)

各リリースで「何ができるようになるか」を、利用者が早く気づく順に並べて
います。

ここでのバージョン番号は**何が一緒に届くか**の約束であって、時期の約束
ではありません。patchリリースは意図的に載せていません。新しく告知するものが
無いためです。ただし「すでにした約束を実際に果たす」のはpatchであり、
ケイパビリティ行が現れたり ✅ に変わったりすることはあります（各位置の意味は
[`PUBLISHING.md`](PUBLISHING.md) を参照）。

以下の各項目は、READMEのケイパビリティ・マトリクスの各行に対応します。
それぞれの根拠と、Pylanceの機能のうち意図的に**予定しない**ものは
[`design/tasks/024-deferred-review-findings.md`](design/tasks/024-deferred-review-findings.md)
（英語、024.R3）にあります。

## 0.4.0 — 細部の調整

- **検査ごとのseverity設定。** `ovallsp.diagnostics.severities` で有効な検査を warning・information・hint へ格下げ、または none で抑制します。構文エラーは error を維持できます。設定解除で既定値へ戻り、open / closed の両方を更新します。safe を既定に保ち、モードや unresolved-constant を有効にする公開設定は追加しません。
- **`require` の自動挿入。** 対応範囲の plain Ruby ファイルで JSON・URI・Pathname の明示的なクイックフィックスを提示し、診断なしの要求にも応答します。Rails、bundle / Ruby 選択環境、名前衝突、構文が不確実な場合は辞退します。古い CodeAction の安全な適用は保証しないため、編集後は改めて提案を取得してください。
- **signature help が対応する引数をハイライトします。** キーワードは順序によらず名前で対応させ、過剰・未知・曖昧な引数に強調範囲を返しません。S4・G20・Q4 の範囲は[能力表](EXTENSION_CAPABILITIES.ja.md)を参照してください。

## 1.0.0 — 機能ではなく、保証

このページで唯一、ケイパビリティを追加しないリリースです。代わりに
READMEのマトリクスにある2つの但し書きを消します。

- **公開するすべてのプラットフォームを検証済みにする。** Apple Silicon
  だけでなく、`darwin-x64`・`win32-x64`・`linux-x64` です（024.R4）。
- **素のRubyプロジェクトを保証する。** Railsだけではありません。有限の auto-require など個別 fixture の検証はありますが、plain Ruby workspace
  全体の保証はまだありません（024.R1）。

それまでは、READMEのマトリクスの ✅ はすべて「macOS Apple Silicon上の、
Railsプロジェクトで、同梱Coreを使った場合に検証済み」という意味であり、
それ以外は何も保証しません。
