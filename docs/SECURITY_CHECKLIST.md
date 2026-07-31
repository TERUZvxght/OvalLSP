# Security Checklist / Threat Model

`docs/RELEASE_CHECKLIST.md`項目9(security checklist)に対応する。個別の
実装(Task 018 plugin isolation, workspace trust, Task 022 Agent protocol
version拒否/ログredaction)は既にコード・テストとして存在するが、それらを
1つの脅威モデルとして横断的に記述した文書がこれまで存在しなかった。

## スコープと前提

OvalLSPはローカル開発マシン上で動くLSPサーバーであり、ネットワークリスナー
は一切持たない(stdin/stdout上のJSON-RPCのみ)。したがって脅威モデルの
主眼は「リモート攻撃者からの侵入」ではなく、以下の3つ:

1. **信頼できないワークスペース**(他人のリポジトリを開く、悪意あるPRを
   チェックアウトする)がCoreプロセス自体やユーザーの開発環境を侵害しな
   いこと。
2. **信頼できないプラグイン**(サードパーティ製、`docs/design/tasks/018-plugin-api-and-sdk.md`)
   がCoreの内部状態やLSPプロトコルそのものを乗っ取れないこと。
3. **ログ・エラーメッセージ経由の秘密情報漏洩**を最小化すること(Coreは
   任意のワークスペース内のRailsアプリの例外テキストをそのままログに
   書くことが多いため)。

このOS上で動くローカルプロセスという性質上、「同一OSユーザーのファイル
書き込み権限を持つ攻撃者」は既に多くの権限を持っている、という前提を
明示的に置く(項目ごとの根拠欄で繰り返し参照する)。

## 脅威モデルと緩和策

### 1. 信頼できないワークスペースを開く

| 脅威 | 緩和策 | 根拠 |
|---|---|---|
| ワークスペースを開いただけでRails Runtime Agent(任意のRailsアプリの`config/environment.rb`をロードし、結果的に任意コードを実行しうる)が自動起動してしまう | Workspace Trustが`true`の場合のみAgentを起動。`initializationOptions.workspaceTrusted`が明示的に`true`でない限り、値の欠如・`false`・フィールド自体の欠如を含め全て起動を拒否するfail-closed設計 | `core/lib/ovallsp/server.rb`の`maybe_start_agent`/`workspace_trusted?` |
| Agentプロセスが、Coreサーバー自身のBundler/Gemfileコンテキストを引き継いでしまう(依存関係の混線) | Agent子プロセスの`BUNDLE_GEMFILE`を明示的にunset | `core/lib/ovallsp/rails_bootstrap.rb` |
| ワークスペースが偽装したAgentプロトコル応答を返し、Coreがそれを信頼してしまう | `agent/hello`ハンドシェイクで`RuntimeAgent::Agent::PROTOCOL_VERSION`の完全一致を要求。不一致時は`:static_only`にフォールバックし子プロセスを終了、以後Agentを信頼しない(Task 022) | `core/lib/ovallsp/agent_process_manager.rb` |
| Agentがクラッシュを繰り返し、無限に再起動しリソースを消費し続ける | `AgentSupervisor`が指数バックオフ+最大試行回数(デフォルト5回)でcrash-loop保護。手動リスタートは`reset`でこのキャップをバイパス可能(意図的なユーザー操作は自動保護でブロックしない) | `core/lib/ovallsp/agent_supervisor.rb`(Task 022) |

### 2. 信頼できないプラグインをロードする

| 脅威 | 緩和策 | 根拠 |
|---|---|---|
| プラグインコードがCoreの生きたLSP stdout transportやAgentのパイプに直接書き込み、プロトコルストリームを汚染/乗っ取る | プラグインは`Process.fork`された別プロセスで実行され、実行前にSTDIN/STDOUT/STDERRを`/dev/null`に付け替え、`ObjectSpace.each_object(::IO)`で到達可能な他の生きたIOを全てclose。結果を返す書き込み側は生のfd番号としてのみ渡す(ObjectSpaceから不可視) | `core/lib/ovallsp/plugins/loader.rb`(`isolate_child_io`) |
| プラグインが実行結果として任意オブジェクト(Procや生のインデックス参照)を親プロセスに返し、コード実行や内部状態の書き換えにつながる | 親子間はMarshal可能なプレーンデータのみ(宣言配列、スナップショットセクション/フックの"名前"のみ、Procそのものは含まない) | `core/lib/ovallsp/plugins/runtime_context.rb`, `static_context.rb` |
| プラグインが`WorkspaceIndex`を直接操作し、Coreの索引状態を汚染する | プラグインには書き込み専用のcollection surfaceのみ渡され、実際の`WorkspaceIndex`オブジェクトは渡さない | `core/lib/ovallsp/plugins/static_context.rb` |
| ランタイムプラグイン(任意コード実行の範囲が広い)が、ワークスペースを信頼していない状態でもロードされてしまう | `load_runtime(manifest_paths, trusted:)`は`trusted:`が真でない限り無条件に空配列を返す(runtime entrypointの中身を一切読まない) | `core/lib/ovallsp/plugins/loader.rb` |
| プラグインマニフェストの互換性のないプロトコルバージョンを暗黙に受理してしまう | `Plugins::CURRENT_PROTOCOL_VERSION`との厳密一致チェック、不一致はロードせずログのみ | `core/lib/ovallsp/plugins/manifest.rb`, `loader.rb`(`safe_load_manifest`) |
| プラグインが無限ループ/ハングし、Core全体をブロックする | デフォルト5秒のタイムアウト、3回連続失敗で自動的に無効化 | `core/lib/ovallsp/plugins/loader.rb`(`DEFAULT_TIMEOUT_SECONDS`, `MAX_CONSECUTIVE_FAILURES`) |

