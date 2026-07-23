# ADR-0003: Runtime Agentは`bin/rails runner`ではなくplain rubyプロセスとして起動する

- Status: Accepted
- Date: 2026-07-24
- Supersedes: ADR-0002の起動コマンド詳細（stdio子プロセスであること自体は継続）

## Context

ADR-0002は「`bin/rails runner`を子プロセスとして起動し、stdin/stdoutでContent-Length framed JSON-RPCを行う」ことを決定していた。しかし`bin/rails runner`はRailsアプリの全initializerを実行し終えてから渡されたスクリプトに制御を渡す。ADR-0002自身が課題として挙げていた「Railsのstdout汚染対策」は、boot.rb側で`$stdout`/`STDOUT`を退避・差し替える形で実装する計画だったが、`bin/rails runner`経由ではその保護コードが実行される前にすべてのinitializerのstdout出力（ログ、gemの起動時メッセージ等）が既に本来のstdoutへ流れてしまい、Content-Length framingを破壊し得る。

## Decision

Core Serverは`bin/rails runner <script>`ではなく、`bundle exec ruby <boot.rb> start <config/environment.rb>`をplain rubyプロセスとして起動する。boot.rb自身が起動直後（Railsを`require`する前）に、（1）実プロトコル用の`STDOUT`を退避、（2）`$stdout`を`$stderr`へ切替、（3）`STDOUT`定数自体も差し替え、（4）その後で対象アプリの`config/environment.rb`を`require`する、という順序でRails起動前にstdout保護を確立する。

`bin/rails`ファイル自体は「Railsアプリである」ことの判定材料（`RailsBootstrap.rails_app?`）としてのみ使われ、実行はされない。

併せて、Core Server自身が`bundle exec`で起動されている場合に`BUNDLE_GEMFILE`環境変数が子プロセスへ継承され、対象アプリ自身の`config/boot.rb`（`ENV["BUNDLE_GEMFILE"] ||= ...`）が誤ってCore側のGemfileを指してしまう問題も同時に対処し、デフォルト起動時は`BUNDLE_GEMFILE`を明示的に子プロセスで解除する。

## Consequences

### Positive

- initializer由来のstdout出力（通常のログ、gemの起動時メッセージ、`STDOUT`定数を直接使うコード）がプロトコルフレーミングを一切破壊しない。実Rails（`spec/integration/real_rails_spec.rb`）で検証済み。
- Core Server自身が`bundle exec`で起動されていても、対象Railsアプリは自分自身のGemfile/Gemfile.lockで正しく解決される。

### Negative

- `bin/rails runner`が提供していた環境変数・working directoryの一部の暗黙的なセットアップ（該当する場合）を、boot.rb側で明示的に用意する必要がある。
- Rails起動失敗時のエラー表示が`bin/rails runner`標準のものと異なる（boot.rb独自のログ経路になる）。

## Rejected alternatives

- `bin/rails runner`のまま、stdout保護をmonkey patchで先取りする: 実行順序を保証する公式なフックがなく、Railsバージョン間で壊れやすい。
- TCP/Unix socketへの切替: ADR-0002が既に却下した理由（port競合、認証、firewall、cleanup）がそのまま当てはまる。
