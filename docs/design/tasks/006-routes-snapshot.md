# Task 006: Rails Routes Snapshot

## Goal

Runtime Agentが名前付きルートを正規化して返し、Coreが`*_path`/`*_url`のgenerated declarationsを構築する。

## In scope

- agent/snapshot routes section
- RouteFact
- required/optional parts
- source location fallback
- helper declarations
- completion
- definition to routes.rb
- action target metadata

## Tests

- resources
- nested resources
- namespace
- member/collection
- no named route
- route source location unavailable fallback

## Acceptance criteria

- [ ] `post_path`を補完
- [ ] `post_path(post)`のsignature help
- [ ] routes.rbへdefinition
- [ ] PostsController#showをsecondary definitionとして返せる
- [ ] reload後に削除routeが消える
