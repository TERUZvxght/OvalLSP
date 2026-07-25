# Task 013: Unified Semantic QueryとLSP機能統合

## Goal

Completion、Hover、Definition、Signature Helpが同一のSemantic Query層を利用し、機能ごとに異なる推論結果を返さない構成へ統合する。

## Depends on

- Task 012

## In scope

- semantic context construction
- type_at
- resolve_call
- members_of
- definitions_of
- signatures_of
- evidence/explain query
- Completion
- Completion resolve
- Hover
- Definition
- Signature Help
- result ranking
- confidence表示
- cancellation and request budget
- Ruby/ERB context
- Rails generated declarations

## Out of scope

- references
- diagnostics
- rename
- code actions
- semantic tokens

## Required interfaces

```ruby
module Ovallsp
  module Semantic
    QueryContext = Data.define(
      :uri,
      :position,
      :document_version,
      :workspace_generation,
      :runtime_generation,
      :signature_generation,
      :budget,
      :cancellation_token
    )

    class QueryService
      def type_at(context); end
      def members_of(context, receiver_type:, prefix: nil); end
      def definitions_of(context, target:); end
      def signatures_of(context, call:); end
      def explain(context, target:); end
    end
  end
end
```

## Behavior

### Completion

候補源:

- local variables
- constants
- lexical methods
- receiver methods
- Rails generated methods
- route helpers
- columns/associations
- RBS/Gem methods

ranking要素:

- exact/prefix match
- lexical proximity
- receiver確度
- origin authority
- visibility
- common vs conditional Union member
- deprecated metadata

同名候補はoriginを維持し、必要なら1候補へ集約してresolve時に詳細を返す。

### Hover

最低限:

```text
User#company
() -> Company | nil
Origin: Active Record belongs_to
Defined: app/models/user.rb:4
Confidence: high
```

情報不足時は断定的な表示を避ける。

### Definition

- source declaration
- RBS/RBI declaration
- generated declaration origin
- route source
- controller action secondary target
-複数候補

generated symbol自体に物理位置がない場合は、生成元DSLまたはschemaへ移動する。

### Signature Help

- active parameter
- positional/keyword
- overloads
- route required/optional parts
- `_path`/`_url`名維持
- block signature

### Staleness

QueryContext生成時の各generationを結果へ紐づける。処理中に世代が変わった場合は、古い結果を破棄するかstale metadataを付ける。

## Tests

- same expression across completion/hover/definition consistency
- non-ASCII position
- unsaved document precedence
- ERB controller context
- route helper
- AR column and association
- method summary chain
- RBS method
- Union conditional candidates
- cancellation
- budget timeout
- stale generation
- completion ranking golden tests
- VS Code integration smoke tests

## Acceptance criteria

- [ ] 同一式についてHoverとCompletionが同じreceiver型を利用する
- [ ] method chain末尾で適切なmember補完が出る
- [ ] generated Rails methodの生成元へdefinitionできる
- [ ] route/通常method/RBSでSignature Helpが統一的に動く
- [ ] timeout/cancelでserverが不安定にならない
- [ ] 未保存文書がディスク索引より優先される
- [ ] explain queryで型の根拠を確認できる
- [ ] VS Code上で主要4機能の統合テストが通る
