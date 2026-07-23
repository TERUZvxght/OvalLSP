# OvalLSP — Ruby Semantic LSP (RSLSP)

Ruby/Rails向けセマンティック言語サーバーのmonorepo。設計の背景と全体方針は
[`docs/design/README.md`](docs/design/README.md) と
[`docs/design/START_HERE.md`](docs/design/START_HERE.md) を参照。

## Layout

- `core/` — Ruby製Core Language Server (`rslsp`)。LSP 3.17をstdio/Content-Length framingで実装。
- `vscode/` — VS Code拡張 (TypeScript)。workspace folderごとに `core/bin/rslsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書一式（PRD、architecture、ADR、実装タスク）。

## Status

`tasks/001-bootstrap-core-and-vscode.md` を実装済み: LSP handshake、
didOpen/didChange/didClose、固定Hover応答、VS Code拡張からの起動、統合テスト。
次は `docs/design/tasks/002-prism-file-summary.md`。

## Development

```bash
# Core Server
cd core
bundle install
bundle exec rspec

# VS Code Extension
cd vscode
npm install
npm run test:unit         # vscode API非依存の単体テスト
npm run test:integration  # Extension Development Hostでの実機テスト（VS Codeバイナリをダウンロードします）
```
