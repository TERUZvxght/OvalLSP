# Task 019: Opt-in Runtime Observation

## Goal

テストまたは明示コマンド実行中にworkspace内methodの引数・戻り値クラスを観測し、静的にUnknownな型へ低authority evidenceとして統合する。

## Depends on

- Task 018

## In scope

- explicit opt-in command
- isolated observation runner
- TracePointまたは同等機構
- workspace path filtering
- class-only event recording
- method identity mapping
- argument class union
- return class union
- sample counts
- observation generation
- evidence merge
- expiration/invalidation
- overhead benchmark
- privacy documentation

## Out of scope

- 値の保存
- argument文字列やinspect保存
- production process injection
- network upload
- exhaustive path coverage claim
- observationを高authorityにすること

## Privacy and safety

保存可能:

- class/module名
- method SymbolId
-引数位置
-呼び出し回数
-例外終了の有無

保存禁止:

- 実値
-文字列内容
-SQL
-環境変数
-ファイル内容
-秘密情報

## Required interfaces

```ruby
module Ovallsp
  module Observation
    ObservedSignature = Data.define(
      :symbol_id,
      :parameter_types,
      :return_type,
      :samples,
      :run_id,
      :code_fingerprint,
      :created_at
    )

    class Store
      def replace_run(run); end
      def evidence_for(symbol_id); end
      def invalidate_changed(fingerprints); end
    end
  end
end
```

## Behavior

- observation authorityはsource/RBS/Rails deterministic factsより低くする。
- 1回しか観測されていない型を網羅的型と断定しない。
- `NilClass`を内部Nilへ変換する。
- anonymous classやsingleton classは安全に正規化する。
- workspace外Gemイベントを既定で収集しない。
- code fingerprint変更時に古い観測をstale化する。

## VS Code commands

- `OvalLSP: Run Tests with Type Observation`
- `OvalLSP: Clear Observed Types`
- `OvalLSP: Show Type Evidence`

テストコマンドは設定可能にする。

## Tests

- method arg/return class
- nil and union
- exception path
- workspace filtering
- no values persisted
- code change invalidation
- repeated runs merge/replace policy
- observation disabled by default
- runner crash
- overhead benchmark

## Acceptance criteria

- [ ] opt-in時だけ観測runnerが起動する
- [ ] 実値を永続化しない
- [ ] Unknown returnをobserved unionで補助できる
- [ ] 明示RBSを観測結果で上書きしない
- [ ] source変更後に古い観測を使用しない
- [ ] runner障害で通常LSPが影響を受けない
- [ ] overheadとprivacy制約を文書化する
