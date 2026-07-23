# Task 004: Type Modelと局所型推論

## Goal

literal、`Class.new`、代入、条件分岐、nil narrowingを解決し、式位置の型を問い合わせ可能にする。

## In scope

- Type classes
- normalization
- minimal CFG
- local bindings
- assignment constraints
- ternary/if union
- truthy/nil narrowing
- `new`
- explainType internal request

## Out of scope

- method body summaries
- RBS
- blocks/generics
- Rails

## Acceptance criteria

- [ ] `user = User.new` -> User
- [ ] branch -> union
- [ ] `return unless user`後にnil除外
- [ ] safe navigationの戻り値へnil追加
- [ ] analysis timeout時にUnknown
