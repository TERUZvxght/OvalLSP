# 01. Product Requirements

## 1. 背景

Ruby/Railsの開発支援は、構文解析や定数ナビゲーションでは実用的だが、receiver型の追跡、戻り値をまたぐメソッドチェーン、Rails DSLが生成する宣言、DBスキーマ、controller-view間のデータフローで精度が大きく落ちる。

本製品は「すべてのRubyを完全に静的解析する」ことを目標にしない。代わりに、一般的なRubyコードと規約的なRailsコードで発生する編集操作を高精度に処理し、解析不能な部分だけを明示的に不確実として扱う。

## 2. 製品目標

### P0: 日常編集の中心を成立させる

- completion
- hover
- go to definition
- signature help
- diagnostics
- document/workspace symbols

### P1: Rails固有の意味を理解する

- routes
- Active Record columns
- associations
- enums
- attributes
- scopes
- controller actions
- views and partials
- common Rails conventions

### P2: 型情報を漸進的に統合する

- RBS
- RBI
- source inference
- runtime reflection
- optional observed types

### P3: 不確実性を隠さない

結果には必ずprovenanceとconfidenceを保持する。UIでは通常は簡潔に表示し、必要時に根拠を確認できるようにする。

## 3. 想定利用者

- 型注釈を全面導入していないRails開発者
- Ruby LSPより深い補完を求める開発者
- 大規模Railsコードベースの保守担当
- Rails DSLや独自gemの開発者
- AIコーディングエージェントを利用するチーム

## 4. 主要ユースケース

### UC-01: Active Record chain completion

```ruby
order = current_user.company.orders.pending.first
order.
```

`order`を`Order | nil`として提示する。

### UC-02: Route helper completion

```erb
<%= link_to "編集", edit_admin_project_
```

現在のRouteSetから候補、引数、controller actionを提示する。

### UC-03: Controller to view propagation

```ruby
# users_controller.rb
@user = User.find(params[:id])
```

```erb
<!-- show.html.erb -->
<%= @user.
```

`User`のメソッドとDBカラムを補完する。

### UC-04: DSL definition navigation

```ruby
user.company
```

`belongs_to :company`の宣言行へ移動し、必要なら`Company`クラスへ第二候補として移動する。

### UC-05: Partial failure

DB未起動、initializer失敗、migration未適用でも、Ruby構文・定数・局所型推論は動作する。

## 5. 品質目標

### レイテンシ

- keystroke起因completion: p50 50ms以下、p95 150ms以下
- hover/definition: p95 200ms以下
- 保存後の単一ファイル再解析: p95 300ms以下
- Rails snapshot更新: UIをブロックしない

### メモリ

初期目標:

- 10万行規模RailsアプリでCore Server 1.5GB以下
- Runtime AgentはRailsアプリの通常boot相当 + 300MB以下の追加

### 安定性

- Core Serverの障害とRuntime Agentの障害を分離する。
- 1リクエストの例外でプロセスを終了しない。
- 最後に成功したRuntime Snapshotを保持する。
- 古い情報にはstaleフラグを付ける。

## 6. UX原則

- 推定候補を無根拠に確定表示しない。
- 同名メソッドを無差別に大量表示しない。
- Runtime Agentが必要な機能だけを遅延起動できる。
- Workspace Trustが無効な場合はRailsをbootしない。
- 通常操作中にinitializerログを通知として大量表示しない。
- エラーはOutput Channelに集約し、Status Barは状態だけを表示する。

## 7. 機能優先順位

### MVP

1. document synchronization
2. Prism parse
3. workspace symbol index
4. local variable type inference
5. method return summaries
6. completion/hover/definition
7. Runtime Agent lifecycle
8. routes
9. Active Record schema/associations
10. controller-view instance variable propagation

### v0.2

- enums
- scopes
- ActiveModel attributes
- concerns
- partial locals
- RBS loading
- RBI import
- signature help

### v0.3

- find references
- guarded rename
- runtime observation
- plugin SDK
- custom Rails engine support

## 8. 成功指標

- 代表的なRails fixture群で、期待completionのTop-5含有率90%以上
- 明確な定義参照でdefinition precision 95%以上
- Runtime AgentなしでもMVP静的テストの80%以上を通過
- 解析不能時にクラッシュせずUnknownへ縮退する割合100%
- 変更後1秒以内に対象ファイルの結果が更新されること
