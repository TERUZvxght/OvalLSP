# Contributing

[English version](CONTRIBUTING.md)

**現在、外部からのissue・Pull Requestは受け付けていません。** 開発者
自身が現在このコードベースの調査・修正作業を継続的に行っており、外部PR
のレビューはその作業より後回しになります — つまり、提出されたPRが
開発者側で進行中の変更と重複・衝突してしまう可能性があり、それを
タイムリーに検知できません。同じ理由でこのリポジトリのIssuesは
無効化されています。

コードベースがより安定した段階に達したら変更される予定で、その際は
本文書を更新します。それまでの間、forkして手元で試すことは自由に
行っていただけます。

OvalLSPへの関心をありがとうございます。このプロジェクトは現在
active PreviewとしてContributingしています。以下はリポジトリの
実際の運用方法を反映しています。

## リポジトリ構成

- `core/` — Ruby製Core Language Server (`ovallsp`)。LSP 3.17をstdio上で実装。
- `vscode/` — VS Code拡張(TypeScript)。workspace folderごとに
  `core/bin/ovallsp --stdio` を起動する薄いLSPクライアント。
- `docs/design/` — 設計文書・ADR・タスクごとの実装ノート
  (`docs/design/tasks/*.md`)。
- `docs/` — 利用者・リリース向け文書(Support Matrix、Release
  Checklist、SBOM、Security Checklist)。

## 開発環境セットアップ

Ruby 3.4.xとNode.jsが必要です(対象のVS Code APIバージョンは
`vscode/package.json`の`engines.vscode`を参照)。

```bash
cd core && bundle install
cd ../vscode && npm install
```

## テストの実行

```bash
# Core Server (Ruby)
cd core && bundle exec rspec

# VS Code extension (TypeScript単体テスト)
cd vscode && npm run test:unit

# VS Code extension (統合テスト、実際のExtension Development Host)
cd vscode && npm run test:integration
```

`npm run test:integration`はmonorepo相対のCore Serverに対して拡張機能を
テストします(packagingステップ不要)。`npm run test:integration:packaged`
はさらに先に`copy-core.js`を実行し、packaging済みのCore配置に対して
テストします — `vscode/scripts/copy-core.js`やVSIX packaging自体を
変更する際に有用です。

## このプロジェクトが守っているコード規律

- すべてのバグ修正には、その修正がなければ実際に失敗するregression
  テストを付ける(修正を一時的に戻してテストが失敗することを確認した後、
  修正を復元する形で検証済み) — たまたま通るテストではなく。
- 修正は報告された症状だけでなく根本的な設計に対処する — レビューでの
  発見が「このアーキテクチャがこの種のバグを許容している」ことを示唆
  する場合、修正すべきはアーキテクチャ自体である。
- 新機能・修正には自身のテストが含まれることが期待される。変更する
  挙動に対するテストカバレッジのないPRは、そのままマージされる可能性は
  低い。
- 振る舞いに関する主張は、受け入れるのではなく確かめる。意味論の問いは
  Rubyインタプリタに対して、「どれくらい起きるか」の問いは実際のコードに
  対して。レビューの指摘も、何かを「意図的」と呼ぶ根拠も、行動に移す前に
  検証する。
- 本当のtrade-offを伴う設計判断(自明な実装詳細ではなく)は
  `docs/design/adrs/`配下にADRとして記録する。

## PRを開く前に

1. 上記の関連テストスイートを実行する。
2. VSIX packagingに影響する変更の場合、`cd vscode && npm run package`
   を実行し成功することを確認する。
3. 何を・なぜ変更したか、実行したテストを記載する。

## バグ報告・機能要望

[SUPPORT.ja.md](SUPPORT.ja.md)を参照。セキュリティ関連の問題は、公開
issueではなく[SECURITY.ja.md](SECURITY.ja.md)を参照してください。

## Code of Conduct

このプロジェクトは[Code of Conduct](CODE_OF_CONDUCT.ja.md)に従います。
