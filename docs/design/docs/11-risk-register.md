# 11. Risk Register

> **これは実装前のブリーフです。** 書かれた時点の設計意図の記録であり、
> 現在のコードの説明ではありません。**この文書とコードが食い違う場合、
> 答えはコードです。** 実装済みの挙動を知りたいときは、この文書ではなく
> `core/lib` と、それを pin している spec を読んでください。

## R-01: Ruby環境の起動失敗

- Probability: High
- Impact: High
- Cause: version manager、Bundler、native gem、missing dependencies
- Mitigation: environment resolver分離、diagnostic command、static-only mode、composed bundle

## R-02: Rails Agentの任意コード実行

- Probability: Certain
- Impact: High
- Mitigation: Workspace Trust、明示設定、no network listener、child process isolation、ログ秘匿

## R-03: 型推論の計算量爆発

- Probability: High
- Impact: High
- Cause: recursive calls、large union、monkey patches
- Mitigation: iteration limits、widening、timeouts、incremental summaries、Unknown fallback

## R-04: False positive diagnostics

- Probability: High
- Impact: High
- Mitigation: safe mode、confidence threshold、diagnosticsとcompletionの基準分離

## R-05: Rails internal API変更

- Probability: High
- Impact: Medium
- Mitigation: version adapters、reflection fallback、compatibility fixtures、public API優先

## R-06: stdout protocol corruption

- Probability: Medium
- Impact: High
- Mitigation: protocol writer専用stdout、stderr redirect、contamination tests

## R-07: Ruby LSPとの競合

- Probability: High
- Impact: Medium
- Mitigation: replacement modeの明示、検出と案内、重複機能を自動操作しない

## R-08: Memory growth

- Probability: High
- Impact: High
- Cause: AST retention、stale generations、method summaries、Rails class reload
- Mitigation: immutable summaries、generation cleanup、bounded caches、Agent restart threshold

## R-09: Runtime observationの誤誘導

- Probability: Medium
- Impact: Medium
- Mitigation: observation authorityを低くする、観測回数表示、値を保存しない

## R-10: Plugin ecosystem fragmentation

- Probability: Medium
- Impact: Medium
- Mitigation: small stable Fact API、schema validation、compatibility constraints、built-in adaptersを先行

## R-11: ERB mapping complexity

- Probability: High
- Impact: Medium
- Mitigation: MVPはembedded Ruby mappingとinstance variablesのみ、HTML LSPとの統合は後続

## R-12: 開発規模が膨張する

- Probability: High
- Impact: High
- Mitigation: Phase exit criteria、非目標固定、MVP fixtureを最初に定義、AIタスクを小分け

## Go/No-Go gates

### Gate A: Phase 3後

Ruby基本推論が既存Ruby LSPとの差を示せない場合、Rails実装へ進まずtype engineを見直す。

### Gate B: Phase 5後

Agent障害でCoreが不安定になる場合、Rails featureを追加しない。

### Gate C: Phase 7後

代表Rails fixtureのTop-5 completion recallが90%未満ならbetaへ進まない。
