# Ruby Semantic LSP 設計パッケージ

作業名: **Ruby Semantic LSP (OvalLSP)**  
目的: RubyおよびRailsに対して、型注釈を必須とせず、静的解析・Rails実行時情報・任意の実行観測を統合した高精度なVS Code向け言語機能を提供する。

このパッケージは、AI実装エージェントへ順番に渡して開発を開始できる粒度で構成している。

## 最初に読む順序

1. `docs/01-product-requirements.md`
2. `docs/02-architecture.md`
3. `docs/03-semantic-engine.md`
4. `docs/04-runtime-agent.md`
5. `docs/05-protocol.md`
6. `docs/06-plugin-system.md`
7. `docs/07-vscode-extension.md`
8. `docs/08-implementation-plan.md`
9. `docs/09-test-strategy.md`
10. `docs/10-ai-execution-guide.md`
11. `docs/11-risk-register.md`

設計判断は`adrs/`、最初の実装タスクは`tasks/`に分離している。

## 採用する基本方針

- VS Code拡張は薄いTypeScriptクライアントとする。
- LSPサーバー本体はRubyで独立実装する。
- Railsを起動する処理はLSP本体から分離し、ワークスペースごとにRuntime Agentを子プロセスとして起動する。
- VS Codeとの通信は標準LSP 3.17、内部通信はJSON-RPC 2.0互換の独自プロトコルを`Content-Length`フレーミングでstdio上に流す。
- 構文解析はPrismを使用する。
- 型情報はRBS/RBI、静的推論、Rails DSL、実行時reflection、任意の観測結果を統合する。
- 情報は「確定・高確度・推定・観測のみ・不明」の出所付きで保持する。
- Railsプロセスが停止・起動失敗しても、静的解析機能は継続する。
- 初期版ではRuby LSPアドオンやRuby LSP本体への依存を避ける。設計と実装は参考にするが、内部APIの変化に製品基盤を依存させない。

## 初期対応範囲

- Ruby 3.3以上
- Rails 7.1以上
- VS Code
- Bundlerベースの単一Railsアプリ
- CRuby
- `.rb`、`.rake`、`Gemfile`、ERBの基本対応

これは技術的上限ではなく、MVPの互換性範囲を狭めるための判断である。

## MVPの完成条件

次のコードで、補完・Hover・定義ジャンプが一貫して動くこと。

```ruby
user = User.find(params[:id])
user.company.orders.first&.total
```

期待される推論:

```text
User.find                    -> User
User#company                 -> Company
Company#orders               -> ActiveRecord::Relation[Order]
Relation[Order]#first        -> Order | nil
Order#total                  -> BigDecimal またはDB型に対応するRuby型
&.total                      -> BigDecimal | nil
```

加えて次を満たすこと。

- `post_path(post)`を補完できる。
- ルートヘルパーから`config/routes.rb`とcontroller actionへ移動できる。
- `belongs_to :company`から生成される`company`と`company=`を認識できる。
- DBカラムをインスタンスメソッドとして認識できる。
- Rails Agentが落ちた場合、静的機能を維持して状態を表示できる。
- 未保存バッファはRails実行時スナップショットより優先される。

## 非目標

初期段階では次を実装しない。

- 任意のメタプログラミングの完全解決
- 絶対安全なRename
- 全Ruby実装への対応
- 全Railsバージョンへの対応
- 既存Ruby LSPとのプロセス統合
- 本番Railsサーバーへの接続
- 値そのものを保存する実行トレース
- デバッガ
- フォーマッタの独自実装

## 参考にした公式資料

- VS Code Language Server Extension Guide: https://code.visualstudio.com/api/language-extensions/language-server-extension-guide
- Language Server Protocol 3.17: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- Prism: https://ruby.github.io/prism/
- RBS: https://github.com/ruby/rbs
- Ruby LSP: https://github.com/Shopify/ruby-lsp
- Ruby LSP Rails: https://github.com/Shopify/ruby-lsp-rails
- Rails autoloading/reloading: https://guides.rubyonrails.org/autoloading_and_reloading_constants.html
