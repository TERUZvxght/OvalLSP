# Task 005: Runtime Agentの起動とheartbeat

## Goal

CoreがRails fixture内でRuntime Agentを子プロセスとして起動し、hello/status/shutdownを実行できる。initializerの標準出力でprotocolが壊れない。

## In scope

- AgentProcessManager
- Content-Length internal transport
- agent/hello
- agent/status
- agent/shutdown
- timeout/crash handling
- static-only degradation
- rails_minimal fixture

## Out of scope

- routes
- Active Record extraction
- reload
- plugins

## Acceptance criteria

- [ ] Rails root/versionを受信
- [ ] initializer `puts` fixtureで接続成功
- [ ] Agent kill後もCore生存
- [ ] boot timeout後にstatic-only
- [ ] Core終了でAgentが残らない
