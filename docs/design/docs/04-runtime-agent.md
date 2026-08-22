# 04. Rails Runtime Agent

> **これは実装前のブリーフです。** 書かれた時点の設計意図の記録であり、
> 現在のコードの説明ではありません。**この文書とコードが食い違う場合、
> 答えはコードです。** 実装済みの挙動を知りたいときは、この文書ではなく
> `core/lib` と、それを pin している spec を読んでください。

## 1. 責務

Runtime Agentは、Railsをbootしないと得られない事実をCore Serverへ提供する。

Agentは型推論を行わない。返すのは正規化された事実である。

- Rails/Ruby/environment情報
- routes
- engines
- model existence
- Active Record columns
- associations
- enums
- validators/callbacks（後続）
- method/ancestor existence
- source locations when available
- reload state

## 2. 起動

推奨コマンド:

```bash
bundle exec bin/rails runner /absolute/path/to/ovallsp/runtime_agent_boot.rb start '<capabilities-json>'
```

環境変数:

```text
RAILS_ENV=development
OvalLSP_AGENT=1
OvalLSP_PROTOCOL_VERSION=1
```

`test` environmentはDB副作用やinitializer差があるため既定にしない。

## 3. 起動シーケンス

```text
Core spawns Agent
Agent boots Rails
Agent redirects accidental stdout to framed log notifications on stderr
Agent loads routes
Agent detects capabilities
Agent sends hello result
Core requests initial snapshot sections
Core commits snapshot generation 1
```

boot timeoutの初期値は60秒。timeout後はCoreがAgentを終了し、static-only modeへ移行する。

## 4. stdout保護

protocol streamはstdout専用とする。

- 起動直後に元stdoutを保持する。
- `$stdout`とdefault output deviceをstderr wrapperへ差し替える。
- protocol writerだけが元stdoutへ書く。
- loggerはstderrへ送る。
- stderr notificationもframed messageにするか、親側でraw logとして処理する。

最も安全なのは、stdout=responses、stderr=raw logsとし、CoreがstderrをOutput Channelへ流す方式である。

## 5. Snapshot

Agentは全情報を毎回巨大JSONで返さず、section単位で返す。

```text
metadata
routes
engines
models
model:<constant>
i18n（後続）
```

### Snapshot metadata

```json
{
  "generation": 12,
  "railsVersion": "8.x",
  "rubyVersion": "3.x",
  "environment": "development",
  "root": "/app",
  "schemaVersion": "...",
  "routesDigest": "sha256:...",
  "loadedAt": "..."
}
```

## 6. Model extraction

modelごとに返す。

```json
{
  "name": "User",
  "abstract": false,
  "tableName": "users",
  "primaryKey": "id",
  "columns": [],
  "associations": [],
  "enums": {},
  "ancestors": [],
  "sourceLocation": null
}
```

### 重要な制約

- `constantize`前にconstant名を検証する。
- modelロード失敗をmodel単位のerrorとして返す。
- abstract classを区別する。
- DBが利用不可ならcolumnsだけ欠落させ、model/association等の取得を試みる。
- リクエスト後にDB connectionをclearする。

## 7. Route extraction

各route:

```json
{
  "name": "post",
  "pathHelper": "post_path",
  "urlHelper": "post_url",
  "verb": "GET",
  "pathTemplate": "/posts/:id(.:format)",
  "requiredParts": ["id"],
  "optionalParts": ["format"],
  "defaults": {"controller": "posts", "action": "show"},
  "constraints": {},
  "sourceLocation": {"path": "config/routes.rb", "line": 4, "column": 2},
  "routeSet": "main_app"
}
```

route helperのMethod#parametersは信用せず、route required/optional partsからsignatureを合成する。

## 8. Reload

Coreがファイル変更を検出し、debounce後に`agent/reload`を送る。

Agent:

```ruby
Rails.application.reloader.reload!
Rails.application.reload_routes! if routes_changed
```

実際の公開API差をadapterに閉じ込める。

reload結果:

```json
{
  "generation": 13,
  "changedSections": ["models", "routes"],
  "errors": []
}
```

reloadに失敗した場合:

- generationを進めない。
- Coreは旧snapshotをstaleとして維持する。
- errorを通知する。
- 連続失敗時にAgent再起動を提案する。

## 9. Invalidation rules

| Changed path | Action |
|---|---|
| `config/routes.rb` | routes reload |
| `app/models/**/*.rb` | Rails reload + affected models refresh |
| `db/schema.rb`, `db/structure.sql` | schema/model refresh |
| `db/migrate/**` | pending state refresh。自動migrationしない |
| `config/initializers/**` | Agent restart |
| `Gemfile.lock` | Core/Agent full restart |
| engine routes | relevant route set refresh |

Coreがpath ruleを持ち、Agentは最終的なreload executionだけを行う。

## 10. Agent plugins

Runtime Agent pluginはRails app内で実行されるため、明示的許可とWorkspace Trustが必要。

plugin例:

- AASM states/transitions
- money-rails generated methods
- ActiveAdmin DSL
- dry-struct schema

pluginは直接protocol writerへ触れず、registryへrequest handlerとsnapshot providerを登録する。

## 11. ライフサイクル

- parent PIDを監視する。
- stdin EOFで即時shutdownする。
- shutdown requestでconnection cleanup後に`exit!`する。
- appが生成した非daemon threadに終了を妨げさせない。
- Core終了時はTERM、猶予後KILL。

## 12. Agentを既存Webサーバーへ接続しない理由

- serverごとにprocess/thread構成が異なる。
- 本番/開発serverの状態を汚染する。
- protocol endpointの追加が必要になる。
- editor終了時のcleanupが困難。
- request中のreloadと競合する。

専用`rails runner`の方が再現性が高い。
