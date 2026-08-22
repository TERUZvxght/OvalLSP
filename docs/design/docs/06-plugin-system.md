# 06. Plugin System

## 1. 目的

Rails/gem ecosystemのDSLをCoreへハードコードし続ける設計は破綻する。静的解析側とRuntime Agent側の両方に、安定した拡張点を設ける。

Pluginは内部状態を直接変更せず、**Facts、Rules、Queries**を登録する。

## 2. Plugin種類

### Static Plugin

Core Server内で動作する。

用途:

- AST上のDSL認識
- generated declaration作成
- type rule
- completion/definition補強
- diagnostics
- file classification

### Runtime Plugin

Rails Runtime Agent内で動作する。

用途:

- gem固有reflection
- runtime-generated methodの取得
- model metadata
- routes以外のframework registry

### Observation Plugin

Observation Runner内で動作する。初期版では非公開。

## 3〜8. API・Manifest・Discovery — `plugin-sdk.md` を見ること

**この6節にあった仕様は実装されなかった。** 0.2.14 でまとめて削除した。
削除した内容と、実際に Task 018 が実装したものの対応:

| 旧 §  | 書かれていたもの | 実際 |
|---|---|---|
| §3 | YAML の `plugin.yml` | JSON の `plugin-manifest.json`。フィールド名はほぼ同じ。schema は `docs/design/schemas/plugin-manifest.schema.json` |
| §4 | `register_index_enhancer` / `register_call_rule` / `register_type_provider` / `register_definition_provider` / `register_diagnostic_provider` | **5つとも存在しない。** 実際の static API は `register_declarations` / `register_generic_rules` / `register_diagnostics` の3つ(`plugins/static_context.rb`) |
| §5 | `register_snapshot_section` と `register_request` | 前者は実在、後者は存在しない。runtime API は `register_snapshot_section` / `register_reload_hook` の2つ(`plugins/runtime_context.rb`) |
| §6 | `Fact = Data.define(:kind, :subject, :attributes, :location, :evidence)` | この型は存在しない。plugin が渡すのは `Index::Declaration` と `Index::GeneratedMethodFact` で、どちらも他の索引寄与と同じ型である |
| §7 | `Ovallsp::Plugin.require_api!(">= 1.0", "< 2.0")` による semantic versioning | 存在しない。互換性は整数1つの完全一致(`Manifest::CURRENT_PROTOCOL_VERSION`)。失敗隔離は実在し、`plugin-sdk.md` の "Failure isolation" が正確 |
| §8 | workspace → bundle 内 gem → user 設定、の3段 discovery | **実装されていないだけでなく、意図的に逆の決定がされている。** Core は `initializationOptions.pluginManifests` にクライアントが明示列挙した manifest しか読まない — 「自動検出したGemだけを理由にコード実行しない」(`server.rb`)。この節の通りに実装すると、その決定を取り消すことになる |

**正確な記述は [`docs/design/plugin-sdk.md`](../plugin-sdk.md) にある**
— Manifest、static/runtime plugin、loading、failure isolation、動く例。
公開 SDK 文書であり、実装と一緒に書かれている。

**なぜ表として残すのか。** 単に消すと、次に読む人が「§4 の API は
まだ無いから作ろう」と読み違える余地が残る。実装されなかったのではなく
**別の形で実装された**ということが、この6節について知るべきことである。

## 9. Built-in adapters

Rails本体の次のadapterはCore同梱とする。

- routes
- Active Record columns
- associations
- enums
- scopes
- Active Model attributes
- controller/view
- concerns

gem plugin候補:

- AASM
- money-rails
- state_machines
- dry-types/dry-struct
- ActiveAdmin
- Administrate
- GraphQL Ruby

## 10. Pluginテスト契約

各Pluginは次をfixtureで保証する。

- index facts
- type rule
- definition location
- plugin absent時の無影響
- gem version非互換時のgraceful disable
- runtime unavailable時のstatic fallback
