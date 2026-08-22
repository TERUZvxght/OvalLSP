# 08. Implementation Plan

> **これは実装前のブリーフです。** 書かれた時点の設計意図の記録であり、
> 現在のコードの説明ではありません。**この文書とコードが食い違う場合、
> 答えはコードです。** 実装済みの挙動を知りたいときは、この文書ではなく
> `core/lib` と、それを pin している spec を読んでください。

## 1. 開発原則

- 各phaseは独立してgreenになる。
- Rails機能より先にRubyの意味解析基盤を完成させる。
- completionだけを個別実装せず、同じSemantic Queryをhover/definitionと共有する。
- 性能計測を後回しにしない。
- dynamic機能は必ずstatic fallbackを持つ。

## 2. Repository layout

```text
ovallsp/
├── Gemfile
├── ovallsp.gemspec
├── exe/ovallsp
├── lib/ovallsp/
│   ├── server.rb
│   ├── transport/
│   ├── lsp/
│   ├── documents/
│   ├── parser/
│   ├── index/
│   ├── semantic/
│   ├── types/
│   ├── inference/
│   ├── rails/
│   ├── agent/
│   ├── plugins/
│   └── support/
├── runtime_agent/
│   ├── boot.rb
│   ├── server.rb
│   ├── extractors/
│   └── plugins/
├── vscode/
│   ├── package.json
│   ├── src/
│   └── test/
├── fixtures/
│   ├── ruby_basic/
│   ├── rails_minimal/
│   └── rails_complex/
├── spec/
├── benchmark/
└── docs/
```

monorepoを採用する。protocol schemaとfixtureを共有しやすくするためである。

## 3. Phase 0: Skeleton and transport

### Deliverables

- Ruby executable `ovallsp --stdio`
- initialize/shutdown/exit
- didOpen/didChange/didClose
- hover固定応答
- VS Code extensionがCoreを起動
- integration test

### Exit criteria

- Extension Development HostでRuby fileを開くとserver logが確認できる。
- incremental text syncが正しい。
- UTF-16 LSP positionとUTF-8 Ruby byte offsetの変換テストが通る。

## 4. Phase 1: Parser and symbol index

### Deliverables

- Prism error-tolerant parse
- FileSummary
- constants/classes/modules/methods index
- document symbols
- workspace symbols
- constant definition
- incremental replacement

### Exit criteria

- class reopenを統合できる。
- syntax error中も既存symbolを可能な限り維持する。
- 1,000 file fixtureの初回index benchmarkを記録する。

## 5. Phase 2: Local type inference

### Deliverables

- type model
- CFG
- assignment inference
- literals
- branch union
- nil narrowing
- `new` return type
- local completion
- explainType debug output

### Exit criteria

次が解決される。

```ruby
user = User.new
user.name
```

```ruby
value = condition ? User.new : Company.new
```

```ruby
return unless user
user.name
```

## 6. Phase 3: Method summaries and hierarchy

### Deliverables

- include/prepend/inheritance
- method lookup
- body return inference
- summary cache
- recursive fixed point/widening
- call chain completion
- signature help base

### Exit criteria

```ruby
def build_user
  User.new
end

build_user.name
```

を解決する。

## 7. Phase 4: RBS integration

### Deliverables

- RBS environment loader
- RBS type converter
- stdlib signatures
- project `sig/`
- gem RBS collection
- overload selectionの初期版

### Exit criteria

- `Array[T]#map`のblock型と戻り値を解決する。
- RBSの明示型がbody推論より優先される。

## 8. Phase 5: Runtime Agent foundation

### Deliverables

- Agent process spawn
- framed JSON-RPC
- hello/snapshot/reload/shutdown
- stdout protection
- crash handling
- stale snapshot

### Exit criteria

- Agent kill後もCore completionが動く。
- Agent再起動でsnapshotが復元する。
- initializerの`puts`でprotocolが壊れない。

## 9. Phase 6: Rails routes

### Deliverables

- routes snapshot
- helper declarations
- signatures
- definition to routes.rb
- controller action location
- main_app/engine route set model

### Exit criteria

- standard resources
- nested resources
- namespace
- member/collection
- optional format

のfixtureが通る。

## 10. Phase 7: Active Record

### Deliverables

- model discovery
- columns
- associations
- generic Relation[T]
- common finder rules
- enums
- schema invalidation

### Exit criteria

READMEのMVP chainを補完・Hover・definitionできる。

## 11. Phase 8: Controller-view

### Deliverables

- action-view mapping
- instance variable propagation
- render static target
- partial locals explicit hash
- ERB embedded Ruby document mapping

### Exit criteria

`@user`が対応viewでUserとして解決される。

## 12. Phase 9: Diagnostics and references

### Deliverables

- safe diagnostics
- references index
- confidence filtering
- guarded rename preview

Renameは確定参照のみ自動編集し、dynamic候補を別一覧にする。

## 13. Phase 10: Observation

### Deliverables

- opt-in test runner
- TracePoint based workspace filtering
- class-only event storage
- observed signatures
- evidence merge

### Exit criteria

- test実行後にUnknown returnがobserved unionへ改善する。
- 値や秘密情報を保存しない。
- overhead benchmarkを提示する。

## 14. 最初に実装しないもの

- Rust化
- distributed analysis
- persistent daemon shared by workspaces
- cloud index
- AI inference in core path
- automatic project code mutation
- automatic migration

## 15. Release milestones

### 0.1-alpha

Phase 0-3。Rubyのみ。

### 0.2-alpha

Phase 4-6。RBSとroutes。

### 0.3-alpha

Phase 7-8。Rails日常利用可能。

### 0.5-beta

diagnostics、references、plugin preview。

### 1.0

性能・互換性・crash recovery・documentationを安定化。
