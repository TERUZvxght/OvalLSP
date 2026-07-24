# Task 011: Generic型・Block Parameter・Enumerable推論

## Goal

`Array[T]`、`Relation[T]`等の型引数を保持し、block引数とblock戻り値を推論してRubyで頻出するcollection処理を解決する。

## Depends on

- Task 010

## In scope

- `Nominal[name, args]`
- type parameter substitution
- Proc/block type
- block parameter bindings
- block return inference
- built-in generic method rules
- Array / Hash / Enumerable / Enumerator
- ActiveRecord::Relation / CollectionProxy
- `each`, `map`, `select`, `filter_map`, `find`, `first`, `to_a`
- block arityの基本処理
- safe widening

## Out of scope

- 完全なRBS overload selection
- keyword block forwarding completeness
- numbered parametersの全特殊ケース
- destructuringの完全対応
- lazy enumerator全API

## Required interfaces

```ruby
module Rslsp
  module Types
    TypeParameter = Data.define(:name)
    ProcType = Data.define(:parameters, :return_type)
  end

  module Semantic
    GenericRule = Data.define(
      :receiver_pattern,
      :method_name,
      :parameters,
      :block_type,
      :return_template
    )

    class GenericRuleRegistry
      def register(rule); end
      def resolve(receiver_type:, method_name:, arguments:, block:); end
    end
  end
end
```

## Behavior

### Array

```ruby
users = [User.new]
users.first
```

`users`は`Array[User]`、`first`は`User | nil`。

```ruby
users.map { |user| user.name }
```

block parameterは`User`、全体は`Array[String]`。

### Union elements

`Array[User | Admin]`のblock parameterはUnionを維持する。member数上限を超えた場合は既存widening policyに従う。

### Active Record

Task 007の型を次の規則へ接続する。

```text
Relation[T]#each            block(T) -> Relation[T]またはself相当
Relation[T]#map             block(T)->U -> Array[U]
Relation[T]#first           -> T | nil
Relation[T]#first!          -> T
Relation[T]#find_each       block(T) -> nil/self（実APIに合わせて決定）
CollectionProxy[T]#build    -> T
CollectionProxy[T]#to_a     -> Array[T]
```

実際の戻り値と一致するよう、Rails APIをfixtureで確認する。

### Block forms

- `{ |x| ... }`
- `do |x| ... end`
- numbered parameter `_1`
- symbol-to-procは初期限定対応またはUnknownへ縮退

## Tests

- array literal homogeneous/heterogeneous
- empty array
- `map`, `each`, `select`, `filter_map`
- nested blocks
- numbered parameters
- relation map/first/to_a
- collection proxy build
- generic substitution in chained calls
- block syntax error partial inference
- type argument explosion widening

## Acceptance criteria

- [ ] `Array[User]#map`のblock引数がUser
- [ ] map結果がblock戻り値のArrayになる
- [ ] `Relation[Order]#first`が`Order | nil`
- [ ] `CollectionProxy[Order]#build`がOrder
- [ ] nested blockで外側bindingを壊さない
- [ ] 空collectionやUnknown elementで安全に縮退する
- [ ] generic型をHoverと内部explainTypeで表示できる
