# Task 020: VSIX配布・Ruby環境解決・Remote対応

## Goal

開発用monorepo相対パスに依存せず、一般ユーザーがVSIXを導入してCore Serverを起動できる配布・環境解決機構を実装する。

## Depends on

- Task 013

## In scope

- Core gem/runtimeのVSIX同梱または管理方式
- executable discovery
- Ruby resolver
- Bundler context
- rbenv/asdf/mise/chruby/RubyInstaller
- macOS/Linux/Windows
- WSL
- Dev Container / Remote SSH
- multi-root workspace isolation
- status UI
- restart command
- output channel/log path
- configuration validation
- install diagnostics
- extension packaging tests

## Out of scope

- Ruby本体の自動ダウンロード
- shell profileの自動書換え
- cloud service
- marketplace自動公開

## Architecture decision required

次のどちらかを明示的に選びADRへ記録する。

### A. CoreをVSIXへ同梱

- extension versionとCore versionを固定しやすい
- Ruby runtimeはユーザー環境を利用

### B. Gemとして別途導入

- Ruby/Bundlerとの整合が高い
- 初回セットアップが増える

推奨は、Core source/gem payloadをVSIXへ同梱し、workspaceのRubyで`bundle exec`せず起動できるモードと、project Gemfileへ統合するモードを分ける構成。実装前に検証すること。

## Ruby resolver

優先順を設定可能にする。

1. explicit `ovallsp.rubyExecutablePath`
2. VS Code terminal/environment integration
3. mise
4. asdf
5. rbenv
6. chruby
7. PATH
8. Windows RubyInstaller locations

shellを毎回起動せず、解決結果をworkspace単位でcacheする。

## Bundler

Runtime Agentは対象Rails appのbundle contextで起動する必要がある。Core自身の依存とworkspace bundleを混同しない。

## Required UX

Status:

- Starting
- Indexing
- Ready static
- Ready Rails
- Agent unavailable
- Configuration error

Commands:

- Restart Server
- Restart Rails Agent
- Show Logs
- Show Environment Diagnostics
- Re-index Workspace

## Tests

- packaged VSIX smoke test
- path with spaces/non-ASCII
- explicit Ruby path
- fake rbenv/asdf/mise
- Bundler missing
- Rails bundle mismatch
- Windows path quoting
- WSL/Remote extension host
- multi-root distinct Ruby versions
- untrusted workspace
- extension update migration

## Acceptance criteria

- [ ] repository checkoutなしでVSIXからCoreを起動できる
- [ ] Ruby executable選択理由を診断画面で確認できる
- [ ] workspaceごとに異なるRuby/Bundlerを扱える
- [ ] Windows/macOS/Linuxでpath quotingが壊れない
- [ ] Remote環境ではremote extension host側でCoreを起動する
- [ ] Agentだけ再起動できる
- [ ] 設定エラー時もExtension Hostが不安定にならない
