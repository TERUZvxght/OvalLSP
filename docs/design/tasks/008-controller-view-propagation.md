# Task 008: ControllerからViewへのInstance Variable伝播

## Goal

規約的なcontroller actionで代入されたinstance variable型を対応viewのRuby式へ伝播する。

## In scope

- controller/action identification
- conventional view lookup
- instance variable assignment summaries
- ERB Ruby region extraction
- view semantic context
- static render target

## Out of scope

- arbitrary template engines
- dynamic render strings
- helper inclusion completeness
- HTML/CSS language features

## Acceptance criteria

- [ ] `UsersController#show`の`@user`がshow.html.erbでUser
- [ ] `render :edit`先へ伝播
- [ ] action変更時にview contextをinvalidate
- [ ] 対応action不明時はUnknownへ縮退
