# Task 017: Rails DSL拡張

## Goal

実Railsアプリで頻出する決定的DSLを、CoreのSemantic GraphとRuntime Agent factsへ追加する。

## Depends on

- Task 013
- Task 015推奨

## In scope

優先順:

1. `enum`
2. `scope`
3. `delegate`
4. `attribute`
5. `store_accessor`
6. `has_one`
7. polymorphic associationの保守的型
8. ActiveSupport::Concern
9. controller `helper_method`
10. mailer/jobの規約的entry points

## Out of scope

- Rails全DSL
- engine完全対応
- Action Cable完全対応
- callback効果解析
- arbitrary macro execution
- Gem固有DSL

## Architecture

各DSLを直接Serverへ分岐追加しない。少なくとも次の共通factへ正規化する。

```ruby
GeneratedMethodFact = Data.define(
  :owner,
  :name,
  :kind,
  :parameters,
  :return_type,
  :source_location,
  :origin,
  :confidence,
  :metadata
)
```

Runtime reflectionが決定的なものはAgentを優先し、未boot/編集中はstatic adapterへ縮退する。

## DSL requirements

### enum

- predicate/bang/scopes
- prefix/suffix
- instance getter/setter
- source location
- Rails version differences

### scope

- class method declaration
- return `Relation[Model]`
-引数は静的に取得可能な範囲
- dynamic body内部型の断定はしない

### delegate

- delegated method name
- target receiver type
- prefix
- allow_nilによるnil
- private option

### attribute/store_accessor

- generated getter/setter
- type metadata when available
- nullable/Unknown fallback

### Concern

- included blockの宣言寄与
- class_methods block
- dependency/invalidation

## Tests

Rails version fixtureで以下:

- enum variants
- scope with args
- delegate prefix/allow_nil
- attribute typed/untyped
- store_accessor
- has_one optional
- polymorphic belongs_to
- Concern include/class_methods
- helper_method visible in view
- Agent unavailable static fallback
- DSL removal invalidation

## Acceptance criteria

- [ ] enum generated methodsを補完・Hover・Definitionできる
- [ ] scope戻り値が`Relation[Model]`
- [ ] delegate先の戻り値を伝播できる
- [ ] Concernによるmethodをancestor lookupへ統合できる
- [ ] DSL削除後にgenerated symbolが残らない
- [ ] Agent停止時も静的に取得可能なDSLは利用できる
- [ ] Rails version差をadapterまたはfixtureで管理する
