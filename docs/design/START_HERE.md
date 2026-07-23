# START HERE

## 推奨する最初の作業

1. このディレクトリ全体を新規repositoryの`docs/design/`へ置く。
2. `tasks/001-bootstrap-core-and-vscode.md`をAI実装エージェントへ渡す。
3. Task 001の完了報告とdiffを別AIまたは人間がレビューする。
4. `tasks/002-prism-file-summary.md`へ進む。

## AIへ最初に渡すプロンプト

```text
添付の設計文書一式に従って、tasks/001-bootstrap-core-and-vscode.mdを実装してください。

重要条件:
- docs/02-architecture.mdで定義されたプロセス境界を変更しない。
- タスク範囲外のPrism、Rails、型推論を先行実装しない。
- stdoutにはLSP protocol以外を出力しない。
- UTF-16位置変換のテストを必ず含める。
- 既存テストを削除または緩和しない。
- 実装完了後、変更ファイル、設計判断、実行したテスト、既知の制約を報告する。
```

## 最初の技術判断

- Core: Ruby
- Parser: Prism（Task 002から）
- VS Code client: TypeScript + `vscode-languageclient/node`
- Test: RSpec + Vitest + VS Code integration test
- Transport: stdio + Content-Length framing
- Repository: monorepo

## 判断を保留してよい項目

Task 001では以下を確定しなくてよい。

- composed bundleの最終方式
- RBS/RBI優先順位の詳細
- Runtime observation
- plugin公開API
- Rails version adapter
- persistent cache形式
