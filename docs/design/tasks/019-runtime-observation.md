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

保存可能な内容の唯一の正は `vscode/PRIVACY.ja.md` とする(0.1.12)。ここで
一覧を書き写すと、そちらだけが更新されて食い違う。設計上の制約として
重要なのは次の一点のみ:

- 保存するのは*型*(クラス名)であって、値ではない。

保存禁止(OvalLSPが*抽出して保持する*ものについての制約):

- 実値
- 文字列内容
- SQL
- 環境変数
- ファイル内容
- 秘密情報

これはあなた自身のテストスイートの出力についての主張ではない。観測実行中の
一時ログにはテストコマンドの標準出力・標準エラーがそのまま入り、Railsアプリ
であればSQLを日常的に含む(0.1.12 の訂正)。この線引きの正は
`vscode/PRIVACY.ja.md`。

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
