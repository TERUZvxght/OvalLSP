# ADR-0002: Rails Runtime Agentはstdio子プロセスとする

- Status: Accepted
- Date: 2026-07-23

## Context

Rails実行時情報が必要だが、Rails bootは不安定かつ任意コード実行を伴う。TCPはport競合、認証、firewall、cleanupが必要になる。

## Decision

Core Serverが`bin/rails runner`を子プロセスとして起動し、stdin/stdoutでContent-Length framed JSON-RPCを行う。

## Consequences

- Windows/macOS/Linuxで同じモデルを使える。
- 外部から接続できない。
- parent death時にchild cleanupを実装する必要がある。
- Railsのstdout汚染対策が必須。
