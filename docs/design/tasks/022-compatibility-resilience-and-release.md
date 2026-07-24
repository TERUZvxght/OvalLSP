# Task 022: 互換性・障害復旧・1.0 Release Readiness

## Goal

対応環境、障害時挙動、互換性契約、ドキュメント、リリース手順を固定し、1.0候補として配布可能な品質へ到達する。

## Depends on

- Task 009〜021

## In scope

- support matrix
- Ruby/Rails version adapters
- protocol compatibility
- Agent auto-restart/backoff
- crash loop protection
- telemetry-free local diagnostics
- log rotation/redaction
- configuration migration
- extension/Core/Agent version negotiation
- compatibility CI
- end-to-end release tests
- user documentation
- troubleshooting
- security review
- license/SBOM
- release checklist

## Out of scope

- cloud telemetry
- paid service
- automatic project mutation
- unsupported legacy versionsの無期限維持

## Support matrix

リリース時点で実際にCI検証できる組合せへ固定する。設計文書の暫定値をそのまま宣言しない。

最低限検討:

- Ruby 3.3以降
- Rails 7.1以降
- VS Code stable current/previous
- Ubuntu/macOS/Windows
- WSL/Dev Container/Remote SSH

各組合せを次へ分類する。

- supported
- best effort
- unsupported

## Version negotiation

Core/Agent internal protocolへversionとcapabilitiesを持たせる。

- major不一致は接続拒否
- minor差はcapability negotiation
- unknown optional fieldは無視
- unknown required capabilityは明示失敗

## Resilience

Agent restart policy:

- exponential backoff
- restart上限
- manual restart
- static-only継続
- crash原因表示

Core crash時はVS Code Clientが適切に再起動し、crash loop時は停止してユーザーへ診断を示す。

## Logging

- stdout protocol contamination禁止
- file/output channel log
- token/credential/path redaction方針
- size/世代rotation
- debug modeは明示opt-in

## Release documentation

- Installation
- Supported environments
- Rails Agent security model
- Workspace Trust
- Configuration
- Features and limitations
- Dynamic Ruby limitations
- Troubleshooting
- Performance tuning
- Plugin author guide
- Privacy of observation
- Changelog/migration guide

## Release gates

- all unit/component/integration tests green
- compatibility matrix green or documented
- benchmark regression within threshold
- no known P0/P1
- protocol schemas versioned
- VSIX clean install smoke
- uninstall leaves no running process
- licenses and third-party notices
- security checklist

## Tests

- Core/Agent version mismatch
- optional capability negotiation
- crash/restart/backoff
- repeated crash loop
- log rotation
- redaction
- settings migration
- clean install/update/uninstall
- all supported platforms
- sample Rails apps
- offline operation

## Acceptance criteria

- [ ] support matrixが実CI結果に基づいている
- [ ] Core/Agent version mismatchを安全に処理できる
- [ ] Agent crash後にstatic-onlyを維持して再起動できる
- [ ] crash loopを無限再起動しない
- [ ] clean VSIX installから主要機能が動く
- [ ] uninstall/終了後に子プロセスが残らない
- [ ]ログに秘密情報を不用意に出さない
- [ ] 1.0 release checklistが全項目判定可能
