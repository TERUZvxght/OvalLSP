# OvalLSP — Ruby Semantic LSP

> **開発途中のプロジェクトです。** 現在、開発者自身が調査・修正作業を
> 継続的に行っている段階のため、**外部からのissue提案・Pull Requestは
> 現在受け付けていません**。PRチェックが後回しになり、開発者側で
> 進行中の修正と内容が重複してしまう可能性があるためです。詳細は
> [CONTRIBUTING.md](CONTRIBUTING.md)を参照してください。

Ruby/Rails向けセマンティック言語サーバーのmonorepo。設計の背景と全体方針は
[`docs/design/README.md`](docs/design/README.md) と
[`docs/design/START_HERE.md`](docs/design/START_HERE.md) を参照。

## Layout

- `core/` — Ruby製Core Language Server (`ovallsp`)。LSP 3.17をstdio/Content-Length framingで実装。
- `vscode/` — VS Code拡張 (TypeScript)。workspace folderごとに `core/bin/ovallsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書一式（PRD、architecture、ADR、実装タスク）。
- `docs/design/docs/12-release-and-support.md` — 利用者向けリリースドキュメント
  (Installation、Security model、Configuration、Troubleshooting等)。
- `docs/SUPPORT_MATRIX.md` / `docs/RELEASE_CHECKLIST.md` — 対応環境と1.0
  リリースチェックリスト。

## Status

`docs/design/tasks/001-*.md` 〜 `022-*.md` を実装済み(1.0リリース候補に
向けた準備段階)。詳細は`docs/RELEASE_CHECKLIST.md`と
`docs/SUPPORT_MATRIX.md`を参照。

- LSP transport、didOpen/didChange/didClose、Hover/completion/signature help
- Prismによる宣言抽出とdocumentSymbol、永続キャッシュによるwarm start
- ワークスペース索引・definition・workspace/symbol・find references・rename
- ローカル型推論(`ovallsp/explainType`)、RBS/RBI連携
- Runtime Agentプロセス管理(hello/status/snapshot/model/reload/shutdown)、
  exponential backoff付き自動再起動とcrash loop保護
- Rails routesからの`*_path`/`*_url`補完・signature help・definition
- Active Recordモデルのcolumn/association型推論、Rails DSL(enum/scope/delegate)
- controller→viewへのinstance variable伝播(ERB)
- Plugin API(static/runtime)、プロセス隔離されたplugin実行
- opt-inのruntime型観測(Task 019)
- VSIXパッケージング、Ruby環境の自動解決(mise/asdf/rbenv/chruby/PATH)
- ログredaction、protocol version negotiation

`core/bin/ovallsp`はワークスペースroot直下に`bin/rails`があるRailsアプリを検出すると、
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
