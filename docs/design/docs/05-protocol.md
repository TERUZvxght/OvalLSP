# 05. Internal Protocol

## 1. 概要

VS CodeとCore Serverは標準LSP 3.17を使用する。

Core ServerとRuntime Agentは、JSON-RPC 2.0互換の**OvalLSP Agent Protocol v1**を使用する。

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

### agent/models

引数なし。`agent/snapshot`の"models"section（name/tableNameのみの軽量discovery）と異なり、非abstractな全モデルのcolumns/associationsをまとめて1回のround tripで返す（Task 008.5: 実Railsアプリでモデル数が多い場合、モデル毎に`agent/model`を発行するとrequest/response overheadが支配的になるため）。

```json
{"models": [{"name": "User", "tableName": "users", "columns": [...], "associations": [...], "partial": false}]}
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

**未実装。** `$/cancelRequest` 相当のものは Core にも Agent にも無い
(`grep -r cancelRequest core/lib vscode/src` が0件)。長い request の
唯一の打ち切り手段は `AgentProcessManager` の request timeout であり、
それは応答を待つのをやめるだけで、Agent 側の処理は走り続ける。

この節はかつて実装済みの仕様として書かれていた。0.2.14 で事実に
書き換えたが、節そのものは残す — 番号を詰めると `section 7` を指す
ソースコメントが壊れるためであり、また「無い」ことは仕様の一部だから
である。

## 7. Message ordering

- request IDは接続内で一意。
- responsesは順不同を許可する。
- snapshot commitはgeneration順。
- reload中のmodel queryは旧snapshotを返すか、`busy=true`を返す。
- MVP Agentはsingle-flight reloadと、read requestの並行処理なしでもよい。

## 8. Limits

**この4つの数値は実装されていない。** 0.2.14 に確認した時点で、
`core/lib` と `vscode/src` のどこにも message サイズ上限・model batch
上限・route 数上限・backtrace フレーム数上限は無い。`coreProcess.ts` の
`SNAPSHOT_MAX_BUFFER_BYTES = 32 * 1024 * 1024` は名前が似ているが、
`ps` の出力を読む `execFile` の `maxBuffer` であってプロトコルとは
関係がない。

実際に効いている制約は2つだけである:

- **文字列は UTF-8**。これは本当で、`agent.rb` が明示エンコーディングで
  読み書きする。
- **request timeout**。`AgentProcessManager#request` が待つのをやめる。
  超過時に "partial result または明示 error" が返るという記述も
  実装されていない — 返るのは timeout であり、呼び出し側は
  `MemberAvailability` の `unknown` に落とす。

上限を入れるならこの節を仕様として書き直してから入れること。逆順に
なっていたのが 0.2.14 以前の状態である。

## 9. LSP custom methods

VS Code固有UI用にCoreが提供するcustom request:

```text
ovallsp/status
ovallsp/restartRuntimeAgent
ovallsp/showEvidence
ovallsp/explainType
ovallsp/runObservation
ovallsp/clearCaches
```

標準language featureは必ず標準LSP requestで返す。
