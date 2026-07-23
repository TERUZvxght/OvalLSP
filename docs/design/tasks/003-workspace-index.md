# Task 003: Incremental Workspace Index

## Goal

FileSummaryをworkspace-wide indexへ追加・置換・削除し、constant/method declaration queryを提供する。

## In scope

- WorkspaceIndex
- generation
- file contribution removal
- file watcher notifications from LSP
- definition for constants
- workspace symbols
- benchmark harness

## Required interfaces

```ruby
class WorkspaceIndex
  def replace_file(summary); end
  def remove_file(uri); end
  def declarations(symbol_id); end
  def search(query, limit:); end
  def generation; end
end
```

## Constraints

- mutationはsingle writer。
- query中に部分更新状態を見せない。
- same content hashは再indexしない。
- stale document versionのsummaryをrejectする。

## Acceptance criteria

- [ ] 1,000 file generated fixtureをindex可能
- [ ] 1ファイル変更時に他FileSummaryを再parseしない
- [ ] class reopenのdefinition候補を全て返す
- [ ] removeで寄与が完全に消える
