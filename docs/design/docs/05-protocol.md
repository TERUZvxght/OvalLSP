# 05. Internal Protocol

## 1. 概要

VS CodeとCore Serverは標準LSP 3.17を使用する。

Core ServerとRuntime Agentは、JSON-RPC 2.0互換の**OvalLSP Agent Protocol v2**を使用する。

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
    "protocolVersion": 2,
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
    "protocolVersion": 2,
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

**不一致は接続拒否。** `AgentProcessManager#compatible_protocol_version?`は
`==`で比べるので、major/minorの区別なくどの差でも拒否する。この行は長く
「major不一致は接続拒否」と書いていたが、そう動いたことはない。minor機能は
capabilityで交渉する。

**version 2は0.3.0。** `agent/gemIndex`を追加し、`module_answer`に
`privateInstanceMethods`と`protectedInstanceMethods`を加えた。version 1は
0.1.0から0.2.18まで。

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

### agent/status

引数なし。生きていることの確認だけを目的とし、pidと起動からの経過秒を返す。

```json
{"pid": 41234, "uptimeSeconds": 12.5}
```

### agent/snapshot

params:

```json
{
  "sections": ["routes", "models"],
  "ifGeneration": 10
}
```

`ifGeneration`と同じならnotModifiedを返せる。

**`"metadata"` sectionは0.2.16で削除した。** Task 006で実装したが、
要求する側が一度も現れなかった — `AgentProcessManager#fetch_snapshot`の
呼び出し元はいずれも`["routes"]`を渡し、specも要求していない。内容は
`agent/hello`のresponseの4フィールドのうち3つを言い換えたものだったので、
必要とするCoreにはより安価な尋ね方が既にあった。sectionを1つも名指さない
requestは何も返さない(以前は`"metadata"`を既定にしていた)。`048`を参照。

### agent/model

```json
{"name": "User", "include": ["columns", "associations", "enums", "ancestors"]}
```

### agent/models

引数なし。`agent/snapshot`の"models"section（name/tableNameのみの軽量discovery）と異なり、非abstractな全モデルのcolumns/associationsをまとめて1回のround tripで返す（Task 008.5: 実Railsアプリでモデル数が多い場合、モデル毎に`agent/model`を発行するとrequest/response overheadが支配的になるため）。

```json
{"models": [{"name": "User", "tableName": "users", "columns": [...], "associations": [...], "partial": false}]}
```

### agent/gemIndex

引数なし。0.3.0で追加。読み込まれている名前付きモジュールのうち、
`Object.const_source_location`が`…/gems/<name>-<version>/`を指すものだけを、
その gem ごとにまとめて返す。

```json
{"gems": {"activerecord-8.1.3.1": {"classes": [
  {"name": "ActiveRecord::Base",
   "ancestors": ["ActiveRecord::Base", "ActiveRecord::Persistence", "Object"],
   "instanceMethods": ["save"],
   "privateInstanceMethods": ["_run_save_callbacks"],
   "protectedInstanceMethods": [],
   "singletonMethods": ["find"],
   "singletonAncestors": ["ActiveRecord::Querying"],
   "definesMethodMissing": false}
]}}}
```

**コアクラスは構造上ここに現れない。** `Object.const_source_location("Integer")`
は`[]`を返すため、gemのパスに帰属させられず、この一覧に載らない。gemが
`Integer`を再オープンしていても同じである。

`instanceMethods`は**publicとprotectedの集合**であり、privateは別に送る。
レシーバなしの呼び出しは継承したprivateにも届くので、分けずに送ると
ActionControllerのサブクラスにおける`process_action`が「存在しないメソッド」
として報告される。

`definesMethodMissing`を送るのは、`method_missing`を定義するクラスが
どんな索引にも列挙できない名前に答えるためである。「閉じている」が
「メソッド集合を全部知っている」を意味しなければ、その上に築いた検査は
確かめていないことを主張することになる。

