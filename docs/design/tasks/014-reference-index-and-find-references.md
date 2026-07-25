# Task 014: Reference IndexとFind References

## Goal

静的に同一性を確認できる参照をFileSummaryへ収集し、workspace-wide Find Referencesを提供する。

## Depends on

- Task 013

## In scope

- constant references
- local variable references
- instance/class variable references within valid scope
- explicit receiver method call references
- implicit self method references
- route helper references
- AR generated method references when receiver確定
- reference confidence
- per-file contribution replacement/removal
- include declaration option
- partial result/cancellation

## Out of scope

- string/symbol based dynamic send
- arbitrary reflection
- template engine beyond ERB
- exact references through method_missing
- rename execution

## Required interfaces

```ruby
module Ovallsp
  module Index
    Reference = Data.define(
      :symbol_id,
      :location,
      :kind,
      :confidence,
      :origin,
      :receiver_type,
      :generation
    )

    class ReferenceIndex
      def replace_file(uri:, references:); end
      def remove_file(uri); end
      def references(symbol_id, minimum_confidence:, limit: nil); end
    end
  end
end
```

## Behavior

- parser/index phaseではcall site候補を収集する。
- semantic resolution後に確定SymbolIdを付与する。
- unresolved候補を確定referenceと同じ集合へ混ぜない。
- reopenされたclass declarationは同じconstant SymbolIdへ集約する。
- local variableはlexical scope identityを持ち、同名別scopeを混同しない。
- file change時は旧参照寄与を完全に除去する。

## Dynamic candidates

将来のRename preview用に、次を別集合として保存してよい。

```ruby
send(:name)
public_send("name")
```

ただしFind Referencesの既定結果へ確定参照として含めない。

## Tests

- constant references
- namespaced constant
- local shadowing
- instance variable in controller/view context
- explicit receiver method
- implicit self method
- Union receiver ambiguity
- route helper
- generated AR association
- file replacement/removal
- class reopen
- cancellation/large result
- dynamic symbol candidate separation

## Acceptance criteria

- [ ] constantの宣言と参照を検索できる
- [ ] lexical scopeの異なる同名localを混同しない
- [ ] receiver型が確定したmethod callを正しいSymbolIdへ結び付ける
- [ ] ambiguous callを確定参照として扱わない
- [ ] route/AR generated method参照を検索できる
- [ ] file削除後に参照が残らない
- [ ] 大量結果でpartial/cancelが機能する