### 3. ログ・例外テキスト経由の秘密情報漏洩

| 脅威 | 緩和策 | 根拠 |
|---|---|---|
| ワークスペース内のRailsアプリの例外メッセージ(DB接続文字列、APIキーを含みうる)がそのままログファイルに書かれる | `Logger#write`は全メッセージを`Redactor.redact`に通す。パイプライン順: Bearerトークン → Basic認証 → URL userinfo(DB接続文字列) → 既知ベンダーキー形式(AWS/Stripe/GitHub/Slack) → ラベル付きcredential(password=/secret=等) → `$HOME`の`~`置換 | `core/lib/ovallsp/redactor.rb`, `core/lib/ovallsp/logger.rb` |
| ログがLSPプロトコル自体を汚染し、クライアント側でJSON-RPCパースが壊れる(秘密漏洩とは別軸だが同じLogger境界の話) | Loggerは「stdoutには絶対に出力しない」という設計制約を明記(stdoutはLSPのJSON-RPCフレームのみが流れる、ログはそれとは別チャンネル) | `core/lib/ovallsp/logger.rb`クラスコメント |
| Redactorが網羅しきれない形式の秘密情報(例: 20文字以上の汎用トークン形状全般)が漏洩する | `redact_generic_tokens`は意図的にデフォルトパイプラインに含めない(コミットSHAやUUID等への誤爆が多いため)。呼び出し側が「このメッセージは信頼できない第三者由来である」と判断できる場合のみ明示的に呼ぶオプトイン設計 | `core/lib/ovallsp/redactor.rb` |

### 4. 観測(Observation)サブシステムによるプライバシー

| 脅威 | 緩和策 | 根拠 |
|---|---|---|
| 実行時の型観測(Task 019)が引数/戻り値の実値やその文字列表現を保存してしまう | `TypeNormalizer`は観測対象の値に対して`#nil?`/`#is_a?`/`.class`/`.name`しか呼ばない。`#inspect`/`#to_s`は一切呼ばない | `core/lib/ovallsp/observation/type_normalizer.rb` |
| 敵対的に`#class`/`#name`をオーバーライドしたオブジェクトが、非String値をJSON応答(`ovallsp/showTypeEvidence`)に紛れ込ませる | `as_nominal_name`が`.name`の戻り値が`String`であることを検証し、そうでなければ`Types::UNKNOWN`に丸める(019-022レビューRound 1で発見・修正) | `core/lib/ovallsp/observation/type_normalizer.rb` |
| 型観測がCoreプロセス自身の中で(本番のLSPサービング処理と同じプロセスで)動いてしまう | `Observation::Collector`はワークスペース自身のテストコマンドに`RUBYOPT`経由で注入される、完全に別のOSプロセス内でのみ動作する。Core自身のプロセスへの注入は設計上スコープ外 | `core/lib/ovallsp/observation/runner.rb` |
| 観測実行中の一時ログに、テストスイート自身の出力(Railsアプリなら日常的にSQL)がそのまま入る | **意図的に未対策(accepted risk)**。`--stdio`モードではfd 1が稼働中のLSPトランスポートであるため、子プロセスの出力をそこへ流すわけにいかない。所有者のみ読み書き可能な権限で作成し、実行終了時に削除する(削除は静かに失敗しうる——クラッシュ・強制終了・読み取り専用の一時ディレクトリでは残る)。OvalLSPはこのログを読みも索引もしない。0.1.12 で「パースキャッシュ以外ディスクには何も書かない」という記述が誤りであると判明し訂正した。記録内容の唯一の正は`vscode/PRIVACY.ja.md` | `core/lib/ovallsp/observation/runner.rb` |

### 5. 永続キャッシュのデシリアライズ

| 脅威 | 緩和策 | 根拠 |
|---|---|---|
| キャッシュファイルが改竄され、`Marshal.load`によって任意コード実行につながる | **意図的に未対策(accepted risk)**。`is_a?(Index::FileSummary)`チェックは`Marshal.load`より後に行われるため、デシリアライズ自体の安全性は保証しない。ただしキャッシュディレクトリは`$XDG_CACHE_HOME`/`~/.cache`配下(このOSユーザーのみ書き込み可能、ワークスペース/リポジトリの外)にあるため、そこに悪意あるエントリを仕込めるレベルの攻撃者は既に同等の任意コード実行能力を持っている(=このデシリアライズを堅牢化しても実質的な権限境界は増えない)。キャッシュルートの置き場所が将来変わる場合は要再検討。なお、このキャッシュは**各メソッドの本文テキストとパラメータのデフォルト式をそのまま保持する**(0.1.12 で明記)——改竄だけでなく読み取りも、ソースコードの一部への読み取りである | `core/lib/ovallsp/cache/store.rb`(class doc), `core/lib/ovallsp/server.rb`(`build_cache_store`) |

## 既知の未対応ギャップ(この文書時点)

- Windows上でのPlugin isolation(`Process.fork`前提)は未検証。WindowsのRubyでは`Process.fork`が使えないため、動作しない可能性が高い(`docs/SUPPORT_MATRIX.md`)。
- `Cache::Store`の`Marshal.load`は上記の通り意図的に未対策(将来キャッシュルートの権限境界が変わった場合は要再検討)。
- Redactorはbest-effort netであり、網羅性を主張するものではない(`core/lib/ovallsp/redactor.rb`冒頭コメント)。

## 更新方針

このチェックリストは実装追跡ドキュメントであり、新しい信頼境界(新しい
プラグインAPI、新しいAgent通信チャネル等)を追加する際は、対応する行を
このファイルに追加すること。
