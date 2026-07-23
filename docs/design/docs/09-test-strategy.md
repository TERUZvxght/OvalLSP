# 09. Test Strategy

## 1. テスト階層

```text
unit
component
protocol contract
fixture semantic
LSP integration
VS Code extension integration
performance
compatibility
failure injection
```

## 2. Unit tests

対象:

- position conversion
- type normalization
- union/intersection
- CFG construction
- constraint solving
- method lookup
- generic substitution
- evidence merge
- Content-Length framing
- generation comparison

各unitはRailsをbootしない。

## 3. Golden semantic tests

fixture Rubyファイルと期待するsemantic query結果をJSON/YAMLで保持する。

例:

```yaml
query:
  kind: type_at
  file: app/example.rb
  marker: "<caret>"
expect:
  type: "User | nil"
  minimum_confidence: 0.9
  evidence:
    - source
    - method_summary
```

markerはfixtureからテスト時に除去する。

## 4. Rails fixture apps

### rails_minimal

- SQLite
- User/Company/Order
- standard routes
- controller/view

### rails_routes

- nested resources
- namespace
- concerns
- direct routes
- mountable engine

### rails_models

- STI
- polymorphic association
- optional belongs_to
- enum
- serialized/json columns
- scopes
- custom primary key

### rails_failure

- DB unavailable
- pending migration
- initializer warning/puts
- model load error
- missing constant

Fixture appは必要最小限にし、bundle lockを固定する。

## 5. Protocol contract tests

CoreとAgentを別々に実装してもschema互換を保つ。

- JSON Schema validation
- unknown method
- malformed header
- invalid UTF-8
- oversized message
- duplicate response
- cancellation
- process EOF

## 6. LSP integration tests

実際のstdio serverを起動し、initializeからrequestを送る。

必須:

- initialize capabilities
- incremental didChange
- completion
- hover
- definition
- signature help
- diagnostics
- cancellation
- shutdown/exit

## 7. VS Code integration

`@vscode/test-electron`でExtension Development Hostを起動する。

確認:

- extension activation
- language client start
- workspace trust behavior
- status changes
- restart command
- output channel
- multi-root isolation

semantic correctnessはCore integrationで検証し、VS Code testへ重複させない。

## 8. Failure injection

Agent test doubleで次を注入する。

- boot timeout
- response timeout
- crash mid-response
- invalid generation
- stdout contamination
- huge snapshot
- DB failure
- reload failure

Coreは常にstatic-onlyへ縮退すること。

## 9. Performance benchmark

### Corpus

- 1k files / 50k LOC
- 5k files / 250k LOC
- 10k files / 500k LOC

生成fixtureと、ライセンス上利用可能な公開Rails appを分ける。

### Metrics

- cold index time
- warm cache startup
- didChange to updated completion latency
- completion p50/p95/p99
- memory RSS
- method summary cache hit rate
- invalidation fan-out
- Agent boot/reload time

benchmarkの退行thresholdをCIへ設定するが、初期はreport-onlyとする。

## 10. Compatibility matrix

MVP CI:

```text
Ruby 3.3 / 3.4 / 4.0
Rails 7.1 / 7.2 / 8.x
Ubuntu latest
macOS latest（nightlyでも可）
Windows latest
```

正確な対応versionはリリース時に更新する。Runtime AgentのRails internal APIはversion adapterで分ける。

## 11. Precision evaluation

代表fixtureに期待候補を定義する。

### Completion

- Top-1 accuracy
- Top-5 recall
- irrelevant candidate count

### Definition

- exact target precision
- candidate set recall

### Diagnostics

- false positive rateを最優先
- safe modeでは推定由来errorを出さない

## 12. Regression policy

bug修正には必ず以下のいずれかを追加する。

- minimal unit
- semantic fixture
- Rails fixture
- protocol failure test

大きなfixtureだけで再現させない。
