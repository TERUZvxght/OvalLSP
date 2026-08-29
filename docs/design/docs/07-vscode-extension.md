# 07. VS Code Extension

## 1. 責務

VS Code拡張はLanguage Clientと製品UIのみを担当する。

- Core Server executable探索/導入
- workspace folderごとのprocess起動
- LSP transport
- Workspace Trust確認
- status bar
- commands
- configuration
- output channels
- crash restart policy

意味解析、Rails reflection、ファイルindexをTypeScript側へ実装しない。

## 2. 技術構成

```text
TypeScript
vscode
vscode-languageclient/node
esbuild or tsup
vitest
@vscode/test-electron
```

## 3. Activation

```json
{
  "activationEvents": [
    "onLanguage:ruby",
    "workspaceContains:Gemfile",
    "workspaceContains:**/*.erb"
  ]
}
```

`*.erb` が3つ目にある — ERB しか開いていない workspace でも起動する
必要があるため。この節はかつて2つしか挙げていなかった。

**「実際のCore起動はRuby workspace判定後に行う」という段は削除した。**
`.ruby-version` / `*.gemspec` / `config/application.rb` を見て起動を
決める処理は存在しない。activation は `activationEvents` がすべてで、
その後は `startupGate.ts` が Ruby 実行環境を解決できるかどうかだけを
見る。`.ruby-version` は `rubyResolver.ts` が **どの Ruby を使うか**を
決めるために読むもので、workspace かどうかの判定ではない — 名前が
似ているために取り違えられていた。

## 4. Language Client

workspace folderごとにLanguageClientを生成する。

server options:

```text
command: resolved Ruby command
args: [path/to/ovallsp-core, "--stdio"]
cwd: workspace folder
```

環境解決は段階化する。

1. user configured command
2. mise
3. asdf
4. rbenv
5. chruby
6. system Ruby

MVPでは1とsystem Rubyだけでもよい。環境解決は独立moduleにする。

## 5. Status Bar

`vscode/src/clientPresentation.ts` が唯一の定義。ただし**2つの定数に
分かれている** — 上4つが `STATUS_LABELS`、最後の1つが
`STATUS_ERROR_TEXT` である（同ファイルのコメントも「The four states」と
書いている）:

```text
$(sync~spin) OvalLSP: Indexing
$(check) OvalLSP: Ready (static)
$(check) OvalLSP: Ready (Rails)
$(warning) OvalLSP: Agent unavailable
$(error) OvalLSP: Configuration error
OvalLSP: ${outcome.state}
```

最後の行はテンプレートリテラルであり、固定文字列ではない。
`statusPresentation` が `STATUS_LABELS` に無い state を受け取ったときの
フォールバックで、`clientPresentation.test.ts` の "renders an
unrecognised state by name, not as an error" が固定している。0.2.16 まで
この行はここに無く、`design_doc_drift_spec.rb` の照合もテンプレート
リテラルを見ていなかったので、出荷される拡張が出しうる文字列を
「唯一の定義」と称する節が挙げていなかった（`024.209`）。

クリックで開くのは Quick Pick ではなく Output channel である。

## 6. Commands

`vscode/package.json` の `contributes.commands` が唯一の定義:

```text
ovallsp.restartServer
ovallsp.restartAgent
ovallsp.reindexWorkspace
ovallsp.showLogs
ovallsp.showEnvironmentDiagnostics
ovallsp.showVersionInformation
ovallsp.observation.runTests
ovallsp.observation.clearTypes
ovallsp.observation.showEvidence
```

## 7. Settings

`vscode/package.json` の `contributes.configuration` が唯一の定義:

```jsonc
{
  "ovallsp.enabled": true,
  "ovallsp.ruby.command": null,
  "ovallsp.rubyExecutablePath": null,
  "ovallsp.server.path": null,
  "ovallsp.observation.testCommand": null
}
```

## 8. Workspace Trust

`vscode/package.json` の `capabilities.untrustedWorkspaces` が実体で、
`supported: "limited"` である。

- 静的解析(parse・completion・definition)は untrusted でも動く。
- workspace 自身の Rails/Bundler コードを実行する Runtime Agent は、
  trust 後にしか起動しない。
- **バイナリやコマンドを指すsettingは、trust するまで workspace scope
  から無視される** — `restrictedConfigurations` に
  `ovallsp.rubyExecutablePath` / `ovallsp.ruby.command` /
  `ovallsp.server.path` / `ovallsp.observation.testCommand` の4つが
  列挙されている。これは untrusted な folder が「何が実行されるか」を
  選べないということであり、この節がかつて書いていた内容より強い。

status bar は `Static (untrusted workspace)` にはならない — そのような
文字列は存在しない。§5 の5つのうち Rails 由来でないものが出る。

`vscode/src/test/unit/workspaceTrust.test.ts` が manifest 側を
fail-closed で pin する: 設定が増えたら restricted 宣言か「実行に
影響し得ない」論証のどちらかを強制する。

## 9. Ruby LSPとの共存

初期版は**置換利用**を前提とする。

理由:

- completion候補が重複する。
- definition結果の優先順位をVS Code側で完全制御できない。
- diagnosticsが重複する。
- 2つのRuby indexがCPU/メモリを消費する。

拡張はRuby LSPを自動無効化しない。検出時に設定案内を表示するだけにする。

将来、次の互換モードを検討できる。

- OvalLSPはsemantic機能のみ
- Ruby LSPはformat/test/code lensのみ

ただしMVPの対象外。

## 10. Custom UI

### Evidence

`ovallsp.observation.showEvidence` が実在する。observation で観測した
型の evidence を Output channel へ出す。

**"Explain Type" は存在しない。** かつてこの節にあった
`Expression:` / `Type:` / `Evidence:` の整形出力と、そこに書かれていた
`user.company.orders.first` の推論チェーン例は、実装されなかった仕様
である。近いものは通常の hover で、書式は違う。

### Evidence decorations

常時表示しない。これは実装どおり — decoration は command 実行時だけ。

## 11. Crash policy

**「10秒内最大3回」という自動再起動ポリシーは実装されていない。**
再起動は `vscode-languageclient` 既定の挙動と、利用者が
`OvalLSP: Restart Server` を押すことによる。

実在するのは Core が Agent に対して持つ側のポリシーで、
`AgentProcessManager` の再起動と `mark_unavailable` — Agent が落ちても
Core は静的解析を続け、status bar が `Agent unavailable` になる
(`docs/design/docs/02-architecture.md`)。

## 12. Packaging

**この節は [ADR-0004](../adrs/0004-vsix-bundles-core-with-dual-run-mode.md)
が置き換えた。** かつてここにあった「VSIXにbootstrap Ruby scriptを同梱し、
実体はRubyGemsからversion固定で導入」は、検討の結果**採らなかった**方の
案である。

実際に採ったのは、Coreのsourceとgem payloadをVSIXへ同梱し、bundle-free
起動とproject Gemfile統合の両方を持たせる方式。理由と経緯はADR-0004に
ある。ADRが決定の記録であり、この節はその前段の検討メモだった、という
関係になる。
