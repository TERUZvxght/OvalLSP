# Task 010: Method Summary・戻り値推論・Call Chain

## Goal

Ruby method bodyから戻り値型を推論してMethodSummaryを生成し、通常メソッド呼び出しと複数段のcall chainへ型を伝播する。

## Depends on

- Task 009

## In scope

- method body storage/reference
- implicit last expression
- explicit `return`
- multiple return paths
- parameter placeholders
- receiver/self type
- call resolution through Task 009
- MethodSummary cache
- summary dependency graph
- recursive fixed point
- widening and timeout
- call chain inference
- source evidence and confidence

## Out of scope

- block generic inference
- RBS overloads
- arbitrary metaprogramming
- interprocedural effect analysis completeness
- exception flow completeness

## Required interfaces

```ruby
module Ovallsp
  module Semantic
    MethodSummary = Data.define(
      :symbol_id,
      :parameter_types,
      :return_type,
      :effects,
      :dependencies,
      :confidence,
      :generation,
      :status
    )

    class MethodSummaryStore
      def fetch(symbol_id); end
      def replace(summary); end
      def invalidate(symbol_ids); end
    end

    class MethodAnalyzer
      def summarize(symbol_id:, context:, budget:); end
    end
  end
end
```

## Behavior

### Return type

```ruby
def build_user
  User.new
end
```

は`User`。

```ruby
def find_user(flag)
  return nil unless flag
  User.new
end
```

は`User | nil`。

### Parameter constraints

初期版ではparameter型がUnknownでもよい。ただし、method内の操作から狭められる情報とcall site由来の情報を将来統合できる構造にする。

### Self

instance method内の`self`はowner nominal type、singleton method内は`ClassOf[Owner]`として扱う。

### Recursion

- 最大反復数を設定する。
- 収束しない場合はwidenする。
- summary statusへ`complete`, `partial`, `timeout`, `recursive_widened`等を保持する。
- 再帰でserver threadを占有し続けない。

### Dependencies

`A#foo`が`B#bar`を呼ぶ場合、`B#bar` summary変更時に`A#foo`をinvalidateする。

### Chain

```ruby
current_user.company.orders.first.total
```

各callごとにMethodResolverとSummaryStoreを通し、途中でUnknownになっても既知区間のevidenceを保持する。

## Tests

- implicit return
- explicit return
- branch union
- early return
- self return
- calls another method
- chain across 3+ methods
- direct recursion
- mutual recursion
- dependency invalidation
- method deletion
- overloaded declarations without RBS degrade conservatively
- timeout returns Unknown/partial instead of crash

## Acceptance criteria

- [ ] method bodyから単純なNominal戻り値を推論できる
- [ ]複数return pathをUnionできる
- [ ] `build_user.name`で`build_user`をUserとして解決できる
- [ ] method chain途中の戻り値を次receiverへ渡せる
- [ ] summary依存先変更時に呼び出し元summaryが更新される
- [ ] direct/mutual recursionが制限内で終了する
- [ ] timeout時もLSP requestが応答する
- [ ] summaryにevidence・confidence・generationが残る
