# Task 007: Active Record Model Snapshot

## Goal

Runtime Agentがmodelごとのcolumnsとassociationsを返し、Coreがgenerated method declarationsと型を構築する。

## In scope

- model discovery
- lazy agent/model request
- columns
- belongs_to/has_one/has_many
- optionality
- Relation[T]/CollectionProxy[T]
- basic finder rules
- DB unavailable partial result

## Out of scope

- scopes
- enums
- polymorphic exact resolution
- STI refinement

## Acceptance criteria

- [ ] `User.find` -> User
- [ ] `user.company` -> Company or Company|nil
- [ ] `company.orders` -> CollectionProxy[Order]
- [ ] `orders.first` -> Order|nil
- [ ] DB停止時もmodel load errorでCoreが落ちない
