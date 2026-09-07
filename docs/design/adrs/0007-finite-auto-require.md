# ADR-0007: 診断に依存しない有限の stdlib require 提案

- Status: Accepted
- Date: 2026-09-07
- Scope: Task 064 P3 / W5a

## Decision

safe モードの診断を増やさず、CodeAction の range にある現在の定数参照から
`JSON => json`、`URI => uri`、`Pathname => pathname` の編集を提案する。
診断の range も入口にできるが、診断の文言を定数 identity の証拠にしない。
編集は明示的な `Add require '…'` quickfix であり、必須・preferred とはしない。

対象は plain Ruby。既存の Rails snapshot は「未ロード」を証明しないため、
Rails はロード済み・Agent 不在・起動中・古い snapshot を含め一律に辞退する。
Gemfile 等の bundle 指定や別 Ruby の選択がある未検証環境も辞退し、Core の
gem が読めることをワークスペースでの利用可能性と取り違えない。
CodeAction 中の Ruby 実行、autoload、gem 探索、新規 RPC は行わない。

定数名は完全一致とし、裸の名前はトップレベルの lexical scope に限定する。
workspace の同名宣言は肯定的な名前解決に使わず、衝突時の辞退にだけ使う。
未完了の cold index、壊れた構文、ERB、動的・条件付き require、autoload は辞退する。
構文で既存 require と file-level の挿入位置を確認し、W5b の
`CodeActions::RequireInsertion.build` に編集生成を委ねる。
編集は現在の文書版を持つ `documentChanges` に入れ、対応 capability がない
client には返さない。LSP/client の根拠は `docs/CLIENT_BEHAVIOUR.md` に記録する。

## Alternatives and limits

unresolved-constant を公開設定で有効にする案は条件1と衝突し、RBS 既知の
定数にも届かない。任意 gem の探索、Rails の load-state RPC、一般的な
lexical/ancestor 解決の新設はこの編集のためには広すぎるため採用しない。
他の定数、nested scope の裸の名前、Bundler/Ruby 選択環境への拡張は行わない。
plain Ruby でも間接ロードの有無は断定しない。

採用パスの実行根拠（Ruby 3.4.10、bundle を継承しないプロセス）:

```console
$ ruby -e 'p [defined?(JSON), defined?(URI), defined?(Pathname)]; require "json"; require "uri"; require "pathname"; p [JSON.generate({a: 1}), URI.parse("https://example.test").host, Pathname.new("a").to_s]'
# => [nil, nil, nil]
# => ["{\"a\":1}", "example.test", "a"]
# ruby 3.4.10
```

同じ対応を Server の実 request → versioned edit 適用 → 隔離 Ruby 実行で検証する。

`BEGIN` はテキスト上の先頭への挿入では解決しないため辞退する:

```console
$ ruby -e 'require "json"; BEGIN { p defined?(JSON) }; p defined?(JSON)'
# => nil
# => "constant"
# ruby 3.4.10
```
