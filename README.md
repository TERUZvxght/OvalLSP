# OvalLSP — Ruby Semantic LSP (RSLSP)

Ruby/Rails向けセマンティック言語サーバーのmonorepo。設計の背景と全体方針は
[`docs/design/README.md`](docs/design/README.md) と
[`docs/design/START_HERE.md`](docs/design/START_HERE.md) を参照。

## Layout

- `core/` — Ruby製Core Language Server (`rslsp`)。LSP 3.17をstdio/Content-Length framingで実装。
- `vscode/` — VS Code拡張 (TypeScript)。workspace folderごとに `core/bin/rslsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書一式（PRD、architecture、ADR、実装タスク）。

## Status

`docs/design/tasks/001-*.md` 〜 `008-*.md` を実装済み。

- LSP transport、didOpen/didChange/didClose、Hover
- Prismによる宣言抽出とdocumentSymbol
- ワークスペース索引・definition・workspace/symbol
- ローカル型推論(`rslsp/explainType`)
- Runtime Agentプロセス管理(hello/status/snapshot/model/reload/shutdown)
- Rails routesからの`*_path`/`*_url`補完・signature help・definition
- Active Recordモデルのcolumn/association型推論
- controller→viewへのinstance variable伝播(ERB)

`core/bin/rslsp`はワークスペースroot直下に`bin/rails`があるRailsアプリを検出すると、
バックグラウンドスレッドでRuntime Agentを起動し、routesとmodelのsnapshotを取得して
補完・definition・型推論に反映する（Railsが無い/起動失敗時は静的機能のみで継続）。

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
