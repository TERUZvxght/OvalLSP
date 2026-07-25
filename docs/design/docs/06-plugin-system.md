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

## 3. Manifest

```yaml
name: aasm
version: 0.1.0
protocol_version: 1
static_entrypoint: lib/ovallsp/plugins/aasm/static.rb
runtime_entrypoint: lib/ovallsp/plugins/aasm/runtime.rb
requires:
  gems:
    aasm: ">= 5.0"
capabilities:
  - generated_methods
  - runtime_model_metadata
```

## 4. Static Plugin API

```ruby
class Plugin
  def activate(context)
    context.register_index_enhancer(...)
    context.register_call_rule(...)
    context.register_type_provider(...)
    context.register_definition_provider(...)
    context.register_diagnostic_provider(...)
  end

  def deactivate
  end
end
```

### register_index_enhancer

DSL callからDeclaration/Factsを返す。

```ruby
context.register_index_enhancer(
  receiver: "ActiveRecord::Base",
  method: :belongs_to
) do |call, semantic_context|
  # GeneratedDeclaration[]を返す
end
```

### register_call_rule

既知メソッドの型関係を登録する。

```ruby
context.register_call_rule(owner: "ActiveRecord::Relation", method: :first) do |receiver, args|
  receiver.type_argument(0).nilable
end
```

### register_type_provider

symbolまたはexpressionへ追加Type Evidenceを返す。

### register_definition_provider

generated methodからDSL declarationへ移動するために使う。

## 5. Runtime Plugin API

```ruby
class RuntimePlugin
  def activate(registry)
    registry.register_snapshot_section("aasm") { ... }
    registry.register_request("modelStates") { |params| ... }
  end
end
```

Runtime Pluginはstdoutへ書かない。返り値はJSON serializableでなければならない。

## 6. Fact形式

```ruby
Fact = Data.define(
  :kind,
  :subject,
  :attributes,
  :location,
  :evidence
)
```

例:

```ruby
Fact.new(
  kind: :generated_method,
  subject: "::Order#may_pay?",
  attributes: { return_type: "Boolean" },
  location: dsl_location,
  evidence: Evidence.new(source: :plugin, authority: 90, ...)
)
```

Pluginが直接SymbolIndexへ書かないことで、generation rollbackとplugin disableを可能にする。

## 7. 互換性

Plugin APIはsemantic versioningする。

```ruby
Ovallsp::Plugin.require_api!(">= 1.0", "< 2.0")
```

- incompatible pluginは起動失敗させず無効化する。
- plugin例外はplugin IDとrequestを記録する。
- automatic requestで一定時間を超えたpluginをsession中無効化できる。

## 8. Discovery

優先順位:

1. workspace `.ovallsp/plugins/`
2. bundle内gemの`ovallsp/plugin.yml`
3. user設定で明示したpath

Workspace Trustがない場合、workspace pluginとruntime pluginをロードしない。

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
