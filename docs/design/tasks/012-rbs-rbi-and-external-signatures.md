# Task 012: RBS・RBI・stdlib/Gem Signature統合

## Goal

Ruby標準ライブラリ、project signature、Gem signatureから型情報を読み込み、ソース推論がGem境界で途切れないようにする。

## Depends on

- Task 011

## In scope

- RBS environment loader
- project `sig/`
- stdlib RBS
- `rbs_collection`またはBundler環境から取得可能なGem RBS
- RBS typeから内部Typeへの変換
- method signatures
- overload候補
- generic type parameters
- block signature
- inheritance/include情報の取り込み
- signature generation/invalidation
-限定的RBI parserまたはRBI→内部宣言変換
- authority/evidence merge

## Out of scope

- Sorbet型検査器互換
- RBS全構文の独自再実装
- RBI DSLの全種類
- signature自動生成
- Steepとのプロセス統合

## Design constraints

- RBS公式Gem/APIを優先して使用する。
- RBS AST objectを長寿命のWorkspaceIndexへ直接保存しない。
- RBS/RBIロード失敗でRuby source解析を停止しない。
- 明示signatureはbody推論より高authorityとする。
- signature source locationをdefinition/hoverに利用可能にする。

## Required interfaces

```ruby
module Rslsp
  module Signatures
    SignatureMethod = Data.define(
      :symbol_id,
      :type_parameters,
      :overloads,
      :location,
      :source_kind,
      :generation
    )

    class Environment
      def load(workspace_root:, bundle_context:); end
      def method_signatures(symbol_id); end
      def ancestors(type_name); end
      def diagnostics; end
      def generation; end
    end
  end
end
```

## Precedence

推奨順:

1. project RBS/RBI
2. Gem/stdlib RBS
3. Rails Runtime deterministic facts
4. source method summary
5. runtime observation

矛盾時は低authority情報を削除せず、explainType用evidenceへ残す。

## Overload selection MVP

- positional arity
- required/optional/rest
- keyword required/optional/rest
- block required/optional
- receiver generic substitution

型の完全なsubtyping selectionは後続改善でよい。複数候補が残る場合は戻り値Unionとする。

## RBI scope

最低限:

- class/module
- `sig { params(...).returns(...) }`
- method declaration
- `T.nilable`
- `T.any`
- `T::Array`, `T::Hash`
- simple generic application

対応不能なRBIはdiagnosticへ記録し、serverを落とさない。

## Tests

- project RBS method
- stdlib Array/Hash
- generic map block
- overload by arity
- keywords
- nilable
- class/module ancestors from RBS
- Gem signature fixture
- broken RBS file
- absent rbs_collection
- minimal RBI
- signature reload after file change
- source/signature conflict evidence

## Acceptance criteria

- [ ] stdlib methodの戻り値がUnknownで途切れない
- [ ] project RBSがbody推論より優先される
- [ ] `Array[User]#map`をRBS signature経由でも解決できる
- [ ] signature definition位置へ移動できる
- [ ] broken/unsupported signatureでCoreが落ちない
- [ ] RBS変更時に関連summaryとquery cacheがinvalidateされる
- [ ] evidenceで型の出所を説明できる
