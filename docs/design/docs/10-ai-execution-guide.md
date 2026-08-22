# 10. AI Execution Guide

> **これは実装前のブリーフです。** 書かれた時点の設計意図の記録であり、
> 現在のコードの説明ではありません。**この文書とコードが食い違う場合、
> 答えはコードです。** 実装済みの挙動を知りたいときは、この文書ではなく
> `core/lib` と、それを pin している spec を読んでください。

## 1. この文書の目的

AI実装エージェントが、設計を勝手に拡張・簡略化して破綻させないための作業規約である。

## 2. AIへ渡す共通前提

各タスクの冒頭に次を添付する。

```text
あなたはRuby Semantic LSPを実装しています。
README.mdとdocs/02-architecture.mdのプロセス境界を変更しないでください。
タスク範囲外の機能を実装しないでください。
公開interfaceを追加・変更する場合は理由と互換性を記録してください。
既存テストを削除・緩和して通さないでください。
Unknownを例外として扱わず、解析不能時はgraceful degradationしてください。
変更後は指定されたテストと全体の高速テストを実行してください。
```

## 3. 1タスクの適正サイズ

1タスクは次を目安にする。

- 変更ファイル 3〜10個
- 新規公開型 0〜3個
- 1つのacceptance criterion
- 1つのfailure path
- 1つのbenchmarkまたは回帰テスト

「型推論を実装する」のような大きな指示を出さない。

## 4. タスク仕様テンプレート

```markdown
# Task: <一意な名前>

## Goal
<完了状態を1段落>

## In scope
- ...

## Out of scope
- ...

## Required interfaces
```ruby
# exact signatures
```

## Behavior
1. ...
2. ...

## Error handling
- ...

## Tests
- ...

## Commands
```bash
bundle exec rspec ...
npm test -- ...
```

## Acceptance criteria
- [ ] ...

## Report format
- changed files
- design choices
- tests run and results
- known limitations
```

## 5. 実装順序

AIへは`tasks/`の番号順に渡す。

並列化可能になるまで単一branchで進める。

### 並列化禁止

- transportとdocument store
- symbol IDとindex
- type modelとsolver
- protocol schemaとAgent server

### 並列化可能

基盤完成後の個別Rails adapter:

- routes
- columns
- associations
- enums

ただし共通Fact型は先に固定する。

## 6. AIによる設計変更の扱い

次に該当する変更は実装前にADRを追加する。

- process boundary変更
- Ruby以外でCoreを実装
- protocol transport変更
- persistent storage導入
- Ruby LSP dependency導入
- plugin API変更
- security/trust model変更

小さな内部リファクタはADR不要。

## 7. コード品質規約

### Ruby

- Ruby 3.3互換構文を基準にする。
- frozen string literal。
- public class/moduleにYARDまたはRBS signature。
- mutable global state禁止。
- IO、clock、process spawningをinjectableにする。
- parser nodeを長期保存せず、必要情報をsummaryへ正規化する。

### TypeScript

- strict mode。
- `any`禁止。外部JSONはunknownからvalidationする。
- VS Code APIをdomain layerへ漏らさない。
- child process lifecycleをDisposableで管理する。

## 8. AIレビュー用チェックリスト

- generationの確認なしに非同期結果をcommitしていないか
- document versionを無視していないか
- runtime情報を確定型として過信していないか
- Railsがないworkspaceでrequireしていないか
- stdoutへdebug出力してprotocolを壊していないか
- Workspace Trustを迂回してcode executionしていないか
- completion requestで全workspace再解析していないか
- pluginがindexを直接mutationしていないか
- exception時にCore全体を終了していないか
- testが実装詳細だけを固定していないか

## 9. 報告フォーマット

AIは各タスク後に次を報告する。

```markdown
## Completed
- ...

## Changed
- path: summary

## Tests
- command: PASS/FAIL

## Architecture impact
- None / ADR-xxxx

## Remaining limitations
- ...
```

## 10. 最初のAIプロンプト

`tasks/001-bootstrap-core-and-vscode.md`をそのまま渡す。完了後、成果物とテスト結果を別AIまたは人間がレビューしてから002へ進む。
