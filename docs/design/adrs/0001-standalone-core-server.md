# ADR-0001: Ruby LSPアドオンではなく独立Core Serverを採用する

- Status: Accepted
- Date: 2026-07-23

## Context

製品の中心はRails機能追加ではなく、Ruby全般のmethod resolution、型推論、semantic graphである。Ruby LSP add-onは既存機能の拡張に適するが、基底の意味解析を置換することを主目的としていない。

## Decision

独立したLSPサーバーをRubyで実装する。Ruby LSPとRuby LSP Railsは設計・テスト・必要なMITコードの参照元とする。

## Consequences

### Positive

- 型エンジンとindexを自由に設計できる。
- API互換性を自分で管理できる。
- 他editorへそのまま展開できる。

### Negative

- document sync、transport、index等を自前で構築する必要がある。
- Ruby LSPとの機能重複が生じる。
- 初期開発量が増える。

## Rejected alternatives

- Ruby LSP add-onのみ: 中核置換が困難。
- Ruby LSP fork: upstream追随コストが継続する。
- VS Code APIのみ: editor lock-inとExtension Host負荷が大きい。
