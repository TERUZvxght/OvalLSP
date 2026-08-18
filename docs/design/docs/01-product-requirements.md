# 01. Product Requirements

## 0. なぜ作るのか、そして「完成」とは何か

**この節が最上位の参照点です。** 以下のすべての要件、リリース、レビュー、
記録整備は、この節に書かれた目的に資する限りにおいて価値を持ちます。
判断に迷ったとき、あるいは長い作業の途中で目的を見失いかけたときは、
ここへ戻ってください。

### 0.1 開発理由

Ruby/Rails 環境の LSP 機能は、Python など他言語と比べて明らかに弱い。
その結果、**コードの保証がすべて手書きのテストに委ねられている**。
本製品はこの状況の改善・健全化のために存在します。

ここで言う保証とは、まず基本的な原則 — **型のチェック**と
**未定義メソッドの呼び出し**の検出です。この基礎が LSP で担保されていれば、
テストを書く際に適切な範囲へ絞ることができ、Ruby/Rails の慣習を破壊する形
ではなく、**慣習をより強固にするための地盤**として機能します。

つまり本製品の目的はテストを置き換えることではありません。テストが
本来担うべきでない負荷を引き取り、テストを本来の仕事に戻すことです。

### 0.2 「完成」の定義

**1.0.0 でこの構想が実運用可能な水準に達し、導入することで Ruby/Rails
エンジニアの環境に明らかな改善をもたらせるようになること。**

「明らかな改善」が基準です。機能が存在することではなく、日々の開発で
実際に効くこと。

### 0.3 1.0.0 のスコープと、2.x.x へ送るもの

1.0.0 のスコープは **Pylance を参考に、基礎的な地盤を盤石にすること**。

したがって優先順位は次のようになります。

| | 内容 | 版 |
|---|---|---|
| 中核 | 型チェック、未定義メソッド呼び出しの検出、その正確さ（誤検出と見逃しの両方） | 1.0.0 |
| 中核 | 上記が依拠する receiver 型追跡・メソッド解決・Rails DSL 由来の宣言 | 1.0.0 |
| 対象外 | 必須でない使い勝手 — 例: 補完候補が使いやすい順にソートされる | 2.x.x |

### 0.4 精度と出荷のあいだの原則

**誤った答えを返すことは、答えないことより悪い。ただし、正確性を重視しよう
とするあまり 1.0.0 のリリースが際限なく遠のくのは、もっと悪い。**

前半だけでは歯止めになりません。基礎の信頼性が製品価値である以上、一度でも
別の名前空間のクラスのメソッドを補完すれば利用者は以後すべての答えを疑う
——これは真ですが、この一文だけを原則に据えると、あらゆる誤答の修正が
無条件に正当化され、出荷が永遠に来なくなります。**最初から完璧なものを作る
のは実質不可能**であり、そこを認めない設計判断は、それ自体が目的から外れて
います。

したがって誤答は、**その経路をどれだけ踏むか**で扱いを変えます。

| 経路 | 扱い |
|---|---|
| 日常的に踏む経路での誤答 | 1.0.0 のブロッカー。基礎が信用できないなら製品は成立しない |
| 滅多に踏まない経路での誤答 | 記録し、既知の制限として公開し、出荷を止めない |
| どちらか判断できない | **頻度を先に測る。** 見積もりで代用しない |

三行目が実務上いちばん効きます。「実バグである」ことと「直す価値がある」
ことは別で、前者だけで並べると全部が最優先になり、結果として何も出ない。

この原則はメンテナが 0.2.5 の準備中に与えたものです。それ以前に書かれていた
版は前半だけで、後半の歯止めを欠いていました。

### 0.5 `docs/PUBLISHING.md` の 1.0.0 条件との関係

`docs/PUBLISHING.md` は 1.0.0 の条件として、公開する全環境の検証済み保証と、
素の Ruby プロジェクトの保証という **環境軸** の 2 条件を挙げています。
それらは**必要条件であって十分条件ではありません**。0.2 節の能力軸の定義が
満たされていない 1.0.0 は、全環境で動く不十分な製品でしかない。

両者は別の軸であり、どちらも 1.0.0 の要件です。この対応関係は 0.2.5 の
準備中に、`PUBLISHING.md` の条件だけを完成条件として参照していた誤りが
見つかったため明文化されました。

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
