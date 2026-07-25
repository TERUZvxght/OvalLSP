# ADR-0004: VSIXはCoreのsource/gem payloadを同梱し、bundle-free起動とproject Gemfile統合の両方を持つ

- Status: Accepted
- Date: 2026-07-25

## Context

`vscode/src/serverConfig.ts`のCore Server起動コマンド解決は、これまで`path.join(extensionRoot, '..', 'core', 'bin', 'rslsp')`という monorepo 相対パスをデフォルトにしていた -- `vscode/`と`core/`が兄弟ディレクトリとして両方チェックアウトされていることが前提で、一般ユーザーがMarketplaceからVSIXを導入した場合、`core/`はそもそも存在しないため即座に壊れる (`020-vsix-packaging-and-ruby-environment-resolution.md`の"repository checkoutなしでVSIXからCoreを起動できる"要件に違反)。

Task 020の設計文書はA/B二択を提示している:

- A: CoreをVSIXへ同梱 -- extension versionとCore versionを固定しやすいが、Ruby runtimeはユーザー環境依存のまま
- B: 別Gemとして導入 -- Ruby/Bundlerとの整合は高いが初回セットアップが増える

## Decision

Aを採用しつつ、実行時に二つの起動モードを両立させる:

1. **bundle-free起動 (デフォルト)**: VSIX同梱の`core/`(source一式。gem化はせず、そのまま`ruby core/bin/rslsp --stdio`として起動できる形でパッケージする)を、ワークスペースのRuby実行系（Ruby Resolverが解決したもの）で直接起動する。Core自身の依存(Prism等)はVSIXのビルド時に`core/vendor/bundle`へvendoringし、`bin/rslsp`が起動時にそのvendor pathを`$LOAD_PATH`へ追加する。ワークスペース自身のGemfileには一切触れない -- Core Serverの依存とworkspace/Railsアプリの依存を混同しないという設計文書の要求そのもの。
2. **project Gemfile統合モード (opt-in)**: `rslsp.server.path`を明示的に指定した場合、その実行系（例: workspace内にvendoringされた`rslsp` gemの`bin/rslsp`）が使われる -- 既存の`serverConfig.ts`の override機構をそのまま流用する。

`serverConfig.ts`のデフォルト解決順序:

1. VSIX同梱の`<extensionRoot>/core/bin/rslsp`が存在すればそれを使う(パッケージ後の一般的なケース)
2. 存在しなければ`<extensionRoot>/../core/bin/rslsp`にフォールバックする(`F5`によるローカル開発時、`vscode:prepublish`のcopy-coreステップを経ていない場合)

Runtime AgentはCoreとは別プロセスとして対象Railsアプリ自身のBundler contextで起動される(既存のADR-0003/RailsBootstrapの設計と変更なし) -- Core自身の依存とworkspaceのRails依存が混ざることはない。

## Consequences

### Positive

- 一般ユーザーはVSIXを導入するだけでCore Serverが起動する。`core/`のチェックアウトも`bundle install`も不要。
- Core自身のバージョンとextensionのバージョンが常に一致する(同じVSIXに同梱されているため)。
- `rslsp.server.path`によるoverrideは既存のまま残るため、開発者がローカルの`core/`を指して動作確認する既存のワークフローを壊さない。

### Negative

- パッケージング時に`core/vendor/bundle`へのvendoring手順が必要になり、CIのVSIXビルドが一段複雑になる。
- Core自身の依存関係(gemバージョン)がVSIXのバージョンに固定される -- ユーザー側で個別にCore依存だけ更新することはできない(意図的なトレードオフ: 固定バージョンの再現性を優先)。

## Rejected alternatives

- B (別Gemとして導入のみ): 初回セットアップの摩擦が高く、"repository checkoutなしで起動できる"という受け入れ基準を満たしにくい。
- Aのみ(project Gemfile統合モードを持たない): Core自身の依存とRailsアプリの依存を意図的に分離したいという設計目標には沿うが、Core自身の挙動を手元でoverrideして検証したい開発者のワークフロー(既存の`rslsp.server.path`)を失う。
