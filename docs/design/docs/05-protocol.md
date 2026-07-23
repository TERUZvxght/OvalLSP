# 05. Internal Protocol

## 1. 概要

VS CodeとCore Serverは標準LSP 3.17を使用する。

Core ServerとRuntime Agentは、JSON-RPC 2.0互換の**RSLSP Agent Protocol v1**を使用する。

transport:

```text
Content-Length: <bytes>\r\n
Content-Type: application/vscode-jsonrpc; charset=utf-8\r\n
\r\n
<json>
```

Content-Typeは省略可能だがwriterは付与する。

## 2. バージョニング

hello request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "agent/hello",
  "params": {
    "protocolVersion": 1,
    "coreVersion": "0.1.0",
    "capabilities": {
      "progress": true,
      "partialResults": true
    }
  }
}
```

response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": 1,
    "agentVersion": "0.1.0",
    "root": "/workspace",
    "railsVersion": "8.x",
    "rubyVersion": "3.x",
    "capabilities": {
      "routes": true,
      "activeRecord": true,
      "reload": true,
      "runtimePlugins": true
    }
  }
}
```

major protocol不一致は接続拒否。minor機能はcapabilityで交渉する。

## 3. 共通型

### SourceLocation

```json
{
  "path": "app/models/user.rb",
  "line": 12,
  "column": 4,
  "endLine": 12,
  "endColumn": 20
}
```

line/columnは0-basedに統一する。

### AgentError

```json
{
  "code": "DATABASE_UNAVAILABLE",
  "message": "...",
  "recoverable": true,
  "details": {},
  "backtrace": []
}
```

backtraceはdebug設定時のみ返す。

## 4. Requests

### agent/hello

接続確立とcapability negotiation。

### agent/snapshot

params:

```json
{
  "sections": ["metadata", "routes", "models"],
  "ifGeneration": 10
}
```

`ifGeneration`と同じならnotModifiedを返せる。

### agent/model

```json
{"name": "User", "include": ["columns", "associations", "enums", "ancestors"]}
```

### agent/routeLocation

```json
{"helper": "post_path", "routeSet": "main_app"}
```

### agent/reload

```json
{
  "reason": "filesChanged",
  "changedPaths": ["app/models/user.rb"],
  "sections": ["models"]
}
```

### agent/restartRequired

query形式で、変更pathがrestartを必要とするか確認する。MVPではCore側ruleのみでもよい。

### agent/plugin/request

```json
{
  "plugin": "aasm",
  "method": "modelStates",
  "params": {"model": "Order"}
}
```

### agent/shutdown

終了要求。

## 5. Notifications

### agent/progress

```json
{
  "jsonrpc": "2.0",
  "method": "agent/progress",
  "params": {
    "token": "reload-12",
    "kind": "report",
    "message": "Reloading models",
    "percentage": 60
  }
}
```

### agent/invalidated

Agent側で変化を検出した場合。既定ではAgentにfile watcherを持たせないため、将来用途。

### agent/log

structured log。raw stderrも許容するが、protocol利用を推奨。

### agent/runtimeChanged

pluginやRails内部の変化でsnapshot generationが変わったとき。

## 6. Cancellation

Coreは長いrequestに`$/cancelRequest`互換notificationを送る。

Agentはrequestごとのtokenを保持する。Rails reflection APIが中断不能な場合、結果送信だけを破棄する。

## 7. Message ordering

- request IDは接続内で一意。
- responsesは順不同を許可する。
- snapshot commitはgeneration順。
- reload中のmodel queryは旧snapshotを返すか、`busy=true`を返す。
- MVP Agentはsingle-flight reloadと、read requestの並行処理なしでもよい。

## 8. Limits

- max message: 32MB
- max model batch: 500
- max route count: 100,000
- max error backtrace: 50 frames
- strings are UTF-8

超過時はpartial resultまたは明示error。

## 9. LSP custom methods

VS Code固有UI用にCoreが提供するcustom request:

```text
rslsp/status
rslsp/restartRuntimeAgent
rslsp/showEvidence
rslsp/explainType
rslsp/runObservation
rslsp/clearCaches
```

標準language featureは必ず標準LSP requestで返す。
