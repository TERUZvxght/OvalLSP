# Task 015: Confidence-aware Diagnostics

## Goal

Rubyの動的性を考慮し、確信度の高い誤りだけを報告する安全なDiagnostics基盤を実装する。

## Depends on

- Task 013
- Task 014推奨

## In scope

- syntax diagnostics統合
- unknown method on known closed receiver
- unresolved constant with high confidence
- route helper不存在
- route argument count
- AR column/association不存在
- controller-view instance variable mismatch
- diagnostic confidence policy
- severity policy
- source/evidence metadata
- debounce/cancellation
- publishDiagnostics lifecycle
- configuration for safe/standard/strict

## Out of scope

- full static type checker
- nil dereferenceの一般検査
- security lint
- style lint
- arbitrary dynamic method absence error
- automatic code mutation

## Core policy

誤検出率を最優先する。

### Safe mode

- parser syntax error
- deterministic Rails facts
- receiver型が単一Nominalで、method setが十分に閉じている場合のみ
- dynamic escape hatchがあるclassではunknown methodを警告しない

### Standard mode

-高confidenceのsource/RBS inferenceを含める
- conditional Union methodはwarning以下

### Strict mode

- inference由来候補を増やすが、confidenceと根拠を表示する

既定値はSafe mode。

## Required interfaces

```ruby
module Ovallsp
  module Diagnostics
    Finding = Data.define(
      :code,
      :message,
      :range,
      :severity,
      :confidence,
      :evidence,
      :related_information,
      :generation
    )

    class Engine
      def analyze(document:, semantic_context:, mode:, budget:); end
    end
  end
end
```

## Behavior

- stale document versionのdiagnosticをpublishしない。
- Agent unavailable時はruntime依存diagnosticを消すか保留する。
- `method_missing`、`respond_to_missing?`、known DSL boundaryを考慮する。
- diagnostics codeを安定した文字列として定義する。
- generated methodの不足は生成元情報をrelatedInformationへ付ける。

## Tests

- syntax error
- known receiver unknown method
- Unknown receiver no false positive
- method_missing class suppression
- RBS-known method
- missing route helper
- route wrong arity
- missing AR association
- view ivar absent
- Agent offline removes runtime-only diagnostics
- rapid edits/debounce/stale version
- safe/standard/strict behavior
- false-positive corpus

## Acceptance criteria

- [ ] Safe modeでUnknown receiverへunknown-method警告を出さない
- [ ] 単一の確定receiverで存在しないmethodを検出できる
- [ ] route/ARの決定的誤りを検出できる
- [ ] Agent停止時に古いruntime diagnosticが残らない
- [ ] stale edit結果をpublishしない
- [ ] diagnosticにcode・confidence・evidenceが含まれる
- [ ] false positive regression fixtureを持つ
