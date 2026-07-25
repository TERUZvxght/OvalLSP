# Task 009: 継承・include・prependとMethod Lookup

## Goal

Rubyの通常の祖先関係をSemantic Graphへ取り込み、receiver型からinstance/singleton method候補と定義位置を一貫して解決する。

## Depends on

- Task 001〜008
- Task 008.5

## In scope

- superclass declaration
- `include`
- `prepend`
- `extend`
- class/module reopen
- instance method lookup
- singleton method lookup
- visibility
- `alias` / `alias_method`の静的引数
- ancestor generationとinvalidation
- method origin metadata
- Union receiverの候補統合

## Out of scope

- refinements
- 動的な`include(send(...))`
- `method_missing`の一般解決
- arbitrary `class_eval`
- RBS祖先情報
- method body return inference

## Required interfaces

```ruby
module Ovallsp
  module Semantic
    AncestorEntry = Data.define(:name, :kind, :origin, :location)

    MethodCandidate = Data.define(
      :symbol_id,
      :declarations,
      :owner,
      :visibility,
      :lookup_rank,
      :conditional,
      :origin
    )

    class HierarchyIndex
      def replace_file(summary); end
      def remove_file(uri); end
      def ancestors(type_name, singleton: false); end
      def generation; end
    end

    class MethodResolver
      def resolve(receiver_type:, name:, context:); end
      def complete(receiver_type:, prefix:, context:, limit:); end
    end
  end
end
```

名称は既存構成へ合わせてよいが、Hierarchyの構築とMethod Queryを分離すること。

## Behavior

### Instance lookup order

通常クラスについて、少なくとも次を表現する。

1. classへprependされたmodule
2. class自身
3. classへincludeされたmodule
4. superclass側の同じ順序
5. Object / Kernel / BasicObject

実際のRubyの`ancestors`順序をfixtureで確認し、独自の推測順序を固定しないこと。

### Singleton lookup

- `def self.foo`
- `class << self`
- `extend SomeModule`
- superclassのsingleton class

を区別して探索する。

### Union receiver

`User | Admin`へ問い合わせた場合:

- 全memberで利用可能なmethodを上位表示する。
- 一部memberのみのmethodは`conditional: true`とする。
- definitionは候補集合を返してよい。
- diagnosticsではconditional候補を即エラーにしない。

### Visibility

- private methodを明示receiver付きcompletionの通常候補に出さない。
- lexical selfへの暗黙呼び出しではprivateを解決可能にする。
- protectedは初期版では候補に残し、metadataを保持する。

### Invalidation

次の変更で依存するlookup cacheを破棄する。

- superclass変更
- include/prepend/extendの追加・削除・順序変更
- method追加・削除
- class/module reopenの追加・削除

## Tests

- simple inheritance
- multi-level inheritance
- module include
- multiple include order
- prepend precedence
- extend singleton methods
- class reopen
- alias and alias_method with symbols
- private/protected/public
- Union common/conditional candidates
- cycle or unresolved constant degrades to partial ancestors
- file removal removes ancestor contribution
- 1,000 classes lookup benchmark

## Acceptance criteria

- [ ] `Admin < User`で`Admin.new.name`が`User#name`へ解決される
- [ ] prepend methodがclass methodより先に解決される
- [ ] included moduleのmethodへdefinitionできる
- [ ] `extend`されたmodule methodをclass receiverで補完できる
- [ ] private methodを不正な明示receiver候補として上位表示しない
- [ ] class reopen後も同一classのmethod集合として統合される
- [ ] ancestor変更時にstale lookupが残らない
- [ ] unresolved ancestorでCoreが落ちず、取得可能な候補だけ返す

## Commands

```bash
cd core
bundle exec rspec
bundle exec ruby -Ilib bin/ovallsp --version
```
