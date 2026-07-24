# Task 021: 永続Cache・Incremental Invalidation・性能安定化

## Goal

大規模Ruby/Railsリポジトリで、起動時間、編集応答、メモリ使用量を実用範囲へ収める。

## Depends on

- Task 013
- Task 020とは独立実装可能

## In scope

- cache format/version
- FileSummary persistence
- MethodSummary persistence
- signature environment cache metadata
- Rails snapshot cache with stale marking
- content hash validation
- dependency graph persistence
- selective invalidation
- startup warm path
- memory bounds/LRU
- benchmark corpus
- profiling
- cancellation/backpressure
- regression thresholds

## Out of scope

- shared global daemon
- cloud cache
- distributed index
- AST object persistence
- cacheをsource of truthにすること

## Cache rules

Cache keyへ最低限含める。

- RSLSP schema version
- Ruby version
- Prism version
- workspace canonical path identity
- relevant Gemfile.lock digest
- RBS environment digest
- file content hash
- settings affecting semantics

保存禁止:

- live AST node
- process object
- open document unsaved text
- secrets
- runtime values

## Startup

1. metadataを読み込む。
2. 有効なFileSummaryをrestoreする。
3. file stat/hashで検証する。
4. Open Documentが来たら常に上書きする。
5. Cold Indexで不足・変更分だけ解析する。

## Performance targets

初期目標として測定し、fixtureと実アプリで現実性を調整する。

- 1k files cold index: 5秒以内目標
- 5k files warm usable: 3秒以内目標
- didChange→completion p95: 200ms以内目標
- Hover p95: 150ms以内目標
- memory: 500k LOCで1.5GB未満目標

目標を満たせない場合も数値を隠さず記録する。

## Invalidation

- file summary change
- hierarchy dependency
- method summary dependency
- signature generation
- runtime snapshot generation
- plugin generation
- settings change

全cache clearだけで正しさを保つ実装を最終形にしない。

## Tests

- cold/warm equivalence
- corrupt cache
- schema version change
- Ruby/Gemfile.lock change
- single file edit fan-out
- deleted file
- unsaved doc never persisted
- interrupted write atomicity
- concurrent workspace instances
- memory pressure
- benchmark report generation

## Acceptance criteria

- [ ] warm start結果がcold解析と意味的に一致する
- [ ] corrupt/stale cacheでCoreが落ちない
- [ ] file 1件変更時に無関係summaryを再計算しない
- [ ] unsaved内容を永続化しない
- [ ] cache writeがatomic
- [ ] benchmark数値をCI artifactまたは文書へ出力する
- [ ] regression thresholdを少なくともreport-onlyで導入する
