# Task 016: Guarded RenameとRename Preview

## Goal

確定参照だけを自動編集し、曖昧・動的参照を明示的に除外またはpreview表示する安全なRenameを実装する。

## Depends on

- Task 014
- Task 015推奨

## In scope

- prepareRename
- local variable rename
- constant rename
- method rename for high-confidence references
- declaration edits
- generated symbol rename refusal or DSL-origin guidance
- dynamic candidate preview
- conflict checks
- versioned WorkspaceEdit
- multi-file edit
- cancellation

## Out of scope

- filesystem path rename
- Rails model/table migration
- route DSL自動書換え
- symbol/string dynamic callの自動編集
- broad heuristic rename

## Safety rules

### Local variable

lexical bindingが確定している場合のみ許可する。

### Constant

- declaration identityと参照が確定していること。
- namespace衝突を確認する。
- Zeitwerk file renameは別機能とし、このTaskでは警告または拒否する。

### Method

- receiver/declarationが確定したreferenceだけ編集する。
- override chain全体のrenameは初期版では明示選択または拒否する。
- dynamic candidatesは編集せずpreviewへ表示する。

### Generated Rails methods

`user.company`のようなassociation generated method上でRenameされた場合、直接method call群だけを書き換えず、生成元DSLを変更すべき旨を返す。自動修正はしない。

## Required interfaces

```ruby
module Rslsp
  module Rename
    Plan = Data.define(
      :target,
      :confirmed_edits,
      :dynamic_candidates,
      :conflicts,
      :warnings,
      :generation
    )

    class Planner
      def prepare(context); end
      def plan(context, new_name:); end
    end
  end
end
```

## Tests

- local variable and shadowing
- constant namespace conflict
- method explicit receiver
- implicit self method
- override ambiguity
- dynamic send candidate
- generated Rails method refusal
- unsaved document versions
- file changes during planning
- invalid identifier
- multi-root isolation

## Acceptance criteria

- [ ] local variableをscope内だけ安全にrenameできる
- [ ]曖昧なmethod renameを拒否またはwarning付きpreviewにする
- [ ] dynamic sendを自動編集しない
- [ ] generated Rails methodで危険な直接renameを行わない
- [ ] stale document versionへのWorkspaceEditを返さない
- [ ] conflictを事前検出する
- [ ] rename planをテスト可能な内部表現として持つ
