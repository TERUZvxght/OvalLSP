# Task 018: Static/Runtime Plugin APIとPlugin SDK

## Goal

Gem固有・社内DSL対応をCore本体へ直書きせず追加できる、versionedかつ障害分離されたPlugin APIを実装する。

## Depends on

- Task 017

## In scope

- plugin manifest validation
- static plugin lifecycle
- runtime plugin lifecycle
- declaration/fact contribution
- generic rule contribution
- diagnostic contribution with policy
- capability declaration
- API version negotiation
- timeout/error isolation
- workspace trust
- plugin discovery from explicit config
- example plugin
- SDK documentation

## Out of scope

- remote plugin marketplace
- arbitrary downloaded code execution
- automatic plugin installation
- in-process untrusted sandbox guarantee
- UI extension API

## Security policy

- Runtime pluginはRailsアプリと同等のコード実行権限を持つため、trusted workspaceのみ。
- 自動検出したGemだけを理由にコード実行しない。
- pluginは明示設定または同梱allowlistからロードする。
- timeout、例外、protocol violationでCore/Agent全体を落とさない。

## Manifest

既存`plugin-manifest.schema.json`を実装へ接続し、最低限次を持つ。

```json
{
  "name": "rslsp-aasm",
  "version": "0.1.0",
  "apiVersion": "1",
  "entrypoint": "lib/rslsp_aasm/plugin.rb",
  "capabilities": ["staticFacts", "runtimeFacts"]
}
```

## Required interfaces

```ruby
module Rslsp
  module Plugins
    class StaticContext
      def register_declarations(...); end
      def register_generic_rules(...); end
      def register_diagnostics(...); end
    end

    class RuntimeContext
      def register_snapshot_section(...); end
      def register_reload_hook(...); end
    end
  end
end
```

Pluginへ内部WorkspaceIndex objectを直接渡さない。

## Failure isolation

- pluginごとの時間予算
- plugin名付きlog
- disable after repeated failure
- malformed contribution validation
- generationごとの全体置換
- unload/reload

## Example plugin

最小のfixture DSLを定義し、次を生成するpluginを同梱する。

```ruby
state_machine do
  state :pending
end
```

`pending?`等のmethod factを返す。

## Tests

- manifest validation
- API version mismatch
- trusted/untrusted workspace
- static contribution
- runtime contribution
- timeout
- exception
- malformed fact
- reload/removal
- two plugins isolation
- example plugin end-to-end

## Acceptance criteria

- [ ] Core変更なしでfixture DSLのmethodを追加できる
- [ ] plugin failureでCore/Agentが落ちない
- [ ] untrusted workspaceでruntime pluginを実行しない
- [ ] API version不一致を明確に報告する
- [ ] plugin寄与をgeneration単位で削除・置換できる
- [ ] SDK文書と最小exampleがある