### agent/ancestors

```json
{"names": ["ActiveSupport::TestCase", "Widget"]}
```

response: `objectAncestors`(そのプロセスの`Object.ancestors`)と、
名前ごとに次の三つのいずれか。

- `{"ancestors": [...]}` — 読み込み済みなので実際の祖先鎖を`Object`のそれと
  比較できる;
- `{"definedOutsideWorkspace": true}` — 読み込まれていないが、ワークスペース
  外のファイルからのautoloadとして登録されている。何も読み込まずに決着する;
- `null` — アプリケーションがその名前を知らないか、まだ読み込んでいない
  ワークスペースのファイルからしか知らない。どちらもCoreの静的な読みを
  そのまま残す。

### agent/routeLocation

**未実装。** `core/lib`のどこもこのメソッドを名指していない。routeの位置は
`agent/snapshot`のroute tableが`sourceLocation`として既に運んでいるので、
Coreはそちらから読む。

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

**未実装。** `core/lib`のどこもこのメソッドを名指していない。

query形式で、変更pathがrestartを必要とするか確認する。MVPではCore側ruleのみでもよい。

### agent/plugin/request

**未実装。** `core/lib`のどこもこのメソッドを名指していない。

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

**未実装。** `core/lib`のどこもこの通知を名指していない。

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

**未実装。** `core/lib`のどこもこの通知を名指していない。Agentのstderrは
そのままCoreのOutput channelへ流れる。

structured log。raw stderrも許容するが、protocol利用を推奨。

### agent/runtimeChanged

**未実装。** `core/lib`のどこもこの通知を名指していない。

pluginやRails内部の変化でsnapshot generationが変わったとき。

## 6. Cancellation

**未実装。** `$/cancelRequest` 相当のものは Core にも Agent にも無い
(`grep -r cancelRequest core/lib vscode/src` が0件)。長い request の
唯一の打ち切り手段は `AgentProcessManager` の request timeout であり、
それは応答を待つのをやめるだけで、Agent 側の処理は走り続ける。

この節はかつて実装済みの仕様として書かれていた。0.2.14 で事実に
書き換えたが、節そのものは残す。理由は二つある。第一に「無い」ことは
仕様の一部だからであり、これは単独で成り立つ。第二に、番号を詰めると
`section 7` を指すソースコメントが壊れる — 具体的には
`core/lib/ovallsp/agent_process_manager.rb` の一箇所であり、`core/lib`
にある本ファイルへの残り三つの引用は節番号を挙げていない。数ではなく
場所を書くのは、読者が確かめられるようにするためである(`024.168`)。

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

VS Code固有UI用にCoreが提供するcustom request。**この一覧は
`Server#dispatch` と双方向に照合される** —
`scripts/check_watched_extensions.rb` ではなく
`scripts/check_protocol_doc.rb` が、旧名の残留と現行名の欠落の両方で
失敗する:

```text
ovallsp/status
ovallsp/restartAgent
ovallsp/showTypeEvidence
ovallsp/explainType
ovallsp/runObservedTests
ovallsp/clearObservedTypes
ovallsp/reindexWorkspace
```

**3つの旧名が現行仕様として並んでいた。** `ovallsp/restartRuntimeAgent`、
`ovallsp/showEvidence`、`ovallsp/runObservation`、`ovallsp/clearCaches` は
Coreのどこにも無く、`ovallsp/clearObservedTypes` と
`ovallsp/reindexWorkspace` は実装されているのに載っていなかった。最後の
2つは名前を置き換えれば同じ意味になるものでもない —
`clearCaches` はキャッシュ全般を、`clearObservedTypes` は観測した型だけを
指す。この節の検査は Agent の dispatch と第2節の `protocolVersion` しか
見ておらず、冒頭の版とこの一覧はその保証の外にあった。2026-09-05 の
批判的レビュー R16。

標準language featureは必ず標準LSP requestで返す。
