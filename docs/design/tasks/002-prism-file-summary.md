# Task 002: PrismによるFileSummary生成

## Goal

Ruby documentをPrismでparseし、class/module/method/constantの宣言をFileSummaryとして抽出する。syntax errorがあっても取得可能な宣言を返す。

## In scope

- Prism dependency
- parser service
- source location conversion
- SymbolId
- Declaration
- FileSummary
- document symbols
- unit/golden tests

## Out of scope

- workspace-wide index
- method type inference
- Rails DSL
- references

## Required interfaces

```ruby
module Rslsp
  module Index
    SymbolId = Data.define(:kind, :owner, :name, :discriminator)
    Declaration = Data.define(:symbol_id, :location, :visibility, :parameters, :origin)
    FileSummary = Data.define(:uri, :content_hash, :document_version, :declarations, :diagnostics)
  end

  class ParserService
    def summarize(document); end
  end
end
```

## Behavior

- nested ownerをabsolute nameへ正規化する。
- singleton methodsを区別する。
- class reopenは同じSymbolIdになる。
- parse diagnosticsをLSP rangeへ変換する。
- AST node objectをFileSummaryへ保存しない。

## Acceptance criteria

- [ ] standard class/module/method fixtureが通る
- [ ] `class User; end`の再オープンが同じID
- [ ] syntax error中も直前のmethod declarationを取得
- [ ] document symbolsがhierarchicalに返る
